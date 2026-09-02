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

	-- Klawisze (tylko dla devów; zwykły gracz nawet nie podpina listenera).
	SkipKey = Enum.KeyCode.P,     -- skip bieżącej fazy/stanu (LOBBY→ROUND w 2 klik)
	EndRoundKey = Enum.KeyCode.O, -- natychmiastowy koniec rundy (restore mapy, nagrody)
}

Config.Game = {
	MinPlayers = 1, -- TODO Day 7: ustaw na 2 przed publishem.
	MaxPlayers = 20,
	LobbyDuration = 15,
	CountdownDuration = 5,
	PostRoundDuration = 10,
}

Config.Lava = {
	-- ⚠️ WYŁĄCZONA NA TESTY DESTRUKCJI (2026-08-12, prośba Kacpra). Part lawy istnieje
	-- (CashPickup/LavaHeat go czytają), ale NIE rośnie i NIE zabija.
	-- PRZYWRÓCIĆ true przed testem pełnych rund i przed launchem!
	Enabled = false,
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
	Phases = {
		{ Name = "Spawn",   Speed = 0.0, Duration = 10 },  -- "Get ready" grace
		{ Name = "Easy",    Speed = 0.6, Duration = 150 },
		{ Name = "Mid",     Speed = 1.2, Duration = 150 },
		{ Name = "Hard",    Speed = 2.0, Duration = 150 },
		{ Name = "Endgame", Speed = 3.0, Duration = 140 },
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
	-- Default visual gdy ReplicatedStorage.BridgeTemplate nie istnieje.
	-- Kacper może podrzucić własny model (np. drewniany most z toolboxa) — kod sam użyje.
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
		RegenRate = 1.5,
		-- Opóźnienie regeneracji po skończeniu sprintu (s). Zapobiega spam shift.
		RegenDelay = 0.8,
		-- Próg minimalny żeby zacząć sprint po wyczerpaniu (anti-stutter).
		-- Gdy stamina spada do 0 → force walk → musi naładować się do tego progu
		-- zanim Shift znów zadziała. Bez tego: 0 stamina → puszczam-łapię shift, mikro-sprinty.
		MinToResume = 1.0,
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
Config.RateLimits = {
	BombThrow = 0.5,
	Push = 4,
	BridgeBuild = 0.5,
	-- EquipItem+UnequipItem: klik hotbar slot. Spam clickowanie = flickering Tool
	-- w rękach innych klientów + bandwidth. 0.15s = ~7 kliknięć/s max, ludzki reflex OK.
	EquipItem = 0.15,
	-- ClaimDaily: klik CLAIM w daily rewards. 1s wystarczy — server i tak odrzuca drugi claim.
	DailyClaim = 1,
}

Config.DailyRewards = {
	-- Nagrody za kolejne dni streaka. Dzień 8+ = ostatni wpis w kółko (500$/dzień).
	-- Streak resetuje się do dnia 1 gdy gracz pominie dzień kalendarzowy (UTC).
	Rewards = { 50, 75, 100, 150, 200, 300, 500 },
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
		-- Budżet globalny (soft): wybuch przy zapchanym serwerze i tak rusza MinChunksPerBlast,
		-- bo bomba za 50$ która "nic nie zrobiła" wkurza bardziej niż chwilowy skok fizyki.
		MaxMovingDebris = 450,
		MinChunksPerBlast = 40,
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
		MinFractureVolume = 18,   -- studs³ — drobnica nie pęka (za mała żeby było widać)
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
		ShardsPerPaneMax = 6,  -- max odłamków z jednej szyby (skaluje z powierzchnią)
		ShardLifetime = 2.5,   -- s życia odłamka szkła zanim fade
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
table.freeze(Config.Lava)
table.freeze(Config.Cash.Popup)
table.freeze(Config.Cash.PickupTrail)
table.freeze(Config.Cash.DigitDisplay)
table.freeze(Config.Cash)
table.freeze(Config.Bridge)
table.freeze(Config.Movement.Stamina)
table.freeze(Config.Movement.HeadTrack)
table.freeze(Config.Movement.Camera.RotationSmoothing)
table.freeze(Config.Movement.Camera.HitReaction)
table.freeze(Config.Movement.Camera)
table.freeze(Config.Movement)
table.freeze(Config.Push)
table.freeze(Config.RateLimits)
table.freeze(Config.AntiCheat)
table.freeze(Config.Rewards)
table.freeze(Config.DailyRewards.Rewards)
table.freeze(Config.DailyRewards)
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
