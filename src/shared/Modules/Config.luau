--!strict
-- Config.luau
-- Single source of truth dla WSZYSTKICH liczb w ESCAPE LAVA.
-- Zasada: zero magic numbers w services. Wszystko stąd.

local Config = {}

Config.Game = {
	MinPlayers = 1, -- TODO Day 7: ustaw na 2 przed publishem.
	MaxPlayers = 20,
	LobbyDuration = 15,
	CountdownDuration = 5,
	PostRoundDuration = 10,
}

Config.Round = {
	-- TotalDuration = suma Phases.Duration poniżej; obliczana w runtime.
}

Config.Lava = {
	StartY = -5,
	MaxY = 250,
	-- DESIGN: szybka i dynamiczna gra. Runda ~80s total, nie 5+ minut.
	-- Jak chcesz wydłużyć — najpierw test czy nie nudzi.
	Phases = {
		{ Name = "Spawn",   Speed = 0.0, Duration = 5 },   -- "Get ready" grace
		{ Name = "Easy",    Speed = 0.6, Duration = 20 },
		{ Name = "Mid",     Speed = 1.2, Duration = 20 },
		{ Name = "Hard",    Speed = 2.0, Duration = 20 },
		{ Name = "Endgame", Speed = 3.0, Duration = 15 },
	},
	Part = {
		SizeXZ = 600,
		Thickness = 6,
		Color = Color3.fromRGB(255, 80, 0),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	},
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
	-- Czas trwania client-side animacji łuku pickup w sekundach. Zwiększone z 0.35 do 0.5
	-- żeby parabola była widoczna i feeling "rzuca się" miał czas wybrzmieć.
	MagnetSpeed = 0.5,
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
	PickupArcMinLift = 2,
	PickupArcLiftFraction = 0.35,
	PickupArcMaxLift = 8,
	-- Ile pełnych obrotów cash wykonuje w trakcie lotu po łuku. Visual flair.
	PickupSpinTurns = 2.5,

	-- Domyślny styl gdy ReplicatedStorage.Cash nie istnieje. Kacper wrzuci asset → kod sam użyje.
	DefaultColor = Color3.fromRGB(255, 215, 0),
	DefaultSize = Vector3.new(2, 2, 0.4),

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

-- TODO Day 5+: Shop = {...}, RateLimits = {...}, Items = {...}.
-- Te sekcje dochodzą gdy zaczynam ich potrzebować — nie wcześniej.

table.freeze(Config.Game)
table.freeze(Config.Round)
-- Spawn ma Vector3 fields — freeze tylko po:
table.freeze(Config.Spawn)
table.freeze(Config.Lava.Part)
table.freeze(Config.Lava)
table.freeze(Config.Cash.Popup)
table.freeze(Config.Cash)
table.freeze(Config.Bridge)
table.freeze(Config)

return Config
