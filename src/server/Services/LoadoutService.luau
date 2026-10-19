--!strict
-- LoadoutService.luau
-- Trzy itemy na rundę (plan: docs/ROADMAP.md → „PLAN: LOADOUT”, decyzje Kacpra 30.09 i 18.10).
-- JEDYNY właściciel `data.loadout` = { "bomb", "grapple", "" } — zawsze 3 napisy, "" = pusty
-- slot. Tablica z dziurami (nil) w DataStore zamienia się w słownik albo traci ogon, stąd "".
--
-- Zasady (dla gracza):
--   * Slot trzyma item także przy 0 sztuk — klawisze 1-2-3 nigdy się nie przestawiają.
--   * Nowy item z wolnym slotem wskakuje sam (`addIfFree`, woła sklep) — nowy gracz nigdy nie
--     musi otwierać ekwipunku, żeby zagrać.
--   * Zmiana tylko w LOBBY — inaczej „3 z 6” nic nie znaczy. Sprawdza serwer, nie tylko UI.
--   * Wyciągnąć można tylko item z loadoutu (`canEquip` w Bomb/Bridge/GrappleService).
--
-- API:
--   LoadoutService.get(player) -> { string }   (kopia; 3 napisy)
--   LoadoutService.canEquip(player, itemId) -> boolean
--   LoadoutService.addIfFree(player, itemId) -> boolean (true = item jest w loadoucie)
--   LoadoutService.replicateTo(player)          — stan startowy po `ClientReady` (paczka 3)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ItemService = require(script.Parent.ItemService)
local GameLoopService = require(script.Parent.GameLoopService)

local LoadoutService = {}

local SLOTS = Config.Loadout.Slots
local lastSetAt: { [Player]: number } = {}

local function log(player: Player, text: string)
	print(("[Loadout] %s %s"):format(player.Name, text))
end

-- Dowolne wejście (zapis z DataStore albo payload klienta) → dokładnie SLOTS napisów:
-- tylko istniejące itemy, bez powtórzeń, reszta "". Nil = wejście bez sensu.
local function sanitize(raw: any): { string }?
	if type(raw) ~= "table" then return nil end
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for i = 1, SLOTS do
		local id = raw[i]
		if type(id) == "string" and id ~= "" and #id <= 64 and ItemDefinitions.exists(id) and not seen[id] then
			seen[id] = true
			out[i] = id
		else
			out[i] = ""
		end
	end
	return out
end

-- Brak zapisu = pierwsze posiadane itemy w kolejności sklepu („masz mniej niż 3 — loadout to
-- to, co masz”). Stare zapisy sprzed loadoutu wchodzą tą samą ścieżką, bez migracji.
-- Przez ItemService, nie `data.inventory`: tryb dev wstrzykuje itemy w JEDNYM miejscu (snapshot).
local function defaultFor(player: Player): { string }
	local out: { string } = {}
	for _, id in ipairs(ItemDefinitions.shopOrder) do
		if #out >= SLOTS then break end
		if ItemService.getCount(player, id) > 0 then
			table.insert(out, id)
		end
	end
	for i = #out + 1, SLOTS do
		out[i] = ""
	end
	return out
end

local function current(player: Player): { string }?
	local data = PlayerDataService.get(player)
	if not data then return nil end
	return sanitize(data.loadout)
end

local function store(player: Player, loadout: { string })
	PlayerDataService.update(player, function(data)
		data.loadout = table.clone(loadout)
		return data
	end)
	Remotes.LoadoutChanged:FireClient(player, table.clone(loadout))
end

function LoadoutService.get(player: Player): { string }
	return current(player) or table.create(SLOTS, "")
end

function LoadoutService.canEquip(player: Player, itemId: string): boolean
	local loadout = current(player)
	return loadout ~= nil and table.find(loadout, itemId) ~= nil
end

function LoadoutService.addIfFree(player: Player, itemId: string): boolean
	local loadout = current(player)
	if not loadout then return false end
	if table.find(loadout, itemId) then return true end
	local free = table.find(loadout, "")
	if not free then return false end
	loadout[free] = itemId
	store(player, loadout)
	log(player, ("auto %s → slot %d"):format(itemId, free))
	return true
end

function LoadoutService.replicateTo(player: Player)
	local loadout = current(player)
	if loadout then
		Remotes.LoadoutChanged:FireClient(player, loadout)
	end
end

local function onSetLoadout(player: Player, raw: any)
	-- Klient zbiera szybkie zmiany i wysyła ostatnią, więc limit nie gubi ludzkiego tempa.
	local now = os.clock()
	if now - (lastSetAt[player] or 0) < Config.RateLimits.SetLoadout * Config.RateLimits.ServerTolerance then
		LoadoutService.replicateTo(player) -- odrzucona prośba: klient wraca do stanu serwera
		return
	end
	lastSetAt[player] = now

	local loadout = sanitize(raw)
	if not loadout or GameLoopService.getState() ~= GameLoopService.STATE.LOBBY then
		LoadoutService.replicateTo(player)
		return
	end
	store(player, loadout)
	log(player, table.concat(loadout, ","))
end

local initialized = false
function LoadoutService.init()
	if initialized then return end
	initialized = true

	-- Po wczytaniu: brak zapisu → domyślny; zapis z nieistniejącym już itemem → wyczyszczony.
	PlayerDataService.subscribe(function(eventKey, player, _old, data)
		if eventKey ~= "loaded" and eventKey ~= "loaded_default" then return end
		local saved = if data then data.loadout else nil
		store(player, sanitize(saved) or defaultFor(player))
	end)

	Remotes.SetLoadout.OnServerEvent:Connect(onSetLoadout)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSetAt[player] = nil
	end)
end

return LoadoutService
