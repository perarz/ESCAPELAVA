--!strict
-- EnergyDrinkController.luau (20.10) — kliencka strona energy drinka. Dwie role:
--   1. Tool.Activated na `EnergyDrinkTool` → łyk od razu u siebie + DrinkEnergy do serwera
--   2. Gest łyku (ręka z puszką do ust) na postaci KAŻDEGO gracza, który pije — sygnałem jest
--      atrybut `EnergyStart` ustawiany przez serwer (replikuje się do wszystkich)
-- Sam efekt (stamina bez końca, kolory paska) liczy MovementController z tych atrybutów.
--
-- GEST = ta sama technika co ItemEquipController (Codex, 20.10): nakładka na Motor6D.Transform,
-- zdejmowana w PreAnimation i kładziona po Animatorze w PreSimulation, bez zapisów C0 (należą do
-- head trackingu). Własna kopia, bo tamten kontroler odpala gest tylko przy POJAWIENIU się Toola,
-- a łyk dzieje się z puszką już w ręce. Wyciągnięcie puszki gestu nie ma (EnergyDrinkTool nie ma
-- profilu w Config.ItemEquip.ToolProfiles), więc dwa gesty na tej samej ręce się nie spotkają;
-- dla pewności przed łykiem wołamy `ItemEquipController.cancel()`, jak przy każdej akcji itemem.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local RagdollState = require(script.Parent.RagdollState)
local ItemEquipController = require(script.Parent.ItemEquipController)

local ToolActivation = require(script.Parent.ToolActivation)

local EnergyDrinkController = {}

local CFG = Config.EnergyDrink
local TOOL_NAME = "EnergyDrinkTool"
local localPlayer = Players.LocalPlayer
local lastDrinkAt = 0

-- Ten sam gate co hak i bomba: poza rundą serwer łyk odrzuca. Pusty stan przepuszczamy (gracz
-- mógł dołączyć, zanim doszedł stan gry).
local gameState = ""
Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
	gameState = newState
end)

-- ── Gest łyku ────────────────────────────────────────────────────────────────────────
type Joint = { motor: Motor6D, base: CFrame?, written: CFrame? }
type Sip = { character: Model, humanoid: Humanoid, tool: Tool, started: number, joints: { [string]: Joint } }

local sips: { [Player]: Sip } = {}
-- Kiedy WŁASNY łyk ruszył z kliknięcia — echo atrybutu z serwera nie może go zacząć drugi raz.
local localSipAt = -math.huge

local JOINT_NAMES = { RightShoulder = "Shoulder", RightElbow = "Elbow", RightWrist = "Wrist" }

local function restore(sip: Sip)
	for _, joint in pairs(sip.joints) do
		-- Nie nadpisujemy Transformu, który zmienił w międzyczasie ktoś inny (Animator).
		if joint.base and joint.written and joint.motor.Parent and joint.motor.Transform == joint.written then
			joint.motor.Transform = joint.base
		end
		joint.base, joint.written = nil, nil
	end
end

local function stop(player: Player)
	local sip = sips[player]
	if sip then restore(sip) end
	sips[player] = nil
end

local function heldCan(character: Model): Tool?
	local tool = character:FindFirstChild(TOOL_NAME)
	return if tool and tool:IsA("Tool") then tool else nil
end

local function playSound(character: Model)
	if CFG.SipSound == "" then return end
	local root = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return end
	local sound = Instance.new("Sound")
	sound.SoundId = CFG.SipSound
	sound.Volume = CFG.SipSoundVolume
	sound.Parent = root
	sound:Play()
	sound.Ended:Once(function() sound:Destroy() end)
	task.delay(5, function() if sound.Parent then sound:Destroy() end end)
end

local function begin(player: Player)
	local character = player.Character
	if not character then return end
	local tool = heldCan(character)
	if not tool then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or RagdollState.isRagdolled(hum) then return end

	stop(player)
	local joints: { [string]: Joint } = {}
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("Motor6D") then
			local key = JOINT_NAMES[inst.Name]
			if key then joints[key] = { motor = inst, base = nil, written = nil } end
		end
	end
	-- Brak kompletu stawów (inny rig) = brak gestu; napój działa dalej.
	if not (joints.Shoulder and joints.Elbow and joints.Wrist) then return end
	sips[player] = { character = character, humanoid = hum, tool = tool, started = os.clock(), joints = joints }
	playSound(character)
