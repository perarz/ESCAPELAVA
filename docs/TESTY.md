# CO PRZETESTOWAĆ

Zaznaczaj `[x]`. Jak coś nie działa — dopisz obok, co się stało.
Po testach destrukcji skopiuj Claude'owi z Output linie `[Collapse]` i `[Destr]`.
Jak coś wisi w powietrzu — **nie zatrzymuj Play**, napisz Claude'owi: przeskanuje to na żywo.

**Zanim zaczniesz:** VS Code otwarty (sam włącza Rojo), wtyczka Rojo w Studio połączona.

---

## 🎒 EKWIPUNEK / LOADOUT (18.10) — NIEPRZETESTOWANE
- [ ] **(19.10) Nowe ikony** (render z gry + czarny obrys) w pasku i w ekwipunku: bomba, most, hak czytelne
- [ ] **(19.10) Wygląd klasyczny**: czarny obrys na wszystkim, pomarańczowy nagłówek, karty itemów w kolorach (x0 szara z zieloną ceną), sloty loadoutu wyglądają jak pasek na dole i stoją na płynącej lawie; karta rośnie pod kursorem, ikona wpada do slotu z odbiciem; model w DETAILS się kręci
- [ ] `I` albo przycisk INVENTORY (lewa strona) → panel spada na miejsce, tło ciemnieje; `I` / X / klik w ciemne tło zamyka. Klik w puste miejsce PANELU go NIE zamyka
- [ ] Najechanie na item → DETAILS: model 3D się kręci, opis, paski POWER / RANGE / MOBILITY dojeżdżają
- [ ] Klik itemu → ikona przelatuje do slotu; klik itemu z zielonym numerkiem → wyjmuje go ze slotu
- [ ] Przeciągnij item na slot; slot na slot (zamiana); slot poza sloty (wyjęcie); prawy klik slotu (wyjęcie)
- [ ] Najedź na item i wciśnij 2 → item w slocie 2, a pasek NIE wyciąga itemu
- [ ] Pasek na dole = sloty loadoutu, nic się nie przestawia, gdy skończą się bomby (slot „x0”, szary, w lobby pulsuje na czerwono; klik = potrząśnięcie)
- [ ] W rundzie panel się otwiera, ale zmiana daje „CHANGE LOADOUT IN LOBBY”
- [ ] Wyjmij hak z loadoutu → klawisz 3 / slot nie wyciąga haka (serwer też nie da)
- [ ] Pełny loadout + kup item spoza niego → sklep: „ADD IT IN INVENTORY”, na przycisku INVENTORY czerwone „!”
- [ ] Ustaw loadout, wyjdź, wejdź → ten sam układ
- [ ] Telefon: tap itemu = DETAILS, drugi tap = do slotu; przeciąganie palcem działa

---

## 📱 START GRY NA WOLNYM TELEFONIE (paczka 3, 18.10) — NIEPRZETESTOWANE
- [ ] Wejdź do gry → ekran ładowania pokazuje „Wczytywanie danych gracza...”, a po zejściu kasa, pasek itemów i czas są już prawidłowe (nie „0$”, nie pusty pasek)
- [ ] Wejdź w **trakcie rundy** → HUD od razu pokazuje ROUND i czas, nie „LOBBY”
- [ ] Kup coś, wyjdź, wejdź → kasa i itemy widać od razu po zejściu ekranu ładowania
- [ ] Studio: Network → wolna sieć (throttling), wejdź → to samo co wyżej
- [ ] Sklep: otwórz → kwota i „za mało kasy” się zgadzają
- [ ] Ruch, sprint, kamera, hak, most, bomba, pchnięcie, drabina działają jak wcześniej (kontrolery startują teraz równolegle)
- [ ] W Output **NIE MA**: `bez ClientReady`, `init padł`, `stan gracza … nie doszedł`. Jeśli są — wklej je Claude'owi

---

