# CO PRZETESTOWAĆ

Zaznaczaj `[x]`. Jak coś nie działa — dopisz obok, co się stało.
Po testach destrukcji skopiuj Claude'owi z Output linie `[Collapse]` i `[Destr]`.

**Zanim zaczniesz:** VS Code otwarty (sam włącza Rojo), wtyczka Rojo w Studio połączona.

---

## 💥 DESTRUKCJA — STAŁY TEST

Zawsze ta sama kolejność. 2 razy bez błędu pod rząd = destrukcja skończona.

- [ ] **T1** OrangeBuilding, parter — bomby w (−385, −145), potem (−365, −143), potem (−384, −121)
  → budynek kładzie się piętrami, nic nie wisi w powietrzu
- [ ] **T2** OrangeBuilding — bomba na piętrze Y 54, potem cała seria T1
  → gruz z góry spada razem z piętrem niżej
- [ ] **T3** Stań na piętrze Y 54, ktoś robi T1
  → jedziesz z piętrem, gruz NIE rani, na dole zwykły upadek
- [ ] **T4** GreenBuilding, parter koło (−250, −161) — 3 bomby co sekundę
  → wieżowiec składa się piętrami
- [ ] **T5** W trakcie T4 rzuć bombę w spadające piętro
  → tylko lekko je popycha
- [ ] **T6** Po T4 bomba w leżący gruz
  → robi dziurę, gruz lekko drga, nie wystrzeliwuje
- [ ] **T7** SandBuilding, parter koło (−157, 133) — 5 bomb w 3 sekundy
  → bez lagów
- [ ] Kurz przy zawalaniu wygląda dobrze (nie za mało)

**Nie może się stać:** blok wiszący w powietrzu dłużej niż sekundę · znikające piętro · śmierć od gruzu · wystrzelony blok.

## 💥 DESTRUKCJA — RESZTA

- [ ] Wszystkie 10 budynków się zawalają (sprawdzone tylko Orange, Green, CyanOffice)
- [ ] Tory w budynku spadają z nim, reszta torów zostaje
- [ ] Wieszaki i drobne rzeczy przy bombie znikają w chmurze pyłu
- [ ] Meble dalej od bomby odlatują w całości, druga bomba je rozwala
- [ ] TV na szafce i deski rusztowania nie wiszą w powietrzu
- [ ] Auto przy bombie wybucha, płonie, auta obok wybuchają po kolei
- [ ] Gruz leży płasko, nie sterczy

## 🧍 GRACZ I ZAPIS

- [ ] Wyjdź i wejdź → **ta sama postać** (w Studio pierwsze wejście od zera — nowy zapis)
- [ ] Kasa i itemy zostają po wyjściu
- [ ] 2 graczy w Studio, drugi wchodzi w trakcie odliczania → ląduje w lobby jako widz, runda się normalnie kończy
- [ ] Stop Play → w Output: `BindToClose done (zapisów w toku: 0)`

## 🛒 SKLEP I HOTBAR

- [ ] Szybkie klikanie KUP → każdy zakup przechodzi
- [ ] ▶ w sklepie i od razu Q → kamera bez szarpnięcia
- [ ] Trzymasz bombę, giniesz albo kończy się runda → jeden klik znowu ją daje
- [ ] Masz 1 bombę i most, rzucasz bombę → zaznaczenie nie skacze samo na most
- [ ] Rzucasz bomby tak szybko, jak pozwala pasek → każdy rzut wychodzi

## 🏃 RUCH

- [ ] Pasek staminy jest dalej po śmierci
- [ ] Przewrócony bombą (ragdoll) z Shiftem → stamina się nie zużywa, głowa nie wykręca się
- [ ] Hak w ragdollu nie strzela
- [ ] Ekran ładowania przy wejściu znika normalnie

## 📜 STARE ZALEGŁE

- [ ] Obrażenia od upadku — 5 przypadków z 19.09
  *dla Claude'a:* lista przy `FallDamageService` w `docs/ARCHITECTURE.md`
