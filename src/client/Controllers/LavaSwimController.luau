--!strict
-- LavaSwimController.luau
-- GĘSTA LAWA (decyzja Kacpra 01.10: „zapada się powoli, da się wypłynąć”). Jedna sprawa
-- z dwóch stron — jak się jest W lawie:
--   * RUCH. Postać jest w fizyce klienta (network ownership), więc opór liczymy tutaj. Stopy
--     pod taflą → prędkość pionowa dąży do powolnego opadania albo, przy trzymanym skoku,
--     do wznoszenia; chód zwalnia (mnożnik w MovementController); przy powierzchni trzymany
--     skok wybija z lawy, żeby dało się wejść na brzeg. Do 01.10 lawa nie miała oporu:
--     leciało się na dno (ulicę pod taflą), a z głębokiej lawy nie było wyjścia.
--   * WIDOK. Kamera pod taflą → gęsto i pomarańczowo (ColorCorrection + Blur w Lighting, jak
--     LavaHeatController). Bez tego warstwy lawy oglądane od spodu są przezroczyste i widać
--     ulicę na dnie („wpadniesz i przezroczysto”).
-- Obrażenia dalej liczy serwer (LavaService, ten sam próg stóp — `Config.Lava.FeetOffset`);
-- upadek do lawy nie rani (FallDamageService). Sterowanie skokiem przez `Humanoid.Jump`, które
-- moduł sterowania ustawia co klatkę, póki skok jest trzymany — klawiatura, pad i dotyk naraz.
-- ⚠️ W ragdollu nic nie robimy: ciało ma wtedy fizykę serwera, a nasze prędkości walczyłyby
-- z toolboxem. Ragdoll w lawie opada więc jak dawniej, do wstania (~2 s).
-- ⚠️ Anty-cheat (plan paczki 6): wznoszenie w lawie trwa dłużej niż sekundę — reguła
-- „ciągłe wznoszenie > 1 s” musi lawę pomijać.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local MovementController = require(script.Parent.MovementController)
local RagdollState = require(script.Parent.RagdollState)

local LavaSwimController = {}

local SWIM = Config.Lava.Swim
local VIEW = Config.Lava.Submerged
local SPEED_KEY = "lava"
local WHITE = Color3.new(1, 1, 1)

local localPlayer = Players.LocalPlayer
local slowed = false
local nextExitAt = 0
local viewIntensity = 0
local colorFx: ColorCorrectionEffect? = nil
local blurFx: BlurEffect? = nil
local initialized = false

local function release()
	if slowed then
		slowed = false
		MovementController.setSpeedFactor(SPEED_KEY, nil)
	end
end

-- ---- Ruch ------------------------------------------------------------------------

local function swimStep(dt: number)
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local top = Utils.lavaSurfaceY()
	if not (hum and hrp and hrp:IsA("BasePart") and top) or hum.Health <= 0 or RagdollState.isRagdolled(hum) then
		release()
		return
	end
	local depth = top - (hrp.Position.Y - Config.Lava.FeetOffset)
	if depth <= 0 then
		release()
		return
	end

	-- Opór rośnie z głębokością: brodzenie po kostki prawie nie zwalnia, po pas — w pełni.
	local immersion = math.clamp(depth / SWIM.FullDepth, 0, 1)
	slowed = true
	MovementController.setSpeedFactor(SPEED_KEY, 1 + (SWIM.SpeedFactor - 1) * immersion)

	local v = hrp.AssemblyLinearVelocity
	local now = os.clock()
	local vy: number
	if hum.Jump and depth <= SWIM.ExitDepth and now >= nextExitAt then
		-- Wyskok przy powierzchni: prędkość zwykłego skoku na wysokość ExitJumpHeight.
		nextExitAt = now + SWIM.ExitCooldown
		vy = math.sqrt(2 * Workspace.Gravity * SWIM.ExitJumpHeight)
	else
		local target = if hum.Jump then SWIM.SwimUpSpeed else -SWIM.SinkSpeed
		local a = 1 - math.exp(-SWIM.Damping * immersion * dt)
		vy = v.Y + (target - v.Y) * a
	end
	-- Poziomo gaśnie tylko NADMIAR ponad chód (np. gracz wrzucony do lawy bombą) — zwykłe
	-- chodzenie spowalnia już mnożnik prędkości.
	local h = Vector3.new(v.X, 0, v.Z)
	local speed = h.Magnitude
	local maxH = hum.WalkSpeed
	if speed > maxH then
		local keep = math.exp(-SWIM.Damping * immersion * dt)
		h = h * ((maxH + (speed - maxH) * keep) / speed)
	end
	hrp.AssemblyLinearVelocity = Vector3.new(h.X, vy, h.Z)
end

-- ---- Widok -----------------------------------------------------------------------

local function effects(): (ColorCorrectionEffect, BlurEffect)
	local cc = colorFx
	if not cc or not cc.Parent then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "LavaSubmergedEffect"
		c.Parent = Lighting
		cc = c
		colorFx = c
	end
	local blur = blurFx
	if not blur or not blur.Parent then
		local b = Instance.new("BlurEffect")
		b.Name = "LavaSubmergedBlur"
		b.Size = 0
		b.Parent = Lighting
		blur = b
		blurFx = b
	end
	return cc :: ColorCorrectionEffect, blur :: BlurEffect
end

local function viewStep(dt: number)
	local cam = Workspace.CurrentCamera
	local top = Utils.lavaSurfaceY()
	local target = if cam and top and cam.CFrame.Position.Y < top then 1 else 0
	viewIntensity += (target - viewIntensity) * (1 - math.exp(-VIEW.LerpSpeed * dt))

	-- Poza lawą nie dotykamy Lighting (zero kosztu przez prawie całą rundę).
	if viewIntensity < 0.01 then
		if colorFx and colorFx.Enabled then
			colorFx.Enabled = false
		end
		if blurFx and blurFx.Enabled then
			blurFx.Enabled = false
		end
		return
	end
	local cc, blur = effects()
	cc.Enabled = true
	blur.Enabled = true
	cc.TintColor = WHITE:Lerp(VIEW.Tint, viewIntensity)
	cc.Brightness = VIEW.Brightness * viewIntensity
	cc.Contrast = VIEW.Contrast * viewIntensity
	cc.Saturation = VIEW.Saturation * viewIntensity
	blur.Size = VIEW.Blur * viewIntensity
end

function LavaSwimController.init()
	if initialized then return end
	initialized = true
	if SWIM.Enabled then
		-- Przed krokiem fizyki: prędkość ustawiona tutaj działa jeszcze w tej klatce.
		RunService.PreSimulation:Connect(swimStep)
	end
	if VIEW.Enabled then
		RunService.RenderStepped:Connect(viewStep)
	end
end

return LavaSwimController
