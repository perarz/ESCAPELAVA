--!strict
-- PushService.luau
-- F key push — lekka rywalizacja PvP w trakcie ROUND. Gracz pcha innego gracza w przód
-- przez prosty velocity nudge (BEZ ragdolla — ragdoll byłby za OP).
--
-- Mechanika:
--   - COOLDOWN 4s per gracz (zużywa się NAWET gdy brak celu w zasięgu — zapobiega
--     spamowi F żeby "wyszukać" cel; gracz musi celować)
--   - MAX_RANGE 7 stud — close-combat only
--   - Stożek ~70° przed pusherem (dot product > 0.3) — push tylko w przód
--   - Target wybierany SERVER-SIDE — klient nie decyduje kogo pchnąć (anti-cheat)
--   - Push tylko w ROUND między żywymi (PlayerService.isAlive)
--   - Velocity NIE może być ustawiane server-side (NetworkOwner=LocalPlayer → klient
--     przerysuje state). Wysyłamy Remotes.Pushed do target client, target sam aplikuje
--     velocity na swoim HRP — klient owns physics więc zmiana się utrzyma.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local PlayerService = require(script.Parent.PlayerService)
local KillService = require(script.Parent.KillService)
local AntiCheatService = require(script.Parent.AntiCheatService)

local PushService = {}

-- Balans z Config (hard rule #5) — tu tylko aliasy dla czytelności.
local MAX_RANGE = Config.Push.MaxRange
local CONE_DOT = Config.Push.ConeDot
local PUSH_FORCE = Config.Push.Force
local PUSH_LIFT = Config.Push.Lift

local lastPushAt: { [Player]: number } = {}

local function pickTarget(pusher: Player, pusherHRP: BasePart): Player?
	-- Najbliższy żywy gracz w MAX_RANGE i w stożku przed pusherem.
	local look = pusherHRP.CFrame.LookVector
	local origin = pusherHRP.Position

	local bestPlayer: Player? = nil
	local bestDist = MAX_RANGE

	for _, other in ipairs(Players:GetPlayers()) do
		if other == pusher then continue end
		if not PlayerService.isAlive(other) then continue end
		local otherHRP = Utils.getRoot(other)
		if not otherHRP then continue end

		local offset = otherHRP.Position - origin
		local dist = offset.Magnitude
		if dist > MAX_RANGE or dist < 0.1 then continue end

		local dir = offset.Unit
		if look:Dot(dir) < CONE_DOT then continue end

		if dist < bestDist then
			bestDist = dist
			bestPlayer = other
		end
	end

	return bestPlayer
end

local function onPush(pusher: Player)
	-- Tylko żywi gracze w ROUND
	if not PlayerService.isAlive(pusher) then return end

	-- Cooldown — START na próbie, nie sukcesie (anti-spam F)
	local now = os.clock()
	if now - (lastPushAt[pusher] or 0) < Config.RateLimits.Push then return end
	lastPushAt[pusher] = now

	local pusherHRP = Utils.getRoot(pusher)
	if not pusherHRP then return end

	local target = pickTarget(pusher, pusherHRP)
	if not target then return end  -- cooldown już zużyty, brak celu = miss

	local targetHRP = Utils.getRoot(target)
	if not targetHRP then return end

	-- Direction: push target away from pusher (poziomo)
	local horizontal = targetHRP.Position - pusherHRP.Position
	horizontal = Vector3.new(horizontal.X, 0, horizontal.Z)
	if horizontal.Magnitude < 0.01 then
		-- Edge case: gracze nakładający się — użyj pusher LookVector
		local look = pusherHRP.CFrame.LookVector
		horizontal = Vector3.new(look.X, 0, look.Z)
	end
	local dir = horizontal.Unit
	local velocity = dir * PUSH_FORCE + Vector3.new(0, PUSH_LIFT, 0)

	-- Okno bezkarności dla anti-cheata — pchnięcie to impuls od SERWERA, nie speedhack.
	AntiCheatService.grantGrace(target)

	-- Klient target'a aplikuje velocity (network ownership = klient, server set nie działa)
	Remotes.Pushed:FireClient(target, velocity)

	-- Tag pusher jako attacker na target humanoid — jeśli target wpadnie w lawę
	-- w oknie KillCreditWindowSec, push dostaje credit.
	local targetHum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if targetHum then
		KillService.tag(targetHum, pusher, "push")
	end

	print(("[Push] %s pushed %s"):format(pusher.Name, target.Name))
end

local function onPlayerRemoving(player: Player)
	lastPushAt[player] = nil
end

local initialized = false
function PushService.init()
	if initialized then return end
	initialized = true

	Remotes.Push.OnServerEvent:Connect(onPush)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PushService
