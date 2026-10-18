--!strict
-- Local ambient lava VFX. Fixed pool: no allocations or raycasts during cycles.
-- Server owns height/damage; LavaSwimController owns the submerged view.
-- Height hysteresis intentionally replaces exposure raycasts (streaming ambiguity).
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Modules.Config)
local FX = Config.Lava.FX
local SURF = Config.Lava.Surface
local Controller = {}
local LavaWaveMesh = require(script.Parent.LavaWaveMesh)
local wave = nil
local rng = Random.new()

type Vent = {
	anchor: Part, bubble: Part,
	embers: ParticleEmitter, smoke: ParticleEmitter,
	sparks: ParticleEmitter, drops: ParticleEmitter,
	light: PointLight?, age: number, duration: number,
	x: number, z: number, size: number, popped: boolean, active: boolean,
}
type Layer = { texture: Texture, u: number, v: number, alpha: number, amount: number, period: number }
local vents: { Vent } = {}
local layers: { Layer } = {}
local surface: BasePart? = nil
local lavaFolder: Instance? = nil
local effects: Folder? = nil
local childConnections: { RBXScriptConnection } = {}
local initialized = false
local heightAllowed = false
local running = false
local accumulator = 0
local minX, maxX, minZ, maxZ = 0, 0, 0, 0

local function cosmeticPart(name: string, folder: Folder): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Locked = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	part.Parent = folder
	return part
end

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

local function buildPool()
	local folder = Instance.new("Folder")
	folder.Name = "LavaFX"
	folder.Parent = Workspace
	effects = folder
	for i = 1, FX.VentCount do
		local anchor = cosmeticPart("Vent" .. i, folder)
		local bubble = cosmeticPart("CrustBubble" .. i, folder)
		bubble.Shape = Enum.PartType.Ball
		bubble.Material = Enum.Material.Neon
		bubble.Color = FX.BubbleColor
		local embers = emitter("Embers", anchor, FX.SparkTexture)
		embers.Color = ColorSequence.new(FX.HotColor, FX.CoolColor)
		embers.Size = NumberSequence.new(0.18, 0.04)
		embers.Transparency = NumberSequence.new(0.2, 1)
		embers.Lifetime = NumberRange.new(FX.EmberLifeMin, FX.EmberLifeMax)
		embers.Speed = NumberRange.new(FX.EmberSpeedMin, FX.EmberSpeedMax)
		embers.SpreadAngle = Vector2.new(25, 25)
		embers.LightEmission = 0.7
		embers.Rate = FX.EmberRate
		local smoke = emitter("Smoke", anchor, FX.SmokeTexture)
		smoke.Color = ColorSequence.new(FX.SmokeColor, FX.SmokeEndColor)
		smoke.Size = NumberSequence.new(FX.SmokeSizeMin, FX.SmokeSizeMax)
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Lifetime = NumberRange.new(FX.SmokeLifeMin, FX.SmokeLifeMax)
		smoke.Speed = NumberRange.new(FX.SmokeSpeedMin, FX.SmokeSpeedMax)
		smoke.SpreadAngle = Vector2.new(28, 28)
		smoke.Rotation = NumberRange.new(-180, 180)
		smoke.RotSpeed = NumberRange.new(-18, 18)
		smoke.Rate = FX.SmokeRate
		local sparks = emitter("PopSparks", anchor, FX.SparkTexture)
		sparks.Color = ColorSequence.new(FX.HotColor, FX.CoolColor)
		sparks.Size = NumberSequence.new(0.3, 0.04)
		sparks.Transparency = NumberSequence.new(0, 1)
		sparks.Lifetime = NumberRange.new(FX.DropLifeMin, FX.DropLifeMax)
		sparks.Speed = NumberRange.new(FX.DropSpeedMin, FX.DropSpeedMax)
		sparks.SpreadAngle = Vector2.new(65, 65)
		sparks.Acceleration = Vector3.new(0, -FX.DropGravity, 0)
		sparks.LightEmission = 0.8
		local drops = emitter("MoltenDrops", anchor, FX.SparkTexture)
		drops.Color = ColorSequence.new(FX.HotColor, FX.BubbleColor)
		drops.Size = NumberSequence.new(0.65, 0.12)
		drops.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.65, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		drops.Lifetime = NumberRange.new(FX.DropLifeMin, FX.DropLifeMax)
		drops.Speed = NumberRange.new(FX.DropSpeedMin, FX.DropSpeedMax)
		drops.SpreadAngle = Vector2.new(40, 40)
		drops.Acceleration = Vector3.new(0, -FX.DropGravity, 0)
		drops.LightEmission = 0.5
		local light: PointLight? = nil
		if i <= FX.LightCount then
			local attachment = Instance.new("Attachment")
			attachment.Position = Vector3.new(0, FX.LightHeight, 0)
			attachment.Parent = anchor
			light = Instance.new("PointLight")
			light.Color = FX.LightColor
			light.Range = FX.LightRange
			light.Shadows = false
			light.Brightness = 0
			light.Parent = attachment
		end
		table.insert(vents, {anchor=anchor, bubble=bubble, embers=embers, smoke=smoke,
			sparks=sparks, drops=drops, light=light, age=0, duration=1,
			x=0, z=0, size=1, popped=false, active=false})
	end
