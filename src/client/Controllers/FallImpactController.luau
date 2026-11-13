--!strict
-- FallImpactController.luau — efekt lądowania z obrażeniami od upadku (12.11, decyzje Kacpra:
-- świat + ekran, świat widzą wszyscy, siła skalowana obrażeniami).
--
-- Serwer (FallDamageService) wysyła `FallImpact` tylko przy upadku, który zranił:
--   • u każdego w pobliżu: płaski pierścień kurzu w kolorze podłogi, odłamki i fala na ziemi,
--   • u poszkodowanego dodatkowo: czerwone krawędzie ekranu (`StarterGui.FallVignette`, układ
--     jak EnergyVignette). Wstrząs ekranu i FOV zostają na `BombHit`, jak dotąd.
-- Bez GUI w placu ekran nic nie robi (UI nie budujemy w kodzie). Pula zestawów gotowa od
-- startu — nic nie powstaje w trakcie gry. Lekcja 10: lokalne party bez kolizji i promieni.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local SettingsState = require(script.Parent.SettingsState)

local FallImpactController = {}

local CFG = Config.FallDamage.Impact
local VIG = CFG.Vignette
local SMOKE_TEXTURE = Config.Lava.FX.SmokeTexture
local CHUNK_TEXTURE = "rbxasset://textures/particles/SquareParticle.png"
local RING_TEXTURE = "rbxasset://textures/particles/explosion01_shockwave_main.dds"

type Rig = { anchor: Part, dust: { ParticleEmitter }, chunks: ParticleEmitter, ring: ParticleEmitter }

local localPlayer = Players.LocalPlayer
local rigs: { Rig } = {}
local nextRig = 1
local low = false
local initialized = false

local function emitter(name: string, parent: Instance, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Enabled = false
	e.Rate = 0
	e.LockedToPart = false
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
	return e
end

local function buildRigs()
	local folder = Instance.new("Folder")
	folder.Name = "FallImpactFX"
	folder.Parent = Workspace
	for i = 1, CFG.Pool do
		local anchor = Instance.new("Part")
		anchor.Name = "Impact" .. i
		anchor.Size = Vector3.one
		anchor.Anchored = true
		anchor.CanCollide = false -- przed CanQuery (CanQuery=false działa tylko bez kolizji)
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Locked = true
		anchor.Transparency = 1
		anchor.Parent = folder

		-- Kurz: po emiterze na kierunek, Attachment obrócony w poziomie (Front = na zewnątrz),
		-- lekko w górę, żeby kłęby sunęły PO ziemi, a nie w niej.
		local dust: { ParticleEmitter } = {}
		for d = 1, CFG.DustDirections do
			local att = Instance.new("Attachment")
			att.Name = "Dust" .. d
			att.CFrame = CFrame.Angles(0, 2 * math.pi * d / CFG.DustDirections, 0) * CFrame.Angles(math.rad(6), 0, 0)
			att.Parent = anchor
			local e = emitter("Dust", att, SMOKE_TEXTURE)
			e.EmissionDirection = Enum.NormalId.Front
			e.Size = NumberSequence.new(CFG.DustSizeStart, CFG.DustSizeEnd)
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.5, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Lifetime = NumberRange.new(CFG.DustLifetime * 0.75, CFG.DustLifetime)
			e.Speed = NumberRange.new(CFG.DustSpeed * 0.7, CFG.DustSpeed)
			e.SpreadAngle = Vector2.new(12, 6)
			e.Drag = CFG.DustDrag
			e.Rotation = NumberRange.new(-180, 180)
			e.RotSpeed = NumberRange.new(-30, 30)
			table.insert(dust, e)
		end

		local chunks = emitter("Chunks", anchor, CHUNK_TEXTURE)
		chunks.Size = NumberSequence.new(CFG.ChunkSize)
		chunks.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		chunks.Lifetime = NumberRange.new(CFG.ChunkLifetime * 0.8, CFG.ChunkLifetime)
		chunks.Speed = NumberRange.new(CFG.ChunkSpeedMin, CFG.ChunkSpeedMax)
		chunks.SpreadAngle = Vector2.new(55, 55)
		chunks.Acceleration = Vector3.new(0, -CFG.ChunkGravity, 0)
		chunks.Rotation = NumberRange.new(-180, 180)
		chunks.RotSpeed = NumberRange.new(-400, 400)

		-- Fala: jedna cząsteczka leżąca płasko (VelocityPerpendicular przy prędkości w górę),
		-- rośnie i gaśnie. Rozmiar ustawiany przy odpaleniu, bo zależy od siły.
		local ring = emitter("Ring", anchor, RING_TEXTURE)
		ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		ring.Speed = NumberRange.new(0.01)
		ring.Lifetime = NumberRange.new(CFG.RingTime)
		ring.Color = ColorSequence.new(CFG.RingColor)
		ring.Transparency = NumberSequence.new(0.35, 1)
		ring.LightEmission = 0.3

		table.insert(rigs, { anchor = anchor, dust = dust, chunks = chunks, ring = ring })
	end
end

-- Kolor podłogi pod miejscem lądowania (z pominięciem postaci i lokalnych efektów).
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function floorColor(at: Vector3): Color3
	local ignore: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -5, 0), rayParams)
	local base = if hit and hit.Instance:IsA("BasePart") then hit.Instance.Color else CFG.DustColor
	return base:Lerp(CFG.DustColor, CFG.DustGrayMix)
