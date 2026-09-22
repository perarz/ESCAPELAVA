--!strict
-- LavaService.luau
-- Animuje lawę, reaguje na fazy z GameLoopService, zabija zanurzone postacie.
--
-- Stan startowy: lawa pod ziemią (wysokość z partu Kacpra), speed = 0.
-- W ROUND: speed czerpany z bieżącej fazy; w pozostałych stanach lawa stoi.
--
-- LAWA TO STOS WARSTW (2026-09-16), nie jeden part. `Workspace.Lava` trzyma dowolnie
-- wiele BasePart: nieprzezroczysty spód + półprzezroczyste warstwy nad nim. Powód:
-- GŁĘBIA to jedyna rzecz, której płaskiej tafli nie da się namalować żadną teksturą —
-- cztery podejścia do malowania jej na jednej płaszczyźnie zostały odrzucone (lista
-- przy `LavaSurfaceController`). Rozsunięte w pionie warstwy dają ją naprawdę, razem
-- z paralaksą przy ruchu kamery.
--
-- Kod nie wie, ile warstw jest ani jak wyglądają: bierze wszystkie party z folderu
-- i sortuje po wysokości. Dodanie czwartej warstwy albo usunięcie jednej = zero zmian
-- w kodzie (ten sam wzorzec co `SHOPCAMERA{N}` w sklepie).
--
-- WARSTWA WIERZCHNIA rządzi wszystkim, co gra: próg śmierci, `getSurfaceY()` dla
-- CashPickup/Debris, wysokość startowa rundy. Reszta to oprawa jadąca za nią ze stałym
-- offsetem — i tylko ona ma prawo wyglądać dowolnie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local GameLoopService = require(script.Parent.GameLoopService)
local KillService = require(script.Parent.KillService)

local LavaService = {}

type LavaLayer = {
	part: BasePart,
	anchorX: number,
	anchorZ: number,
	dy: number,        -- stałe przesunięcie Y względem warstwy wierzchniej
	amplitude: number, -- własna amplituda falowania (w głąb słabnie)
	phase: number,     -- przesunięcie fazy: warstwy pływają WZGLĘDEM SIEBIE
}

local layers: { LavaLayer } = {}
local surfaceLayer: LavaLayer? = nil
-- Granice XZ to SUMA warstw, nie obrys wierzchniej: Kacper może dać cieńszą warstwę
-- na wierzchu mniejszą od spodniej, a gracz stojący nad samym spodem i tak WIDZI pod
-- sobą lawę — więc ma ginąć. Party ruszają się tylko w Y, więc liczone raz przy zbiórce.
local boundsMinX, boundsMaxX = 0, 0
local boundsMinZ, boundsMaxZ = 0, 0
local currentSpeed: number = 0
-- Wysokość, z której lawa startuje każdą rundę. Nadpisywana pozycją wierzchniego partu
-- Kacpra w `collectLayers` — Config to tylko fallback dla partu tworzonego z kodu.
local lavaStartY: number = Config.Lava.StartY
local currentY: number = Config.Lava.StartY
local heartbeatConn: RBXScriptConnection? = nil
local initialized = false

local function getLavaFolder(): Folder
	local folder = Workspace:FindFirstChild("Lava")
	if folder and folder:IsA("Folder") then
		return folder
	end
	-- Fallback gdyby project.json kiedyś nie utworzył:
	local f = Instance.new("Folder")
	f.Name = "Lava"
	f.Parent = Workspace
	return f
end

local function getBaseplateCenterXZ(): (number, number)
	local map = Workspace:FindFirstChild("Map")
	if map then
		-- recursive — kontrakt trzyma Baseplate pod Map.Locked (chroniony przed bombą),
		-- płytki lookup nigdy by go nie znalazł.
		local bp = map:FindFirstChild("Baseplate", true)
		if bp and bp:IsA("BasePart") then
			return bp.Position.X, bp.Position.Z
		end
	end
	return 0, 0
end

