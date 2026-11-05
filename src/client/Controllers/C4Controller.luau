--!strict
-- C4Controller.luau (25.10) — kliencka strona C4. Dwie role:
--   1. Tool.Activated na `C4Tool` → ThrowC4(punkt, w który celuje mysz) — lot i przyklejenie
--      liczy serwer. Zamach ręki (Config.C4.Swing) rysuje każdy klient: rzucający od razu po
--      kliknięciu, pozostali, gdy ładunek z atrybutem właściciela pojawi się w jego dłoni.
--   2. Detonator: klawisz Config.C4.DetonateKey (G) i przycisk `HUD.<DetonateButtonName>`
--      (telefon) → DetonateC4. Przycisk widać tylko, gdy masz przyklejone ładunki.
-- Liczbę ładunków podaje serwer atrybutem gracza (Config.C4.CountAttribute) — jedno źródło
-- prawdy, także po śmierci i końcu rundy (serwer czyści atrybut, przycisk sam znika).
--
-- KONTRAKT NAZW (Studio): `HUD.Detonator.DetonateButton` (GuiButton, kod szuka go w całym HUD,
-- Visible=false), opcjonalnie w nim `Count` („x2”) i `Keybind` („G” — widoczny tylko
-- z klawiaturą) — TextLabel albo ramka z `Label` — oraz UIScale `Pop`. Brak przycisku = działa
-- sam klawisz.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local C4Path = require(ReplicatedStorage.Shared.Modules.C4Path)
local RagdollState = require(script.Parent.RagdollState)
local ItemEquipController = require(script.Parent.ItemEquipController)
local CooldownBarController = require(script.Parent.CooldownBarController)

local ToolActivation = require(script.Parent.ToolActivation)

local C4Controller = {}

local CFG = Config.C4
local TOOL_NAME = "C4Tool"
local localPlayer = Players.LocalPlayer
local lastThrowAt = 0
local lastDetonateAt = 0
local THROW_DEDUPE = 0.1 -- s: klik i Activated tego samego kliknięcia to jedna próba
local button: GuiButton? = nil

-- Ten sam gate co pozostałe itemy (serwer i tak odrzuci akcję poza rundą). Pusty stan
-- przepuszczamy — gracz mógł dołączyć, zanim doszedł stan gry.
local gameState = ""

local function chargeCount(): number
	local n = localPlayer:GetAttribute(CFG.CountAttribute)
	return if type(n) == "number" then n else 0
end

local function aliveHumanoid(): Humanoid?
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	return hum
end

