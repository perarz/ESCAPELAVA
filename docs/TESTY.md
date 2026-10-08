# CO PRZETESTOWAĆ

Zaznaczaj `[x]`. Jak coś nie działa — dopisz obok, co się stało.
Po testach destrukcji skopiuj Claude'owi z Output linie `[Collapse]` i `[Destr]`.
Jak coś wisi w powietrzu — **nie zatrzymuj Play**, napisz Claude'owi: przeskanuje to na żywo.

**Zanim zaczniesz:** VS Code otwarty (sam włącza Rojo), wtyczka Rojo w Studio połączona.

---

## 🆕 NAJPIERW — ZMIANY Z 30.09-01.10

### 🌋 Gęsta lawa
- [ ] Skok z dachu do głębokiej lawy → nie lecisz na dno, tylko wpadasz kilka studów i powoli opadasz
- [ ] W lawie ruszasz się wyraźnie wolniej (jak w miodzie)
- [ ] Trzymasz skok → powoli płyniesz w górę
- [ ] Przy powierzchni trzymany skok wybija z lawy
- [ ] Da się dopłynąć do brzegu (dach, gruz) i wyjść
- [ ] Kamera pod powierzchnią → ekran pomarańczowy i rozmyty, nie widać ulicy na dnie
- [ ] Opadniesz na dno pod lawą → **zero** obrażeń od upadku i brak wywrotki w locie
- [ ] W lawie dalej boli (~7 s do śmierci z pełnym życiem)

### 🌉 Mosty
- [ ] Celujesz w lawę → podgląd czerwony, klik nic nie robi, most nie znika z ekwipunku
- [ ] Most między dwoma dachami leży i da się po nim przejść
- [ ] Most wysunięty nad przepaść przechyla się i spada
- [ ] Most postawiony na dachu przez murek/gzyms NIE wylatuje w powietrze
- [ ] Bomba odrzuca cały most w jednym kawałku (nie rozpada się na deski)

### 🌉 Ghost mostu (08.10)
- [ ] Celuj mostem w lawę (lawa w tle) → ghost WIDAĆ (pełny, zielony/czerwony, bez prześwitu)
- [ ] Wejdź w budowanie, patrząc ukosem na ulicę → most stoi równo z ulicą (kąt co 45°), R obraca co 45°
- [ ] Postawiony most stoi dokładnie tam i tak, jak pokazywał ghost

### 🪜 Drabiny (08.10, v3 — tylko łatwiejsze łapanie, reszta jak w zwykłym Robloxie)
- [ ] Zwykły chód (bez sprintu) prosto na drabinę → łapie
- [ ] Podejście lekko ukosem → łapie
- [ ] Na górze wyjdź na dach → NIE pcha z powrotem na krawędź
- [ ] Zejście po drabinie z góry na ziemię → zero obrażeń od upadku

### 🌆 Ładowanie mapy i przejście (07.10)
- [ ] Wejście do gry: ekran ładowania może trwać dłużej (cała mapa) — ile sekund? Na telefonie też
- [ ] Koniec odliczania: ekran płynnie ciemnieje, po ~1-2 s rozjaśnia się NA MAPIE, z cieniami i oświetleniem od razu (bez doskakiwania 10-20 s). Jeśli cienie dalej dochodzą → podnieść `Config.RoundTransition.SettleTime`
- [ ] Odliczanie przerwane (za mało graczy) → ekran nie zostaje ciemny
- [ ] Druga i trzecia runda: zburzony budynek wraca cały, nietknięte stoją; w Output linia `[Map] restored X/32 jednostek (...)` — X ≈ tyle, ile ruszyłeś (wkleić ją)
- [ ] Przyciemniony (ranny, nie przecięty) element wraca do normalnego koloru w następnej rundzie

### 💥 Destrukcja — poprawki
- [x] **Kebab**: końcówki filarków i narożny słupek nie wiszą, dach nie stoi na kawałku ściany (Kacper 01.10: „kebab git”)
- [ ] **Zielony**: zwal cały GreenBuilding → skrzynie, paczki i palety z górnych pięter NIE zostają w powietrzu
- [ ] **Kebab — dach**: czy dach potrafi jeszcze stać na jednym kawałku ściany w rogu (sprawdzić przy okazji)
- [ ] **Kolor gruzu (07.10)**: kawałki po wybuchu mają RÓŻNE odcienie szarego (od grafitu do jasnego popiołu), a nie jeden; dalej wyraźnie odróżniają się od mapy

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

Budynki, które jeszcze nigdy nie były grane na nowej destrukcji:
- [ ] PurpleSchool
- [ ] OldBuilding1
- [ ] Construction
- [ ] PupleHotel
- [ ] SandBuilding (poza T7)
- [ ] OldBuilding2

Reszta:
- [x] Tory w budynku spadają z nim, reszta torów zostaje ✅ 01.10
- [ ] Wieszaki i drobne rzeczy przy bombie znikają w chmurze pyłu
- [ ] Meble dalej od bomby odlatują w całości, druga bomba je rozwala
- [ ] TV na szafce i deski rusztowania nie wiszą w powietrzu
- [ ] Auto przy bombie wybucha i płonie
- [ ] Auta tuż obok wybuchają po kolei
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

- [x] Pasek staminy jest dalej po śmierci ✅ 01.10
- [x] Przewrócony bombą (ragdoll) z Shiftem → stamina się nie zużywa ✅ 01.10
- [x] W ragdollu głowa nie wykręca się ✅ 01.10
- [x] Hak w ragdollu nie strzela ✅ 01.10
- [x] Ekran ładowania przy wejściu znika normalnie ✅ 01.10

## 📜 STARE ZALEGŁE

- [x] Obrażenia od upadku — 5 przypadków z 19.09 ✅ 01.10
  *dla Claude'a:* lista przy `FallDamageService` w `docs/ARCHITECTURE.md`
