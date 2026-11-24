# STATUS — ESCAPE LAVA

Aktualizacja **24.11.2026**. Ostatni pełny audyt 23.10: kod repo, lokalna historia Git, checklisty i odczyt Studio w Edit, bez Play, pomiaru FPS i publikacji ([audyt kontekstu](CONTEXT_AUDIT_2026-10-23.md)). Sekcje niżej idą od najnowszej; starszy wpis nie unieważnia nowszego. Wpisy o kolejnych wersjach UI COSMETICS (v4–v6e) wyniesione do [archiwum](archive/2026-11-13/COSMETICS_STATUS_v4-v6e.md); bieżący opis: „COSMETICS — stan bieżący (13.11)”.

**Stan na 13.11:** gra nie jest jeszcze opublikowana (potwierdził Kacper); wszystkie zmiany z 06.11 wzwyż są NIEPRZETESTOWANE w Play, a plac (UI, mapa, sceny) przez MCP wymaga zapisu Cmd+S. Kod zgadza się ze Studio (odczyt `.Source` + parsowanie 13.11). Studio: `ESCAPE LAVA`, placeId 107369017875577, `rojo serve` chodzi.

## 24.11 (później) — pociąg, niska grawitacja, hak EPIC, sprawdzone częściowo w Play przez agenta, Cmd+S wymagany

Kacper: „dodaj pociąg, hak lepsza rzadkość, niska grawitacja”. Decyzje (AskUserQuestion): hak EPIC; pociąg 60% HP i wyrzut, dach dla pasażerów; zburzone tory = nie przyjeżdża; grawitacja: wysokie skoki, upadki nie ranią; oba w każdej rundzie; kozły na końcach torów usunąć i zrobić czarne tunele, w które pociąg wjeżdża i znika.

- **Pociąg:** napis „TRAIN INCOMING! GET OFF THE TRACKS! 5”, wyjazd z losowego tunelu, 60 stud/s, lokomotywa i 3 wagony, ~9 s przez miasto (przez oba budynki na torach). Tory są 46 studów nad ulicą, więc uderzony zwykle i tak ginie od upadku.
- **Niska grawitacja:** 10 s, skok 7 → 21 studów, napis odlicza do końca, jeszcze 1,5 s po niej upadki nie ranią. Tylko uczestnicy rundy.
- **Hak:** fioletowy ze snopem, 13% → 8% na mapie, w puli skrzyń (3 z 5; nadal zawsze RPG albo drabina).
- **Plan rundy (80 s) zmieniony:** zrzut 9–12 · nalot 18–20 · pociąg 32–34 · zrzut 40–42 · (50%) nalot 46–49 · grawitacja 60–62.
- **Kod:** nowe `TrainPath`, `TrainService`, `TrainController`, `LowGravityService`, `LowGravityController`; `FallDamageService` i `BridgeController` po jednej zmianie; klawisze dev w `Config.Dev.EventKeys` (L zrzut, J nalot, T pociąg, N grawitacja). Pliki zgodne ze Studio (suma) i się parsują.
- **Plac (zgoda Kacpra):** `Map.Locked.TrainTunnels`, `ReplicatedStorage.Train`; kozły usunięte, kopia w `ServerStorage.RailwayEnds_Backup_2411`.
- **Play agenta (dwie krótkie sesje, obserwacja):** jazda na dachu 4 s przez oba tunele — postać nie przesunęła się względem wagonu; pociąg zniknął po 8,8 s; uderzenie na podkładzie 100 → 40 HP w chwili dojazdu czoła, potem śmierć od upadku z torów; skok w niskiej grawitacji 20,6 studa, upadek z ~58 studów bez obrażeń, po końcu wszystko wróciło. **Po Play poprawione i już niesprawdzane:** siła odrzutu (była za słaba) i jednostronny dach. **Nie sprawdzone w Play:** zburzone tory (odczyt w Edit: 0/145 braków na całych, 140/145 bez jednej szyny).

## 24.11 — wydarzenia w rundzie: zrzut zaopatrzenia i nalot rakietowy, sprawdzone podstawowo w Play przez agenta, Cmd+S wymagany

Kacper: „żeby coś się działo w rundzie: zrzuty z rzadszym lootem i 1–2 razy na rundę nalot rakietowy z alarmem, bez podania budynku”. Decyzje (AskUserQuestion): loot wysypuje się dookoła skrzyni; dachy, 2 na rundę; nalot mocny; cel losowy, częściej budynki z graczami.

- **Zrzut:** skrzynia na spadochronie opada 8 s na losowy dach nad lawą, słup światła pokazuje gdzie. E otwiera od razu, dookoła lądują 3 różne itemy z puli RPG / C4 / bomba / drabina (zawsze RPG albo drabina). Dach pod skrzynią zniszczony → spada niżej, w lawie przepada.
- **Nalot:** syrena i napis „AIR RAID! MISSILES HIT A BUILDING IN 8”, rakiety widać ~2 s przed uderzeniem, 5–10 sztuk co 0,35 s w jeden budynek. Rani każdego w zasięgu (50% w epicentrum), zabójstwo nikomu się nie liczy. Cel wybrany w chwili alarmu i znany tylko serwerowi.
- **Kiedy:** ułamki rundy w `Config.RoundEvents.Schedule` (aktualny plan: wpis wyżej).
- **Kod:** nowe `RoundEventService`, `SupplyDropService`, `AirstrikeService`, `RoundEventController`, `SupplyDropController`, `AirstrikeController`; `ItemPickupService.spawnAt`, łuk wysypu w `ItemPickupController`, `BombService` rani bez sprawcy przy `hurtsWithoutAttacker`; klawisze dev **L** (zrzut) i **J** (nalot). Pliki zgodne ze Studio (suma) i się parsują.
- **Pomiar celowania (Edit, odczyt, nietknięta mapa):** przy lawie Y 3 / 40 / 70 / 85 wszystkie rakiety trafiają w wybrany budynek, koszt < 1 ms; w cel wchodzą kolejno 10 / 5 / 4 / 2 budynki.
- **Plac:** `ReplicatedStorage.SupplyCrate` i `StrikeMissile`, 23 markery `Map.Locked.SupplyDropSpawns` i `HUD.EventMessage` postawione przez MCP (zgoda Kacpra 24.11). Niczego istniejącego nie zmieniono; cofnięcie: Ctrl+Z.
- **Play agenta (jedna sesja za zgodą, obserwacja):** skrzynia opadła w 8 s, po otwarciu 3 itemy (drabina, C4, RPG) na dachu 4,5 studa od niej; zrzut z planu rundy też się odbył. Nalot: odliczanie 8 → 1 → „TAKE COVER!”, pierwsze uderzenie 0,08 s po zerze, 10 wybuchów w SandBuilding w ~3,3 s, serwer 5–20 ms na rakietę, kolaps częściowy (budżet najwyżej 67/100). Gracz obok trafienia 100 → 63 HP, bez komunikatu zabójstwa. Runda skończyła się z rakietami w powietrzu: w lobby zero wybuchów, 3 budynki odbudowane. Po Play poprawione: syrena wczytuje się z góry (wcześniej pierwszy alarm ładował ją ~0,5 s). Wyglądu i dźwięku nie oceniałem.
- Syrena: „Air Raid Siren Old Fashioned 2” (Pro Sound Effects, darmowa, `rbxassetid://9113073796`) — propozycja, nieodsłuchana. Świst rakiety i dźwięki skrzyni puste.
- Pomysły na kolejne wydarzenia: [ROADMAP](ROADMAP.md) → „Wydarzenia w rundzie”. Testy: [TESTY](TESTY.md) → „Wydarzenia w rundzie”.

## 15.11 (noc, jeszcze później) — pasek lawy po prawej w rundzie, Cmd+S wymagany

**v3 (Kacper: „góra lawy kwadratowa, max 90% paska — limit gry”):** lawa na pasku ma kwadratową górę (zaokrąglony tylko spód, `Track.LavaBase` przez MCP — Cmd+S); poziom lawy na końcu rundy (~Y 122, liczony z `Config.Lava`) = 90% paska, ulica 25%, start lawy 15%. Play agenta: wymiary zgodne, zrzut `artifacts/lava-meter/4_square_top_v3.jpg`.

**v2 (Kacper: „buja się przy chodzeniu, lawa też; przy małej lawie rozjeżdża się z ramką”):** znacznik liczony ze stóp (korzeń postaci) zamiast głowy, z wygładzaniem i martwą strefą; lawa pokazuje najwyższy dotychczasowy poziom (bez falowania); skala: start lawy = 15% paska, ulica = 25%, dach = 100%. Ostrzeżenie od stóp: 4 studa. Play agenta: w miejscu znacznik 0 ruchu, lawa stała 15,8%, gracz na ulicy na 24,8%.

Kacper: „po prawej podczas rundy pasek z poziomem lawy i gdzie jesteś”. Decyzje: tylko ty, znacznik = głowa awatara, ostrzeżenie blisko lawy.
- Pionowy pasek: lawa rośnie od dołu (od poziomu ze startu rundy do najwyższego dachu), okrągła miniatura głowy pokazuje twoją wysokość; lawa bliżej niż 8 studów pod głową → czerwona obwódka i puls.
- Kod: `LavaMeterController`, `Config.LavaMeter`; UI `HUD.LavaMeter` przez MCP; podpowiedź detonatora C4 przesunięta w lewo. Kod zgodny ze Studio i parsuje się. Play agenta: pasek tylko w rundzie, lawa rośnie, ostrzeżenie działa. Testy: [TESTY](TESTY.md) → „Pasek lawy”.

## 15.11 (noc, później) — drzewko: pasek postępu rebirthu i rozpiska nagród, Cmd+S wymagany

Kacper: „REBIRTH 3/5 brzmi, jakbym miał 3 rebirthy” + „pokaż, co daje rebirth, ładnie, z ikonkami”. Decyzje: pasek postępu pod napisem; rozpiska po najechaniu na REBIRTH.
- Przycisk zawsze „REBIRTH”, pod nim pasek kupionych pól z „3/5” (do rebirthu trzeba kupić wszystkie odblokowane).
- Najechanie: w miejscu szczegółów „REBIRTH N GIVES” — ikona kasy +5% (z sumą), ikona i kolor nowej odnogi, nowy item (jeśli jest), „YOU KEEP CASH, ITEMS, COSMETICS”.
- Kod: `SkillTreeController` (`rewardRows`), `SkillTreeFx` (`setRebirth` z paskiem, `setRebirthInfo`, `showRebirthInfo`), teksty i liczby w `Config.Skills`. UI przez MCP: `RebirthButton.Progress`, `Panel.RebirthInfo`. Po restarcie Studio wtyczka Rojo była rozłączona — po Connect kod zgodny ze Studio (suma) i się parsuje. Play agenta: zrzuty w `artifacts/skilltree/`. Testy: [TESTY](TESTY.md) → „Rebirth: pasek postępu”.

## 15.11 (noc) — własny prompt E wszędzie, snop do sufitu, Cmd+S wymagany

