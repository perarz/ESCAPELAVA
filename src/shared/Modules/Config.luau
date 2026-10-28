--!strict
-- Config.luau
-- Single source of truth dla WSZYSTKICH liczb w ESCAPE LAVA.
-- Zasada: zero magic numbers w services. Wszystko stąd.

local Config = {}

-- Cosmetic upper-body overlay; times are normalized to Duration, angles in degrees.
Config.ItemEquip = {
	Enabled = true,
	Duration = 0.3,
	ProfileDurations = { Rpg = 0.7 },
	ToolProfiles = { BombTool = "Hip", GrappleTool = "Hip", BlueprintTool = "Back", RpgTool = "Rpg", C4Tool = "Hip" },
	HoldBlendStart = 0.4,
	HoldBlendEnd = 0.84,
	HoldPoses = {
		Rpg = {
			-- 25.10 (Kacper: „bardziej na barku, nie w prawo od ciała”): rura leży na prawym barku obok
			-- głowy, lufa prosto w przód bioder, lewa dłoń pod lufą. Kąty z IK na rigu StarterCharacter
			-- RAZEM z postawą bokiem `Movement.HeadTrack.WaistYawTools.RpgTool = -50` — zmiana jednego
			-- bez drugiego krzywi lufę. Zdjęcie pozy w Edit zaakceptowane przed wpisaniem.
			-- Poprzednia poza (21.10): 33/-16.5/-49, 104.5, -64/47/-23 | 54/6/75.5, 20, -14/-35/-99.5
			-- — lufa 44,5° w lewo przez pierś, na wysokości klatki.
			Shoulder = Vector3.new(47.1, 60.6, -8.7), Elbow = Vector3.new(111.8, 0, 0), Wrist = Vector3.new(-46.7, -31.9, 5.0),
			LeftShoulder = Vector3.new(72.6, -41.0, 20.0), LeftElbow = Vector3.new(56.3, 0, 0), LeftWrist = Vector3.new(-5.9, 17.7, -39.7),
		},
	},
	Profiles = {
		Rpg = {
			-- Reach over the shoulder, clear the head, then settle into Animate's tool hold.
			{ Time = 0, Weight = 0, Shoulder = Vector3.new(150, -12, -18), Elbow = Vector3.new(105, 0, 0), Wrist = Vector3.new(-8, 0, -12), Waist = Vector3.new(0, 0, 0) },
			{ Time = 0.22, Weight = 1, Shoulder = Vector3.new(150, -12, -18), Elbow = Vector3.new(105, 0, 0), Wrist = Vector3.new(-8, 0, -12), Waist = Vector3.new(0, -9, 3) },
			{ Time = 0.4, Weight = 1, Shoulder = Vector3.new(130, -8, -24), Elbow = Vector3.new(85, 0, 0), Wrist = Vector3.new(-12, 0, -8), Waist = Vector3.new(0, -6, 2) },
			{ Time = 0.68, Weight = 1, Shoulder = Vector3.new(82, -4, -16), Elbow = Vector3.new(35, 0, 0), Wrist = Vector3.new(-5, 0, -4), Waist = Vector3.new(0, 3, 0) },
			{ Time = 0.84, Weight = 0.75, Shoulder = Vector3.new(76, 0, -6), Elbow = Vector3.new(12, 0, 0), Wrist = Vector3.new(0, 0, 0), Waist = Vector3.new(0, 1, 0) },
			{ Time = 1, Weight = 0, Shoulder = Vector3.new(80, 0, 0), Elbow = Vector3.new(0, 0, 0), Wrist = Vector3.new(0, 0, 0), Waist = Vector3.new(0, 0, 0) },
		},
		Hip = {
			{ Time = 0, Weight = 0, Shoulder = Vector3.new(-12, -8, -8), Elbow = Vector3.new(18, 0, 0), Wrist = Vector3.new(0, 0, -8), Waist = Vector3.new(0, 0, 0) },
			{ Time = 0.27, Weight = 1, Shoulder = Vector3.new(-12, -8, -8), Elbow = Vector3.new(18, 0, 0), Wrist = Vector3.new(0, 0, -8), Waist = Vector3.new(0, -5, 2) },
			{ Time = 0.45, Weight = 1, Shoulder = Vector3.new(5, -6, -12), Elbow = Vector3.new(35, 0, 0), Wrist = Vector3.new(-5, 0, 0), Waist = Vector3.new(0, -4, 1) },
			{ Time = 0.76, Weight = 0.85, Shoulder = Vector3.new(62, 0, -5), Elbow = Vector3.new(12, 0, 0), Wrist = Vector3.new(0, 0, 0), Waist = Vector3.new(0, 2, 0) },
			{ Time = 1, Weight = 0, Shoulder = Vector3.new(80, 0, 0), Elbow = Vector3.new(0, 0, 0), Wrist = Vector3.new(0, 0, 0), Waist = Vector3.new(0, 0, 0) },
		},
		Back = {
			{ Time = 0, Weight = 0, Shoulder = Vector3.new(-48, -20, -18), Elbow = Vector3.new(65, 0, 0), Wrist = Vector3.new(0, -15, -10), Waist = Vector3.new(0, 0, 0) },
			{ Time = 0.28, Weight = 1, Shoulder = Vector3.new(-48, -20, -18), Elbow = Vector3.new(65, 0, 0), Wrist = Vector3.new(0, -15, -10), Waist = Vector3.new(0, -8, 2) },
			{ Time = 0.48, Weight = 1, Shoulder = Vector3.new(-22, -12, -26), Elbow = Vector3.new(75, 0, 0), Wrist = Vector3.new(0, -8, -5), Waist = Vector3.new(0, -6, 1) },
			{ Time = 0.78, Weight = 0.85, Shoulder = Vector3.new(65, -5, -8), Elbow = Vector3.new(18, 0, 0), Wrist = Vector3.new(0, 0, 0), Waist = Vector3.new(0, 2, 0) },
			{ Time = 1, Weight = 0, Shoulder = Vector3.new(80, 0, 0), Elbow = Vector3.new(0, 0, 0), Wrist = Vector3.new(0, 0, 0), Waist = Vector3.new(0, 0, 0) },
		},
	},
}

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
	LobbyDuration = 25, -- 19.10: +10 s (prośba Kacpra „10 sekund więcej w lobby na start”)
	StartCountdown = 3,
	FinishHold = 3,

	-- ⚠️ WYŁĄCZA DOMYŚLNĄ REGENERACJĘ ŻYCIA (decyzja Kacpra 2026-09-21, razem z lawą
	-- raniącą zamiast zabijającej na miejscu). Roblox wkłada do każdej postaci skrypt
	-- `Health`, który leczy ~1% HP/s — bez jego usunięcia „giniesz po 7 s ŁĄCZNIE"
	-- nie działa, bo krótkie wejścia do lawy zdążyłyby się zaleczyć między wejściami.
	-- ⚠️ To reguła CAŁEJ GRY, nie tylko lawy: obrażenia od upadku, bomby i gruzu też
	-- przestają się goić. W 80-sekundowej rundzie bez apteczek to spójne — ale gdyby
	-- kiedyś doszło leczenie, zacząć od tej flagi.
	DisableHealthRegen = true,

	-- Ile sekund martwy gracz leży jako ragdoll, zanim wróci do lobby (decyzja Kacpra
	-- 25.09: „po śmierci od razu włącza się ragdoll i tak z 2 sekundy leżysz martwy” —
	-- wcześniej lobby ładowało się w następnej klatce i nie było widać, że i od czego się
	-- zginęło). Ragdoll przy śmierci robi toolbox (humanoid.Died), tu tylko czekamy.
	-- Od 26.09 dotyczy KAŻDEJ śmierci, także poza rundą (decyzja Kacpra: „zawsze odradzaj”).
	DeathRagdollTime = 2,

	-- Ile najdłużej spawn gracza czeka, aż skończy się poprzedni spawn TEGO SAMEGO gracza
	-- (PlayerService, `spawnBusy`). Normalnie to ułamek sekundy; limit jest po to, żeby
	-- zawieszony spawn jednego gracza nie wstrzymał startu rundy wszystkim.
	SpawnWaitMax = 5,

	-- Paczka 3 (18.10): stan startowy (runda, kasa, itemy) idzie do klienta po jego
	-- `Remotes.ClientReady`. Gdy ten nie przyjdzie w tyle sekund od dołączenia (klient
	-- padł przy starcie), serwer wysyła stan i tak — jak przed handshake'iem. Kolejny
	-- `ClientReady` wyśle go jeszcze raz, więc za krótki limit niczego nie psuje.
	ClientReadyFallback = 5,
}

-- Zapis danych gracza (PlayerDataService). Liczby przeniesione z serwisu 29.09 (zasada 5).
Config.PlayerData = {
	AutoSaveInterval = 60,   -- s między auto-zapisami jednego gracza
	InitialBackoff = 0.5,    -- s przed 2. próbą, potem ×2
	SaveRetries = 3,
	-- Wczytanie próbuje DŁUŻEJ niż zapis (decyzja Kacpra 29.09): gracz i tak czeka za ekranem
	-- ładowania, a gdy wszystkie próby zawiodą, wyrzucamy go z komunikatem — nigdy nie gra
	-- na domyślnych danych, które nadpisałyby jego wygląd i itemy. 6 prób = czekanie ~15 s.
	LoadRetries = 6,
	-- Nieudany auto-zapis wraca po tylu sekundach, nie w następnym obrocie pętli (co 5 s).
	-- Przy awarii DataStore i 50 graczach ponawianie co 5 s samo przekraczało limit zapytań.
	SaveFailRetryDelay = 30,
	-- Session lock przy wczytaniu (opis przy loadPlayer).
	LockStaleSec = 90,
	LockWaitAttempts = 3,
	LockWaitDelay = 2,
	-- Pierwszy spawn czeka na dane (decyzja Kacpra 29.09: wygląd od razu z zapisu). Sufit
	-- większy niż czekanie na lock + wszystkie próby wczytania, więc zwykle nie jest osiągany;
	-- po nim gracz dostaje spawn z losowym wyglądem tylko na to jedno życie.
	SpawnDataWaitMax = 30,
	-- BindToClose czeka na WSZYSTKIE zapisy w toku; Roblox daje ~30 s, 5 s zapasu.
	CloseWaitMax = 25,
	-- Studio zapisuje do osobnego magazynu (decyzja Kacpra 29.09) — testy nie zmieniają kont graczy.
	StudioStoreSuffix = "_Studio",
	LoadFailKickMessage = "Nie udało się wczytać Twoich danych (problem po stronie Roblox). Wejdź ponownie — Twój postęp jest bezpieczny.",
}