end

local function stopVent(v: Vent)
	v.active = false
	v.bubble.Transparency = 1
	v.embers.Enabled = false
	v.smoke.Enabled = false
	v.embers:Clear()
	v.smoke:Clear()
	v.sparks:Clear()
	v.drops:Clear()
	if v.light then v.light.Brightness = 0 end
end

local function stopPool()
	for _, v in ipairs(vents) do stopVent(v) end
	running = false
end

local function beginCycle(v: Vent, cameraPos: Vector3, delay: number)
	-- Relocate only after particles and light have faded. Bubbles are visual only.
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(rng:NextNumber(FX.VentMinRadius ^ 2, FX.VentSpread ^ 2))
	v.x = math.clamp(cameraPos.X + math.cos(angle) * radius, minX, maxX)
	v.z = math.clamp(cameraPos.Z + math.sin(angle) * radius, minZ, maxZ)
	v.age = -delay
	v.duration = rng:NextNumber(FX.CycleMin, FX.CycleMax)
	v.size = rng:NextNumber(FX.BubbleMin, FX.BubbleMax)
	v.popped = false
	v.active = true
end

local function tickVent(v: Vent, dt: number, y: number, cameraPos: Vector3)
	v.age += dt
	local distance = (Vector2.new(v.x, v.z) - Vector2.new(cameraPos.X, cameraPos.Z)).Magnitude
	if distance > FX.RelocateDistance then
		stopVent(v)
		beginCycle(v, cameraPos, rng:NextNumber(0, 0.5))
	elseif v.age >= v.duration then
		stopVent(v)
		beginCycle(v, cameraPos, 0)
	end
	v.anchor.Position = Vector3.new(v.x, y + 0.08, v.z)
	if v.age < 0 then return end
	local phase = math.clamp(v.age / v.duration, 0, 1)
	local grow = FX.GrowFraction
	local fadeEnd = grow + FX.PopFadeFraction
	local growing = phase < grow
	-- Disable continuous emission early enough for the pool to move without trails.
	local emitting = phase < grow * 0.8
	v.embers.Enabled = emitting
	v.smoke.Enabled = emitting
	if phase < fadeEnd then
		local t = math.clamp(phase / grow, 0, 1)
		local swell = math.sin(t * math.pi * 0.5)
		local width = v.size * (0.25 + swell * 0.75)
		local height = v.size * FX.BubbleHeightRatio
		v.bubble.Size = Vector3.new(width, height, width * 0.85)
		-- Track the live surface, rather than tweening toward an obsolete Y.
		v.bubble.Position = Vector3.new(v.x, y - height * 0.48 + swell * height * 0.6, v.z)
		v.bubble.Transparency = if growing then 0 else (phase - grow) / FX.PopFadeFraction
	else
		v.bubble.Transparency = 1
	end
	if not growing and not v.popped then
		v.popped = true
		v.sparks:Emit(FX.SparkBurst)
		v.drops:Emit(FX.DropBurst)
		v.smoke:Emit(FX.SmokeBurst)
	end
	if v.light then
		local fadeIn = math.clamp(v.age / FX.LightFadeSeconds, 0, 1)
		local fadeOut = math.clamp((v.duration - v.age) / FX.LightFadeSeconds, 0, 1)
		local sincePop = v.age - grow * v.duration
		local flash = if sincePop >= 0 then math.max(0, 1 - sincePop / FX.LightFadeSeconds) else 0
		v.light.Brightness = (FX.LightBaseBrightness + FX.LightPopBrightness * flash) * fadeIn * fadeOut
	end
end

