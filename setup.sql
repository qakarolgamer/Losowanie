-- =====================================================================
--  LOSOWANIE PREZENTÓW – konfiguracja bazy (Supabase → SQL Editor → Run)
--  Przed uruchomieniem zmień HASŁO ORGANIZATORA na dole pliku.
--  Skrypt można uruchomić ponownie – wyczyści wszystko i zacznie od zera.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

drop function if exists public.reveal(text, text);
drop function if exists public.get_info();
drop function if exists public.admin_start(text, jsonb, text, text);
drop function if exists public.admin_status(text);
drop function if exists public.admin_reset_pin(text, text);
drop function if exists public._check_admin(text);
drop table if exists public.participants cascade;
drop table if exists public.settings cascade;

create table public.settings (
  id          int primary key default 1 check (id = 1),
  admin_hash  text not null,
  budget      text not null default '100 zł',
  event_info  text not null default 'Prezenty zostawiamy pod choinką w Wigilię',
  started_at  timestamptz
);

create table public.participants (
  name            text primary key,
  partner         text,                 -- małżonek / partner (nie może go wylosować)
  recipient       text,                 -- komu kupuje prezent
  pin_hash        text,                 -- PIN ustawiony przy pierwszym wejściu
  failed_attempts int  not null default 0,
  claimed_at      timestamptz
);

-- Nikt z zewnątrz nie czyta tabel bezpośrednio. Tylko przez funkcje poniżej.
alter table public.settings     enable row level security;
alter table public.participants enable row level security;
revoke all on public.settings, public.participants from anon, authenticated;

