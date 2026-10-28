--!strict
-- Local ambient lava VFX. Fixed pool: no allocations or raycasts during cycles.
-- Server owns height/damage; LavaSwimController owns the submerged view.
-- Height hysteresis intentionally replaces exposure raycasts (streaming ambiguity).
-- GRAPHICS LOW / HIGH (27.10, SettingsState): LOW = mniej skupisk i świateł (dawna reguła
-- dla telefonu), HIGH = pełne skupiska + łuna na ścianach (`Lava.Glow`) + iskry i popiół
-- (`Lava.Air`). Przełączane na żywo; pule zbudowane raz w rozmiarze HIGH.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Modules.Config)
local FX = Config.Lava.FX
local SURF = Config.Lava.Surface
local GLOW = Config.Lava.Glow
local AIR = Config.Lava.Air
local Controller = {}
local LavaWaveMesh = require(script.Parent.LavaWaveMesh)
local SettingsState = require(script.Parent.SettingsState)
local wave = nil
local rng = Random.new()

type Vent = {
	anchor: Part, bubble: Part, core: Part,
	embers: ParticleEmitter, smoke: ParticleEmitter,
	sparks: ParticleEmitter, drops: ParticleEmitter,
	light: PointLight?, lit: boolean, age: number, duration: number,
	x: number, z: number, size: number, popped: boolean, active: boolean,
	strength: number, rotation: number,
}
type GlowSlot = { attachment: Attachment, light: PointLight, key: number?, level: number, want: boolean }
type Air = { anchor: Part, embers: ParticleEmitter, ash: ParticleEmitter }
type Layer = { texture: Texture, u: number, v: number, alpha: number, amount: number, period: number }
local vents: { Vent } = {}
local layers: { Layer } = {}
local surface: BasePart? = nil
local lavaFolder: Instance? = nil
local effects: Folder? = nil
local childConnections: { RBXScriptConnection } = {}
local ventLimit = FX.VentCount
local lightLimit = FX.LightCount
local particleScale = 1
local extras = true -- HIGH: łuna i iskry/popiół
local glowSlots: { GlowSlot } = {}
local air: Air? = nil
local airRise = -1
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
		local core = cosmeticPart("MoltenCore" .. i, folder)
		core.Shape = Enum.PartType.Ball
		core.Material = Enum.Material.Neon
		core.Color = FX.HotColor
		local embers = emitter("Embers", anchor, FX.SparkTexture)
		embers.Color = ColorSequence.new(FX.HotColor, FX.CoolColor)
		embers.Size = NumberSequence.new(0.18, 0.04)
		embers.Transparency = NumberSequence.new(0.2, 1)
		embers.Lifetime = NumberRange.new(FX.EmberLifeMin, FX.EmberLifeMax)
		embers.Speed = NumberRange.new(FX.EmberSpeedMin, FX.EmberSpeedMax)
		embers.SpreadAngle = Vector2.new(25, 25)
		embers.LightEmission = 0.7
		embers.Rate = FX.EmberRate * particleScale
		embers.Drag = FX.EmberDrag
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
		smoke.Rate = FX.SmokeRate * particleScale
		smoke.Acceleration = FX.SmokeDrift
		smoke.Drag = FX.SmokeDrag
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
		table.insert(vents, {anchor=anchor, bubble=bubble, core=core, embers=embers, smoke=smoke,
			sparks=sparks, drops=drops, light=light, lit=light ~= nil, age=0, duration=1,
			x=0, z=0, size=1, popped=false, active=false, strength=1, rotation=0})
	end

	-- Łuna: światła na attachmentach jednego parta w zerze świata (Position = pozycja w świecie).
	local glowRoot = cosmeticPart("GlowRoot", folder)
	glowRoot.CFrame = CFrame.identity
	for _ = 1, GLOW.Grid * GLOW.Grid do
		local attachment = Instance.new("Attachment")
		attachment.Parent = glowRoot
		local light = Instance.new("PointLight")
		light.Color = GLOW.Color
		light.Range = GLOW.Range
		light.Shadows = false
		light.Brightness = 0
		light.Enabled = false
		light.Parent = attachment
		table.insert(glowSlots, { attachment = attachment, light = light, key = nil, level = 0, want = false })
	end

	-- Iskry i popiół: jedno płaskie pudło przy tafli — emiter sieje z całej jego objętości.
	local anchor = cosmeticPart("AirFX", folder)
	anchor.Size = Vector3.new(AIR.HalfSize * 2, 0.2, AIR.HalfSize * 2)
	local embers = emitter("AirEmbers", anchor, FX.SparkTexture)
	embers.Color = ColorSequence.new(AIR.EmberColor, AIR.EmberEndColor)
	embers.Size = NumberSequence.new(0.14, 0.03)
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Speed = NumberRange.new(AIR.EmberSpeedMin, AIR.EmberSpeedMax)
	embers.SpreadAngle = Vector2.new(15, 15)
	embers.LightEmission = 1
	local ash = emitter("AirAsh", anchor, FX.SmokeTexture)
	ash.Color = ColorSequence.new(AIR.AshColor, AIR.AshEndColor)
	ash.Size = NumberSequence.new(0.18, 0.1)
	ash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	ash.Speed = NumberRange.new(AIR.AshSpeedMin, AIR.AshSpeedMax)
	ash.SpreadAngle = Vector2.new(35, 35)
	ash.Acceleration = AIR.AshDrift
	ash.Rotation = NumberRange.new(-180, 180)
	ash.RotSpeed = NumberRange.new(-60, 60)
	air = { anchor = anchor, embers = embers, ash = ash }
