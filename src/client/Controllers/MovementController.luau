--!strict
-- MovementController.luau
-- Centralny client controller ruchu. Etapowo:
--   Etap 1: bazowy WalkSpeed na każdy character + camera zoom enforcement (3rd person).
--   Etap 2: sprint hold (LeftShift) z staminą + HUD pasek.
--   Etap 3: dynamic FOV (sprint = +X°).
--   Etap 4: smooth camera (elastic rotation smoothing, landing dip, screenShake API).
--   Etap 5 (TERAZ): head rotation — lokalna głowa + waist obracają się za kamerą,
--                   replikacja do innych klientów ~10Hz przez HeadTrackingService.
--
-- Wszystkie liczby z Config.Movement — zero magic numbers tutaj.
-- Klient-side: ruch i kamera są lokalne (smooth feedback), serwer dostaje finalne WalkSpeed
-- przez Roblox Humanoid auto-replication. WalkSpeed cap enforced przez AntiCheatService (server).
--
-- ===== RAGDOLL SAFETY =====
-- Toolbox ARTFVL ustawia Humanoid.PlatformStand=true podczas ragdoll'u (bomba/push).
-- - WalkSpeed nie działa przy PlatformStand=true (humanoid leży, fizyka kości decyduje).
-- - NIE drainujemy staminy podczas ragdoll (gracz nie biegnie świadomie, byłoby unfair).
-- - REGENUJEMY staminę podczas ragdoll (gracz "odzyskuje siłę leżąc", logiczne).
-- - Force-stop sprint przy ragdoll → po un-ragdoll player musi wcisnąć Shift ponownie
--   żeby świadomie wznowić sprint (eliminuje "obudziłem się i magicznie biegnę").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local MovementController = {}

local CFG = Config.Movement
local CFG_STAM = CFG.Stamina
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
	neckC0: CFrame?,     -- rest C0 do reset gdy joint znika
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

-- FOV punch (bomba) — chwilowy additive offset FOV, decays do 0. Niezależny od sprint FOV.
local fovPunch: number = 0

-- HUD references (lookup raz przy init — HUD ResetOnSpawn=false więc persistują)
local staminaLabel: TextLabel? = nil
local lastStaminaShown: number = -1
local hudWarned: boolean = false

-- ====================================================================
-- HELPERS
-- ====================================================================

local function isRagdolled(): boolean
	-- Toolbox ARTFVL: PlatformStand=true gdy gracz ragdoll'owany. WalkSpeed nie działa.
	return currentHumanoid ~= nil and currentHumanoid.PlatformStand == true
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

