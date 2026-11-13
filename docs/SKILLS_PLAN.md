# Drzewko umiejętności i rebirth u maga — plan

Stan: **WDROŻONE 09–10.11.2026, NIEPRZETESTOWANE.** Kod i panel są; bieżący stan, co sprawdzone i co otwarte: [STATUS](STATUS.md). Ten plik zostaje jako zapis decyzji i uzasadnień. Tabele liczb niżej Kacper zaakceptował 09.11 — źródłem prawdy są teraz `SkillDefinitions` i `Config.Skills`.

**Rozstrzygnięte przy wdrożeniu (Kacper, 09.11):**
- liczby drzewka i nagrody rebirthów 0–4: zaakceptowane bez zmian, razem z trzema punktami „do potwierdzenia” (śmiertelny upadek zabija, napój i szybkość się sumują, GREED nie działa na pickupy);
- rebirthy 5–10: na razie samo +5% kasy; itemy albo trzeci poziom dopisze się w `SkillDefinitions`;
- liczba rebirthów: kolumna `Rebirths` w tabeli graczy (Tab), bez znaczka przy nicku;
- FORCE: „sam gruz i pył”, bez ognia, huku i wstrząsu;
- TOUGHNESS a przygniecenie gruzem: pytanie bez przedmiotu, przygniecenia nie ma od 29.09.

**Zmiany względem planu:** wibracje i dźwięki idą przez `ShopFx.feedback` (jeden zestaw dla wszystkich paneli) zamiast osobnych pól w `Config.Skills.Fx`; układ pól to sześciokąt „na płasko” (pierwsza odnoga w prawo-górę), bo przy odnodze prosto w dół napis „REBIRTH n” nie miał miejsca; kamera panelu nie zmienia FOV (pisze go co klatkę `MovementController`); `RoundWon` idzie do każdego ocalałego osobno z jego kwotą.

**Cel (Kacper):** dalszy rozwój, żeby gra się nie nudziła i było po co grać. Drzewko daje stałe ulepszenia, a rebirth zaczyna je od nowa w zamian za nowe odnogi, itemy i więcej kasy.

## Decyzje Kacpra (08.11)

| Pytanie | Decyzja |
|---|---|
| Kształt drzewka | Jedno ulepszenie na start (+5% szybkości), od niego odnogi. Każda odnoga ma **2 poziomy**; drugi wymaga pierwszego |
| Czym się płaci | **Hybryda**: poziom I za kasę, poziom II za kasę + wymaganie (kille, przetrwane albo rozegrane rundy) |
| Odnogi | SPEED, STAMINA, LAVA SKIN, TOUGHNESS, GREED, a od 09.11 także **FORCE** (pomysł Kacpra: pchnięciem F lekko rozwalasz ścianę; F już tłucze szyby). Przed pierwszym rebirthem dostępne **tylko dwie**, kolejne odblokowuje rebirth |
| Rebirth | Dostępny po wykupieniu wszystkiego, co jest odblokowane. **Zabiera tylko drzewko**: kasa, itemy i kosmetyki zostają |
| Co daje rebirth | **+5% kasy za każdy rebirth na zawsze**, do tego nowa odnoga albo **nowy item w sklepie** |
| Ile | **Bez limitu** (da się zrobić i 100). Nagrody (odnogi, itemy) do **10. rebirthu**, dalej już tylko +5% kasy za każdy |
| Wygląd | **Kamera na maga + panel**, jak w sklepie. Panel stawia agent przez MCP w stylu HUD, Kacper ocenia |

„+HP” odpadło: obrażenia w grze liczą się jako procent `MaxHealth` (bomba, RPG, upadek, lawa), więc więcej życia nic by nie dało. Zastąpił je TOUGHNESS.

## Dla gracza

W lobby gracz idzie do wieży (około 100 studów od lobby) i naciska E przy magu `TowerMage`. Kamera podjeżdża do maga, obok otwiera się panel z drzewkiem. Kliknięcie pola pokazuje, co daje, ile kosztuje i czego brakuje („SURVIVE 10 ROUNDS 3/10”). Gdy wszystko odblokowane jest wykupione, pojawia się REBIRTH z podsumowaniem: co zniknie (ulepszenia), co zostaje (kasa, itemy, kosmetyki) i co dostanie (procent, odnoga, item).