end

local function stopVent(v: Vent)
	v.active = false
	v.bubble.Transparency = 1
	v.core.Transparency = 1
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
	v.strength = v.size / FX.BubbleMax
	v.rotation = rng:NextNumber(0, math.pi*2)
	local p = surface
	if p then
		v.bubble.Material = p.Material
		v.bubble.MaterialVariant = p.MaterialVariant
		v.bubble.Color = p.Color
	end
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
	-- The wave mesh no longer follows the physical plate's whole-part bob.
	if wave then y = wave:surfaceY(v.x, v.z) or y end
	v.anchor.Position = Vector3.new(v.x, y + FX.EmitterLift, v.z)
	if v.age < 0 then return end
	local phase = math.clamp(v.age / v.duration, 0, 1)
	local grow = FX.GrowFraction
	local fadeEnd = grow + FX.PopFadeFraction
	local growing = phase < grow
	-- Disable continuous emission early enough for the pool to move without trails.
	local emitting = v.age < math.max(0, v.duration - FX.SmokeLifeMax)
	v.embers.Enabled = emitting
	v.smoke.Enabled = emitting
	local t = math.clamp(phase / grow, 0, 1)
	local swell = t*t*(3-2*t)
	local collapse = math.clamp((phase-grow) / FX.PopFadeFraction, 0, 1)
	local width = v.size * (0.25 + swell * 0.75)
	local height = v.size * FX.BubbleHeightRatio
	if phase < fadeEnd then
		-- The cap sinks and flattens at rupture instead of a complete ball fading out.
		local capHeight = height * (1-collapse*0.9)
		v.bubble.Size = Vector3.new(width, math.max(0.05,capHeight), width * 0.85)
		v.bubble.CFrame = CFrame.new(v.x, y - capHeight*0.5 + swell*capHeight*0.72, v.z)
			* CFrame.Angles(0,v.rotation,0)
		v.bubble.Transparency = collapse
	else
		v.bubble.Transparency = 1
	end
	local sincePop = v.age - grow*v.duration
	if sincePop >= 0 and sincePop < FX.CoreSeconds then
		local fade = sincePop/FX.CoreSeconds
		local coreWidth = v.size*(FX.CoreStartScale+fade*FX.CoreSpread)
		v.core.Size = Vector3.new(coreWidth,FX.CoreThickness,coreWidth*0.85)
		v.core.CFrame = CFrame.new(v.x,y+FX.CoreLift,v.z)*CFrame.Angles(0,v.rotation,0)
		v.core.Transparency = FX.CoreTransparency+(1-FX.CoreTransparency)*fade
	else
		v.core.Transparency = 1
	end
	if not growing and not v.popped then
		v.popped = true
		local dose = particleScale * v.strength
		v.sparks:Emit(math.max(1,math.floor(FX.SparkBurst*dose)))
		v.drops:Emit(math.max(1,math.floor(FX.DropBurst*dose)))
		v.smoke:Emit(math.max(1,math.floor(FX.SmokeBurst*dose)))
	end
	if v.light and v.lit then
		local fadeIn = math.clamp(v.age / FX.LightFadeSeconds, 0, 1)
		local fadeOut = math.clamp((v.duration - v.age) / FX.LightFadeSeconds, 0, 1)
		local flash = if sincePop >= 0 then math.max(0, 1 - sincePop / FX.LightFadeSeconds) else 0
		local breathe = 1 + FX.LightBreath * math.sin(v.age*FX.LightBreathSpeed+v.rotation)
		v.light.Brightness = (FX.LightBaseBrightness*breathe + FX.LightPopBrightness*flash*v.strength) * fadeIn * fadeOut
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

