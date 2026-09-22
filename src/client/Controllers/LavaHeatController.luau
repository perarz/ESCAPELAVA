--!strict
-- LavaHeatController.luau
-- Klient-side "żar" bliskości lawy: im niżej nad powierzchnią lawy jest gracz, tym
-- mocniej ekran ciepleje (ColorCorrection tint + lekki kontrast). Czysty feedback
-- zagrożenia — gracz CZUJE że lawa jest blisko zanim ją zobaczy pod nogami.
--
-- Zasady:
--   * Nie ruszamy globalnego lightingu (design świateł = domena Kacpra) — nasz efekt to
--     osobny ColorCorrectionEffect, przy intensity=0 całkowicie neutralny (brak zmian).
--   * Intensywność = 1 - dist/Distance (dist = wysokość HRP nad TOPEM lawy), smooth lerp.
--   * Throttle 10Hz — odczyt pozycji lawy nie musi być per-frame; lerp jest per-frame
--     dla płynności (RenderStepped tylko interpoluje w stronę targetu).
--
-- Config: Config.Lava.HeatEffect (Enabled, Distance, Tint, MaxContrast, LerpSpeed).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local LavaHeatController = {}

local CFG = Config.Lava.HeatEffect
local WHITE = Color3.new(1, 1, 1)

local localPlayer = Players.LocalPlayer
local effect: ColorCorrectionEffect? = nil
local lavaPart: BasePart? = nil
local targetIntensity = 0
local currentIntensity = 0
local initialized = false

local function getEffect(): ColorCorrectionEffect
	if effect and effect.Parent then return effect end
	local existing = Lighting:FindFirstChild("LavaHeatEffect")
	if existing and existing:IsA("ColorCorrectionEffect") then
		effect = existing
		return existing
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "LavaHeatEffect"
	cc.Parent = Lighting
	effect = cc
	return cc
end

-- Lawa to STOS warstw (2026-09-16) — żar liczymy od warstwy WIERZCHNIEJ, bo to ona
-- jest powierzchnią, do której zbliża się gracz. Skanujemy folder za każdym razem
-- zamiast cache'ować jeden part: warstw jest kilka, Kacper dokłada je i zabiera
-- w trakcie Play, a trzy porównania przy 10 Hz kosztują dokładnie nic.
local function findLava(): BasePart?
	local folder = Workspace:FindFirstChild("Lava")
	if not folder then return nil end

	local best: BasePart? = nil
	local bestTop = -math.huge
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local top = child.Position.Y + child.Size.Y * 0.5
			if top > bestTop then
				best, bestTop = child, top
			end
		end
	end
	lavaPart = best
	return best
end

local function computeTarget(): number
	local lava = findLava()
	if not lava then return 0 end
	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return 0 end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return 0 end

	local lavaTop = lava.Position.Y + lava.Size.Y * 0.5
	local dist = hrp.Position.Y - lavaTop
	-- Poniżej powierzchni (spadanie w lawę) = max. Powyżej Distance = zero.
	return math.clamp(1 - dist / CFG.Distance, 0, 1)
end

function LavaHeatController.init()
	if initialized then return end
	initialized = true
	if not CFG.Enabled then return end

	-- Target 10Hz (odczyt world state), lerp per-frame (płynność efektu).
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt: number)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			targetIntensity = computeTarget()
		end

		local alpha = 1 - math.exp(-CFG.LerpSpeed * dt)
		currentIntensity = currentIntensity + (targetIntensity - currentIntensity) * alpha

		-- Poniżej progu nie dotykamy Lighting (zero kosztu gdy daleko od lawy).
		if currentIntensity < 0.01 then
			if effect and effect.TintColor ~= WHITE then
				effect.TintColor = WHITE
				effect.Contrast = 0
			end
			return
		end

		local cc = getEffect()
		cc.TintColor = WHITE:Lerp(CFG.Tint, currentIntensity)
		cc.Contrast = CFG.MaxContrast * currentIntensity
	end)
end

return LavaHeatController