## Drzewko — propozycja liczb (do akceptacji)

Napisy w grze po angielsku. Liczby trafią do `Config` i można je stroić bez zmian w kodzie.

| Pole | Efekt | Poziom I | Poziom II |
|---|---|---|---|
| **START** (korzeń) | +5% chodu i sprintu | 150$ | — |
| **SPEED** | +2,5% / +2,5% (z korzeniem razem +10%) | 300$ | 800$ + 10 przetrwanych rund |
| **STAMINA** | +15% / +15% staminy | 250$ | 700$ + 15 rozegranych rund |
| **LAVA SKIN** | −10% / −10% obrażeń od lawy | 300$ | 800$ + 20 rozegranych rund |
| **TOUGHNESS** | −10% / −10% obrażeń od wybuchów i upadku | 350$ | 900$ + 10 killi |
| **GREED** | +10% / +10% kasy za przetrwanie i kille | 400$ | 1000$ + 25 killi |
| **FORCE** | I: F wybija małą dziurę w ścianie przed tobą · II: większa dziura i +20% siły pchnięcia | 500$ | 1200$ + 15 killi |

Wymagania liczą się **od ostatniego rebirthu**, inaczej po pierwszym okrążeniu byłyby już spełnione. Statystyki od początku gry zostają osobno, do wyświetlania.

## Rebirthy — propozycja nagród (do akceptacji)

| Rebirth | Co odblokowuje | Kasa na stałe |
|---|---|---|
| 0 (start) | START + odnogi SPEED i STAMINA | — |
| 1 | odnoga **LAVA SKIN** + **nowy item #1** w sklepie | +5% |
| 2 | odnoga **TOUGHNESS** | +10% |
| 3 | odnoga **GREED** + **nowy item #2** | +15% |
| 4 | odnoga **FORCE** | +20% |
| 5–10 | do ustalenia: kolejne itemy, trzeci poziom odnóg albo kosmetyki | +25% … +50% |
| 11 i dalej | nic poza procentem | +5% za każdy |

Bonus z rebirthów i GREED dodają się do siebie. Itemy z rebirthu kupuje się normalnie za kasę; w sklepie przed odblokowaniem widać je z napisem „REBIRTH 1”. Jakie to będą itemy, projektujemy osobno, bo każdy to nowa mechanika (bez rocket jumpa, wycofanego 21.10).

Długość okrążenia przy dzisiejszych nagrodach (przetrwanie 100$, kill 25$, średnio około 60$ na rundę): przed 1. rebirthem około 2 250$, czyli około 40 rund; po trzecim, z pięcioma odnogami, około 5 450$ na okrążenie. Kolejne okrążenia idą szybciej dzięki procentom.

Rozstrzygnięte w planie, do potwierdzenia przy akceptacji:
- **Upadek ze śmiertelnej wysokości dalej zabija.** TOUGHNESS zmniejsza tylko obrażenia poniżej progu śmierci.
- **Napój i szybkość sumują się.**
- **GREED i rebirth nie działają na pickupy** (10$), tylko na przetrwanie i kille.
- **Ryzyko:** przy wielu rebirthach procent do kasy rośnie bez końca (100. rebirth to +500%), więc dla weteranów itemy staną się prawie darmowe. Ocenić po pierwszych tygodniach; ewentualny sufit to jedna liczba w `Config`.
- **Do decyzji:** liczba rebirthów przy nicku i w tabeli graczy jako status widoczny dla innych.

## Wygląd panelu (propozycja 09.11, Kacper: „ma być ładny”, z ui-resources.com)