-- Klucz oczka siatki łuny (oczka mieszczą się w ±32768 — mapa ma kilkaset studów).
local function cellKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

local function cellInside(cx: number, cz: number): boolean
	local x, z = cx * GLOW.Spacing, cz * GLOW.Spacing
	return x >= minX and x <= maxX and z >= minZ and z <= maxZ
end

local function glowY(cx: number, cz: number, y: number): number
	local x, z = cx * GLOW.Spacing, cz * GLOW.Spacing
	return (if wave then wave:surfaceY(x, z) or y else y) + GLOW.Lift
end

local glowTaken: { [number]: boolean } = {}

-- Oczko w siatce Grid × Grid wokół oczka kamery (ccx, ccz)?
local function inGrid(key: number, ccx: number, ccz: number, lo: number, hi: number): boolean
	local cx = key // 65536 - 32768
	local cz = key % 65536 - 32768
	return cx >= ccx + lo and cx <= ccx + hi and cz >= ccz + lo and cz <= ccz + hi
end

-- Wolne światło → pierwsze nieobsadzone oczko siatki nad lawą.
local function claimCell(s: GlowSlot, ccx: number, ccz: number, lo: number, hi: number)
	for dx = lo, hi do
		for dz = lo, hi do
			local cx, cz = ccx + dx, ccz + dz
			local key = cellKey(cx, cz)
			if not glowTaken[key] and cellInside(cx, cz) then
				glowTaken[key] = true
				s.key = key
				s.want = true
				return
			end
		end
	end
end

-- Oczka zostają w świecie: światło, którego oczko wyszło z siatki wokół kamery, gaśnie i
-- dopiero przy zerze przenosi się w wolne oczko — przeskoku nie widać.
local function updateGlow(dt: number, on: boolean, y: number, pos: Vector3)
	local fade = dt / GLOW.FadeTime
	local lo = -math.floor((GLOW.Grid - 1) / 2)
	local hi = lo + GLOW.Grid - 1
	local ccx = math.floor(pos.X / GLOW.Spacing + 0.5)
	local ccz = math.floor(pos.Z / GLOW.Spacing + 0.5)
	table.clear(glowTaken)
	for _, s in ipairs(glowSlots) do
		local key = s.key
		s.want = on and key ~= nil and inGrid(key, ccx, ccz, lo, hi)
		if s.want then glowTaken[key :: number] = true end
	end
	for _, s in ipairs(glowSlots) do
		if on and not s.want and s.level <= 0 then claimCell(s, ccx, ccz, lo, hi) end
		s.level = math.clamp(s.level + (if s.want then fade else -fade), 0, 1)
		local key = s.key
		-- Gasnące światło stoi tam, gdzie było — inaczej pojechałoby za kamerą w trakcie gaszenia.
		if key and s.want then
			local cx, cz = key // 65536 - 32768, key % 65536 - 32768
			s.attachment.Position = Vector3.new(cx * GLOW.Spacing, glowY(cx, cz, y), cz * GLOW.Spacing)
		end
		s.light.Brightness = GLOW.Brightness * s.level
		s.light.Enabled = s.level > 0
	end
end

-- Iskry i popiół. Zasięg wznoszenia = czas życia × prędkość maks. (particle przelatują przez
-- geometrię): w kanale do jezdni minus zapas, nad ulicą `MaxRise`.
local function updateAir(on: boolean, y: number, pos: Vector3)
	local a = air
	if not a then return end
	local rise = if heightAllowed then AIR.MaxRise else FX.MinSurfaceY - y - AIR.CanalMargin
	if not on or rise < AIR.MinRise then
		a.embers.Enabled = false
		a.ash.Enabled = false
		return
	end
	local h = AIR.HalfSize
	local cx = if maxX - minX > h * 2 then math.clamp(pos.X, minX + h, maxX - h) else (minX + maxX) / 2
	local cz = if maxZ - minZ > h * 2 then math.clamp(pos.Z, minZ + h, maxZ - h) else (minZ + maxZ) / 2
	-- Fizyczna tafla, nie fala: przy fali start bywa o ~1 stud wyżej, a limit w kanale musi trzymać.
	a.anchor.Position = Vector3.new(cx, y + AIR.Lift, cz)
	local ramp = math.clamp((y - AIR.RampStartY) / (AIR.RampEndY - AIR.RampStartY), 0, 1)
	a.embers.Rate = AIR.EmberRateMin + (AIR.EmberRateMax - AIR.EmberRateMin) * ramp
	a.ash.Rate = AIR.AshRateMin + (AIR.AshRateMax - AIR.AshRateMin) * ramp
	if math.abs(rise - airRise) > 0.1 then
		airRise = rise
		local travel = math.max(rise - AIR.Lift, 0.1)
		a.embers.Lifetime = NumberRange.new(travel / AIR.EmberSpeedMax * 0.5, travel / AIR.EmberSpeedMax)
		a.ash.Lifetime = NumberRange.new(travel / AIR.AshSpeedMax * 0.5, travel / AIR.AshSpeedMax)
	end
	a.embers.Enabled = true
	a.ash.Enabled = true