Config.Lava = {
	-- WŁĄCZONA z powrotem 2026-09-21 na prośbę Kacpra — oprawa lawy (embery, dym, bąble,
	-- para, światła, poświata) zapala się dopiero, gdy tafla wyjdzie z kanału ponad ulicę
	-- (`FX.MinSurfaceY`), więc przy nierosnącej lawie nie było jej jak zobaczyć.
	Enabled = true,
	StartY = -5,
	MaxY = 250,
	-- RUNDA BEZ FAZ (11.10, decyzja Kacpra „usuń fazy, płynne przyspieszanie”): lawa rośnie
	-- przez całą rundę z prędkością rosnącą LINIOWO od `SpeedStart` do `SpeedEnd`. Do 11.10
	-- były fazy Spawn/Easy/Mid/Hard/Endgame ze skokami prędkości (`Phases`, `PhaseChanged`).
	-- Całkowity przyrost = RoundDuration × (SpeedStart + SpeedEnd) / 2.
	--
	-- ⚠️ RUNDA 4-MINUTOWA NA TESTY Z LUDŹMI (od 2026-09-21, prośba Kacpra). PRODUKCJA:
	-- RoundDuration 80, SpeedStart 0, SpeedEnd 3.0 (ten sam przyrost ~120 studów w 80 s).
	-- PRZYWRÓCIĆ PRZED LAUNCHEM — GameLoopService warnuje co boot, dopóki runda > 180 s.
	-- Czas i prędkość zmieniać RAZEM: dłuższa runda przy tych samych prędkościach zalałaby
	-- mapę w połowie i test skończyłby się pływaniem.
	--
	-- Zmierzone na tej mapie: tafla startuje na Y 2.5, najwyższy dach jest na Y 109.
	-- Przyrost 120 → koniec rundy na ~Y 122, czyli **lawa zalewa wszystko** i runda
	-- naprawdę się kończy, zamiast wygasnąć na timerze. Start od prędkości 0 = pierwsze
	-- sekundy lawa prawie stoi (dawna faza „Get ready”: po 15 s +0,5 studa). Próg oprawy
	-- (`FX.MinSurfaceY` = 9, +6,5 studa) mija po ~56 s — wtedy zapalają się embery, dym,
	-- światła i poświata.
	RoundDuration = 240,
	SpeedStart = 0,    -- stud/s na starcie rundy
	SpeedEnd = 1.0,    -- stud/s na końcu rundy
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
	-- Od HumanoidRootPart do stóp (R15). „W lawie” = stopy pod taflą — ten sam próg dla obrażeń
	-- (LavaService) i dla oporu gęstej lawy (LavaSwimController), żeby nie bolało bez oporu
	-- ani nie było oporu bez bólu.
	FeetOffset = 2.5,

	Part = {
		SizeXZ = 600,
		Thickness = 6,
		Color = Color3.fromRGB(255, 80, 0),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	},
	-- GĘSTA LAWA (decyzja Kacpra 01.10: „zapada się powoli, da się wypłynąć”). Do tego dnia
	-- lawa nie miała żadnego oporu: gracz leciał na dno (ulicę pod taflą) i z głębokiej lawy
	-- nie było wyjścia, bo skok nie sięgał powierzchni. Ruch liczy klient (postać jest jego
	-- w fizyce) — LavaSwimController; obrażenia bez zmian (`Damage`), upadek do lawy nie rani
	-- (FallDamageService). Głębokość = ile STÓP jest pod taflą.
	Swim = {
		Enabled = true,
		FullDepth = 3,       -- stud: od tej głębokości stóp opór jest pełny (≈ po pas)
		Damping = 10,        -- 1/s: jak szybko lawa wyhamowuje do docelowej prędkości (wpadnięcie z dachu = kilka studów zanurzenia)
		SinkSpeed = 3,       -- stud/s: powolne opadanie, gdy nic nie robisz
		SwimUpSpeed = 7,     -- stud/s: wznoszenie przy trzymanym skoku (musi być > SinkSpeed)
		SpeedFactor = 0.45,  -- mnożnik chodu/sprintu przy pełnym zanurzeniu („jak w miodzie”)
		-- Wyjście: przy powierzchni trzymany skok wybija z lawy jak zwykły skok, żeby dało się
		-- wejść na brzeg (krawędź dachu, gruz). Niżej niż wysokość zwykłego skoku (7,2) —
		-- z lawy wychodzi się trudniej niż z ziemi.
		ExitDepth = 1.5,     -- stud: stopy najwyżej tyle pod taflą = można wyskoczyć
		ExitJumpHeight = 6,  -- stud
		ExitCooldown = 0.6,  -- s między wyskokami
	},
	-- Widok spod tafli (LavaSwimController): kamera pod powierzchnią = gęsto i pomarańczowo,
	-- nic nie widać na wylot (zgłoszenie Kacpra 01.10: „wpadniesz i przezroczysto”). Same
	-- efekty postprocesu w Lighting (jak `HeatEffect`), bez żadnego UI.
	Submerged = {
		Enabled = true,
		Tint = Color3.fromRGB(255, 120, 40),
		Brightness = 0.15,
		Contrast = -0.3,
		Saturation = 0.4,
		Blur = 24,           -- rozmycie (BlurEffect.Size) — to ono zabiera szczegóły
		LerpSpeed = 12,      -- szybkość wejścia/wyjścia efektu (1-exp(-k·dt))
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

	-- 11.10: oprawa za zgodą Kacpra — matowa skorupa, emisyjne szczeliny.
	-- Wariant materiału zapisany w Studio; instalator i cofnięcie w artifacts/lava.
	-- Texture pozostaje opcjonalne, żeby cofnięcie starej oprawy działało bez migracji.
	Surface = {
		Enabled = true,
		UpdateHz = 30, -- kosmetyka nie potrzebuje 144 aktualizacji/s
		MaxFrameStep = 0.1, -- po przycięciu nie nadrabiaj salwą efektów
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
		Amplitude = 0.45, -- stud (10.10: było 0.9 — Kacper: „zmniejsz, jak bardzo buja się lawa”)
		Period = 3.5,    -- s pełnego cyklu
		-- STOS WARSTW (2026-09-16): lawa to kilka partów jeden nad drugim. Gdyby wszystkie
		-- falowały identycznie, stos jechałby jak jeden sztywny blok i przezroczystość
		-- niczego by nie dawała. Dopiero gdy warstwy pływają WZGLĘDEM SIEBIE, widać
		-- objętość cieczy — o to w tym stosie chodzi.
		-- 2) RÓŻNICOWY — warstwy pływają WZGLĘDEM SIEBIE (efekt cieczy o objętości).
		--    Ten zjada szczelinę między warstwami, więc kod przycina go do niej
		--    (`MaxGapUsage`) — podnoszenie go bez rozsunięcia warstw w Studio nic nie da.
		--    Inny okres niż wspólny, żeby ruch nie wyglądał jednostajnie.
		LayerAmplitude = 0.2, -- 10.10: było 0.35
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

	-- Connected cosmetic mesh; disable to retain the original flat surface.
	Waves = {
		Enabled = true,
		Cells = 24,
		Amplitude = 1.05,
		Wavelength = 96,
		CrossWavelength = 130,
		Period = 7,
		CrossPeriod = 9,
		CrossWeight = 0.3,
		DirectionZ = 0.45,
		CrossDirectionX = 0.55,
		TileSize = 44,
		UpdateHz = 20,
	},

	-- V5: fixed local pool, 8 vents on HIGH / 4 on LOW (`Config.Settings` → graphics).
	-- Tylko LavaSurfaceController. Damage/Submerged/Swim są niezależne.
	FX = {
		MinSurfaceY = 9,
		MinSurfaceHysteresis = 1.2,
		Distance = 140,
		VentCount = 8,
		LowVentCount = 4,
		LowLightCount = 1,
		LowParticleScale = 0.55,
		EmitterLift = 0.18,
		CoreSeconds = 0.5,
		CoreStartScale = 0.6,
		CoreSpread = 0.5,
		CoreThickness = 0.12,
		CoreLift = 0.04,
		CoreTransparency = 0.4,
		EmberDrag = 1.4,
		SmokeDrag = 0.6,
		SmokeDrift = Vector3.new(0.6, 0.35, -0.3),
		LightBreath = 0.14,
		LightBreathSpeed = 2.3,
		VentSpread = 48,
		VentMinRadius = 10,
		RelocateDistance = 85,
		CycleMin = 4.8,
		CycleMax = 6.8,
		GrowFraction = 0.42,
		PopFadeFraction = 0.08,
		BubbleMin = 1.8,
		BubbleMax = 5.2,
		BubbleHeightRatio = 0.32,
		BubbleColor = Color3.fromRGB(38, 20, 23),
		HotColor = Color3.fromRGB(210, 18, 25),
		CoolColor = Color3.fromRGB(48, 6, 12),
		SmokeColor = Color3.fromRGB(52, 52, 56),
		SmokeEndColor = Color3.fromRGB(28, 28, 32),
		SparkTexture = "rbxasset://textures/particles/sparkles_main.dds",
		SmokeTexture = "rbxasset://textures/particles/smoke_main.dds",
		EmberRate = 1.5,
		EmberLifeMin = 0.8,
		EmberLifeMax = 1.5,
		EmberSpeedMin = 1.5,
		EmberSpeedMax = 4,
		SmokeRate = 1.5,
		SmokeLifeMin = 1.4,
		SmokeLifeMax = 2.2,
		SmokeSpeedMin = 1.5,
		SmokeSpeedMax = 3.5,
		SmokeSizeMin = 2,
		SmokeSizeMax = 7,
		SmokeBurst = 5,
		SparkBurst = 9,
		DropBurst = 5,
		DropLifeMin = 0.45,
		DropLifeMax = 0.85,
		DropSpeedMin = 9,
		DropSpeedMax = 15,
		DropGravity = 38,
		LightCount = 2,
		LightRange = 11,
		LightHeight = 1.2,
		LightColor = Color3.fromRGB(255, 42, 30),
		LightBaseBrightness = 0.8,
		LightPopBrightness = 1.5,
		LightFadeSeconds = 0.45,
	},

	-- 27.10, tylko GRAPHICS HIGH (LavaSurfaceController). Stała łuna na ścianach tuż nad lawą:
	-- siatka PointLightów wokół kamery, oczka nie jadą za kamerą (zmiana oczka = zgaś → przenieś
	-- → zapal). ⚠️ Range = przebicie stropu (reguła 21.09, stropy co ~14): 12 = jedna
	-- kondygnacja. Mocniej = Brightness, NIGDY Range. Bramka jak ambient (lawa nad ulicą).
	Glow = {
		Grid = 3,            -- siatka Grid × Grid świateł wokół kamery
		Spacing = 20,        -- stud między światłami
		Lift = 1.5,          -- stud nad taflą
		Range = 12,
		Brightness = 2.2,
		Color = Color3.fromRGB(255, 70, 35),
		FadeTime = 0.6,      -- s zapalania / gaszenia oczka
	},

	-- 27.10, tylko GRAPHICS HIGH (LavaSurfaceController). Iskry i popiół z tafli wokół kamery,
	-- ilość rośnie z wysokością lawy. ⚠️ Particle NIE kolidują z geometrią — o tym, dokąd
	-- dolecą, decyduje czas życia × prędkość: w kanale (lawa pod ulicą, `FX.MinSurfaceY`)
	-- wznoszą się najwyżej do jezdni minus `CanalMargin`, nad ulicą najwyżej `MaxRise`.
	-- Dzięki temu nie wylatują nad ulicę i nie sypią do pokoi wyżej (to samo piętro co Glow).
	Air = {
		HalfSize = 55,       -- stud: pół boku pudła emisji wokół kamery
		Lift = 0.4,
		MaxRise = 8,         -- stud nad taflą, gdy lawa jest nad ulicą
		CanalMargin = 1,     -- stud zapasu pod jezdnią, gdy lawa jest w kanale
		MinRise = 1,         -- poniżej tego zapasu nic nie emitujemy
		RampStartY = 2.5,    -- wysokość tafli = najmniej (start rundy)
		RampEndY = 100,      -- wysokość tafli = najwięcej (najwyższy dach ~109)
		EmberRateMin = 4, EmberRateMax = 28,   -- iskier/s w całym pudle
		AshRateMin = 3, AshRateMax = 20,       -- płatków popiołu/s
		EmberSpeedMin = 2.5, EmberSpeedMax = 5,
		AshSpeedMin = 0.6, AshSpeedMax = 1.4,
		EmberColor = Color3.fromRGB(255, 105, 40),
		EmberEndColor = Color3.fromRGB(210, 18, 25),
		AshDrift = Vector3.new(0.5, 0, -0.3),  -- boczny dryf popiołu (bez składowej Y — liczy się do MaxRise)
		AshColor = Color3.fromRGB(95, 92, 96),
		AshEndColor = Color3.fromRGB(55, 53, 58),
	},

	-- 27.10, tylko GRAPHICS HIGH (LavaSplashController). Rozbryzg, dym i krótki błysk, gdy
	-- czyjaś postać WPADA stopami pod taflę. Liczone z ruchu postaci po stronie klienta —
	-- bez remote'ów. Lawa podchodząca pod stojącego gracza = bez efektu (`MinFallSpeed`).
	-- Śmierć w lawie ma osobny, serwerowy efekt (LavaService) — ten zostaje.
	Splash = {
		UpdateHz = 15,
		Distance = 160,      -- stud od kamery
		MinFallSpeed = 12,   -- stud/s w dół przy wejściu w taflę
		FullFallSpeed = 45,  -- przy tej prędkości efekt jest pełny
		MinStrength = 0.4,
		Cooldown = 1.2,      -- s na postać (wyskok i ponowne wpadnięcie)
		Pool = 4,            -- gotowe zestawy efektu, używane po kolei
		DropBurst = 26,
		SparkBurst = 18,
		SmokeBurst = 10,
		DropSpeedMin = 14, DropSpeedMax = 26,
		DropGravity = 55,
		FlashRange = 12,     -- reguła 21.09 jak Glow
		FlashBrightness = 6,
		FlashTime = 0.35,
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
	-- ScreenGui skalowane tą samą regułą (HudScaleController). 18.10: + panel ekwipunku.
	ScaledGuis = { "HUD", "Inventory", "ShopUI", "Settings" }, -- 21.10: + sklep; 26.10: + ustawienia
	MinScale = 0.5,         -- safety: nie zmniejszaj HUD poniżej połowy (mikro-okna)
	MaxScale = 2.0,         -- safety: nie rozdmuchuj powyżej 2× (ultra-tall porty)

	-- Numer wersji w prawym dolnym rogu (HUD.Version.VersionLabel, 27.10). Podbijać przy
	-- publikacji — gracz na zrzucie z błędem od razu pokazuje, na której wersji grał.
	Version = "0.8",

	-- Wyciągnięcie itemu w pasku (HotbarController, 11.10): wybrany slot podskakuje, zostaje
	-- wyżej i trochę większy, ikona się buja; po schowaniu opada. Px = px projektu.
	HotbarEquip = {
		-- 18.10 (zgłoszenie Kacpra: „sloty lekko nachodzą, przejście ma być płynne jak w grze”):
		-- bez skoku skali do 1,2 w jednej klatce (to wjeżdżało na sąsiada i szarpało) — skala
		-- i pozycja jadą jednym płynnym tweenem; sloty w Studio rozsunięte na 30 px odstępu.
		Raise = 16,           -- px: o ile wybrany slot jest wyżej
		RaiseTime = 0.24,     -- s: wjazd w górę
		SelectedScale = 1.05, -- skala wybranego slotu (przy odstępie 30 px nie dotyka sąsiada)
		ScaleTime = 0.3,      -- s: dojście do tej skali (Back = lekkie przestrzelenie)
		IconWiggle = 8,       -- stopnie: bujnięcie ikony przy wyciągnięciu (tam i z powrotem)
		WiggleTime = 0.14,    -- s: jedna strona bujnięcia
		DropTime = 0.24,      -- s: opadnięcie po schowaniu / zmianie slotu
		StrokeTime = 0.2,     -- s: zmiana ramki (czarna ↔ biała)
		DeselectDelay = 0.12, -- s: zwłoka opadnięcia, gdy NIC innego nie jest wybrane (auto-re-equip
		                      --    bomby po rzucie nie szarpie slotem); przy zmianie slotu — od razu
	},

	-- Ekwipunek / loadout (InventoryController + LoadoutState, 18.10). Kontrakt panelu:
	-- docs/STUDIO_CONTRACT.md → „Ekwipunek”.
	Inventory = {
		ToggleKey = Enum.KeyCode.I,  -- `E` = ProximityPrompt sklepu, `Tab` = lista graczy
		SendDelay = 0.25,     -- s: szybkie kliknięcia → jedna wysyłka ostatniego stanu
		-- Wygląd (19.10, trzecia wersja — Kacper: „bardziej klasycznie, czarny obrys wszędzie,
		-- pasuje do reszty UI”): panel z czarnym obrysem jak sloty paska, nagłówek w gradiencie
		-- licznika czasu, karty itemów w kolorze itemu ze studsami, sloty loadoutu = klony slotu
		-- paska na pasie płynącej lawy.
		OpenTime = 0.3,       -- s: panel wskakuje (Back) i ściemnia tło
		OpenDrop = 40,        -- px: z jak wysoka panel opada przy otwarciu
		ClosedScale = 0.9,    -- skala panelu na starcie wskoku
		BackdropTransparency = 0.45, -- ściemnienie gry pod otwartym panelem
		HoverScale = 1.07,    -- karta / przycisk pod kursorem
		HoverTilt = -3,       -- stopnie: karta pod kursorem lekko się przechyla (19.10, „bardziej zanimuj”)
		IntroDelay = 0.08,    -- s: po otwarciu karty i sloty wskakują po kolei…
		IntroStagger = 0.045, -- …co tyle sekund jedna po drugiej
		IntroTime = 0.32,     -- s: wskok jednej karty (Back)
		CloseDrop = 50,       -- px: panel opada przy zamykaniu
		FlyTime = 0.28,       -- s: ikona przelatuje z półki do slotu
		SnapDrop = 40,        -- px: ikona wpada do slotu z tej wysokości…
		SnapTime = 0.4,       -- …i odbija się (Bounce)
		DragThreshold = 10,   -- px: od tylu ruch z wciśniętym przyciskiem to przeciąganie, nie klik
		-- Przeciąganie całej karty / slotu (19.10, prośba Kacpra: „cały slot się porusza i elastycznie
		-- wraca albo wchodzi na loadout”).
		DragLift = 1.1,       -- karta „uniesiona” w trakcie przeciągania
		DragOriginScale = 0.85, -- miejsce, z którego ją wzięto, kurczy się na ten czas
		DragTiltPerPx = 0.6,  -- stopnie przechyłu na piksel ruchu w klatce…
		DragTiltMax = 14,     -- …najwyżej tyle
		DropTime = 0.55,      -- s: sprężysty wskok do slotu (Elastic)
		ReturnTime = 0.65,    -- s: sprężysty powrót na miejsce (Elastic)
		LavaScroll = { 16 },  -- px/s: przesuw lawy w panelach (`Lava1`; 19.10: jedna warstwa, druga usunięta)
		StatMax = 5,          -- pełny pasek cechy = 5 studsów (`ItemDefinitions.<id>.stats`)
		StatTime = 0.35,      -- s: dojazd pasków przy zmianie itemu
		-- DETAILS (19.10, prośba Kacpra: „kręcenie się itemu i real oświetlenie”): ViewportFrame ma
		-- uproszczone światło (szarawe), więc item to PRAWDZIWY obiekt w świecie — lokalna,
		-- pomniejszona kopia tuż przed kamerą, widoczna przez okno w panelu (`Details.Window`),
		-- z lampami jak na zdjęciach ikon. Liczby względem promienia modelu po pomniejszeniu.
		ModelSpin = 0.7,      -- rad/s: obrót itemu
		ModelTilt = 18,       -- stopnie: item pochylony do kamery (widać go lekko z góry)
		ShowcaseRadius = 0.3, -- studs: promień itemu po pomniejszeniu (blisko kamery = nic ze świata nie wejdzie)
		ShowcaseFill = 0.85,  -- jaką część wysokości okna zajmuje kula opisana na itemie (margines od ramki)
		ShowcaseBackDepth = 8, -- tło tyle promieni za itemem (dalej niż lampy — inaczej łapie ich światło)
		ShowcaseBackColor = Color3.fromRGB(20, 17, 24), -- tło za itemem (Neon = równy kolor, ciemniejszy od panelu)
		-- lampy: przesunięcie w promieniach (x w prawo, y w górę, z do kamery), jasność, zasięg w promieniach
		ShowcaseLights = {
			{ offset = Vector3.new(-3.4, 3.8, 4.2), brightness = 4, range = 12, color = Color3.fromRGB(255, 236, 210), shadows = true },
			{ offset = Vector3.new(3, 2.1, -3), brightness = 5, range = 8.5, color = Color3.fromRGB(170, 205, 255), shadows = false },
			{ offset = Vector3.new(3.4, -0.85, 4.2), brightness = 1.2, range = 10, color = Color3.fromRGB(255, 245, 235), shadows = false },
		},
		-- Kolor karty itemu. Nowy item bez wpisu = `DefaultItemColor`; x0 = szara karta.
		ItemColors = {
			bomb = Color3.fromRGB(226, 52, 40),
			bridge_builder = Color3.fromRGB(196, 128, 62),
			grapple = Color3.fromRGB(35, 120, 230),
			energy_drink = Color3.fromRGB(140, 60, 220),
			rpg = Color3.fromRGB(95, 120, 50),
			c4 = Color3.fromRGB(70, 74, 84), -- 25.10: grafit (kostka ma oliwkowe belki jak RPG — kolor inny)
		},
		DefaultItemColor = Color3.fromRGB(120, 190, 60),
		EmptyItemColor = Color3.fromRGB(95, 90, 100),
		-- Wzór karty itemu (23.10, Kacper: „nie tylko kolory, wywal studsy, ciekawe patterny, droższe
		-- = bardziej dojebane”; bez napisów rzadkości i bez podziału na poziomy — każdy item po swojemu).
		-- Layers (najwyżej 2) = paski z jednego UIGradient na `Fill.Pattern1/2` — rysuje je Roblox, więc
		-- są ostre w każdej skali (UI_RULES 6): Rotation (°), Count (1-4 pasy: sufit 20 punktów
		-- gradientu), Width (część okresu zajęta przez pas), Color, Transparency (0 pełny, 1 brak),
		-- Offset (przesunięcie wzoru, część karty). Dodatki: Rim = dwa kolory wewnętrznej ramki,
		-- Sweep = co ile s przelatuje błysk, Sparkles = migające iskierki. Item bez wpisu = gładka karta.
		CardStyles = {
			energy_drink = { -- 25$: same ukośne paski
				Layers = { { Rotation = 60, Count = 4, Width = 0.42, Color = Color3.new(1, 1, 1), Transparency = 0.8 } },
			},
			grapple = { -- 40$: siatka jak z liny
				Layers = {
					{ Rotation = 45, Count = 4, Width = 0.2, Color = Color3.new(1, 1, 1), Transparency = 0.78 },
					{ Rotation = -45, Count = 4, Width = 0.2, Color = Color3.new(1, 1, 1), Transparency = 0.78 },
				},
			},
			bomb = { -- 50$: taśma ostrzegawcza + żółta ramka
				Layers = { { Rotation = 35, Count = 4, Width = 0.5, Color = Color3.new(0, 0, 0), Transparency = 0.55 } },
				Rim = { Color3.fromRGB(255, 235, 50), Color3.fromRGB(255, 140, 0) },
			},
			rpg = { -- 75$: wojskowe pasy + oliwkowo-złota ramka + błysk
				Layers = {
					{ Rotation = -30, Count = 3, Width = 0.45, Color = Color3.new(0, 0, 0), Transparency = 0.6 },
					{ Rotation = 70, Count = 2, Width = 0.3, Color = Color3.fromRGB(225, 235, 150), Transparency = 0.75 },
				},
				Rim = { Color3.fromRGB(240, 245, 160), Color3.fromRGB(125, 155, 40) },
				Sweep = 3.4,
			},
			c4 = { -- 60$: czarne opaski jak na kostce + czerwona ramka jak dioda
				Layers = { { Rotation = 90, Count = 3, Width = 0.25, Color = Color3.new(0, 0, 0), Transparency = 0.5 } },
				Rim = { Color3.fromRGB(255, 90, 70), Color3.fromRGB(170, 20, 20) },
			},
			bridge_builder = { -- 100$: złota krata + złota ramka + błysk + iskierki
				Layers = {
					{ Rotation = 45, Count = 4, Width = 0.22, Color = Color3.fromRGB(255, 228, 120), Transparency = 0.5 },
					{ Rotation = -45, Count = 4, Width = 0.22, Color = Color3.fromRGB(255, 228, 120), Transparency = 0.5 },
				},
				Rim = { Color3.fromRGB(255, 248, 170), Color3.fromRGB(255, 170, 20) },
				Sweep = 2.4,
				Sparkles = true,
			},
		},
		CardSweepTime = 0.75,     -- s: jeden przelot błysku przez kartę
		CardSparklePeriod = 1.8,  -- s: jedno mignięcie iskierki (każda w innej fazie)
		SelectedColor = Color3.fromRGB(255, 255, 255), -- obrys wybranej karty / slotu-celu (jak w pasku)
		EmptyColor = Color3.fromRGB(235, 45, 45), -- x0: puls ramki slotu PASKA w lobby
		EmptyPulsePeriod = 1.1, -- s: jeden puls
		-- DETAILS jako osobne okno (19.10, decyzja Kacpra): wysuwa się zza głównego okna po kliknięciu
		-- itemu, a para zjeżdża razem na środek. Klik = podgląd; do loadoutu przycisk w DETAILS.
		DetailsGap = 24,      -- px: odstęp między głównym oknem a DETAILS
		DetailsSlideTime = 0.32, -- s: wysuwanie / chowanie DETAILS (Back przy wysuwaniu)
		AddText = "ADD TO LOADOUT",
		RemoveText = "REMOVE",
		SwapText = "SWAP INTO SLOT",
		PickSlotText = "PICK A SLOT TO SWAP",
		AddColors = { Color3.fromRGB(70, 215, 95), Color3.fromRGB(10, 140, 52) },   -- gradient jak kasa
		RemoveColors = { Color3.fromRGB(255, 95, 80), Color3.fromRGB(200, 30, 25) }, -- jak X
		SwapColors = { Color3.fromRGB(255, 240, 33), Color3.fromRGB(255, 130, 0) },  -- jak licznik czasu
		ShopFullText = "ADD IT IN INVENTORY",
	},

	-- Licznik czasu na górze (UIController, 11.10): wskok napisu przy zmianie stanu i nerwowe
	-- ostatnie sekundy (czerwony gradient + wskok co sekundę).
	Timer = {
		StatePop = 1.25,      -- skala napisu stanu w chwili zmiany (LOBBY → ROUND → ROUND OVER)
		StatePopTime = 0.4,
		UrgentSeconds = 10,   -- od ilu sekund do końca odliczanie robi się nerwowe
		TickPop = 1.22,       -- wskok czasu co sekundę w tej końcówce
		TickPopTime = 0.3,
		UrgentTop = Color3.fromRGB(255, 150, 120),   -- gradient czasu w końcówce (góra → dół)
		UrgentBottom = Color3.fromRGB(215, 25, 25),
	},
}

-- Loadout (18.10): ile itemów gracz bierze na rundę. Zmiana liczby = nowe sloty w HUD.Hotbar
-- i w panelu Inventory (kontrakt w docs/STUDIO_CONTRACT.md).
Config.Loadout = {
	Slots = 3,
}

Config.Spawn = {
	-- Wysokość offsetu nad lobby spot Part (gracz ląduje LobbyYOffset stud nad jego topem).
	LobbyYOffset = 5,
	-- Fallback gdyby Workspace.Lobby.Spawn nie istniał (na czas zanim Kacper postawi).
	FallbackLobbyPosition = Vector3.new(0, 10, 0),
	FallbackRoundPosition = Vector3.new(0, 10, 0),
}

-- Odbudowa mapy po rundzie (MapService, 07.10). Do tej pory po KAŻDEJ rundzie kasowane
-- i stawiane od nowa było całe miasto (25,6 tys. partów): każdy klient dostawał całą
-- mapę jeszcze raz, a silnik przeliczał jej cienie i oświetlenie od zera. Teraz mapa
-- dzieli się na JEDNOSTKI (dziecko każdego folderu z listy niżej = jeden budynek albo
-- jedna grupa dekoracji) i odbudowywane są tylko te, których odcisk się zmienił.
Config.Map = {
	-- Ścieżki od `Workspace.Map`, przez nazwy dzieci. KAŻDE dziecko wskazanego folderu
	-- to osobna jednostka. Wszystko inne pod `Workspace.Map` (poza `Locked`) też jest
	-- jednostką — w całości.
	RestoreGroups = {
		{ "Map", "Map", "Buildings" },
		{ "Map", "Map", "OutsideDecorations" },
	},
	-- Odcisk to sumy (w liczbach podwójnej precyzji) pozycji, rozmiarów, osi i kolorów
	-- partów — różnica poniżej tej wartości to szum kolejności sumowania w świeżym klonie,
	-- nie zniszczenie. Najmniejsza widoczna zmiana (1/255 koloru) jest ~40× większa.
	RestoreTolerance = 1e-4,
}

-- Ciemne przejście przy teleporcie na mapę (RoundTransitionController, 07.10). Zgłoszenie
-- Kacpra: po teleporcie z lobby budynki są, ale cienie i oświetlenie dochodzą 10-20 s.
-- Ekran ściemnia się pod koniec odliczania i rozjaśnia, gdy gracz stoi już na mapie, a
-- silnik miał chwilę na zbudowanie oświetlenia wokół kamery (świat renderuje się POD
-- zasłoną, więc ten czas nie idzie na marne).
Config.RoundTransition = {
	ResetCoverTime = 0.6,
	PrepareMaxHold = 20,
	ExitHold = 1.2,
	CountdownScale = 0.5,        -- 26.10: 0,63 → 0,5 (Kacper: „mniejsze”)
	CountdownPopTime = 0.32,     -- 26.10: mocniejszy wskok z odbiciem (było 0,22 / 1,15)
	CountdownStartScale = 1.6,
	FadeInTime = 0.35,      -- ściemnianie pod koniec odliczania lobby
	FadeOutTime = 0.5,      -- rozjaśnianie na mapie
	-- Ile trzymać ciemno PO tym, jak gracz stoi na mapie — czas dla oświetlenia i cieni.
	-- Gałka do strojenia w Play: jeśli cienie dalej doskakują, podnieść; każda sekunda
	-- zabiera sekundę z początku rundy (lawa wtedy jeszcze prawie stoi).
	SettleTime = 1.2,
	-- Sygnał „stoisz na mapie” (Remotes.AliveChanged true) nie przyszedł — gracz nie jest
	-- w tej rundzie (np. dołączył w ostatniej chwili lobby). Zdejmujemy zasłonę.
	SpawnSignalTimeout = 2.5,
	-- Twardy sufit całej zasłony: ciemny ekran, który wisi, jest gorszy od doskakujących cieni.
	MaxHold = 5,
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
	-- zwykłego tekstowego licznika (FredokaOne + UIGradient + UIStroke, styl Kacpra);
	-- aktualnego HUD CashLabel, który aktualizuje CashCounterController. Enabled = true przywraca cyfry-obrazki.
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

	-- LECĄCE BANKNOTY (10.10, pomysł Kacpra; zastępuje popup „+10$”, usunięty jego decyzją).
	-- Każdy ZAROBEK (zbieranie, zabójstwo, wygrana): banknoty wyskakują na środku ekranu,
	-- lecą do ikony licznika, licznik podskakuje przy każdym dolocie, a liczba rośnie płynnie
	-- do nowej sumy. Wydatek (sklep) → liczba spada od razu, bez banknotów. CashCounterController.
	Fly = {
		-- Ile banknotów przy danej kwocie: pierwszy wiersz, którego próg ≤ kwota.
		Notes = { { 100, 6 }, { 25, 3 }, { 0, 1 } },
		AppearTime = 0.18, -- s: wyskok banknotu na środku (od zera do pełnego rozmiaru)
		HoldTime = 0.28,   -- s: chwila na środku przed lotem (11.10: było 0.08, Kacper „0,2 s dłużej”)
		FlyTime = 0.5,     -- s: lot do ikony licznika
		Stagger = 0.09,    -- s: odstęp między kolejnymi banknotami jednego zarobku
		StartJitter = 70,  -- px projektu: rozrzut miejsca startu wokół środka ekranu
		EndScale = 0.45,   -- rozmiar przy liczniku względem wzoru
		Spin = 25,         -- ± stopnie obrotu w locie (losowo)
		PopScale = 1.18,   -- podskok licznika przy dolocie banknotu
		PopTime = 0.22,    -- s: powrót z podskoku
		IconTilt = 12,     -- stopnie: przechył ikony przy dolocie (na przemian w lewo / w prawo)
		-- Efekt zarobku na ŚRODKU ekranu (10.10 wieczór, Kacper: „nikt nie patrzy w róg”, potem
		-- „ulepsz 5×”): błysk, promienie, dwa pierścienie, iskierki z opadaniem, gwiazdki. Wygląd
		-- warstw = wzory `HUD.Cash*Template`; tu liczby. Przy liczniku został tylko `Body.Glow`.
		FlashTime = 0.45,      -- s: błysk rośnie i gaśnie
		RayCount = 10,         -- promieni przy 1 banknocie
		RayPerNote = 2,        -- + za każdy kolejny banknot
		RayInner = 40,         -- px projektu: promień startuje tyle od środka
		RayTime = 0.5,
		RingTime = 0.45,       -- s: pierwszy pierścień (drugi o 30% dłużej, 45% większy)
		RingGap = 0.09,        -- s: opóźnienie drugiego pierścienia
		-- ⚠️ 11.10: iskierki USUNIĘTE decyzją Kacpra (skasowany wzór `HUD.CashSparkTemplate`) —
		-- liczby Spark* działają dopiero, gdy wzór wróci do HUD.
		SparkCount = 14,       -- iskierek przy 1 banknocie
		SparkPerNote = 4,      -- + za każdy kolejny (25$ → 22, 100$ → 34)
		SparkDistance = 240,   -- px projektu: zasięg wylotu (losowo 50-120%)
		SparkFall = 70,        -- px projektu: opadanie po wylocie
		SparkTime = 0.75,      -- s: wylot (45%) + opadanie i zgaśnięcie (55%)
		SparkScaleMin = 0.6,   -- rozmiar iskierki względem wzoru (losowo z zakresu)
		SparkScaleMax = 1.6,
		TwinkleCount = 6,      -- gwiazdek przy 1 banknocie (+1 za każdy kolejny)
		TwinkleMinRadius = 90, -- px projektu: gdzie migoczą (pierścień wokół środka)
		TwinkleMaxRadius = 260,
		TwinkleSpread = 0.35,  -- s: rozrzut momentu pojawienia się
		TwinkleTime = 0.45,    -- s: wskok + zniknięcie jednej gwiazdki
		GlowTime = 0.35,     -- s: zgaśnięcie poświaty
		GlowAlpha = 0.45,    -- przezroczystość poświaty w szczycie błysku (0 = pełna)
		ShineTime = 0.55,    -- s: jeden przejazd połysku przez napis kasy przy dolocie banknotu
		CountRate = 6,     -- jak szybko liczba dogania sumę (1/s; więcej = szybciej) — w górę i w dół
		SpendTilt = 7,     -- stopnie: zachwianie licznika przy wydatku (11.10)
		SpendTime = 0.55,  -- s: powrót z zachwiania (sprężyście)
	},
}

Config.Bridge = {
	-- Kolory ghost preview (klient-side podgląd przed kliknięciem LMB).
	GhostColorOK = Color3.fromRGB(100, 220, 120),       -- zielony — w zasięgu, można budować
	GhostColorBad = Color3.fromRGB(220, 80, 80),        -- czerwony — za daleko lub invalid
	-- ⚠️ 0 = NIEPRZEZROCZYSTY, CELOWO (zgłoszenie Kacpra 08.10: „gdy w tle lawa, ghosta nie ma,
	-- a na tle budynku jest”). Wierzchnia warstwa lawy (`LavaSurface`, przezroczystość 0,55 —
	-- prześwit świecącego `LavaMid`) i półprzezroczysty ghost to DWIE przezroczyste rzeczy;
	-- silnik sortuje je po odległości środka, a środek tafli 512×457 bywa bliżej kamery niż
	-- ghost — lawa rysowała się na wierzchu i `Highlight` tego nie ratował. Nieprzezroczysty
	-- ghost idzie w zwykłym przebiegu z głębią, więc lawa za nim nie ma jak go zakryć.
	-- Decyzja Kacpra: nieprzezroczysty ghost zamiast nieprzezroczystej lawy (lawa traciłaby
	-- prześwit). Wartość > 0 wraca do starego błędu.
	GhostTransparency = 0,

	-- ⚠️ GHOST MUSI MIEĆ `Highlight` — BEZ NIEGO ZNIKA NAD LAWĄ (zgłoszenie 2026-09-21:
	-- „lawa w tle działa jak maska i nie widać zielonego ghosta").
	-- Mechanizm to ta sama rodzina buga co „pod kątem znika tekstura lawy": part
	-- z `Transparency > 0` trafia do KOLEJKI PRZEZROCZYSTEJ, a Roblox sortuje ją po
	-- odległości OBIEKTU. Warstwy lawy są przezroczyste (0.35 / 0.55) i wielkie
	-- (512×457), więc sortują się niestabilnie względem małego ghosta i potrafią zostać
	-- narysowane PO nim — czyli zamalować go. Żadna wartość `GhostTransparency` > 0 tego
	-- nie wygra, bo problem jest w kolejności rysowania; wygrywa tylko 0 (ghost wychodzi
	-- z kolejki przezroczystej — patrz `GhostTransparency` wyżej, 08.10).
	-- 🔴 Założenie z 21.09, że `Highlight` „renderuje się poza tą kolejką, więc jest odporny
	-- z definicji”, okazało się w grze NIEPRAWDZIWE (Kacper 08.10: na tle lawy ghosta dalej
	-- nie widać). Highlight zostaje dla konturu, ale nie on trzyma widoczność.
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
	-- Most to FIZYKA od postawienia (decyzja Kacpra 01.10). Deska, która przy postawieniu
	-- utkwiła w murku albo gzymsie dachu, nie zderza się z nim (inaczej silnik wypycha bryłę
	-- „wybuchowo” — ta sama lekcja co grupy kolapsu 25.09). Pudło deski zwężone o tyle z każdej
	-- strony, żeby leżenie NA dachu nie liczyło się jako utknięcie.
	SpawnOverlapInset = 0.1,
	-- Most, którego spód jest najwyżej tyle nad taflą lawy, jest „na lawie” — z fizyką od razu
	-- by w niej utonął (lawa nie ma kolizji), więc ghost jest czerwony, a serwer odrzuca budowę
	-- PRZED zabraniem itemu (decyzja Kacpra 01.10). Zapas pokrywa falowanie tafli i to, ile
	-- lawa urośnie, zanim prośba dojdzie do serwera — klient i serwer liczą tym samym progiem.
	LavaMargin = 1,
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
		-- Grubość obrysu jako ułamek SZEROKOŚCI paska na ekranie (11.10). Pasek ma rozmiar w
		-- studach, a obrys w pikselach — bez tego 2,3 px było za cienkie na dużym monitorze
		-- i za grube na telefonie. 0.1 ≈ dawne 2,3 px przy typowym oddaleniu kamery.
		BorderToWidth = 0.1,
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
		-- (wyglądałoby jak ukłon) — poza narzędziami z listy niżej.
		WaistYawRatio = 0.3,
		-- 24.10 (decyzja Kacpra): z tym narzędziem w ręce taka część pitch'a idzie na talię —
		-- tułów razem z wyrzutnią celuje w górę/dół, reszta zostaje na głowie. Klucz = nazwa Toola.
		-- 25.10: 1 = lufa dokładnie w górę/dół za kamerą (było 0.6 — lufa szła tylko 60% kąta).
		-- ⚠️ Nie przenosić pochylenia na barki: przy postawie bokiem (niżej) oś barków leży pod
		-- kątem 45° do lufy, więc obrót barków przechyla wyrzutnię krzywo (próba z 25.10, cofnięta).
		WaistPitchTools = {
			RpgTool = 1,
		},
		-- 25.10 (Kacper: „RPG w kierunku celowania, tam gdzie leci rakieta”): postawa bokiem.
		-- Przy krótkich rękach rigu lewa dłoń sięga 6-studowej wyrzutni tylko z tułowiem obróconym
		-- w prawo (stopnie, − = w prawo); głowa odkręca się z powrotem i patrzy przed siebie.
		-- Para z `ItemEquip.HoldPoses.Rpg` (poza na barku liczona dla −50) — zmieniać razem.
		WaistYawTools = {
			RpgTool = -50,
		},
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

		-- Kamera ZZA RAMIENIA (2026-09-23, prośba Kacpra: „kamera lekko w lewo od gracza").
		-- Przesunięcie w bok w układzie SAMEJ kamery, nakładane po wygładzaniu. Mysz, zoom
		-- i obrót zostają domyślne Robloxa — zmienia się tylko miejsce postaci w kadrze.
		-- Celowanie bombą i hakiem bez zmian: kursor jest wolny, a `mouse.Hit` liczy się
		-- z tej samej, przesuniętej kamery, więc trafia tam, gdzie widać kursor.
		ShoulderOffset = {
			Enabled = true,
			-- Study w bok. DODATNIE = kamera w PRAWO, czyli postać stoi po LEWEJ stronie ekranu
			-- (nad prawym ramieniem, jak w Fortnite). UJEMNE = odwrotnie.
			-- 23.09: najpierw −1.5 (postać po prawej), potem próba drugiej strony — i Kacper:
			-- „prawa zostaje". Czyli kamera nad prawym ramieniem, jak w Fortnite.
			Side = 1.5,
			-- 🔴 X-RAY (zgłoszenie Kacpra 2026-09-23: „kamera ma się zatrzymywać na ścianie").
			-- Plac miał `StarterPlayer.DevCameraOcclusionMode = Invisicam` — tryb, w którym kamera
			-- Robloxa w ogóle NIE zatrzymuje się na ścianach, tylko robi je przezroczystymi.
			-- Przesunięcie w bok częściej stawiało ścianę między kamerą a postacią, więc wbudowany
			-- x-ray wyszedł na wierzch. Naprawa w dwóch miejscach:
			--   • `default.project.json` → `DevCameraOcclusionMode = Zoom` (kamera staje na ścianie);
			--   • `keepLineOfSight` w MovementController — promień OD GŁOWY do kamery, bo `Zoom`
			--     pilnuje kamery tylko PRZED naszym przesunięciem i wygładzaniem.
			-- ⚠️ Lekcja: plan zakładał tryb Zoom, a sprawdziłem tylko zakres zoomu. Przy każdej
			-- zmianie kamery sprawdzić NAJPIERW `DevCameraOcclusionMode`.
			-- Odstęp kamery od ściany (i w bok, i na linii głowa → kamera).
			WallMargin = 0.5,
			-- Party co najmniej tak przezroczyste kamera przepuszcza (szyby mają 0.60) — tak samo
			-- robi tryb Zoom; inaczej kamera kleiłaby się do każdej szyby. Postacie też przepuszcza.
			SeeThroughTransparency = 0.5,
			-- ⚠️ Ściana za plecami: tryb Zoom przysuwa wtedy kamerę do postaci, a pełne
			-- przesunięcie z bliska daje widok z boku głowy. Poniżej tej odległości kamera–postać
			-- przesunięcie maleje proporcjonalnie. = CameraMinZoom, bo tyle ma kamera normalnie.
			FullOffsetDistance = 8,
			-- Dochodzenie do przesunięcia (1-exp(-k·dt)) — przejście obok słupa nie szarpie.
			LerpSpeed = 12,
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
		-- Lekkie drżenie kamery przy SPRINCIE na ziemi (11.10, prośba Kacpra „shake podczas biegu
		-- lekkie”). Płynny szum, nie losowe szarpanie; przy chodzeniu NIC (Kacper nie chciał
		-- bujania przy chodzeniu — stary sprint bob usunięty). Wyłącznik: Amplitude 0.
		SprintShake = {
			Amplitude = 0.11,   -- studa — maksymalne przesunięcie kamery (11.10: było 0.07, „trochę bardziej”)
			Frequency = 6,      -- szybkość drżenia (wyżej = drobniej i szybciej)
			FadeTime = 0.2,     -- s: wejście / zejście przy starcie i końcu sprintu
		},
		-- Przechył kamery przy ruchu w BOK (11.10, „podrasuj movement”): biegniesz w prawo →
		-- kamera lekko kładzie się w prawo. Pełny przechył przy prędkości sprintu. 0 = wyłączony.
		Lean = {
			MaxDegrees = 1.2,   -- 11.10: było 2.5 (Kacper: „mniej stopni”)
			Speed = 8,          -- jak szybko dochodzi do przechyłu (wyżej = szybciej)
		},

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

-- DRABINY (08.10) — niższa prędkość potrzebna do złapania drabiny (LadderController). Zgłoszenie
-- Kacpra: „bez sprintu jestem za wolny, żeby się złapać”. Wspinanie robi silnik Robloxa; przy
-- chodzie 12 często nie łapie, przy sprincie łapie — więc tuż przed drabiną, idąc w jej stronę,
-- prędkość w stronę drabiny jest dobijana do sprintu. Drabina = party z tagiem `Tag`
-- (skrypt LADDERS_TAG.luau). ⛔ Własny tryb drabiny (trzymanie, W/S) odrzucony 08.10.
Config.Ladder = {
	Tag = "Ladder",
	-- Jak daleko PRZED płaszczyzną szczebli zaczyna działać (od środka postaci, w studach).
	ReachDistance = 3,
	-- Ile studów poza końcem szczebla w bok jeszcze działa (podejście ukosem).
	LateralMargin = 1.5,
	-- Maksymalny kąt między kierunkiem ruchu a drabiną. Idąc RÓWNOLEGLE do ściany nie działa.
	IntentAngle = 70,
	-- Prędkość w stronę drabiny, do której dobijamy. Sprint łapał — więc tyle samo.
	GrabSpeed = Config.Movement.SprintSpeed,

	-- SERWER (FallDamageService): gracz tak blisko szczebli, poruszający się pionowo nie
	-- szybciej niż `MaxClimbSpeed`, stoi „jak na ziemi” — licznik upadku liczy się od nowa.
	-- Bez tego zejście po drabinie z dachu kończyło się obrażeniami za całą wysokość (promień
	-- w dół przelatuje obok szczebli).
	OnLadderDistance = 2.5,
	MaxClimbSpeed = 16,
}

Config.Push = {
	Windup = 0.15, -- authoritative delay before target selection / impulse
	AnimationEnabled = true,
	AnimationId = 0, -- publish Push_TwoHands_R15 and insert the owner account's ID
	AnimationStudioPreview = true,
	AnimationFolder = "PushAnimations",
	AnimationName = "Push_TwoHands_R15",
	AnimationImpactTime = 0.15, -- authored contact time; playback scales to Windup
	AnimationFadeIn = 0.035,
	AnimationFadeOut = 0.10,
	AnimationLoadTimeout = 10,
	AnimationLoadPoll = 0.1,
	MaxRange = 7,   -- stud; close-combat only
	ConeDot = 0.3,  -- min dot(look, kierunek do celu) — ~70° stożek przed pusherem
	Force = 80,     -- pozioma velocity (stud/s)
	Lift = 20,      -- pionowy kick — bez niego push szoruje graczem po ziemi
	-- Feedback ofiary: screen shake gdy ktoś Cię pchnie (klient, MovementController.screenShake).
	HitShakeIntensity = 1.1,
	HitShakeDuration = 0.3,
	-- Feedback POPYCHAJĄCEGO (11.10): krótkie szarpnięcie kamery + mały zoom w chwili uderzenia
	-- (po `Windup`), także przy pudle — czujesz, że pchnąłeś.
	PushShakeIntensity = 0.45,
	PushShakeDuration = 0.18,
	PushFOVKick = 4,     -- stopnie (wraca sam, jak FOV punch od bomby)
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
	MinFlightTime = 0.01, -- dotychczasowy próg wykonania klienta; no-op nie zużywa haka
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

-- Energy drink (20.10, decyzje Kacpra): pijesz w biegu, przez `Duration` sprint nie zużywa
-- staminy, a pasek staminy mieni się kolorami. Napój NIE przyspiesza — sprint jest tak samo
-- szybki, więc anti-cheat nie musi o nim wiedzieć. Serwer (EnergyDrinkService) zapisuje okno
-- działania w dwóch atrybutach gracza (czas serwera); efekt liczy MovementController
-- właściciela, gest łyku widzą wszyscy (EnergyDrinkController).
Config.EnergyDrink = {
	Duration = 10,        -- s nieskończonej staminy (Kacper 20.10)
	-- Łyk: efekt rusza SipTime po kliknięciu (puszka przy ustach), gest z opuszczeniem ręki
	-- trwa SipDuration. Bieg się NIE zatrzymuje (decyzja Kacpra: „krótkie picie w biegu”).
	SipTime = 0.5,
	SipDuration = 0.8,
	StartAttribute = "EnergyStart",
	EndAttribute = "EnergyEnd",
	-- Puszka w dłoni: obrót uchwytu (Tool.Grip) w stopniach. Model ma wieczko po swojej osi +X;
	-- (0, 0, -90) ma stawiać ją pionowo, wieczkiem do góry, przy ręce trzymającej item przed sobą.
	-- Leży albo stoi do góry dnem → zmienić TĘ liczbę (np. Z = 90 albo Y = 90).
	GripRotation = Vector3.new(0, 0, -90),
	-- Gest łyku: kąty stawów prawej ręki w stopniach, Time = ułamek SipDuration, Weight 0 = sama
	-- animacja postaci, 1 = poza z tabeli. Ta sama technika co Config.ItemEquip (nakładka na
	-- Motor6D.Transform), te same znaki: Shoulder X+ = ręka do przodu, Z− = do środka ciała,
	-- Elbow X+ = zgięcie łokcia. Dopasowane do wieczka puszki, Tool.Grip i stawów
	-- StarterCharacter: wieczko przed ustami, nie przy prawym uchu. Druga poza przechyla puszkę.
	Sip = {
		{ Time = 0, Weight = 0, Shoulder = Vector3.new(80, 30.5, -59.5), Elbow = Vector3.new(52.5, 0, 0), Wrist = Vector3.new(-0.5, 34, 57.5) },
		{ Time = 0.3, Weight = 1, Shoulder = Vector3.new(80, 30.5, -59.5), Elbow = Vector3.new(52.5, 0, 0), Wrist = Vector3.new(-0.5, 34, 57.5) },
		{ Time = 0.62, Weight = 1, Shoulder = Vector3.new(87.5, 30, -56.5), Elbow = Vector3.new(42.5, 0, 0), Wrist = Vector3.new(9.5, 33.5, 55.5) },
		{ Time = 1, Weight = 0, Shoulder = Vector3.new(87.5, 30, -56.5), Elbow = Vector3.new(42.5, 0, 0), Wrist = Vector3.new(9.5, 33.5, 55.5) },
	},
	-- 21.10 (Kacper): w trakcie działania szybszy CHÓD (sprint bez zmian) i szersza kamera.
	-- Chód 12 + 3 = 15 < sprint 20 — anti-cheat dalej nic nie musi wiedzieć.
	WalkBonus = 3,        -- stud/s do chodu
	FOVBonus = 5,         -- stopni do kamery (chód i sprint)
	-- Pasek staminy (21.10, druga wersja — Kacper: „pogrubiona obramówka, różne odcienie
	-- przechodzące, środek też w różnych odcieniach”): obrys i wypełnienie płyną po palecie
	-- niebieskich (`Palette`, w kółko, `PaletteSpeed` cykli/s), środek przesunięty w fazie
	-- o `FillPhase`, żeby nie były tego samego koloru. Obrys × `BorderThickness`.
	-- W ostatnich `WarnTime` s paleta płynie `WarnSpeedMul` razy szybciej — zaraz koniec.
	-- 21.10 wieczór (Kacper: „tylko złote”): paleta złota zamiast niebieskiej.
	Palette = {
		Color3.fromRGB(230, 145, 15),
		Color3.fromRGB(255, 195, 40),
		Color3.fromRGB(255, 235, 140),
		Color3.fromRGB(255, 210, 70),
		Color3.fromRGB(215, 120, 10),
	},
	PaletteSpeed = 0.9,
	FillPhase = 0.5,
	BorderThickness = 1.8,
	WarnTime = 2,
	WarnSpeedMul = 2.5,
	-- Winieta na krawędziach ekranu właściciela (21.10, Kacper: „jak czerwone przy damage po
	-- bokach, ale lekko złotawe albo niebieskie”; filtr na cały ekran ODRZUCONY). Wygląd:
	-- `StarterGui.EnergyVignette` (Studio). Kod: wejście/zejście `VignetteFade`, pulsowanie
	-- między `VignetteMin` a 1 widoczności (`VignettePulseHz`), kolor płynie po `VignetteColors`
	-- (niebieski ↔ złotawy). Złoto/niebieski = tu.
	VignetteColors = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 225, 130) }, -- tylko złoto (Kacper)
	VignetteColorSpeed = 0.35, -- cykli/s przejścia kolorów
	VignettePulseHz = 1.2,
	VignetteMin = 0.55,
	VignetteFade = 0.35,
	SipSound = "",        -- dźwięk łyku, rbxassetid od Kacpra; "" = cisza
	SipSoundVolume = 0.8,
}

-- RPG (20.10, decyzje Kacpra): rakieta leci PROSTO i szybko, bez opadania, wybucha przy
-- pierwszym trafieniu; wybuch słabszy od bomby (siła: ItemDefinitions.rpg); 1 rakieta = 1 strzał
-- za 75$; własny wybuch jak bomba rzucającego (rocket jump usunięty 21.10). Lot liczy SERWER promieniami
-- (RpgService), klienci rysują rakietę u siebie po tej samej prostej (RpgController).
Config.Rpg = {
	Speed = 120,          -- stud/s
	MaxRange = 300,       -- dalej rakieta wybucha w powietrzu (2,5 s lotu)
	MuzzleHeight = 1.5,   -- start lotu nad środkiem HRP — mniej więcej wysokość ramienia
	-- 25.10: wyrzutnia leży na prawym barku — start lotu tyle studów w prawo od środka postaci
	-- (z lufy, nie z głowy). Ściana przy prawym boku skraca to przesunięcie (RpgService).
	MuzzleSide = 1.0,
	HitBackoff = 0.5,     -- środek wybuchu odsunięty od trafionej powierzchni (nie w ścianie)
	-- Głowica w modelu `Rpg` — to ona leci (jej kopia u klientów); w ręce zostaje cała wyrzutnia.
	RocketPartName = "Cylinder",
	-- Chwyt wyrzutni: punkt względem środka modelu, wzdłuż lufy (w stronę głowicy = +) i pod
	-- lufą. Model ma tam rękojeść. Ręka w złym miejscu → stroić te dwie liczby.
	HoldAlong = -0.28,
	HoldBelow = 0.35,
	-- Smuga za rakietą u klientów (prosta, docelowy dym w etapie efektów).
	TrailLifetime = 0.35,
	TrailWidth = 0.5,
	TrailColor = Color3.fromRGB(235, 235, 235),
	-- Klient sprząta swoją kopię rakiety po czasie lotu + tyle, gdy RocketExploded nie doszedł.
	VisualLinger = 0.5,
	-- Celowanie na PPM / L2 (24.10, Kacper: „lekko zbliżona kamera, całe ciało w kierunku
	-- strzału, celownik z 4 kresek pusty w środku”). Z celowania rakieta leci w środek
	-- celownika; bez PPM dalej w kursor. Decyzje 24.10: chód wolniej, bez sprintu.
	Aim = {
		-- Profil dla MovementController.setAim (kamera, ruch, obrót ciała).
		Profile = {
			FOVOffset = -18,   -- stopnie: 70 → 52 (25.10, Kacper: „nieco większy zoom”; było −12)
			PushIn = 3,        -- studa kamery bliżej postaci (zoom 8 → 5; było 2,5)
			Lift = 0.8,        -- studa kamery wyżej (26.10, Kacper: „trochę wyżej, lekko”); 0 = jak dotąd
			WalkFactor = 0.65, -- chód 12 → ~7,8 stud/s
			TurnSpeed = 25,    -- 1/s — ciało dogania kamerę prawie od razu, bez szarpnięcia
			BlendSpeed = 14,   -- 1/s wjazdu i wyjazdu kamery
		},
		-- Promień spod celownika. Dalej niż MaxRange — nawet bez trafienia daje kierunek.
		RayLength = 400,
		-- `HUD.<CrosshairName>.Body` z UIScale `Pop`: wskok przy wejściu, rozszerzenie przy strzale.
		CrosshairName = "Crosshair",
		ShowPop = 0.6,
		FirePop = 1.35,
		PopTime = 0.15,
	},
	-- Odrzut przy strzale (21.10, Kacper: kamera + błysk i dym + wyrzutnia w ręce, „mocno”).
	-- Kamera tylko u strzelca; błysk, dym i kop ręki u wszystkich (RpgController na RocketFired).
	Recoil = {
		-- 21.10, Kacper: podbicie kamery w górę „wkurwia” — gra nie ma celownika, a kamera to
		-- jedyne celowanie, więc NIC nie może zmieniać kierunku patrzenia. Odrzut kamery = sam
		-- wstrząs (przesunięcie, bez obrotu) i zoom-out. 0 = podbicie wyłączone; nie wracać.
		-- 24.10: celownik na PPM (`Aim`) niczego tu nie zmienia — siedzi na środku kamery, więc
		-- podbicie zrzuciłoby go z celu tak samo.
		CameraKick = 0,
		CameraKickDecay = 7,   -- 1/s
		Shake = 1.6,           -- MovementController.screenShake (sufit ShakeMaxIntensity)
		ShakeTime = 0.25,
		FOVKick = 9,           -- chwilowe oddalenie — „kop” bez ruszania celu
		-- Kop ręki: nakładka na stawy (jak gest łyku), stopnie: bark w górę, łokieć zgina do tyłu.
		ArmShoulder = 32,
		ArmElbow = 28,
		ArmTime = 0.45,        -- s całego kopa
		ArmAttack = 0.05,      -- s do pełnego wychylenia
		-- Wylot i tył wyrzutni (od głowicy w ręce; bez wyrzutni — od startu lotu).
		LauncherLength = 5,
		FlashSize = 3.5,
		FlashTime = 0.12,
		FlashColor = Color3.fromRGB(255, 185, 70),
		FlashLight = 14,       -- zasięg błysku światła
		FrontSmoke = 8,        -- kłęby dymu z przodu
		BackSmoke = 16,        -- backblast z tyłu
		SmokeSize = 3,
		SmokeLifetime = 1.4,
		SmokeSpeed = 14,
		SmokeColor = Color3.fromRGB(170, 165, 160),
	},
}

-- C4 (25.10, decyzje Kacpra): klik z C4 w ręce przykleja ładunek tam, gdzie celujesz (tylko mapa,
-- nie gracze); naraz najwyżej MaxActive; klawisz / przycisk detonatora odpala wszystkie. Śmierć =
-- ładunki znikają bez wybuchu. Siła wybuchu: ItemDefinitions.c4. Serwer: C4Service, klient: C4Controller.
Config.C4 = {
	MaxActive = 3,          -- ładunki jednego gracza naraz, w locie i przyklejone (Kacper: 3)
	-- Rzut: lot liczy serwer promieniem co klatkę; pierwsza trafiona część mapy = przyklejenie.
	-- Kacper 25.10: najpierw „dalej i prościej” (90 + 12 przy grawitacji 120), po teście
	-- „wysoki łuk jak granat” — zasięg mniej więcej jak bomba (60 + 20), ale wyraźnie wyżej:
	-- rzut na wprost wznosi się ~5 studów nad dłoń i spada ~25 studów dalej.
	ThrowSpeed = 45,        -- stud/s w kierunku celu
	ThrowLift = 45,         -- stud/s w górę — to robi łuk
	InheritMaxSpeed = 50,   -- tyle najwyżej prędkości postaci dostaje rzut (biegnąc rzucasz dalej)
	Spin = 9,               -- rad/s — kostka koziołkuje w locie
	-- Gest rzutu (Kacper 25.10: zamach od góry): nakładka na prawy bark i łokieć, stopnie
	-- względem trzymania. Widzą go wszyscy — u siebie od kliknięcia, u innych od pojawienia się
	-- ładunku w dłoni rzucającego (atrybut OwnerAttribute, bez osobnego remote'a).
	Swing = {
		Windup = 0.1,       -- s do pełnego zamachu (ręka nad głową, łokieć zgięty)
		Release = 0.2,      -- s do wyrzutu (ręka przed sobą, niżej niż przy trzymaniu)
		Time = 0.42,        -- s całego gestu (spokojny powrót do trzymania)
		ShoulderUp = 60,
		ElbowBend = 70,
		ShoulderDown = -35,
		-- Ładunek dalej od dłoni rzucającego = wczytany później (streaming, dołączenie), nie rzut.
		MaxHandDistance = 8,
	},
	OwnerAttribute = "Owner", -- UserId rzucającego na modelu ładunku
	-- Odpalenie: ładunki wybuchają po kolei co tyle sekund — łańcuch zamiast jednej klatki
	-- z trzema wybuchami (destrukcja ma budżet CPU na klatkę).
	ChainDelay = 0.12,
	BlastBackoff = 0.3,     -- środek wybuchu odsunięty od ściany (jak Rpg.HitBackoff — nie w ścianie)
	DetonateKey = Enum.KeyCode.G, -- Kacper 25.10; telefon: przycisk `HUD.<DetonateButtonName>`
	DetonateButtonName = "DetonateButton",
	-- Atrybut gracza z liczbą przyklejonych ładunków — czyta go przycisk detonatora.
	CountAttribute = "C4Charges",
	-- Ładunek NIE jest przyspawany do mapy (system zawaleń liczy połączenia części), tylko
	-- zakotwiczony; serwer co tyle sekund sprawdza, czy pod nim dalej coś jest.
	CheckInterval = 0.1,
	-- Zapas przy sprawdzaniu „punkt styku nadal leży na tej części” (przycięta ściana).
	HostMargin = 0.4,
	-- Lot po rzucie i spadanie, gdy podłoże zniknie — ten sam ruch: grawitacja, promień co klatkę,
	-- przyklejenie na pierwszej trafionej części. Bez trafienia po MaxFlightTime (poleciał
	-- poza mapę) znika bez wybuchu.
	Gravity = 196.2,        -- stud/s² — jak grawitacja gry (bomba leci tą samą)
	FallMaxSpeed = 90,
	MaxFlightTime = 6,
	-- Dioda: miga na czerwono, żeby dało się wypatrzyć ładunek i uciec.
	LightColor = Color3.fromRGB(255, 40, 30),
	LightRange = 7,
	LightBrightness = 3,
	BlinkHz = 1.5,
	-- Ładunek w dłoni: obrót uchwytu (Tool.Grip) w stopniach; model trzymany za środek. Krzywo
	-- w ręce → zmienić TĘ liczbę (np. Y = 90 obraca długi bok do przodu).
	GripRotation = Vector3.new(0, 0, 0),
}

-- Panel ustawień (26.10, decyzje Kacpra: strona kamery + przechył/FOV, zapis na koncie, ikona
-- zębatki). Klucz opcji = atrybut `Setting` przycisku w `StarterGui.Settings`, wartość = atrybut
-- `Value` (STUDIO_CONTRACT → „Ustawienia”). Nowa opcja: wpis tutaj + przyciski w Studio + odczyt
-- tam, gdzie działa (SettingsState.get). Serwer przepuszcza wyłącznie wartości z `Values`.
Config.Settings = {
	Options = {
		-- Kamera nad prawym (jak dotąd, Fortnite) albo lewym ramieniem — znak ShoulderOffset.Side.
		shoulder = { Values = { "right", "left" }, Default = "right" },
		-- Przechył obrazu przy ruchu w bok i zmiany FOV (sprint, energy drink, kopnięcia od
		-- wybuchu/RPG). Zoom celowania RPG zostaje — to celowanie, nie efekt.
		cameraFx = { Values = { true, false }, Default = true },
		-- 27.10: GRAPHICS LOW / HIGH — wyłącznie ozdobniki lawy u klienta (bez kolizji i promieni,
		-- więc nie zmienia gry; gruz i wybuchy mają jeden `Config.Graphics.Profile` dla wszystkich).
		-- „auto” rozwiązuje klient (SettingsState): dotyk albo suwak grafiki Robloxa ≤
		-- `AutoLowQualityLevel` → low, inaczej high. Kliknięcie w panelu zapisuje wybór na stałe.
		graphics = { Values = { "auto", "low", "high" }, Default = "auto", AutoLowQualityLevel = 3 },
	},
	SendDelay = 0.3, -- s: klient wysyła ostatni stan po tym czasie od kliknięcia
	-- Przycisk wybranej wartości / pozostałe — gradient `Fill` (te same kolory co BUY / NOT ENOUGH $).
	SelectedColors = { Color3.fromRGB(70, 215, 95), Color3.fromRGB(10, 140, 52) },
	IdleColors = { Color3.fromRGB(120, 115, 125), Color3.fromRGB(70, 66, 76) },
	OpenScale = 0.85,   -- panel wskakuje od tej skali do 1
	OpenTime = 0.25,
	HoverScale = 1.06,  -- przyciski i zębatka pod kursorem
	PressScale = 0.92,  -- krótkie wciśnięcie przy kliknięciu
	HoverTime = 0.12,
}

Config.RateLimits = {
	-- Serwer przepuszcza akcję już od tego ułamka cooldownu (decyzja Kacpra 29.09, B-5). Klient
	-- wysyła najwcześniej po PEŁNYM cooldownie (pasek), ale serwer mierzy czas ODBIORU — jitter
	-- sieci skracał odstęp i legalny rzut / most / hak / push ginął po cichu. Spam i tak ucina
	-- limit, tylko o 15% luźniejszy. Dotyczy wszystkich limitów akcji niżej (nie BuyItemPerSecond).
	ServerTolerance = 0.85,
	BombThrow = 0.5,
	Push = 2.5,      -- 10.10: było 4 (prośba Kacpra „zmniejsz cooldown na popychanie”)
	BridgeBuild = 0.5,
	Grapple = 0.6,   -- hak: krótki, bo item jest zużywalny — limituje go cena, nie zegar
	EnergyDrink = 1.0, -- dłuższy niż łyk (SipTime): dwuklik nie wypije dwóch puszek naraz
	Rpg = 1.0,         -- 1 rakieta = 1 strzał; limit chroni tylko przed dwuklikiem przy kilku sztukach
	C4Throw = 0.35,    -- trzy rzuty w sekundę — człowiek szybciej nie celuje w trzy miejsca
	C4Detonate = 0.5,
	-- EquipItem+UnequipItem: klik hotbar slot. Spam clickowanie = flickering Tool
	-- w rękach innych klientów + bandwidth. 0.15s = ~7 kliknięć/s max, ludzki reflex OK.
	EquipItem = 0.15,
	-- Zmiana loadoutu w ekwipunku (18.10). Klient zbiera szybkie kliknięcia i wysyła ostatni
	-- stan po `Config.UI.Inventory.SendDelay`, więc limit nie dotyka człowieka.
	SetLoadout = 0.2,
	-- Panel ustawień (26.10): ten sam wzorzec co loadout — wysyłka ostatniego stanu po
	-- `Config.Settings.SendDelay`.
	SetSettings = 0.2,
	-- Zakupy w sklepie: SUFIT na spam remote'a, nie cooldown (przegląd 29.09). Człowiek nie
	-- kliknie KUP 10 razy na sekundę; limit 0,5 s między zakupami usunięto wcześniej, bo
	-- blokował zwykłe klikanie — nie wracać do niego.
	BuyItemPerSecond = 10,
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

-- Komunikat „YOU KILLED <nick>” dla zabójcy (KillMessageController, 10.10, projekt z Figmy).
-- Wygląd w Studio (`HUD.KillMessage`); tu tylko czasy i kolor słowa „KILLED”.
Config.KillMessage = {
	ShowTime = 2.5,   -- s widoczności, zanim zacznie gasnąć
	FadeTime = 0.35,  -- s wygaszania
	PopScale = 1.35,  -- wskok: start z tej skali do 1
	PopTime = 0.3,
	KilledColor = Color3.fromRGB(159, 0, 0), -- Figma: #9F0000
}

-- Komunikat „YOU SURVIVED!” + nagroda dla ocalałego (WinMessageController, 20.10).
-- Wygląd w Studio (`HUD.WinMessage`); tu tylko czasy. Pokaz + wygaszanie mieszczą się
-- w `Game.FinishHold` (3 s) — potem zasłania go ciemne przejście do lobby.
Config.WinMessage = {
	ShowTime = 2.4,
	FadeTime = 0.35,
	PopScale = 1.35,
	PopTime = 0.3,
}

Config.Rewards = {
	-- Nagroda dla snapshotu ocalałych na RoundFinished (wejście w FINISHING). Bomba=50, most=100,
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
	-- Napis „SHOP” nad sprzedawcą (19.10, wybór Kacpra: „płynąca lawa”): BillboardGui `ShopSign`
	-- w głowie NPC (MaxDistance 90 = widać tylko w lobby — mapa jest 300+ studów dalej). Kolory
	-- lawy płyną przez litery w kółko (`Body.Label.Lava`, kod przelicza gradient co klatkę).
	SignName = "ShopSign",
	SignFlowSpeed = 0.35, -- cykle palety na sekundę (szybkość płynięcia)
	SignFlowSpan = 1.0,   -- ile cykli palety mieści się na szerokości napisu
	SignFlowColors = {    -- zapętlona paleta: czerwony → pomarańczowy → żółty → pomarańczowy → …
		Color3.fromRGB(255, 60, 20),
		Color3.fromRGB(255, 170, 30),
		Color3.fromRGB(255, 245, 120),
		Color3.fromRGB(255, 170, 30),
	},
	PromptActionText = "Shop",       -- 21.10: napisy po angielsku (decyzja Kacpra)
	PromptObjectText = "Seller",
	PromptKeyCode = Enum.KeyCode.E,
	PromptMaxDistance = 12,

	-- ── SCENA SKLEPU (osobne pomieszczenie, do którego jedzie kamera) ───────────
	-- Gracz NIE jest tam teleportowany — zostaje przy sprzedawcy, leci sama kamera.
	-- Dlatego scena może stać dowolnie daleko od lobby i kilku graczy może kupować
	-- naraz, nie wchodząc sobie w kadr.
	SceneName = "WeaponShopScene",
	ItemsFolder = "Decorations",   -- modele na wystawie (nazwa z ItemDefinitions.sceneModel)
	CamerasFolder = "ShopCameras", -- markery pozycji kamery
	-- Światło sceny: od 23.10 stałe lampy w placu (`<SceneName>.ShopLights`, po jednej nad itemem),
	-- kod ich nie zna. Lampa jadąca za kamerą (21.10, `LightName`) usunięta — oświetlenie
	-- doganiało ją kilka sekund po każdym przewinięciu.
	-- Ogólne światło sceny (`Lighting.Ambient`) na czas sklepu, tylko u oglądającego (23.10).
	-- Lamp Roblox nie rysuje na niskiej jakości grafiki — to trzyma sklep jasny na każdej.
	-- Jaśniej = płaściej na wysokiej jakości (mniej widać plamy lamp). Poza sklepem: 88,58,52.
	SceneAmbient = Color3.fromRGB(135, 120, 110),

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
	-- 21.10 (Kacper: „źle ustawione kamery, od dołu, nie naprzeciw”): markery były za nisko
	-- (i w Play opadały, zanim serwer je zakotwiczył), a kadr automatyczny odsuwał kamerę
	-- OD środka sceny — za ścianę wystawy. Teraz KAŻDY item: kamera dokładnie naprzeciw,
	-- w głąb pomieszczenia (krótsza pozioma oś sceny), lekko z góry, odległość z wielkości.
	UseCameraMarkers = false,     -- true = wracają markery ShopCameras (pozycja z markera)
	-- Panel sklepu (21.10, nowy: pasek na dole w stylu ekwipunku, napisy po angielsku).
	BuyText = "BUY",
	NoCashText = "NOT ENOUGH $",
	BoughtText = "BOUGHT!",
	BuyColors = { Color3.fromRGB(70, 215, 95), Color3.fromRGB(10, 140, 52) },     -- jak ADD w ekwipunku
	NoCashColors = { Color3.fromRGB(120, 115, 125), Color3.fromRGB(70, 66, 76) },
	FailTexts = {
		not_enough_cash = "NOT ENOUGH CASH",
		too_far = "GET CLOSER TO THE SELLER",
		unknown_item = "UNKNOWN ITEM",
		inventory_full = "INVENTORY FULL",
		invalid_payload = "ERROR",
		internal_error = "SERVER ERROR",
	},
	FailDefault = "PURCHASE FAILED",
	AutoCameraFill = 0.28,        -- jaką część wysokości ekranu ma zająć item (21.10: 0,45 → dalej)
	AutoCameraMinDistance = 7,    -- stud — drobne itemy (puszka) nie wchodzą w obiektyw (było 4)
	AutoCameraPitch = 12,         -- stopni z góry (0 = idealnie na wprost; 23.10: 8 → 12)
	-- Stopni z boku (23.10, Kacper: „lekki kąt do itema”). Dodatnie = kamera przesunięta w stronę
	-- sklepu z ubraniami (początek wystawy, RPG), ujemne = w drugą stronę, 0 = na wprost.
	AutoCameraYaw = 20,

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
		-- Mosty (ActiveBridges): kruche drewno — bomba w pobliżu łamie deski, deski
		-- lecą w lawę (sabotaż PvP). Deski mostu to DROBNICA (3 studs³), więc od v3
		-- ten próg działa jak próg drobnicy, tylko niższy: most pęka do 24×(1−40/160) =
		-- 18 studów, zwykła drobnica do 12. Most jest modelem → pada CAŁY (Small niżej).
		Bridge = { HP = 40 },
		-- DROBNICA (v3, 2026-09-23 — patrz `Small` niżej): próg JEDNORAZOWY, bez pamięci
		-- HP. Obrażenia ≥ progu = pęka, mniej = nic. Bomba 160/24 łamie drobnicę do
		-- 24×(1−80/160) = 12 studów (ściany: do 9). Liczone z modelu obrażeń, nie osobnym
		-- promieniem, żeby mocniejsza bomba łamała dalej bez dodatkowej gałki.
		Small = { HP = 80 },
	},
	PillarTag = "Pillar", -- nazwa tagu CollectionService którym Kacper oznacza filary

	-- FEEDBACK OBRAŻEŃ STRUKTURALNYCH: ranny part ciemnieje proporcjonalnie do utraconego
	-- HP. Kolor wraca sam po rundzie (MapService restore).
	-- (2026-09-23: USUNIĘTY pył przy trafieniu. Był osobnym ParticleEmitterem tworzonym
	-- NA SERWERZE dla każdego rannego parta — zmierzone: jedna bomba w zielonym budynku
	-- = 338 emiterów replikowanych do każdego gracza. Pył robi klient w ExplosionFX.)
	DamageFeedback = {
		DarkenMax = 0.45,   -- max przyciemnienie koloru przy ~100% zniszczenia
	},
	-- Atrybuty, które wybuch zostawia na partach mapy. Jedno źródło nazw dla
	-- DestructionService, CollapseService i MapService (07.10: odbudowa po rundzie
	-- odbudowuje tylko naruszone jednostki — ranny part bez zmiany kształtu poznaje
	-- właśnie po tych atrybutach; ciemny part ciemniejący do ciemnego nie zmienia koloru).
	DamageAttributes = {
		HP = "DestrHP",                -- pozostałe HP strukturalne (brak = pełne HP kategorii)
		OrigColor = "DestrOrigColor",  -- kolor sprzed przyciemnienia
	},

	-- ===== DROBNICA vs KONSTRUKCJA (v3, 2026-09-23) =====
	-- Zmierzone na mapie: 20 376 z 26 039 partów (78%) ma objętość < 4 studs³ albo
	-- najdłuższy bok < 2.8 — wieszaki, ubrania, listwy, nogi krzeseł. System v2
	-- traktował je jak ściany (HP, ciemnienie, pył, gruz serwerowy, pass podparcia), więc
	-- jedna bomba w sklepie z ubraniami robiła setki partów fizyki serwera, a limit gruzu
	-- natychmiast je kasował („wieszaki znikają”). Teraz:
	--   * drobnica NIE ma HP, nie ciemnieje, nie jest gruzem serwera i nie wchodzi do
	--     grafu podparcia. Pęka od progu `Categories.Small.HP` i serwer PRZEKAZUJE ją
	--     klientom (Remotes.DebrisFall) — każdy animuje upadek u siebie, w swoim trybie
	--     grafiki. Serwer kasuje oryginały dopiero po `HandoffDelay`.
	--   * MEBEL (decyzja Kacpra: „cały mebel pada”): Model z SAMEJ drobnicy, najwyżej
	--     `AssemblyMaxSize` studów i `AssemblyMaxParts` partów, bez partów Locked. Gdy
	--     pęka jego jakakolwiek część — pada cały (zero ubrań wiszących bez wieszaka).
	--     Warunek „sama drobnica” CELOWY: model z dużą bryłą (automat, komoda, lada,
	--     schody) mógłby być elementem rozgrywki, więc takie pękają jak ściany.
	Small = {
		MaxVolume = 4,        -- studs³ — poniżej: drobnica
		-- Najdłuższy bok poniżej = drobnica. 2.8 = 2 × Fracture.MinChunkSize — krótszego
		-- parta i tak nie da się przeciąć na dwa kawałki, więc „dziura” w nim nie istnieje.
		MinCutSize = 2.8,
		-- Obrażenia od tego progu = drobnica jest ODRZUCANA od wybuchu, poniżej po prostu
		-- PADA. 120 → do 6 studów od epicentrum (bomba 160/24).
		LaunchDamage = 120,
		-- Prędkość odrzutu drobnicy = impuls bomby × ten ułamek. Mebel to nie pocisk:
		-- przy pełnym impulsie (95 stud/s) wieszaki rozlatywały się po całym piętrze.
		LaunchSpeedFactor = 0.35,
		AssemblyMaxSize = 18, -- studów (największy wymiar bbox modelu)
		AssemblyMaxParts = 200,
		-- Opóźnienie kasowania na serwerze. Klient musi DOSTAĆ listę i skopiować party,
		-- zanim ich usunięcie do niego dojedzie — kopia z już skasowanego parta nie istnieje.
		HandoffDelay = 0.25,
		-- Sufit instancji (modeli/partów) przekazanych w jednym wybuchu. Mebel = 1 wpis,
		-- więc to jest sufit rozmiaru payloadu, nie liczby partów. Ponad nim drobnica
		-- ZOSTAJE na miejscu (lepiej niż zniknąć bez animacji).
		MaxHandoffPerBlast = 300,
		-- Luz przy szukaniu drobnicy „przyczepionej” do parta, który zniknął (dekoracja
		-- na ścianie z dziurą, rzeczy na spadającej płycie).
		AttachPadding = 0.3,
	},

	-- Budżet CPU destrukcji na JEDNĄ klatkę serwera (wszystkie wybuchy razem). Gdy kilka
	-- bomb wybucha w tej samej klatce, kolejny etap czeka na następną klatkę zamiast
	-- zamrażać serwer na sumę kosztów (zgłoszenie 2026-09-23: 4 bomby naraz = lag u
	-- wszystkich). Przesunięcie skutków o 1-3 klatki jest niewidoczne.
	FrameBudgetMs = 6,
	MaxBudgetWaitFrames = 8, -- sufit czekania — wybuch nie może czekać w nieskończoność

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
	-- Mosty graczy (ActiveBridges) NIE wchodzą do sprawdzenia z samej bliskości — wiszą
	-- z designu.
	--
	-- 🔴 v3 (2026-09-23): SPADA TYLKO TO, CO PODPARCIE STRACIŁO. Graf liczony jest DWA
	-- razy — przed wybuchem i po — i spada wyłącznie część wspólna „było podparte, nie
	-- jest”. Powód zmierzony na mapie: w KAŻDYM budynku setki partów są „niepodparte”
	-- według tej reguły jeszcze przed jakimkolwiek wybuchem (zielony 1724, hotel 590,
	-- szkoła 426, łącznie ~3500 — cienkie listwy, wieszaki, rzeczy wiszące), więc każda
	-- bomba w promieniu kolumny zrzucała je hurtem jako fizykę serwera. Stąd `spadło=472`
	-- w logu z dachu i znikające wieszaki. Drobnica (patrz `Small`) w grafie w ogóle nie
	-- bierze udziału — ani jako podpora, ani jako kandydat.
	-- Konsekwencja: `Locked` na „wiszących z designu” platformach przestaje być
	-- konieczny, ale dalej nie szkodzi.
	Support = {
		Enabled = true,
		Padding = 0.2,          -- luz dotyku (stud) przy szukaniu sąsiadów-podpór
		ColumnRadiusFactor = 1.3, -- XZ zasięg sprawdzenia = radius wybuchu × ten mnożnik
		ColumnHeight = 400,     -- pełna wysokość kolumny sprawdzenia (stud)
		-- Tolerancja „sąsiad całkowicie powyżej” (stud) — ale najwyżej POŁOWA grubości
		-- parta. Stała 0.5 sprawiała, że part cieńszy niż 0.5 studa nie mógł mieć
		-- podparcia z boku: sąsiad na tej samej wysokości liczył się jako „powyżej”.
		AboveEpsilon = 0.5,
		-- Sufit partów, które mogą spaść z jednego wybuchu (graf i tak ogranicza kolumna).
		-- Ponad nim zostają zakotwiczone — lepiej coś zawieszone niż zamrożony serwer.
		MaxFelledPerBlast = 400,
	},

	-- CIĘCIE partów na kawałki (Fracture.luau). Part w kuli wybuchu jest docinany do
	-- TargetChunkSize; kawałki poza kulą zostają DUŻE i wracają jako anchored "remnants"
	-- (dziura z drobnym gruzem + reszta panelu w 2-4 płytach).
	-- v3 (2026-09-23): plan cięcia liczy `Fracture.planHole` z SEEDEM — serwer bierze z
	-- niego resztki (scalone w możliwie duże bryły), a KLIENT z tego samego seeda liczy
	-- kawałki dziury i animuje je lokalnie. Kawałki z dziury nie są już partami serwera
	-- (to one — do 110 na wybuch — replikowały pozycję do każdego gracza i dławiły łącze).
	-- Ile kawałków gracz WIDZI, decyduje profil grafiki (`Config.Graphics.Profile`).
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
		-- (MaxServerChunksPerBlast 110 USUNIĘTE 2026-09-23 — serwer nie tworzy już kawałków
		-- dziury; sufit tego, co gracz widzi, to `Graphics.Profile.CutChunksPerBlast`.)
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
		-- v3: ten sam próg decyduje, czy duży part wyrzucony w CAŁOŚCI (kula, walec, klin,
		-- union) zostaje gruzem serwera (rani, można na nim stanąć), czy leci tylko u graczy.
		PlatformMinVolume = 45,
		-- v3 (2026-09-23): sufit NOWEGO gruzu serwera z jednego wybuchu — płyty, które
		-- straciły podparcie, i duże party wyrzucone w całości (największe pierwsze).
		-- Reszta leci już tylko u graczy (Remotes.DebrisFall). Decyzja Kacpra: ranić
		-- i służyć za platformy mają tylko DUŻE płyty; drobny gruz jest efektem.
		-- (Zastąpiło `MinChunksPerBlast` 40 — gwarancja kawałków dziury na serwerze
		-- straciła sens, bo kawałków dziury na serwerze już nie ma.)
		MaxServerPiecesPerBlast = 30,

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

	-- REKWIZYTY (2026-09-24, zgłoszenie po teście v4: „pudła, szafki — pobugowane”).
	-- Wszystko w folderze dekoracji budynku to rekwizyt: NIGDY nie jest cięte jak ściana. Mebel
	-- (najwyższy Model pod folderem dekoracji, do MaxSize) pada albo odlatuje W CAŁOŚCI — jak
	-- wieszaki (decyzja Kacpra 23.09: „cały mebel pada”). Zmierzone: 1474 duże party dekoracji
	-- (szafki, szafy, regały, łóżka, sofy, automaty, pudła) szły ścieżką ścian — dostawały
	-- poszarpane dziury, a drobne części tego samego mebla odpadały osobno.
	-- Większe od MaxSize (dywany 63×63, płoty 53, drabiny 45) zostają przy cięciu jak dotąd.
	Props = {
		-- 08.10: + Lamps (latarnie uliczne, `OutsideDecorations.Lamps`; zgłoszenie Kacpra „latarnie
		-- wiszą w powietrzu, kłuje w oczy”). Cięte po kawałku jak ściana: bomba wycinała kawałek
		-- słupa, a góra słupa z wysięgnikiem i kloszem zostawała w powietrzu. Jako MEBEL padają
		-- w całości. Decyzja Kacpra: TYLKO latarnie (nie sygnalizatory, przystanki, drzewa).
		-- 08.10 wieczór: + TrafficLights (sygnalizatory, 25 modeli 17,6 studa / 12 partów) — prośba
		-- Kacpra „to samo z sygnalizacją co z lampami”. Liczy się tylko FOLDER o tej nazwie
		-- (Destructible.isPropFolder) — modele sygnalizatorów też nazywają się „TrafficLights”.
		Folders = { Decorations = true, Lamps = true, TrafficLights = true },
		MaxSize = 24,   -- studów (największy wymiar modelu albo parta)
		MaxParts = 200,
		-- (26.09, decyzje Kacpra) Rekwizyty, które w zasięgu DZIURY znikają od razu z obłokiem
		-- pyłu — bez kopii i bez kawałków (wieszaków w GreenBuildingu: 37 sztuk, 1958 partów,
		-- każdy trafiony był kopiowany i animowany u każdego gracza). Klucz = nazwa folderu
		-- kategorii w Decorations. Wszystko inne w Decorations to MEBLE.
		-- 27.09: + Chairs (tak nazywa się folder krzeseł w OrangeKebab i CyanOffice — decyzja Kacpra:
		-- wszystkie krzesła znikają). Biurka CyanOffice (OfficeDesks, 48 × ~109 partów) zostają MEBLAMI.
		-- 27.09 (migracja 4 budynków, decyzja Kacpra): + drobiazgi (ToiletPapers, Products, Paintings,
		-- Mirrors), dywany (Carpets), beczki (Barrels); dla spójności liczby pojedyncze/mnogie tego,
		-- co już znika (TVs/Tvs, TrashBin, Painting, Carpet). Drzwi (Doors) zostają meblami.
		Vaporize = {
			ClothingHangers = true, Plants = true, Packages = true, TrashBins = true, TrashBin = true,
			Chair = true, Chairs = true, TV = true, TVs = true, Tvs = true,
			ToiletPapers = true, Products = true, Paintings = true, Painting = true, Mirrors = true,
			Carpets = true, Carpet = true,
			-- Barrels USUNIĘTE 21.10 — beczki są wybuchowe (Cars.Profiles.Barrels), nie znikają.
		},
		-- MEBLE: w zasięgu dziury rozpad od razu; dalej, od tych obrażeń, odepchnięcie w całości
		-- (fizyka serwera, PropService); drugie trafienie → rozpad. 80 = dawny próg drobnicy
		-- (~12 studów od bomby 160/24).
		PushHP = 80,
		MaxPushPerBlast = 6, -- odepchnięć na wybuch (fizyka serwera); ponad limit mebel zostaje
		PushSettleTime = 1,  -- s bezruchu → mebel kotwiczony tam, gdzie leży
		PushMaxTime = 8,     -- s — po tylu kotwiczony i tak (toczy się bez końca)
		ShatterLife = 1.5,   -- s życia kawałków rozpadniętego mebla (w obu trybach grafiki)
		VaporDust = 18,      -- cząstek obłoku na rekwizyt (× ParticleScale trybu)
		-- OSIEROCONE (28.09, decyzje Kacpra): rzecz stojąca tylko na meblu spada razem z nim (TV
		-- na szafce), duża dekoracja ponad MaxSize (deska rusztowania) — gdy nic jej nie trzyma.
		-- Skupisko stykających się luźnych rzeczy ocenia się razem; ponad limit zostaje na miejscu
		-- (bezpiecznie: tak jak przed poprawką). Ocena kończy się na pierwszym styku z czymś
		-- stojącym, więc zwykle skupisko to 1-3 rzeczy (szczebel → szyna drabiny → strop).
		OrphanMaxCluster = 40, -- rzeczy w jednym skupisku
		OrphanMaxJudged = 200, -- rzeczy ocenionych na jedno przekazanie (sufit CPU)
	},
	-- AUTA (27.09, decyzja Kacpra: „wybucha + ogień”). Party aut są `Locked` (kontrakt „wybuch
	-- nie tyka” — inaczej v3 ciąłby je na dziury i rozsypywał 72 drobne części osobno), więc
	-- bomba pomijała je w całości. Teraz auto w zasięgu DZIURY bomby wybucha jako całość:
	-- rozlatuje się u klientów, na jego miejscu płonie ogień (SAM efekt — nie rozprzestrzenia
	-- się i nie rani; pożary jako mechanika są poza v1.0), a wybuch idzie tą samą ścieżką co
	-- bomba (gracze + otoczenie), tylko słabszy. Auto obok w zasięgu dziury wybucha łańcuchowo.
	Cars = {
		-- Model = bezpośrednie dziecko takiego folderu. 21.10: + Barrels — beczki (czerwono-szare,
		-- 13 sztuk: Construction + OutsideDecorations) wybuchają tym samym torem co auta, z
		-- własnym profilem niżej (decyzje Kacpra: 1,3× bomby, od razu, łańcuch, kill dla odpalającego).
		Folders = { Cars = true, Barrels = true },
		-- Foldery, których model wybucha od PCHNIĘCIA (F, PushService) — tylko beczki, nie auta.
		PushIgnites = { Barrels = true },
		-- Foldery, których model przy zawaleniu (strop/podłoga pod nim znika) SPADA fizyką serwera
		-- i wybucha przy uderzeniu (21.10, Kacper: „przy collapsie beczka spada i przy kontakcie
		-- wybucha”). Zamiast animacji u klientów — serwer musi wiedzieć, gdzie i kiedy uderzyła.
		FallIgnites = { Barrels = true },
		Fall = {
			MinDrop = 2,      -- studów spadku, zanim zatrzymanie liczy się jako uderzenie (start na
			                  -- spadającej podłodze nie odpala od razu)
			StopSpeed = 6,    -- stud/s pionowo: wolniej po spadku = uderzyła i wybucha
			MaxTime = 6,      -- s; zaklinowana albo w lawie — wybucha i tak
		},
		-- s od trafienia do wybuchu. 0 = razem z bombą (Kacper 27.09: 0,35 s „wygląda jak bug”).
		-- Nawet przy 0 wybuch idzie klatkę później (task.delay w CarService) — wprost z wnętrza
		-- wybuchu bomby wszedłby w jej niedokończoną destrukcję.
		Delay = 0,
		FireTime = 6,              -- s płonięcia wraku (efekt u klientów)
		-- Wybuch auta: pola jak w ItemDefinitions.bomb (BombService.explodeAt), słabszy od bomby.
		Blast = {
			blastRadius = 16,       -- gracze (bomba: 22)
			damagePercent = 0.4,    -- MaxHealth w epicentrum (bomba: 0.6 od 10.10)
			knockbackForce = 380,   -- (bomba: 450)
			knockbackMinT = 0.3,
			ragdollDuration = 2,
			destruction = {
				radius = 18,        -- (bomba: 24)
				damage = 130,       -- (bomba: 160) → dziura do ~4 studów: łańcuch tylko dla aut tuż obok
				impulse = 85,
				minImpulseT = 0.1,
				glassRadius = 25,
			},
		},
		-- Profil per folder (21.10). Brak wpisu = Blast/FireTime aut wyżej.
		Profiles = {
			Barrels = {
				FireTime = 3,
				-- 1,3× bomby (decyzja Kacpra 21.10). `id` = broń w tagu zabójstwa i w logu.
				Blast = {
					id = "barrel",
					blastRadius = 29,       -- bomba 22
					damagePercent = 0.78,   -- bomba 0.6 — pełne HP przeżywa epicentrum
					knockbackForce = 585,   -- bomba 450
					knockbackMinT = 0.35,
					ragdollDuration = 2,
					destruction = {
						radius = 31,        -- bomba 24
						damage = 210,       -- bomba 160 → większa dziura, łańcuch do beczek obok
						impulse = 120,      -- bomba 95
						minImpulseT = 0.1,
						glassRadius = 40,   -- bomba 35; 40 = sufit FX.GlassMaxPanes
					},
				},
			},
		},
	},

	-- (KOLAPS SEKCJI v2 — `Collapse` z filarami `Pillar` — USUNIĘTY 2026-09-24 razem ze
	-- StructureService: na mapie było 0 filarów. Kolaps robi teraz v4: `Config.Structure`.)

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
		-- Przygniecenia gruzem NIE MA (decyzja Kacpra 29.09: „usuwamy obrażenia od spadającego
		-- gruzu”) — ranią bomba, wybuch auta, lawa i upadek. Nie wracać bez decyzji Kacpra.
	},

	-- STRONA KLIENCKA (ExplosionFXController + DebrisFXController). Wszystko lokalne,
	-- zero replikacji — dlatego liczby mogą być wysokie.
	FX = {
		-- ⚠️ ILE i JAK DŁUGO (liczby odłamków, kawałków, czasy leżenia, sufity) jest od
		-- 2026-09-23 w `Config.Graphics.Profile` (od 08.10 jeden profil dla wszystkich). Tu
		-- zostaje tylko KSZTAŁT i ZACHOWANIE.
		-- (Historia: 150 → 45 odłamków ogólnych 2026-08-12 — przy takiej chmurze NIE BYŁO
		-- WIDAĆ realnej destrukcji. Efekty mają podkreślać zniszczenie, nie je zasłaniać.)
		FragMinSize = 0.4,
		FragMaxSize = 1.5,
		FragMinSpeed = 18,
		FragMaxSpeed = 60,
		FragFadeTime = 0.45,  -- s gaśnięcia KAŻDEGO lokalnego kawałka (odłamek, gruz, mebel)
		-- 🔴 LOKALNY GRUZ NIE MA KOLIZJI (2026-09-23, pytanie Kacpra o dwóch graczy z różnymi
		-- trybami „chodzących po innym gruzie”). Leci fizyką silnika bez zderzeń, a odbicie,
		-- lądowanie i stertę liczy DebrisFXController promieniem omijającym postacie — więc
		-- gruz nie istnieje dla niczego, co wpływa na grę. Liczby niżej stroją tylko wygląd.
		-- (Usunięte razem z kolizjami: `FragDensity`, `GhostTime` i grupy kolizji gruzu.)
		MaxFlightTime = 6,     -- s — kawałek, który nie znalazł podłoża (próżnia, lawa bez dna), zamiera
		-- LEŻĄCY gruz sprawdza co chwilę, czy ma pod sobą podłoże (zgłoszenie 24.09: „party, przez
		-- które się przenika, lewitują” — kawałek leżący na stropie, który potem spadł, zostawał
		-- w powietrzu). Tyle leżących kawałków sprawdzamy na klatkę (po kolei) i tak głęboko
		-- szukamy podłoża pod spodem (sterta leży na podłodze najwyżej tyle nad nią).
		RestChecksPerFrame = 20,
		RestSupportProbe = 4,
		FloorNormalY = 0.55,   -- normalna bardziej pionowa niż to = podłoże (ląduje); mniej = ściana (odbija)
		MaxBounces = 1,        -- ile razy szybki kawałek odbije się od podłoża, zanim się położy
		BounceMinSpeed = 16,   -- stud/s wbijania w podłoże — wolniejszy kawałek od razu się kładzie
		Restitution = 0.3,     -- ile prędkości „w podłoże” zostaje po odbiciu
		BounceFriction = 0.6,  -- ile prędkości wzdłuż powierzchni zostaje po odbiciu (podłoże i ściana)
		WallRestitution = 0.35, -- odbicie od ściany/sufitu
		-- STERTA: gruz kładzie się NA leżącym gruzie (mapa wysokości w siatce XZ), zamiast
		-- przenikać na podłogę — inaczej pobojowisko byłoby płaskim dywanem.
		LandCellSize = 1.5,    -- stud — oczko siatki sterty
		PileSnap = 2,          -- stud — kawałek łapie się sterty tylko tuż nad nią (nie „teleportuje” piętro wyżej)
		-- MEBEL SIĘ PRZEWRACA (animacja zakotwiczona — zero fizyki): obrót wokół dolnej krawędzi
		-- od wybuchu, z przyspieszeniem. W trybie Pełnym po przewróceniu rozsypuje się na części.
		ToppleTime = 0.55,     -- s obrotu (odrzucony od wybuchu: × 0.6 — gwałtowniej)
		ToppleAngle = 88,      -- stopnie — mebel ląduje na boku
		ToppleJitter = 12,     -- ± stopnie (kąt i kierunek) — każdy mebel pada trochę inaczej
		-- Mebel/dekoracja, która PADA (nie odrzucona): lekki, losowy ruch, żeby rozsypywała
		-- się chaotycznie, a nie zjeżdżała w dół jak winda (prośba Kacpra: „trochę
		-- chaotycznie”). Prędkość w stud/s, obrót w rad/s.
		DropSpeed = 3,
		DropSpin = 2.5,
		-- Odrzucona drobnica koziołkuje szybciej niż padająca.
		LaunchSpin = 8,
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
		-- (Sufit na CAŁY wybuch jest w profilu grafiki: `GlassShardsPerBlastMax`.)
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

		-- Wstrząs ekranu przy kolapsie sekcji. WYŁĄCZONY (decyzja Kacpra 25.09: „usuń te
		-- wibracje przy niszczeniu filarów”) — v4 wysyła `collapse` przy KAŻDEJ spadającej
		-- grupie, więc przy kaskadzie ekran trząsł się bez przerwy. Pył i dźwięk zostają;
		-- wstrząs od samego wybuchu (ShakeMax niżej) też. Gałka zostaje, gdyby wrócić.
		CollapseShakeMax = 0,
		CollapseShakeDuration = 1.2,
		CollapseShakeDistance = 160,
		-- Obłoki pyłu kolapsu na sekundę u jednego klienta (29.09, B-6): budynek to kilkadziesiąt
		-- grup w kilku klatkach — przy kaskadzie obłoki i tak zlewają się w jeden.
		CollapseDustPerSecond = 6,
		-- Ostrzeżenie (creak) — wyłączone razem z kolapsem (ta sama decyzja).
		CreakShakeMax = 0,
		CreakShakeDuration = 0.9,
		CreakShakeDistance = 110,
		-- LOKALNY GRUZ = CIEMNOSZARY (decyzja Kacpra 25.09: „zmień kolor na jakiś ciemny
		-- szary, że to widać, że debris”). Gruz u gracza nie ma kolizji — kolor mówi „przez
		-- to przejdziesz, na tym nie staniesz”. Dotyczy gruzu z BUDOWY (kawałki dziur,
		-- posiekane bryły, odłamki); meble i szkło zostają w swoich kolorach.
		-- Kilka ODCIENI szarego zamiast jednego (Kacper 07.10: „daj różne odcienie szarego, a nie
		-- jeden”) — każdy kawałek losuje odcień z listy, potem lekki rozrzut jasności. Od ciemnego
		-- grafitu do średniej szarości, z odrobiną ciepła/chłodu (beton, popiół, cegła w pyle),
		-- ale dalej na tyle ciemno, żeby gruz odróżniał się od mapy.
		LocalDebrisColors = {
			Color3.fromRGB(44, 44, 47), -- grafit
			Color3.fromRGB(58, 58, 62), -- ciemny szary (dawny jedyny kolor)
			Color3.fromRGB(72, 70, 68), -- ciepły szary (beton)
			Color3.fromRGB(86, 87, 90), -- chłodny szary
			Color3.fromRGB(102, 100, 97), -- jasny popiół
		},
		LocalDebrisColorJitter = 0.06, -- ± jasność na kawałek w obrębie odcienia
		-- Pojedynczy przekazany part budynku dłuższy niż tyle jest SIEKANY na kawałki wielkości
		-- odłamków dziury (Fracture.TargetChunkSize), zamiast lecieć jednym klocem (Kacper
		-- 25.09: „skoro i tak nie ma kolizji, to go posiekaj, a nie że takie duże kloce
		-- zostają, przez które da się przechodzić” — zaklinowane stropy 22×33, szyny 66).
		HandoffSliceAbove = 4,
		-- ILE kawałków z jednej bryły (27.09, Kacper: „przy niedużym parcie powstaje z niego za
		-- dużo odpadu”, „za bardzo się sypią z całego parta”). Do tej pory liczba wynikała tylko
		-- z rozmiaru kawałka (Fracture.TargetChunkSize 3,2): panel 6×6 → ~4, klocek 8×8×8 → ~27,
		-- strop 22×33 → 48. Teraz ~1 kawałek na tyle studów³, z sufitem — duża bryła rozpada się
		-- na WIĘKSZE kawałki (Fracture.slice zawsze dzieli największy), a nie na 48 drobnych.
		-- Dotyczy przekazanych brył i dziur v4 (u klienta); dziury v3 zostają (serwer liczy je
		-- tym samym ziarnem co klient, zmiana tylko u klienta rozjechałaby resztki).
		DebrisPieceVolume = 12, -- studs³ na kawałek: panel 6×6×1 → 3, belka 13,5×3×1 → 4, klocek 3×6×1 → 2
		DebrisMaxPieces = 16,   -- sufit na bryłę / dziurę (było 48)
		-- Na której ścianie leży kawałek po upadku (27.09, Kacper: „zawsze stoją góra do góry,
		-- takie spiczaste”): losowo, z wagą (pole ściany)^wykładnik — jak w prawdziwym upadku
		-- najczęściej na największej. 3: płytka 3×3×1 leży płasko w ~94%, pręt 1×1×6 staje na
		-- końcu w ~0,1%; sześcian — równo. 0 = każda ściana tak samo prawdopodobna.
		RestFaceExponent = 3,
		-- Ambientowy screen shake dla każdego w pobliżu (trafieni dostają mocniejszy z BombHit).
		ShakeMaxDistance = 90,
		ShakeMax = 1.1,
		ShakeDuration = 0.5,
	},

	-- Log [Destr] per detonacja (struktura/kawałki/ms). WŁĄCZONE na czas strojenia —
	-- wyłączyć przed launchem (print × dziesiątki serwerów = śmieci w logach produkcji).
	Debug = true,
}

-- ===== DESTRUKCJA v4 — GRAF KONSTRUKCJI (2026-09-24) =====
-- DESTRUCTION_PLAN.md → aktualne reguły v4. Te same ustawienia czytają bake w Edit
-- i StructuralService w grze; wszystkie 10 budynków ma konfigurację poniżej.
-- Strojenie wymaga testu Kacpra; sama obecność ustawień nie potwierdza akceptacji Play.
Config.Structure = {
	-- Podbić przy każdej zmianie reguł bake'u, która zmienia dane — stare dane w placu
	-- przestają wtedy pasować. Przy AnalyzeIfMissing runtime analizuje geometrię od nowa;
	-- nie wolno grać na nieaktualnym grafie. MapRevision obecnie nie jest walidowane przez loadData.
	BakeVersion = 3, -- 2 (24.09): szkło wchodzi do danych jako pasażer (było pomijane → lewitowało)
	                 -- 3 (26.09): TrimLinks — styki listew dla passu podparcia listew

	-- Nazwy są kontraktem ze Studio (atrybuty ustawiane ręcznie w Properties → Attributes).
	Attributes = {
		SID = "SID",                         -- stabilne ID parta (pisze bake, przeżywa klonowanie mapy)
		Permanent = "StructPermanent",       -- bool: ten part nigdy nie spada (żółty w podglądzie)
		NonStructural = "StructNonStructural", -- bool: to nie konstrukcja, tylko listwa/ozdoba
		Kind = "StructKind",                 -- string: wymuszenie rodzaju (Slab/Beam/Wall/Column/Block/Trim/Other)
		MapRevision = "StructMapRevision",   -- number na folderze budynku: podbijany ręcznie po przeróbce
	},

	-- Foldery budynku, które NIE są konstrukcją (po nazwie, w całym drzewie budynku).
	ExcludeFolders = { "Decorations", "Lights" },

	-- KLASYFIKACJA po wymiarach w osiach ŚWIATA (part obrócony o 90° ma Size w innej kolejności).
	Classify = {
		MinStructuralSize = 6,  -- najdłuższy bok krótszy → nie konstrukcja (kostki, skrzynki)
		SlabMaxThickness = 2.5, -- strop: grubość ≤ tego i oba wymiary poziome ≥ SlabMinWidth
		SlabMinWidth = 6,
		TrimMaxThickness = 0.6, -- cieńsze (panele elewacji) → listwa
		TrimMaxWidth = 2,       -- drugi najmniejszy wymiar ≤ tego (pręty, listwy 1×1×N) → listwa
		VerticalMinHeight = 8,  -- pion: wysokość ≥ tego i grubość ≤ WallMaxThickness
		WallMaxThickness = 5,
		ColumnMaxWidth = 6,     -- pion o szerokości ≤ tego = słup (także filarek 3×5×12), szerszy = ściana
		BeamMinLength = 8,      -- poziomy i wydłużony → belka
	},

	-- PODZIAŁ NA CHUNKI (chunk ≠ part: słup 67 studów to jeden part i kilka pasm)
	ChunkMaxSize = 20,  -- ≈ rozmiar dziury po bombie (18×18) — rozdzielczość konstrukcji
	SnapDistance = 5,   -- linia podziału stropu przyciągana do belki/ściany/słupa bliżej niż tyle
	LevelTolerance = 3, -- stropy o środkach bliższych niż tyle w pionie = ten sam poziom
	MinBandHeight = 4,  -- pasmo pionu niższe niż tyle nie powstaje
	MinSegment = 3,     -- odcinek stropu/belki krótszy niż tyle nie powstaje

	-- STYKI
	ContactPadding = 0.15,     -- party „stykają się”, gdy dzieli je ≤ tyle
	GroundTolerance = 1.5,     -- spód chunka ≤ tyle nad najniższym partem budynku = stoi na gruncie
	OverlapReportDepth = 0.05, -- przenikanie głębsze niż tyle → lista par do odfiltrowania przy kolapsie

	-- SOLVER: „zasięg” = odległość od ostatniej PRAWDZIWEJ podpory (Bearing/Lateral zeruje,
	-- Continuity dolicza przęsło). Chunk dalej niż MaxSpan swojego rodzaju spada.
	MinInterfaceWidth = 1,
	MaxSpan = {
		Slab = 24,  -- jeden chunk wspornika (~20) + zapas; dwa już nie
		Beam = 24,
		Wall = 20,  -- nadproże nad wyrwą
		Column = 0, -- słup nie „wisi” na sąsiednim słupie
		Block = 0,
	},
	-- Które POZIOME elementy mogą trzymać PION z boku. Belka tak (węzeł ramy: słup podcięty
	-- przy ziemi wisi na belkach), strop NIE — inaczej po podcięciu wszystkich słupów cała
	-- wieża „wisiałaby” na cienkim stropie parteru. Pion zawieszony na belce dziedziczy jej
	-- zasięg — belka na wsporniku nie utrzyma słupa (MaxSpan.Column = 0).
	LateralHoldsVertical = { Beam = true },

	-- Szacunek „ile bomb kładzie budynek” (cel Kacpra: ~8). Bomba = wszystkie chunki podanych
	-- rodzajów w promieniu cięcia (dziura ~18×18 przecina słup, pasmo ściany, belkę; stropu
	-- nie przecina — tylko zwęża). Zachłannie: każda kolejna bomba tam, gdzie zrzuci najwięcej.
	BombEstimateRadius = 9,
	BombEstimateKinds = { Column = true, Wall = true, Block = true, Beam = true },
	BombEstimateFallShare = 0.6, -- liczymy, aż spadnie tyle chunków budynku
	BombEstimateMax = 30,

	-- OBRAŻENIA (faza B). Dwie niezależne gałki (pomysł z debaty 24.09): DZIURY (geometria)
	-- i MOC STRUKTURALNA (przecinanie nośnych) — można osłabić jedno bez drugiego.
	-- ⚠️ HoleThreshold i MinHoleRadius to te same liczby co v3 (Categories.Wall.HP,
	-- Fracture.MinHoleRadius) — dwie kopie tylko do końca migracji, v3 zniknie.
	Damage = {
		HoleThreshold = 100,       -- obrażenia na powierzchni parta, od których powstaje dziura
		MinHoleRadius = 3.5,
		MinStrip = 1.4,            -- pas „okna” węższy niż tyle nie zostaje (dziura do krawędzi)
		SeverTolerance = 0.3,      -- dziura musi pokryć przekrój nośny chunka z taką dokładnością
		StructuralPowerFactor = 1, -- mnożnik obrażeń bomby dla konstrukcji
		-- Decyzja Kacpra 24.09: bomba OBOK nośnego elementu go osłabia — obrażenia się sumują,
		-- przy sumie ≥ HP element się kruszy. Bomba 160 w promieniu 24 kruszy element w ~9
		-- studach jednym strzałem, a w ~15 studach dopiero drugim.
		HP = { Column = 100, Wall = 100, Block = 140, Beam = 100 },
		DamagedFrom = 0.25,        -- od tej części HP element jest „Damaged” (widoczne rysy)
	},

	-- GRUPY KOLAPSU (faza C): logiczne chunki ≠ fizyczne bryły. Spadające chunki łączą się
	-- w grupy (każda = jedna bryła fizyki), żeby wieża nie spadała jako 100 osobnych kawałków.
	Planner = {
		BondMinWidth = 2,      -- węższy styk między spadającymi chunkami nie trzyma ich razem
		GroupMaxFootprint = 40, -- większa grupa jest dzielona (bryła 60×60 wygląda jak tektura)
		GroupMaxChunks = 24,
		GroupMinVolume = 300,  -- mniejsza grupa dołącza do sąsiedniej spadającej
	},

	-- ===== FAZA D — GRA (2026-09-24) =====
	-- Które budynki gra prowadzi na v4. Reszta mapy zostaje na v3, dopóki nie przejdzie
	-- przez bake i test (migracja budynek po budynku).
	-- Budynki na v4 (klucz = nazwa folderu w Map.Buildings). `true` = reguły ogólne; tabela =
	-- ustawienia tylko dla tego budynku (26.09, migracja GreenBuildingu — decyzje Kacpra):
	--   MaxSpan           — własne przęsła (np. { Slab = 27 }), SandBuilding 27.09; bake i solver w grze.
	--   TrimMaxThickness  — własny próg grubości listwy (Classify.TrimMaxThickness).
	--   TrimMaxWidth      — własny próg listwy (Classify.TrimMaxWidth). GreenBuilding stoi na
	--                       belkach krawędziowych 1×2, które przy ogólnym 2 są listwami (250 z 284
	--                       chunków bez podparcia); ogólne 1,9 psuje za to OrangeBuilding.
	--   DemoteUnsupported — element konstrukcji bez podparcia w NIETKNIĘTYM budynku staje się
	--                       listwą (tunel torów w GreenBuildingu: „spada z budynkiem”).
	--   Guests            — foldery spoza budynku, których kawałek w jego obrysie jest listwą
	--                       budynku: stoi, póki dotyka czegoś stojącego, spada z budynkiem
	--                       („tylko ten kawałek torów, nie całe”).
	Buildings = {
		OrangeBuilding = { Guests = { "Railway" } },
		GreenBuilding = { TrimMaxWidth = 1.9, DemoteUnsupported = true, Guests = { "Railway" } },
		-- 27.09 (decyzja Kacpra: najpierw budynki bez poprawek). Pomiar w Edit, nietknięty budynek:
		-- OrangeKebab i CyanOffice stoją na regułach ogólnych (0 czerwonych), OldBuilding2 ma
		-- 4 czerwone przy progu 2 i 0 przy 1,9. Czekają: PurpleSchool (183/325 — belki 1×2 jak
		-- w GreenBuildingu; 1,9 + degradacja 6), OldBuilding1 (1,9 + 2), Construction (degr. 1),
		-- SandBuilding (degr. 9), PupleHotel (degr. 10).
		OrangeKebab = true,
		CyanOffice = true,
		OldBuilding2 = { TrimMaxWidth = 1.9 },
		-- 27.09 (druga tura, decyzja Kacpra): degradacja zamienia w listwy tylko DROBNE elementy —
		-- PurpleSchool: ozdobne słupki na dachu 4×18×4 / 4×14×4 z czapkami i 2 klocki; OldBuilding1:
		-- 5 paneli 1×6×3 (próg 1,9 mu szkodzi — robi czerwony strop 32×30); Construction: 1 element
		-- 7×3×1; PupleHotel: 8 paneli i 2 belki 8×1×13. SandBuilding CZEKA: nawet z progami 0,4/1,9
		-- zostaje 1 czerwony róg stropu 44×0,5×73, a degradacja zrobiłaby listwę z CAŁEGO stropu.
		PurpleSchool = { TrimMaxWidth = 1.9, DemoteUnsupported = true },
		OldBuilding1 = { DemoteUnsupported = true },
		Construction = { DemoteUnsupported = true },
		PupleHotel = { DemoteUnsupported = true },
		-- 27.09: czerwony był ŚRODEK stropu 44×0,5×73 (nie róg): najkrótsza droga do pionu 25,8 >
		-- MaxSpan.Slab 24. Z progiem grubości 0,4 (ściany 0,5 niosą), szerokości 1,9 i Slab 27 —
		-- 0 czerwonych bez degradacji (~20 listew → belki), szacunek 8 bomb. Degradacja zrobiłaby
		-- listwę z całego stropu (znikałby spod nóg zamiast spadać).
		SandBuilding = { TrimMaxThickness = 0.4, TrimMaxWidth = 1.9, MaxSpan = { Slab = 27 } },
	},
	-- Brak zapisanych danych (TRYB 3 bake'u) → dane liczone przy starcie rundy (~15 ms na
	-- budynek, ten sam kod co bake). Wygodne w prototypie; przed launchem dane mają być
	-- zapisane i sprawdzane odciskiem geometrii (kontrakt v4).
	AnalyzeIfMissing = true,

	-- WYKONAWCA KOLAPSU (CollapseService). Wszystko to WARTOŚCI STARTOWE do benchmarku.
	Collapse = {
		-- Budżet fizyki: grupa kosztuje 1 + liczba kawałków z kolizją. Rezerwa tylko dla
		-- grup, na których ktoś stoi (P0) — jeździec nigdy nie traci podłogi przez budżet.
		-- 60 → 100 po teście 24.09: przy zawaleniu wieży (25 grup) 16 grup nie zmieściło się,
		-- serwer oddawał je klientom i górne piętra po prostu znikały („na 3. piętrze już nie ma ścian”).
		MaxCost = 100,
		ReserveP0 = 15,
		-- Grupa bez miejsca w budżecie CZEKA na zwolnienie (grupy osiadają w ~1 s), zamiast od
		-- razu przejść na animację u klientów. Kolejka idzie od dołu, więc piętro wyżej wisi
		-- chwilę dłużej i spada na to, co już leży — naturalna kaskada. Dopiero po tylu
		-- sekundach czekania upadek przejmują klienci.
		MaxQueueWait = 1.5,
		-- Ile grup odkotwiczamy w jednej klatce — kaskada rozkłada się na kilka klatek
		-- (opóźnienie techniczne, nie ostrzeżenie: Kacper chce „natychmiast”).
		MaxReleasesPerFrame = 4,
		NearPlayerDistance = 60, -- P1: gracz tak blisko grupy
		RiderHeight = 5,         -- P0: stopy gracza do tylu nad górą grupy (w jej rzucie)
		-- Start lotu: lekkie pchnięcie w dół i odrobina obrotu — piętro się odrywa, nie
		-- wystrzeliwuje (duże prędkości = latające płyty, sztuczne).
		FallSpeed = 4,
		Spin = 0.25,
		-- Osiadanie: grupa wolniejsza niż SettleSpeed przez SettleTime = zakotwiczona na miejscu.
		SettleSpeed = 1.5,
		SettleTime = 0.6,
		MaxFallTime = 8,       -- po tylu sekundach lotu kotwiczymy na siłę
		-- ZAKLINOWANIE (test dymny 25.09: 21 z 25 grup „osiadło” w miejscu po 0,7 s, bo
		-- fizycznie coś je trzymało). Grupa, która po JamCheckTime od odkotwiczenia przesunęła
		-- się mniej niż JamMinMove i obróciła mniej niż JamMinAngle, idzie do klientów
		-- (decyzja Kacpra 25.09). 0,4 s: wolna grupa spada w tym czasie ~17 studów, więc 1 stud
		-- to pewny sygnał; krócej łapałoby grupy leżące chwilę na przekazanym (0,25 s) gruzie.
		JamCheckTime = 0.4,
		JamMinMove = 1,
		JamMinAngle = 0.05,    -- rad (~3°) — ściana przewracająca się na zawiasie też „rusza”
		JamProbe = 0.3,        -- stud pod spodem grupy: szukanie tego, co ją trzyma (do logu)
		JamBelowOverlap = 0.3, -- stud zakładki w poziomie, żeby styk liczył się jako „pod spodem”/„nad”
		JamLogMax = 8,         -- styków w logu zaklinowania (najpierw POD); reszta jako „(+N)”
		-- Styk przy STARCIE grupy (28.09): party bliżej niż tyle „dotykają się”. Filtr dostaje dotyk
		-- ze stojącą częścią budynku v4 (z każdej strony) i z inną spadającą grupą (z boku) —
		-- log 28.09: najczęstszym „trzymaczem” był styk ściana w ścianę (BOK 0.00) z resztą parta.
		ReleaseContactPad = 0.05,
		-- Grupa, która opadła o co najmniej tyle i leży na STOJĄCEJ konstrukcji v4, wylądowała
		-- (osiada). Mniej = trzymało ją to od startu (styk bez filtra) — to przypadek dla siatki.
		LandMinDrop = 0.1,
		-- Kikut przeciętego elementu dotykający grupy bliżej niż tyle leci razem z nią
		-- (decyzja Kacpra 25.09). Mniejsze niż ContactPadding bake'u (0,15) gubiłoby styki,
		-- które solver widział; dużo większe łapałoby kikuty tylko stojące obok.
		StubContact = 0.2,
		MonitorHz = 10,
		-- Gruz po zatrzymaniu (decyzja Kacpra 24.09): duże elementy zostają do końca rundy
		-- jako platformy, małe znikają po kilku sekundach.
		SmallRubbleVolume = 300,
		SmallRubbleLifetime = 4,
		-- TWARDE RUINY (08.10, pomysł Kacpra: „20-30% ruin spada z kolizją w takich kształtach,
		-- jakie były”). Do tej pory po zawaleniu zostawały tylko duże bryły, a reszta znikała albo
		-- szła do graczy jako gruz bez kolizji — z budynku robiła się przechodnia kupa.
		--   * Mała bryła (< SmallRubbleVolume) z tą szansą NIE znika po SmallRubbleLifetime, tylko
		--     leży do końca rundy (losowane RAZ, przy pierwszym osiadaniu — ponowne osiadanie po
		--     wybudzeniu nie podbija szansy). Leży zakotwiczona, więc fizyki nie kosztuje.
		--   * Mały fragment kruszenia (FragmentMinVolume > objętość ≥ SolidFragmentMinVolume) z tą
		--     szansą spada fizyką serwera jak duży, zamiast u graczy bez kolizji — i zostaje. W tym
		--     samym budżecie (MaxCost): bez miejsca idzie do graczy jak dotąd.
		KeepSmallRubbleChance = 0.25,
		SolidFragmentChance = 0.25,
		SolidFragmentMinVolume = 8, -- okruchy mniejsze niż ~2×2×2 zawsze u graczy (drgałyby i plątały się pod nogami)
		LavaCullMargin = 1,
		-- Filtr kolizji na starcie: pary kawałek grupy ↔ stojąca konstrukcja, które na siebie
		-- NACHODZĄ (158 par w OrangeBuilding), nie zderzają się — inaczej silnik wypycha
		-- odkotwiczony kawałek „wybuchowo”.
		OverlapMinDepth = 0.05, -- dotyczy oparcia od spodu; styk z boku filtrowany zawsze (needsFilter)
		OverlapFilterMax = 80,
		-- Kawałek ze skruszonego elementu: duży = fragment fizyki serwera (ściany mogą
		-- naprawdę odlecieć — decyzja Kacpra), mały = animacja u klientów. Od 28.09 (decyzje
		-- Kacpra) fragment to rumowisko kolapsu: koszt 2 z MaxCost (bez miejsca → u klientów),
		-- leżący jest cięty bombą, mały (< SmallRubbleVolume) znika po SmallRubbleLifetime.
		FragmentMinVolume = 45,
		FragmentSpeed = 18,
		-- Obudzona LEŻĄCA bryła dostaje tylko tyle impulsu fali (decyzja Kacpra 25.09: „mniejszy
		-- odrzut dla wszystkich”) — pełny wyrzucał ją 72 stud/s na 45 studów i zabijał przygnieceniem.
		WakeImpulseFactor = 0.3,
		-- Przekazanie klientom (Remotes.DebrisFall): zasięg i siła, z jaką klient wyrzuca
		-- skruszone kawałki (upadek grup ponad budżetem leci bez wyrzutu).
		HandoffRadius = 24,
		HandoffImpulse = 50,
		-- Osiadła bryła BEZ OPARCIA (M-1, decyzja Kacpra 29.09: spada fizyką). Sprawdzamy ją od
		-- razu, gdy coś pod nią zniknie (start grupy, wybuch, zniknięcie bryły), a poza tym po
		-- kolei w tle: najwyżej tyle brył na przebieg monitora, każdą nie częściej niż co tyle s.
		RubbleRecheckPerTick = 4,
		RubbleRecheckInterval = 2,
		RubbleRecheckPad = 1,     -- stud: zasięg „coś pod nią zniknęło” wokół zdarzenia
		-- Budzona bryła (bombą albo bez oparcia) nie może zostać WYSTRZELONA przez silnik, który
		-- wypycha ją z nachodzącej geometrii (M-4): przez WakeClampTime prędkość w bok i w górę
		-- jest przycinana do zamierzonej + zapas; w dół bez limitu (spadanie to grawitacja).
		WakeClampTime = 0.5,
		WakeSpeedMargin = 6,      -- stud/s ponad prędkość nadaną wybuchem
		WakeSpinMargin = 1,       -- rad/s ponad obrót nadany wybuchem
		MinPieceSize = 0.05, -- kawałek cieńszy niż tyle przy podziale = błąd zaokrąglenia, pomijamy
		Debug = true,        -- log [Collapse] — wyłączyć przed launchem
	},
}

-- ===== GRAFIKA — JEDEN PROFIL (08.10) =====
-- Do 08.10 były dwa tryby: Ziemniak (telefon) i Pełny (mocny PC), z wyborem w ustawieniach
-- i zapisem w DataStore. Decyzja Kacpra 08.10: „usuń tryb potato i full, zrób jeden po
-- środku” — każda liczba to środek między dawnymi trybami; z włączników: meble się
-- rozsypują (było tylko w Pełnym), gruz NIE rzuca cieni (było tylko w Pełnym).
-- Ustawienie WYŁĄCZNIE KOSMETYCZNE: serwer robi dla wszystkich dokładnie to samo (te same
-- dziury, te same płyty) — profil decyduje tylko, ile gruzu, kurzu i odłamków KLIENT
-- dorysowuje u siebie. Czytają go ExplosionFXController i DebrisFXController.
Config.Graphics = {
	Profile = {
		ClientFrags = 25,           -- ogólne odłamki z otoczenia na wybuch (było 10 / 45)
		CutChunksPerBlast = 60,     -- kawałki z dziur w ścianach/podłogach, największe pierwsze (16 / 110)
		FallPartsPerBlast = 500,    -- party mebli/dekoracji przejęte od serwera na wybuch (150 / 900)
		ShatterFurniture = true,    -- przewrócony mebel rozsypuje się na części; blisko bomby — od razu
		RubbleLifetime = 10,        -- s leżenia gruzu i mebli (3 / 20)
		FragLifetime = 3.5,         -- s życia drobnych odłamków (2 / 5)
		GlassShardScale = 0.65,     -- mnożnik liczby odłamków szkła na taflę (0,35 / 1)
		GlassShardsPerBlastMax = 90, -- (40 / 150)
		ParticleScale = 0.75,       -- mnożnik cząsteczek wybuchu: ogień, dym, iskry, pył (0,5 / 1)
		MaxLocalParts = 1000,       -- sufit WSZYSTKICH lokalnych partów, najstarsze gasną (300 / 2000)
		CastShadows = false,        -- gruz bez cieni (decyzja Kacpra 08.10)
		FXDistance = 230,           -- dalej od kamery gruzu nie rysujemy wcale (160 / 300)
		RaysPerFrame = 200,         -- sufit promieni lądowania na klatkę, reszta gruzu czeka (80 / 400)
	},
}

for _, profile in pairs(Config.ItemEquip.Profiles) do
	for _, key in ipairs(profile) do table.freeze(key) end
	table.freeze(profile)
end
table.freeze(Config.ItemEquip.Profiles)
table.freeze(Config.ItemEquip.ProfileDurations)
for _, pose in pairs(Config.ItemEquip.HoldPoses) do table.freeze(pose) end
table.freeze(Config.ItemEquip.HoldPoses)
table.freeze(Config.ItemEquip.ToolProfiles)
table.freeze(Config.ItemEquip)
table.freeze(Config.Dev.Usernames)
table.freeze(Config.Dev)
table.freeze(Config.Game)
table.freeze(Config.PlayerData)
table.freeze(Config.UI.HotbarEquip)
table.freeze(Config.UI.Inventory.ItemColors)
table.freeze(Config.UI.Inventory.CardStyles)
table.freeze(Config.UI.Inventory.LavaScroll)
table.freeze(Config.UI.Inventory.AddColors)
table.freeze(Config.UI.Inventory.RemoveColors)
table.freeze(Config.UI.Inventory.SwapColors)
for _, l in ipairs(Config.UI.Inventory.ShowcaseLights) do table.freeze(l) end
table.freeze(Config.UI.Inventory.ShowcaseLights)
table.freeze(Config.UI.Inventory)
table.freeze(Config.Loadout)
table.freeze(Config.UI.Timer)
table.freeze(Config.UI)
-- Spawn ma Vector3 fields — freeze tylko po:
table.freeze(Config.Spawn)
table.freeze(Config.Map.RestoreGroups)
table.freeze(Config.Map)
table.freeze(Config.RoundTransition)
table.freeze(Config.Lava.Part)
table.freeze(Config.Lava.HeatEffect)
table.freeze(Config.Lava.Swim)
table.freeze(Config.Lava.Submerged)
table.freeze(Config.Lava.Surface.LayerMultipliers)
table.freeze(Config.Lava.Wobble)
table.freeze(Config.Lava.Waves)
table.freeze(Config.Lava.FX)
table.freeze(Config.Lava.Surface)
table.freeze(Config.Lava)
for _, row in ipairs(Config.Cash.Fly.Notes) do
	table.freeze(row)
end
table.freeze(Config.Cash.Fly.Notes)
table.freeze(Config.Cash.Fly)
table.freeze(Config.Cash.PickupTrail)
table.freeze(Config.Cash.DigitDisplay)
table.freeze(Config.Cash)
table.freeze(Config.Bridge)
table.freeze(Config.Shop.SignFlowColors)
table.freeze(Config.Shop.BuyColors)
table.freeze(Config.Shop.NoCashColors)
table.freeze(Config.Shop.FailTexts)
table.freeze(Config.Shop)
table.freeze(Config.Movement.Stamina)
table.freeze(Config.Movement.StaminaBar)
table.freeze(Config.Movement.HeadTrack)
table.freeze(Config.Movement.Camera.RotationSmoothing)
table.freeze(Config.Movement.Camera.HitReaction)
table.freeze(Config.Movement.Camera.SprintShake)
table.freeze(Config.Movement.Camera.Lean)
table.freeze(Config.Movement.Camera)
table.freeze(Config.Movement)
table.freeze(Config.Ladder)
table.freeze(Config.Push)
for _, row in ipairs(Config.EnergyDrink.Sip) do
	table.freeze(row)
end
table.freeze(Config.EnergyDrink.Sip)
table.freeze(Config.EnergyDrink.Palette)
table.freeze(Config.EnergyDrink.VignetteColors)
table.freeze(Config.EnergyDrink)
table.freeze(Config.Rpg.Recoil)
table.freeze(Config.Rpg)
table.freeze(Config.RateLimits)
table.freeze(Config.AntiCheat)
table.freeze(Config.KillMessage)
table.freeze(Config.WinMessage)
table.freeze(Config.Rewards)
table.freeze(Config.Destruction.Categories.Wall)
table.freeze(Config.Destruction.Categories.Glass)
table.freeze(Config.Destruction.Categories.Pillar)
table.freeze(Config.Destruction.Categories.Bridge)
table.freeze(Config.Destruction.Categories.Small)
table.freeze(Config.Destruction.Categories)
table.freeze(Config.Destruction.Small)
table.freeze(Config.Destruction.Props)
table.freeze(Config.Destruction.DamageFeedback)
table.freeze(Config.Destruction.DamageAttributes)
table.freeze(Config.Destruction.Occlusion)
table.freeze(Config.Destruction.Support)
table.freeze(Config.Destruction.Impact)
table.freeze(Config.Destruction.Fracture)
table.freeze(Config.Destruction.Shockwave)
table.freeze(Config.Destruction.Debris)
table.freeze(Config.Destruction.FX)
table.freeze(Config.Destruction)
table.freeze(Config.Graphics.Profile)
table.freeze(Config.Graphics)
-- COSMETICS: durable purchases, independent from consumable item loadout.
Config.Cosmetics = {
	AssetFolder = "Cosmetics",
	ShopModelName = "ClothesShop",
	NpcName = "NPC",
	PromptName = "CosmeticsPrompt",
	PromptMaxDistance = 12,
	InteractDistance = 18,
	RequestsPerSecond = 10,
	Prices = { HalloweenPumpkin = 500, KevlarVest = 750, SchoolBackpack = 600 },
	SceneName = "ClothesShopScene",
	PlatformPath = { "Decoriations", "Platform", "platform" },
	UI = {
		Width = 1920, Height = 1080, ScreenMargin = 48,
		PortraitWidth = 800, PortraitHeight = 1200,
		Columns = 3, Gap = 28, RowHeight = 320, CardPadding = 24,
		CatalogTop = 180, CatalogBottom = 82,
		BalanceTop = 88, BalanceSafeTopPixels = 64,
		LargeCards = { HalloweenPumpkin = true },
		HoverTime = 0.16, HoverScale = 1.015,
		OpenTime = 0.22, OpenScale = 0.985,
		BackdropTransparency = 0,
		-- Catalog background (27.10): studs drift up like heat off the lava, the glow at the
		-- bottom breathes. Slow on purpose — the cards are what the eye should follow.
		BackdropDriftSpeed = 10, BackdropGlowPeriod = 5, BackdropGlowLift = 0.03,
		BackdropGlowPeak = Color3.fromRGB(104, 38, 15),
		RequestTimeout = 6,
		CameraFov = 40, CameraDistance = 11, CameraHeight = 1,
		StandYaw = -90,
		FittingFillOffset = Vector3.new(0, 2, -4),
		FittingFillBrightness = 2, FittingFillRange = 16,
		FittingFillColor = Color3.fromRGB(255, 242, 226),
		DragDegrees = 360, FittingHeightFraction = 0.58, FittingFocusOffset = 0.04, FittingCameraLift = 1.0,
		CardAmbient = Color3.fromRGB(195, 195, 205),
		CardLight = Color3.fromRGB(255, 245, 230),
		CardLightDirection = Vector3.new(-1, -1, -2),
		-- Cards show the item alone (27.10, item-shop look); the fitting room shows it worn.
		CardFov = 30, CardDistanceFactor = 1.0,
		CardFrontView = Vector3.new(0.55, 0.3, -1), CardBackView = Vector3.new(-0.55, 0.3, 1),
		MannequinColor = Color3.fromRGB(188, 193, 210),
		-- Large cards sway and spin their rays all the time; the rest only under the cursor.
		CardSwayDegrees = 22, CardSwaySpeed = 1.3, RaysSpeed = 14, SwayEase = 4,
		FittingSpinSpeed = 20, FittingSpinDelay = 3,
		CashCountTime = 0.45,
		UnlockedPopTime = 0.35, UnlockedHold = 1.4, UnlockedFadeTime = 0.25, UnlockedRaysSpeed = 40,
		-- The colour of a card says how special the item is (rarity), not which slot it uses.
		Rarities = {
			Common = { Label = "COMMON", Text = Color3.fromRGB(210, 215, 225), Rays = Color3.new(1, 1, 1),
				Fill = ColorSequence.new(Color3.fromRGB(190, 195, 205), Color3.fromRGB(80, 85, 98)) },
			Rare = { Label = "RARE", Text = Color3.fromRGB(110, 200, 255), Rays = Color3.new(1, 1, 1),
				Fill = ColorSequence.new(Color3.fromRGB(60, 180, 255), Color3.fromRGB(15, 60, 160)) },
			Epic = { Label = "EPIC", Text = Color3.fromRGB(215, 150, 255), Rays = Color3.new(1, 1, 1),
				Fill = ColorSequence.new(Color3.fromRGB(200, 110, 255), Color3.fromRGB(70, 20, 140)) },
			Legendary = { Label = "LEGENDARY", Text = Color3.fromRGB(255, 215, 80), Rays = Color3.new(1, 1, 1),
				Fill = ColorSequence.new(Color3.fromRGB(255, 205, 60), Color3.fromRGB(200, 80, 10)) },
			-- Seasonal, not a step above Legendary: dark night card so the orange item pops.
			Halloween = { Label = "HALLOWEEN", Text = Color3.fromRGB(255, 170, 70), Rays = Color3.fromRGB(255, 150, 40),
				Fill = ColorSequence.new(Color3.fromRGB(105, 45, 165), Color3.fromRGB(32, 12, 58)) },
		},
		-- Same gradients as the weapon shop price/BUY, the X button and the yellow HUD counters.
		Colors = {
			Price = ColorSequence.new(Color3.fromRGB(70, 215, 95), Color3.fromRGB(10, 140, 52)),
			Wearing = ColorSequence.new(Color3.fromRGB(255, 240, 33), Color3.fromRGB(255, 130, 0)),
			Owned = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 205)),
			Buy = ColorSequence.new(Color3.fromRGB(70, 215, 95), Color3.fromRGB(10, 140, 52)),
			Equip = ColorSequence.new(Color3.fromRGB(255, 240, 33), Color3.fromRGB(255, 130, 0)),
			Unequip = ColorSequence.new(Color3.fromRGB(255, 95, 80), Color3.fromRGB(200, 30, 25)),
			Disabled = ColorSequence.new(Color3.fromRGB(140, 140, 150), Color3.fromRGB(80, 80, 92)),
		},
	},
}
table.freeze(Config.Cosmetics.Prices)
for _, rarity in pairs(Config.Cosmetics.UI.Rarities) do table.freeze(rarity) end
table.freeze(Config.Cosmetics.UI.Rarities)
table.freeze(Config.Cosmetics.UI.Colors)
table.freeze(Config.Cosmetics.UI.LargeCards)
table.freeze(Config.Cosmetics.UI)
table.freeze(Config.Cosmetics)
table.freeze(Config)

return Config