- Kamera jak w sklepie: płynny przejazd do maga, lekko z boku; panel po prawej, mag po lewej.
- **Tło drzewka:** ciemny panel ze studsami jak sklep, a za drzewkiem duży, powoli obracający się **magiczny krąg** — pięciokąt z węzłami (ui-resources: „Circle effect”, Kek, `kek_circle_magic_1`), barwiony na fiolet maga.
- **Pola:** okrągłe sloty jak w pasku (czarny obrys, ikona odnogi w środku), każda odnoga w swoim kolorze: SPEED żółty, STAMINA zielony, LAVA SKIN pomarańczowy, TOUGHNESS stalowoniebieski, GREED złoty, FORCE fioletowy.
- **Stany pól:** zablokowane szare z kłódką; dostępne ze **świecącym pierścieniem**, który oddycha w kolorze odnogi (`kek_circle_3`); kupione złote z miękką poświatą (`kek_circle_5`). Wybrane pole obiega **wirujący łuk** (`kek_circle_6`).
- **Połączenia:** grube linie z czarnym obrysem, po zakupie wypełniają się płynącą lawą (tekstura lawy z gry). Zamknięte odnogi szare z napisem „REBIRTH 2”, żeby było wiadomo, na co się gra.
- **Zakup:** wskok pola, rozbłysk promieni (jak `StarterGui.Cosmetics.Root.Body.Unlocked.Rays` przy odblokowaniu kosmetyku) i gwiazdki (`SparkleBurst.play`, jak `ShopUI.Panel.BuySparkles`). Pod drzewkiem szczegóły: nazwa, efekt, cena, postęp wymagania i zielony UNLOCK jak BUY. Bez kasy albo wymagania przycisk jest szary i mówi, czego brakuje.
- **REBIRTH:** duży przycisk w kolorach lawy z **obramowaniem z błyskawic** („Lightning Border Effect”) i obracającymi się promieniami, gdy jest dostępny; okno potwierdzenia, potem wybuch efektu przy magu i nowe drzewko.
- Mikroanimacje opisane niżej. Rzeczy drugorzędne małe (UI_RULES 9).
- **Ikony odnóg (decyzja 09.11):** game-icons.net, białe kształty z czarnym obrysem jak w HUD, barwione kolorem odnogi: START różdżka, SPEED biegacz, STAMINA płuca, LAVA SKIN tarcza z ogniem, TOUGHNESS hełm, GREED monety, FORCE pięść, REBIRTH strzałki w kółko, kłódka dla zablokowanych. **Licencja CC BY 3.0: w opisie gry musi być podpis „Icons: Lorc, Delapouite — game-icons.net, CC BY 3.0”**, zanim drzewko trafi do wydania.
- **Wgrane 09.11 (zgoda Kacpra):** 4 kręgi Keka i obramowanie z błyskawic z ui-resources.com (licencja niepodana; obramowanie ma na stronie autora „???”, jako jedyne bez podpisu) oraz 9 ikon. ID, źródła i autorzy: `artifacts/ui-effects/ASSETS.md` → „Drzewko umiejętności”.

### Mikroanimacje (09.11, prośba Kacpra)

Zasada: rusza się to, co da się kliknąć albo co właśnie się zmieniło, a zablokowane pola stoją. Styl jak w sklepie, bez udziwnień. Animacja zakupu rusza dopiero po odpowiedzi serwera, żeby nie pokazać zakupu, który serwer odrzuci.

- **Otwarcie:** panel wjeżdża z lekkim przeskokiem jak sklep, pola wskakują kaskadą od korzenia w głąb odnóg, a linie „rysują się” za nimi. Zamknięcie szybsze, w odwrotnej kolejności.
- **Spoczynek:** krąg za drzewkiem powoli się obraca, pierścienie dostępnych pól oddychają, poświata kupionych lekko pulsuje, a lawa w połączeniach płynie. Gdy rebirth jest dostępny, przycisk co kilka sekund pulsuje, a błyskawice migają.
- **Najechanie i klik:** pole rośnie o 10%, a ikona lekko się przechyla; po kliknięciu pole się wciska i sprężyście odbija. Na telefonie bez najechania.
- **Wybór pola:** wirujący łuk wskakuje na pole. W szczegółach nazwa wjeżdża z boku jak w sklepie, pasek wymagania napełnia się od zera, a licznik „3/10” odlicza w górę.
- **Czekanie na serwer:** UNLOCK na chwilę zamienia się w trzy skaczące kropki (zwykle niezauważalne).
- **Zakup:** pole zgniata się i wyskakuje, przechodząc z szarego w kolor odnogi, do tego promienie i gwiazdki. Lawa wpływa w linię, kłódka następnego pola pęka i spada, a jego pierścień się zapala. Wibracja jak przy BUY.
- **Brak kasy albo wymagania:** UNLOCK trzęsie się na boki, a to, czego brakuje (cena albo licznik), miga na czerwono. Wibracja jak przy błędzie w sklepie.
- **Rebirth:** okno potwierdzenia wskakuje na przyciemnionym tle. Po potwierdzeniu pola gasną po kolei od końców odnóg do korzenia, lawa cofa się z linii, krąg przyspiesza i rozbłyskuje, przy magu wybucha efekt, a licznik rebirthów podskakuje o 1. Potem nowa odnoga się odsłania (kłódka pęka, linie się rysują) i wyskakuje napis „NEW BRANCH” albo „NEW ITEM IN SHOP” oraz „+5% CASH”.

