--!strict
-- LavaService.luau
-- Tworzy Part lawy, reaguje na fazy z GameLoopService, zabija dotknięte postacie.
--
-- Stan startowy: lawa pod ziemią (Config.Lava.StartY), speed = 0.
-- W ROUND: speed czerpany z bieżącej fazy; w pozostałych stanach lawa stoi.

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
		local bp = map:FindFirstChild("Baseplate")
		if bp and bp:IsA("BasePart") then
			return bp.Position.X, bp.Position.Z
		end
	end
	return 0, 0
end

-- Touched odpala się masowo dla każdej postaci stojącej w lawie (lawa rośnie co klatka).
-- Dedup żeby nie próbować zabić humanoida który już jest dying-but-not-yet-dead.
local pendingDeath: { [Humanoid]: boolean } = {}

local function onTouched(otherPart: BasePart)
	local model = otherPart:FindFirstAncestorOfClass("Model")
	if not model then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if pendingDeath[hum] then return end
	pendingDeath[hum] = true

	hum.Health = 0
	-- PlayerDied jest fired przez PlayerService.onDeath (single source) — Humanoid.Died
	-- listener tam łapie i ogarnia aliveSet + remote. Nie fire'ujemy tu drugi raz.
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
		existing.Touched:Connect(onTouched)
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
	part.Touched:Connect(onTouched)
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
	heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
		if not lavaPart then return end
		if currentSpeed <= 0 then return end
		currentY = math.min(currentY + currentSpeed * dt, Config.Lava.MaxY)
		lavaPart.Position = Vector3.new(lavaAnchorX, currentY, lavaAnchorZ)
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