## 🎨 NOWE UI Z FIGMY (10.10)
- [ ] **(18.10) Pasek itemów**: wybrany slot NIE nachodzi na sąsiada (też w chwili wyciągnięcia); zmiana 1 → 2 → 3 płynna — stary slot opada razem z wjazdem nowego, ikona buja się lekko, bez szarpnięcia. Rzut bombą: slot nie podskakuje przy każdym rzucie
- [ ] Licznik kasy w lewym dolnym rogu: banknoty + zielona liczba z czarnym cieniem; zmienia się przy zbieraniu/wydawaniu
- [ ] Zbierz kasę z mapy → banknot wyskakuje na środku ekranu i leci do licznika, licznik podskakuje, liczba płynnie rośnie
- [ ] Zabójstwo (25$) → 3 banknoty, wygrana (100$) → 6, jeden po drugim
- [ ] Zakup w sklepie → liczba spada od razu, bez banknotów; zakup w trakcie lotu banknotów nie psuje licznika
- [ ] Wejście do gry → licznik od razu pokazuje stan, bez lecących banknotów
- [ ] Pasek: 3 sloty z IKONAMI (bomba, most, hak), mała angielska nazwa na dole, numer klawisza w lewym górnym rogu (bez kółka), liczba sztuk w prawym; wybrany → biała ramka
- [x] Pasek, ramka (poprawka 10.10): wybierz item → biała ramka; kliknij ten sam slot / klawisz drugi raz (schowaj) → ramka wraca do czarnej. Powtórz kilka razy na każdym slocie i po rzucie bombą — biała nie może zostać na schowanym slocie
- [ ] Czas na górze (Figma, 10.10): napis stanu biały z cieniem, po bokach czarne kreski zwężające się na zewnątrz; czas pod spodem żółto-pomarańczowy. Przejdź LOBBY → GET READY → ROUND → ROUND OVER — kreski zawsze tuż przy napisie, nic nie nachodzi; sprawdź mały i duży ekran (telefon)
- [ ] Licznik czasu przy samej górze ekranu (10.10 wieczór): w oknie Studio, na pełnym ekranie i na telefonie (emulator) zawsze ~4 px od górnej krawędzi, nic go nie zasłania; reszta HUD na miejscu (kasa, pasek, przyciski z boku)
- [ ] Kamera w ruchu (11.10): chodzenie → kamera spokojna (zero bujania); sprint po ziemi → lekkie, płynne drżenie, znika po puszczeniu shifta i w powietrzu; bieg w bok (A/D) → kamera lekko się przechyla w stronę ruchu i wraca; F (push) → krótkie szarpnięcie + mały zoom u popychającego, także przy pudle; nic z tego w ragdollu; kamera dalej nie wchodzi w ściany. Za mocne / za słabe → `Config.Movement.Camera.SprintShake.Amplitude`, `.Lean.MaxDegrees` (1,2° od 11.10), `Config.Push.PushShakeIntensity`
- [ ] Bez GET READY (11.10): lobby odlicza do 0, ekran ściemnia się w ostatniej chwili i od razu startuje runda na mapie (bez 5 s „GET READY”); po rundzie lobby → budynki znowu stoją i walą się normalnie (przebudowa przeniesiona na wejście do lobby); ktoś wychodzi w lobby przy MinPlayers 2 → ekran nie zostaje czarny
- [ ] Przełączanie itemów (11.10): hak → bomba → most → hak w różnej kolejności, także szybko — w ręce zawsze JEDEN przedmiot, w pasku podniesiony tylko jeden slot
- [ ] Runda bez faz (11.10): lawa przez pierwsze ~15 s prawie stoi, potem przyspiesza płynnie bez skoków; po 240 s jest ~120 studów wyżej (zalewa najwyższy dach); w logu serwera brak linii `[GameLoop] phase`; klawisz skip w rundzie kończy rundę
- [ ] Wyciąganie itemu (11.10): klik / klawisz → slot podskakuje, zostaje wyżej i trochę większy, ikona się buja; schowanie → opada; rzut bombą (auto-wyciągnięcie następnej) → slot NIE skacze przy każdym rzucie; zmiana itemu 1 → 2 → slot 1 opada, 2 wjeżdża
- [ ] Licznik czasu (11.10): przy zmianie LOBBY → GET READY → ROUND → ROUND OVER napis wskakuje; ostatnie 10 s lobby / odliczania / rundy → czas czerwony i podskakuje co sekundę, potem wraca do żółtego
- [ ] Zakup w sklepie (11.10): liczba kasy spada płynnie (nie skokiem), licznik krótko się chwieje
- [ ] Pasek staminy (11.10): pobiegnij w małym oknie Studio, na pełnym ekranie i w emulatorze telefonu, z kamerą blisko i daleko — obrys i odstęp wypełnienia od ramki zawsze w tych samych proporcjach (nie cienka nitka na dużym ekranie, nie gruby klocek na telefonie)
- [ ] Balans (10.10 wieczór): push co 2,5 s (pasek odnowienia krótszy niż wcześniej 4 s); bomba w epicentrum zabiera 60% HP (było 50%) — dwie bomby blisko nadal nie muszą zabić, sprawdzić odczucie; lawa buja się mniej (fala o połowę niższa)
- [ ] Zbieranie kasy (11.10): na środku ekranu za banknotami zielony błysk, promienie, dwa pierścienie i migoczące gwiazdki — BEZ iskierek; nic nie zostaje na ekranie po ~1 s; napis kasy: pionowy gradient (góra jaśniejsza), przy dolocie banknotu przejeżdża po nim jasny połysk
- [ ] Kasa (10.10 wieczór): w spoczynku napis równo zielony, bez ruchu; przy zebraniu kasy przez napis raz przejeżdża jasny połysk (przy kilku banknotach naraz — bez szarpania)
- [ ] Licznik czasu: bez poświat, kreski ostre (nie rozmyte) w oknie i na pełnym ekranie
- [ ] Komunikat zabójstwa (Figma, 10.10, potrzebny drugi gracz): zabij kogoś (bomba / zepchnięcie do lawy) → na środku nad połową ekranu wskakuje „YOU KILLED <nick>” z czerwonym KILLED i czaszkami, pod spodem „+25$”; po ~2,5 s gaśnie. Zabity NIE widzi komunikatu, killfeedu w prawym górnym rogu już nie ma. Dwa zabójstwa szybko po sobie → drugi nick, komunikat od nowa, nie znika w połowie. Długi nick nie nachodzi na czaszki
- [ ] Dolot banknotu: z ikony wybuchają zielone iskierki, za ikoną błyska zielona poświata
- [ ] Licznik kasy: inny odcień zieleni, połysk przesuwa się po napisie w kółko; ikona przechyla się przy dolocie banknotu
- [ ] Sklep pokazuje angielskie nazwy (Bomb / Bridge / Grapple)
- [ ] Małe okno / telefon: wszystko się zmniejsza proporcjonalnie, nic nie wychodzi za ekran

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