end

-- GRAPHICS LOW / HIGH na żywo. Skupiska ponad limitem gasną od razu; nowe dochodzą w
-- następnym cyklu `update` (tam nieaktywne skupisko w limicie dostaje nowy cykl).
local function applyQuality()
	local high = SettingsState.get("graphics") ~= "low"
	extras = high
	ventLimit = if high then FX.VentCount else FX.LowVentCount
	lightLimit = if high then FX.LightCount else FX.LowLightCount
	particleScale = if high then 1 else FX.LowParticleScale
	for i, v in ipairs(vents) do
		v.embers.Rate = FX.EmberRate * particleScale
		v.smoke.Rate = FX.SmokeRate * particleScale
		v.lit = v.light ~= nil and i <= lightLimit
		if v.light and not v.lit then v.light.Brightness = 0 end
		if i > ventLimit and v.active then stopVent(v) end
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
		updateGlow(dt, false, 0, Vector3.zero)
		updateAir(false, 0, Vector3.zero)
		return
	end
	local physicalY = p.Position.Y + p.Size.Y/2
	local baseY = p:GetAttribute("LavaVisualBaseY")
	local y = physicalY
	local gateY = if typeof(baseY) == "number" then baseY else physicalY
	if gateY >= FX.MinSurfaceY + FX.MinSurfaceHysteresis then heightAllowed = true
	elseif gateY <= FX.MinSurfaceY - FX.MinSurfaceHysteresis then heightAllowed = false end
	local pos = camera.CFrame.Position
	local nearest = Vector3.new(math.clamp(pos.X,minX,maxX), y, math.clamp(pos.Z,minZ,maxZ))
	local cameraSurfaceY = if wave then wave:surfaceY(pos.X,pos.Z) or y else y
	local surfaceVisible = pos.Y >= math.max(physicalY,cameraSurfaceY) and (nearest - pos).Magnitude <= FX.Distance
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
			for i = 1, ventLimit do beginCycle(vents[i], pos, (i-1) * FX.CycleMin / ventLimit) end
		end
		for i = 1, ventLimit do
			local v = vents[i]
			-- Skupisko dołożone przełączeniem na HIGH w trakcie — zaczyna od losowego opóźnienia.
			if not v.active then beginCycle(v, pos, rng:NextNumber(0, FX.CycleMin)) end
			tickVent(v, dt, y, pos)
		end
	end
	updateGlow(dt, extras and allowed, y, pos)
	updateAir(extras and surfaceVisible, y, pos)
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

-- Widoczna wysokość tafli w punkcie (fala, jeśli jest) — czyta ją LavaSplashController.
-- nil = lawy nie ma albo punkt leży poza nią (lobby).
function Controller.surfaceYAt(x: number, z: number): number?
	local p = surface
	if not p or not p.Parent then return nil end
	if x < minX or x > maxX or z < minZ or z > maxZ then return nil end
	local y = p.Position.Y + p.Size.Y/2
	return if wave then wave:surfaceY(x, z) or y else y
end

function Controller.init()
	if initialized then return end
	initialized = true
	if not SURF.Enabled then return end
	applyQuality()
	SettingsState.onChanged(applyQuality)
	task.spawn(function()
		local folder = Workspace:WaitForChild("Lava", 30)
		if not folder then warn("[LavaSurface] missing Workspace.Lava"); return end
		lavaFolder = folder
		buildPool()
		applyQuality()
		rebuild()
		folder.ChildAdded:Connect(rebuild)
		folder.ChildRemoved:Connect(rebuild)
		RunService.Heartbeat:Connect(update)
	end)
end
return Controller
