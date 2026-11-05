--!strict
-- TowerAmbienceController.luau (02.11) — „mroczniej przy wieży maga”, tylko u gracza.
--
-- Im bliżej osi wieży stoi postać, tym mocniej obraz ciemnieje i chłodnieje: własny
-- ColorCorrectionEffect (jak LavaHeatController), a od 03.11 też ExposureCompensation (ciemnieje
-- niebo), lokalna Atmosphere (mglisty horyzont) i gasnące słońce (tarcza + promienie). Zmiany Lightingu są tylko u tego gracza i przy
-- zerowej sile wracają DOKŁADNIE do wartości z placu (Atmosphere jest wtedy usuwana) — z dala od
-- wieży lobby i mapa wyglądają jak dotąd. Mgła to cząsteczki w placu
-- (`WizardTower.Grounds.Mist`); tu tylko jej ilość według GRAPHICS (LOW = mniej).
--
-- Odległość w poziomie od PIVOTU modelu, nie od środka obrysu — ścieżka i mgła należą do
-- modelu i przesuwają środek obrysu z dala od wieży.
--
-- Config: Config.Ambience.Tower.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local SettingsState = require(script.Parent.SettingsState)

local TowerAmbienceController = {}

local CFG = Config.Ambience.Tower
local WHITE = Color3.new(1, 1, 1)
local EFFECT_NAME = "TowerAmbienceEffect"

local ATMOSPHERE_NAME = "TowerAmbienceAtmosphere"

local localPlayer = Players.LocalPlayer
local effect: ColorCorrectionEffect? = nil
local atmosphere: Atmosphere? = nil
-- Plac ma własną Atmosphere → nie tworzymy drugiej (dwie naraz = nieokreślony wygląd nieba).
local foreignAtmosphere = false
local baseExposure = 0
-- Słońce z placu (Sky + SunRaysEffect) — przy wieży gaśnie, po odejściu wraca do tych wartości.
local sky: Sky? = nil
local baseSunSize = 0
local sunRays: SunRaysEffect? = nil
local baseSunRays = 0
local center: Vector3? = nil
local current = 0
local initialized = false

local function getEffect(): ColorCorrectionEffect
	if effect and effect.Parent then return effect end
	local existing = Lighting:FindFirstChild(EFFECT_NAME)
	if existing and existing:IsA("ColorCorrectionEffect") then
		effect = existing
		return existing
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = EFFECT_NAME
	cc.Enabled = false
	cc.Parent = Lighting
	effect = cc
	return cc
end

local function targetAmount(): number
	local c = center
	if not c then return 0 end
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return 0 end
	local d = Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z).Magnitude
	if d <= CFG.InnerRadius then return 1 end
	if d >= CFG.OuterRadius then return 0 end
	local t = (CFG.OuterRadius - d) / (CFG.OuterRadius - CFG.InnerRadius)
	return t * t * (3 - 2 * t) -- smoothstep: bez wyczuwalnej „krawędzi” strefy
end

local function setAtmosphere(amount: number)
	if foreignAtmosphere then return end
	local A = CFG.Atmosphere
	if amount <= 0.001 then
		if atmosphere then atmosphere:Destroy() end
		atmosphere = nil
		return
	end
	local atm = atmosphere
	if not (atm and atm.Parent) then
		atm = Instance.new("Atmosphere")
		atm.Name = ATMOSPHERE_NAME
		atm.Offset = A.Offset
		atm.Glare = A.Glare
		atm.Color = A.Color
		atm.Decay = A.Decay
		atm.Density = 0
		atm.Haze = 0
		atm.Parent = Lighting
		atmosphere = atm
	end
	local a = atm :: Atmosphere
	a.Density = A.Density * amount
	a.Haze = A.Haze * amount
end

local function apply(amount: number)
	local cc = getEffect()
	cc.Enabled = amount > 0.001
	cc.Brightness = CFG.Brightness * amount
	cc.Contrast = CFG.Contrast * amount
	cc.Saturation = CFG.Saturation * amount
	cc.TintColor = WHITE:Lerp(CFG.Tint, amount)
	Lighting.ExposureCompensation = baseExposure + CFG.Exposure * amount
	local s, r = sky, sunRays
	if s and s.Parent then s.SunAngularSize = baseSunSize * (1 + (CFG.SunSizeFactor - 1) * amount) end
	if r and r.Parent then r.Intensity = baseSunRays * (1 + (CFG.SunRaysFactor - 1) * amount) end
	setAtmosphere(amount)
end

local function mistEmitters(model: Instance): { ParticleEmitter }
	local node: Instance? = model
	for _, name in ipairs(CFG.MistPath) do
		node = node and node:FindFirstChild(name)
	end
	local list: { ParticleEmitter } = {}
	if node then
		for _, d in ipairs(node:GetDescendants()) do
			if d:IsA("ParticleEmitter") then table.insert(list, d) end
		end
	end
	return list
end

local function applyMistQuality(model: Instance)
	local factor = if SettingsState.get("graphics") == "low" then CFG.LowMistFactor else 1
	for _, e in ipairs(mistEmitters(model)) do
		local base = e:GetAttribute("BaseRate")
		if type(base) == "number" then
			e.Rate = base * factor
		end
	end
end

function TowerAmbienceController.init()
	if initialized then return end
	initialized = true

	-- Wartości z placu — punkt powrotu przy zerowej sile.
	baseExposure = Lighting.ExposureCompensation
	sky = Lighting:FindFirstChildOfClass("Sky")
	baseSunSize = if sky then sky.SunAngularSize else 0
	sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	baseSunRays = if sunRays then sunRays.Intensity else 0
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	foreignAtmosphere = existing ~= nil and existing.Name ~= ATMOSPHERE_NAME

	RunService.RenderStepped:Connect(function(dt: number)
		local target = targetAmount()
		if target == current and target == 0 then return end
		-- Stałe tempo zamiast skoku: teleport do lobby/na mapę zmienia odległość w jednej klatce.
		local step = CFG.BlendSpeed * dt
		current = if math.abs(target - current) <= step then target else current + math.sign(target - current) * step
		apply(current)
	end)

	task.spawn(function()
		local model = Workspace:WaitForChild(CFG.ModelName, 30)
		if not (model and model:IsA("Model")) then
			warn(("[TowerAmbience] brak Workspace.%s — klimat wieży wyłączony"):format(CFG.ModelName))
			return
		end
		center = model:GetPivot().Position
		applyMistQuality(model)
		SettingsState.onChanged(function() applyMistQuality(model) end)
	end)
end

return TowerAmbienceController