## 11.10 — kierunkowy chód/sprint R15 (DO TESTU KACPRA)

8 kierunków chodu; sprint tylko W, W+A, W+D; postać patrzy zgodnie z kamerą. Sprawdzić zmianę kierunku i tempa, start/stop pod ścianą, zatrzymanie zużycia staminy podczas Shift+A/D/S, skoki, drabiny, lawę, hak, ragdoll, śmierć/respawn i sklep. Potem wyłączyć `Config.DirectionalLocomotion.Enabled`, ponowić Play: stare animacje i obracanie oraz sprint we wszystkich kierunkach. Nowe animacje to lokalny podgląd Studio, publikacja 11 assetów jeszcze nieukończona. Pełna instrukcja i rollback w `artifacts/animations/directional/README.md`. Sprawdzone bez Play: kompilacja, zgodność kodu ze Studio, 15 stawów, skończone liczby i identyczne końce 11 pętli.


### Kierunkowy ruch R15 — poprawka 11.10, wersja 2

Zestaw rozszerzony z 11 do 14 sekwencji o `Jump`, `Fall`, `Land` w `ReplicatedStorage.DirectionalAnimations` i `Config.DirectionalLocomotion.AnimationIds`. Jump/Land nie są zapętlone. Controller wybiera ruch powietrzny po stanie Humanoida i znaku prędkości Y; lądowanie nie blokuje fizyki ani wejścia. Krok przebudowany na tor stopy z oddzielnym podparciem i uniesieniem. Sprint nadal F/FR/FL, chód 8 kierunków, prędkości 12/20. Backup v1: `ServerStorage.DirectionalAnimations_v1_20261011` i `artifacts/animations/directional/backup_v1/`. Pełne cofnięcie flagą Enabled=false. Nadal StudioPreview (ID=0). Sprawdzono kompilację Edit, zgodność kodu i pętle; Play wyłącznie Kacper: ocenić unoszenie stóp, skok z miejsca/w biegu, spadanie z krawędzi, lądowanie, ragdoll, respawn.


