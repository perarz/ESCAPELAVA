--!strict
-- MovementController.luau
-- Centralny client controller ruchu. Etapowo:
--   Etap 1: bazowy WalkSpeed na każdy character + camera zoom enforcement (3rd person).
--   Etap 2: sprint hold (LeftShift) z staminą + HUD pasek.
--   Etap 3: dynamic FOV (sprint = +X°).
--   Etap 4: smooth camera (elastic rotation smoothing, landing dip, screenShake API).
--   11.10: lekkie drżenie przy sprincie i przechył przy ruchu w bok (Config.Movement.Camera).
--   Etap 5 (TERAZ): head rotation — lokalna głowa + waist obracają się za kamerą,
--                   replikacja do innych klientów ~10Hz przez HeadTrackingService.
--
-- Wszystkie liczby z Config.Movement — zero magic numbers tutaj.
-- Klient-side: ruch i kamera są lokalne (smooth feedback), serwer dostaje finalne WalkSpeed
-- przez Roblox Humanoid auto-replication. WalkSpeed cap enforced przez AntiCheatService (server).
--
-- ===== RAGDOLL SAFETY =====
-- Czy postać leży jako ragdoll — `RagdollState` (29.09: toolbox ARTFVL zwiotcza przez
-- ChangeState(Physics), nie przez PlatformStand, więc sam PlatformStand go nie łapał).
-- - WalkSpeed nie działa w ragdollu (humanoid leży, fizyka kości decyduje).
-- - NIE drainujemy staminy podczas ragdoll (gracz nie biegnie świadomie, byłoby unfair).
-- - REGENUJEMY staminę podczas ragdoll (gracz "odzyskuje siłę leżąc", logiczne).
-- - Force-stop sprint przy ragdoll → po un-ragdoll player musi wcisnąć Shift ponownie
--   żeby świadomie wznowić sprint (eliminuje "obudziłem się i magicznie biegnę").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local RagdollState = require(script.Parent.RagdollState)

local MovementController = {}

local CFG = Config.Movement
local CFG_STAM = CFG.Stamina
local CFG_BAR = CFG.StaminaBar
local CFG_CAM = CFG.Camera
local CFG_HT = CFG.HeadTrack
local MAX_YAW_RAD = math.rad(CFG_HT.MaxYawDegrees)
local MAX_PITCH_RAD = math.rad(CFG_HT.MaxPitchDegrees)
local REPLICATE_INTERVAL = 1 / CFG_HT.ReplicateHz

local localPlayer = Players.LocalPlayer
local initialized = false

-- Per-character state (reset on każdy CharacterAdded)
local currentCharacter: Model? = nil
local currentHumanoid: Humanoid? = nil
local currentStamina: number = CFG_STAM.Max
local isSprintingHeld: boolean = false       -- LeftShift trzymany (intent gracza)
local exhausted: boolean = false              -- stamina spadła do 0 → blokada do MinToResume
local lastSprintActiveTime: number = 0       -- ostatni moment AKTYWNEGO sprintu (drain) — dla RegenDelay
local currentWalkSpeed: number = CFG.WalkSpeed -- aktualnie zaaplikowany (do lerp)
local currentFOV: number = CFG.BaseFOV         -- aktualny FOV kamery (do lerp)
-- Mnożniki prędkości od innych systemów, każdy pod swoim kluczem (01.10: gęsta lawa —
-- LavaSwimController; potem itemy typu energy drink). WalkSpeed pisze dalej TYLKO ten
-- kontroler — dwa miejsca piszące tę samą liczbę co klatkę walczyłyby ze sobą.
local speedFactors: { [string]: number } = {}

local function speedFactor(): number
	local f = 1
	for _, v in pairs(speedFactors) do
		f *= v
	end
	return f
end

-- Head tracking (Etap 5) — per-player joint cache + aim state.
type AimState = {
	targetYaw: number,    -- gdzie chcemy żeby głowa była (z kamery dla self, z remote dla innych)
	targetPitch: number,
	currentYaw: number,   -- aktualnie zaaplikowane (lerp do target)
	currentPitch: number,
}
local localAim: AimState = { targetYaw = 0, targetPitch = 0, currentYaw = 0, currentPitch = 0 }
local remoteAim: { [Player]: AimState } = {}

-- Joint cache per player. Re-build na CharacterAdded.
type JointCache = {
	neck: Motor6D?,
	waist: Motor6D?,
	neckC0: CFrame?,     -- C0 SPOCZYNKOWY: punkt odniesienia obrotu (C0 = neckC0 * kąty) i reset
	waistC0: CFrame?,
}
local jointCache: { [Player]: JointCache } = {}

-- Throttle replikacji
local lastReplicateTime: number = 0
local lastSentYaw: number = 0
local lastSentPitch: number = 0
local headTrackWarnedR6: { [Player]: boolean } = {}

-- Forward declarations — funkcje zdefiniowane w HEAD TRACKING section ale wołane
-- z updateLoop (UPDATE LOOP section niżej). Lua resolve'uje lexykalnie przy parse,
-- więc bez forward declare `maybeReplicate()` byłby globalem = nil w runtime.
local maybeReplicate: () -> ()

-- Camera effects (Etap 4) — wszystkie sumują się w CameraOffset.
local landingDipStart: number = -1      -- os.clock() początku dip'u; -1 = nieaktywny
local landingDipIntensity: number = 0   -- amplituda aktualnego dip'u
local freefallStartY: number? = nil     -- HRP.Y przy wejściu w Freefall — do liczenia wysokości spadku
local shakeStart: number = -1           -- os.clock() początku shake'u; -1 = nieaktywny
local shakeIntensity: number = 0
local shakeDuration: number = 0
local stateChangedConn: RBXScriptConnection? = nil

-- Elastic camera rotation — lagged CFrame renderowany zamiast surowego (default camera).
local smoothedCam: CFrame? = nil
-- Kamera zza ramienia: bieżące (wygładzone) przesunięcie w bok + promień do ścian.
-- RespectCanCollide: lawa, liny haka i efekty nie mają kolizji, więc nie ściskają kadru.
local shoulderCurrent = 0
local shoulderRayParams = RaycastParams.new()
shoulderRayParams.FilterType = Enum.RaycastFilterType.Exclude
shoulderRayParams.IgnoreWater = true
shoulderRayParams.RespectCanCollide = true
local shoulderFilterChar: Model? = nil

-- FOV punch (bomba) — chwilowy additive offset FOV, decays do 0. Niezależny od sprint FOV.
local fovPunch: number = 0
-- Drżenie przy sprincie i przechył przy ruchu w bok (11.10) — stan wygładzania między klatkami.
local sprintShakeAmount = 0
local leanAngle = 0