Kacper: „nie przez sufit” + „custom proximity prompt przy podnoszeniu”. Decyzje: klawisz E jak przy C4, nazwa w kolorze rzadkości, od razu (bez przytrzymania), styl wszędzie (itemy, sklep, przebieralnia, mag).
- **Prompt:** `PromptController` + szablon `StarterGui.PromptTemplate` (MCP): nazwa nad klawiszem E i akcja obok, skalowany jak HUD; klawisz wciska się przy naciśnięciu; na telefonie dotknięcie promptu. Kolor nazwy itemu = rzadkość (`TitleColor` z `ItemPickupFx`).
- **Snop** kończy się pod pierwszym stropem nad itemem.
Kod zgodny ze Studio i parsuje się. Play agenta: oba prompty działają, E podnosi item, snopy pod stropem. Testy: [TESTY](TESTY.md) → „Własny prompt E”.

## 15.11 (wieczór, później) — aura itemów wg rzadkości, sam kod

Kacper: „VFX do itemów, outline, aura zależnie od rzadkości”. Decyzje: aura + światło dla wszystkich, obrys, snop światła tylko przy najlepszych; rzadkość wg szansy (COMMON napój/bandaż/hak, RARE bomba/C4, EPIC RPG, LEGENDARY drabina), kolory jak w COSMETICS; rzadsze = mocniejszy efekt.
- Nowy helper `ItemPickupFx` + podpięcie w `ItemPickupController`, liczby w `Config.ItemPickup.FX`. Obrys tylko na 12 najbliższych w 70 studach i nie przez ściany (limit silnika 31 obrysów). GRAPHICS LOW: połowa drobinek.
- Kod zgodny ze Studio i parsuje się; Play agenta: efekty na wszystkich itemach, snopy tylko RPG/drabina, obrysy tylko z bliska, bez błędów. Wyglądu nie oglądałem — [TESTY](TESTY.md) → „Aura itemów”.

## 15.11 (wieczór) — więcej itemów i kasy, większa szansa na broń, rozmiary itemów, Cmd+S wymagany

Kacper: „więcej pieniędzy na mapie i itemów — z 3 itemy na budynek, nieco większa szansa na bomby/RPG/C4, popraw rozmiary (bandaż i energy drink za duże, RPG za mały)”.
- **Itemy:** 43 spoty w 9 budynkach (było 20), w rundzie po 3 losowe z każdego budynku = **27 itemów** (było 10). Spoty mają atrybut `Building`; `Config.ItemPickup.PerBuilding`. CyanOffice dostał 5 spotów mimo braku wyjścia z pięter (hak/wybuch); OrangeKebab pominięty (parter z ulicy).
- **Szanse:** bomba, RPG i C4 ×2 (`WeightBoost`): napój 26%, bomba 19%, C4 14%, bandaż 13%, hak 13%, RPG 11%, drabina 3%.
- **Rozmiary:** osobno dla itemu (`Config.ItemPickup.Sizes`, najdłuższy bok): bandaż 1,5, napój 1,6, C4 2,2, bomba 2,4, hak 2,4, drabina 3,2, RPG 4,6 (było wszystko 2,6, RPG 3,0).
- **Kasa:** wszystkie 50 miejsc w każdej rundzie (`Config.Cash.SpawnFraction` 0,6 → 1,0).
Kod zgodny ze Studio i parsuje się; Play agenta: 27 itemów po 3 na budynek, 50 paczek kasy, bez błędów. Testy: [TESTY](TESTY.md) → „Więcej itemów i kasy”. Cofnięcie markerów: Ctrl+Z („ItemSpawns v2”).

## 15.11 (później) — skalowanie UI: Edit = Play, pasek zdrowia w kasie, panele na telefonie, Cmd+S wymagany

Kacper: „czy całe UI jest responsywne; w Edit kasa inna niż w Play”. Przegląd: kolory kasy w Edit i Play identyczne (różni się tylko rozmiar). Naprawione (decyzja „napraw wszystkie”):
- **Edit = Play:** w placu były stare, wymieszane skale podglądu (0,66 / brak / 1,0). Nowy `HUD_PREVIEW.luau` (Command Bar, Edit) ustawia ten sam wzór co gra; odpalony raz (okno 577 px → 0,5).
- **Pasek zdrowia → `HUD.Cash.HealthBar`:** skaluje się z kasą, zawsze tuż nad nią (wcześniej na 1920×1080 nachodził na kasę o ~59 px). Puls `Pop` → `Pulse` (kasa szuka `Pop` w całej ramce).
- **Paski odnowienia → `HUD.Hotbar.CooldownBars`:** stoją nad hotbarem na każdym ekranie (na telefonie wchodziły na niego).
- **Telefon:** INVENTORY i drzewko u maga dopasowują się do wysokości ekranu (`FitHeight`, `Config.UI.FitHeightFraction` 0,94).
Kod zgodny ze Studio, parsuje się; Play agenta przy oknie Studio bez błędów. Telefonu nie sprawdzono — [TESTY](TESTY.md) → „Skalowanie UI”. Cofnięcie UI: Ctrl+Z („UI scale fixes”, „HUD preview scale”).

## 15.11 — własny pasek zdrowia zamiast domyślnego Robloxa, sprawdzony podstawowo w Play przez agenta, Cmd+S wymagany

Kacper: „usunąć default roblox health bar i dać nasz custom”. Decyzje (AskUserQuestion): lewy dół nad kasą, pasek + liczba „72 / 100”, widoczny tylko w rundzie, efekty: ghost spadek, kolor od HP, potrząśnięcie, puls przy niskim HP.

- **Gra:** w rundzie nad kasą pasek w stylu HUD (czarny obrys, FredokaOne). Trafienie → liczba spada, jasny kawałek straconego HP chwilę stoi i zjeżdża, pasek drga (mocniej przy dużym trafieniu). Kolor zielony → żółty → czerwony, poniżej 25% pulsuje. Po śmierci pokazuje 0 jeszcze ~1 s. Domyślny pasek Robloxa wyłączony.
- **Kod:** `HealthBarController`, `Config.HealthBar`, wyłączenie `CoreGuiType.Health` w `init.client`. Zgodne ze Studio (suma) i parsują się. **Plac:** `HUD.HealthBar` przez MCP (kontrakt: STUDIO_CONTRACT). Cofnięcie: Ctrl+Z (krok „HealthBar v1”).
- **Play agenta (obserwacja):** patrz [TESTY](TESTY.md) → „Pasek zdrowia”. Wyglądu nie oglądałem zrzutem (zrzuty Studio tylko za zgodą).

## 13.11 (noc) — itemy porozrzucane po mapie, sprawdzone podstawowo w Play przez agenta, Cmd+S wymagany

Kacper: itemy na mapie do zebrania, droższe rzadsze, ~20 spotów głównie na piętrach budynków, nie aż tak łatwo dostępne. Decyzje (AskUserQuestion): item spoza slotów idzie **tylko do inventory** (slotów w rundzie nie zmieniamy), podniesienie na **E**, co rundę **losowo ~10 z 20**, spoty stawia agent.

- **Gra:** w rundzie leży 10 itemów (bomba, drabina, hak, napój, RPG, C4, bandaż), każdy kręci się nad podłogą. E → +1 do inventory na stałe. Jeśli item jest w twoich slotach, możesz go użyć od razu. Szansa: napój 34%, bandaż i hak po 17%, bomba 12%, C4 9%, RPG 7%, drabina 4% (z cen, `Config.ItemPickup.RarityExponent`). Zalany lawą albo bez podłogi po wybuchu — znika.
- **Spoty (plac):** 20 w `Map.Locked.ItemSpawns` na piętrach 8 budynków, każdy niedaleko okna/otworu (hak, drabina, wybicie szyby), w SandBuilding schodami. CyanOffice pominięty — piętra bez wyjścia. Opis: STUDIO_CONTRACT. Cofnięcie: Ctrl+Z (kroki „ItemSpawns v1”, „ItemSpawn10 off rail”, „PickupMessage v1”).
- **Kod:** `ItemPickupService`, `ItemPickupController`, remote `ItemPickedUp`, `Config.ItemPickup`, UI `HUD.PickupMessage` (kopia układu KillMessage). Zgodne ze Studio (suma) i się parsują.
- **Play agenta (obserwacja, nie werdykt):** 10 itemów na starcie rundy, prompt na każdym, podniesienie napoju zadziałało (serwer `give`, komunikat widoczny). Napój dopisał się do studyjnych danych testowych. Testy: [TESTY](TESTY.md) → „Itemy na mapie”.

## 13.11 (wieczór) — HUD: COSMETICS rośnie jak INVENTORY, mikro animacje SKIP ROUND i SPECTATE, NIEPRZETESTOWANE

- **COSMETICS:** przycisk miał `Pop` (UIScale) na placu, ale kod go nie ruszał. Teraz `HudButtonFx.hook`: hover 1,07, wciśnięcie 0,93, klik odbija.
- **SKIP ROUND:** ikona przesuwa się do przodu przy hover, po kliknięciu odskakuje w tył i „strzela”, co 4,5 s sama się szturcha (tylko gdy nikt nie najeżdża).
- **SPECTATE:** źrenica oka patrzy za kursorem (promień 8 px), klik = mrugnięcie, mruga też sama co 3–6 s. Wyszarzony („NO PLAYERS”) nie reaguje.
- Nowy moduł `src/client/Controllers/HudButtonFx.luau`, liczby w `Config.HudButtonFx`, podpięcie w `CosmeticsController`, `RoundSkipController`, `SpectateController`. Plac nietknięty (moduł dodaje tylko `UIScale` „Pop” na przyciskach, jak `InventoryController`). Nie sprawdzono składni w Studio (był Play), tylko czytaniem.

## 13.11 (po południu) — sklep: płyta ceny na karcie → BUY, ciemniejsze światło przebieralni, NIEPRZETESTOWANE, Cmd+S wymagany

- **Sklep (karty katalogu), nie przymierzalnia:** płyta ceny na karcie jest większa (`Config.Cosmetics.UI.PlateHeight` 72, `PlateTextSize` 50, `PlateIconSize` 88, wcześniej 52 / 36 / 64). W spoczynku pokazuje cenę; po najechaniu zmienia się w **BUY** (jaśniejsza zieleń `PlateHover`), a klik kupuje od razu, bez przymierzania (`quickBuy` w `CosmeticsController`, serwer waliduje jak zawsze; BUY od razu zakłada). Bez gotówki: cena zostaje, płyta szarzeje, klik pokazuje „NEED x$ MORE” i trzęsie płytą. Dotyk: od razu „BUY 750$”. Klik w resztę karty nadal otwiera przymierzalnię. Płyta ma przezroczysty przycisk `PriceRow.BuyHit` tworzony w kodzie przy budowie karty; nazwa na karcie kończy się przed płytą (`PlateNameReserve`).
- **Przymierzalnia — cofnięte:** moja pierwsza wersja (płyta ceny zamiast przycisku w lewym dolnym rogu) była zrozumiana błędnie. `Fitting` przywrócony z `ServerStorage.CosmeticsUI_v6e_1311`, kod `showAction` usunięty.
- **Światło sceny przebieralni (plac):** ściany `9a825a`, deski i belki ciemniejsze, lampy wiszące 0,8 / kinkiety 0,55, reflektory „key” węższe (34°) i mocniejsze (3,2); podest jest najjaśniejszy.
- Kod zgodny ze Studio (parsuje się, znaczniki są).