-- Touched odpala się masowo dla każdej postaci stojącej w lawie (lawa rośnie co klatka).
-- Dedup żeby nie próbować zabić humanoida który już jest dying-but-not-yet-dead.
-- Weak keys — humanoid GC'owany po zniszczeniu character'a (respawn/leave), wpis znika sam.
-- Bez weak keys wpisy akumulowałyby się dożywotnio serwera (memory leak przy skali).
local pendingDeath: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function spawnDeathPoof(position: Vector3)
	-- Syk pary + embery w miejscu śmierci w lawie. Server-side — widzą wszyscy.
	-- Czytelny feedback "ktoś wpadł" nawet z daleka (słupek pary nad lawą).
	local Debris = game:GetService("Debris")
	local anchor = Instance.new("Part")
	anchor.Name = "LavaDeathFX"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	Debris:AddItem(anchor, 2)

	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235), Color3.fromRGB(180, 180, 180))
	steam.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 7),
	})
	steam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	steam.Lifetime = NumberRange.new(0.8, 1.4)
	steam.Rate = 0
	steam.Speed = NumberRange.new(10, 18)
	steam.EmissionDirection = Enum.NormalId.Top
	steam.SpreadAngle = Vector2.new(25, 25)
	steam.Parent = anchor
	steam:Emit(18)

	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 160, 50), Color3.fromRGB(255, 70, 20))
	embers.Size = NumberSequence.new(0.5, 0.1)
	embers.Lifetime = NumberRange.new(0.5, 0.9)
	embers.Rate = 0
	embers.Speed = NumberRange.new(15, 30)
	embers.SpreadAngle = Vector2.new(60, 60)
	embers.Acceleration = Vector3.new(0, -40, 0)
	embers.LightEmission = 1
	embers.Parent = anchor
	embers:Emit(14)
end

-- Odległość od HumanoidRootPart do stóp w R15 — żeby gracz ginął gdy zanurzy się
-- po kostki, a nie dopiero gdy lawa sięgnie mu bioder.
local FEET_OFFSET = 2.5
local KILL_CHECK_HZ = 10

-- Zabijanie przez POZYCJĘ, nie przez Touched.
-- Touched na parcie 361×6×388 poruszającym się co klatkę odpala się dla KAŻDEGO
-- stykającego się obiektu w każdej klatce — a przy destrukcji otoczenia na lawę spadały
-- setki kawałków gruzu. To były tysiące wywołań na sekundę (każde z FindFirstAncestorOfClass)
-- w najgorszym możliwym momencie: gdy na mapie dużo się dzieje. Lawa to płaski
-- prostopadłościan, więc test "czy gracz jest w środku" to kilka porównań na gracza:
-- 20 graczy × 10 Hz = 200 operacji/s zamiast tysięcy eventów. Przy okazji znika stara
-- klasa błędów "Touched nie odpalił bo postać poruszała się za szybko".
-- LAWA RANI, NIE ZABIJA NA MIEJSCU (decyzja Kacpra 2026-09-21).
-- Obrażenia lecą WYŁĄCZNIE dopóki stopy są pod powierzchnią — wyjdziesz, przestaje boleć.
-- Nic się nie goi (`Game.DisableHealthRegen` zdejmuje skrypt `Health` w `PlayerService`),
-- więc kilka krótkich wejść sumuje się do tych samych `SecondsToKill`.
-- ⚠️ Tempo liczone z `MaxHealth`, nie ze sztywnego DPS — „7 sekund" ma znaczyć 7 sekund
-- niezależnie od tego, ile gracz ma maksymalnego życia.
local function damageSubmerged(dt: number)
	local surf = surfaceLayer
	if not surf then return end
	-- Próg czytany Z PARTU, więc faluje razem z nim (patrz `applyPositions`).
	local part = surf.part
	local surfaceY = part.Position.Y + part.Size.Y * 0.5
	local seconds = math.max(Config.Lava.Damage.SecondsToKill, 0.1)

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then continue end

		local pos = hrp.Position
		if pos.Y - FEET_OFFSET > surfaceY then continue end
		if pos.X < boundsMinX or pos.X > boundsMaxX then continue end
		if pos.Z < boundsMinZ or pos.Z > boundsMaxZ then continue end

		-- ⚠️ ODNOWIENIE TAGU PRZED OBRAŻENIAMI, nie po. Śmierć w lawie trwa teraz dłużej
		-- niż okno kredytu (7 s vs 5 s), więc bez tego „zepchnąłem go do lawy" przestałoby
		-- się liczyć. Po `TakeDamage` humanoid bywa już martwy, a wtedy `refreshTag`
		-- wychodzi bez efektu — czyli kolejność jest tu częścią mechaniki, nie stylem.
		KillService.refreshTag(hum)

		hum:TakeDamage(hum.MaxHealth / seconds * dt)

		if hum.Health <= 0 and not pendingDeath[hum] then
			pendingDeath[hum] = true
			spawnDeathPoof(pos)
			-- PlayerDied leci z PlayerService.onDeath (single source) — nie dublujemy.
		end
	end