Do implementacji: moduł `SkillTreeFx` na wzór `ShopFx`, liczby w `Config.Skills.Fx`, dźwięki jako puste pola do uzupełnienia przez Kacpra. Lekcje ze sklepu: jedna `UIScale` na element, pozycje liczone w kodzie, najechanie ignorowane na dotyku, stan wciśnięcia czyszczony globalnie. Animacje spoczynku chodzą tylko przy otwartym panelu.

## Architektura

**Nowe pliki**
- `src/shared/Modules/SkillDefinitions.luau` — jedyna lista pól (id, odnoga, poziom, wymagane pole, cena, wymaganie `{ stat, count }`, efekt `{ kind, value }`, napisy) i tabela nagród rebirthów (który rebirth odblokowuje odnogę albo item). Czytają ją serwer, panel i sklep.
- `src/server/Services/StatsService.luau` — właściciel statystyk `kills`, `survived`, `played`, w dwóch wersjach: od początku gry i od ostatniego rebirthu. Nalicza z istniejących miejsc: kill zaliczony w `KillService.processDeath`, ocaleni z `RewardsService`, uczestnicy rundy z `PlayerService` (bez pomijających i dołączających).
- `src/server/Services/SkillService.luau` — właściciel drzewka i rebirthów: zakup pola, rebirth, suma bonusów `getBonus(player, kind)` i mnożnik kasy.
- `src/client/Controllers/SkillTreeController.luau` — prompt, kamera, panel, rebirth i animacje.
- `StarterGui.SkillTree` — panel stawiany przez MCP po akceptacji wyglądu.

**Dane gracza** (`PlayerDataService`, migracja dopisująca pola jak przy kosmetykach): `skills = { nodes = { [nodeId] = true }, rebirths = 0 }`, `stats = { total = {…}, cycle = {…} }`.

**Komunikacja** (wpisy w `Remotes.luau`)
- `UnlockSkill(nodeId: string)` i `Rebirth()` — klient → serwer.
- `SkillResult(success: boolean, action: string, id: string?, reason: string?)` — wynik.
- `SkillsChanged(owned: {string}, rebirths: number, stats: {...})` — przy wczytaniu, zakupie, rebirthie i zmianie statystyk; stan startowy przez `sendInitialState`.
- Bonusy ruchu dla klienta jako atrybuty gracza `SkillSpeed` i `SkillStamina`, a liczba rebirthów jako `Rebirths`, ustawiane tylko przez serwer.

**Zakup i rebirth — walidacja na serwerze:** typ i istnienie pola, odnoga odblokowana na tym rebirthie, jeszcze niekupione, kupione pole poprzednie, spełnione wymaganie, dość kasy, odległość do `TowerMage` (`Config.Skills.InteractDistance`), dane gotowe do zapisu, limit zapytań. Rebirth tylko przy komplecie odblokowanych pól. Każda zmiana w jednym atomowym zapisie (kasa i pole albo reset i licznik), jak zakup kosmetyku. Log z powodem `skill_<id>` i `rebirth_<n>`.

