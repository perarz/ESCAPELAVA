--!strict
-- LavaService.luau
-- Tworzy Part lawy, reaguje na fazy z GameLoopService, zabija dotknięte postacie.
--
-- Stan startowy: lawa pod ziemią (Config.Lava.StartY), speed = 0.
-- W ROUND: speed czerpany z bieżącej fazy; w pozostałych stanach lawa stoi.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local GameLoopService = require(script.Parent.GameLoopService)

local LavaService = {}

local lavaPart: Part? = nil
local lavaAnchorX: number = 0
local lavaAnchorZ: number = 0
local currentSpeed: number = 0
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
local function killSubmerged(part: BasePart)
	local center = part.Position
	local surfaceY = center.Y + part.Size.Y * 0.5
	local halfX = part.Size.X * 0.5
	local halfZ = part.Size.Z * 0.5

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		if pendingDeath[hum] then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then continue end

		local pos = hrp.Position
		if pos.Y - FEET_OFFSET > surfaceY then continue end
		if math.abs(pos.X - center.X) > halfX then continue end
		if math.abs(pos.Z - center.Z) > halfZ then continue end

		pendingDeath[hum] = true
		spawnDeathPoof(pos)
		hum.Health = 0
		-- PlayerDied jest fired przez PlayerService.onDeath (single source) — Humanoid.Died
		-- listener tam łapie i ogarnia aliveSet + remote. Nie fire'ujemy tu drugi raz.
	end
end

local function attachLavaVFX(part: BasePart)
	-- Żywa lawa: embery unoszące się z powierzchni + ciężki dym. Emitter na parcie
	-- emituje z górnej ściany (EmissionDirection=Top). Rate stały — koszt pomijalny,
	-- particle renderują się tylko u klientów którzy patrzą.
	if part:FindFirstChild("LavaEmbers") then return end

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "LavaEmbers"
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

local function createLavaPart()
	if lavaPart then return end

	local folder = getLavaFolder()

	-- Preferuj istniejący LavaPart (Kacper mógł go postawić w Studio) — kod tylko animuje Y.
	local existing = folder:FindFirstChild("LavaPart")
	if existing and existing:IsA("BasePart") then
		lavaPart = existing
		lavaAnchorX = existing.Position.X
		lavaAnchorZ = existing.Position.Z
		existing.Anchored = true
		-- CanCollide=false: lawa NIE pcha rozjebanych klocków w górę razem z rosnącym Y.
		-- Wcześniej parts spadające na lawę osiadały na niej i jechały do MaxY — gracze
		-- mogli wskoczyć na takiego "winda-klocka" i wygrywać za darmo. Touched eventy
		-- nadal latają (CanTouch domyślnie true).
		existing.CanCollide = false
		-- Performance + fix flickeru Neon: CastShadow=true na ogromnym Neon parcie ruchomym
		-- co klatka = engine liczy shadow propagation 60Hz dla 361×6×388 powierzchni.
		-- CanQuery=false bo lawa nie jest celem raycast — tylko Touched potrzebuje CanTouch=true.
		existing.CastShadow = false
		existing.CanQuery = false
		-- CanTouch=false: zabijamy przez pozycję (killSubmerged), więc eventy Touched są
		-- czystym kosztem — a przy gruzie z wybuchów byłyby ich tysiące na sekundę.
		existing.CanTouch = false
		attachLavaVFX(existing)
		return
	end

	-- Brak partu → tworzymy z Config, X/Z na środku Baseplate (jeśli istnieje).
	local cx, cz = getBaseplateCenterXZ()
	lavaAnchorX, lavaAnchorZ = cx, cz

	local part = Instance.new("Part")
	part.Name = "LavaPart"
	part.Anchored = true
	-- CanCollide=false: lawa zabija przez Touched (CanTouch=true), ale NIE działa jako
	-- platforma — rozjebane parts nie jeżdżą w górę z lawą, gracze nie mogą wskoczyć
	-- na "windę-klocek".
	part.CanCollide = false
	part.Locked = true
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

	part.CastShadow = false
	part.CanQuery = false
	part.CanTouch = false  -- patrz killSubmerged — zabijanie idzie przez pozycję
	attachLavaVFX(part)
	lavaPart = part
end

local function reset()
	currentSpeed = 0
	currentY = Config.Lava.StartY
	if lavaPart then
		lavaPart.Position = Vector3.new(lavaAnchorX, currentY, lavaAnchorZ)
	end
end

local function startGrowth()
	if heartbeatConn then return end
	local killAccumulator = 0
	local killInterval = 1 / KILL_CHECK_HZ
	heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		local part = lavaPart
		if not part then return end

		-- Wzrost tylko gdy faza ma prędkość (faza Spawn ma 0), ale sprawdzanie ofiar
		-- MUSI lecieć zawsze — inaczej gracz który sam wskoczy w stojącą lawę w fazie
		-- Spawn przeżyje, a przy Touched ginął.
		if currentSpeed > 0 then
			currentY = math.min(currentY + currentSpeed * dt, Config.Lava.MaxY)
			part.Position = Vector3.new(lavaAnchorX, currentY, lavaAnchorZ)
		end

		killAccumulator += dt
		if killAccumulator >= killInterval then
			killAccumulator = 0
			killSubmerged(part)
		end
	end)
end

local function stopGrowth()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

function LavaService.init()
	if initialized then return end
	initialized = true

	createLavaPart()
	reset()

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