end

local function attachLavaVFX(part: BasePart)
	-- Żywa lawa: embery unoszące się z powierzchni + ciężki dym. Emitter na parcie
	-- emituje z górnej ściany (EmissionDirection=Top). Rate stały — koszt pomijalny,
	-- particle renderują się tylko u klientów którzy patrzą.
	if part:FindFirstChild("LavaEmbers") then return end

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "LavaEmbers"
	-- Startuje WYŁĄCZONY: dopóki lawa siedzi w kanale, particle przelatywałyby przez
	-- jezdnię (nie kolidują z geometrią) i wynurzały się nad ulicą. Włącza `refreshSurfaceFX`.
	embers.Enabled = false
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 80, 20))
	embers.Size = NumberSequence.new(0.6, 0.15)
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(1.2, 2.2)
	embers.Rate = 90
	embers.Speed = NumberRange.new(8, 16)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.SpreadAngle = Vector2.new(12, 12)
	embers.LightEmission = 1
	embers.Parent = part

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "LavaSmoke"
	smoke.Enabled = false
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 50, 40), Color3.fromRGB(50, 40, 40))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 5),
		NumberSequenceKeypoint.new(1, 11),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(2.5, 4)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(3, 6)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.SpreadAngle = Vector2.new(8, 8)
	smoke.Parent = part
end

-- Właściwości, które kod wymusza na KAŻDEJ warstwie — niezależnie od tego, co Kacper
-- ustawił w Studio. To nie jest wygląd (wygląd jest jego), tylko zachowanie:
local function forceLavaProperties(part: BasePart)
	part.Anchored = true
	-- CanCollide=false: lawa NIE pcha rozjebanych klocków w górę razem z rosnącym Y.
	-- Wcześniej parts spadające na lawę osiadały na niej i jechały do MaxY — gracze
	-- mogli wskoczyć na takiego "winda-klocka" i wygrywać za darmo.
	part.CanCollide = false
	-- Locked=true: bez tego DestructionService potraktuje warstwę jak zwykłą ścianę
	-- i pierwsza bomba przy brzegu potnie ją na gruz.
	part.Locked = true
	-- CastShadow: ogromna ruchoma powierzchnia = engine liczy shadow propagation 60Hz.
	part.CastShadow = false
	-- CanQuery=false: lawa nie jest celem raycastów (para w LavaSurfaceController
	-- musi widzieć mapę POD lawą, nie samą lawę).
	part.CanQuery = false
	-- CanTouch=false: ranimy przez pozycję (damageSubmerged), więc eventy Touched są
	-- czystym kosztem — a przy gruzie z wybuchów byłyby ich tysiące na sekundę.
	part.CanTouch = false
end

local function topFaceY(part: BasePart): number
	return part.Position.Y + part.Size.Y * 0.5
end

-- Fallback gdy folder jest pusty (świeże miejsce, ktoś skasował party). Jedyna sytuacja,
-- w której kod tworzy wygląd lawy sam — i dlatego jest brzydki z założenia: ma krzyczeć
-- "postaw swój part", a nie udawać docelową oprawę.
local function createFallbackPart(folder: Folder): BasePart
	local cx, cz = getBaseplateCenterXZ()
	local part = Instance.new("Part")
	part.Name = "LavaPart"
	part.Size = Vector3.new(
		Config.Lava.Part.SizeXZ,
		Config.Lava.Part.Thickness,
		Config.Lava.Part.SizeXZ
	)
	part.Color = Config.Lava.Part.Color
	part.Material = Config.Lava.Part.Material
	part.Transparency = Config.Lava.Part.Transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Position = Vector3.new(cx, Config.Lava.StartY, cz)
	part.Parent = folder
	warn("[Lava] brak partów w Workspace.Lava — stworzono awaryjny LavaPart z Config. Postaw własne warstwy w Studio.")
	return part
end