**Gdzie działa efekt**
- Szybkość: `MovementController` mnoży chód i sprint; `AntiCheatService.maxAllowedSpeed` mnoży limit tym samym bonusem z serwera, inaczej szybszy gracz dostawałby kary.
- Stamina: `MovementController`, maksymalna stamina.
- Lawa: `LavaService`, obrażenia na klatkę.
- Wybuchy i upadek: `BombService.applyDamageAndKnockback` (bomba, RPG, C4, beczki, auta) i `FallDamageService`, z wyjątkiem śmiertelnego upadku.
- Kasa: mnożnik GREED + rebirthy w `RewardsService` (przetrwanie) i `KillService` (kill).
- FORCE: `PushService` po pchnięciu szuka ściany przed graczem promieniem, tak jak dziś szyby (`glassAhead`), i wybija w niej małą dziurę przez `DestructionService.detonate` z małymi parametrami (cały potok gruzu i odbudowy jak przy bombie; szczegóły w briefie na końcu). Tylko w rundzie i tylko na mapie (lobby i `Locked` nietykalne); cooldown pchnięcia (2,5 s) ogranicza spam. Rozmiar dziury i obrażenia ściany w `Config`. `PushService` zmienia teraz drugi agent, więc ta część po jego commicie.
- Itemy z rebirthu: pole `requiresRebirth` w `ItemDefinitions`; `ShopService` odrzuca zakup przed czasem, sklep pokazuje kłódkę.

**Przypadki brzegowe:** wejście w trakcie rundy (stan przez `sendInitialState`), wyjście w trakcie zakupu albo rebirthu (zapis atomowy), DataStore niedostępny (odrzucone „data_not_ready”, gra bez zmian), zakup w trakcie rundy przez pomijającego albo martwego (bonus od razu, anty-cheat czyta ten sam stan), rebirth w trakcie rundy (bonusy znikają od razu, dlatego tylko przy magu, czyli poza mapą), spam kliknięć (limit, przycisk zablokowany do wyniku), klient podmienia atrybut (serwer liczy limity i obrażenia ze swojego stanu), item z rebirthu w loadoucie i inventory zostaje po kolejnym rebirthie.

## Etapy

1. Akceptacja liczb i nagród przez Kacpra (ten plik).
2. Po skończeniu pracy drugiego agenta: `SkillDefinitions`, `StatsService`, `SkillService` z rebirthem, zapis, Remote'y, anty-cheat i mnożnik kasy.
3. Efekty pięciu odnóg.
4. Panel, kamera, mikroanimacje i okno rebirthu przy magu przez MCP, zrzut do oceny Kacpra.
5. Itemy z rebirthu: blokada w sklepie od razu, same itemy według osobnych planów.
6. Lista testów w TESTY i test Kacpra w Play; wpisy w STATUS, ARCHITECTURE i STUDIO_CONTRACT.

## Brief dla agenta wykonawczego (stan kodu i placu z 09.11)

Ta sekcja zbiera wszystko, czego potrzeba do wdrożenia bez szukania od zera. Numery linii są z 09.11 i mogą się przesunąć, więc szukaj po nazwie funkcji.

### 1. Zanim napiszesz linijkę

1. **Przeczytaj:** `docs/CLAUDE.md` (twarde zasady), górny wpis w `docs/STATUS.md`, cały ten plik, w `docs/ARCHITECTURE.md` opisy plików, które zmieniasz (lista w punkcie 3), `docs/UI_RULES.md` przed panelem i `docs/STUDIO_CONTRACT.md` przed dotknięciem wieży albo `StarterGui`.
2. **Sprawdź, czy drugi agent skończył:** `git status` i `git log`. 09.11 miał niescommitowane zmiany w `Config`, `Remotes`, `ItemDefinitions`, `Utils`, `MovementController`, `PlayerService`, `PushService`, `DestructionService` i obu plikach `init`. Jeśli nadal są cudze i niescommitowane, zapytaj Kacpra, zanim je ruszysz.
3. **Zadaj Kacprowi pytania z otwartych decyzji** (AskUserQuestion, konkretne A/B): akceptacja liczb z tabel wyżej, nagrody rebirthów 5–10, rebirthy przy nicku albo w tabeli graczy. Do tego dwie rzeczy, których plan nie rozstrzyga:
   - czy TOUGHNESS zmniejsza też przygniecenie gruzem;
   - jak ma wyglądać wybicie ściany przez FORCE, bo `DestructionService.detonate` odpala pełny efekt wybuchu (punkt 3).

   Nie wybieraj za niego.
4. **Na start sesji:** `ps aux | grep rojo`. Czy kod dojechał do Studio, sprawdzaj przez `.Source` i sumę, nigdy przez `require` (lekcja 5, zasada 14).

### 2. Twarde zasady, które tu najłatwiej złamać

