--!strict
-- LavaSplashController.luau — rozbryzg, dym i krótki błysk, gdy czyjaś postać WPADA do lawy
-- (27.10, tylko GRAPHICS HIGH). Czysto u klienta: wejście wykrywamy z ruchu postaci, którą
-- i tak widzimy (pozycje są replikowane), więc nie ma remote'ów ani pracy serwera. Serwerowy
-- efekt śmierci w lawie (LavaService) jest osobny i zostaje.
--
-- „Wpada” = stopy przechodzą pod widoczną taflę (LavaSurfaceController.surfaceYAt, z falą)
-- z prędkością w dół ≥ `MinFallSpeed`. Lawa podchodząca pod stojącego gracza daje prędkość
-- ~0 → bez efektu. Pierwszy odczyt nowej postaci tylko zapamiętuje stan, więc teleport
-- i respawn nie robią rozbryzgu. Gotowa pula zestawów — nic nie powstaje w trakcie gry.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local SettingsState = require(script.Parent.SettingsState)
local LavaSurfaceController = require(script.Parent.LavaSurfaceController)

local LavaSplashController = {}

local CFG = Config.Lava.Splash
local FX = Config.Lava.FX
local FEET = Config.Lava.FeetOffset

type Rig = {
	anchor: Part, drops: ParticleEmitter, sparks: ParticleEmitter, smoke: ParticleEmitter,
	light: PointLight, flash: number, strength: number,
}
type Track = { y: number, inLava: boolean, lastSplash: number }

local rigs: { Rig } = {}
local nextRig = 1
-- Słabe klucze: model postaci po respawnie / wyjściu znika z tabeli sam.
local tracks: { [Model]: Track } = setmetatable({}, { __mode = "k" }) :: any
local accumulator = 0
local enabled = true
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
	folder.Name = "LavaSplashFX"
	folder.Parent = Workspace
	for i = 1, CFG.Pool do
		-- Lekcja 10: lokalny part bez kolizji, dotyku i promieni.
		local anchor = Instance.new("Part")
		anchor.Name = "Splash" .. i
		anchor.Size = Vector3.one
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Locked = true
		anchor.Transparency = 1
		anchor.Parent = folder

		local drops = emitter("Drops", anchor, FX.SparkTexture)
		drops.Color = ColorSequence.new(FX.HotColor, FX.BubbleColor)
		drops.Size = NumberSequence.new(0.8, 0.15)
		drops.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		drops.Lifetime = NumberRange.new(0.5, 1)
		drops.Speed = NumberRange.new(CFG.DropSpeedMin, CFG.DropSpeedMax)
		drops.SpreadAngle = Vector2.new(50, 50)
		drops.Acceleration = Vector3.new(0, -CFG.DropGravity, 0)
		drops.LightEmission = 0.5

		local sparks = emitter("Sparks", anchor, FX.SparkTexture)
		sparks.Color = ColorSequence.new(FX.HotColor, FX.CoolColor)
		sparks.Size = NumberSequence.new(0.3, 0.04)
		sparks.Transparency = NumberSequence.new(0, 1)
		sparks.Lifetime = NumberRange.new(0.4, 0.8)
		sparks.Speed = NumberRange.new(CFG.DropSpeedMax, CFG.DropSpeedMax * 1.3)
		sparks.SpreadAngle = Vector2.new(70, 70)
		sparks.Acceleration = Vector3.new(0, -CFG.DropGravity * 0.6, 0)
		sparks.LightEmission = 0.8

		local smoke = emitter("Smoke", anchor, FX.SmokeTexture)
		smoke.Color = ColorSequence.new(FX.SmokeColor, FX.SmokeEndColor)
		smoke.Size = NumberSequence.new(3, 9)
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Lifetime = NumberRange.new(0.9, 1.6)
		smoke.Speed = NumberRange.new(6, 12)
		smoke.SpreadAngle = Vector2.new(30, 30)
		smoke.Rotation = NumberRange.new(-180, 180)
		smoke.RotSpeed = NumberRange.new(-25, 25)

		-- Reguła 21.09: Range = przebicie stropu, więc błysk nie mocniej niż jedna kondygnacja.
		local light = Instance.new("PointLight")
		light.Color = FX.LightColor
		light.Range = CFG.FlashRange
		light.Shadows = false
		light.Brightness = 0
		light.Enabled = false
		light.Parent = anchor

		table.insert(rigs, { anchor = anchor, drops = drops, sparks = sparks, smoke = smoke,
			light = light, flash = 0, strength = 0 })
	end
end

local function play(at: Vector3, strength: number)
	local rig = rigs[nextRig]
	if not rig then return end
	nextRig = nextRig % #rigs + 1
	rig.anchor.Position = at + Vector3.new(0, 0.3, 0)
	rig.drops:Emit(math.max(1, math.floor(CFG.DropBurst * strength)))
	rig.sparks:Emit(math.max(1, math.floor(CFG.SparkBurst * strength)))
	rig.smoke:Emit(math.max(1, math.floor(CFG.SmokeBurst * strength)))
	rig.flash = 1
	rig.strength = strength
end

local function update(dt: number)
	-- Błysk gaśnie co klatkę (płynnie); wykrywanie wejść wystarczy `UpdateHz`.
	for _, r in ipairs(rigs) do
		if r.flash > 0 then
			r.flash = math.max(0, r.flash - dt / CFG.FlashTime)
			r.light.Brightness = CFG.FlashBrightness * r.flash * r.strength
			r.light.Enabled = r.flash > 0
		end
	end
	accumulator += dt
	if accumulator < 1 / CFG.UpdateHz then return end
	local elapsed = math.min(accumulator, 0.5)
	accumulator = 0
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local cameraPos = camera.CFrame.Position
	local now = os.clock()
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (char and hrp and hrp:IsA("BasePart")) then continue end
		local pos = hrp.Position
		local surfaceY = LavaSurfaceController.surfaceYAt(pos.X, pos.Z)
		local inLava = surfaceY ~= nil and pos.Y - FEET < surfaceY
		local track = tracks[char]
		if not track then
			tracks[char] = { y = pos.Y, inLava = inLava, lastSplash = -math.huge }
			continue
		end
		-- Prędkość z ruchu między odczytami, nie z fizyki — działa tak samo dla cudzych postaci.
		local fallSpeed = (track.y - pos.Y) / elapsed
		if enabled and surfaceY and inLava and not track.inLava and fallSpeed >= CFG.MinFallSpeed
			and now - track.lastSplash >= CFG.Cooldown and (pos - cameraPos).Magnitude <= CFG.Distance then
			track.lastSplash = now
			local strength = math.clamp(fallSpeed / CFG.FullFallSpeed, CFG.MinStrength, 1)
			play(Vector3.new(pos.X, surfaceY, pos.Z), strength)
		end
		track.y = pos.Y
		track.inLava = inLava
	end
end

local function applyQuality()
	enabled = SettingsState.get("graphics") ~= "low"
end

function LavaSplashController.init()
	if initialized then return end
	initialized = true
	applyQuality()
	SettingsState.onChanged(applyQuality)
	buildRigs()
	RunService.Heartbeat:Connect(update)
end

return LavaSplashController