-- Falowanie z przesuniętą fazą ma sens tylko dopóki warstwy się nie PRZETNĄ: dwie tafle
-- wchodzące w siebie dają migotanie (z-fighting) zamiast głębi, czyli dokładną odwrotność
-- tego, po co ten stos powstał. Zamiast kazać Kacprowi liczyć odstępy w Studio, kod sam
-- przycina amplitudy do najciaśniejszej szczeliny — warstwy można dosunąć na 0.2 studa
-- i nadal nic nie miga, po prostu falowanie robi się subtelniejsze.
local function clampWobbleAmplitudes()
	local cfg = Config.Lava.Wobble
	local scale = 1
	for i = 1, #layers - 1 do
		local upper, lower = layers[i], layers[i + 1]
		local gap = (upper.dy - upper.part.Size.Y * 0.5) - (lower.dy + lower.part.Size.Y * 0.5)
		local travel = upper.amplitude + lower.amplitude
		if travel <= 0 then continue end
		if gap <= 0 then
			warn(("[Lava] warstwy '%s' i '%s' zachodzą na siebie (szczelina %.2f studa) — falowanie wyłączone. Rozsuń je w Studio."):format(
				upper.part.Name, lower.part.Name, gap))
			scale = 0
			break
		end
		scale = math.min(scale, gap * cfg.MaxGapUsage / travel)
	end
	if scale >= 1 then return end
	for _, layer in ipairs(layers) do
		layer.amplitude *= scale
	end
end

-- Zbiera stos warstw z `Workspace.Lava`. Wołane na init i ponownie, gdy warstwa zniknie
-- w trakcie Play (Kacper stroi wygląd na żywo).
local function collectLayers()
	local folder = getLavaFolder()

	local parts: { BasePart } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	if #parts == 0 then
		table.insert(parts, createFallbackPart(folder))
	end

	-- Sortowanie po GÓRNEJ ŚCIANIE, nie po środku partu: warstwy mają różne grubości
	-- (cienka skorupa na wierzchu, gruba masa pod spodem), więc środek kłamie o tym,
	-- która z nich jest widoczną powierzchnią.
	table.sort(parts, function(a, b)
		return topFaceY(a) > topFaceY(b)
	end)

	local cfg = Config.Lava.Wobble
	local top = parts[1]
	table.clear(layers)
	boundsMinX, boundsMaxX = math.huge, -math.huge
	boundsMinZ, boundsMaxZ = math.huge, -math.huge

	for index, part in ipairs(parts) do
		forceLavaProperties(part)
		table.insert(layers, {
			part = part,
			anchorX = part.Position.X,
			anchorZ = part.Position.Z,
			dy = part.Position.Y - top.Position.Y,
			-- Amplituda RÓŻNICOWA (ruch względem sąsiednich warstw). Wspólne falowanie
			-- całego stosu jest osobno w `applyPositions` i nie podlega przycinaniu.
			amplitude = cfg.LayerAmplitude * (cfg.LayerDecay ^ (index - 1)),
			phase = (index - 1) * cfg.LayerPhase,
		})
		boundsMinX = math.min(boundsMinX, part.Position.X - part.Size.X * 0.5)
		boundsMaxX = math.max(boundsMaxX, part.Position.X + part.Size.X * 0.5)
		boundsMinZ = math.min(boundsMinZ, part.Position.Z - part.Size.Z * 0.5)
		boundsMaxZ = math.max(boundsMaxZ, part.Position.Z + part.Size.Z * 0.5)
	end

	surfaceLayer = layers[1]
	clampWobbleAmplitudes()

	-- Wysokość startowa Z PARTU Kacpra (2026-09-14). Kod respektuje jego X/Z, kolor,
	-- materiał i rozmiar — a Y kiedyś nadpisywał `Config.Lava.StartY`, więc lawa
	-- postawiona świadomie pod poziomem ulic podskakiwała przy starcie serwera.
	-- Liczona z WIERZCHNIEJ warstwy, bo to ona jest powierzchnią, którą widać.
	lavaStartY = top.Position.Y

	-- VFX (embery, dym) tylko na wierzchniej warstwie: mają unosić się Z POWIERZCHNI,
	-- a nie ze środka stosu — plus trzy emittery to trzy razy więcej particli za nic.
	attachLavaVFX(top)
end

local TAU = math.pi * 2