- **Nie uruchamiaj Play i nie testuj przez MCP.** W Edit wolno tylko obserwować: odczyty, pomiary i sprawdzenie, czy kod dojechał. Test robi Kacper z twojej listy.
- **Zrzuty Studio:** zgoda Kacpra jest tylko na pracę nad wyglądem, i nigdy w trakcie jego Play.
  - Przed zrzutem panelu ustaw `HudScale` na `ScreenGui.AbsoluteSize.Y / Config.UI.ReferenceHeight`, po zrzucie przywróć.
  - Klony do podglądu usuwaj (lekcja 16).
- **Gdzie co trzymać:**
  - Wszystkie liczby, ID zasobów i napisy idą do `Config.Skills` albo `SkillDefinitions`. Kod nie odwołuje się do `artifacts/`.
  - Każdy nowy Remote trafia do `REMOTE_NAMES` w `Remotes.luau` z komentarzem payloadu.
- **Serwer liczy wszystko ze swojego stanu.** Atrybuty gracza służą tylko do wyświetlania i ruchu po stronie klienta. Limit anty-cheatu i obrażenia czytają `SkillService`, nie atrybut.
- **Każda zmiana kasy idzie przez `CashService`** z powodem `skill_<id>` albo `rebirth_<n>`, bo to zapewnia log z czasem.
- **Commit tylko na prośbę.** Repo jest publiczne: nie dodawać `artifacts/`, `marketing/`, `output/`, `generated_images/`, `tests/`, `.codex/`, `AGENTS.md`, `docs/AGENTS.md`.
- **Pliki i Rojo:** nowe pliki w istniejących folderach (`Services`, `Controllers`, `Modules`) dojeżdżają bez restartu `rojo serve`. Nowe serwisy i kontrolery trzeba dopisać do `server/init.server.luau` i `client/init.client.luau`.

### 3. Gotowe klocki w kodzie

