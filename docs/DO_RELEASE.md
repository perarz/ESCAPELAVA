# CO ZOSTAŁO DO RELEASE'U

🎨 = robisz Ty (Studio / decyzja) · 💻 = robi Claude (kod)
Linijki „*dla Claude'a:*” to szczegóły techniczne — nie musisz ich czytać.

---

## ⚠️ WAŻNE — NAJPIERW TO

- [ ] 🎨 Przetestuj wszystko z `docs/TESTY.md`
- [ ] 💻 Popraw to, co wyjdzie z testu, i zrób commity
- [ ] 🎨💻 Destrukcja: stały test (T1-T7) przejdzie 2 razy pod rząd → destrukcja skończona, bez nowych ficzur

---

## 🎨 UI I RZECZY W STUDIO

- [ ] **Slot 3 w hotbarze** (i kolejne) — hak działa z klawisza 3, ale nie widać go w pasku.
  *dla Claude'a:* skopiować `HUD.Hotbar.Slot2` → `Slot3`.
- [ ] **Kamera przy haku w sklepie** — postawić marker obok modelu haka.
  *dla Claude'a:* `WeaponShopScene.ShopCameras`, kod sam go znajdzie.
- [ ] **Przyciski dotykowe na telefon** — wygląd przycisków sprint / push / most (logikę podłącza Claude).
- [ ] **Panel „Ekwipunek"** — tu wybierasz 3 itemy na rundę (decyzja 30.09). Kontrakt nazw i pułapka `ResetOnSpawn` w `docs/ROADMAP.md` → „PLAN: LOADOUT”. Stoisko loadoutu NIE powstaje.
- [ ] **5 dźwięków destrukcji**: wybuch, szkło, uderzenie, trzask, zawalenie — podaj id.
  *dla Claude'a:* `Config.Destruction.FX`.
- [ ] **Kill feed i baner zwycięzcy** — dziś zrobione w kodzie; do przeniesienia do Studio? (decyzja)

---

## 💥 POPRAWKI DESTRUKCJI

- [ ] Poprawki po teście T1-T7 (lewitujące bloki, zaklinowane piętra, zabijanie przez gruz — jeśli jeszcze wystąpią).
  *dla Claude'a:* log `[Collapse]` / `[Destr]`, plan w `docs/DESTRUCTION_PLAN.md` → „Paczka 5 (29.09)”.
- [ ] Budżet fizyki liczy za mało kawałków — poprawić dopiero po teście.
  *dla Claude'a:* M-7 w `docs/REVIEW_2026-09-29.md`.
- [ ] Zapis danych budynków w placu — szybszy start rundy.
  *dla Claude'a:* STRUCTURE_BAKE TRYB 3; zapis zaokrągla do 0,001 i nie sprawdza `MapRevision`.
- [ ] Sprzątanie starej destrukcji (v3) poza budynkami — najpierw sprawdzić, co jej jeszcze używa.

---

## 🎒 LOADOUT I WIĘCEJ ITEMÓW

- [ ] **LOADOUT** — masz dużo itemów, na rundę bierzesz 3. Klawisze 1-3 = Twoje 3 itemy, nic się nie przesuwa. **Plan gotowy, decyzja podjęta 30.09: wybór mieszka w EKWIPUNKU** (nie w sklepie, nie na osobnym stoisku).
  - 🎨 panel „Ekwipunek" w Studio — kontrakt nazw w planie, ⚠️ `ResetOnSpawn = false`
  - 💻 kod (pole w danych gracza, `LoadoutService`, `InventoryController`, blokada equipa po stronie serwera)
  *dla Claude'a:* `docs/ROADMAP.md` → „PLAN: LOADOUT” (koniec pliku). Wchodzi PO paczce 3.
- [ ] **RPG** 💻 (model już stoi na wystawie)
- [ ] **STICKY BOMB** 💻 (model już stoi)
- [ ] **ENERGY DRINK** 💻 (model już stoi)
- [ ] **HAK** 💻 — kliknięcie pod nogi nie może zużywać sztuki za nic.
  *dla Claude'a:* odrzucić przed `consume`, gdy lot < ~3 study.
- [ ] **BOMBA** — działa; do sprawdzenia w teście (NaN, limity).

---

## 📱 TELEFON

- [ ] 💻 Logika przycisków sprint / push / most (wygląd: UI wyżej)
- [ ] 💻 Start gry na wolnym telefonie — dziś może pokazać „0$”, pusty hotbar albo „LOBBY” w trakcie rundy. **Plan gotowy 30.09.**
  *dla Claude'a:* paczka 3 — `docs/REVIEW_2026-09-29.md` → „Plan paczki 3”.

---

## 🛡️ ANTY-CHEAT I BEZPIECZEŃSTWO 💻

- [ ] Łapać teleport i lot w górę → **cofnięcie na ostatnią dobrą pozycję, po kilku razach zabicie, potem kick** (decyzje 30.09). Lot w górę karany dopiero po ~1 s. **Plan gotowy, zero otwartych pytań.**
  *dla Claude'a:* paczka 6, A-3 / B-13 / A-24 — `docs/REVIEW_2026-09-29.md` → „Plan paczki 6”.
- [ ] Jedno sprawdzanie danych od graczy dla wszystkich akcji (dziś 3 różne wersje).
- [ ] Uprawnienia dev po UserId, nie po nicku (🎨 podaj swój UserId).

---

## ⚙️ WYDAJNOŚĆ I STABILNOŚĆ 💻

- [ ] Start rundy przy 40 graczach — postacie ładują się po kolei i zjadają fazę Spawn.
- [ ] Pozycja głowy gracza wysyłana do wszystkich na serwerze — ograniczyć do tych w pobliżu.
- [ ] Błąd w jednym systemie nie może zatrzymać całej gry przy starcie serwera.
- [ ] Odbudowa mapy po rundzie — zmierzyć, czy nie przycina.
  *dla Claude'a:* paczka 7 (A-5, A-11, A-12, A-13) w `docs/REVIEW_2026-09-29.md`.

---

## 🧹 PORZĄDKI W KODZIE 💻

- [ ] Usunąć powtórzony i martwy kod, liczby przenieść do Config (paczka 8).
- [ ] Podzielić 5 największych plików (paczka 9, po porządkach).

---

## ❓ DECYZJE DO PODJĘCIA 🎨

- [ ] Balans lawy na koniec rundy — po teście z prawdziwymi graczami
- [ ] 25$ za zabójstwo bez limitu — dwa konta mogą się farmić. OK?
- [ ] Nazwa fazy lawy na ekranie (Easy / Mid / Hard / Endgame) — tak czy nie?
- [ ] Latarnie świecą pod ulicę — poprawić?
- [ ] Szyby w autach, automatach, przystanku — mają się tłuc?
- [ ] Ile punktów spawnu na 30-50 graczy?

---

## 🚀 TUŻ PRZED PUBLIKACJĄ

- [ ] 💻 Lawa z powrotem na 80 s (5/20/20/20/15), prędkości 0,6 / 1,2 / 2,0 / 3,0
- [ ] 💻 Wyłączyć tryb dev (`Config.Dev.Enabled`, `InfiniteItemsForAll` = false)
- [ ] 💻 Minimum graczy = 2 (`Config.Game.MinPlayers`)
- [ ] 💻 Wyłączyć logi debug (`Structure.Collapse.Debug`, `Destruction.Debug`)
- [ ] 🎨 Maks. graczy na serwerze w ustawieniach miejsca (30-50)
- [ ] 🎨 Test z kilkoma osobami na prawdziwym serwerze, także na telefonach
- [ ] 🎨 Publikacja