-- ============================================================================
-- OPRAWA LAWY: JEDNA BRAMKA — WYSOKOŚĆ TAFLI (2026-09-21, decyzja Kacpra)
-- ============================================================================
-- Dopóki lawa siedzi w kanale pod ulicami, jej oprawa jest WYŁĄCZONA w całości.
-- Tu gasimy embery i dym; bąble, para, światła i poświata gasną po stronie klienta
-- (`LavaSurfaceController`) na podstawie TEJ SAMEJ liczby z `Config.Lava.FX.MinSurfaceY`,
-- więc nie ma czego replikować ani synchronizować.
--
-- ⚠️ DLACZEGO PRÓG WYSOKOŚCI, A NIE RAYCASTY: particle w Robloxie **nie kolidują
-- z geometrią** — ember wypuszczony z tafli na Y 2.5 przelatuje przez jezdnię na Y 9
-- i wynurza się nad ulicą. Żadna bramka „czy nad tym punktem coś jest" tego nie naprawi,
-- bo problem nie jest w miejscu emisji, tylko w torze lotu. Do tego raycast, który w nic
-- nie trafił, przy `StreamingEnabled` znaczy „jeszcze się nie wczytało" i przez pierwsze
-- ~15 s po wejściu kłamie. Porównanie dwóch liczb nie ma jak się pomylić.
local fxAllowed = false

local function refreshSurfaceFX()
	local y = LavaService.getSurfaceY()
	local fx = Config.Lava.FX
	local h = fx.MinSurfaceHysteresis or 0
	-- HISTEREZA: tafla faluje, więc goły próg przełączałby się kilka razy na sekundę,
	-- gdy średni poziom stoi blisko niego. Między progami trzymamy poprzedni stan.
	local allowed = fxAllowed
	if y >= fx.MinSurfaceY + h then
		allowed = true
	elseif y <= fx.MinSurfaceY - h then
		allowed = false
	end
	if allowed == fxAllowed then return end
	fxAllowed = allowed
	for _, layer in ipairs(layers) do
		local part = layer.part
		if not part.Parent then continue end
		for _, name in ipairs({ "LavaEmbers", "LavaSmoke" }) do
			local emitter = part:FindFirstChild(name)
			if emitter and emitter:IsA("ParticleEmitter") then
				emitter.Enabled = allowed
			end
		end
	end
	print(("[Lava] oprawa %s (wierzch tafli Y=%.1f, próg %.1f ±%.1f)"):format(
		if allowed then "WŁĄCZONA" else "wyłączona", y, fx.MinSurfaceY, h))
end

-- JEDYNE miejsce zapisujące pozycje warstw. Wzrost aktualizuje tylko `currentY`.
-- Dwie pętle zapisujące `Position` co klatkę biłyby się o nią zależnie od kolejności
-- podpięcia — dokładnie ten rodzaj niejawnej zależności, który wraca po miesiącu jako
-- "czasem lawa drga".
local function applyPositions(wobbleClock: number?)
	local cfg = Config.Lava.Wobble

	-- Składnik WSPÓLNY: cały stos podnosi się i opada razem, więc odstępy między
	-- warstwami się nie zmieniają i amplituda może być duża bez ryzyka przecięcia.
	-- To on odpowiada za "widać, że lawa faluje".
	local common = 0
	if wobbleClock and cfg.Amplitude > 0 and cfg.Period > 0 then
		common = math.sin(wobbleClock * TAU / cfg.Period) * cfg.Amplitude
	end

	for _, layer in ipairs(layers) do
		local part = layer.part
		if not part.Parent then continue end

		-- Składnik RÓŻNICOWY: warstwy pływają względem siebie. Osobny, szybszy okres,
		-- żeby suma nie wyglądała jak jedna równa sinusoida.
		local diff = 0
		if wobbleClock and layer.amplitude > 0 and cfg.LayerPeriod > 0 then
			diff = math.sin(wobbleClock * TAU / cfg.LayerPeriod + layer.phase) * layer.amplitude
		end

		part.Position = Vector3.new(layer.anchorX, currentY + layer.dy + common + diff, layer.anchorZ)
	end
end

local function reset()
	currentSpeed = 0
	currentY = lavaStartY
	applyPositions(nil)
	-- Nowa runda zaczyna od tafli w kanale, więc oprawa MUSI zgasnąć razem z nią.
	refreshSurfaceFX()
