# 🎄 Świąteczne Losowanie

Generator do losowania prezentów (Secret Santa). Każdy sam wchodzi na stronę, wybiera swoje imię, ustawia PIN i dowiaduje się, komu kupuje prezent.

**Reguły, których losowanie nigdy nie łamie:**
- nikt nie losuje siebie,
- nie ma par wzajemnych (A kupuje B i B kupuje A),
- małżonkowie się nie losują,
- każdy kupuje dokładnie jeden prezent i dostaje dokładnie jeden.

Jak to działa: w chwili startu baza układa wszystkich w jeden losowy krąg (A → B → C → … → A) i każdy kupuje prezent kolejnej osobie. Losowanie powtarza się, dopóki obok siebie nie stoją małżonkowie. Wyniki zostają w bazie, a strona pokazuje każdemu tylko jego własny wynik, po podaniu PIN-u.

| Plik | Do czego |
|---|---|
| `index.html` | cała strona (wygląd + logika) |
| `setup.sql` | skrypt bazy danych do wklejenia w Supabase |

---

## Uruchomienie (jednorazowo, ok. 15 min)

### 1. Baza danych: Supabase
1. Załóż darmowe konto na [supabase.com](https://supabase.com) i kliknij **New project**. Region: **Frankfurt** (albo inny w UE). Hasło do bazy zapisz sobie, ale strona go nie potrzebuje.
2. Otwórz plik `setup.sql` tutaj na GitHubie i skopiuj całą zawartość.
3. W Supabase wejdź w **SQL Editor → New query** i wklej skrypt.
4. **Na samym dole skryptu zmień hasło organizatora** `ZMIEN-MNIE-swieta2026` na własne. Zmieniaj je tylko w Supabase, nie w pliku na GitHubie, bo repozytorium jest publiczne.
5. Kliknij **Run**. Powinno się pojawić „Success. No rows returned”.

### 2. Połączenie strony z bazą
1. W Supabase wejdź w **Project Settings → API** (albo **Data API**) i skopiuj:
   - **Project URL** (np. `https://abcdxyz.supabase.co`),
   - klucz **anon / public**.
2. Na GitHubie otwórz `index.html`, kliknij ołówek (✏️ Edit) i na górze pliku wklej:
   ```js
   const SUPABASE_URL      = "https://abcdxyz.supabase.co";
   const SUPABASE_ANON_KEY = "eyJhbGciOi...";
   ```
3. Kliknij **Commit changes**.

> Klucz `anon` może być publiczny. Baza nie pozwala czytać tabel, tylko wywoływać przygotowane funkcje: „pokaż mój wynik po PIN-ie” i funkcje organizatora chronione hasłem.

### 3. Strona: GitHub Pages
1. Repozytorium musi być **publiczne**, bo Pages dla prywatnych repo jest płatne: **Settings → General → Danger Zone → Change visibility → Public**.
2. **Settings → Pages**, w sekcji *Build and deployment* wybierz **Source: Deploy from a branch**, **Branch: `main` / `(root)`** i kliknij **Save**.
3. Po 1–2 minutach strona działa pod adresem:
   **https://qakarolgamer.github.io/Losowanie/**

---

## Jak przeprowadzić losowanie

### Organizator
1. Wejdź na **https://qakarolgamer.github.io/Losowanie/#admin** (albo kliknij „organizator” w stopce strony).
2. Podaj hasło organizatora z kroku 1.4.
3. Wpisz uczestników, **każdego w osobnej linii**, małżeństwa **razem w jednej linii z `&`**:
   ```
   Anna & Piotr
   Kasia & Tomek
   Basia
   Karol
   ```
   Imiona muszą być różne. Przy dwóch Kasiach dopisz inicjał: `Kasia M.`, `Kasia W.`
4. Sprawdź limit (100 zł) i opis („pod choinką w Wigilię”), potem kliknij **🎲 Rozpocznij losowanie**.
5. Wyślij wszystkim **jeden wspólny link**: https://qakarolgamer.github.io/Losowanie/

W panelu widać tylko, **kto już sprawdził** swój wynik. Samych wyników organizator nie widzi.

### Uczestnik
1. Otwiera link i klika swoje imię.
2. Za pierwszym razem **ustawia 4-cyfrowy PIN** i wpisuje go dwa razy.
3. Klika prezent 🎁 i widzi, komu kupuje upominek.
4. Może wrócić w dowolnym momencie, kliknąć swoje imię, podać PIN i zobaczyć wynik jeszcze raz.

### Numer kontrolny (sprawdzenie, czy nikt się nie powtórzył)
Przy losowaniu każdy uczestnik dostaje tajny, losowy numer (np. 47). Nie widzi go ani on sam, ani organizator. Widzi go tylko osoba, która go wylosowała, obok jego imienia.

Po losowaniu każdy podaje numer ze swojego wyniku, np. na grupie. Jeśli numerów jest tyle, ilu uczestników, i żaden się nie powtarza, to każdy kupuje prezent innej osobie. Numer nie zdradza, kto kogo wylosował.

---

## Najczęstsze sytuacje

| Sytuacja | Co zrobić |
|---|---|
| Ktoś zapomniał PIN-u | Organizator: panel `#admin` → **reset PIN** przy tej osobie. Ustawia nowy PIN, a wylosowana osoba zostaje ta sama. |
| Ktoś wpisał 5× zły PIN | Konto się blokuje (chroni przed zgadywaniem). Odblokowuje to samo **reset PIN**. |
| Ktoś kliknął cudze imię | Bez PIN-u nic nie zobaczy. Jeśli pierwszy ustawił komuś PIN, organizator robi reset PIN-u tej osobie. |
| Trzeba dodać lub usunąć osobę | Panel → popraw listę → **Losuj od nowa**. Uwaga: losowanie zaczyna się od zera i każdy musi sprawdzić wynik jeszcze raz. |
| Zapomniałem hasła organizatora | Uruchom ponownie `setup.sql` w Supabase z nowym hasłem. To kasuje losowanie i trzeba wylosować od nowa. |
| Strona pokazuje „Tryb demo” | W `index.html` nie wpisano `SUPABASE_URL` / `SUPABASE_ANON_KEY` (krok 2). |

## Test przed prawdziwym losowaniem
Zrób próbne losowanie na prawdziwych imionach, sprawdź 1–2 osoby, a potem kliknij **Losuj od nowa**. Dopiero po tym wyślij link.

Bez wpisanych kluczy Supabase strona działa w **trybie demo**: dane zapisują się tylko w Twojej przeglądarce, a hasło organizatora to `demo`. To dobry sposób na obejrzenie strony przed konfiguracją.

> Darmowy projekt Supabase usypia się po ok. tygodniu bez ruchu. Jeśli strona przestanie działać, wejdź do panelu Supabase i kliknij **Restore project**.