### Kierunkowy ruch R15 — wersja 3, idle (11.10)

`ReplicatedStorage.DirectionalAnimations.Idle` i `Config.DirectionalLocomotion.AnimationIds.Idle`: 4 s, pętla, priorytet Idle. Istniejący kontroler wybiera ją na ziemi przy braku kroku, po zakończeniu lądowania; przejście `IdleBlendTime=0.20`. Faza idle nie przechodzi do chodu. W zestawie 15 klipów; Jump/Fall/Land bez zmian. Ramiona lekko odwiedzione i poruszane bocznie, tułów reaguje na kierunek. Kopia v2: `ServerStorage.DirectionalAnimations_v2_20261011` oraz `artifacts/animations/directional/backup_v2/`. Nadal StudioPreview i cofnięcie Enabled=false. Kacper sprawdza w nowym Play idle, start/stop, trzymanie przedmiotu, ruch boczny i przejście po skoku; agent sprawdził tylko dane, Blender, budowę i kompilację Edit.


Doprecyzowanie v3: Kacper wybrał swobodny idle i wyraźniejszy ruch tułowia. Wgrano mocniejszy przeciwskręt barków/bioder oraz przechył kierunkowy do 11 klipów Walk/Sprint. Idle/Jump/Fall/Land identyczne z wcześniejszą v3. Subtelny wariant zachowany w `backup_v3_subtle/` i `ServerStorage.DirectionalAnimations_v3_subtle_20261011`. Pętle i eksport sprawdzone; ocena ruchu w nowym Play po stronie Kacpra.


### Wycofanie kierunkowych animacji — 11.10

Na prośbę Kacpra usunięto DirectionalLocomotionController, jego zależność/init/bramkę sprintu w MovementController oraz Config.DirectionalLocomotion. Oryginalny Animate w StarterCharacter jest włączony i nie był zmieniany. Poprzednie sekcje o customowym chodzie/idle/skoku są historyczne. Klipy przeniesione z ReplicatedStorage do ServerStorage.DirectionalAnimations_Retired_20261011. Aktywny kierunek: default animacje + wyłącznie custom push pod F.


### Default + custom push R15 — 11.10

Aktywne: oryginalny Animate + `ReplicatedStorage.PushAnimations.Push_TwoHands_R15` (Action, 0.7 s, kontakt0.15, tylko 8 stawów górnej części ciała). `PushController` odtwarza na F, czyści track na respawn i przerywa przy śmierci/ragdollu/końcu rundy. `PushService` rezerwuje cooldown2.5 na próbę, po `Config.Push.Windup=0.15` ponownie sprawdza postać/rundę/zdrowie/ragdoll i wybiera cel. Remote Push bez payloadu; Pushed bez zmian. Koniec rundy unieważnia oczekujące próby. Config.Push.AnimationId=0, AnimationStudioPreview=true — lokalny podgląd, publikacja assetu nadal wymagana. Cofnięcie gestu AnimationEnabled=false, opóźnienia Windup=0. Szczegóły i lista prób Kacpra: `artifacts/animations/push_r15/README.md`. Kompilacja/synchronizacja i czysta logika sprawdzone, Play nieuruchamiany.