end

local function startGrowth()
	if heartbeatConn then return end
	local killAccumulator = 0
	local killInterval = 1 / KILL_CHECK_HZ
	heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		if not surfaceLayer then return end

		-- Wzrost tylko gdy faza ma prędkość (faza Spawn ma 0), ale sprawdzanie ofiar
		-- MUSI lecieć zawsze — inaczej gracz który sam wskoczy w stojącą lawę w fazie
		-- Spawn przeżyje, a przy Touched ginął.
		-- Sam STAN wysokości; pozycje warstw zapisuje wyłącznie `applyPositions`,
		-- żeby wzrost i falowanie nie biły się o tę samą właściwość co klatkę.
		if currentSpeed > 0 then
			currentY = math.min(currentY + currentSpeed * dt, Config.Lava.MaxY)
		end

		killAccumulator += dt
		if killAccumulator >= killInterval then
			-- Realny czas, nie nominalny interwał: przy spadku FPS akumulator bywa większy,
			-- a obrażenia mają lecieć w tempie zegara, nie klatek.
			local elapsed = killAccumulator
			killAccumulator = 0
			damageSubmerged(elapsed)
			-- Piggyback na 10 Hz: sama funkcja i tak wychodzi od razu, gdy nic się nie zmieniło.
			refreshSurfaceFX()
		end
	end)
end

local function stopGrowth()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

-- Wysokość POWIERZCHNI lawy (góra parta). Single source of truth dla wszystkich,
-- którzy pytają "czy to już pod lawą": CashPickupService (kasowanie zalanego cashu),
-- DebrisService (kasowanie zatopionego gruzu). Czytane wprost z parta, bo LavaService
-- animuje go co klatkę — wartość jest zawsze świeża, także gdy Config.Lava.Enabled=false.
function LavaService.getSurfaceY(): number
	local surf = surfaceLayer
	if not surf or not surf.part.Parent then
		-- Warstwa zniknęła (Kacper skasował part w trakcie Play) — zbierz stos od nowa,
		-- zamiast podawać CashPickup/Debris wysokość, której już nic nie odpowiada.
		collectLayers()
		surf = surfaceLayer
	end
	if surf and surf.part.Parent then
		return surf.part.Position.Y + surf.part.Size.Y * 0.5
	end
	return Config.Lava.StartY
end

-- Falowanie musi iść przez SERWER: party są serwerowe, więc klienckie ruszanie Y
-- zostałoby nadpisane przez replikację w następnej klatce.
-- Świadomie podpięte PRZED sprawdzeniem `Config.Lava.Enabled` — to czysty kosmetyk,
-- a przy wyłączonej lawie (tryb testów destrukcji) i tak chcemy ją widzieć żywą.
-- ⚠️ Próg obrażeń (`damageSubmerged`) czyta pozycję wierzchniej warstwy, więc faluje
-- razem z nią. Przy 0.3 studa jest to pomijalne, ale nie podnosić bez zastanowienia.
local function startPositionLoop()
	local cfg = Config.Lava.Wobble
	RunService.Heartbeat:Connect(function()
		if #layers == 0 then return end
		applyPositions(if cfg.Enabled then os.clock() else nil)
	end)
end

function LavaService.init()
	if initialized then return end
	initialized = true

	collectLayers()
	reset()
	startPositionLoop()

	-- Tryb testów destrukcji: part istnieje (inne services go czytają), ale lawa nie
	-- rośnie i nie zabija. Głośny warn co boot, żeby flaga nie przeżyła do produkcji.
	if not Config.Lava.Enabled then
		warn("[Lava] WYŁĄCZONA (Config.Lava.Enabled=false) — tryb testów destrukcji. PRZYWRÓĆ przed testem rund/launchem!")
		return
	end

	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState == GameLoopService.STATE.ROUND then
			startGrowth()
		elseif newState == GameLoopService.STATE.LOBBY
			or newState == GameLoopService.STATE.COUNTDOWN
			or newState == GameLoopService.STATE.POST_ROUND then
			stopGrowth()
			reset()
		end
	end)

	GameLoopService.PhaseChanged:Connect(function(_name: string, index: number, _duration: number)
		local phase = Config.Lava.Phases[index]
		if phase then
			currentSpeed = phase.Speed
		end
	end)
end

return LavaService
