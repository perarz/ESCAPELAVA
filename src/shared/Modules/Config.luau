--!strict
-- Config.luau
-- Single source of truth dla WSZYSTKICH liczb w ESCAPE LAVA.
-- Zasada: zero magic numbers w services. Wszystko stąd.

local Config = {}

-- ============================================================================
-- TRYB DEV / TESTOWY (2026-08-12) — skraca pętlę testów destrukcji.
-- ⚠️ `Enabled = false` PRZED LAUNCHEM. Jedna flaga wyłącza wszystko naraz:
-- nieskończone itemy, skipowanie faz i klawisze dev. Nic z tego nie dotyka
-- DataStore — inventory deva jest syntetyczne, prawdziwe dane zostają nietknięte.
-- ============================================================================
Config.Dev = {
	Enabled = true,

	-- Kto dostaje uprawnienia dev NA ŻYWYM SERWERZE (nicki, case-insensitive).
	-- Dopisanie kolejnej osoby = jedna linijka tutaj.
	Usernames = { "PROGGam3r" },
	-- W Studio KAŻDY jest devem (testujesz też jako drugi/trzeci gracz w multi-client).
	AllowInStudio = true,

	-- Nieskończone itemy: hotbar zawsze pełny, rzucanie/budowanie nic nie zużywa,
	-- sklep niepotrzebny. Działa dla WSZYSTKICH itemów z ItemDefinitions.shopOrder.
	InfiniteItems = true,
	InfiniteItemCount = 99, -- ile pokazuje licznik w hotbarze
	-- ⚠️ NIESKOŃCZONE ITEMY DLA **KAŻDEGO**, nie tylko dla nicków z `Usernames`
	-- (prośba Kacpra 2026-09-21 na czas testów z kolegami — inaczej koledzy musieliby
	-- kupować bomby i test mierzyłby ekonomię zamiast mechanik).
	-- ⚠️ Klawisze dev (P/O) tego NIE obejmują — sterowanie rundą zostaje przy `Usernames`,
	-- żeby przypadkowe O nie kończyło rundy wszystkim.
	-- 🔴 WYŁĄCZYĆ PRZED LAUNCHEM razem z `Config.Dev.Enabled`.
	InfiniteItemsForAll = true,

	-- Klawisze (tylko dla devów; zwykły gracz nawet nie podpina listenera).
	--
	-- ⛔ **SKIP NIE MOŻE BYĆ NA `P`** (lekcja 2026-09-21, zgłoszone w trakcie testu:
	-- „kliknąłem kilka razy P i wyłączyło UI, włączył się jakiś freecam"). Roblox Studio
	-- ma WBUDOWANY freecam pod **Shift+P**, który przy okazji chowa cały interfejs.
	-- A u nas **sprint to LeftShift** — więc skipnięcie fazy w biegu trafiało prosto
	-- w skrót Studia. Wychodzi się z tego drugim Shift+P.
	-- ⚠️ Dotyczy TYLKO Studio (na opublikowanym serwerze freecamu nie ma), ale testy
	-- robimy właśnie w Studio, więc kolizja jest realna.
	-- Przy zmianie tych klawiszy sprawdź, czy nie kolidują z: WASD, Space (skok),
	-- LeftShift (sprint), F (push), 1-5 (hotbar), R (obrót mostu), Q (wyjście ze sklepu),
	-- E (ProximityPrompt).
	SkipKey = Enum.KeyCode.K,     -- skip bieżącej fazy/stanu (LOBBY→ROUND w 2 klik)
	EndRoundKey = Enum.KeyCode.O, -- natychmiastowy koniec rundy (restore mapy, nagrody)
}

Config.Game = {
	MinPlayers = 1, -- TODO Day 7: ustaw na 2 przed publishem.
	MaxPlayers = 20,
	LobbyDuration = 15,
	CountdownDuration = 5,
	PostRoundDuration = 10,

	-- ⚠️ WYŁĄCZA DOMYŚLNĄ REGENERACJĘ ŻYCIA (decyzja Kacpra 2026-09-21, razem z lawą
	-- raniącą zamiast zabijającej na miejscu). Roblox wkłada do każdej postaci skrypt
	-- `Health`, który leczy ~1% HP/s — bez jego usunięcia „giniesz po 7 s ŁĄCZNIE"
	-- nie działa, bo krótkie wejścia do lawy zdążyłyby się zaleczyć między wejściami.
	-- ⚠️ To reguła CAŁEJ GRY, nie tylko lawy: obrażenia od upadku, bomby i gruzu też
	-- przestają się goić. W 80-sekundowej rundzie bez apteczek to spójne — ale gdyby
	-- kiedyś doszło leczenie, zacząć od tej flagi.
	DisableHealthRegen = true,
}

Config.Lava = {
	-- WŁĄCZONA z powrotem 2026-09-21 na prośbę Kacpra — oprawa lawy (embery, dym, bąble,
	-- para, światła, poświata) zapala się dopiero, gdy tafla wyjdzie z kanału ponad ulicę
	-- (`FX.MinSurfaceY`), więc przy nierosnącej lawie nie było jej jak zobaczyć.
	Enabled = true,
	StartY = -5,
	MaxY = 250,
	-- DESIGN: szybka i dynamiczna gra. Runda ~80s total, nie 5+ minut.
	--
	-- ⚠️ WYDŁUŻONE DO 10 MINUT NA TESTY (2026-08-12, prośba Kacpra) — długa runda daje
	-- czas na spokojne wysadzanie bez przerywania w połowie. To NIE jest zmiana designu:
	-- wartości produkcyjne to 5/20/20/20/15 = 80s (GDD + zasada "dynamika > kompleksowość").
	-- PRZYWRÓCIĆ PRZED LAUNCHEM. GameLoopService warnuje co boot, dopóki tu jest >180s.
	--
	-- UWAGA przy powrocie do lawy: przy tych czasach i tych prędkościach lawa urosłaby
	-- o ~990 stud i po ~3 minutach siedziałaby na MaxY (250) do końca rundy. Jeśli chcesz
	-- testować rundy Z lawą, trzeba albo zejść z prędkościami, albo podnieść MaxY.
	-- ⚠️ RUNDA 4-MINUTOWA NA TESTY Z LUDŹMI (2026-09-21, prośba Kacpra).
	-- Wartości PRODUKCYJNE to 15/60/60/60/45 → 5/20/20/20/15 (80 s) i prędkości
	-- 0.6 / 1.2 / 2.0 / 3.0. PRZYWRÓCIĆ PRZED LAUNCHEM.
	--
	-- CZASY: kształt projektowy (5/20/20/20/15) przeskalowany ×3 = 240 s.
	-- PRĘDKOŚCI: przeskalowane ÷3, żeby CAŁKOWITY przyrost został ten sam co w designie
	-- (~120 studów). To jest tu najważniejsze: wydłużenie rundy bez zejścia z prędkości
	-- dałoby 3× większy przyrost, lawa zalałaby mapę w połowie i test skończyłby się
	-- pływaniem. Tak zachowany jest i czas na testowanie, i narastanie presji.
	--
	-- Zmierzone na tej mapie: tafla startuje na Y 2.5, najwyższy dach jest na Y 109.
	-- Przyrost 120 → koniec rundy na ~Y 122, czyli **lawa zalewa wszystko** i runda
	-- naprawdę się kończy, zamiast wygasnąć na timerze.
	-- Próg oprawy (`FX.MinSurfaceY` = 9) przekroczony po ~33 s fazy Easy, czyli ~48 s
	-- od startu rundy — wtedy zapalają się embery, dym, światła i poświata.
	Phases = {
		{ Name = "Spawn",   Speed = 0.00, Duration = 15 },  -- "Get ready" grace
		{ Name = "Easy",    Speed = 0.20, Duration = 60 },  -- +12 studów
		{ Name = "Mid",     Speed = 0.40, Duration = 60 },  -- +24
		{ Name = "Hard",    Speed = 0.65, Duration = 60 },  -- +39
		{ Name = "Endgame", Speed = 1.00, Duration = 45 },  -- +45
	},
	-- LAWA RANI, NIE ZABIJA NA MIEJSCU (decyzja Kacpra 2026-09-21).
	-- Obrażenia lecą WYŁĄCZNIE, dopóki stopy są pod powierzchnią — wyskoczysz, przestaje
	-- boleć. Nic się nie goi (`Game.DisableHealthRegen`), więc kilka krótkich wejść sumuje
	-- się do tych samych sekund. Sens: lawa przestaje być ścianą śmierci, a zaczyna być
	-- zagrożeniem, przed którym da się uciec — i to jest moment, którego wcześniej nie było.
	Damage = {
		-- Ile sekund CIĄGŁEGO kontaktu zabija gracza z pełnym życiem. Liczone z `MaxHealth`,
		-- nie ze sztywnego DPS — dzięki temu zmiana maksymalnego HP nie rozjeżdża balansu.
		SecondsToKill = 7,
	},

	Part = {
		SizeXZ = 600,
		Thickness = 6,
		Color = Color3.fromRGB(255, 80, 0),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	},
	-- Klient-side "żar" gdy gracz jest nisko nad lawą (LavaHeatController):
	-- ColorCorrection tint narasta im bliżej powierzchni lawy. Czysty feedback zagrożenia.
	HeatEffect = {
		Enabled = true,
		-- 16 (było 22): na płaskiej mapie gracze na starcie rundy byli <22 stud nad lawą
		-- i CAŁY ekran świecił pomarańczem — teraz żar wchodzi dopiero przy realnym zagrożeniu.
		Distance = 16,      -- stud nad lawą od których efekt zaczyna narastać (0 nad lawą = max)
		Tint = Color3.fromRGB(255, 175, 140), -- docelowy tint przy max (złagodzony)
		MaxContrast = 0.08, -- dodatkowy kontrast przy max (subtelne "gęste powietrze")
		LerpSpeed = 4,      -- szybkość dochodzenia efektu (1-exp(-k·dt))
	},

	-- RUCH POWIERZCHNI LAWY (LavaSurfaceController, 2026-09-14).
	--
	-- PODZIAŁ RÓL: teksturę daje Kacper w Studio, kod ją tylko PRZEWIJA. Kod nie tworzy
	-- ani nie podmienia wyglądu powierzchni — próbowaliśmy tego cztery razy (siatka kafli
	-- ze studsami, podział na trójkąty, `Material = CrackedLava`, własne wygenerowane
	-- tekstury) i każde podejście zostało odrzucone. Wygląd należy do Kacpra, ruch do kodu.
	--
	-- KONTRAKT: każdy part w `Workspace.Lava` → dziecko typu **`Texture`** (NIE `Decal` —
	-- Decal nie ma `OffsetStuds`), `Face = Top`. Tekstury mogą siedzieć na jednym parcie
	-- albo rozłożone po warstwach stosu (2026-09-16) — kod numeruje je od góry w dół
	-- i każdej kolejnej daje inny mnożnik prędkości. Opcjonalne atrybuty NA WARSTWIE
	-- nadpisują te wartości: `ScrollU`, `ScrollV`, `PulseAmount`, `PulsePeriod` — czyli
	-- stroisz tempo w Studio, bez wchodzenia w kod, także w trakcie Play.
	Surface = {
		Enabled = true,
		-- Domyślne przewijanie w studach/s. Podniesione 2026-09-16 na prośbę "więcej
		-- ruchu" — przy kaflu 30 studów stare 0.55 dawało jeden kafel na ~55 s, czyli
		-- ruch na granicy zauważalności. Teraz ~20 s na kafel: widać płynięcie, ale
		-- lawa dalej czyta się jako gęsta, a nie jak woda.
		DefaultScrollU = 1.4,
		DefaultScrollV = 0.8,
		-- Mnożniki prędkości dla kolejnych warstw. JEDNA przewijana tekstura czyta się jak
		-- przesuwana tapeta; dopiero druga, sunąca wolniej i w przeciwną stronę (ujemny
		-- mnożnik), miesza się z pierwszą i wygląda jak coś płynącego.
		LayerMultipliers = { 1, -1.6, 0.55 },
		-- Pulsowanie przezroczystości (0 = wyłączone). Waha się WOKÓŁ wartości ustawionej
		-- przez Kacpra na warstwie, więc nie nadpisuje jego designu.
		DefaultPulseAmount = 0,
		DefaultPulsePeriod = 7,
	},

	-- FALOWANIE TAFLI (LavaService, strona serwera). Lawa kołysze się wokół swojej
	-- bieżącej wysokości, więc przestaje wyglądać jak sztywna płyta.
	-- ⚠️ To jest part ZABIJAJĄCY: `killSubmerged` porównuje pozycję gracza z powierzchnią,
	-- więc próg śmierci też faluje o tę amplitudę. Przy 0.3 studa jest to pomijalne
	-- (gracz i tak ginie po kostki), ale nie podnosić tego bez zastanowienia.
	-- Musi iść przez serwer — part jest serwerowy, więc klienckie ruszanie Y zostałoby
	-- nadpisane przez replikację w następnej klatce.
	Wobble = {
		Enabled = true,
		-- DWA SKŁADNIKI FALOWANIA (2026-09-16, po prośbie "zwiększ amplitudę").
		-- Rozdzielone, bo ograniczenie dotyczy tylko JEDNEGO z nich:
		--
		-- 1) WSPÓLNY — cały stos jedzie razem, jak tafla wody podnoszona falą. Warstwy
		--    nie zbliżają się do siebie ani o milimetr, więc ten może być DUŻY i to on
		--    odpowiada za "widać, że lawa faluje".
		Amplitude = 0.9, -- stud
		Period = 3.5,    -- s pełnego cyklu
		-- STOS WARSTW (2026-09-16): lawa to kilka partów jeden nad drugim. Gdyby wszystkie
		-- falowały identycznie, stos jechałby jak jeden sztywny blok i przezroczystość
		-- niczego by nie dawała. Dopiero gdy warstwy pływają WZGLĘDEM SIEBIE, widać
		-- objętość cieczy — o to w tym stosie chodzi.
		-- 2) RÓŻNICOWY — warstwy pływają WZGLĘDEM SIEBIE (efekt cieczy o objętości).
		--    Ten zjada szczelinę między warstwami, więc kod przycina go do niej
		--    (`MaxGapUsage`) — podnoszenie go bez rozsunięcia warstw w Studio nic nie da.
		--    Inny okres niż wspólny, żeby ruch nie wyglądał jednostajnie.
		LayerAmplitude = 0.35,
		LayerPeriod = 2.3,
		LayerPhase = 2.1,  -- przesunięcie fazy każdej kolejnej warstwy (radiany, ~120°)
		LayerDecay = 0.6,  -- mnożnik amplitudy w głąb: masa pod spodem kołysze się mniej
		-- Ile szczeliny między sąsiednimi warstwami wolno zjeść falowaniu (0..1).
		-- Dwie tafle, które w siebie wejdą, dają MIGOTANIE zamiast głębi, więc kod
		-- przycina amplitudy do najciaśniejszej szczeliny w stosie. Dzięki temu warstwy
		-- można w Studio dosunąć dowolnie blisko — falowanie samo zrobi się subtelniejsze
		-- zamiast popsuć obraz.
		MaxGapUsage = 0.7,
	},

	-- EFEKTY POWIERZCHNI (LavaSurfaceController, klient). Wszystko lokalne: zero
	-- replikacji, zero fizyki serwera — ten sam wzorzec co DebrisFXController.
	FX = {
		-- Dalej niż to od kamery żaden z efektów nie jest liczony ani spawnowany.
		-- Lawa bywa widoczna przez pół mapy, a bąble z 400 studów to kilka pikseli.
		Distance = 420,

		-- ===== ODSŁONIĘCIE TAFLI (2026-09-16) =====
		-- Tafla lawy jest JEDNYM wielkim prostokątem pod całą mapą, ale widać z niej
		-- tylko kawałki: zmierzone na gotowej mapie **86% powierzchni jest zakryte**
		-- ulicami, chodnikami i stropami. Efekty spawnowane na ślepo lądowały pod
		-- jezdnią — stąd zgłoszenie Kacpra "w losowych miejscach nad lawą pojawia się
		-- dziwne światło": dwa z czterech świateł stały dokładnie pod chodnikiem
		-- i prześwietlały go od spodu.
		-- Jeden raycast W GÓRĘ przed spawnem załatwia wszystkie efekty naraz, a wraz
		-- ze wzrostem lawy coraz więcej tafli robi się odsłonięte samo z siebie.
		-- ===== JEDYNA BRAMKA OPRAWY: WYSOKOŚĆ TAFLI (2026-09-21) =====
		-- Dopóki lawa siedzi w kanale pod ulicami, NIE MA żadnych efektów: ani emberów
		-- i dymu (serwer, `LavaService`), ani bąbli, pary, świateł i poświaty (klient).
		-- Zapalają się dopiero, gdy wierzch tafli przekroczy tę wysokość.
		--
		-- ⚠️ DLACZEGO TO JEST LEPSZE OD POPRZEDNICH BRAMEK ODSŁONIĘCIA (decyzja Kacpra):
		-- tamte pytały GEOMETRIĘ raycastami („czy nad tym punktem coś jest?"), a raycast,
		-- który w nic nie trafił, znaczy albo „otwarte niebo", albo „jeszcze się nie
		-- wczytało". Przy `StreamingEnabled = true` po wejściu na mapę przez ~15 s nie ma
		-- jeszcze ulic, więc kod uznawał lawę za odsłoniętą i zapalał poświatę
		-- prześwitującą przez niedoładowaną podłogę. Porównanie dwóch LICZB nie ma jak
		-- się pomylić i jest poprawne od pierwszej klatki. Przy okazji znika 16 raycastów
		-- na sprawdzenie i cały problem „particle przelatują przez jezdnię" — bo particle
		-- w Robloxie nie kolidują z geometrią i nie dało się tego obejść inaczej.
		--
		-- Zmierzone na mapie: tafla startuje na Y 2.5, strop kanału jest 6.0 studa wyżej,
		-- a Kacper odczytał poziom ulicy (po białych pasach) jako Y 9.
		MinSurfaceY = 9,
		-- ⚠️ HISTEREZA — BEZ NIEJ OPRAWA MIGOCZE (zgłoszenie z logu 2026-09-21).
		-- Tafla FALUJE (`Wobble.Amplitude` 0.9, okres 3.5 s), więc gdy średni poziom stoi
		-- blisko progu, sama fala przenosi go w tę i z powrotem co ~1.75 s — embery i dym
		-- mrugają, a poświata pompuje. Zapalamy dopiero powyżej `MinSurfaceY + H`, gasimy
		-- poniżej `MinSurfaceY - H`, a pomiędzy trzymamy stan. **H musi być większe od
		-- amplitudy falowania** — przy 0.9 daje to zapas 0.3.
		MinSurfaceHysteresis = 1.2,

		-- ===== BĄBLE =====
		-- Powierzchnia wybrzusza się kopułą, rośnie, pęka i pryska iskrami.
		BubblesEnabled = true,
		BubbleInterval = 0.55,  -- średni odstęp (s); losowany ±50%, żeby nie tykało jak metronom
		BubbleMaxActive = 10,   -- sufit jednocześnie żyjących bąbli
		BubbleSpread = 120,     -- promień wokół gracza, w którym szukamy odsłoniętej lawy
		BubbleTries = 5,        -- prób na jeden bąbel (86% tafli jest zakryte)
		BubbleRiseTime = 0.7,   -- s wzrostu przed pęknięciem (dłużej = widać rosnącą kopułę)
		BubbleSizeMin = 3,
		BubbleSizeMax = 7,
		BubbleRise = 1.6,       -- ile studów kopuła wychodzi ponad powierzchnię
		BubbleColor = Color3.fromRGB(255, 140, 40),
		BubbleSparks = 16,      -- iskier przy pęknięciu
		-- Pęknięcie wyrzuca też KROPLE lawy: cięższe od iskier, lecą po łuku i gasną.
		-- Particle, nie party — dziesiątki fizycznych kropel na sekundę to koszt bez sensu.
		BubbleGlobs = 7,
		BubbleGlobGravity = 70,

		-- ===== ŚWIATŁO ZNAD LAWY =====
		-- Kilka świateł sunących po powierzchni — ciepła poświata na dolne piętra.
		-- Dynamiczne światła są w Robloxie drogie, więc jest ich mało i bez cieni.
		-- ===== STAŁA POŚWIATA Z TAFLI =====
		-- Prośba Kacpra: "żeby lawa ciągle tak świeciła". Wędrujące PointLighty dają
		-- zmienność, ale z definicji gasną i wracają — stałe światło musi iść z samej
		-- tafli. `SurfaceLight` na górnej ścianie warstwy wierzchniej świeci NIEPRZERWANIE
		-- na wszystko w zasięgu i nie ma nic wspólnego z cyklem wędrujących świateł.
		SurfaceGlowEnabled = true,
		-- ⚠️ ZASIĘG = ILE ŚWIATŁO PRZEBIJA PRZEZ PIĘTRA, nie „jak daleko ładnie świeci".
		-- Pod `Lighting.Technology = ShadowMap` światła lokalne (PointLight/SurfaceLight)
		-- **nie rzucają cieni w ogóle**, więc strop ich nie zatrzymuje — `Range` jest
		-- jedyną rzeczą, która je ogranicza.
		-- ZMIERZONE na tej mapie 2026-09-21: mediana rozstawu stropów = **14 studów**.
		--   Range 60 -> przebija ~4.3 piętra  (tak było; zgłoszenie „oświetla całe piętro")
		--   Range 30 -> ~2.1 piętra
		--   Range 12 -> ~0.9 piętra  <- mieści się w kondygnacji, w której jest lawa
		-- ➜ Podniesiesz `Range` powyżej ~14 i światło zacznie wychodzić piętro wyżej.
		-- Chcesz mocniejszej łuny bez przebijania → podnoś `Brightness`, NIE `Range`.
		SurfaceGlowRange = 12,        -- zasięg poświaty; patrz pomiar wyżej
		SurfaceGlowBrightness = 2.2,
		SurfaceGlowAngle = 150,       -- szeroki stożek: lawa świeci na boki, nie tylko w górę
		SurfaceGlowColor = Color3.fromRGB(255, 120, 35),

		-- ===== ŚWIATŁO NIE MOŻE PRZEŚWIECAĆ PRZEZ PODŁOGĘ (2026-09-16) =====
		-- Zgłoszenie Kacpra: lawa startuje w kanale POD ulicą i światło przebijało jezdnię
		-- od spodu. To nie jest błąd w kodzie, tylko właściwość silnika: przy
		-- `Lighting.Technology = ShadowMap` światła lokalne (PointLight/SurfaceLight)
		-- **nie rzucają cieni w ogóle** — cienie świateł lokalnych są dopiero we `Future`,
		-- które na telefonach jest drogie. Czyli albo Future, albo światła nie mogą
		-- świecić, dopóki tafla siedzi niżej niż grunt dookoła.
		-- ⚠️ ROZWIĄZANE OSTATECZNIE 2026-09-21 PRZEZ `MinSurfaceY` (wyżej): żadnych raycastów,
		-- tylko próg wysokości tafli. Skasowane razem z tamtym podejściem:
		-- `LightsRequireOpenLava`, `OpenSamples`, `OpenRings`, `OpenTolerance`,
		-- `SurfaceGlowCheckHz`, `LightCutFade`, `LightRecheck`. **Nie przywracać** — powód
		-- (dwuznaczny raycast przy StreamingEnabled + particle nie kolidujące z geometrią)
		-- opisany przy `fxAllowed` w `LavaSurfaceController`.
		SurfaceGlowFade = 1.5,  -- stud jasności/s — poświata narasta płynnie, nie skokiem

		LightsEnabled = true,
		LightCount = 4,
		-- Ten sam powód co przy `SurfaceGlowRange`: pod ShadowMap `Range` to zasięg
		-- PRZEBICIA przez geometrię. Mediana piętra = 14, więc 12 trzyma światło
		-- w kondygnacji lawy. (Stare 30 przebijało ~2 piętra.)
		LightRange = 12,       -- zasięg wędrującego światła
		LightBrightness = 1.2,
		LightColor = Color3.fromRGB(255, 130, 45),
		LightHeight = 3,        -- ile nad powierzchnią wisi światło (nisko = zostaje W wyrwie)
		LightDrift = 1.2,       -- stud/s dryfu (niski: cały dryf wchodzi w zapas przy wyborze miejsca)
		-- Światła żyją W POBLIŻU GRACZA, nie wędrują po całej tafli 513×457. Wcześniej
		-- dryfowały przez całą planszę i po dojściu do krawędzi PRZESKAKIWAŁY na drugą
		-- stronę — z perspektywy gracza światło "pojawiało się" znikąd w losowym miejscu.
		-- Teraz każde ma cykl życia: rozjaśnia się, dryfuje, gaśnie i DOPIERO PO ZGAŚNIĘCIU
		-- przenosi się w nowe wylosowane miejsce.
		LightSpread = 140,      -- promień wokół kamery, w którym losowane są miejsca
		LightLifetime = 7,      -- s pełnego cyklu (losowane ±30%, żeby nie mrugały zgodnie)
		LightFade = 1.5,        -- s narastania i zanikania — tyle trwa "brak przeskoku"
		LightPlacementTries = 6,-- prób znalezienia odsłoniętego punktu na cykl
		LightRetry = 0.75,      -- s przerwy, gdy w pobliżu nie ma odsłoniętej lawy

		-- ===== PARA NA STYKU Z MAPĄ =====
		-- Szukamy miejsc, gdzie tuż POD powierzchnią jest geometria mapy — czyli linii
		-- zalania — i tam unosi się para. Raycasty w dół, nie w bok: gdy lawa podchodzi
		-- pod strop czy ulicę, to właśnie tam jest styk, który widać.
		SteamEnabled = true,
		SteamCheckHz = 3,       -- jak często losujemy próbki
		SteamSamples = 8,       -- próbek na tick (cały koszt tego efektu)
		SteamSpread = 180,      -- promień wokół gracza
		SteamTries = 4,         -- prób znalezienia odsłoniętej lawy na próbkę
		SteamProbeDepth = 4,    -- stud w dół: trafienie = geometria przy linii zalania
		SteamPerSecond = 4,     -- sufit obłoczków/s (przy zalewaniu piętra trafień jest dużo)
		SteamLifetime = 1.6,
	},
}

-- HUD skalowanie (HudScaleController). Projekt UI robiony W PIKSELACH przy referencyjnej
-- wysokości ekranu; każdy top-level element HUD dostaje UIScale = viewportY / ReferenceHeight.
-- Dzięki temu wygląd jest IDENTYCZNY na każdym monitorze (skaluje się całość razem z tekstem),
-- a pozycje kotwiczone do krawędzi/rogów (px marginesy) nie dryfują między aspect ratio.
Config.UI = {
	-- GŁÓWNA GAŁKA WIELKOŚCI HUD: mniejsza wartość = większy HUD na każdym ekranie
	-- (skala = wysokośćEkranu / ReferenceHeight). Wartości projektowe px są "przy 1440",
	-- ale 1200 daje ~20% większy render — kalibracja pod feel Kacpra (1440 było za małe).
	ReferenceHeight = 1200,
	MinScale = 0.5,         -- safety: nie zmniejszaj HUD poniżej połowy (mikro-okna)
	MaxScale = 2.0,         -- safety: nie rozdmuchuj powyżej 2× (ultra-tall porty)
}

Config.Spawn = {
	-- Wysokość offsetu nad lobby spot Part (gracz ląduje LobbyYOffset stud nad jego topem).
	LobbyYOffset = 5,
	-- Fallback gdyby Workspace.Lobby.Spawn nie istniał (na czas zanim Kacper postawi).
	FallbackLobbyPosition = Vector3.new(0, 10, 0),
	FallbackRoundPosition = Vector3.new(0, 10, 0),
}

Config.Cash = {
	-- Każda zebrana paczka cash daje Value$. Kacper zatwierdził 10$/pickup.
	Value = 10,
	-- Frakcja spawn pointów które się aktywują na rundę. 1.0 = wszystkie (10 z 10).
	-- Zmniejsz jeśli rundy będą za bogate.
	SpawnFraction = 1.0,
	-- Promień w stud w którym cash leci do gracza (magnet trigger).
	MagnetRange = 8,
	-- Czas trwania client-side animacji łuku pickup w sekundach. Dłuższy = bardziej
	-- czytelny łuk i smooth pickup. Za długo i pickup czuje się ślamazarnie.
	MagnetSpeed = 0.9,
	-- Częstotliwość server-side checku magnet (Hz). 10Hz × 10 cash × 30 graczy = 3k op/s — OK.
	HeartbeatHz = 10,
	-- Margines (stud) od bieżącej wysokości lawy poniżej którego cash NIE spawnuje
	-- (raycast filter). Bez tego cash mogłoby spawnować nad lawą wpadającą w pierwsze 5s.
	LavaSafetyMargin = 3,
	-- Globalny Y offset doliczany do każdej pozycji w Workspace.Map.Locked.CashSpawns.
	-- Kacper stawia markery na podłodze/dachu (wygodne do mierzenia) ale cash powinien
	-- "wisieć" nieco wyżej — bardziej czytelne wizualnie. Zmień tu, nie w Studio.
	SpawnHeightOffset = 2,

	-- Idle animacja (klient-side, lokalna, deterministyczna z pozycji — wszyscy widzą to samo).
	-- Amplituda góra-dół w stud. 0.25 = subtelne, 0.5 = bardziej rzucające się.
	HoverAmplitude = 0.3,
	-- Częstotliwość hoveru w Hz (1 = pełen cykl góra→dół→góra co 1s).
	HoverFrequency = 0.8,
	-- Prędkość obrotu wokół osi Y w radianach/s. 0.8 ≈ 45°/s = wolna elegancka rotacja.
	SpinSpeed = 1.2,

	-- Pickup parabola: midpoint Beziera w górze. Lift = max(MinLift, distance × LiftFraction)
	-- z capem MaxLift. Im dalszy cash, tym wyższy łuk — ale nie więcej niż MaxLift żeby
	-- daleki pickup nie strzelał w niebo.
	PickupArcMinLift = 5,
	PickupArcLiftFraction = 0.65,
	PickupArcMaxLift = 18,
	-- Ile pełnych obrotów cash wykonuje w trakcie lotu po łuku. Visual flair.
	PickupSpinTurns = 2.5,

	-- Domyślny styl gdy ReplicatedStorage.Cash nie istnieje. Kacper wrzuci asset → kod sam użyje.
	DefaultColor = Color3.fromRGB(255, 215, 0),
	DefaultSize = Vector3.new(2, 2, 0.4),

	-- Licznik kasy renderowany OBRAZKAMI cyfr (sprite strip 0-9 + $). Powód: Roblox
	-- TextLabel nie umie teksturować glifów, a design wymaga studs W literach.
	-- Sprite wygenerowany skryptem (studs + zielony gradient + kontur), wgrany przez MCP.
	--
	-- WYŁĄCZONE (2026-08-04): wygenerowany sprite wyglądał źle na ekranie — wracamy do
	-- zwykłego CoinLabel (TextLabel, FredokaOne + UIGradient + UIStroke, styl Kacpra),
	-- który aktualizuje UIController. Enabled = true przywraca cyfry-obrazki.
	DigitDisplay = {
		Enabled = false,
		AssetId = "rbxassetid://74720156873015",
		CellWidth = 160,  -- szerokość komórki znaku w stripie (px źródła)
		CellHeight = 200, -- wysokość stripa (px źródła)
		DigitHeight = 84, -- px projektu na ekranie (HudScale skaluje z rozdzielczością)
		Spacing = -6,     -- odstęp między znakami; ujemny = ciaśniej (-14 sklejało sąsiednie cyfry)
	},

	-- Trail (wstęga) za cashem lecącym do gracza podczas pickup arc. Klient-side VFX.
	PickupTrail = {
		Enabled = true,
		ColorStart = Color3.fromRGB(255, 235, 120), -- jasne złoto przy cashu
		ColorEnd = Color3.fromRGB(255, 170, 30),    -- cieplejszy pomarańcz na ogonie
		StartTransparency = 0.1,
		Lifetime = 0.25,        -- sekundy życia śladu (dłużej = dłuższy ogon)
		AttachmentSpread = 0.5, -- połowa szerokości wstęgi (stud)
		LightEmission = 1,      -- 1 = addytywnie świeci, czytelne na każdym tle
	},

	-- Floating popup nad CashLabel ("+10$", "-50$"). Stack maks Popup.MaxSlots, najstarszy
	-- wycieka przy overflow. Tylko klient-side — server odpala przez Remotes.CashChanged.
	Popup = {
		MaxSlots = 4,
		SpacingPixels = 28,              -- odstęp Y między slotami stacku (px)
		PopInTime = 0.15,                -- scale 0.7 → 1.0 (Back EaseOut)
		SteadyTime = 1.7,                -- czas pełnej widoczności
		FadeOutTime = 0.5,               -- normalny zanik
		DriftUpPixels = 20,              -- ile px popup unosi się podczas fade-out
		OverflowFadeTime = 0.2,          -- skrócony fade gdy nowy wypycha najstarszy
		SlotTransitionTime = 0.18,       -- czas przesuwania stacku gdy nowy popup wpada
		ColorPositive = Color3.fromRGB(80, 230, 100),
		ColorNegative = Color3.fromRGB(230, 80, 80),
	},
}

Config.Bridge = {
	-- Kolory ghost preview (klient-side podgląd przed kliknięciem LMB).
	GhostColorOK = Color3.fromRGB(100, 220, 120),       -- zielony — w zasięgu, można budować
	GhostColorBad = Color3.fromRGB(220, 80, 80),        -- czerwony — za daleko lub invalid
	GhostTransparency = 0.5,

	-- ⚠️ GHOST MUSI MIEĆ `Highlight` — BEZ NIEGO ZNIKA NAD LAWĄ (zgłoszenie 2026-09-21:
	-- „lawa w tle działa jak maska i nie widać zielonego ghosta").
	-- Mechanizm to ta sama rodzina buga co „pod kątem znika tekstura lawy": part
	-- z `Transparency > 0` trafia do KOLEJKI PRZEZROCZYSTEJ, a Roblox sortuje ją po
	-- odległości OBIEKTU. Warstwy lawy są przezroczyste (0.35 / 0.55) i wielkie
	-- (512×457), więc sortują się niestabilnie względem małego ghosta i potrafią zostać
	-- narysowane PO nim — czyli zamalować go. Nie da się tego wygrać dobieraniem
	-- `GhostTransparency`, bo problem jest w kolejności rysowania, nie w wartości.
	-- `Highlight` renderuje się POZA tą kolejką, więc jest odporny z definicji.
	-- ⚠️ LAWA JAKO PODŁOGA DLA KURSORA (zgłoszenie 2026-09-21: „ghost nie działa powyżej 9Y").
	-- Warstwy lawy mają wymuszone `CanQuery = false` (rosnąca tafla nie może łapać
	-- raycastów — patrz `LavaService.forceLavaProperties`), więc promień celowania
	-- PRZELATUJE przez nią i trafia w grunt POD spodem. Dopóki lawa siedziała w kanale,
	-- nikt w nią nie celował i nie było tego widać; gdy wyszła na ulice, ghost zaczął
	-- lądować kilkanaście studów niżej, niż gracz celował — a warstwa `LavaMid` jest
	-- NIEPRZEZROCZYSTA, więc po prostu znikał. To NIE był problem renderowania.
	-- Fix: przecinamy promień z płaszczyzną wierzchu tafli i bierzemy to, co bliżej.
	-- `false` = stary zachowanie (most stawia się pod lawą).
	LavaAsFloor = true,

	GhostHighlight = true,
	GhostFillTransparency = 0.55,    -- wypełnienie sylwetki (1 = sam kontur)
	GhostOutlineTransparency = 0,    -- kontur na ostro — to on niesie czytelność kształtu
	-- `AlwaysOnTop` = ghost widać też PRZEZ ściany. Dla podglądu budowania to zaleta
	-- (zawsze wiesz, gdzie stanie most), ale gdybyś wolał, żeby chował się za geometrią,
	-- zmień na `Enum.HighlightDepthMode.Occluded`.
	GhostDepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	-- Awaryjny wygląd, gdy modelu `ItemDefinitions.bridge_builder.worldModel`
	-- (dziś ReplicatedStorage.Bridge) nie ma — wtedy staje goły Part o wymiarach
	-- z definicji itemu. Normalnie most bierze wygląd I WYMIARY z modelu Kacpra.
	DefaultMaterial = Enum.Material.Wood,
	DefaultColor = Color3.fromRGB(115, 80, 50),
}

Config.Movement = {
	-- Bazowa prędkość chodu. Specjalnie niższa niż default Roblox (16) żeby sprint miał
	-- wyraźną różnicę i był decyzją (a nie "zawsze trzymam Shift bo czemu nie").
	WalkSpeed = 12,
	-- Prędkość sprintu (Etap 2). Sprint = ~+67% nad walk → wyraźna różnica feelingowa.
	SprintSpeed = 20,
	-- Czas lerp WalkSpeed przy przełączaniu walk↔sprint (s). Eliminuje szarpanie.
	SpeedLerpTime = 0.15,

	-- Kamera 3rd person (Etap 1). MinZoomDistance > 0 = blokuje FPP.
	-- 8 = blisko ramienia, widoczna sylwetka. 15 = znormalizowany "lot ptaka".
	CameraMinZoom = 8,
	CameraMaxZoom = 15,
	-- Bazowy FOV (Etap 3). 70 = standard Roblox, czytelne dla casuals.
	BaseFOV = 70,
	-- FOV w trakcie sprintu (Etap 3). +8° dosadnie pokazuje prędkość bez motion sickness.
	SprintFOV = 78,
	-- Czas lerp FOV (s). Krótszy = bardziej "snap", dłuższy = filmowy.
	FOVLerpTime = 0.2,

	Stamina = {
		-- Max stamina (sekundy biegu przy 1.0 drain rate). Etap 2.
		-- Wartość bazowa; PlayerDataService może override per-player (upgrade).
		Max = 5.0,
		-- Drain rate w trakcie sprintu (stamina/s). 1.0 = 1s sprintu = 1 stamina.
		DrainRate = 1.0,
		-- Regen rate gdy nie sprintujesz (stamina/s). Walk = regen, idle = regen.
		-- 1.5 → 2.2 (2026-09-12): pełne naładowanie z zera 5s → ~2.3s.
		RegenRate = 2.2,
		-- Opóźnienie regeneracji po skończeniu sprintu (s). Zapobiega spam shift.
		-- 0.8 → 0.35 (2026-09-12): krótka pauza dalej blokuje spam, ale nie czuć "martwej chwili".
		RegenDelay = 0.35,
		-- Próg minimalny żeby zacząć sprint po wyczerpaniu (anti-stutter).
		-- Gdy stamina spada do 0 → force walk → musi naładować się do tego progu
		-- zanim Shift znów zadziała. Bez tego: 0 stamina → puszczam-łapię shift, mikro-sprinty.
		MinToResume = 1.0,
	},

	-- Pasek staminy 3D (BillboardGui obok postaci, client-only — MovementController).
	-- Template robi Kacper w Studio: ReplicatedStorage.StaminaBar (BillboardGui) z pionowym
	-- `Fill` (GuiObject zakotwiczony dołem). Pozycję obok postaci ustawia StudsOffset
	-- na BillboardGui w Studio; kod steruje tylko wysokością Fill (0..1), kolorem i fade.
	StaminaBar = {
		-- Pasek widoczny WYŁĄCZNIE przy sprincie albo gdy stamina się odbudowuje
		-- (sprint aktywny LUB stamina < max). Pełna stamina bez biegu = ukryty.
		-- Fade transparencji jest LINIOWY — trwa dokładnie tyle sekund, ile tu stoi.
		FadeInTime = 0.12,
		FadeOutTime = 0.25,
		-- Elastic pop: UIScale "Anim" w template animowany 0→1 przy pokazaniu, 1→0 przy chowaniu.
		-- PopOutTime MUSI być <= FadeOutTime, inaczej pasek zniknie w połowie zwijania.
		PopInTime = 0.55,
		PopOutTime = 0.2,
		PopInStyle = Enum.EasingStyle.Elastic, -- sprężysty wjazd (Back = spokojniejszy wariant)
		PopOutStyle = Enum.EasingStyle.Quad,
		-- Reaktywny kolor wypełnienia wg poziomu: pełna → połowa → pusta.
		ColorFull = Color3.fromRGB(60, 140, 255), -- niebieski
		ColorMid = Color3.fromRGB(250, 205, 55),  -- żółty
		ColorLow = Color3.fromRGB(235, 60, 55),   -- czerwony
	},

	HeadTrack = {
		-- Etap 5: clamp kątów obrotu głowy.
		MaxYawDegrees = 70,
		MaxPitchDegrees = 60,
		-- Lerp speed Motor6D Neck (większe = szybsze nadążanie za kamerą).
		LerpSpeed = 10,
		-- Replikacja do innych klientów (Hz). 10Hz dla 20 graczy = 200 events/s — OK.
		ReplicateHz = 10,
		-- Próg zmiany (rad) poniżej którego nie wysyłamy do serwera (skip dla micro-jitter).
		ReplicateEpsilon = 0.02,  -- ~1.1°
		-- Część yaw'a przejmuje waist (talia) — daje bardziej naturalne skręcanie ciała,
		-- nie tylko sama głowa. 0.3 = neck robi 70%, waist 30%. Pitch nie idzie na waist
		-- (wyglądałoby jak ukłon).
		WaistYawRatio = 0.3,
	},

	Camera = {
		-- Elastyczne wygładzanie rotacji kamery — kamera "dogania" ruch myszy z lekką
		-- bezwładnością zamiast snapować natychmiast. Daje ciężki, płynny feel przy obracaniu.
		RotationSmoothing = {
			Enabled = true,
			-- Framerate-independent responsiveness (1-exp(-k·dt)). Wyższe = szybsza/twardsza
			-- kamera (mniej lag). ~22 = subtelny elastic; 12 = mocno płynne/ciężkie; 40 = prawie snap.
			Speed = 22,
			-- Snap gdy pozycja kamery skoczy o więcej niż to (stud) — respawn/teleport bez swoop.
			SnapDistance = 30,
		},

		-- Landing dip — kamera w dół przy hard landing. Sine pulse (0 → -intensity → 0).
		LandingDipMin = 0.4,        -- minimum intensity (małe spadki)
		LandingDipMax = 1.5,        -- max intensity (długi spadek)
		LandingDipPerStud = 0.08,   -- intensity = clamp(fallHeight × this, Min, Max)
		LandingDipDuration = 0.35,  -- całkowity czas pulse'u (s)
		MinFallHeightForDip = 5,    -- nie odpalaj dip'a dla małych spadków (jump = ~7 stud)

		-- Screen shake (publiczne API). MovementController.screenShake(intensity, duration).
		-- Decay liniowy; offset = random unit vec * intensity * (1 - progress).
		ShakeMaxIntensity = 3.0,    -- safety cap (żeby ktoś nie podał 50 i nie wymiotował)

		-- Reakcja trafionego gracza na wybuch bomby (Remotes.BombHit → shake + FOV punch).
		-- Intensywność skaluje z falloff wybuchu (1.0 w epicentrum, 0 na krawędzi radius).
		HitReaction = {
			ShakeMax = 2.4,        -- max intensity screenShake w epicentrum
			ShakeDuration = 0.45,  -- czas trwania shake (s)
			FOVPunchMax = 14,      -- max stopni FOV kick w epicentrum (zoom out → wraca)
			FOVPunchDecay = 8,     -- szybkość powrotu FOV (wyższe = szybszy powrót)
		},
	},
}

-- F key PvP push (PushService). Balans gameplay — hard rule #5: liczby w Config.
-- Cooldown pusha jest w RateLimits.Push (wspólny kontrakt server/klient CooldownBar).
-- OBRAŻENIA I RAGDOLL ZA UPADEK (FallDamageService, 2026-09-16).
-- Ustalone z Kacprem: bezpiecznie do 25 studów, śmierć od 75, ragdoll od 2× progu,
-- tylko w rundzie. Sens dla rozgrywki: push przestaje działać wyłącznie nad lawą —
-- zepchnięcie kogoś z dachu zabija samo w sobie, a `KillService` przypisze zabójstwo
-- spychającemu przez istniejące okno 5 s.
Config.FallDamage = {
	Enabled = true,
	-- Do tylu studów upadek jest DARMOWY. Zeskok z piętra czy dwóch nie może karać,
	-- bo gra ma być szybka — gracz, który waha się przed każdym zeskokiem, jest wolny.
	SafeHeight = 25,
	-- Od tylu studów upadek zabija (100% MaxHealth). Pomiędzy progami liniowo.
	LethalHeight = 75,
	-- Ragdoll od `SafeHeight × ten mnożnik` (czyli 30 studów). Schodziło dwa razy na
	-- prośbę Kacpra: 50 → 35 → 30, bo przy wyższych progach efektu prawie nie było widać.
	-- 30 studów to upadek za ~10 dmg, czyli przewraca już przy lekkim draśnięciu.
	-- ⚠️ 1.0 (czyli 25) to PODŁOGA tej gałki — wtedy KAŻDY raniący upadek kładzie gracza
	-- na 2 s, a to jest dokładnie ta opcja, którą Kacper świadomie odrzucił przy
	-- projektowaniu ficzuru ("nie mogę wstać" w trakcie ucieczki przed lawą wkurza).
	RagdollHeightMultiplier = 1.2,
	RagdollDuration = 2,      -- s, tyle co ragdoll po bombie
	RagdollTumble = 0.35,     -- ile poziomej prędkości z momentu uderzenia idzie w przewrotkę

	-- 30 Hz, nie 12: przy 12 opóźnienie między dotknięciem ziemi a obrażeniami wynosiło
	-- zmierzone 0.10 s i było wyczuwalne. Koszt to 1 raycast na gracza na próbkę, czyli
	-- 600/s przy 20 graczach — pomijalne.
	CheckHz = 30,
	GroundProbe = 4.5,        -- stud w dół z HRP; HRP jest ~2.5 nad stopami w R15
	-- RAGDOLL W POWIETRZU (2026-09-17). Jeden raycast w dół mówi, gdzie jest ziemia, więc
	-- całą wysokość upadku znamy JUŻ PRZY ODERWANIU SIĘ OD DACHU — nie trzeba czekać na
	-- uderzenie. Gdy prognoza przekroczy próg ragdolla, wywracamy gracza w locie.
	-- To jest też właściwe rozwiązanie opóźnienia: toolbox potrzebuje pełnej drogi
	-- serwer → klient, a tak ma na nią cały lot zamiast ułamka sekundy po uderzeniu.
	PredictReach = 400,          -- stud w dół: zasięg szukania gruntu (i prognozy)
	PreRagdollMinAirTime = 0.25, -- s w powietrzu zanim wywrócimy — zeskok z krawędzi
	                             -- nie ma kłaść gracza natychmiast po odbiciu
	-- Dwa warunki odróżniające SPADANIE od zwykłego „braku gruntu pod stopami"
	-- (wspinaczka, drabina, wyskok w górę, stanie na wąskiej półce nad przepaścią).
	-- Bez nich prognoza rosła razem ze wspinającym się graczem i wywracała go w połowie
	-- ściany — zgłoszone 2026-09-17.
	PreRagdollMinDrop = 10,      -- stud, które gracz musi już zjechać od swojego szczytu
	PreRagdollMinSpeed = 30,     -- stud/s w dół; wspinaczka nigdy tyle nie osiąga,
	                             -- a swobodny spadek przekracza to po ~0.15 s
	RagdollAirSafety = 8,        -- s: bezpiecznik wstawania, gdy gracz nigdy nie wyląduje
	                             -- (wpadł w lawę albo w przepaść)
	MinAirTime = 0.25,        -- krócej w powietrzu = schodek/krawężnik, nie upadek
	-- ⚠️ Były tu `MaxLookAhead` i `LandingCooldown` — OBA USUNIĘTE 2026-09-19, bo oba
	-- gubiły prawdziwe upadki. `MaxLookAhead` był sufitem dla sondy sięgającej w PRZYSZŁOŚĆ
	-- (dach, nad którym gracz przelatywał, meldował się jako lądowanie — „bomba mnie
	-- wyrzuca i nie ma obrażeń"). `LandingCooldown` 0.8 s wyciszał każdy kolejny upadek
	-- w tym oknie, także po nieszkodliwym lądowaniu („spadam na tory, potem niżej i już
	-- nic"). Sonda liczy teraz PRZEBYTĄ DROGĘ, a „jedno lądowanie = jedna kara" wynika
	-- ze struktury przejścia lot→ziemia, nie z licznika czasu.
	Debug = false,            -- print przy każdym raniącym upadku (przydatne przy strojeniu liczb)
}

Config.Push = {
	MaxRange = 7,   -- stud; close-combat only
	ConeDot = 0.3,  -- min dot(look, kierunek do celu) — ~70° stożek przed pusherem
	Force = 80,     -- pozioma velocity (stud/s)
	Lift = 20,      -- pionowy kick — bez niego push szoruje graczem po ziemi
	-- Feedback ofiary: screen shake gdy ktoś Cię pchnie (klient, MovementController.screenShake).
	HitShakeIntensity = 1.1,
	HitShakeDuration = 0.3,
}

-- Rate limits per akcja (sekundy). Server enforces, klient mirrors dla wizualizacji
-- CooldownBar. TE SAME wartości MUSZĄ być używane po obu stronach — dlatego jedno źródło.
-- Hak (item `grapple`) — celujesz, trafiasz (w zasięgu), LECISZ PO ŁUKU DO TEGO PUNKTU
-- i kończysz lot trochę nad nim. Specyfikacja Kacpra zebrana z trzech testów (2026-09-22/23):
--   1. leci W KIERUNKU zaczepu („jak wysoko wbijesz, to wysoko lecisz"), nie do góry
--   2. DOLATUJE do punktu, trochę wyżej — lot KOŃCZY się w punkcie, nie przelatuje
--   3. po ŁUKU, nie po prostej — prosta linia wygląda jak winda, nienaturalnie
--
-- ⛔ HISTORIA — TRZY ODRZUCONE MODELE. KAŻDY SPEŁNIAŁ JEDNO WYMAGANIE KOSZTEM INNEGO:
--   ① impuls balistyczny, wolny lot (TravelSpeed 55) → łamał 1: „wywala do góry".
--     Przy g = 196.2 każda dziesiąta sekunda lotu dokłada ~10 stud/s pionu; kąt wychodził
--     33-67° bez względu na cel.
--   ② ta sama balistyka, szybki lot (TravelSpeed 120) → łamał 2: tor rzutu PRZECINA punkt
--     z pełną prędkością (~120-170 stud/s), zamiast się w nim kończyć.
--   ③ lina po prostej ze stałą prędkością → łamał 3: „nienaturalnie po prostej".
--   ➜ LOT PROWADZONY PO KRZYWEJ (moduł GrappleArc): parabola od startu do celu ze szczytem
--     nad linią prostą. Postać nie jest RZUCANA (wtedy przelatuje), tylko PROWADZONA
--     (LinearVelocity) po łuku, który z definicji kończy się w punkcie. Spełnia wszystkie
--     trzy naraz. ⚠️ Nie wracać do „dostrajania" ①/②: to nie była kwestia liczb.
Config.Grapple = {
	MaxRange = 70,        -- stud; dalej serwer odrzuca (mierzone od HRP do punktu)

	-- ── Kształt i tempo lotu (GrappleArc) ──
	-- Średnia prędkość WZDŁUŻ łuku; czas lotu = długość łuku / FlightSpeed.
	FlightSpeed = 100,
	-- Wysokość łuku nad linią prostą = dystans POZIOMY × ArcRatio, najwyżej ArcMax.
	-- Liczone od poziomu celowo: przy wspinaczce pionowo w górę łuku nie ma (i wyglądałby
	-- jak błąd), a przy locie poziomym jest pełny. 0.12 daje kąt startu ~28-34° przy celu
	-- na wprost. 🎚️ GŁÓWNA GAŁKA „jak bardzo po łuku": wyżej = bardziej po łuku.
	-- ⚠️ Nie przesadzać: kąt startu powyżej ~40° przy celu na wprost czyta się jak ①.
	ArcRatio = 0.12,
	ArcMax = 10,
	-- Tempo po łuku: na starcie (1 + ArcEase) × średnia — szarpnięcie; na końcu
	-- (1 − ArcEase) × średnia — „dolecisz", a nie „rąbniesz". 0 = stałe tempo.
	ArcEase = 0.4,
	-- Jak mocno lot poprawia odchyłkę od łuku (1/s). Bez tego postać dryfuje od krzywej
	-- przez opóźnienie klatki i kończy lot obok punktu.
	TrackGain = 10,

	-- ── Gdzie kończy się lot ──
	-- Cel = trafienie + Normal × Standoff + góra × Lift.
	-- Standoff odsuwa cel OD POWIERZCHNI: środek HRP nie może stanąć na ścianie, więc bez
	-- tego lot zawsze kończyłby się pchaniem w mur. Lift to „trochę wyżej": trafisz w ścianę
	-- tuż pod krawędzią dachu → dolecisz ponad krawędź; trafisz w dach → staniesz na nim.
	Standoff = 1.8,
	Lift = 3.5,
	ArriveRadius = 2.5,   -- lina INNEGO gracza gaśnie, gdy jego postać jest tak blisko celu

	-- ── Wyjście z lotu ──
	-- Część prędkości z końca łuku zostaje (bez tego lot urywa się szarpnięciem, bo koniec
	-- łuku ma jeszcze ~40-60 stud/s) + wybicie w górę i W STRONĘ ŚCIANY, w którą trafiłeś —
	-- to ono przerzuca przez krawędź dachu. Przy zaczepie o sam dach kierunek wybicia to
	-- kierunek lotu. To samo po zahaczeniu i po timeoucie.
	ExitCarry = 0.35,
	ExitUp = 18,
	ExitForward = 10,

	-- ── Bezpieczniki ──
	-- Czas lotu z GrappleArc + TimeMargin, przycięty do MaxFlightTime. Liczy go SERWER
	-- i wysyła klientowi jako twardy sufit — jedno źródło prawdy dla klienta (koniec lotu),
	-- anti-cheata i fall damage.
	TimeMargin = 0.3,
	MaxFlightTime = 1.2,
	-- Zapas serwera na ping przy oknach bezkarności anti-cheata i wyłączeniu ragdolla w locie.
	NetMargin = 0.4,
	-- Zahaczenie po drodze: postać odstaje od łuku o więcej niż StuckDistance przez
	-- StuckTime → koniec lotu. Po ODLEGŁOŚCI od krzywej, nie po prędkości — tempo na łuku
	-- celowo się zmienia, więc „za wolno" nie znaczyłoby nic. Sprawdzane po StuckGrace,
	-- bo w pierwszej klatce postać dopiero rusza.
	StuckDistance = 3.5,
	StuckTime = 0.15,
	StuckGrace = 0.1,
	-- Siła liny = masa postaci × grawitacja × ForceScale. Musi wyraźnie przebić ciężar
	-- i kontroler Humanoida; 30 daje prędkość lotu w ~0.02 s. Skończona celowo: siła
	-- nieograniczona przy zetknięciu z geometrią potrafi wypchnąć postać przez cienki part.
	ForceScale = 30,

	-- ── Lina (kosmetyka, rysowana lokalnie u KAŻDEGO klienta — Remotes.GrappleFX) ──
	-- Trwa przez CAŁY lot i skraca się razem z nim. Bez tego lot wygląda jak lewitacja,
	-- a inni gracze widzą kolegę odlatującego bez powodu.
	RopeThickness = 0.12,
	RopeColor = Color3.fromRGB(70, 60, 50),
	RopeFadeTime = 0.12,

	-- Feedback u strzelca — szarpnięcie na starcie ma być czuć.
	ShakeIntensity = 1.3,
	ShakeDuration = 0.25,
}

Config.RateLimits = {
	BombThrow = 0.5,
	Push = 4,
	BridgeBuild = 0.5,
	Grapple = 0.6,   -- hak: krótki, bo item jest zużywalny — limituje go cena, nie zegar
	-- EquipItem+UnequipItem: klik hotbar slot. Spam clickowanie = flickering Tool
	-- w rękach innych klientów + bandwidth. 0.15s = ~7 kliknięć/s max, ludzki reflex OK.
	EquipItem = 0.15,
}

-- Anti-cheat: wykrywanie speedhacka/teleportu u żywych graczy w ROUND.
Config.AntiCheat = {
	-- Detekcja speedhacka mierzy REALNIE przebytą odległość poziomą, nie Humanoid.WalkSpeed.
	-- Zmierzone 2026-08-11 w Studio: klient ustawia WalkSpeed=100, serwer dalej czyta 16 —
	-- właściwości Humanoida ustawiane lokalnie NIE replikują się na serwer, więc stary
	-- cap na WalkSpeed nie wykrywał niczego.
	CheckIntervalSec = 2,   -- co ile server próbkuje pozycje (heartbeat throttled)
	-- Dozwolona prędkość = SprintSpeed + tolerancja. Tolerancja pokrywa lag, zbiegi
	-- ze skarpy, schody i zjazd po pochyłym gruzie.
	SpeedTolerance = 8,
	-- Ile próbek pod rząd musi przekroczyć limit zanim ukarzemy. Cheater biegnący 100
	-- przekracza KAŻDĄ próbkę; gracz zdmuchnięty bombą najwyżej jedną-dwie.
	Strikes = 3,
	-- Okno bezkarności po impulsie nadanym PRZEZ SERWER (knockback bomby, push).
	-- Bez tego własna bomba robiłaby z gracza "cheatera".
	GraceAfterImpulseSec = 4,
}

Config.Rewards = {
	-- Nagroda za przeżycie do końca rundy (wszyscy alive po Endgame). Bomba=50, most=100,
	-- więc wygrana pokrywa 2 bomby lub 1 most — czyste zachęta do zakupów.
	Win = 100,
	-- Nagroda za zabicie innego gracza (bomba explosion / push w lawę). Tagujemy attacker'a
	-- w Humanoid attribute na X sekund; jeśli victim umrze w tym oknie, credit attackerowi.
	Kill = 25,
	-- Ile sekund attacker "trzyma" tag na victim'ie. Zbyt duże = kill-steal po lave'em przypadkowym.
	KillCreditWindowSec = 5,
}

-- SYSTEM DESTRUKCJI v2 (DESTRUCTION_PLAN.md). SYSTEMOWE gałki wspólne dla każdego źródła
-- wybuchu; siła/zasięg konkretnego itemu siedzi w ItemDefinitions.<item>.destruction.
-- Wartości startowe CELOWO hojne (decyzja Kacpra: "dużo fragmentów, najwyżej będę hamował")
-- — po testach kręcimy TU, nie w logice.
-- Sklep-NPC (ShopController + ShopService). Gracz podchodzi do sprzedawcy w lobby
-- (ProximityPrompt) → kamera przeskakuje do SCENY SKLEPU i celuje w wystawiony model itemu,
-- a na dole StarterGui.ShopUI (KUP / cena / opis). Sam gracz zostaje przy sprzedawcy.
--
-- KONTRAKT MAPY (przebudowany 2026-09-20 pod nowe lobby Kacpra):
--   Workspace.Lobby/…/WeaponsShop/NPC   — sprzedawca. Szukany REKURENCYJNIE, więc może
--                        siedzieć dowolnie głęboko w dekoracjach. ProximityPrompt tworzy
--                        ShopService, jeśli go nie ma (własny = nazwij go PromptName).
--   Workspace.WeaponShopScene.Decorations.<sceneModel>  — model itemu na wystawie; nazwa
--                        z ItemDefinitions.<item>.sceneModel (bomb → "Bomb", …).
--   Workspace.WeaponShopScene.ShopCameras/*             — markery POZYCJI kamery. Nazwy
--                        DOWOLNE: marker obsługuje item, naprzeciw którego stoi (parowanie
--                        po odległości). Obrót markera nieistotny — kod sam celuje w model.
--
-- Dodanie itemu do sklepu = model na wystawie + marker obok + pole sceneModel w definicji.
-- Item bez markera dostaje kadr policzony automatycznie, więc sklep działa od razu.
Config.Shop = {
	-- ── STRAGAN W LOBBY (gdzie gracz staje i naciska E) ─────────────────────────
	-- Szukane REKURENCYJNIE pod Workspace.Lobby, więc stragan można przesuwać
	-- w drzewie dekoracji bez wracania do kodu. Dziś leży w:
	--   Workspace.Lobby.Lobby.Lobby.Decorations.Shops.WeaponsShop.NPC
	ShopModelName = "WeaponsShop",
	NpcName = "NPC",

	-- ProximityPrompt: jeśli NPC go nie ma, ShopService tworzy własny na tych
	-- wartościach. Postawisz swój w Studio → kod użyje Twojego i nie dotknie tych pól.
	-- ⚠️ PromptMaxDistance MUSI być mniejszy niż InteractDistance, inaczej gracz
	-- widzi prompt z miejsca, z którego serwer odrzuci mu zakup.
	-- Nazwa promptu to JEDYNE, co łączy serwer z klientem w tej sprawie: serwer go
	-- tworzy (albo zastaje Twój), klient szuka pod tą nazwą i nie musi znać ścieżki NPC.
	PromptName = "ShopPrompt",
	PromptActionText = "Sklep",
	PromptObjectText = "Sprzedawca",
	PromptKeyCode = Enum.KeyCode.E,
	PromptMaxDistance = 12,

	-- ── SCENA SKLEPU (osobne pomieszczenie, do którego jedzie kamera) ───────────
	-- Gracz NIE jest tam teleportowany — zostaje przy sprzedawcy, leci sama kamera.
	-- Dlatego scena może stać dowolnie daleko od lobby i kilku graczy może kupować
	-- naraz, nie wchodząc sobie w kadr.
	SceneName = "WeaponShopScene",
	ItemsFolder = "Decorations",   -- modele na wystawie (nazwa z ItemDefinitions.sceneModel)
	CamerasFolder = "ShopCameras", -- markery pozycji kamery

	-- PAROWANIE KAMERY Z ITEMEM IDZIE PO ODLEGŁOŚCI, NIE PO NAZWIE MARKERA.
	-- Marker obsługuje ten item, naprzeciw którego stoi — ten sam wzorzec, co dawne
	-- SHOPCAMERA{N} → najbliższy model. Dostawienie itemu to postawienie modelu
	-- i markera obok niego; literówka w nazwie markera niczego nie psuje.
	-- (2026-09-20: w Studio nazwy są zamienione względem pozycji — BombCamera stoi
	-- naprzeciw Blueprintu — a kadry i tak wychodzą poprawnie właśnie dzięki temu.)

	-- Kadr awaryjny, gdy item nie ma markera: kamera odsuwa się od modelu w stronę
	-- środka sceny (czyli do wnętrza pomieszczenia, nie w ścianę) i celuje w środek
	-- jego bounding boxa. Dystans rośnie z wielkością modelu, żeby RPG nie wyszedł
	-- poza kadr przy dystansie dobranym pod bombę.
	AutoCameraDistance = 12,      -- stud, minimum
	AutoCameraSizeFactor = 1.6,   -- × przekątna modelu
	AutoCameraHeight = 1,         -- stud nad środkiem modelu

	-- Server distance-check gracz↔NPC przy zakupie (hard rule #3). Większy niż zasięg
	-- promptu, żeby lag/animacja kamery nie odrzuciły legalnego zakupu; wciąż blokuje
	-- zakup z dowolnego miejsca mapy (klient odpala BuyItem, serwer waliduje odległość).
	InteractDistance = 18,
	-- Płynny przejazd kamery między itemami przy przewijaniu (s).
	CameraTweenTime = 0.35,
	-- Podniesienie punktu celowania nad środek modelu (stud). 0 = prosto w środek;
	-- lekko dodatnie ładniej kadruje wysokie modele.
	LookAtHeightOffset = 0,
	-- Przewijanie itemów klawiszami (oprócz ◀▶ w UI i scrolla) + wyjście.
	PrevKey = Enum.KeyCode.A,
	NextKey = Enum.KeyCode.D,
	CloseKey = Enum.KeyCode.Q, -- NIE Escape (otwiera menu Roblox) — Q zamyka sklep.
}

Config.Destruction = {
	-- HP strukturalne per kategoria (etap 2). Rozpoznawanie: tag "Pillar" → Pillar,
	-- Material Glass → Glass, descendant ActiveBridges → Bridge, reszta → Wall.
	Categories = {
		Wall = { HP = 100 },
		-- Szyby: giną od SAMEJ fali w osobnym, dużym promieniu (glassRadius itemu) —
		-- "szyby sypią się na sąsiednich blokach". Zero gruzu serwerowego: server tylko
		-- niszczy part, odłamki renderują klienci (payload w BlastFX).
		Glass = { HP = 1 },
		-- Filary (tag "Pillar" w Tag Editor). 300 → 180 → 140, przy jednoczesnym buffie
		-- bomby do damage=165 (2026-08-12, decyzja Kacpra: "filary padają od jednej").
		-- Przy damage=165/radius=24 trafienie z 1 studa zadaje 158, z 4 stud 138, z 9 stud 103.
		-- Czyli: filar ŚCINA jedna bomba z bliska (do ~3.8 stud), z dalszego dystansu
		-- dalej trzeba dwóch. Filar jest więc twardszy od ściany (HP 100), ale nie jest
		-- już "gąbką na 3 bomby".
		-- HP nie regeneruje się (attribute DestrHP żyje do restore mapy), więc trafienia
		-- z całej rundy sumują się. Feedback pęknięć (ciemnienie + pył) = DamageFeedback niżej.
		Pillar = { HP = 140 },
		-- Mosty (ActiveBridges): kruche drewno — bomba w pobliżu łamie na deski, deski
		-- lecą w lawę (sabotaż PvP). Remnants mostu bez podparcia też spadają (Support).
		Bridge = { HP = 40 },
	},
	PillarTag = "Pillar", -- nazwa tagu CollectionService którym Kacper oznacza filary

	-- FEEDBACK OBRAŻEŃ STRUKTURALNYCH: ranny part ciemnieje proporcjonalnie do utraconego
	-- HP + puff pyłu przy trafieniu. Kolor wraca sam po rundzie (MapService restore).
	DamageFeedback = {
		DarkenMax = 0.45,   -- max przyciemnienie koloru przy ~100% zniszczenia
		DustPerHit = 10,    -- particli pyłu przy przyjęciu obrażeń
		DustMinDamage = 20, -- poniżej tego dmg bez pyłu (krawędź zasięgu nie spamuje emitterami)
	},

	-- OSŁONA GRACZY: każda ściana między graczem a epicentrum tnie damage/knockback.
	-- Destrukcja geometrii liczy się PRZED obrażeniami graczy, więc zdmuchnięta ściana
	-- NIE osłania (została po niej dziura). Szkło i przezroczyste nie osłaniają.
	Occlusion = {
		Enabled = true,
		PerWallFactor = 0.45, -- mnożnik za KAŻDĄ ścianę (2 ściany = 0.2 efektu)
		MaxHits = 4,          -- sufit raycastów przez kolejne ściany
		MinEffect = 0.05,     -- efekt poniżej progu = brak trafienia (zero ragdolla przez 2 ściany)
	},

	-- PODPARCIE (odpowiedź na testy Kacpra: "większe party wiszą anchored po wybuchu",
	-- "wysadziłem dół i reszta wisi"). Po każdej destrukcji sprawdzamy PIONOWĄ KOLUMNĘ
	-- geometrii wokół epicentrum (kolumna, nie kula — po wysadzeniu podstawy wieży spaść
	-- mają też piętra WYSOKO nad wybuchem): part bez transytywnej drogi podparcia w dół
	-- SPADA jak gruz. Kierunkowo — sąsiad CAŁKOWICIE powyżej parta go NIE podpiera
	-- ("wiszenie na niebie" nie istnieje); kontakt boczny (przęsło, wspornik) podpiera.
	-- UWAGA kontrakt mapy: platformy/ozdoby które MAJĄ wisieć w powietrzu z designu →
	-- Locked=true albo Workspace.Map.Locked, inaczej spadną przy pierwszej bombie obok.
	-- Mosty graczy (ActiveBridges) NIE wchodzą do sprawdzenia z samej bliskości — wiszą
	-- z designu; sprawdzane są tylko ich POŁAMANE kawałki.
	Support = {
		Enabled = true,
		Padding = 0.2,          -- luz dotyku (stud) przy szukaniu sąsiadów-podpór
		ColumnRadiusFactor = 1.3, -- XZ zasięg sprawdzenia = radius wybuchu × ten mnożnik
		ColumnHeight = 400,     -- pełna wysokość kolumny sprawdzenia (stud)
		AboveEpsilon = 0.5,     -- tolerancja "całkowicie powyżej" (stud)
	},

	-- CIĘCIE partów na kawałki (Fracture.luau). Part w kuli wybuchu jest docinany do
	-- TargetChunkSize; kawałki poza kulą zostają DUŻE i wracają jako anchored "remnants"
	-- (dziura z drobnym gruzem + reszta panelu w 2-4 płytach).
	Fracture = {
		TargetChunkSize = 3.2,       -- docelowy wymiar kawałka gruzu (stud)
		MinChunkSize = 1.4,          -- poniżej tego NIE tniemy — drobnica to particle, nie party
		-- Sufit kawałków z JEDNEGO parta. Budżet idzie w całości na okolicę trafienia
		-- (Fracture tnie zawsze największy box w kuli), więc te 48 to realnie rozdzielczość
		-- DZIURY, a nie całej ściany — wielki panel dalej zostaje w 2-4 płytach.
		MaxChunksPerPart = 48,
		-- Minimalny promień dziury (stud). Dziura liczy się z modelu obrażeń
		-- (radius × (1 − HP/damage)), a ten floor gwarantuje, że part zniszczony "na styk"
		-- zostawia widoczny otwór zamiast zniknąć bez śladu.
		-- (2026-08-12: był tu jeszcze sufit MaxHoleRadius z próby nerfu — skasowany,
		-- bo przycinał wyrwy w ścianach do odprysków i psuł całe odczucie wybuchu.
		-- Górnym ogranicznikiem jest z powrotem sam promień wybuchu.)
		MinHoleRadius = 3.5,
		-- NIEREGULARNOŚĆ DZIURY. Granica dziury to nie czysta kula, tylko promień
		-- modulowany szumem Perlina zależnym od kierunku — krawędź wychodzi poszarpana
		-- ("wyrwa"), a nie okrągła/kwadratowa. 0 = idealna kula, 0.5 = mocno rwana.
		HoleIrregularity = 0.42,
		-- Skala szumu: mniejsza = duże, łagodne wybrzuszenia; większa = drobne poszarpanie.
		HoleNoiseScale = 0.14,
		-- Wariacja rozmiaru kawałka i promienia dziury PER WYBUCH — bez tego dwie bomby
		-- w tę samą ścianę dawały bliźniaczy wzór.
		ChunkSizeJitter = 0.22,
		HoleRadiusJitter = 0.15,
		MaxServerChunksPerBlast = 110, -- sufit kawałków serwerowych z JEDNEGO wybuchu
		ChunkRotJitter = 7,          -- ± stopnie obrotu kawałka przy spawnie (łamie siatkę)
		ChunkShrink = 0.96,          -- lekki shrink kawałków — szczeliny czytają się jako gruz
		WedgeChance = 0.22,          -- szansa na WedgePart zamiast boxa (poszarpane krawędzie)
	},

	-- KIERUNEK I SIŁA WYRZUTU. Stożek "na zewnątrz i w górę": stromo w epicentrum (jedyna
	-- wolna droga = góra), płasko na krawędzi. Kąt steruje odczuciem grawitacji (wysokość
	-- ∝ sin²) bez ruszania Workspace.Gravity, czyli bez psucia skoku gracza.
	Shockwave = {
		AngleNear = 45,   -- stopnie w epicentrum
		AngleFar = 25,    -- stopnie na krawędzi promienia
		AngleJitter = 10, -- ± losowe odchylenie (bez tego siatka kafli leci jak jeden blok)
		-- Skalowanie rozmiarem: scale = clamp((RefVolume/objętość)^Power, MinScale, 1).
		-- Party mniejsze od RefVolume są NIETKNIĘTE (clamp do 1) — gałka hamuje tylko kolosy.
		ReferenceChunkVolume = 200,
		SizeFalloffPower = 2 / 3,
		MinSizeScale = 0.15,
		Spin = 10, -- rad/s max losowego tumble — beton koziołkuje wolno, nie wiruje jak pocisk
	},

	-- FIZYKA I CYKL ŻYCIA gruzu serwerowego (DebrisService).
	--
	-- PRZEBUDOWA 2026-09-13 (feedback Kacpra: "dużo gruzu zostaje i laguje" + "party
	-- anchorują się w powietrzu"). Stary model miał JEDEN limit — `MaxMovingDebris` —
	-- i liczył tylko gruz W RUCHU. Kawałek, który znieruchomiał, dostawał Anchored,
	-- wypadał z licznika i ZWALNIAŁ budżet, więc suma partów nie była ograniczona
	-- niczym poza końcem rundy. Pomiar na żywej sesji: 5620 partów w `BlastDebris`
	-- przy mapie liczącej 25 332 party (+22% sceny do renderu i replikacji).
	--
	-- Model docelowy (decyzje Kacpra):
	--   * DUŻE kawałki (>= PlatformMinVolume) zostają jako chodliwe platformy — limit
	--     MaxPersistentDebris; DROBNICA gaśnie sama po TempLifetimeAfterSleep
	--   * przy pełnym budżecie nowy wybuch jest ZAWSZE pełny — miejsce robi się
	--     kasując najstarszy gruz (DebrisService.reserve), a nie tnąc świeży wybuch
	--   * gruz zatopiony lawą znika (sprzątanie nasilające się z czasem rundy)
	Debris = {
		-- Materiał: bez tego default elasticity 0.5 + friction 0.3 = "gumowe klocki LEGO".
		-- Density NIE zmienia toru lotu (prędkość nadajemy wprost) — tylko zderzenia:
		-- ciężki gruz spycha graczy i lżejsze party zamiast być odbijanym.
		Density = 3,
		Friction = 0.85,
		Elasticity = 0.05,
		FrictionWeight = 1,
		ElasticityWeight = 1,
		-- Izolacja kolizji gruz↔gruz tuż po wybuchu (solver nie zjada pędu ciasnym kawałkom).
		CollisionGroup = "BlastDebris",
		SelfCollisionTime = 0.35,
		-- Usypianie: nieruchomy kawałek → Anchored = chodliwa platforma za zero fizyki.
		SleepSpeed = 2,   -- stud/s — poniżej tego "leży"
		SleepTime = 0.6,  -- s nieprzerwanie poniżej progu przed zakotwiczeniem
		SleepCheckHz = 5,

		-- ===== BUDŻET (twardy — liczy TAKŻE uśpione party) =====
		-- Sufit wszystkiego, co jest w rejestrze gruzu. To jest ta liczba, która realnie
		-- decyduje o FPS na słabym sprzęcie — podnosić tylko po teście pod obciążeniem.
		MaxTotalDebris = 260,
		-- Ile z tego może spać jako platformy. Reszta budżetu należy do gruzu w locie,
		-- więc świeży wybuch ma gdzie wylądować nawet przy pełnej mapie platform.
		MaxPersistentDebris = 70,
		-- Od tej objętości (studs³) kawałek jest PLATFORMĄ (zostaje), poniżej DROBNICĄ
		-- (gaśnie). 45 ≈ 3.6³ — typowy kawałek z cięcia (TargetChunkSize 3.2 → ~29 studs³)
		-- jest drobnicą, a płyty z remnantów i kolapsu sekcji zostają.
		PlatformMinVolume = 45,
		-- Gwarancja dla świeżego wybuchu: bomba za 50$, która "nic nie zrobiła", wkurza
		-- bardziej niż chwilowy skok fizyki. reserve() kasuje stary gruz, żeby tyle dać.
		MinChunksPerBlast = 40,

		-- ===== WYGASANIE DROBNICY =====
		TempLifetimeAfterSleep = 6, -- s leżenia, zanim drobnica zacznie gasnąć
		TempMaxAge = 15,            -- s twardy sufit od spawnu (kawałek, który nigdy nie usnął)
		RetireFade = 0.3,           -- s półprzezroczystości przed Destroy (nie znika "pyknięciem")
		MaxRetiresPerTick = 40,     -- ile partów można wycofać w jednym ticku skanu (anty-spike)
		-- Nie kasujemy gruzu spod nóg gracza — platforma znikająca pod stopami to
		-- niezawiniona śmierć w lawie, czyli dokładnie to, co ma nie istnieć.
		RetireSafeDistance = 12,

		-- ===== PODPARCIE UŚPIONEGO GRUZU (fix "party anchorują się w powietrzu") =====
		-- Kotwiczymy DOPIERO po sprawdzeniu, że kawałek ma coś pod sobą, a potem
		-- re-weryfikujemy to cyklicznie: podpora mogła zostać wysadzona, wycofana przez
		-- budżet albo zalana lawą. Bez tego floater wisi do końca rundy — uśpiony gruz
		-- jest świadomie wykluczony z passu podparcia w DestructionService.
		SleepGroundProbe = 1.2,      -- stud raycastu pod spodem = "ma na czym stać"
		SupportRecheckInterval = 1,  -- s między sprawdzeniami tego samego uśpionego kawałka
		SupportChecksPerTick = 14,   -- sufit raycastów na tick skanu (round-robin po śpiących)

		-- ===== LAWA KASUJE ZATOPIONY GRUZ =====
		LavaCullMargin = 0.5,   -- stud: kasujemy, gdy GÓRA kawałka jest pod powierzchnią
		LavaSteamPerSecond = 3, -- sufit obłoczków pary/s (przy zalaniu tonie naraz kilkadziesiąt)
	},

	-- KOLAPS SEKCJI (etap 4 — StructureService). Filary (tag `Pillar`) grupowane w PASMA
	-- po wysokości: pasmo = filary jednego piętra. Gdy padnie odpowiednio dużo filarów
	-- pasma, wszystko POWYŻEJ tego piętra leci w dół. To jest moment "na TikToka", więc
	-- ma być czytelny: najpierw ostrzeżenie (trzeszczenie + pył), potem kolaps.
	Collapse = {
		Enabled = true,
		-- Filary, których środki Y mieszczą się w tym zakresie, to JEDNO pasmo (piętro).
		-- Za mało = każdy filar osobnym piętrem; za dużo = cały budynek jednym pasmem.
		BandTolerance = 10,
		-- Ułamek martwych filarów pasma → ostrzeżenie (creak: pył ze stropów, dźwięk, shake).
		CreakThreshold = 0.5,
		-- Ułamek martwych filarów pasma → SEKCJA LECI. 0.75 = 3 z 4 filarów; celowo nie 1.0,
		-- bo "ostatni filar w rogu trzyma wieżowiec" wygląda jak bug, nie jak fizyka.
		CollapseThreshold = 0.75,
		-- Sufit partów odkotwiczonych jednym kolapsem (największy budynek = najgorszy przypadek).
		MaxPartsPerCollapse = 220,
		-- Lekki impuls przy starcie kolapsu — sekcja "odrywa się", zamiast zjeżdżać jak winda.
		ImpulseSpread = 7,
		-- Minimalny odstęp między ostrzeżeniami z tego samego pasma (s).
		CreakCooldown = 4,
	},

	-- UDERZENIA GRUZU (etap 3 — DebrisService).
	Impact = {
		-- FALL-FRACTURE: kawałek który twardo uderzył (nagła zmiana prędkości między
		-- tickami skanu) pęka na mniejsze. TWARDY LIMIT jednej generacji — bez tego
		-- liczba partów rośnie wykładniczo. Uwaga: impuls z drugiej bomby też robi
		-- deltę prędkości → gruz "dobity" bombą pęka dalej. Celowe — czuć moc.
		FallFractureEnabled = true,
		ImpactDeltaV = 55,        -- stud/s zmiany prędkości = twarde uderzenie
		                          -- (sama grawitacja robi ~39 przy skanie 5Hz — próg wyżej)
		-- 18 → 60 (2026-09-13): fall-fracture to był GŁÓWNY mnożnik liczby partów
		-- (1 kawałek → 3, przy każdym kolapsie razy 220 partów). Przy 60 studs³ pękają
		-- tylko płyty, na których to realnie widać — typowy kawałek z cięcia (~29) nie.
		MinFractureVolume = 60,   -- studs³ — drobnica nie pęka (za mała żeby było widać)
		-- Pękanie WYŁĄCZA SIĘ, gdy rejestr gruzu jest zapełniony powyżej tego ułamka —
		-- mnożenie partów przy napiętym budżecie tylko wypycha z niego świeży wybuch.
		FractureBudgetHeadroom = 0.7,
		FracturePieces = 3,       -- na ile kawałków max pęka przy uderzeniu
		MaxGenerations = 1,       -- kawałek z kawałka JUŻ nie pęka
		InheritVelocityFactor = 0.55, -- ile prędkości dziedziczą odłamki po uderzeniu
		SpreadSpeed = 6,          -- stud/s losowego rozrzutu odłamków
		DustMinVolume = 25,       -- pył uderzenia tylko dla większych kawałków
		MaxImpactsPerTick = 6,    -- cap pęknięć per tick skanu (spike safety)

		-- CRUSH: duży, szybki kawałek gruzu rani gracza (kill credit "crushed" dla tego,
		-- kto go wystrzelił — attribute BlastAttackerId). Decyzja Kacpra z planu: TAK.
		CrushEnabled = true,
		CrushCheckHz = 10,
		CrushSpeed = 24,          -- stud/s minimum żeby kawałek był groźny
		CrushMinVolume = 8,       -- studs³ minimum (kamyczki nie zabijają)
		CrushContact = 2.5,       -- stud od POWIERZCHNI kawałka do HRP = kontakt
		CrushMaxDamage = 70,      -- dmg przy pełnej objętości i prędkości
		CrushMinDamage = 12,      -- floor — trafienie gruzem zawsze boli
		CrushVolumeForMax = 60,   -- studs³ przy których skala objętości = 1.0
		CrushSpeedForMax = 70,    -- stud/s przy których skala prędkości = 1.0
		CrushCooldown = 0.7,      -- s niewrażliwości gracza między trafieniami gruzem
	},

	-- STRONA KLIENCKA (ExplosionFXController + DebrisFXController). Wszystko lokalne,
	-- zero replikacji — dlatego liczby mogą być wysokie.
	FX = {
		-- Kosmetyczne odłamki per wybuch (skalowane jakością grafiki).
		-- 150 → 45 (2026-08-12): przy takiej chmurze NIE BYŁO WIDAĆ realnej destrukcji —
		-- dziura i lecący gruz ginęły w kurzawie. Efekty mają podkreślać zniszczenie,
		-- nie je zasłaniać.
		ClientFrags = 45,
		FragMinSize = 0.4,
		FragMaxSize = 1.5,
		FragMinSpeed = 18,
		FragMaxSpeed = 60,
		FragLifetime = 5,     -- s życia odłamka zanim shrink+fade
		FragFadeTime = 0.45,
		MaxLocalFrags = 500,  -- twardy sufit ŁĄCZNIE (FIFO — najstarsze wypadają)
		FragDensity = 0.35,   -- niska masa: odłamek muska character zamiast go spychać
		-- Szkło (etap 2): odłamki szyb renderowane lokalnie z payloadu BlastFX.
		GlassMaxPanes = 40,    -- sufit szyb w payload (server tłucze WSZYSTKIE, FX najbliższe N)
		-- ⚠️ ILE ODŁAMKÓW I JAK DUŻYCH — SKALOWANE POWIERZCHNIĄ TAFLI (poprawka 2026-09-21,
		-- zgłoszenie „rzucam bombę i szyba po prostu znika, a mam duże szyby").
		-- PRZYCZYNA BYŁA W LICZBACH, nie w wyglądzie. Stary wzór `clamp(area/10, 3, 6)`
		-- dawał, zmierzone na tej mapie:
		--     typowa tafla  30 std² (5×6)     -> 3 odłamki = 1 na 10 std²   (ledwo)
		--     duża          102 std² (2.5×41) -> 6 odłamków = 1 na 17 std²  (za mało)
		--     największa    594 std² (11×54)  -> 6 odłamków = 1 na 99 std²  (NIEWIDOCZNE)
		-- Przy odłamku długości ~1 studa sześć sztuk na ścianie 11×54 to nic — tafla jest
		-- KASOWANA i zastępowana czymś, czego nie widać. Stąd wrażenie, że znika.
		-- Teraz liczba rośnie z powierzchnią, a **ROZMIAR odłamka rośnie razem z nią**:
		-- wielka szyba ma się rozpaść na wielkie kawały, nie na tę samą drobnicę.
		ShardAreaPerShard = 5,   -- studów² tafli na jeden odłamek
		ShardsPerPaneMin = 4,
		ShardsPerPaneMax = 26,   -- sufit na JEDNĄ taflę (było 6 — to był cały problem)
		ShardsPerBlastMax = 150, -- sufit na CAŁY wybuch; tafle idą od najbliższej, więc
		                         -- przy budżecie wyczerpanym gubią się te najdalsze
		-- Skalowanie rozmiaru: „komórka" = sqrt(powierzchnia / liczba odłamków), czyli ile
		-- tafli przypada na jeden kawałek. Odnosimy ją do typowej szyby (`ShardCellRef`)
		-- i tym mnożymy bazowe wymiary. Duże tafle -> kawałki do `ShardScaleMax` razy większe.
		ShardCellRef = 2.2,
		ShardScaleMax = 3.0,
		ShardLifetime = 2.5,   -- s życia odłamka szkła zanim fade
		-- ⚠️ KSZTAŁT ODŁAMKA — OSTRY DRZAZG, NIE KWADRACIK (prośba Kacpra 2026-09-21).
		-- Poprzednio odłamek był `Part` o wymiarach (0.25..0.7, 0.25..0.7, 0.08) — obie osie
		-- w płaszczyźnie brane z TEGO SAMEGO zakresu, więc wychodziły prawie kwadratowe
		-- płytki i całość czytała się jak konfetti. Teraz to `WedgePart` (zbiega się
		-- do krawędzi = realny szpikulec) i jest WYDŁUŻONY: długość ~5× większa od szerokości.
		-- ➜ Chcesz bardziej igłowate — rozjedź `Length` od `Width`. Chcesz grubsze szkło —
		--   podnieś `Thickness`, ale powyżej ~0.2 przestaje wyglądać jak szkło.
		ShardLengthMin = 0.50,
		ShardLengthMax = 1.60,
		ShardWidthMin = 0.10,
		ShardWidthMax = 0.34,
		ShardThickness = 0.07,
		-- (Ślady opalenia USUNIĘTE 2026-08-12: raycast w dół z epicentrum kładł plamę na
		-- ziemi także przy wybuchach w powietrzu — plama pojawiała się kilkadziesiąt
		-- studów pod bombą, bez związku z tym, co gracz widział.)

		-- ===== AUDIO (etap 5) =====
		-- WSZYSTKIE puste do czasu assetów Kacpra. Wpisanie "rbxassetid://..." wystarczy —
		-- wpięcie po stronie kodu już jest, nic więcej nie trzeba ruszać.
		-- Dźwięki grają lokalnie u każdego klienta z rolloffem 3D (dalekie = ciche).
		ExplosionSoundId = "",  -- huk wybuchu
		GlassSoundId = "",      -- brzęk tłuczonej szyby (gra raz na wybuch, nie raz na taflę)
		ImpactSoundId = "",     -- grzechot gruzu uderzającego o ziemię
		CreakSoundId = "",      -- trzeszczenie konstrukcji przed kolapsem
		CollapseSoundId = "",   -- rumble walącej się sekcji
		-- Ile najwyżej dźwięków uderzeń gruzu na sekundę u jednego klienta — bez tego
		-- 200 kawałków lądujących naraz to ściana szumu i zjazd FPS na słabym sprzęcie.
		ImpactSoundsPerSecond = 6,

		-- Wstrząs ekranu przy kolapsie sekcji (mocniejszy i dłuższy niż przy wybuchu —
		-- wali się piętro, ma być czuć).
		CollapseShakeMax = 2.2,
		CollapseShakeDuration = 1.2,
		CollapseShakeDistance = 160,
		-- Ostrzeżenie (creak) — subtelne, ma niepokoić, nie oślepiać.
		CreakShakeMax = 0.5,
		CreakShakeDuration = 0.9,
		CreakShakeDistance = 110,
		-- Ambientowy screen shake dla każdego w pobliżu (trafieni dostają mocniejszy z BombHit).
		ShakeMaxDistance = 90,
		ShakeMax = 1.1,
		ShakeDuration = 0.5,
	},

	-- Log [Destr] per detonacja (struktura/kawałki/ms). WŁĄCZONE na czas strojenia —
	-- wyłączyć przed launchem (print × dziesiątki serwerów = śmieci w logach produkcji).
	Debug = true,
}

table.freeze(Config.Dev.Usernames)
table.freeze(Config.Dev)
table.freeze(Config.Game)
table.freeze(Config.UI)
-- Spawn ma Vector3 fields — freeze tylko po:
table.freeze(Config.Spawn)
table.freeze(Config.Lava.Part)
table.freeze(Config.Lava.HeatEffect)
table.freeze(Config.Lava.Surface.LayerMultipliers)
table.freeze(Config.Lava.Wobble)
table.freeze(Config.Lava.FX)
table.freeze(Config.Lava.Surface)
table.freeze(Config.Lava)
table.freeze(Config.Cash.Popup)
table.freeze(Config.Cash.PickupTrail)
table.freeze(Config.Cash.DigitDisplay)
table.freeze(Config.Cash)
table.freeze(Config.Bridge)
table.freeze(Config.Shop)
table.freeze(Config.Movement.Stamina)
table.freeze(Config.Movement.StaminaBar)
table.freeze(Config.Movement.HeadTrack)
table.freeze(Config.Movement.Camera.RotationSmoothing)
table.freeze(Config.Movement.Camera.HitReaction)
table.freeze(Config.Movement.Camera)
table.freeze(Config.Movement)
table.freeze(Config.Push)
table.freeze(Config.RateLimits)
table.freeze(Config.AntiCheat)
table.freeze(Config.Rewards)
table.freeze(Config.Destruction.Categories.Wall)
table.freeze(Config.Destruction.Categories.Glass)
table.freeze(Config.Destruction.Categories.Pillar)
table.freeze(Config.Destruction.Categories.Bridge)
table.freeze(Config.Destruction.Categories)
table.freeze(Config.Destruction.DamageFeedback)
table.freeze(Config.Destruction.Occlusion)
table.freeze(Config.Destruction.Support)
table.freeze(Config.Destruction.Collapse)
table.freeze(Config.Destruction.Impact)
table.freeze(Config.Destruction.Fracture)
table.freeze(Config.Destruction.Shockwave)
table.freeze(Config.Destruction.Debris)
table.freeze(Config.Destruction.FX)
table.freeze(Config.Destruction)
table.freeze(Config)

return Config