| Potrzeba | Gdzie i jak |
|---|---|
| Zakup pola | `CashService.purchase(player, amount, reason, prepare)`: kasa i zmiana stanu w jednej podmianie danych. `prepare` nie może yieldować ani zmieniać wejścia, tylko zwraca kopię (`table.clone`). Kwota musi być liczbą całkowitą. |
| Wzór całego przepływu zakupu | `CosmeticsService.buy`: typ i długość id, `lobbyOnly` (LOBBY albo pomijający rundę, `isWritable`, żywa postać), odległość do NPC, `allowRequest` (limit na sekundę), `reply` (najpierw `replicateTo`, potem wynik z bezpiecznym id). Prompt: `ensurePrompt` tworzy `ProximityPrompt` w kodzie. |
| Rebirth (bez kasy) | Jedna mutacja `PlayerDataService.update`: zeruje `nodes` i `cycle`, podbija `rebirths`. Wcześniej `isWritable`. Mutator dostaje żywą tabelę i nie może yieldować. Log ręcznie, z tym samym formatem co `CashService`. |
| Nowe pola w zapisie | `PlayerDataService.defaultData` i `migrateSchema` dopisują `skills` i `stats` tak jak `cosmetics` (bez nowej przestrzeni DataStore). Czyszczenie przy wczytaniu jak w `CosmeticsService.init`: subskrypcja `loaded` i `loaded_default`. |
| Stan startowy dla klienta | `sendInitialState` w `server/init.server.luau` (po `ClientReady`) i `replicateTo` przy wczytaniu danych. Zasada 9: RemoteEvent nie buforuje. |
| Statystyka: kill | `KillService.processDeath`, zaraz przy `CashService.add(attacker, …)`. |
| Statystyka: przetrwana runda | `RewardsService.onRoundEnded`: snapshot `PlayerService.getAliveList()`. |
| Statystyka: rozegrana runda | `PlayerService.sendEveryoneToRound` buduje `roundPlayers` (bez dołączających i pomijających). Dodaj publiczny getter tylko do odczytu, nie drugą listę. To plik drugiego agenta. |
| Mnożnik kasy | `Config.Rewards.Win` w `RewardsService` i `Config.Rewards.Kill` w `KillService`, pomnożone przez `SkillService.cashMultiplier(player)` i zaokrąglone. `CashPickupService` bez mnożnika. Komunikaty (`RoundWon`, `PlayerKilled`) pokazują kwotę po mnożniku. |
| Szybkość (klient) | `MovementController` około linii 787: `walk` i `sprint` z `Config` plus bonus napoju. Pomnożyć przez bonus z atrybutu `SkillSpeed`. |
| Stamina (klient) | `MovementController`: `CFG_STAM.Max` jest użyte w kilku miejscach (start, pasek, respawn, drenaż i regeneracja). Zastąp je jedną funkcją `maxStamina()`. |
| Limit anty-cheatu | `AntiCheatService.maxAllowedSpeed` około linii 57: `SprintSpeed + SpeedTolerance` (plus napój). Mnożyć bonusem z `SkillService`, inaczej szybszy gracz dostanie karę. |
| Lawa | `LavaService.damageSubmerged`, linia około 186: `hum:TakeDamage(hum.MaxHealth / seconds * dt)` razy (1 − LAVA SKIN). |
| Wybuchy | `BombService.applyDamageAndKnockback`, linia około 286 (bomba, RPG, C4, beczki, auta) razy (1 − TOUGHNESS). |
| Upadek | `FallDamageService.applyFall`, linia około 162: przy `t < 1` razy (1 − TOUGHNESS); przy `t = 1` bez zmian, bo śmiertelny upadek zostaje. |
| FORCE | `PushService.resolvePush` już szuka szyby promieniem (`glassAhead`). Ścianę wybijać przez `DestructionService.detonate(center, params, pusher)` w `xpcall`, jak w `BombService` (około linii 321), z małymi `DestructionParams` w `Config` (`radius`, `damage`, `impulse`). Opis niżej. |
| Itemy z rebirthu | `ItemDefinitions` (pole `requiresRebirth`), `ShopService` (odrzucenie zakupu), `ShopController.buildEntries` (kłódka i „REBIRTH 1”). |
| Kamera i panel (klient) | Wzór `ShopController`: `setFrozen`, `focusCamera` (tween), `startCameraLoop` (jeden zapis kamery na klatkę), `closeShop` / `openShop`. Animacje: wzór `ShopFx`. Gwiazdki: `SparkleBurst.play`. |
| Inne otwarte panele | Sklep: `ShopController.onOpenChanged` / `isOpen`. Kosmetyki: atrybut gracza `CosmeticsOpen`. Czytają je `InventoryController`, `RoundSkipController`, `SpectateController` i `CosmeticsController`. Drzewko musi dać to samo (np. atrybut `SkillTreeOpen`) i być wpięte w te miejsca, inaczej przyciski HUD zostaną na panelu albo otworzą się dwa panele naraz. |

Szczegóły do FORCE:
- `detonate` sam pomija chronione części (`Destructible.isProtected`: `Locked`, `Map.Locked`) i rusza tylko geometrię mapy (`isDestructible`), więc lobby i wieża są bezpieczne.
- Graczy nie rani, bo obrażenia graczy liczy `BombService`.
- Odpala jednak efekt wybuchu (BlastFX), więc wygląd ustal z Kacprem przed wdrożeniem.
- Uwaga przy gruzie: lokalny gruz klienta nie może mieć kolizji ani łapać promieni (lekcja 10).

### 4. Plac w Studio (odczyt w Edit, 09.11)

- **Mag:** `Workspace.WizardTower.Interior.WizardRoom.TowerMage`, Model R6 z `Humanoid`, `PrimaryPart = HumanoidRootPart`. Pivot około (171, 179, 814), przód w stronę (−0,32, 0, −0,95). **Nie ma `ProximityPrompt`**, więc serwis tworzy go w kodzie jak `CosmeticsService.ensurePrompt` (nazwa i zasięg w `Config.Skills`). Mag i prompt trafiają do kontraktu w STUDIO_CONTRACT.
- **Wieża:** stoi na wyspie lobby, przesuniętej 09.11 razem z nią. Jest w `Config.LobbyHide.Roots`, więc z mapy jej nie widać.
- **Ściemnienie przy wieży:** `TowerAmbienceController` ściemnia obraz przy wieży (`ColorCorrectionEffect` i `ExposureCompensation`). Sprawdź, czy panel i kadr na maga są w tym czytelne; ewentualne wyłączenie przy otwartym panelu zrób na wzór `setShopAmbient` w `ShopController`.
- **Panel:** `StarterGui.SkillTree` jeszcze nie istnieje. Stawiasz go przez MCP w Edit, nie z kodu: obiekty buduj poza placem i wstawiaj na końcu, każde `execute_luau` to jeden krok cofania (lekcja 15). `ResetOnSpawn = false` (zasada 10), czcionka Fredoka, czarne obrysy, cienie `<Nazwa>Shadow` (`TextShadowController`).
- **Zasoby (wgrane 09.11, gotowe do użycia).** Ikony są białe z czarnym obrysem; kolor odnogi nadaje `ImageColor3`.

