# CO PRZETESTOWAĆ

Zaznaczaj `[x]`. Jak coś nie działa — dopisz obok, co się stało.
Po testach destrukcji skopiuj Claude'owi z Output linie `[Collapse]` i `[Destr]`.
Jak coś wisi w powietrzu — **nie zatrzymuj Play**, napisz Claude'owi: przeskanuje to na żywo.

**Zanim zaczniesz:** VS Code otwarty (sam włącza Rojo), wtyczka Rojo w Studio połączona.

---

## 🆕 NAJPIERW — ZMIANY Z 30.09-08.10

> **10.10:** potwierdzone ✅ gęsta lawa, mosty + ghost, jeden profil grafiki, drabiny. Eksplozje „raczej git, nie na 100%” — zostają do stałego testu T1-T7 niżej.

### 🌋 Gęsta lawa — ✅ Kacper 10.10: „gęsta lawa git”
- [x] Skok z dachu do głębokiej lawy → nie lecisz na dno, tylko wpadasz kilka studów i powoli opadasz
- [x] W lawie ruszasz się wyraźnie wolniej (jak w miodzie)
- [x] Trzymasz skok → powoli płyniesz w górę
- [x] Przy powierzchni trzymany skok wybija z lawy
- [x] Da się dopłynąć do brzegu (dach, gruz) i wyjść
- [x] Kamera pod powierzchnią → ekran pomarańczowy i rozmyty, nie widać ulicy na dnie
- [x] Opadniesz na dno pod lawą → **zero** obrażeń od upadku i brak wywrotki w locie
- [x] W lawie dalej boli (~7 s do śmierci z pełnym życiem)

### 🌉 Mosty — ✅ Kacper 10.10: „mosty git”
- [x] Celujesz w lawę → podgląd czerwony, klik nic nie robi, most nie znika z ekwipunku
- [x] Most między dwoma dachami leży i da się po nim przejść
- [x] Most wysunięty nad przepaść przechyla się i spada
- [x] Most postawiony na dachu przez murek/gzyms NIE wylatuje w powietrze
- [x] Bomba odrzuca cały most w jednym kawałku (nie rozpada się na deski)

### 🎨 Jeden profil grafiki (08.10) — ✅ Kacper 10.10: „jeden profil grafiki działa” (telefon niesprawdzony)
- [x] Gra startuje bez błędów (nie ma już trybów Ziemniak/Pełny ani klawisza G)
- [x] Wybuch: gruz i cząsteczki „pośrodku” — więcej niż dawny Ziemniak, mniej niż Pełny; meble się rozsypują; gruz leży ~10 s
- [ ] Na telefonie (jeśli możesz) kilka bomb naraz nie zacina

### 🧱 Twarde ruiny (08.10)
- [ ] Zawal kawałek budynku → część (~1/4) małych brył i fragmentów zostaje do końca rundy, twarda, w swoim kształcie — da się na nich stanąć
- [ ] Reszta dalej znika / jest gruzem bez kolizji; serwer nie laguje bardziej niż wcześniej
- [ ] Wklej z Output linie `[Collapse] … twarda ruina` i `kruszenie … małych twardych N`

### 💡 Latarnie i sygnalizatory (08.10)
- [ ] Bomba tuż przy latarni / sygnalizatorze → rozpada się na kawałki, nic nie wisi
- [ ] Bomba kilka studów dalej → przewraca się w całości (nie zostaje pół słupa ani sama głowica w powietrzu)

### ⏱️ Wyjście z Play w Studio (08.10)
- [ ] Stop → Studio odwiesza się w ~1-2 s, nie po 25-30 s; w Output `BindToClose done po X s` z małym X
- [ ] Jeśli dalej wisi: wklej linię `BindToClose: limit … minął — …` (mówi, co trzyma)

### 🚪 Drzwi (08.10)
- [ ] Zawal ścianę/strop przy drzwiach w PupleHotel i SandBuilding → drzwi spadają, nie wiszą
- [ ] Przez drzwi dalej da się przejść

### 🌉 Ghost mostu (08.10) — ✅ Kacper 10.10: „mosty git”
- [x] Celuj mostem w lawę (lawa w tle) → ghost WIDAĆ (pełny, zielony/czerwony, bez prześwitu)
- [x] Wejdź w budowanie, patrząc ukosem na ulicę → most stoi równo z ulicą (kąt co 45°), R obraca co 45°
- [x] Postawiony most stoi dokładnie tam i tak, jak pokazywał ghost

### 🪜 Drabiny (08.10, v3 — tylko łatwiejsze łapanie, reszta jak w zwykłym Robloxie) — ✅ Kacper 10.10: „drabiny sprawdzone”
- [x] Zwykły chód (bez sprintu) prosto na drabinę → łapie
- [x] Podejście lekko ukosem → łapie
- [x] Na górze wyjdź na dach → NIE pcha z powrotem na krawędź
- [x] Zejście po drabinie z góry na ziemię → zero obrażeń od upadku

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