-- Pasek staminy 3D (BillboardGui obok postaci, client-only). Template = ReplicatedStorage.StaminaBar.
local staminaBar: BillboardGui? = nil
local staminaFill: GuiObject? = nil
-- Baseline transparencji każdego GuiObject w pasku — fade in/out całego poddrzewa działa
-- niezależnie od tego, jak Kacper zaprojektuje bar (transp = 1 − (1 − baseline) × alpha).
local barBaseTransparency: { [GuiObject]: { bg: number, text: number?, img: number? } } = {}
-- UIStroke NIE jest GuiObject — bez osobnej listy czarna obramówka zostawałaby w pełni
-- widoczna, gdy reszta paska już wyblakła (pasek "znika", a ramka wisi w powietrzu).
local barStrokeBase: { [UIStroke]: number } = {}
local barAlpha: number = 0 -- 0 = ukryty, 1 = w pełni widoczny (ramp liniowy)
local barScale: UIScale? = nil -- UIScale "Anim" z template — elastic pop 0↔1
local barTween: Tween? = nil
local barShown: boolean = false -- ostatni stan widoczności (wykrywanie zbocza)
local barWarned: boolean = false

-- Czy sprint jest aktywny W TEJ KLATCE. Pasek ma wjeżdżać już na pierwszej klatce biegu,
-- zanim stamina zdąży spaść poniżej maksa — inaczej widać mignięcie na starcie sprintu.
local activeSprintNow: boolean = false

-- ====================================================================
-- HELPERS
-- ====================================================================

local function isRagdolled(): boolean
	local hum = currentHumanoid
	return hum ~= nil and RagdollState.isRagdolled(hum)
end

local function isAlive(): boolean
	return currentHumanoid ~= nil and currentHumanoid.Health > 0
end

local function isMoving(): boolean
	-- MoveDirection = znormalizowany wektor inputu (W/A/S/D / joystick). 0 = stoję.
	-- Sprawdzamy żeby nie drenować staminy gdy gracz stoi z trzymanym Shift.
	if not currentHumanoid then return false end
	return currentHumanoid.MoveDirection.Magnitude > 0.01
end

local function shouldActivelySprintThisFrame(): boolean
	-- "Aktywny sprint" = drenuje staminę + applikuje SprintSpeed.
	-- Wszystkie warunki muszą być spełnione.
	if not isSprintingHeld then return false end
	if exhausted then return false end
	if not isAlive() then return false end
	if isRagdolled() then return false end
	if not isMoving() then return false end
	if currentStamina <= 0 then return false end
	return true
end

-- ====================================================================
-- CAMERA EFFECTS (Etap 4)
-- ====================================================================

local function triggerLandingDip(fallHeight: number)
	if fallHeight < CFG_CAM.MinFallHeightForDip then return end
	local intensity = math.clamp(
		fallHeight * CFG_CAM.LandingDipPerStud,
		CFG_CAM.LandingDipMin,
		CFG_CAM.LandingDipMax
	)
	landingDipStart = os.clock()
	landingDipIntensity = intensity
end

local function spawnLandingDust(position: Vector3, fallHeight: number)
	-- Kurz przy twardym lądowaniu — LOKALNY VFX (feedback własnego ruchu, nie broadcast;
	-- ragdoll landing ma osobny server-side dust w BombService). Ilość skaluje ze spadkiem.
	local anchor = Instance.new("Part")
	anchor.Name = "LandingDustFX"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	game:GetService("Debris"):AddItem(anchor, 1.2)

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 190, 175), Color3.fromRGB(150, 140, 130))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 3.2),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.35, 0.6)
	dust.Rate = 0
	dust.Speed = NumberRange.new(4, 9)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Parent = anchor
	dust:Emit(math.clamp(math.floor(fallHeight * 0.8), 6, 16))
end