| Zasób | Asset | Użycie |
|---|---|---|
| `kek_circle_magic_1` | `rbxassetid://135211706675942` | magiczny krąg-pięciokąt za drzewkiem |
| `kek_circle_3` | `rbxassetid://104862904593188` | pierścień pola dostępnego |
| `kek_circle_5` | `rbxassetid://94855065348267` | poświata pola kupionego |
| `kek_circle_6` | `rbxassetid://133961197928736` | wirujący łuk wybranego pola |
| `lightning_border` (1920×1080) | `rbxassetid://95318101124033` | obramowanie REBIRTH |
| ikona `wizard-staff` | `rbxassetid://93905985234522` | START |
| ikona `sprint` | `rbxassetid://71623328175568` | SPEED |
| ikona `lungs` | `rbxassetid://98337319713905` | STAMINA |
| ikona `fire-shield` | `rbxassetid://83252931225082` | LAVA SKIN |
| ikona `heavy-helm` | `rbxassetid://133442847526088` | TOUGHNESS |
| ikona `two-coins` | `rbxassetid://137538707406156` | GREED |
| ikona `punch` | `rbxassetid://92012252540188` | FORCE |
| ikona `cycle` | `rbxassetid://138067380664051` | REBIRTH |
| ikona `padlock` | `rbxassetid://72783047857523` | pole zablokowane |

Pliki źródłowe i autorzy są lokalnie w `artifacts/ui-effects/` (poza gitem). Ikony game-icons wymagają podpisu CC BY w opisie gry (DO_RELEASE).

### 5. Szkic listy testów dla Kacpra (przenieść do TESTY i uzupełnić)

1. Podejdź do maga i naciśnij E: kamera podjeżdża, panel się otwiera, HUD (inventory, SKIP, spectate) się chowa. Esc albo X: wszystko wraca.
2. Kup START: kasa spada o 150, pole złote, chód i sprint wyraźnie szybsze.
3. Kliknij SPEED II bez 10 przetrwanych rund: przycisk szary, napis „SURVIVE 10 ROUNDS x/10”, kasa bez zmian.
4. Sprint przez całą rundę ze wszystkimi bonusami szybkości: anty-cheat nie cofa ani nie karze.
5. Stań w lawie z LAVA SKIN II: wytrzymujesz dłużej niż bez niego (porównaj z poprzednim kontem albo przed zakupem).
6. Skok ze śmiertelnej wysokości z TOUGHNESS II: dalej zabija. Niższy upadek: mniej obrażeń.
7. Wykup wszystko i zrób rebirth: drzewko puste, kasa, itemy i kosmetyki zostały, za przetrwanie dostajesz 105$ zamiast 100.
8. Wyjdź i wejdź ponownie: drzewko, rebirthy i statystyki są takie same.
9. FORCE: F w ścianę na mapie robi dziurę; F w lobby i w wieży nic nie niszczy.
10. Pomijając rundę, otwórz drzewko w jej trakcie i kup pole: działa, bonus od razu.
11. Otwórz sklep, kosmetyki i drzewko szybko po sobie: nigdy dwa panele naraz.

### 6. Po każdym etapie

Wpis w `docs/STATUS.md` (z „NIEPRZETESTOWANE”, dopóki Kacper nie sprawdzi), przypadki w `docs/TESTY.md`, opisy nowych plików w `docs/ARCHITECTURE.md`, kontrakt maga i panelu w `docs/STUDIO_CONTRACT.md`, wiersz w `docs/README.md`. Aktualizuj stan na górze tego pliku.
