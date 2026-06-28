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

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local PlayerService = require(script.Parent.PlayerService)

local PushService = {}

local COOLDOWN = 4
local MAX_RANGE = 7
local CONE_DOT = 0.3   -- ~70° forward cone
local PUSH_FORCE = 80  -- horizontal velocity (stud/s)
local PUSH_LIFT = 20   -- mały lift żeby push nie szorał gracza po ziemi

local lastPushAt: { [Player]: number } = {}

local function getHRP(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return nil
end

local function pickTarget(pusher: Player, pusherHRP: BasePart): Player?
	-- Najbliższy żywy gracz w MAX_RANGE i w stożku przed pusherem.
	local look = pusherHRP.CFrame.LookVector
	local origin = pusherHRP.Position

	local bestPlayer: Player? = nil
	local bestDist = MAX_RANGE

	for _, other in ipairs(Players:GetPlayers()) do
		if other == pusher then continue end
		if not PlayerService.isAlive(other) then continue end
		local otherHRP = getHRP(other)
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
	if now - (lastPushAt[pusher] or 0) < COOLDOWN then return end
	lastPushAt[pusher] = now

	local pusherHRP = getHRP(pusher)
	if not pusherHRP then return end

	local target = pickTarget(pusher, pusherHRP)
	if not target then return end  -- cooldown już zużyty, brak celu = miss

	local targetHRP = getHRP(target)
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

	-- Klient target'a aplikuje velocity (network ownership = klient, server set nie działa)
	Remotes.Pushed:FireClient(target, velocity)

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