local function onHumanoidStateChanged(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	if not currentHumanoid then return end
	local char = currentHumanoid.Parent
	local hrp = char and (char :: Model):FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end

	if new == Enum.HumanoidStateType.Freefall then
		-- Zapisz Y na początku spadku — różnica z Y na Landed = wysokość spadku.
		freefallStartY = hrp.Position.Y
	elseif new == Enum.HumanoidStateType.Landed then
		if freefallStartY then
			local fallHeight = math.max(0, freefallStartY - hrp.Position.Y)
			triggerLandingDip(fallHeight)
			if fallHeight >= CFG_CAM.MinFallHeightForDip then
				spawnLandingDust(hrp.Position - Vector3.new(0, 2.6, 0), fallHeight)
			end
		end
		freefallStartY = nil
	elseif new == Enum.HumanoidStateType.Jumping then
		-- Jump też zaczyna "freefall" w sensie wysokości, ale Roblox emituje Freefall
		-- po wejściu w fazę spadkową. Reset tutaj żeby skok nie liczył się jako spadek.
		freefallStartY = nil
	end
end

local function computeLandingDipOffset(): number
	if landingDipStart < 0 then return 0 end
	local progress = (os.clock() - landingDipStart) / CFG_CAM.LandingDipDuration
	if progress >= 1 then
		landingDipStart = -1
		return 0
	end
	-- Sine pulse: 0 → -intensity → 0, peak na 50%.
	return -landingDipIntensity * math.sin(progress * math.pi)
end

local function computeShakeOffset(): Vector3
	if shakeStart < 0 then return Vector3.zero end
	local progress = (os.clock() - shakeStart) / shakeDuration
	if progress >= 1 then
		shakeStart = -1
		return Vector3.zero
	end
	-- Linear decay z random unit vec. Math.noise byłby ładniejszy ale random wystarczy.
	local decay = 1 - progress
	local mag = shakeIntensity * decay
	return Vector3.new(
		(math.random() * 2 - 1) * mag,
		(math.random() * 2 - 1) * mag,
		(math.random() * 2 - 1) * mag
	)
end

-- Public API: mnożnik prędkości chodu i sprintu pod kluczem `key`; nil zdejmuje mnożnik.
function MovementController.setSpeedFactor(key: string, factor: number?)
	speedFactors[key] = factor
end

function MovementController.screenShake(intensity: number, duration: number)
	-- Public API. BombService/LavaService etc. mogą wołać dla feedback'u.
	if type(intensity) ~= "number" or type(duration) ~= "number" then return end
	if duration <= 0 then return end
	intensity = math.clamp(intensity, 0, CFG_CAM.ShakeMaxIntensity)
	-- Jeśli już trwa shake — zachowaj większą intensity (overlap mocniejszego eventu).
	if shakeStart > 0 and shakeIntensity > intensity then return end
	shakeStart = os.clock()
	shakeIntensity = intensity
	shakeDuration = duration
end

function MovementController.fovKick(amount: number)
	-- Public API — chwilowy FOV punch (zoom out → wraca). Bomba woła przez Remotes.BombHit.
	if type(amount) ~= "number" then return end
	amount = math.clamp(amount, 0, CFG_CAM.HitReaction.FOVPunchMax)
	-- Overlap: zachowaj mocniejszy (drugi słabszy hit nie osłabia trwającego punchu).
	if amount > fovPunch then fovPunch = amount end
end

-- ====================================================================
-- INPUT
-- ====================================================================

local function tryStartSprint()
	-- gameProcessed check w callbacku (np. typing w chat).
	if not isAlive() then return end
	if exhausted then return end  -- musi naładować się do MinToResume
	isSprintingHeld = true
end

local function stopSprint()
	isSprintingHeld = false
end

-- ====================================================================
-- HUD
-- ====================================================================

-- Pasek staminy 3D (BillboardGui obok postaci — client-only, 2026-09-07; zastąpił tekstowy
-- StaminaLabel). Template robi Kacper w Studio (Figma → BillboardGui):
--   ReplicatedStorage.StaminaBar (BillboardGui) z pionowym `Fill` (GuiObject) zakotwiczonym
--   DOŁEM (AnchorPoint Y=1, Position Y=1), żeby zmniejszanie Size.Y.Scale opróżniało pasek
--   OD GÓRY. Kod ustawia tylko wysokość Fill (0..1) i jego kolor (zielony→żółty→czerwony);
--   tło/ramkę/obrys i pozycję obok postaci (StudsOffset) projektuje Kacper. Reaktywny kolor
--   ⇒ Fill ma być tintowalny: jednolity Frame albo BIAŁY ImageLabel.
-- Client-only: klon → PlayerGui + Adornee = HRP (instancja tworzona lokalnie nie replikuje
-- się w górę, więc inni gracza paska nie widzą).

local function captureBarBaselines(bar: BillboardGui)
	table.clear(barBaseTransparency)
	table.clear(barStrokeBase)
	for _, d in ipairs(bar:GetDescendants()) do
		if d:IsA("GuiObject") then
			local entry: { bg: number, text: number?, img: number? } = { bg = d.BackgroundTransparency }
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				entry.text = (d :: any).TextTransparency
			end
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then
				entry.img = (d :: any).ImageTransparency
			end
			barBaseTransparency[d] = entry
		elseif d:IsA("UIStroke") then
			barStrokeBase[d] = d.Transparency
		end
	end
end

local function setupStaminaBar()
	-- Yield-safe (task.spawn z init). Template dostarcza Kacper — czekamy z timeoutem,
	-- żeby brak template'a nie zawiesił kontrolera (tylko ostrzeżenie, reszta ruchu działa).
	local template = ReplicatedStorage:WaitForChild("StaminaBar", 15)
	if not template or not template:IsA("BillboardGui") then
		if not barWarned then
			barWarned = true
			warn("[Movement] brak ReplicatedStorage.StaminaBar (BillboardGui) — pasek staminy nieaktywny. " ..
				"Postaw BillboardGui 'StaminaBar' z pionowym elementem 'Fill'.")
		end
		return
	end

	local pg = localPlayer:WaitForChild("PlayerGui")
	local bar = template:Clone() :: BillboardGui
	local fill = bar:FindFirstChild("Fill", true)
	if not (fill and fill:IsA("GuiObject")) then
		if not barWarned then
			barWarned = true
			warn("[Movement] StaminaBar nie ma elementu 'Fill' (GuiObject) — pasek nieaktywny.")
		end
		bar:Destroy()
		return
	end

	captureBarBaselines(bar)
	-- UIScale napędza elastic pop. Brak = pasek działa dalej, tylko bez animacji skali.
	local scaleObj = bar:FindFirstChildWhichIsA("UIScale", true)
	if scaleObj then
		scaleObj.Scale = 0
		barScale = scaleObj
	end
	barAlpha = 0
	barShown = false
	bar.Enabled = false -- update loop włączy przy sprincie/regeneracji
	-- Klon tworzymy RAZ na sesję, a referencję trzymamy do końca — przy domyślnym
	-- ResetOnSpawn = true pierwszy respawn kasowałby go z PlayerGui i pasek znikałby na
	-- zawsze (zasada 10 dotyczy każdego GUI klonowanego do PlayerGui, nie tylko HUD).
	bar.ResetOnSpawn = false
	bar.Parent = pg
	staminaBar = bar
	staminaFill = fill :: GuiObject
end

-- Fade całego poddrzewa: transp = 1 − (1 − baseline) × alpha (0 = ukryty, 1 = pełny wygląd Kacpra).
local function applyBarAlpha()
	for obj, base in pairs(barBaseTransparency) do
		if obj.Parent then
			obj.BackgroundTransparency = 1 - (1 - base.bg) * barAlpha
			if base.text ~= nil then
				(obj :: any).TextTransparency = 1 - (1 - (base.text :: number)) * barAlpha
			end
			if base.img ~= nil then
				(obj :: any).ImageTransparency = 1 - (1 - (base.img :: number)) * barAlpha
			end
		end
	end
	for stroke, base in pairs(barStrokeBase) do
		if stroke.Parent then
			stroke.Transparency = 1 - (1 - base) * barAlpha
		end
	end
end

-- Interpolacja po KOLE BARW (HSV), nie po RGB. `Color3:Lerp` miesza kanały liniowo, a
-- niebieski i żółty są barwami DOPEŁNIAJĄCYMI — ich średnia RGB to ~(155,172,155), czyli
-- szarość. Stąd "biały" pasek w połowie. Po HSV lecimy blue→cyan→zielony→żółty, cały czas
-- nasycone, i przy okazji wygląda to jak naturalna skala energii.
local function lerpHSV(a: Color3, b: Color3, t: number): Color3
	local h1, s1, v1 = a:ToHSV()
	local h2, s2, v2 = b:ToHSV()
	-- Najkrótsza droga po kole barw — bez tego blue→yellow poszłoby przez purpurę i czerwień.
	local dh = h2 - h1
	if dh > 0.5 then
		dh -= 1
	elseif dh < -0.5 then
		dh += 1
	end
	return Color3.fromHSV((h1 + dh * t) % 1, s1 + (s2 - s1) * t, v1 + (v2 - v1) * t)
end

-- Niebieski (pełna) → żółty (połowa) → czerwony (pusta), dwa odcinki wokół 0.5.
local function staminaColor(frac: number): Color3
	if frac >= 0.5 then
		return lerpHSV(CFG_BAR.ColorMid, CFG_BAR.ColorFull, (frac - 0.5) * 2)
	end
	return lerpHSV(CFG_BAR.ColorLow, CFG_BAR.ColorMid, frac * 2)
end

local BAR_FULL_EPSILON = 0.999 -- powyżej = "pełna" → chowaj

local function updateStaminaBar(dt: number)
	local bar = staminaBar
	local fill = staminaFill
	if not bar or not fill then return end

	-- Re-adorn co klatkę (tanie) — obsługuje respawn bez osobnego hooka: nowy HRP,
	-- nowy adornee. Brak character = adornee nil = billboard po prostu nie renderuje.
	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		if bar.Adornee ~= hrp then
			bar.Adornee = hrp
		end
	end

	local frac = math.clamp(currentStamina / CFG_STAM.Max, 0, 1)

	-- Widoczny WYŁĄCZNIE przy sprincie albo gdy stamina się odbudowuje (< max).
	-- `activeSprintNow` łapie pierwszą klatkę biegu, zanim stamina zdąży spaść.
	local wantVisible = isAlive() and (activeSprintNow or frac < BAR_FULL_EPSILON)

	-- ZBOCZE widoczności → elastic pop na UIScale. Tween startuje tylko przy ZMIANIE
	-- stanu, nie co klatkę — inaczej restartowałby się w kółko i nigdy nie doszedł końca.
	if wantVisible ~= barShown then
		barShown = wantVisible
		if wantVisible and not bar.Enabled then
			bar.Enabled = true -- włącz ZANIM ruszy animacja, inaczej pop jest niewidoczny
		end
		local s = barScale
		if s then
			if barTween then
				barTween:Cancel()
				barTween = nil
			end
			local info = if wantVisible
				then TweenInfo.new(CFG_BAR.PopInTime, CFG_BAR.PopInStyle, Enum.EasingDirection.Out)
				else TweenInfo.new(CFG_BAR.PopOutTime, CFG_BAR.PopOutStyle, Enum.EasingDirection.In)
			local tw = TweenService:Create(s, info, { Scale = if wantVisible then 1 else 0 })
			barTween = tw
			tw:Play()
		end
	end

	-- Fade LINIOWY — trwa dokładnie FadeIn/FadeOutTime. Wykładniczy lerp ciągnął się
	-- kilka razy dłużej niż liczba w Configu i pasek "wisiał" długo po sprincie.
	local fadeTime = if wantVisible then CFG_BAR.FadeInTime else CFG_BAR.FadeOutTime
	local step = if fadeTime > 0 then dt / fadeTime else 1
	barAlpha = math.clamp(barAlpha + (if wantVisible then step else -step), 0, 1)

	-- Obrys proporcjonalny do paska (11.10). Pasek ma rozmiar w studach, więc rośnie i maleje
	-- z ekranem i odległością kamery, a `UIStroke.Thickness` jest w PIKSELACH — przy stałej
	-- wartości obrys był za cienki na dużym monitorze i za gruby na telefonie. Szerokość
	-- billboardu (nie `Root`), bo na `Root` siedzi UIScale wskoku, który i tak mnoży obrys.
	if bar.Enabled then
		local thickness = math.max(1, bar.AbsoluteSize.X * CFG_BAR.BorderToWidth)
		for stroke in pairs(barStrokeBase) do
			stroke.Thickness = thickness
		end
	end

	-- W pełni schowany → wyłącz render (zero kosztu billboardu przy pełnej staminie).
	if not wantVisible and barAlpha <= 0 then
		if bar.Enabled then
			bar.Enabled = false
		end
		return
	end

	-- Wysokość wypełnienia: X bez zmian, Y.Scale = frac (Fill zakotwiczony dołem = opróżnia od góry).
	local sz = fill.Size
	fill.Size = UDim2.new(sz.X.Scale, sz.X.Offset, frac, 0)

	-- Reaktywny kolor — na ImageLabel tint przez ImageColor3, inaczej BackgroundColor3.
	local col = staminaColor(frac)
	if fill:IsA("ImageLabel") or fill:IsA("ImageButton") then
		(fill :: any).ImageColor3 = col
	else
		fill.BackgroundColor3 = col
	end

	applyBarAlpha()
end

-- ====================================================================
-- UPDATE LOOP
-- ====================================================================

local function updateLoop(dt: number)
	if not currentHumanoid then
		activeSprintNow = false
		updateStaminaBar(dt)
		return
	end

	-- Dead character → cleanup sprint state (lerp WalkSpeed do bazowego, ale i tak humanoid
	-- nie żyje). State zostaje, reset dopiero na CharacterAdded (nowy respawn).
	if not isAlive() then
		isSprintingHeld = false
		activeSprintNow = false
		updateStaminaBar(dt)
		return
	end

	local activeSprint = shouldActivelySprintThisFrame()
	activeSprintNow = activeSprint

	-- Stamina drain / regen
	if activeSprint then
		currentStamina = math.max(0, currentStamina - CFG_STAM.DrainRate * dt)
		lastSprintActiveTime = os.clock()
		if currentStamina <= 0 then
			-- Wyczerpanie → force release + flag exhausted. Gracz musi puścić i poczekać
			-- aż stamina się naładuje do MinToResume zanim shift znów zadziała.
			exhausted = true
			isSprintingHeld = false
		end
	else
		-- Regen po RegenDelay od ostatniego aktywnego sprintu (anti-spam shift).
		-- WAŻNE: regen działa też podczas ragdoll'u (CLAUDE.md zasada 11) — gracz leży,
		-- odzyskuje siłę. Inaczej ragdoll = double-kara (zostałeś rzucony + nie regeneuje).
		if os.clock() - lastSprintActiveTime >= CFG_STAM.RegenDelay then
			currentStamina = math.min(CFG_STAM.Max, currentStamina + CFG_STAM.RegenRate * dt)
		end
		-- Re-enable sprint po wyczerpaniu (musi naładować do MinToResume).
		if exhausted and currentStamina >= CFG_STAM.MinToResume then
			exhausted = false
		end
	end

	-- WalkSpeed lerp (framerate-independent). alpha = dt/lerpTime z clampem.
	-- Snap do target gdy bardzo blisko (uniknięcie infinitesimal residuum).
	local targetSpeed = (activeSprint and CFG.SprintSpeed or CFG.WalkSpeed) * speedFactor()
	local alpha = math.clamp(dt / CFG.SpeedLerpTime, 0, 1)
	currentWalkSpeed = currentWalkSpeed + (targetSpeed - currentWalkSpeed) * alpha
	if math.abs(currentWalkSpeed - targetSpeed) < 0.05 then
		currentWalkSpeed = targetSpeed
	end
	-- Nie nadpisuj WalkSpeed podczas ragdoll — i tak nie działa, ale unikamy
	-- niepotrzebnej replikacji do serwera (każda zmiana WalkSpeed = RemoteUpdate).
	if not isRagdolled() then
		currentHumanoid.WalkSpeed = currentWalkSpeed
	end

	-- Dynamic FOV (Etap 3): sprint → SprintFOV, else → BaseFOV. Lerp ten sam pattern.
	-- Workspace.CurrentCamera może być nil bardzo krótko przy charakter swap — guard.
	local camera = Workspace.CurrentCamera
	if camera then
		local targetFOV = activeSprint and CFG.SprintFOV or CFG.BaseFOV
		local fovAlpha = math.clamp(dt / CFG.FOVLerpTime, 0, 1)
		currentFOV = currentFOV + (targetFOV - currentFOV) * fovAlpha
		if math.abs(currentFOV - targetFOV) < 0.05 then
			currentFOV = targetFOV
		end
		-- FOV punch (bomba) — additive, exponential decay do 0. Działa też w ragdollu
		-- (FieldOfView nie jest gate'owane isRagdolled, w przeciwieństwie do CameraOffset).
		if fovPunch > 0.01 then
			fovPunch = fovPunch * math.exp(-CFG_CAM.HitReaction.FOVPunchDecay * dt)
			if fovPunch < 0.05 then fovPunch = 0 end
		end
		camera.FieldOfView = currentFOV + fovPunch
	end

	-- Camera effects (Etap 4): landing dip → Humanoid.CameraOffset. Screen shake NIE tutaj —
	-- przeniesiony do camera render step (CFrame), żeby działał TEŻ podczas ragdollu (wtedy
	-- CameraOffset jest pomijany, a bomba = ragdoll, więc shake z bomby by nie było widać).
	-- Sprint bob USUNIĘTY (Kacper nie chciał bujania przy chodzeniu).
	local dipY = computeLandingDipOffset()

	-- NIE aplikuj CameraOffset podczas ragdoll'u — toolbox może też w niego pisać, konflikt.
	if not isRagdolled() then
		currentHumanoid.CameraOffset = Vector3.new(0, dipY, 0)
	end

	-- Head tracking replikacja (Etap 5) — throttled ~10Hz + epsilon skip.
	-- maybeReplicate() bezpieczne nawet bez character (sprawdza w środku).
	maybeReplicate()

	updateStaminaBar(dt)
end

-- ====================================================================
-- HEAD TRACKING (Etap 5)
-- ====================================================================

local function findMotor6DBetween(character: Model, nameA: string, nameB: string): Motor6D?
	-- Szukamy Motor6D łączącego dwa parts, niezależnie gdzie jest parented i jak nazwany.
	-- Klasyczny R15: Neck (Motor6D na Head), Waist (Motor6D na UpperTorso).
	-- Nowy R15 (2024+, CLAUDE.md zasada 11): BallSocketConstraint + AnimationConstraint
	-- zamiast Motor6D — nic nie znajdziemy = silent skip.
	-- Inne rigi (custom, toolbox-modded): Motor6D może być inaczej parented/nazwany.
	local a = character:FindFirstChild(nameA)
	local b = character:FindFirstChild(nameB)
	if not a or not b then return nil end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			local p0, p1 = descendant.Part0, descendant.Part1
			if (p0 == a and p1 == b) or (p0 == b and p1 == a) then
				return descendant
			end
		end
	end
	return nil
end

local function asyncCacheJoints(player: Player, character: Model)
	-- CharacterAdded fire'uje gdy character ma Humanoid, ale Head/UpperTorso replikują się
	-- chwilę później. Czekamy async (WaitForChild z timeout) i szukamy Motor6Dów po replikacji.
	task.spawn(function()
		local head = character:WaitForChild("Head", 5)
		local upper = character:WaitForChild("UpperTorso", 5)
		if player.Character ~= character then return end

		if not head and not upper then
			-- R6 lub character zniszczony — bez warn'a, nie ma sensu.
			return
		end

		-- Drobny dodatkowy wait żeby Motor6Dy (jeśli istnieją) zdążyły się dopodpiąć
		-- między body parts. Na praktyce <100ms wystarczy.
		task.wait(0.2)
		if player.Character ~= character then return end

		local cache: JointCache = {
			neck = findMotor6DBetween(character, "Head", "UpperTorso"),
			waist = findMotor6DBetween(character, "UpperTorso", "LowerTorso"),
			neckC0 = nil,
			waistC0 = nil,
		}
		if cache.neck then cache.neckC0 = cache.neck.C0 end
		if cache.waist then cache.waistC0 = cache.waist.C0 end

		if not cache.neck and not cache.waist then
			-- Nowy R15 rig (BallSocketConstraint + AnimationConstraint, brak Motor6D).
			-- print zamiast warn — to normalna sytuacja dla nowego avatara, nie błąd.
			-- Head aim po prostu nieaktywne dla tego characteru (cała reszta movementu OK).
			if not headTrackWarnedR6[player] then
				headTrackWarnedR6[player] = true
				print(("[HeadTrack] %s — brak Motor6D Neck/Waist (nowy R15 rig). Head aim skip dla tego avatara."):format(player.Name))
			end
			return
		end

		jointCache[player] = cache
	end)
end

local function ensureJointCache(player: Player): JointCache?
	-- Tylko czytanie cache'u (asyncCacheJoints buduje go w tle przy każdym CharacterAdded).
	-- Brak synchronicznego lookup'u = brak false-positive warnów w render loop race window.
	local cached = jointCache[player]
	if not cached then return nil end
	-- Validate że joint nadal istnieje (mógł zostać zniszczony po unhook'u characteru).
	if cached.neck and not cached.neck.Parent then cached.neck = nil end
	if cached.waist and not cached.waist.Parent then cached.waist = nil end
	if not cached.neck and not cached.waist then
		jointCache[player] = nil
		return nil
	end
	return cached
end

local function isCharacterRagdolled(character: Model): boolean
	-- W trakcie ragdoll'u NIE obracamy stawów (BallSocketConstraints driveją fizykę,
	-- nasze write'y by się fightowały z constraint physics → dziwne wykrzywienia).
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	return hum.Health <= 0 or RagdollState.isRagdolled(hum)
end

-- ⚠️ OBRÓT IDZIE PRZEZ `C0`, NIE PRZEZ `Transform` (2026-09-23). Pierwsza wersja mnożyła
-- `Motor6D.Transform` w RenderStepped, zakładając, że animator działa w RenderStep z priorytetem
-- `Character` i wystarczy być po nim. Nie działa: `RenderPriority.Character` to tylko numer
-- kolejki dla skryptów, a animator nadpisuje `Transform` w całości we własnej fazie klatki.
-- Skutek: head tracking NIE DZIAŁAŁ NIGDY, choć stawy były znajdowane (w logach nie było ani
-- jednego „brak Motor6D"), i przez miesiące figurował w CLAUDE.md jako gotowy.
-- `C0` to statyczna część stawu — animator go nie dotyka — więc obrót od zapisanego C0
-- spoczynkowego jest odporny na to, JAK dokładnie animator nadpisuje `Transform`. Animacja
-- dalej gra, bo `Transform` zostaje w łańcuchu: Part0 * C0 * Transform * C1⁻¹.
local function restoreRestC0(cache: JointCache)
	if cache.neck and cache.neckC0 then cache.neck.C0 = cache.neckC0 end
	if cache.waist and cache.waistC0 then cache.waist.C0 = cache.waistC0 end
end

local function applyAim(player: Player, character: Model, yaw: number, pitch: number)
	local cache = ensureJointCache(player)
	if not cache then return end
	if isCharacterRagdolled(character) then
		-- `C0`, w odróżnieniu od `Transform`, NIE resetuje się sam — bez tego głowa leżałaby
		-- wykręcona o ostatni kąt przez cały ragdoll.
		restoreRestC0(cache)
		return
	end

	-- Pitch wyłącznie na neck. Yaw rozdzielamy: WaistYawRatio idzie na waist (talia
	-- skręca lekko za kamerą), reszta na neck.
	local waistYaw = yaw * CFG_HT.WaistYawRatio
	local neckYaw = yaw - waistYaw

	-- Zawsze OD C0 SPOCZYNKOWEGO, nigdy od bieżącego — inaczej obrót kumulowałby się co
	-- klatkę i głowa kręciłaby się w kółko.
	if cache.waist and cache.waistC0 then
		cache.waist.C0 = cache.waistC0 * CFrame.Angles(0, waistYaw, 0)
	end
	if cache.neck and cache.neckC0 then
		-- Znaki na tym rigu (C0 bez rotacji, przód = −Z): dodatnie rx podnosi przód głowy,
		-- więc kamera w dół (pitch < 0) → głowa w dół; dodatni yaw skręca przód w −X, czyli
		-- w lewo, zgodnie z `computeLocalAimFromCamera`. Sprawdzone rachunkiem 2026-09-23,
		-- NIE okiem — wcześniej obrót nigdy nie był widoczny. Odwrotnie w grze = zmienić znak.
		cache.neck.C0 = cache.neckC0 * CFrame.Angles(pitch, neckYaw, 0)
	end
end

local function computeLocalAimFromCamera()
	-- Liczymy desired yaw (świat-space kąt między forward postaci a kamery) +
	-- desired pitch (vertical kąt kamery).
	if not currentCharacter then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local hrp = currentCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end

	local camLook = camera.CFrame.LookVector
	local charForward = hrp.CFrame.LookVector

	-- Yaw: signed kąt między char forward i cam look, oba projected do XZ.
	local camH = Vector3.new(camLook.X, 0, camLook.Z)
	local charH = Vector3.new(charForward.X, 0, charForward.Z)
	if camH.Magnitude < 1e-4 or charH.Magnitude < 1e-4 then
		-- Kamera prawie pionowo (oba projekty są 0) — zostaw current.
		return
	end
	camH = camH.Unit
	charH = charH.Unit
	local cross = charH:Cross(camH).Y  -- + lewo / - prawo (lub odwrotnie zal. od conv.)
	local dot = math.clamp(charH:Dot(camH), -1, 1)
	local yaw = math.atan2(cross, dot)

	-- Pitch: vertical angle of camera. asin(camLook.Y).
	local pitch = math.asin(math.clamp(camLook.Y, -1, 1))

	-- Clamp do max kątów. Lerp do current dzieje się w renderStep.
	localAim.targetYaw = math.clamp(yaw, -MAX_YAW_RAD, MAX_YAW_RAD)
	localAim.targetPitch = math.clamp(pitch, -MAX_PITCH_RAD, MAX_PITCH_RAD)
end

local function lerpAimState(state: AimState, dt: number)
	-- Framerate-independent lerp: alpha = 1 - exp(-LerpSpeed * dt). Numerically stable
	-- nawet przy bardzo małym dt, daje czystą eksponencjalną decay.
	local alpha = 1 - math.exp(-CFG_HT.LerpSpeed * dt)
	state.currentYaw = state.currentYaw + (state.targetYaw - state.currentYaw) * alpha
	state.currentPitch = state.currentPitch + (state.targetPitch - state.currentPitch) * alpha
end

local function onRenderStepHeadAim(dt: number)
	-- Liczy target dla local (z kamery) + lerpuje wszystkich + aplikuje Transform.
	-- Priorytet Character+1 = PO kamerze (Camera+1), więc głowa czyta już wygładzoną kamerę.
	-- (NIE „po animatorze" — animator nie jest w kolejce RenderStep; patrz applyAim.)
	computeLocalAimFromCamera()
	lerpAimState(localAim, dt)
	-- Apply local (sami też widzimy swoją głowę kręcącą się w 3rd person — immersja).
	if currentCharacter then
		applyAim(localPlayer, currentCharacter, localAim.currentYaw, localAim.currentPitch)
	end
	-- Apply remote players
	for player, state in pairs(remoteAim) do
		lerpAimState(state, dt)
		local char = player.Character
		if char then
			applyAim(player, char, state.currentYaw, state.currentPitch)
		end
	end
end

maybeReplicate = function()
	-- Wywoływane z głównego Heartbeat loop'u (już istnieje). Throttle ~10Hz.
	-- Przypisanie (nie `local function`) bo forward-declared powyżej.
	local now = os.clock()
	if now - lastReplicateTime < REPLICATE_INTERVAL then return end
	-- Skip jeśli zmiana poniżej epsilon (oszczędza bandwidth przy stojącym graczu).
	if math.abs(lastSentYaw - localAim.targetYaw) < CFG_HT.ReplicateEpsilon
		and math.abs(lastSentPitch - localAim.targetPitch) < CFG_HT.ReplicateEpsilon then
		return
	end
	lastReplicateTime = now
	lastSentYaw = localAim.targetYaw
	lastSentPitch = localAim.targetPitch
	Remotes.HeadAim:FireServer(localAim.targetYaw, localAim.targetPitch)
end

local function onRemoteHeadAim(sourcePlayer: Player, yaw: number, pitch: number)
	-- Echo własnych danych nie powinien się stać (server skipuje sendera) ale guard.
	if sourcePlayer == localPlayer then return end
	local state = remoteAim[sourcePlayer]
	if not state then
		state = { targetYaw = 0, targetPitch = 0, currentYaw = 0, currentPitch = 0 }
		remoteAim[sourcePlayer] = state
	end
	state.targetYaw = yaw
	state.targetPitch = pitch
end

local function onPlayerRemoving(player: Player)
	remoteAim[player] = nil
	jointCache[player] = nil
	headTrackWarnedR6[player] = nil
end

-- ====================================================================
-- CHARACTER LIFECYCLE
-- ====================================================================

local function onCharacterAdded(character: Model)
	currentCharacter = character

	-- Cleanup poprzedniego StateChanged connection (poprzedni character mógł go zostawić).
	if stateChangedConn then
		stateChangedConn:Disconnect()
		stateChangedConn = nil
	end

	currentHumanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?

	-- Fresh respawn = pełna stamina, czysty stan sprintu, FOV do bazy, camera effects reset.
	currentStamina = CFG_STAM.Max
	isSprintingHeld = false
	exhausted = false
	lastSprintActiveTime = 0
	currentWalkSpeed = CFG.WalkSpeed
	currentFOV = CFG.BaseFOV
	landingDipStart = -1
	landingDipIntensity = 0
	freefallStartY = nil
	shakeStart = -1
	fovPunch = 0
	smoothedCam = nil  -- nowy character = kamera reinicjalizuje się (snap, bez swoopu)
	-- Head tracking: invalidate joint cache (nowy character = nowe Motor6D) + reset aim state.
	jointCache[localPlayer] = nil
	localAim.targetYaw = 0
	localAim.targetPitch = 0
	localAim.currentYaw = 0
	localAim.currentPitch = 0
	lastSentYaw = 0
	lastSentPitch = 0

	if currentHumanoid then
		currentHumanoid.WalkSpeed = CFG.WalkSpeed
		currentHumanoid.CameraOffset = Vector3.zero
		-- Hook landing detection: Freefall → zapamiętaj Y, Landed → policz fall + dip.
		stateChangedConn = currentHumanoid.StateChanged:Connect(onHumanoidStateChanged)
	end
	-- Async pre-cache joints (Head/UpperTorso + Motor6D mogą jeszcze nie być replicated).
	asyncCacheJoints(localPlayer, character)
	-- Pasek staminy re-adornuje się sam w updateLoop; po respawnie stamina = max → schowany.
end

local function setupRemotePlayerHeadTrack(player: Player)
	-- Lokalny obsługujemy w onCharacterAdded (z resztą stanu); tu tylko remote players.
	if player == localPlayer then return end
	player.CharacterAdded:Connect(function(character)
		jointCache[player] = nil
		asyncCacheJoints(player, character)
	end)
	if player.Character then
		asyncCacheJoints(player, player.Character)
	end
end

-- ====================================================================
-- CAMERA
-- ====================================================================

-- Czy przez to wolno patrzeć kamerą. Postacie i party półprzezroczyste (szyby) przepuszczamy —
-- tak samo robi tryb `Zoom` Robloxa; inaczej kamera kleiłaby się do szyby albo do kolegi obok.
local function isSeeThrough(inst: Instance): boolean
	if inst:IsA("BasePart") and inst.Transparency >= CFG_CAM.ShoulderOffset.SeeThroughTransparency then
		return true
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Filtr promieni kamery (własna postać) podmieniany tylko przy zmianie postaci — bez alokacji
-- tablicy co klatkę.
local function refreshCameraFilter()
	if shoulderFilterChar ~= currentCharacter then
		shoulderFilterChar = currentCharacter
		shoulderRayParams.FilterDescendantsInstances = if currentCharacter then { currentCharacter } else {}
	end
end

-- Promień dla kamery: dystans do pierwszej przeszkody, przez którą NIE da się patrzeć, albo nil.
-- Przezroczyste trafienia przeskakujemy (maks. 4), zamiast kończyć na nich promień.
local function castForCamera(origin: Vector3, dir: Vector3): number?
	local total = dir.Magnitude
	if total < 1e-3 then return nil end
	local unit = dir / total
	local travelled = 0
	for _ = 1, 4 do
		local hit = Workspace:Raycast(origin + unit * travelled, unit * (total - travelled), shoulderRayParams)
		if not hit then return nil end
		local d = travelled + hit.Distance
		if not isSeeThrough(hit.Instance) then return d end
		travelled = d + 0.05
		if travelled >= total then return nil end
	end
	return nil
end

-- Kamera zza ramienia (Config.Movement.Camera.ShoulderOffset). Zwraca przesunięcie
-- w układzie kamery (X = w prawo); `shoulderCurrent` trzyma bieżącą, wygładzoną wartość.
local function computeShoulderOffset(camera: Camera, base: CFrame, dt: number): Vector3
	local so = CFG_CAM.ShoulderOffset
	if not (so and so.Enabled) or so.Side == 0 then
		shoulderCurrent = 0
		return Vector3.zero
	end

	local target = so.Side

	-- Ściana ZA PLECAMI: tryb `Zoom` Robloxa przysuwa wtedy kamerę do postaci, a pełne
	-- przesunięcie z bliska dałoby widok z boku głowy — maleje więc razem z odległością.
	local dist = (camera.Focus.Position - base.Position).Magnitude
	target *= math.clamp(dist / so.FullOffsetDistance, 0, 1)

	-- Ściana Z BOKU: przesunięcie kończy się przed nią (kamera zostaje na swoim dystansie,
	-- tylko mniej wychodzi w bok). Narożniki łapie dopiero `keepLineOfSight`.
	if math.abs(target) > 0.01 then
		local reach = math.abs(target) + so.WallMargin
		local hitDist = castForCamera(base.Position, base.RightVector * (math.sign(target) * reach))
		if hitDist then
			local free = math.max(0, hitDist - so.WallMargin)
			target = math.sign(target) * math.min(math.abs(target), free)
		end
	end

	local alpha = 1 - math.exp(-so.LerpSpeed * dt)
	shoulderCurrent += (target - shoulderCurrent) * alpha
	return Vector3.new(shoulderCurrent, 0, 0)
end

-- ⚠️ OSTATNIA LINIA OBRONY PRZED X-RAYEM: między głową postaci a kamerą NIE może stać ściana.
-- Tryb `Zoom` Robloxa pilnuje tego wyłącznie dla kamery PRZED naszymi efektami, a oba potrafią
-- wyprowadzić ją za przeszkodę: przesunięcie w bok — za narożnik, wygładzanie przy szybkim
-- obrocie — po cięciwie przez róg. Jeden promień OD GŁOWY łapie oba: głowa zawsze stoi
-- w wolnej przestrzeni, więc promień nie startuje w ścianie (a w takiej promień niczego nie
-- widzi — boczny promień z pozycji kamery nie miał tej gwarancji).
-- Zgłoszenie Kacpra 2026-09-23: „kamera ma się zatrzymywać na ścianie, a nie x-ray".
local function keepLineOfSight(camera: Camera, cf: CFrame): CFrame
	local focus = camera.Focus.Position
	local toCam = cf.Position - focus
	local dist = toCam.Magnitude
	if dist < 0.05 then return cf end
	local hitDist = castForCamera(focus, toCam)
	if not hitDist then return cf end
	local safe = math.max(0, hitDist - CFG_CAM.ShoulderOffset.WallMargin)
	return CFrame.new(focus + toCam / dist * safe) * cf.Rotation
end

-- Lekkie drżenie przy SPRINCIE na ziemi (11.10). Płynny szum (`math.noise`), nie losowe skoki
-- jak `computeShakeOffset` — to ma być rytm biegu, nie trafienie. Wchodzi i schodzi przez
-- `FadeTime`, więc start/koniec sprintu nie szarpie kamerą.
local function computeSprintShake(dt: number): Vector3
	local cfg = CFG_CAM.SprintShake
	local hum = currentHumanoid
	local want = activeSprintNow and hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
		and hum.MoveDirection.Magnitude > 0.1 and not isRagdolled()
	local k = if cfg.FadeTime > 0 then math.clamp(dt / cfg.FadeTime, 0, 1) else 1
	sprintShakeAmount += ((if want then 1 else 0) - sprintShakeAmount) * k
	if sprintShakeAmount < 0.001 or cfg.Amplitude <= 0 then
		sprintShakeAmount = if want then sprintShakeAmount else 0
		return Vector3.zero
	end
	local t = os.clock() * cfg.Frequency
	local a = cfg.Amplitude * sprintShakeAmount * 2 -- noise ∈ ~[-0.5, 0.5]
	return Vector3.new(math.noise(t, 1.7) * a, math.noise(4.3, t) * a, 0)
end

-- Przechył przy ruchu w BOK względem kamery (11.10): w prawo → kamera kładzie się w prawo
-- (ujemny kąt wokół osi patrzenia). Pełny przy prędkości sprintu, w ragdollu / po śmierci 0.
local function computeLean(camera: Camera, dt: number): number
	local cfg = CFG_CAM.Lean
	local target = 0
	local hum = currentHumanoid
	local root = hum and hum.RootPart
	if cfg.MaxDegrees > 0 and root and isAlive() and not isRagdolled() then
		local vel = root.AssemblyLinearVelocity
		local right = camera.CFrame.RightVector
		local lateral = vel.X * right.X + vel.Z * right.Z
		target = -math.clamp(lateral / CFG.SprintSpeed, -1, 1) * math.rad(cfg.MaxDegrees)
	end
	leanAngle += (target - leanAngle) * (1 - math.exp(-cfg.Speed * dt))
	if math.abs(leanAngle) < 1e-4 then
		leanAngle = 0
	end
	return leanAngle
end

local function onRenderStepCamera(dt: number)
	-- Trzy efekty na finalnym CFrame kamery, liczone PO default camera (priorytet Camera+1):
	--   1. Elastic rotation smoothing — renderujemy lagged wersję (kamera dogania mysz).
	--   2. Kamera zza ramienia — przesunięcie w bok (Config ShoulderOffset).
	--   3. Screen shake — camera-local jitter, DZIAŁA W RAGDOLLU (nie zależy od CameraOffset).
	-- Na końcu `keepLineOfSight`: żaden z efektów nie może wyprowadzić kamery za ścianę.
	-- Default camera nie czyta z powrotem camera.CFrame, więc override nie psuje jej stanu
	-- (mysz śledzona 1:1, my modyfikujemy tylko co widać).
	local camera = Workspace.CurrentCamera
	if not camera then
		smoothedCam = nil
		return
	end
	-- Scriptable = inny system kamery (cutscene itp.) — nie ruszamy w ogóle.
	if camera.CameraType == Enum.CameraType.Scriptable then
		smoothedCam = nil
		-- Po wyjściu ze sklepu przesunięcie wjeżdża płynnie od zera, zamiast skoczyć.
		shoulderCurrent = 0
		return
	end

	refreshCameraFilter()

	local raw = camera.CFrame
	local base = raw

	-- 1. Rotation smoothing (opcjonalne).
	local cfg = CFG_CAM.RotationSmoothing
	if cfg.Enabled then
		local prev = smoothedCam
		if not prev or (raw.Position - prev.Position).Magnitude > cfg.SnapDistance then
			-- Pierwsza klatka lub duży skok (respawn/teleport) — snap bez swoopu.
			smoothedCam = raw
			base = raw
		else
			local alpha = 1 - math.exp(-cfg.Speed * dt)
			base = prev:Lerp(raw, alpha)
			smoothedCam = base
		end
	end

	-- 2. Kamera zza ramienia. Liczona od WYGŁADZONEJ bazy, ale NIE wchodzi do `smoothedCam`:
	--    wygładzanie lerpuje czystą kamerę Robloxa, a przesunięcie nakładamy na wynik.
	--    Inaczej przesunięcie i lerp karmiłyby się nawzajem co klatkę.
	local shoulder = computeShoulderOffset(camera, base, dt)

	-- 3. Shake — camera-local translacja (X=right, Y=up, Z=back). Zero gdy nieaktywny.
	--    + drżenie przy sprincie (11.10).
	local offset = shoulder + computeShakeOffset() + computeSprintShake(dt)
	-- 4. Przechył przy ruchu w bok (11.10) — obrót wokół osi patrzenia.
	local roll = computeLean(camera, dt)

	-- Ustaw CFrame tylko gdy faktycznie coś modyfikujemy — inaczej zostaw default camera
	-- w spokoju (mniej redundantnych setów, brak konfliktu gdy efekty wyłączone/idle).
	-- Każda NASZA kamera przechodzi przez `keepLineOfSight` — to on gwarantuje brak x-raya.
	if cfg.Enabled or offset ~= Vector3.zero or roll ~= 0 then
		local cf = if offset ~= Vector3.zero then base * CFrame.new(offset) else base
		if roll ~= 0 then
			cf *= CFrame.Angles(0, 0, roll)
		end
		camera.CFrame = keepLineOfSight(camera, cf)
	end
end

local function enforceCameraZoom()
	-- StarterPlayer w default.project.json ustawia limity (replikowane do Player przy join).
	-- Wymuszamy też runtime na wypadek gdyby inny skrypt override'ował.
	localPlayer.CameraMinZoomDistance = CFG.CameraMinZoom
	localPlayer.CameraMaxZoomDistance = CFG.CameraMaxZoom
	-- Shift-lock: NIE ustawiamy runtime — Roblox capability system blokuje
	-- (DevEnableMouseLock wymaga RobloxScript capability której nie mamy).
	-- StarterPlayer.EnableMouseLockOption=false w default.project.json załatwia default
	-- dla nowych graczy, więc nasz sprint na Shift nie koliduje z built-in shift-lock.

	-- Cleanup po usuniętym motion blur feature — Lighting mógł zachować BlurEffect
	-- z poprzedniego Play. Bez tego ekran byłby trwale rozmyty.
	local existing = game:GetService("Lighting"):FindFirstChild("MovementMotionBlur")
	if existing then existing:Destroy() end
end

-- ====================================================================
-- INIT
-- ====================================================================

function MovementController.init()
	if initialized then return end
	initialized = true

	enforceCameraZoom()

	-- Pasek staminy 3D — może yieldować na ReplicatedStorage.StaminaBar / PlayerGui.
	task.spawn(setupStaminaBar)

	-- Character hook (obecny + przyszłe respawny).
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacterAdded)

	-- Input: LeftShift hold. gameProcessed=true gdy fokus na TextBox (chat) — skip.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			tryStartSprint()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		-- InputEnded ignoruje gameProcessed celowo — chcemy stopować sprint nawet jeśli
		-- gracz puścił shift podczas focus'u w chat (inaczej "stuck sprint" po typowaniu).
		if input.KeyCode == Enum.KeyCode.LeftShift then
			stopSprint()
		end
	end)
	-- Alt-tab / focus loss → InputEnded może nie fire'ować dla niektórych klawiszy.
	-- WindowFocusReleased gwarantuje że sprint się stopuje.
	UserInputService.WindowFocusReleased:Connect(stopSprint)

	-- Main loop: drain/regen/lerp WalkSpeed + camera effects + head replikacja.
	RunService.Heartbeat:Connect(updateLoop)

	-- Head tracking apply: priorytet Character+1, czyli PO kamerze (Camera+1) — głowa
	-- czyta już wygładzoną kamerę. Priorytet NIE chroni przed animatorem (animator nie jest
	-- w tej kolejce); przed nim chroni to, że obracamy `C0`, a nie `Transform` — patrz applyAim.
	RunService:BindToRenderStep(
		"MovementHeadAim",
		Enum.RenderPriority.Character.Value + 1,
		onRenderStepHeadAim
	)

	-- Camera post-fx: priorytet PO Camera (default camera już ustawiła świeży CFrame) —
	-- czytamy go i nakładamy rotation smoothing + shake. Head aim (Character+1) leci jeszcze
	-- później i czyta już zmodyfikowaną kamerę, więc głowa jest spójna z tym co widać.
	RunService:BindToRenderStep(
		"MovementCamera",
		Enum.RenderPriority.Camera.Value + 1,
		onRenderStepCamera
	)

	-- Remote: odbieraj aim danych od innych klientów.
	Remotes.HeadAim.OnClientEvent:Connect(onRemoteHeadAim)

	-- Trafienie wybuchem — screen shake + FOV punch skalowane siłą (intensity 0..1).
	Remotes.BombHit.OnClientEvent:Connect(function(intensity: number)
		if type(intensity) ~= "number" then return end
		intensity = math.clamp(intensity, 0, 1)
		local hr = CFG_CAM.HitReaction
		MovementController.screenShake(intensity * hr.ShakeMax, hr.ShakeDuration)
		MovementController.fovKick(intensity * hr.FOVPunchMax)
	end)

	-- Pre-cache joints dla wszystkich remote players (existing + future).
	for _, p in ipairs(Players:GetPlayers()) do
		setupRemotePlayerHeadTrack(p)
	end
	Players.PlayerAdded:Connect(setupRemotePlayerHeadTrack)

	-- Cleanup state per-player gdy gracz wychodzi.
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return MovementController