## 13.11 — COSMETICS: bezwładność obrotu postaci, ciemniejsze gradienty BUY / BACK, NIEPRZETESTOWANE

- **Obrót z wybiegiem:** po puszczeniu postać (przebieralnia i ramka katalogu) kręci się dalej i wytraca prędkość (`Config.Cosmetics.UI.SpinFriction` 2,6 /s, `SpinMaxVelocity` 900 °/s, `SpinStopVelocity` 6 °/s, `SpinHoldTime` 0,07 s). Złapanie zatrzymuje wybieg; trzymany, nieruszany palec zeruje prędkość. Samoobrót wraca po `FittingSpinDelay` od zatrzymania. Kod: `turn`, `rotateBy`, `animate` w `CosmeticsController`.
- **Gradienty:** BUY 46,196,84 → 28,152,62 → 12,96,40; BACK 92,66,142 → 62,42,100 → 34,22,58; połysk `Sweep` na BUY w jasnej zieleni zamiast bieli (ustawia kod). Plac nietknięty. Do sprawdzenia w Play: czy wybieg nie jest za długi / za krótki (stroić `SpinFriction`).

## 13.11 — więcej kasy po mapie i 16 spawnów: PLAC PRZEZ MCP, NIEPRZETESTOWANE, Cmd+S wymagany

Kacper: „porozstawiaj po mapie dużo kasy, usuń tą co jest, losowo; więcej spawnów na 15 osób, 1–2 na parterze budynku; kasa po dachach, budynkach, drogach, ale nie za dużo”. Decyzje (AskUserQuestion): 50 miejsc, co rundę 30; zostawić 6 starych spawnów i dodać 10; budynek wybieram sam.

- **Kasa:** 9 starych markerów usunięte, 50 nowych `CashSpawn01..50` w `Map.Locked.CashSpawns` — 18 w środku budynków (parter i piętra, tylko miejsca z dojściem z ulicy), 14 na dachach (w tym najwyższe: hotel 106, GreenBuilding 102), 18 na ulicach/chodnikach/trawnikach. Co rundę gra losuje 30 z 50 (`Config.Cash.SpawnFraction` 1.0 → **0.6**), więc kasa za każdym razem gdzie indziej.
- **Spawny:** 6 starych zostaje, +8 na chodnikach/ulicach na obrzeżach mapy (`SidewalkSpawn7..14`) i +2 w holu hotelu na parterze (`HotelLobbySpawn1..2`, PupleHotel, dywan Y 11,1, ~17 studów od siebie). Razem 16 — każdy z 15 graczy dostaje osobne miejsce. Kod nie ma limitu liczby spawnów.

Każdy punkt postawiony promieniem na realną podłogę i sprawdzony odczytem: płasko, nad głową wolne (kasa 4 study, spawn 6), brak ścian i przeszkód obok, nic nad lawą. Wnętrza i hol hotelu — dojście z ulicy sprawdzone przeszukaniem po podłodze (bez skakania). Markery nowe mają `CanQuery/CanTouch = false` (stare kasy miały `true` — niewidzialny marker mógł łapać promienie haka/celownika). Cofnięcie: Ctrl+Z w Studio (krok „Assistant 9” + mała poprawka wysokości 5 punktów na dywanie/trawie). Kontrakt: [STUDIO_CONTRACT](STUDIO_CONTRACT.md). Testy: [TESTY](TESTY.md) → „Kasa i spawny 13.11”.

## 12.11 — światło u maga cieplejsze, efekt upadku z obrażeniami: NIEPRZETESTOWANE, Cmd+S wymagany

Kacper: „światło u maga bardziej ciepłe, ale fioletowe, ciemniejsze” + „VFX przy obrażeniach od upadku”. Decyzje (AskUserQuestion): ciepła śliwka; efekt w świecie i na ekranie; świat widzą wszyscy; siła skalowana obrażeniami.

- **Mag:** doświetlenie przy otwartym drzewku 226,205,255 / 1,6 → **190,110,165 / 1,4** (`Config.Skills.Camera.Fill*`).
- **Upadek, który zranił:** u wszystkich w promieniu 160 studów — pierścień kurzu w kolorze podłogi, odłamki wyskakujące spod stóp i fala na ziemi, wielkość od obrażeń. U poszkodowanego dodatkowo czerwone krawędzie ekranu (błysk i wygaszenie ~0,8 s); wstrząs ekranu jak dotąd. GRAPHICS LOW: połowa kurzu i odłamków, bez fali.

**Kod:** nowy `FallImpactController`, remote `FallImpact` (serwer → wszyscy, tylko przy raniącym upadku), `FallDamageService` wysyła go obok `BombHit`; liczby w `Config.FallDamage.Impact`. Pięć zmienionych plików zgodnych ze Studio (suma) i się parsuje. **Plac (MCP w Edit):** `StarterGui.FallVignette` — kopia układu `EnergyVignette` bez linii prędkości, krawędzie czerwone. Bez Play nie widziane: kolor maga w kadrze i sam efekt. Testy: [TESTY](TESTY.md) → „Upadek i mag 12.11”.

**Dalej 12.11 — odliczanie i miganie lawy.** (1) Cyfry 3-2-1 bez wskoku i z przerwą: od 10.11 obrazek cyfry pokazywał się dopiero po statusie „wczytany” z `ContentProvider`, który przychodzi później niż zmiana cyfry — przedtem lukę zasłaniał napis zastępczy. Teraz cyfra widoczna od razu, napis tylko przy błędzie wczytania (`RoundTransitionController`, zgodny ze Studio). (2) Gradient cyfr: `UIGradient` „Shade” na `RoundCountdown.Digits.1/2/3` (MCP, Cmd+S wymagany) — górna połowa w kolorze cyfry, dół do ~60% jasności (zielona → ciemnozielona, żółta → ciemnożółta, czerwona → ciemnoczerwona). (3) Lawa — „w najniższych punktach tafli czarne przemiguje”: **przyczyna zmierzona w Play (odczyt)** — pudło, z którego rodzą się popiół i iskry `Lava.Air`, stało 0,4 nad FIZYCZNĄ taflą (2,5–3,3), a fala sięga 1,5–3,6. Ciemny popiół rodził się pod grzbietami i wychodził w dolinach. Teraz start od grzbietu fali (`LavaWaveMesh:topY()`), sufit lotu bez zmian (w kanale dalej pod jezdnią). Odrzucone po sprawdzeniu: cień ukrytych płyt (`CastShadow` już false), podmiana `MaterialVariant`, zmiana `MeshSize`. Po tej zmianie Kacper: „częściej miga” — czyli migające czarne to SAM popiół (płatki pojawiają się i gasną; podniesione nad falę były widoczne wszędzie). **Popiół wyłączony** (`Lava.Air.AshRateMin/Max = 0`, było 3/20), iskry zostają, start nad grzbietem fali zostaje. Kod zgodny ze Studio (suma) i się parsuje. Kacper potem: „dalej miga, po minucie, w najniższych punktach; czy coś jest pod falą?”. **Prawdziwa przyczyna:** fala była wyśrodkowana na tafli, więc jej dołki schodziły ~1 stud POD prawdziwą lawę. Gdy lawa mijała ulicę (asfalt 8,8, renderuje się czarno), w dołkach wychodził czarny asfalt. Płyty lawy SĄ ukryte (`LocalTransparencyModifier` działa — zdjęcie w Edit: w kanale pod lawą widać niebo). Bąble skorupy (wyłączone po drodze przez błędną diagnozę) przywrócone. **Decyzja Kacpra „fala nad lawą”:** siatka podniesiona o `Waves.Amplitude` — dołek = prawdziwa tafla, grzbiet do ~2,1 nad nią (`LavaWaveMesh`). Zmierzone w Play: dołek równo z taflą (8,36/8,36 … 8,94/8,93). Minus: na grzbiecie fala może zakryć stopy, zanim zaczną parzyć. Popiół zostaje wyłączony. Kod zgodny ze Studio (suma), bez błędów w logu. **Dalej migało** → Kacper: „zrób od nowa, tekstura ma zostać, resztę efektów wyjebać”. **Siatka fali i wszystkie efekty tafli WYŁĄCZONE** (`Lava.Waves.Enabled = false`, `Lava.FX.SurfaceEffects = false`): została płyta lawy z teksturą `EscapeLava_RoundedRed_v4` i falowanie całej tafli z serwera (`Lava.Wobble`). Najmocniejsza hipoteza (niepotwierdzona pomiarem): siatka z EditableMesh, aktualizowana 20×/s, chwilami się nie rysowała — pierwsze zgłoszenie brzmiało „tekstura na chwilę znika”, a przez dziurę widać czarną ulicę. Rozbryzg przy wpadnięciu i widok spod tafli zostają. Play przez MCP: siatki brak, 0 widocznych partów/świateł/emiterów tafli, płyty widoczne, zrzut — tekstura na miejscu. Kod zgodny ze Studio. Powrót do fali/efektów: dwie flagi w Config (kod nietknięty).

## 12.11 (wieczór) — nowa przebieralnia „pracownia krawca” (scena w Workspace), obejrzana zrzutem z Edit, bez Play, Cmd+S wymagany

Na prośbę Kacpra: pierwsza wersja „butik lawy” odrzucona (napisy, brzydkie manekiny, kwadratowa obwódka okrągłego podestu). Teraz pokój 28×42×11 w stylu krawca, **bez żadnych napisów**: drewniana podłoga i belki, kremowe ściany ze studsami, lustro w drewnianej ramie za podestem, kinkiety i trzy lampy wiszące, tablica z narzędziami (nożyce, miara, szpule, kreda), regał z belami materiału, wieszak z płaszczami, stół z maszyną do szycia.
- **Manekiny = prawdziwe rigi R6** (`CreateHumanoidModelFromDescription`, bez Humanoida i Animate, kotwiczone, pozowane ręcznie, na drewnianych podstawkach): dynia, kamizelka i plecak nałożone przez atrybuty rigu (`HatAttachment`, `BodyFrontAttachment`, `BodyBackAttachment`).
- **Podest:** ten sam obiekt i ścieżka (`Decoriations.Platform.platform`), przemalowany na orzech; obwódka to mosiężny okrąg `Room.PlatformTrim.BrassRing` (średnica 5,3), nie kwadrat.
- **Backup starej sceny:** `ServerStorage.ClothesShopBackup_1211` (scena + 7 luźnych `Workspace.Part`; te zostały usunięte z Workspace). Kod nietknięty.
- **Poprawka detali (12.11):** podstawki manekinów (mosiężna stopa 0–0,1 + drewniany dysk 0,1–0,4, bez przenikania), pierścień podestu poniżej jego powierzchni, tablica narzędzi przebudowana (linijka z podziałką, nożyce, szpule, kreda, miara; wszystko płasko na desce, bez nachodzenia), wieszak z trzema płaszczami o odstępach 2,0, maszyna do szycia ułożona z brył bez nakładania.
- Zrzut z kadru gry (Edit) przeszedł; nie sprawdzono w Play: jasność postaci przy światłach z kodu i kolizja kamery z lampą nad podestem.