local function numberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function rebuild()
	if wave then wave:Destroy(); wave = nil end
	stopPool()
	for _, c in ipairs(childConnections) do c:Disconnect() end
	table.clear(childConnections)
	table.clear(layers)
	surface = nil
	minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local folder = lavaFolder
	if not folder then return end
	local parts: { BasePart } = {}
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then table.insert(parts, p) end
	end
	table.sort(parts, function(a, b) return a.Position.Y + a.Size.Y/2 > b.Position.Y + b.Size.Y/2 end)
	surface = parts[1]
	if surface and Config.Lava.Waves.Enabled then wave = LavaWaveMesh.new(surface, Config.Lava.Waves, parts) end
	for _, p in ipairs(parts) do
		minX = math.min(minX, p.Position.X - p.Size.X/2)
		maxX = math.max(maxX, p.Position.X + p.Size.X/2)
		minZ = math.min(minZ, p.Position.Z - p.Size.Z/2)
		maxZ = math.max(maxZ, p.Position.Z + p.Size.Z/2)
		for _, child in ipairs(p:GetChildren()) do
			-- Clear remnants saved into the place; the server no longer creates these.
			if (child.Name == "LavaEmbers" or child.Name == "LavaSmoke") and child:IsA("ParticleEmitter") then
				child.Enabled = false
				child:Clear()
			elseif child.Name == "LavaGlow" and child:IsA("SurfaceLight") then
				child.Enabled = false
			elseif child:IsA("Texture") then
				local mult = SURF.LayerMultipliers[#layers % #SURF.LayerMultipliers + 1]
				table.insert(layers, {texture=child,
					u=numberAttribute(child,"ScrollU",SURF.DefaultScrollU * mult),
					v=numberAttribute(child,"ScrollV",SURF.DefaultScrollV * mult), alpha=child.Transparency,
					amount=numberAttribute(child,"PulseAmount",SURF.DefaultPulseAmount),
					period=math.max(0.1,numberAttribute(child,"PulsePeriod",SURF.DefaultPulsePeriod))})
			end
		end
		table.insert(childConnections, p.ChildAdded:Connect(rebuild))
		table.insert(childConnections, p.ChildRemoved:Connect(rebuild))
	end
end

local function update(dt: number)
	accumulator += dt
	if accumulator < 1 / SURF.UpdateHz then return end
	dt = math.min(accumulator, SURF.MaxFrameStep)
	accumulator = 0
	if wave and wave.dead then rebuild() end
	local p = surface
	local camera = Workspace.CurrentCamera
	if not p or not p.Parent or not camera then
		if running then stopPool() end
		return
	end
	local y = p.Position.Y + p.Size.Y/2
	if y >= FX.MinSurfaceY + FX.MinSurfaceHysteresis then heightAllowed = true
	elseif y <= FX.MinSurfaceY - FX.MinSurfaceHysteresis then heightAllowed = false end
	local pos = camera.CFrame.Position
	local nearest = Vector3.new(math.clamp(pos.X,minX,maxX), y, math.clamp(pos.Z,minZ,maxZ))
	local surfaceVisible = pos.Y >= y and (nearest - pos).Magnitude <= FX.Distance
	local allowed = heightAllowed and surfaceVisible
	-- The street-height gate prevents smoke crossing roads; the surface itself
	-- must already deform in canals before the lava reaches street level.
	if wave then wave:update(dt, surfaceVisible) end
	-- Leave the established submerged view alone, including its blur and tint.
	if not allowed then
		if running then stopPool() end
	else
		if not running then
			running = true
			for i, v in ipairs(vents) do beginCycle(v, pos, (i-1) * FX.CycleMin / FX.VentCount) end
		end
		for _, v in ipairs(vents) do tickVent(v, dt, y, pos) end
	end
	local now = os.clock()
	for _, layer in ipairs(layers) do
		local t = layer.texture
		if not t.Parent then continue end
		t.OffsetStudsU = now * layer.u % math.max(t.StudsPerTileU, 0.1)
		t.OffsetStudsV = now * layer.v % math.max(t.StudsPerTileV, 0.1)
		if layer.amount ~= 0 then
			t.Transparency = math.clamp(layer.alpha + math.sin(now * math.pi*2/layer.period) * layer.amount,0,1)
		end
	end
end

function Controller.init()
	if initialized then return end
	initialized = true
	if not SURF.Enabled then return end
	task.spawn(function()
		local folder = Workspace:WaitForChild("Lava", 30)
		if not folder then warn("[LavaSurface] missing Workspace.Lava"); return end
		lavaFolder = folder
		buildPool()
		rebuild()
		folder.ChildAdded:Connect(rebuild)
		folder.ChildRemoved:Connect(rebuild)
		RunService.Heartbeat:Connect(update)
	end)
end
return Controller
