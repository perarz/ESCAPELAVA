--!strict
-- LoadoutState.luau — JEDNO miejsce po stronie klienta ze stanem ekwipunku (18.10): co gracz
-- ma (inventory), co bierze na rundę (loadout) i czy trwa lobby. Czytają go HotbarController
-- (pasek) i InventoryController (panel) — dwie kopie tego stanu by się rozjechały.
--
-- Prawdę trzyma serwer (LoadoutService). Panel zmienia stan OPTYMISTYCZNIE (`set`), żeby
-- przeciąganie reagowało od razu, a wysyła dopiero ostatni stan po `SendDelay` — szybkie
-- kliknięcia nie wpadają w limit serwera. Do chwili wysyłki odpowiedzi serwera są pomijane
-- (echo poprzedniej zmiany cofnęłoby na moment świeży ruch gracza); po wysyłce wygrywa serwer.
--
-- `init` startuje PIERWSZY w init.client — listenery muszą stać przed `ClientReady` (paczka 3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local LoadoutState = {}

local SLOTS = Config.Loadout.Slots
local CFG = Config.UI.Inventory

local inventory: { [string]: number } = {}
local loadout: { string } = table.create(SLOTS, "")
local gameState = "LOBBY"
local sendToken = 0
local sending = false
local listeners: { () -> () } = {}

local function notify()
	for _, cb in ipairs(listeners) do
		task.spawn(cb)
	end
end

local function clean(raw: any): { string }
	local out: { string } = {}
	for i = 1, SLOTS do
		local v = type(raw) == "table" and raw[i] or nil
		out[i] = if type(v) == "string" then v else ""
	end
	return out
end

-- Wywoływane przy każdej zmianie inventory / loadoutu / stanu gry.
function LoadoutState.onChanged(cb: () -> ())
	table.insert(listeners, cb)
end

function LoadoutState.getLoadout(): { string }
	return table.clone(loadout)
end

function LoadoutState.getCount(itemId: string): number
	return inventory[itemId] or 0
end

function LoadoutState.isLobby(): boolean
	return gameState == "LOBBY"
end

function LoadoutState.slotOf(itemId: string): number?
	return table.find(loadout, itemId)
end

-- Zmiana z panelu. Zwraca false poza lobby (panel pokazuje wtedy komunikat).
function LoadoutState.set(newLoadout: { string }): boolean
	if not LoadoutState.isLobby() then return false end
	loadout = clean(newLoadout)
	notify()
	sendToken += 1
	local token = sendToken
	sending = true
	task.delay(CFG.SendDelay, function()
		if token ~= sendToken then return end
		sending = false
		Remotes.SetLoadout:FireServer(table.clone(loadout))
	end)
	return true
end

local initialized = false
function LoadoutState.init()
	if initialized then return end
	initialized = true
	Remotes.InventoryChanged.OnClientEvent:Connect(function(inv: any)
		inventory = if type(inv) == "table" then inv else {}
		notify()
	end)
	Remotes.LoadoutChanged.OnClientEvent:Connect(function(raw: any)
		if sending then return end
		loadout = clean(raw)
		notify()
	end)
	Remotes.GameStateChanged.OnClientEvent:Connect(function(state: any)
		if type(state) == "string" then
			gameState = state
			notify()
		end
	end)
end

return LoadoutState