## COSMETICS — stan bieżący (13.11), zastępuje wpisy v4–v6e

Jedno miejsce, które opisuje, jak sklep i garderoba wyglądają **teraz**; historia wersji i odrzucone pomysły: [archiwum](archive/2026-11-13/COSMETICS_STATUS_v4-v6e.md).
- **Wejście:** przycisk COSMETICS w HUD (pod INVENTORY; od 13.11 rośnie na hover jak INVENTORY, `HudButtonFx`) = garderoba (tylko posiadane), E przy sprzedawcy `ClothesShop.NPC` = sklep (tylko w lobby). Własny `CosmeticsOpen` blokuje nakładanie się z innymi panelami.
- **Katalog (jeden ekran):** po lewej ramka z kopią postaci gracza w `ViewportFrame` (obrót przeciąganiem z **bezwładnością** od 13.11, sam po 3 s bez dotyku), kasa nad nią; po prawej przewijana siatka kart (kolumny z szerokości, 9 kart COMING SOON tylko w sklepie). Karta: kolor z `Config.Cosmetics.UI.Rarities`, obrys 8 z LED w środku, plakietka rzadkości, nazwa, OWNED / WEARING. **Płyta ceny (13.11):** większa (`PlateHeight` 72), po najechaniu zmienia się w **BUY** i klik kupuje od razu (`quickBuy`), bez gotówki szarzeje i pokazuje „NEED x$ MORE”.
- **Przebieralnia:** klik w resztę karty → scena `ClothesShopScene` (od 12.11 **pracownia krawca**, opis i kontrakt: STUDIO_CONTRACT), kopia postaci na `Decoriations.Platform.platform`, kamera z bounding boxa i parallax za myszą, BACK i BUY / EQUIP / UNEQUIP (`Colors.Buy`, `Colors.Back`, bez bieli; połysk BUY jasnozielony). Przymierzanie nie zmienia zapisanego stroju; BUY od razu zakłada (`CashService.purchase`).
- **Plac:** `StarterGui.Cosmetics` (`Design` = `shop_v6e`); kopie historyczne `ServerStorage.CosmeticsUI_v*`, nowsza `CosmeticsUI_v6e_1311`. Test: TESTY → „COSMETICS — aktualny test”.


## 09–10.11 — drzewko umiejętności i rebirth u maga: KOD I PANEL, NIEPRZETESTOWANE, Cmd+S wymagany

Wdrożony cały [SKILLS_PLAN](SKILLS_PLAN.md) poza samymi itemami z rebirthu. Decyzje Kacpra z 09.11: liczby z planu zaakceptowane; rebirthy 5–10 na razie samo +5% kasy; liczba rebirthów jako kolumna w tabeli graczy (Tab); FORCE robi dziurę bez wybuchu („sam gruz i pył”).

**Dla gracza:** E przy magu w wieży → kamera podjeżdża do maga, po prawej panel z drzewkiem. START (+5% szybkości), od niego sześć odnóg po dwa poziomy; przed pierwszym rebirthem tylko SPEED i STAMINA. Poziom II wymaga rund albo killi liczonych od ostatniego rebirthu. Gdy wszystko odblokowane jest kupione, REBIRTH zeruje drzewko (kasa, itemy i kosmetyki zostają) i daje +5% kasy na zawsze oraz kolejną odnogę.

**Co gdzie działa:**
- SPEED i STAMINA: ruch gracza; limit prędkości anty-cheatu rośnie tak samo, liczony ze stanu serwera.
- LAVA SKIN: mniej obrażeń od lawy. TOUGHNESS: mniej od wybuchów i upadku; śmiertelny upadek dalej zabija.
- GREED i rebirthy: mnożnik nagrody za przetrwanie i kill (nie pickupy). Komunikaty pokazują kwotę po mnożniku.
- FORCE: F w ścianę mapy wybija dziurę (I ≈ 7 studów, II ≈ 10 i +20% siły pchnięcia). Bliższe wygrywa jak dotąd: beczka, szyba, gracz albo ściana. Lobby i wieża nietykalne.
- Itemy z rebirthu: sklep zna pole `requiresRebirth` (szary przycisk „REBIRTH N”, serwer odrzuca zakup). Żaden item go jeszcze nie ma — itemy projektujemy osobno.

**Kod:** nowe `SkillDefinitions`, `StatsService`, `SkillService`, `SkillTreeController`, `SkillTreeFx`; liczby w `Config.Skills`. Opisy: [ARCHITECTURE](ARCHITECTURE.md). Zmiany zrobione 09.11 (serwer, ruch, sklep, pozostałe panele — 26 plików) są w Studio zgodne z dyskiem (suma) i się parsują. **Cztery pliki z 10.11 (`SkillTreeController`, `SkillTreeFx`, `Config`, start klienta) NIE są jeszcze sprawdzone w Studio:** `rojo serve` chodzi, ale wtyczka nie była połączona. Po Connect trzeba sprawdzić sumy i parsowanie, zanim ktokolwiek odpali Play — błąd składni w nowym kontrolerze zatrzymałby start całego klienta.

**Plac (MCP w Edit, Cmd+S wymagany):** `StarterGui.SkillTree` (244 obiekty, `Design = skilltree_v1`), zapis budowy w `artifacts/skilltree/skilltree_ui_v1.luau`, zrzut podglądu z Edit w `artifacts/skilltree/preview_v1.jpg`. Podgląd miał tymczasowe pola — usunięte, panel wyłączony. Kontrakt: [STUDIO_CONTRACT](STUDIO_CONTRACT.md) → „Drzewko umiejętności”. Cofnięcie budowy: Ctrl+Z w Studio (krok „SkillTree UI v1”).

**Nie widziane bez Play:** kadr kamery na maga, animacje, kaskada otwarcia, sekwencja rebirthu, dziura od FORCE. Liczby kadru: `Config.Skills.Camera`.

Otwarte:
- test Kacpra: [TESTY](TESTY.md) → „Drzewko umiejętności i rebirth”;
- itemy z rebirthu 1 i 3 (osobne plany) i nagrody rebirthów 5–10;
- dźwięki (puste ID w `Config.Shop.Fx.Feedback` i `Config.Skills.Force.SoundId`);
- przed wydaniem podpis CC BY game-icons w opisie gry ([DO_RELEASE](DO_RELEASE.md));
- przy 100 rebirthach +500% kasy — ocenić po pierwszych tygodniach (`Config.Skills.RebirthCashBonusMax`).

## 08–09.11 — drzewko umiejętności i rebirth u maga: PLAN (wdrożony 09–10.11, wpis wyżej)

Kacper chce dalszego rozwoju, „żeby gra się nie nudziła”. Pełny plan: [SKILLS_PLAN](SKILLS_PLAN.md). Ustalone:
- **Drzewko:** korzeń +5% szybkości, od niego odnogi po 2 poziomy. Poziom I kosztuje kasę, poziom II kasę i wymaganie (kille, przetrwane albo rozegrane rundy).
- **Odnogi:** SPEED, STAMINA, LAVA SKIN, TOUGHNESS, GREED i FORCE (F wybija małą dziurę w ścianie).
- **Rebirth:** zabiera tylko drzewko. W zamian daje +5% kasy na zawsze, a do 10. rebirthu także nowe odnogi i itemy w sklepie. Liczba rebirthów bez limitu.
- **Wygląd:** kamera na maga `TowerMage` i panel, efekty z ui-resources.com, ikony game-icons z czarnym obrysem i mikroanimacje (sekcja w planie).
- **Zasoby:** 14 obrazów wgranych 09.11 za zgodą Kacpra. ID są w planie i w `artifacts/ui-effects/ASSETS.md` (poza gitem, repo publiczne).

Otwarte punkty tego planu rozstrzygnął wpis 09–10.11 wyżej.

## 09.11 (noc) — lobby oddalone od mapy, NIEPRZETESTOWANE, Cmd+S wymagany

Kacper: „oddal to lobby od mapy”. Wybrał ~500 studów od barier i zostawienie chowania lokalnego (sama odległość wyspy nie schowa — plac bez mgły). Przez MCP w Edit przesunięte o (+204, 0, +330) prosto od mapy, na tej samej wysokości: `Workspace.Lobby` (z `SpawnPoints`, straganami i napisami) i `Workspace.WizardTower`, czyli 3764 party i pivoty 265 modeli bez `PrimaryPart`. Pozycje docelowe liczone przed ruchem — każdy part sprawdzony, odchyłka 0. Środek wyspy (59, 451) → (263, 781), brzeg ~505 studów od barier (było ~110). Nic w lobby nie łączy się z partami spoza niego, terenu (Terrain) przy wyspie nie ma, Rojo nie zarządza `Workspace.Lobby`. Kod czyta pozycje z placu (spawny, stragany, mgła wieży, widok po spawnie), więc w logice nic się nie zmienia — tylko komentarze z pomiarami. Napisy: kamera z mapy najbliżej ~650 od SHOP i ~700 od COSMETICS (było ~285 / ~326), `MaxDistance` bez zmian. Cofnięcie: Ctrl+Z w Studio (krok „Assistant 57”), dopóki Studio jest otwarte. Testy: TESTY → „Lobby niewidoczne z mapy — 09.11”, dwa ostatnie punkty.

## 09.11 (noc) — napisy SHOP / COSMETICS bez migania, NIEPRZETESTOWANE, Cmd+S wymagany

Kacper: napis migał przy szybkim ruchu kamery. Przyczyna: `LobbySign` chował napis za ścianami promieniem kamera → napis co 0,1 s, a promień łapał słupy i krawędzie. Na prośbę Kacpra chowanie usunięte — widoczność wyłącznie ze stałego `MaxDistance`: SHOP 275 (przez MCP, wymaga Cmd+S), COSMETICS 250. Pomiar z 09.11: chodliwe lobby sięga 269 / 223 od napisów, kamera z mapy najbliżej ~285 / ~326. Skutek uboczny: w lobby napisy widać przez budynki (`AlwaysOnTop`). Kod zgodny ze Studio i parsuje się. Test: TESTY → „Lobby niewidoczne z mapy — 09.11”, pierwszy punkt.

## 09.11 (noc) — lobby niewidoczne z mapy, NIEPRZETESTOWANE