-- ---------------------------------------------------------------------
-- Pomocnicza: sprawdzenie hasła organizatora
-- ---------------------------------------------------------------------
create or replace function public._check_admin(p_pass text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
begin
  if not exists (select 1 from settings where admin_hash = crypt(p_pass, admin_hash)) then
    raise exception 'ZLE_HASLO';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- ORGANIZATOR: start losowania
-- p_people: [{"name":"Anna","partner":"Piotr"}, {"name":"Kasia"}, ...]
-- Generuje JEDEN zamknięty krąg A→B→C→…→A, więc:
--   * nikt nie losuje siebie,
--   * nie ma par wzajemnych (A→B i B→A),
--   * nikt nie losuje swojego małżonka.
-- ---------------------------------------------------------------------
create or replace function public.admin_start(p_pass text, p_people jsonb,
                                              p_budget text, p_event text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_names    text[];
  v_partner  jsonb := '{}'::jsonb;
  v_order    text[];
  v_ok       boolean;
  v_n        int;
  v_try      int := 0;
  p          jsonb;
  i          int;
begin
  perform _check_admin(p_pass);

  select array_agg(trim(x->>'name')) into v_names
  from jsonb_array_elements(p_people) x
  where coalesce(trim(x->>'name'), '') <> '';

  v_n := coalesce(array_length(v_names, 1), 0);
  if v_n < 3 then raise exception 'ZA_MALO_OSOB'; end if;
  if (select count(distinct lower(n)) from unnest(v_names) n) <> v_n then
    raise exception 'POWTORZONE_IMIE';
  end if;

  -- mapa małżeństw (w obie strony)
  for p in select * from jsonb_array_elements(p_people) loop
    if coalesce(trim(p->>'partner'), '') <> '' then
      if not (trim(p->>'partner') = any(v_names)) then
        raise exception 'NIEZNANY_PARTNER: %', p->>'partner';
      end if;
      v_partner := v_partner || jsonb_build_object(trim(p->>'name'), trim(p->>'partner'))
                             || jsonb_build_object(trim(p->>'partner'), trim(p->>'name'));
    end if;
  end loop;

  -- losujemy kolejność w kręgu, aż spełni wszystkie reguły
  loop
    v_try := v_try + 1;
    if v_try > 20000 then raise exception 'NIE_DA_SIE_WYLOSOWAC'; end if;

    select array_agg(n order by random()) into v_order from unnest(v_names) n;

    v_ok := true;
    for i in 1..v_n loop
      if v_partner->>v_order[i] = v_order[(i % v_n) + 1] then
        v_ok := false; exit;
      end if;
    end loop;
    exit when v_ok;
  end loop;

  -- "where true" / "where id = 1": Supabase (pg_safeupdate) odrzuca DELETE/UPDATE bez WHERE
  delete from participants where true;
  insert into participants(name, partner, recipient)
  select v_order[g.k], v_partner->>v_order[g.k], v_order[(g.k % v_n) + 1]
  from generate_series(1, v_n) as g(k);

  update settings set budget = p_budget, event_info = p_event, started_at = now() where id = 1;
end $$;

-- ORGANIZATOR: kto już sprawdził wynik (bez ujawniania wyników)
create or replace function public.admin_status(p_pass text)
returns table(name text, partner text, claimed boolean, locked boolean)
language plpgsql security definer
set search_path = public, extensions as $$
begin
  perform _check_admin(p_pass);
  return query
    select p.name, p.partner, p.pin_hash is not null, p.failed_attempts >= 5
    from participants p order by p.name;
end $$;

-- ORGANIZATOR: reset PIN-u, gdy ktoś zapomniał lub się zablokował
create or replace function public.admin_reset_pin(p_pass text, p_name text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
begin
  perform _check_admin(p_pass);
  update participants set pin_hash = null, failed_attempts = 0, claimed_at = null
  where name = p_name;
end $$;

-- ---------------------------------------------------------------------
-- UCZESTNICY
-- ---------------------------------------------------------------------
create or replace function public.get_info()
returns jsonb language sql security definer
set search_path = public, extensions as $$
  select jsonb_build_object(
    'started',  s.started_at is not null,
    'budget',   s.budget,
    'event',    s.event_info,
    'people',   coalesce((select jsonb_agg(jsonb_build_object(
                    'name', p.name, 'claimed', p.pin_hash is not null) order by p.name)
                  from participants p), '[]'::jsonb))
  from settings s;
$$;

-- Pierwsze wejście: ustawia PIN i zwraca osobę.
-- Kolejne wejście: sprawdza PIN. 5 błędnych prób = blokada (odblokowuje organizator).
create or replace function public.reveal(p_name text, p_pin text)
-- Zwraca {"ok":true,"recipient":"..."} albo {"ok":false,"error":"...","left":N}
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare r participants;
begin
  if coalesce(p_pin, '') !~ '^\d{4}$' then
    return jsonb_build_object('ok', false, 'error', 'PIN_4_CYFRY');
  end if;

  select * into r from participants where name = p_name for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'BRAK_OSOBY'); end if;
  if r.failed_attempts >= 5 then return jsonb_build_object('ok', false, 'error', 'ZABLOKOWANE'); end if;

  if r.pin_hash is null then
    update participants set pin_hash = crypt(p_pin, gen_salt('bf')), claimed_at = now()
    where name = p_name;
    return jsonb_build_object('ok', true, 'recipient', r.recipient, 'first', true);
  end if;

  if r.pin_hash = crypt(p_pin, r.pin_hash) then
    update participants set failed_attempts = 0 where name = p_name;
    return jsonb_build_object('ok', true, 'recipient', r.recipient, 'first', false);
  end if;

  -- błędny PIN: zapisujemy próbę (bez raise, żeby licznik się nie cofnął)
  update participants set failed_attempts = failed_attempts + 1 where name = p_name;
  return jsonb_build_object('ok', false, 'error', 'ZLY_PIN', 'left', 4 - r.failed_attempts);
end $$;

-- uprawnienia: z zewnątrz można tylko wywoływać funkcje publiczne
revoke all on function public._check_admin(text) from public, anon, authenticated;
grant execute on function public.get_info()                         to anon, authenticated;
grant execute on function public.reveal(text, text)                 to anon, authenticated;
grant execute on function public.admin_start(text, jsonb, text, text) to anon, authenticated;
grant execute on function public.admin_status(text)                 to anon, authenticated;
grant execute on function public.admin_reset_pin(text, text)        to anon, authenticated;

-- =====================================================================
--  ⬇⬇⬇  ZMIEŃ HASŁO ORGANIZATORA  ⬇⬇⬇
-- =====================================================================
insert into public.settings(admin_hash)
values (extensions.crypt('ZMIEN-MNIE-swieta2026', extensions.gen_salt('bf')));