-- Stamina jako TEKST, nie pasek (2026-08-12, decyzja Kacpra). Kontrakt:
-- `HUD.StaminaLabel` (TextLabel) — kod ustawia tylko `.Text` na "STAMINA: N" (N = 0-100),
-- cały styling jest Kacpra. Gdy labela nie ma, a jest jeszcze stary `HUD.StaminaBar`,
-- kod tworzy label przejmując geometrię paska i chowa pasek — dzięki temu HUD działa
-- od razu, a Kacper może potem podmienić na własny (wystarczy postawić StaminaLabel).
local function findStaminaLabel()
	-- Yield-safe, task.spawn z init() żeby nie blokować bootstrap'u.
	local pg = localPlayer:WaitForChild("PlayerGui")
	local hud = pg:WaitForChild("HUD", 10)
	if not hud then
		if not hudWarned then
			hudWarned = true
			warn("[Movement] StarterGui.HUD nie istnieje — licznik staminy nieaktywny")
		end
		return
	end

	-- Rekurencyjny find, żeby Kacper mógł trzymać label w dowolnym Frame.
	local label = hud:FindFirstChild("StaminaLabel", true)
	if label and label:IsA("TextLabel") then
		staminaLabel = label
	end

	-- Stary pasek: chowamy (nie Destroy — to element Kacpra w StarterGui, ma prawo
	-- wrócić jednym Visible=true, gdyby decyzja się zmieniła).
	local bar = hud:FindFirstChild("StaminaBar", true)
	local barBG = hud:FindFirstChild("StaminaBarBG", true)
	local source = bar or barBG
	if bar and bar:IsA("GuiObject") then
		bar.Visible = false
	end
	if barBG and barBG:IsA("GuiObject") then
		barBG.Visible = false
	end

	if staminaLabel then return end

	-- Fallback: brak StaminaLabel → tworzymy w miejscu paska (ten sam wzorzec co
	-- WinBannerController: domyślny wygląd w kodzie, migrowalny do template'a Kacpra).
	if not source or not source:IsA("GuiObject") then
		if not hudWarned then
			hudWarned = true
			warn("[Movement] brak HUD.StaminaLabel (TextLabel) i brak HUD.StaminaBar — licznik staminy nieaktywny. " ..
				"Postaw TextLabel o nazwie 'StaminaLabel' w StarterGui.HUD.")
		end
		return
	end

	-- Geometrię bierzemy z NAJWYŻSZEGO elementu paska (bezpośredniego dziecka HUD) —
	-- to on niesie pozycję względem ekranu. Wewnętrzny StaminaBar ma współrzędne względem
	-- swojego rodzica (u Kacpra 0.5/0.5 w StaminaBarBG), więc sam w sobie nie mówi nic
	-- o miejscu na ekranie.
	local anchorElement: GuiObject = source
	while
		anchorElement.Parent
		and anchorElement.Parent ~= hud
		and anchorElement.Parent:IsA("GuiObject")
	do
		anchorElement = anchorElement.Parent :: GuiObject
	end

	local created = Instance.new("TextLabel")
	created.Name = "StaminaLabel"
	created.BackgroundTransparency = 1
	created.AnchorPoint = anchorElement.AnchorPoint
	created.Position = anchorElement.Position
	created.Size = anchorElement.Size
	created.Font = Enum.Font.FredokaOne
	created.TextScaled = true
	created.TextColor3 = Color3.fromRGB(255, 255, 255)
	created.TextXAlignment = Enum.TextXAlignment.Left
	created.TextYAlignment = Enum.TextYAlignment.Center
	created.Text = "STAMINA: 100"

	-- Bez capa TextScaled rozdmuchuje tekst do wysokości kontenera paska (u Kacpra 108 px)
	-- i licznik zasłania pół HUD.
	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = 42
	sizeConstraint.Parent = created

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = created

	-- Parent = HUD, NIE kontener paska: właśnie go ukryliśmy, a ukryty rodzic chowa
	-- całe poddrzewo (to był powód "nie widzę napisu"). Jako top-level dziecko HUD
	-- label dostaje też UIScale z HudScaleController (podpięte pod ChildAdded).
	created.Parent = hud
	staminaLabel = created
end

local function updateHUD()
	local label = staminaLabel
	if not label then return end
	local pct = math.clamp(currentStamina / CFG_STAM.Max, 0, 1)
	local value = math.floor(pct * 100 + 0.5)
	-- Zapis tylko przy realnej zmianie — property write na TextLabel co klatkę to
	-- niepotrzebny koszt renderu przy 60Hz update loopie.
	if value ~= lastStaminaShown then
		lastStaminaShown = value
		label.Text = ("STAMINA: %d"):format(value)
	end
end

-- ====================================================================
-- UPDATE LOOP
-- ====================================================================

local function updateLoop(dt: number)
	if not currentHumanoid then
		updateHUD()
		return
	end

	-- Dead character → cleanup sprint state (lerp WalkSpeed do bazowego, ale i tak humanoid
	-- nie żyje). State zostaje, reset dopiero na CharacterAdded (nowy respawn).
	if not isAlive() then
		isSprintingHeld = false
		updateHUD()
		return
	end

	local activeSprint = shouldActivelySprintThisFrame()

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
	local targetSpeed = activeSprint and CFG.SprintSpeed or CFG.WalkSpeed
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

	updateHUD()
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
	-- Per CLAUDE.md zasada 11: toolbox ARTFVL ragdoll = PlatformStand=true.
	-- W trakcie ragdoll'u NIE dotykamy Motor6D Transform (BallSocketConstraints driveją fizykę,
	-- nasze write'y by się fightowały z constraint physics → dziwne wykrzywienia).
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	return hum.PlatformStand == true or hum.Health <= 0
end

local function applyAim(player: Player, character: Model, yaw: number, pitch: number)
	local cache = ensureJointCache(player)
	if not cache then return end
	if isCharacterRagdolled(character) then return end

	-- Pitch wyłącznie na neck. Yaw rozdzielamy: WaistYawRatio idzie na waist (talia
	-- skręca lekko za kamerą), reszta na neck.
	local waistYaw = yaw * CFG_HT.WaistYawRatio
	local neckYaw = yaw - waistYaw

	if cache.waist then
		-- .Transform po animatorze (BindToRenderStep priority Character+1) zawiera animacyjny
		-- output dla tej klatki. Multiply zachowuje animację + dodaje skręcenie.
		cache.waist.Transform = cache.waist.Transform * CFrame.Angles(0, waistYaw, 0)
	end
	if cache.neck then
		-- Pitch sign: R15 neck local frame ma +Y up, -Z forward. CFrame.Angles(rx, 0, 0)
		-- z dodatnim rx obraca głowę W GÓRĘ (top of head do tyłu). Kamera patrząc w dół:
		-- camLook.Y < 0 → pitch = asin(Y) < 0 → CFrame.Angles(pitch, ...) z ujemnym rx →
		-- głowa w dół. Stąd `pitch` (nie -pitch). Jeśli wygląda na flipped — odwróć znak.
		cache.neck.Transform = cache.neck.Transform * CFrame.Angles(pitch, neckYaw, 0)
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
	-- Priorytet Character+1 = po Animatorze → nasze write'y wygrywają.
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
	updateHUD()
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

local function onRenderStepCamera(dt: number)
	-- Dwa efekty na finalnym CFrame kamery, liczone PO default camera (priorytet Camera+1):
	--   1. Elastic rotation smoothing — renderujemy lagged wersję (kamera dogania mysz).
	--   2. Screen shake — camera-local jitter, DZIAŁA W RAGDOLLU (nie zależy od CameraOffset).
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
		return
	end

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

	-- 2. Shake — camera-local translacja (X=right, Y=up, Z=back). Zero gdy nieaktywny.
	local shake = computeShakeOffset()

	-- Ustaw CFrame tylko gdy faktycznie coś modyfikujemy — inaczej zostaw default camera
	-- w spokoju (mniej redundantnych setów, brak konfliktu gdy oba efekty wyłączone/idle).
	if cfg.Enabled then
		if shake ~= Vector3.zero then
			camera.CFrame = base * CFrame.new(shake)
		else
			camera.CFrame = base
		end
	elseif shake ~= Vector3.zero then
		camera.CFrame = raw * CFrame.new(shake)
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

	-- HUD lookup w background — może yieldować na PlayerGui/HUD.
	task.spawn(findStaminaLabel)

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

	-- Head tracking apply: BindToRenderStep priorytet po Character (animator). Inaczej
	-- Animator nadpisze nasze .Transform write'y w następnej klatce.
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