Kacper chciał, żeby z mapy nie było widać lobby; zamiast przenoszenia wybrał chowanie lokalne. Pomiar w Edit: wyspa lobby (koło ~370 studów) wisi na wysokości dachów, ~110 studów od barier, a plac nie ma mgły, chmur ani Atmosphere — przeniesiona byłaby widoczna gdzie indziej. Nowy `LobbyVisibilityController`: kamera nad obszarem gry (pudło barier w XZ + 30 studów, powyżej Y −50) → lobby (`Workspace.Lobby` + `WizardTower`) i postacie innych dalej niż 40 studów za barierą znikają z obrazu tego gracza (`LocalTransparencyModifier`, efekty wyłączone). Kolizja zostaje, więc obserwujący stoi dalej na wyspie. Liczby w `Config.LobbyHide`. Kod w Studio zgodny z dyskiem i parsuje się; plac bez zmian (Cmd+S niepotrzebny). Testy: TESTY → „Lobby niewidoczne z mapy — 09.11”.

## 09.11 (wieczór) — bariery: hak + czerwone pole siłowe, NIEPRZETESTOWANE

Decyzje Kacpra: bariery na skraju mapy (`Map.Locked.InvisableWalls`, 4 ściany) widać tylko z bliska, wzór = ForceField. Hak: trafienie w barierę = pudło (`GrappleService.isAnchorable`, `Utils.barrierFolder`). Wygląd lokalny (`BarrierController`): czerwone pole siłowe od 40 studów, pełne od 15, przezroczystość pulsuje 0,2–0,6 co 1,6 s. Plac bez zmian (Cmd+S niepotrzebny), kod w Studio zgodny z dyskiem i parsuje się. Testy: TESTY → „Bariery na skraju mapy — 09.11”.

## 09.11 (wieczór) — szyby pushem, NIEPRZETESTOWANE

Decyzje Kacpra: F w szybę ją tłucze, pchnięty gracz wylatuje przez okno, bliższe (szyba / gracz / beczka) wygrywa, jedna tafla. `PushService` liczy promienie od HRP serwera (tułów i głowa), szybę na torze pchniętego tłucze tuż przed jego dolotem; nowe `DestructionService.shatterGlass` + `Remotes.GlassFX` (same odłamki, bez wybuchu). Kod w Studio zgodny z dyskiem i parsuje się. Pomiar w Edit: promień sięga 304 z 343 okien; przy parapecie 4 studa (większość) pchnięty rozbija szybę, ale zatrzymuje go murek — wylatuje przez niskie okna. Dźwięk szkła dalej pusty (`GlassSoundId`). Testy: TESTY → „Szyby pushem — 09.11”. Kod tylko w skryptach — Cmd+S niepotrzebny dla tej zmiany.

## 09.11 (później) — drabina zamiast mostu, NIEPRZETESTOWANE, Cmd+S wymagany

Na prośbę Kacpra item mostu (`bridge_builder`, id bez zmian ze względu na zapisy) stawia **drabinę**: pochyloną o 75°, 16 studów, z fizyką jak most — oparta o ścianę stoi, bez oparcia przewraca się do przodu, a nad przepaścią kładzie jak most (decyzje Kacpra). Wspólny wzór ustawienia `LadderPlacement` (duch + serwer): ściana przed drabiną cofa stopę, aż wierzch się oprze. Pomiar w Edit na mapie (obserwacja, nie test): pochylenie, wysokość 15,6 i strona szczebli zgodne; potem 125 ścian z całej mapy × 2 odległości stopy = 250 ustawień, tymczasowe kopie usunięte. Pierwsza wersja (1 promień) zostawiała szynę w słupach i gzymsach → 6 promieni (środek i pod szynami, wzdłuż spodu i wierzchu), do 3 cofnięć, cofnięta stopa siada na krawężniku. Wynik końcowy: **234/250 bez nachodzeń**, wierzch oparty o coś w 156, koszt 0,011 ms. Zostało 16 przy nietypowej geometrii (balkony/dachy budynków ×10, fundament ×2, niewidzialna ściana na skraju mapy ×2, latarnia ×2) — tam część drabiny nie zderza się z tym jednym elementem (NoCollisionConstraint ze spawnu), reszta działa. Modele przez MCP: `ReplicatedStorage.Ladder`, `LadderTool` (dłoń + ikona z modelu), wystawa na kołkach blueprintu; stary blueprint z wystawy w `ServerStorage.RetiredItems`. Napis SHOP widać z 300 studów (było 90). Testy: TESTY → „Drabina zamiast mostu + napis SHOP — 09.11”.

## 09.11 — detonator C4 jako podpowiedź klawisza, NIEPRZETESTOWANE, Cmd+S wymagany

Na prośbę Kacpra czerwony przycisk DETONATE zastąpiła podpowiedź sterowania: biały cieniowany klawisz „G”, obok DETONATE i żółte „x3” (decyzje Kacpra: tylko PC, trochę niżej niż wcześniej, licznik za napisem, klawisz wciska się przy G). Telefon dostał okrągły czarny DETONATE w stylu SPRINT przy skoku (wcześniej używał czerwonego przycisku, który teraz jest tylko na PC). UI postawione przez MCP w Edit, kod (`C4Controller`, `TouchControlsController.nudge`, `Config.C4`) zgodny ze Studio i parsuje się. Kacper obejrzał detonator: „no spoko”. Potem: paski odnowienia grubszy obrys 3, zaokrąglone, cieniowane, niżej (Y 0,68); **sceny sklepu i przymierzalni przeniesione pod mapę** o (−350, −300, 0) razem z 11 luźnymi partami pokoi (STUDIO_CONTRACT → „Sklep-NPC i scena”). Reszta nietestowana w Play. Po teście Kacpra dwie poprawki: (1) kamera sklepu stała w miejscu z błędem `ShopController:155` — zmiana sortowania z 07.11 usunęła środek itemu, którego używa krążenie kamery; przywrócony, sortowanie po cenie bez zmian; (2) w sklepie był filtr „pod lawą”, bo kamera była pod taflą — próg `Config.Lava.Submerged.FloorY` (−50). Testy: TESTY → „Detonator C4, paski odnowienia, sceny pod mapą — 09.11”.

## 06.11 — punkt wznowienia (dzień premiery)

> ⚠️ **Stan z 06.11, przed terminem premiery — nieaktualizowany.** Kacper 13.11: termin minął, gra **nie jest jeszcze opublikowana**, nowej daty brak. Lista kroków poniżej jest wciąż w zasadzie aktualna (testy, ustawienia produkcyjne, publikacja), ale zrobione od 06.11 rzeczy są w sekcjach wyżej.

**06.11 — SPECTATE:** na zlecenie Kacpra dodano obserwowanie żywych uczestników z lobby: przycisk pod SKIP, poprzedni/następny, nazwa i X; natywna kamera Custom z obrotem. Serwer publikuje RoundParticipant, klient zarządza kamerą i blokadą ruchu. Kacper jawnie pozwolił agentowi samodzielnie uruchamiać/testować Play przy tym zadaniu (wyjątek od dotychczasowej zasady) i użyć subagentów. Test solo: start, oznaczenie uczestnika, ukrycie przycisku na mapie, powrót do lobby/NO PLAYERS; kontrolowany test klienta z dwoma zastępczymi celami: 18 asercji zaliczonych, również kliknięcia Open/Next. Naprawiono oddawanie CameraSubject przy otwarciu samego katalogu kosmetyków. Pełny multiplayer i fizyczny obrót myszą/dotykiem pozostają niepotwierdzone: narzędzie ruchu myszy raportowało Delta=0 (także na zwykłej kamerze), a sterowanie oknem Studio do wielu klientów miało timeout. Build i składnia przeszły. Testowe obiekty usunięte przez zakończenie Play; UI w Edit wymaga Cmd+S. Bez publikacji i commita. Szczegóły testów: TESTY → Spectate.

**06.11 — późniejsze potwierdzenie SKIP:** Kacper: „skip już działa”. Zakres wykonanych przypadków nie został wyszczególniony, więc nie zaliczamy automatycznie całej checklisty. Dodatkowy przegląd kodu: wybór rundy, brak nagrody za przetrwanie dla pomijających, dostęp do sklepów/loadoutu, respawn i cleanup. Odczyt Studio w Edit: 14 powiązanych modułów zgodnych z dyskiem i poprawnych składniowo; `SkipButton` ma `Fill`, `Label`, `Pop`, HUD ma `ResetOnSpawn=false`. Nie uruchamiano Play; przypadki z dwoma graczami i opóźnioną siecią nie zostały w tej kontroli zweryfikowane. Poniższe wcześniejsze oznaczenia SKIP jako całkowicie nieprzetestowanego zastępuje to potwierdzenie.

**Gdzie jesteśmy:** praca 05–06.11 poszła w sklep i pomijanie rundy. Ocena Kacpra po obejrzeniu: światło „git jest”, panel „takto spoko całkiem” i „no może być”. To ocena wyglądu, nie zaliczenie listy z TESTY. Logika pomijania rundy i pełna runda po dzisiejszych zmianach nie mają wyniku testu.

**Git:** kod i dokumentacja z 05–06.11 są w commicie po `f166687` na `main`, wypchniętym na `origin/main` na prośbę Kacpra, przed jego testem w Play, więc commit nie oznacza działania. Plac zapisuje się osobno przez Cmd+S. Kolejne commity tylko na prośbę, pliki dodawać jawnie.

**Plac:** odczyt 06.11 po restarcie Studio potwierdził zapis: arsenał, brak `ShopLights` i pyłu, `Panel.LavaPool`, `Panel.Dots`, `BuyButton.Sweep`, `RoundTimer.SkipButton`. Mini ramka `SkipButton.Fill` powstała po tym odczycie, więc jej Cmd+S jest niepotwierdzony. Kod w Studio zgodny z dyskiem (suma i parsowanie, ostatnio dla `Config` i `RoundSkipController`).

**Kolejność do premiery:**
1. Kacper: Cmd+S i test w Play: zwykła runda, SKIP z dwoma graczami, sklep, animacja F, kliknięcia po zmianie itemu (hak → napój, napój → RPG). Listy w [TESTY](TESTY.md).
2. Poprawki ze zgłoszeń, commit i push na prośbę.
3. Ustawienia produkcyjne i usunięcie tymczasowych logów: [DO_RELEASE](DO_RELEASE.md) → „Tuż przed publikacją”.
4. Test z kilkoma osobami na prawdziwym serwerze, także telefony.
5. Publikacja po akceptacji Kacpra.

Otwarte poza tą listą: dźwięki (ID poda Kacper), anty-cheat paczka 6 (niezrobiona; agent radził po premierze, decyzja Kacpra otwarta), limit graczy w ustawieniach miejsca.

**06.11 — pomijanie rundy, NIEPRZETESTOWANE, Cmd+S wymagany** *(UI przebudowany 09.11 na kwadratowy przycisk SKIP ROUND / JOIN ROUND po lewej od hotbara)*: mini ramka SKIP pod licznikiem, po kliknięciu czerwone DON'T SKIP (decyzja Kacpra: przycisk zamiast pola startu, przełącznik do odkliknięcia). Pomijający stoi w lobby, nie zarabia, sklep, ekwipunek i kosmetyki działają mu przez całą rundę; gdy pomijają wszyscy, lobby odlicza od nowa. Opis: ARCHITECTURE → `RoundSkipService`; testy: TESTY → „Pomijanie rundy” (runda z pomijającym wymaga dwóch graczy).