end

local function playWorld(at: Vector3, strength: number)
	local rig = rigs[nextRig]
	if not rig then return end
	nextRig = nextRig % #rigs + 1
	rig.anchor.Position = at + Vector3.new(0, 0.4, 0)
	local burst = if low then CFG.LowBurstScale else 1
	local color = floorColor(at)
	local dark = color:Lerp(Color3.new(0, 0, 0), CFG.ChunkDarken)

	local perDirection = math.max(1, math.floor(CFG.DustPerDirection * strength * burst + 0.5))
	local dustSeq = ColorSequence.new(color)
	for _, e in ipairs(rig.dust) do
		e.Color = dustSeq
		e:Emit(perDirection)
	end
	rig.chunks.Color = ColorSequence.new(dark, color)
	rig.chunks:Emit(math.max(2, math.floor(CFG.ChunkBurst * strength * burst)))
	if low then return end
	local size = CFG.RingSize * strength
	rig.ring.Size = NumberSequence.new(size * 0.25, size)
	rig.ring:Emit(1)
end

-- ============================================================================
-- Ekran poszkodowanego
-- ============================================================================

local vignetteGui: ScreenGui? = nil
local vignetteEdges: { GuiObject } = {}
local vignettePeak = 0   -- krycie przy błysku (0..1)
local vignetteAge = math.huge
local vignetteConn: RBXScriptConnection? = nil

local function findVignette(): ScreenGui?
	if vignetteGui and vignetteGui.Parent then return vignetteGui end
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	local gui = pg and pg:FindFirstChild(VIG.GuiName)
	if not (gui and gui:IsA("ScreenGui")) then return nil end
	table.clear(vignetteEdges)
	local holder = gui:FindFirstChild("Edges")
	for _, e in ipairs(if holder then holder:GetChildren() else {}) do
		if e:IsA("GuiObject") then
			e.BackgroundColor3 = VIG.Color
			table.insert(vignetteEdges, e)
		end
	end
	vignetteGui = gui
	return gui
end

local function stepVignette(dt: number)
	vignetteAge += dt
	local gui = findVignette()
	local alpha = 0
	if vignetteAge <= VIG.Hold then
		alpha = vignettePeak
	else
		local k = 1 - (vignetteAge - VIG.Hold) / math.max(VIG.Fade, 1e-3)
		alpha = vignettePeak * math.max(0, k) ^ 2
	end
	if gui then
		gui.Enabled = alpha > 0
		for _, e in ipairs(vignetteEdges) do
			e.BackgroundTransparency = 1 - alpha
		end
	end
	if alpha <= 0 and vignetteConn then
		vignetteConn:Disconnect()
		vignetteConn = nil
	end
end

local function playScreen(strength: number)
	if not findVignette() then return end
	-- Drugi upadek w trakcie gaśnięcia nie przygasza mocniejszego błysku.
	local current = if vignetteAge <= VIG.Hold then vignettePeak else 0
	vignettePeak = math.max(current, VIG.Peak * strength)
	vignetteAge = 0
	if not vignetteConn then
		vignetteConn = RunService.RenderStepped:Connect(stepVignette)
	end
end

-- ============================================================================

local function onImpact(player: Player, damage: number, ground: Vector3)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if type(damage) ~= "number" or typeof(ground) ~= "Vector3" then return end
	local strength = CFG.MinStrength + (1 - CFG.MinStrength) * math.clamp(damage, 0, 1)
	if player == localPlayer then
		playScreen(strength)
	end
	local camera = Workspace.CurrentCamera
	if camera and (ground - camera.CFrame.Position).Magnitude <= CFG.Distance then
		playWorld(ground, strength)
	end
end

local function applyQuality()
	low = SettingsState.get("graphics") == "low"
end

function FallImpactController.init()
	if initialized then return end
	initialized = true
	-- Listener przed czymkolwiek, co może yieldować (hard rule 9).
	Remotes.FallImpact.OnClientEvent:Connect(onImpact)
	applyQuality()
	SettingsState.onChanged(applyQuality)
	buildRigs()
end

return FallImpactController