local function pop(scale: number)
	local b = button
	local ui = b and b:FindFirstChild("Pop")
	if not (ui and ui:IsA("UIScale")) then return end
	ui.Scale = scale
	TweenService:Create(ui, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Znaczek na rogu przycisku: sam TextLabel albo ramka z `Label` w środku (wzór Badge ekwipunku).
-- Cień `LabelShadow` dopisuje TextShadowController.
local function setBadge(b: GuiButton, name: string, text: string, visible: boolean)
	local badge = b:FindFirstChild(name)
	if not (badge and badge:IsA("GuiObject")) then return end
	badge.Visible = visible
	local label = if badge:IsA("TextLabel") then badge else badge:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function refreshButton()
	local b = button
	if not b then return end
	local n = chargeCount()
	b.Visible = n > 0 and (gameState == "" or gameState == "ROUND") and aliveHumanoid() ~= nil
	setBadge(b, "Count", "x" .. tostring(n), n > 0)
	setBadge(b, "Keybind", CFG.DetonateKey.Name, UserInputService.KeyboardEnabled)
end

local function detonate()
	if gameState ~= "" and gameState ~= "ROUND" then return end
	if chargeCount() <= 0 then return end
	if not aliveHumanoid() then return end
	local now = os.clock()
	if now - lastDetonateAt < Config.RateLimits.C4Detonate then return end
	lastDetonateAt = now
	pop(1.25)
	Remotes.DetonateC4:FireServer()
end

-- ── Zamach ręki ──────────────────────────────────────────────────────────────────────
-- Ta sama technika co kop RPG / ItemEquipController: nakładka na `Motor6D.Transform`
-- zdejmowana w PreAnimation i kładziona po Animatorze w PreSimulation, DODAWANA do pozy
-- trzymania (base * obrót) — kostka zostaje w dłoni, kiedy ma się jeszcze czym rzucać.
local SWING = CFG.Swing
type Swing = { started: number, humanoid: Humanoid, shoulder: Motor6D, elbow: Motor6D,
	written: { [Motor6D]: { base: CFrame?, w: CFrame? } } }
local swings: { [Player]: Swing } = {}

-- Klatki kluczowe gestu: (czas, bark, łokieć) w stopniach względem trzymania.
local SWING_KEYS = {
	{ 0, 0, 0 },
	{ SWING.Windup, SWING.ShoulderUp, SWING.ElbowBend },
	{ SWING.Release, SWING.ShoulderDown, 0 },
	{ SWING.Time, 0, 0 },
}

local function restoreSwing(sw: Swing)
	for motor, rec in pairs(sw.written) do
		if motor.Parent and rec.base and rec.w and motor.Transform == rec.w then motor.Transform = rec.base end
		rec.base, rec.w = nil, nil
	end
end

local function startSwing(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum) then return end
	local sh, el
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") then
			if d.Name == "RightShoulder" then sh = d elseif d.Name == "RightElbow" then el = d end
		end
	end
	if not (sh and el) then return end
	local old = swings[player]
	if old then restoreSwing(old) end
	swings[player] = { started = os.clock(), humanoid = hum, shoulder = sh, elbow = el,
		written = { [sh] = {}, [el] = {} } }
end

local function updateSwings()
	if next(swings) == nil then return end
	local now = os.clock()
	for player, sw in pairs(swings) do
		local t = now - sw.started
		if t >= SWING.Time or not sw.shoulder.Parent or not sw.shoulder.Enabled
			or not sw.elbow.Parent or not sw.elbow.Enabled
			or sw.humanoid.Health <= 0 or RagdollState.isRagdolled(sw.humanoid) then
			restoreSwing(sw)
			swings[player] = nil
			continue
		end
		local a, b = SWING_KEYS[1], SWING_KEYS[#SWING_KEYS]
		for i = 2, #SWING_KEYS do
			if t <= SWING_KEYS[i][1] then a, b = SWING_KEYS[i - 1], SWING_KEYS[i]; break end
		end
		local alpha = math.clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
		alpha = alpha * alpha * (3 - 2 * alpha)
		local shoulderDeg = a[2] + (b[2] - a[2]) * alpha
		local elbowDeg = a[3] + (b[3] - a[3]) * alpha
		for motor, rec in pairs(sw.written) do
			local deg = if motor == sw.shoulder then shoulderDeg else elbowDeg
			local base = motor.Transform
			local result = base * CFrame.Angles(math.rad(deg), 0, 0)
			rec.base, rec.w = base, result
			motor.Transform = result
		end
	end
end

-- ── Płynny lot ───────────────────────────────────────────────────────────────────────
-- Serwer przestawia ładunek co klatkę, a to dojeżdża do klienta skokowo (zgłoszenie Kacpra
-- 01.11). W locie rysujemy więc KOPIĘ liczoną z tego samego wzoru co serwer (C4Path) od czasu
-- serwera, a sam ładunek jest u nas niewidoczny. Po przyklejeniu kopia w LandBlend dojeżdża do
-- prawdziwego ładunku (który dotąd tylko czytamy — nie piszemy w jego CFrame, więc zawsze
-- jest tam, gdzie postawił go serwer) i znika.
local FLIGHT = CFG.Flight
type Visual = { clone: Model, primary: BasePart, at: number, start: CFrame, vel: Vector3,
	axis: Vector3, offset: CFrame, landFrom: CFrame?, landAt: number }
local visuals: { [Model]: Visual } = {}

local function setHidden(model: Model, hidden: boolean)
	local v = if hidden then 1 else 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = v
		end
	end
end

local function dropVisual(model: Model)
	local vis = visuals[model]
	if not vis then return end
	visuals[model] = nil
	vis.clone:Destroy()
	if model.Parent then setHidden(model, false) end
end

local function refreshFlight(model: Model)
	local at = model:GetAttribute(FLIGHT.At)
	local vis = visuals[model]
	if type(at) ~= "number" then
		-- Koniec lotu: dosiadanie (albo nic, jeśli kopii nie było).
		if vis and not vis.landFrom then
			vis.landFrom = vis.primary.CFrame
			vis.landAt = os.clock()
		end
		return
	end
	local start, vel = model:GetAttribute(FLIGHT.Start), model:GetAttribute(FLIGHT.Vel)
	local axis, offset = model:GetAttribute(FLIGHT.Axis), model:GetAttribute(FLIGHT.Offset)
	if typeof(start) ~= "CFrame" or typeof(vel) ~= "Vector3" or typeof(axis) ~= "Vector3"
		or typeof(offset) ~= "CFrame" then
		return
	end
	if not vis then
		local clone = model:Clone()
		local primary = clone.PrimaryPart
		if not primary then
			clone:Destroy()
			return
		end
		-- Dioda świeci z prawdziwego ładunku (miga po serwerze) — w kopii byłaby druga.
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("Light") then d:Destroy() end
		end
		clone.Name = "C4Visual"
		vis = { clone = clone, primary = primary, at = at, start = start, vel = vel, axis = axis,
			offset = offset, landFrom = nil, landAt = 0 }
		visuals[model] = vis
		clone.Parent = Workspace
		setHidden(model, true)
	end
	local v = vis :: Visual
	v.at, v.start, v.vel, v.axis, v.offset, v.landFrom = at, start, vel, axis, offset, nil
end

local function updateVisuals()
	if next(visuals) == nil then return end
	local serverNow = Workspace:GetServerTimeNow()
	local now = os.clock()
	for model, vis in pairs(visuals) do
		local real = model.PrimaryPart
		if not (model.Parent and real) then
			dropVisual(model) -- wybuch albo sprzątanie w locie
			continue
		end
		local from = vis.landFrom
		if from then
			local alpha = math.clamp((now - vis.landAt) / CFG.LandBlend, 0, 1)
			if alpha >= 1 then
				dropVisual(model)
				continue
			end
			alpha = alpha * alpha * (3 - 2 * alpha)
			vis.primary.CFrame = from:Lerp(real.CFrame, alpha)
		else
			local t = math.clamp(serverNow - vis.at, 0, CFG.MaxFlightTime)
			vis.primary.CFrame = C4Path.frame(vis.start, vis.vel, vis.axis, t) * vis.offset:Inverse()
		end
	end
end

local function trackCharge(child: Instance)
	if not child:IsA("Model") then return end
	child:GetAttributeChangedSignal(FLIGHT.At):Connect(function()
		refreshFlight(child)
	end)
	refreshFlight(child)
end

-- Cudzy rzut: ładunek wpada do folderu z atrybutem właściciela. Tylko świeży — blisko dłoni
-- rzucającego; wczytany później (streaming, dołączenie w trakcie) leży daleko i ręka nie macha.
local function onChargeAdded(child: Instance)
	trackCharge(child)
	if not child:IsA("Model") then return end
	local id = child:GetAttribute(CFG.OwnerAttribute)
	if type(id) ~= "number" or id == localPlayer.UserId then return end
	local owner = Players:GetPlayerByUserId(id)
	local hand = owner and owner.Character and owner.Character:FindFirstChild("RightHand")
	if not (owner and hand and hand:IsA("BasePart")) then return end
	if (child:GetPivot().Position - hand.Position).Magnitude > SWING.MaxHandDistance then return end
	startSwing(owner)
end

-- Jedna próba rzutu, niezależnie od tego, co ją wywołało (klik, R2, dotyk).
local lastAttemptAt = 0
local function tryThrow()
	-- Klik na PC wywołuje i `InputBegan`, i (zwykle) `Tool.Activated` — liczy się pierwszy.
	local now = os.clock()
	if now - lastAttemptAt < THROW_DEDUPE then return end
	lastAttemptAt = now
	if gameState ~= "" and gameState ~= "ROUND" then return end
	if now - lastThrowAt < Config.RateLimits.C4Throw then return end
	local hum = aliveHumanoid()
	local char = localPlayer.Character
	if not hum or not char or RagdollState.isRagdolled(hum) then return end
	if not char:FindFirstChild(TOOL_NAME) then return end
	if chargeCount() >= CFG.MaxActive then
		-- Limit: przycisk podskakuje — „najpierw odpal”, zamiast ciszy.
		pop(1.35)
		return
	end
	local mouse = localPlayer:GetMouse()
	local target = mouse.Hit and mouse.Hit.Position
	if not target then return end

	lastThrowAt = now
	ItemEquipController.cancel()
	Remotes.ThrowC4:FireServer(target)
	CooldownBarController.trigger("c4", Config.RateLimits.C4Throw)
	startSwing(localPlayer)
end

local function hookCharacter(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if hum and hum:IsA("Humanoid") then
		hum.Died:Connect(refreshButton)
	end
	refreshButton()
end

local initialized = false
function C4Controller.init()
	if initialized then return end
	initialized = true

	-- Listenery PRZED czekaniem na HUD (zasada 9).
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
		gameState = newState
		refreshButton()
	end)
	localPlayer:GetAttributeChangedSignal(CFG.CountAttribute):Connect(refreshButton)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end -- czat, pole tekstowe, klik w przycisk HUD
		if input.KeyCode == CFG.DetonateKey then
			detonate()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			-- ⚠️ Rzut z kliknięcia, NIE z samego `Tool.Activated` (zgłoszenie Kacpra 25.10, log DIAG):
			-- po strzale z RPG i szybkim przełączeniu na C4 Roblox przestawał wołać Activated nowego
			-- narzędzia — klik dochodził do świata (gameProcessed=false), C4 był wyciągnięty
			-- (Equipped), a Activated nie przyszło ani razu, aż do ponownego wyciągnięcia.
			tryThrow()
		end
	end)
	-- Activated pozostaje obsługą dotyku; InputBegan wyżej zachowuje obejście PC/R2.
	ToolActivation.bind(TOOL_NAME, tryThrow)
	localPlayer.CharacterAdded:Connect(hookCharacter)
	if localPlayer.Character then
		task.spawn(hookCharacter, localPlayer.Character)
	end
	RunService.PreAnimation:Connect(function()
		for _, sw in pairs(swings) do restoreSwing(sw) end
	end)
	RunService.PreSimulation:Connect(updateSwings)
	RunService.PreRender:Connect(updateVisuals)
	Players.PlayerRemoving:Connect(function(p)
		local sw = swings[p]
		if sw then restoreSwing(sw) end
		swings[p] = nil
	end)
	task.spawn(function()
		local charges = Workspace:WaitForChild("ActiveCharges", 30)
		if charges then
			charges.ChildAdded:Connect(onChargeAdded)
			-- Już lecące (dołączenie w trakcie) — tylko kopia lotu, bez machania ręką.
			for _, c in ipairs(charges:GetChildren()) do
				trackCharge(c)
			end
		end
	end)

	local hud = localPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD")
	local found = hud:FindFirstChild(CFG.DetonateButtonName, true)
	if found and found:IsA("GuiButton") then
		button = found
		found.Activated:Connect(detonate)
		refreshButton()
	else
		warn(("[C4Controller] brak HUD.%s (GuiButton) — detonator tylko z klawisza %s")
			:format(CFG.DetonateButtonName, CFG.DetonateKey.Name))
	end
end

return C4Controller