**05.11 — tło sklepu: arsenał, NIEPRZETESTOWANE, Cmd+S wymagany:** brązowe listwy i ladę (`Decorations.Workshop`) zastąpił wojskowy magazyn `WeaponShopScene.Arsenal` (oliwkowe panele ze studsami, stalowe słupy, tablice za itemami, stalowa lada ze skrzyniami), decyzje Kacpra w jednej turze. Itemy nieruszone (pozycje sprawdzone odczytem), każdy dostał uchwyt, żeby nie lewitował. Zrzuty z Edit obejrzane, w grze jeszcze nie. **06.11 światło:** stare `ShopLights` usunięte, kontrast robią lampki nad itemami: tablica i item jasne, reszta ściany ciemna; słabe oświetlenie z góry trzyma widoczną podłogę, `Config.Shop.SceneAmbient` neutralne zamiast brązowego. Blat lady ciemna stal. **06.11 panel, NIEPRZETESTOWANE:** nowy `ShopFx`: wjazd panelu, reakcje przycisków, przejście przy zmianie itemu, efekt zakupu i błędu, wibracje, połysk BUY, 6 małych kropek nad ramką, płynący pas lawy na dole panelu; kamera lekko krąży za myszą. Dźwięki przygotowane, ale puste: ID poda Kacper (`Config.Shop.Fx.Feedback`). Opis: STUDIO_CONTRACT → „WeaponShopScene”; testy: TESTY → „arsenał”.

## TEST 31.10 — punkt wznowienia

Sesja testowa Kacpra: 4 rundy w Play, logi bez błędów naszego kodu (szum toolboxowego ragdolla, przestarzałych collision groups i asset `203785492` spoza placu — do zignorowania). **git:** kod z 31.10 w `8bcbb6f`, zmiany 01–03.11 w commicie po nim, wszystko na `main` i wypchnięte na `origin/main`; to podsumowanie dokumentacji — osobno, po nim.

**Sprawdzone przez Kacpra w Play:**
- **Zawalone piętra lecą dużymi bryłami** („spoko”). Przyczyna znikania: pass kikutów (`StructuralService.unsupportedStrips`) liczył chunk `Falling` jako martwy, więc kruszenie tuż po planie oddawało klientom całe górne piętra jako drobnicę, zanim ich grupa wystartowała (log: 25 grup `bez kawałków`). Teraz chunk `Falling` należy do swojej grupy. Po poprawce kolaps GreenBuilding: grupy po 14–21 kawałków; ~15 z 24 grup idzie ponad budżet (`MaxCost` 100) do klientów — budżetu nie ruszano.
- **Leżący gruz tnie się od RPG** („lepiej to wygląda”): osobny próg `Config.Structure.Damage.RubbleHoleThreshold` = 70 (RPG tnie z ~7 studów, dziura 2× szersza; C4 ~13). Wcześniej próg ściany 100 → RPG tylko budził bryłę. Przestrzelona bryła dzieli się na osobne (`CollapseService.splitApart`; decyzja „obie połówki odskakują”).
- **F nie pcha z RPG** („rpg git”). Potem decyzja: **F (pchnięcie i beczka) tylko z pustymi rękami** — `Config.Push.BlockWithToolInHand`, klient + serwer, PUSH na telefonie znika. Wersja „każdy item” jeszcze niesprawdzona.
- **Róg murku**: kolizja HRP przywrócona poza ragdollem i śmiercią (`MovementController.syncRootCollision`, tylko klient; toolbox ragdolla wyłączał ją w ragdollserver:245). Test A/B komendą: „git lepie”; wersja w kodzie niesprawdzona.

**Wdrożone, niesprawdzone:** więcej małego gruzu zostaje (`KeepSmallRubbleChance` 0,25 → 0,67).

**Otwarte:** napój — „klik pić → od razu inny item = nie wypije”. Serwer zalicza łyk przy kliknięciu, zwykły łyk działa (0,03 s), przyczyna nieustalona. Tymczasowe logi `[EnergyDrink] klik: …`, `puszka w ręce/schowana` i odmowy łyku na serwerze — usunąć po rozstrzygnięciu.

**02.11 po teście Kacpra — kliknięcia itemów, NIEPRZETESTOWANE:** `Utils.holdTool` (niżej) NIE pomogło: log 02.11 — hak → napój: `puszka w ręce` → zero linii `[EnergyDrink] klik` → `schowana` (2 z 2 razy). Ten sam błąd silnika zmierzono już 25.10 przy C4 (RPG → C4: klik dochodzi do świata, Tool w ręce, `Tool.Activated` nie przychodzi aż do ponownego wyciągnięcia) — C4 dostał wtedy obejście, reszta itemów nie. Poprawka: `ToolActivation` czyta klik na PC wprost z myszy (LPM / R2) dla WSZYSTKICH itemów, Activated zostaje dla dotyku, jeden klik = jedno użycie (dedup 0,1 s). Telefon bez tego obejścia — do sprawdzenia. Zsynchronizowane i parsuje się (odczyt Edit). `holdTool` zostaje jako porządek (nigdy dwa itemy w ręce). Tymczasowe logi `[Rpg] klik` / `[EnergyDrink] klik` — usunąć po teście.

**02.11 — hak zawsze strzela, NIEPRZETESTOWANE:** zgłoszenie „ktoś może klikać i nie wie o co chodzi”. Teraz klik poza zasięgiem, w niebo albo w coś nie do złapania = pudło: lina wylatuje jak najdalej (do 70 studów albo do przeszkody) i szybko się zwija, u wszystkich graczy (`Remotes.GrappleMiss`). Decyzje Kacpra: pudło nie zabiera sztuki, postać stoi. Klik w budynek dalej niż 70 zaczepia o to, co stoi na tej linii w zasięgu. Pasek odnowienia także po pudle. Zsynchronizowane i parsuje się (odczyt Edit).

**Wdrożone 02.11 (porządek, nie przyczyna):** RPG — „napiję się energy drinka i od razu RPG = nie strzela”. Log z Play 01.11 22:48: `[Rpg] … wyrzutnia w ręce` (serwer, 25.516) → `puszka schowana` (klient, 25.550) → **zero linii `[Rpg] klik`**, czyli `Tool.Activated` wyrzutni w ogóle nie odpala (to nie odmowa klienta ani serwera; winieta napoju i `Speedlines` mają `Active=false`, nie łapią kliknięć — sprawdzone w Edit 02.11). Przyczyna (hipoteza, niesprawdzona w Play): przy zmianie itemu serwer mógł dać nowy Tool, ZANIM serwis starego go zabrał (każdy serwis ma własny handler `EquipItem`, kolejność nie jest gwarantowana) → przez chwilę dwa Toole w postaci. Poprawka (decyzja Kacpra 02.11): **`Utils.holdTool`** — jedno miejsce, które przed podaniem itemu niszczy każdy inny Tool itemu w postaci; wszystkie 6 serwisów itemów woła je zamiast `tool.Parent = char` (w `C4Service` jedna linia). Po Disconnect → Connect w Rojo (wtyczka wcześniej nie nakładała zmian) wszystkie 7 plików zgodne z dyskiem (suma) i parsują się (odczyt Edit 02.11). Tymczasowe logi `[Rpg] klik: …`, `wyrzutnia w ręce` i odmowy strzału na serwerze (`RpgController`, `RpgService`) — usunąć po teście. Testy: [TESTY](TESTY.md) → „Napój → od razu RPG” i „Szybkie przełączanie”.

**Logi zostające (Debug):** `[Destr] … rumowisko cięte=X/Y (najbliżej D)` i strażnik `[Collapse] … bez kawałków — pomijam` (w rundach 3–4 zero takich linii).

Następny test: [TESTY](TESTY.md) → „31.10” (napój, F z każdym itemem, róg murku bez komendy, regresje ragdoll/drabina/hak/most).

**03.11 — napisy SHOP / COSMETICS, NIEPRZETESTOWANE, Cmd+S wymagany:** COSMETICS ma rozmiar SHOP i kolory przycisku COSMETICS z HUD (fiolet/niebieski, płynący gradient). Oba napisy znikają za ścianami — kod (`LobbySign`, promień kamera → napis), bo samo `AlwaysOnTop = false` dawało dach straganu obcinający litery (pomiar w Edit). Kod SHOP przeniesiony do tego samego pomocnika. 4 pliki zsynchronizowane i parsują się; bez zrzutu. Testy: [TESTY](TESTY.md) → „Napisy SHOP i COSMETICS”.

**03.11 — ekran ładowania i lina haka, NIEPRZETESTOWANE:** „ESCAPE LAVA” przestaje przeskakiwać — przyczyna zmierzona w Edit: Roblox rysuje tekst tylko w całych rozmiarach fontu (przy +2,5% szerokość 624 → 626 → 636 px), a korekta pozycji szła w całych pikselach, więc „oddychanie” skalą było widać jako skoki. Napis już nie rośnie, buja się jak dotąd; oddycha jasność obrysu. Obrys = płynąca lawa (UIGradient na klonie obrysu, kolory z szumu; najgorętszy (205, 45, 0) ciemniejszy od „LAVA”). Lina haka 0,12 → 0,2 (`Config.Grapple.RopeThickness`). Zsynchronizowane i parsuje się (odczyt Edit); bez zrzutu. Testy: [TESTY](TESTY.md) → „Tytuł ekranu ładowania”.

## WIEŻA MAGA — poprawki 02.11 (MCP, Cmd+S wymagany, bez zrzutów)

`Workspace.WizardTower`: 4 luźne świece z `Interior.Hall` wisiały 12–13 studów nad podłogą w studni schodów → przeniesione na stopnie pod nimi (r 5,9 od osi, przy wewnętrznej poręczy), każda na podstawku `CandleDish`. Waga na `Interior.WizardRoom.Counter` przebudowana na szalkową (20 części `Scale*`, belka przechylona 8°, odważnik na niższej szalce), 3 butelki przesunięte o 0,5 wzdłuż blatu; stara waga w `ServerStorage.WizardScale_Backup_0211`. Żyrandol `Interior.Hall.Chandelier` (= „lampa na schodach bez zaczepienia”, potwierdzone przez Kacpra i zrzutem): **prawdziwa przyczyna — błąd generatora wieży: walce z długością w osi Z** (`Cylinder` w Robloxie ma długość tylko w osi X, średnica = min(Y, Z)), więc druty piasta→pierścień rysowały się jako krążki 0,15 i pierścień wisiał w powietrzu. Druty przestawione na pręty (długość w X, gr. 0,2), 8 zamiast 4; fioletowa kula `Orb` podwieszona na pręcie `OrbRod` z nakładką `OrbCap`; łańcuch 0,35 z kołnierzem `ChainCollar` pod guzem `Floors.HallCeiling.Boss`, piasta 0,95. Ten sam błąd miały 32 płaskie części biurka i szyldu (okładka i strony książki, bieżnik, pióro, emblematy, gwiazdki, szyjki kolb) — zmienione na `Block`, wymiary bez zmian; po poprawce 0 takich walców w `WizardTower`. ⚠️ Przy kolejnych modelach z generatora sprawdzać `Cylinder` z Y ≠ Z.

