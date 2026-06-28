--!strict
-- Remotes.luau
-- Single source of truth dla wszystkich RemoteEventów.
-- Serwer tworzy je przy pierwszym require, klient czeka aż się pojawią.
--
-- Użycie:
--   local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
--   Remotes.GameStateChanged:FireAllClients(...)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	"GameStateChanged",   -- (stateName: string, payload: table?)
	"PhaseChanged",       -- (phaseName: string, phaseIndex: number, duration: number)
	"PlayerDied",         -- (player: Player, reason: string)
	"RoundEnded",         -- (survivors: {Player}, payload: table?)
	"CashChanged",        -- FireClient: (balance: number, delta: number?, reason: string?)
	"CashCollected",      -- FireAllClients: (player: Player, fromPosition: Vector3) — klient animuje pickup
	"InventoryChanged",   -- FireClient: (inventory: {[slot]={itemId, count}})
	"BuyItem",            -- klient→server: FireServer(itemId: string)
	"ShopResult",         -- FireClient: (success: boolean, itemId: string, reason: string?)
	"UseItem",            -- klient→server: FireServer(slot: number, direction: Vector3) — instant-use itemy (przyszłość)
	"UseItemResult",      -- FireClient: (success: boolean, slot: number, reason: string?)
	"EquipItem",          -- klient→server: FireServer(slot: number)
	"UnequipItem",        -- klient→server: FireServer()
	"ThrowBomb",          -- klient→server: FireServer(direction: Vector3) — gdy ma BombTool equipped
	"Push",               -- klient→server: FireServer() — F key, server pickuje cel w stożku przed graczem
	"Pushed",             -- server→target client: FireClient(target, velocity: Vector3) — target aplikuje na swoim HRP
	"BuildBridge",        -- klient→server: FireServer(position: Vector3, rotationY: number)
	"BridgeBuildMode",    -- server→klient: FireClient(active: boolean) — enter/exit build mode
	"BridgeResult",       -- FireClient: (success: boolean, reason: string?) — feedback build
}

local function getRemotesFolder(): Folder
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local folder = shared:FindFirstChild("Remotes")

	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = shared
		else
			folder = shared:WaitForChild("Remotes")
		end
	end

	return folder :: Folder
end

local function getOrCreateEvent(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if RunService:IsServer() then
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		return event
	else
		return folder:WaitForChild(name, 10) :: RemoteEvent
	end
end

local Remotes = {}

local folder = getRemotesFolder()
for _, name in ipairs(REMOTE_NAMES) do
	Remotes[name] = getOrCreateEvent(folder, name)
end

return Remotes