end

local function angles(v: Vector3): CFrame
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

local poseFrames: { [Vector3]: CFrame } = {}
for _, key in ipairs(CFG.Sip) do
	for _, name in pairs(JOINT_NAMES) do
		local value = (key :: any)[name]
		poseFrames[value] = angles(value)
	end
end

local function update()
	local now = os.clock()
	local keys = CFG.Sip
	for player, sip in pairs(sips) do
		local hum = sip.humanoid
		local t = (now - sip.started) / CFG.SipDuration
		-- Koniec gestu albo cokolwiek, co go unieważnia: śmierć, ragdoll, drabina albo w ręce jest
		-- już INNY item (jego gest wyciągania pisze te same stawy). Samo zniknięcie puszki gestu
		-- nie przerywa: ostatnia sztuka znika po łyku, a u innych graczy ta wiadomość potrafi
		-- dojść przed końcem ich kopii gestu — ręka ma wtedy spokojnie opaść, nie skoczyć.
		local otherItem = sip.tool.Parent ~= sip.character and sip.character:FindFirstChildOfClass("Tool") ~= nil
		if t >= 1 or player.Character ~= sip.character or not sip.character.Parent or otherItem
			or hum.Health <= 0 or RagdollState.isRagdolled(hum) or hum.Sit
			or hum:GetState() == Enum.HumanoidStateType.Climbing then
			stop(player)
			continue
		end
		local a, b = keys[1], keys[#keys]
		for i = 2, #keys do
			if t <= keys[i].Time then a, b = keys[i - 1], keys[i]; break end
		end
		local span = b.Time - a.Time
		local alpha = if span > 0 then math.clamp((t - a.Time) / span, 0, 1) else 1
		alpha = alpha * alpha * (3 - 2 * alpha)
		local weight = a.Weight + (b.Weight - a.Weight) * alpha
		for name, joint in pairs(sip.joints) do
			local motor = joint.motor
			if not motor.Parent or not motor.Enabled then stop(player); break end
			local pose = poseFrames[(a :: any)[name]]:Lerp(poseFrames[(b :: any)[name]], alpha)
			local base = motor.Transform
			local result = base:Lerp(pose, weight)
			joint.base, joint.written = base, result
			motor.Transform = result
		end
	end
end

-- ── Łyk z kliknięcia ─────────────────────────────────────────────────────────────────
local function onActivated()
	if gameState ~= "" and gameState ~= "ROUND" then return end
	local now = os.clock()
	if now - lastDrinkAt < Config.RateLimits.EnergyDrink then return end
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or RagdollState.isRagdolled(hum) then return end

	lastDrinkAt = now
	ItemEquipController.cancel()
	-- Gest od razu, bez czekania na serwer — łyk z opóźnieniem pingu czyta się jak lag.
	-- Efekt i tak włączy dopiero serwer (atrybuty), więc odrzucony łyk nic nie daje.
	localSipAt = now
	begin(localPlayer)
	Remotes.DrinkEnergy:FireServer()
end



-- Gest u wszystkich: serwer ustawia `EnergyStart` przy każdym łyku (też przy odnowieniu w
-- trakcie działania — wtedy zmienia się tylko `EnergyEnd`, więc słuchamy końca).
local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal(CFG.EndAttribute):Connect(function()
		local e = player:GetAttribute(CFG.EndAttribute)
		if type(e) ~= "number" or e <= Workspace:GetServerTimeNow() then
			return
		end
		if player == localPlayer and os.clock() - localSipAt < CFG.SipDuration then
			return -- własny łyk już trwa (z kliknięcia)
		end
		begin(player)
	end)
end

local initialized = false
function EnergyDrinkController.init()
	if initialized then return end
	initialized = true

	ToolActivation.bind("EnergyDrinkTool", onActivated)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(stop)

	-- Animator pisze Transform między tymi fazami (jak w ItemEquipController).
	RunService.PreAnimation:Connect(function()
		for _, sip in pairs(sips) do restore(sip) end
	end)
	RunService.PreSimulation:Connect(update)
end

return EnergyDrinkController