**02.11 wieczorem — wieża na wzniesieniu (Kacper przeniósł ją sam):** kamienna ścieżka od podnóża do drzwi (dwa biegi schodów, podest, murki, 8 fioletowych latarenek), lekka mgła z cząsteczek wokół wieży i wzdłuż schodów, a w kodzie `TowerAmbienceController` — obraz lekko ciemnieje i chłodnieje tylko w promieniu ~40–75 studów od wieży (u gracza, płynnie). Opis w STUDIO_CONTRACT („Wieża maga — otoczenie”) i ARCHITECTURE. Zrzuty z Edit obejrzane (schody, latarnie po przygaszeniu, mgła po ręcznym `Emit`). Kod na dysku; sesja Play Kacpra z 02.11 wystartowała PRZED synchronizacją (na serwerze brak modułu) — przyciemnienie sprawdzić w nowym Play. Cmd+S wymagany.

**03.11 — poprawki Kacpra:** schody szersze (8) i nieregularne (kamienie o różnej wysokości/wysunięciu/skręcie, poszarpane brzegi, murki różnej wysokości z czapami, głazy), mgła ~2× gęstsza, a przy wieży u gracza ciemnieje też niebo (ekspozycja −0,55 + lokalna Atmosphere, usuwana po odejściu). Wartości atmosfery dobrane na podglądzie w Edit (pełna siła: ciemne fioletowe niebo, wieża czytelna); podgląd zdjęty, Lighting placu przywrócony (Exposure 0, brak Atmosphere). 3 pliki zsynchronizowane i parsują się. Play nietestowany, Cmd+S wymagany. **Potem 03.11 („słońce dalej razi”):** przy wieży tarcza słońca maleje do 0 i gaśnie `SunRays` (podgląd w Edit: ciemne fioletowe niebo bez tarczy i blasku; Lighting placu przywrócony — Exposure 0, SunAngularSize 21, SunRays 0,2, brak Atmosphere). Wszystkie lampy wieży dotykają czegoś poza sobą (odczyt).

## TELEFON — punkt wznowienia 28.10.2026 (premiera 6.11)

**02.11 — loadout palcem, NIEPRZETESTOWANE:** zgłoszenie „przeciągam item na slota, klinuje się i zostaje tam”; log Play bez błędu z `InventoryController`, czyli koniec dotyku nie dochodził przez `UserInputService.InputEnded` (podejrzenie: karty leżą w przewijanym `Card.Shelf.Grid`, które przejmuje dotyk). Poprawka: koniec dotyku łapany też ze stanu samego obiektu dotyku (End/Cancel), drugi palec nie podmienia przeciągania, lista nie przewija się pod przeciąganą kartą. Plik w Studio zgodny z dyskiem (suma) i parsuje się (odczyt Edit 02.11). Testy: [TESTY](TESTY.md) → „Telefon” → „Loadout palcem”.

Przyciski dotykowe wdrożone według decyzji Kacpra z 28.10 (plan: [ROADMAP](ROADMAP.md) → „Sterowanie na telefonie”). Okrągłe przyciski w stylu slotów przy skoku Robloxa: **SPRINT** (trzymanie), **PUSH**, w trybie mostu **BUILD/ROTATE** (dotknij miejsce → duch staje, BUILD stawia), z RPG **AIM** (przełącznik) i **FIRE**. Bomba, hak, napój i C4 już wcześniej działały dotknięciem ekranu. Nowy `TouchControlsController` + podpięcia w Movement/Push/Bridge/Rpg, bez zmian na serwerze. `HUD.TouchControls` postawiony przez MCP, `HUD.Detonator` przesunięty z Y 0,55 na 0,40 (zwolnił miejsce nad skokiem). 7 plików zsynchronizowanych z Studio (suma zgodna z dyskiem) i parsuje się; zrzut układu z atrapą skoku: `artifacts/touch/touch_controls_preview_2810.jpg`. **Play nietestowany, Cmd+S wymagany.** Testy: [TESTY](TESTY.md) → „Telefon”.

## Gra obecnie

`LOBBY → PREPARING → COUNTDOWN → ROUND → FINISHING → RESETTING → LOBBY` (26.10: bez POST_ROUND — po zasłonie od razu lobby; NIEPRZETESTOWANE).

Lobby **25 s**, w nim przycisk **SKIP ROUND** po lewej od hotbara (`HUD.RoundSkip.SkipButton`, od 09.11; po kliknięciu JOIN ROUND): kto go kliknie, zostaje w lobby na kolejne rundy; przygotowanie i teleport pod zasłoną; **3-2-1** na mapie z blokadą ruchu/itemów; runda z płynnie przyspieszającą lawą, **bez faz**; **3 s FINISHING**, wypłata ocalałym, zasłona i cleanup/odbudowa, potem **od razu lobby** (10 s „ROUND OVER” w lobby usunięte 26.10). Produkcyjny cel rundy: **80 s**, obecnie **240 s testowo**.

Kod zawiera **7 itemów**: Bomb 50$, Bridge 100$ (od 09.11 stawia drabinę, id `bridge_builder` bez zmian), Grapple 40$, Energy Drink 25$, RPG 75$, **Bandage 40$**, **C4 60$** (25.10 — C4 = zaplanowana sticky bomb, decyzja Kacpra; przyklejanie, G i rzut z ikoną zadziałały w testach; 25.10 wieczorem wysoki łuk jak granat + zamach ręki — NIEPRZETESTOWANE; `ReplicatedStorage.C4` i `HUD.Detonator.DetonateButton` postawione przez MCP). Loadout to **3 stałe sloty**, ekwipunek jest dostępny wyłącznie w lobby, a pomijającemu rundę także w jej trakcie. Nowy item nie wymaga czwartego slotu.

Destrukcja v4 obejmuje **wszystkie 10 budynków**; starszy pass podparcia działa poza nimi. Fizyka dużych brył zostaje. **Gruz nie zadaje obrażeń**; lokalne odłamki nie mają kolizji ani wpływu na promienie. Obrażenia od upadku pozostają. Jeden profil `Config.Graphics.Profile`, bez trybów Potato/Full i ich panelu.

Nagrody: przetrwanie 100$, kill 25$, pickup 10$, kasa startowa 100$. Wybuchy bomby/RPG/auta/beczki ranią także odpalającego; samobójstwo nie daje nagrody. Rocket jump wycofany 21.10 — nie jest zadaniem do zrobienia.

## Potwierdzone w dotychczasowych testach Kacpra

- Sklep-NPC i spawn w lobby (wcześniejsza wersja sklepu), rig R15 na Motor6D i ragdoll, zapis kasy w Studio.
- Hak po łuku, kamera zza prawego ramienia bez x-ray i head tracking (22–23.09).
- Poprawki 25–26.09: kolaps fizyką, brak taśmociągu, respawn po śmierci, hak w ragdollu, próba 5 wybuchów (26.09).
- Tory, pasek staminy po śmierci, ragdoll/ruch głowy i **5 zaległych przypadków fall damage** (01.10, zaznaczone w TESTY).
- Drabiny, gęsta lawa, mosty i ghost, jeden profil grafiki (10.10).
- Ramka slotu (10.10), ikony v2 pierwszych trzech itemów (19.10), szybkie wyjście z Play (20.10).

Te potwierdzenia dotyczą wskazanych wersji. Nie zaliczają automatycznie późniejszych zmian ani całej obecnej gry.

## Zaimplementowane, pełna akceptacja pozostaje otwarta

Listy przypadków są w [TESTY](TESTY.md); nie oznaczać ich jako zaliczonych na podstawie kompilacji lub odczytu Edit.

- Destrukcja całego miasta, zaklinowania, osierocone dekoracje, twarde ruiny, auta; stały test **T1–T7 dwa razy pod rząd** nadal nie ma zapisanego kompletu zaliczeń.
- Start klienta z `ClientReady` (18.10), zapis/loadout i obsługa panelu Inventory, hotbar ze stałymi slotami, pełny przebieg rundy i ekran ładowania v2.
- RPG i odrzut, energy drink i gest picia, wyciąganie itemów, chwyt RPG oburącz i poprawki jego ułożenia (20–21.10).
- **RPG celowanie na PPM (24.10)**: zoom, ciało i tułów w stronę celu, celownik `HUD.Crosshair` (postawiony przez MCP, wygląd zaakceptowany na zrzucie; zapis Cmd+S niepotwierdzony — sprawdzić, czy jest w placu), chód wolniej bez sprintu. Kod zsynchronizowany z Studio i parsuje się (odczyt Edit); w Play nietestowane. **25.10**: RPG na prawym barku (nowa poza rąk z IK + tułów bokiem −50°), lufa w kierunku lotu rakiety, rakieta startuje z lufy (`Rpg.MuzzleSide` 1,0), pochylenie całe na talii, mocniejszy zoom (FOV −18, PushIn 3) — NIEPRZETESTOWANE.
- Beczki wybuchowe, zapłon od F, łańcuchy i wybuch przy upadku (21.10).
- Nowy panel sklepu i automatyczne kadry; **23.10** wydłużona ściana/pokój, przesunięta wystawa, kąt kamery yaw 20° / pitch 12°, następnie ruchomą lampę zastąpiły stałe `ShopLights` (po jednej nad sześcioma modelami plus doświetlenie skrajów; 06.11 usunięte na rzecz lampek arsenału). Najnowszy kod przy zamknięciu sklepu po respawnie przypina kamerę do aktualnego Humanoida; test pozostaje otwarty. **25.10** panel `ShopUI` przebudowany przez MCP (węższy, ciemne strzałki przy panelu, cena nad BUY, bez kasy w nagłówku) — zrzut z Edit pokazany, ocena Kacpra i zapis Cmd+S niepotwierdzone; kopia starej wersji w `ServerStorage.ShopUI_Backup_2510`.
- **Panel ustawień (26.10)**: zębatka pod INVENTORY (zawsze widoczna) otwiera panel SETTINGS z dwiema opcjami — kamera nad prawym/lewym ramieniem i włącz/wyłącz przechył kamery + zmiany FOV; zapis na koncie gracza (`SettingsService`). Zębatka i panel postawione przez MCP (zapis Cmd+S niepotwierdzony), kod zsynchronizowany i parsuje się (odczyt Edit); w Play nietestowane. Oprawa lawy wstrzymana na rzecz panelu — decyzje w ROADMAP.
- **GRAPHICS LOW / HIGH + oprawa lawy (27.10)**: trzeci wiersz panelu ustawień (postawiony przez MCP, Cmd+S niepotwierdzony); start: telefon LOW, komputer HIGH. Na HIGH: łuna na ścianach tuż nad lawą, iskry i popiół rosnące z lawą, rozbryzg przy wpadnięciu (`LavaSplashController`). Tylko u klienta, bez kolizji. Kod zsynchronizowany i parsuje się (odczyt Edit); w Play nietestowane. Plan: ROADMAP.
- Oprawa lawy: fala lokalnej siatki i FX v5; zachowanie na urządzeniach i FPS nadal do sprawdzenia. Odczyt działania siatki w sesji 12.10 nie jest akceptacją wyglądu/FPS.

## Braki potwierdzone w kodzie / placu

- **Telefon:** 28.10 przyciski SPRINT/PUSH/BUILD/ROTATE/AIM/FIRE wdrożone (sekcja TELEFON na górze) — czekają na test Play na emulatorze i prawdziwym telefonie.
- **Anty-cheat:** obecny pomiar poziomy co 2 s, limit sprint +8, kara po 3 przekroczeniach. Pojedynczy teleport i lot w pionie nie są pokryte. Plan paczki 6 ma zamknięte decyzje: cofnięcie → powtarzane naruszenia: kill → kick, pion po ~1 s; potrzebuje wyjątków dla legalnej fizyki.
- **Skala:** spawn postaci nadal sekwencyjny; HeadAim od 02.11 tylko do graczy w promieniu 150 studów (kod, nietestowane — TESTY → „Ruch głowy”); bootstrap serwera bez izolacji błędów `init`. Odbudowa tylko naruszonych jednostek już istnieje, jej koszt wymaga testu.
- **Spawny rundy (02.11):** `Map.Locked.SpawnPoints` ma 6 punktów na chodnikach wokół basenów lawy (4 stare ze środka usunięte), lobby — 4 punkty w `Lobby.SpawnPoints` losowane przy każdym powrocie (nowy kod `PlayerService`; MCP, Cmd+S wymagany; szczegóły w STUDIO_CONTRACT). ⚠️ 02.11 wieczorem `rojo serve` nie działał — kod lobby i HeadAim był tylko na dysku. Przy więcej graczy niż punktów kilku dostaje ten sam punkt. Docelową liczbę graczy trzeba ustalić przed testem większej grupy. `Config.Game.MaxPlayers = 20` nie ustawia limitu miejsca Roblox; limit publikowanego serwera pozostaje do sprawdzenia.
- **Studio 23.10:** brak zapisanych modułów w `ServerStorage.StructureData` (0 dzieci/brak folderu); analiza budynków nadal wykonywana w grze. Przed bake sprawdzić zaokrąglenia i walidację rewizji.
- **Animacja F:** 05.11 opublikowana na koncie właściciela gry (`Config.Push.AnimationId = 128117097694041`, moderacja Approved), podgląd Studio wyłączony. Odtwarzanie w Play NIEPRZETESTOWANE; sama mechanika pchnięcia jest osobna.
- **Audio:** 5 pustych ID destrukcji, brak dźwięku strzału RPG, 4 puste ID panelu sklepu (`Config.Shop.Fx.Feedback`, ID poda Kacper); łyk opcjonalny.
- **Hak pod nogi:** 26.10 serwer ocenia gotowy łuk przed zużyciem, z tym samym minimalnym czasem co klient. Zmiana i pozostałe poprawki po pełnym przeglądzie czekają na Play — patrz [raport](CODE_REVIEW_2026-10-26.md).
- **Dev:** uprawnienia nadal po nicku. Przejście na UserId pozostaje otwarte; przed wydaniem dev musi być wyłączony.

## Stan repo i Studio

**27.10 — import dyni zakończony:** `ReplicatedStorage.Cosmetics.HalloweenPumpkin` zawiera 4 MeshParty i HatAttachment (0,0.445,0) względem Handle, 3 weldy, prawidłowe kolory, brak kolizji/masy i SmoothPlastic. Rozmiar ok. 1.90 × 1.91 × 1.92 studa. Mocowanie obejrzane na nieruchomej kopii StarterCharacter w Edit; kopia podglądu usunięta. Oryginał importu zachowany w `ServerStorage.HalloweenPumpkin_Imported_2710`. Cena 500, katalog i zakup korzystają z istniejącej definicji. Kamizelka i plecak czekają na import użytkownika; Play i zapis Cmd+S niepotwierdzone.

**27.10 — uproszczenie COSMETICS na prośbę Kacpra:** usunięto Wallet, napis ESCAPE LAVA / THE CLOSET, zakładki i etykiety kategorii. Wszystkie produkty we wspólnym katalogu (garderoba nadal tylko posiadane). Sam licznik kasy po lewej, poniżej kontrolek Robloxa; główny tytuł wyśrodkowany. Kategorie wyposażenia i zapis pozostają bez zmian. Kopia UI: `ServerStorage.CosmeticsUI_v2_2710`; skrypt zmiany: `artifacts/cosmetics/simplify_ui.luau`. Build i kontrola Edit, bez testu Play. Wymagany Cmd+S.

**26.10 — poprawka wyglądu COSMETICS:** po odrzuceniu pierwszego małego panelu przebudowano sklep na pełny ekran, dodano bezpośrednie zakładki kategorii i większą asymetryczną wystawę. X jest kopią przycisku Inventory. Układ obejrzany w Edit, bez Play; import modeli nadal pozostaje otwarty. Szczegóły w [planie](COSMETICS_PLAN.md).

**26.10 — COSMETICS:** przygotowano kod sklepu/garderoby, zapis własności i stroju, bezpieczny zakup, lokalną przebieralnię i katalog. Po osobnej zgodzie Kacpra postawiono UI, przycisk pod Inventory i napis nad ClothesShop.NPC; układ obejrzano w Edit. **Brakuje importu trzech FBX** — kafelki pokazują COMING SOON, zakup niedostępnego modelu jest blokowany. Ceny 500/750/600 zaakceptowane. [Plan i realizacja](COSMETICS_PLAN.md), [kontrakt](STUDIO_CONTRACT.md), testy w TESTY. Potrzebny Cmd+S; bez Play i publikacji.

**27.10 — ikony itemów v3:** wszystkie 6 ikon wyrenderowane od nowa z modeli bez studsów (te same ujęcia, światło i obrys co v2), wgrane i podpięte w `ItemDefinitions`; pliki i ID w `output/inventory-icons-v3/README.txt`. Studio zdjęciowe usunięte, ustawienia przywrócone. Play nietestowany.

**26.10 — wygląd modeli itemów:** Studs usunięte tylko z 156 części modeli itemów w ReplicatedStorage i na wystawie. Wygląd otoczenia przywrócony na podstawie historii Studio. Zakres: [kontrakt Studio](STUDIO_CONTRACT.md). Potrzebny zapis Cmd+S; publikacji nie potwierdzono.

**25.10 — częściowy przegląd itemów:** wdrożone optymalizacje gestów i filtrów lotu C4 oraz poprawki walidacji/loadoutu/przełączania. Zakres, weryfikacja Edit i propozycje dalszych porządków: [raport przeglądu](ITEM_REVIEW_2026-10-25.md). Play pozostaje otwarte w [TESTY](TESTY.md); nie traktować tej kontroli jako akceptacji rozgrywki.

**26.10 — pełny przegląd kodu:** przejrzane całe `src/` i 9 narzędzi korzenia; poprawki i porządki w 33 plikach src oraz 2 narzędziach. Pokrycie, kontrola składni/synchronizacji i pozostawione ryzyka: [pełny raport](CODE_REVIEW_2026-10-26.md). Testy Play i pomiary wydajności pozostają otwarte.

**28.10 — git:** cała praca 21–27.10 (C4, COSMETICS, ustawienia, GRAPHICS LOW/HIGH i oprawa lawy, przegląd kodu, dokumentacja) zacommitowana na `main` i wypchnięta na `origin/main` (na prośbę Kacpra). Nadal NIEPRZETESTOWANE w Play. Lokalna gałąź `marketing/kampania-2` została na `0d6c63c` (bez własnych commitów).

Studio: `ESCAPE LAVA`, placeId **107369017875577**, Edit. Przy pierwszym odczycie 23.10 sumy `Config` i `ShopController` zgadzały się z dyskiem. W trakcie audytu pojawiły się dalsze robocze zmiany sklepu (stałe ShopLights, CameraSubject po respawnie); pierwszy pomiar nie potwierdza synchronizacji tych nowszych zmian. UI, modele i zmiany sceny wymagają zapisu placu **Cmd+S**; odczyt nie potwierdza zapisu na dysku ani publikacji.

`artifacts/`, `output/`, `.codex/`, główny `AGENTS.md` i `docs/AGENTS.md` były nieśledzone. Nie dodawać ich zbiorczo do commita. **`marketing/` celowo poza gitem: repo `perarz/ESCAPELAVA` jest PUBLICZNE**, a plan kampanii zawiera konta (także te „bez marki”), budżet i creatorów. Commit/push na prośbę Kacpra.

## Kolejność dalszych prac

> ⚠️ **Stan z 06.11, przed terminem premiery — nieaktualizowany.** Kacper 13.11: termin minął, gra **nie jest jeszcze opublikowana**, nowej daty brak. Lista kroków poniżej jest wciąż w zasadzie aktualna (testy, ustawienia produkcyjne, publikacja), ale zrobione od 06.11 rzeczy są w sekcjach wyżej.

Do premiery obowiązuje krótka kolejność z sekcji 06.11 na górze. Poniżej pełna lista.

1. Test Kacpra z TESTY, w tym T1–T7 dwukrotnie; naprawy tylko na podstawie konkretnych zgłoszeń i aktualnego logu.
2. Telefon, anty-cheat i przygotowanie większego serwera; test zapisu/obciążenia na rzeczywistym serwerze.
3. Test łuku i zamachu C4, postawy i zoomu RPG oraz animacji F, poprawka haka, audio i bake.
4. Ustawienia produkcyjne oraz pełny test z ekipą na PC i telefonach. Szczegółowa lista: [DO_RELEASE](DO_RELEASE.md).

To porządek pracy wynikający z istniejącej listy; nie oznacza zatwierdzenia nowego zakresu ani zmiany designu.

## 06.11 — Bandage: implementacja i test Play

Dodany siódmy item: biały zwój z czerwonym krzyżem, wystawa w sklepie, kafelek Inventory i ikona hotbara renderowana z modelu. Cena 40$, leczenie +35 HP po 3 s (maksymalnie MaxHealth). Loadout nadal ma 3 sloty. Gest bandażowania i pasek BANDAGING; można chodzić. Zmiana itemu, ragdoll, śmierć lub koniec rundy przerywają bez zużycia. Serwer rozlicza leczenie i sztukę; klient wyłącznie pokazuje animację.

Za zgodą Kacpra agent wykonał solo Play: 15 asercji integracyjnych zaliczonych na prawdziwych remotes i działających usługach, w tym spam, limit HP i anulowanie. Dane ekwipunku/loadoutu przywrócone przez fixture. Szczegóły i pozostałe testy: TESTY. Nowa poza rąk wymaga jeszcze wizualnej akceptacji w ruchu; test wieloosobowy i telefon pozostają otwarte. Studio wróciło do Edit. Model, wystawa i szablon paska wymagają Cmd+S; bez publikacji i commita.
