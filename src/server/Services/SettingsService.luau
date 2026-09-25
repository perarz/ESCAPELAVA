--!strict
-- SettingsService.luau
-- Ustawienia gracza (NOWY 2026-09-23). Na razie jedno: TRYB GRAFIKI (Ziemniak / Pełny).
--
-- Serwer TYLKO PRZECHOWUJE wybór — co tryb robi, decyduje wyłącznie klient
-- (QualityController). W grze nic od niego nie zależy: serwer robi dla wszystkich
-- dokładnie to samo, tryb zmienia tylko to, ile gruzu i efektów klient dorysowuje u siebie.
-- Dlatego walidacja jest prosta (znany tryb + limit spamu) i nie ma tu nic do oszukania.
--
-- Zapis: `data.settings.graphics` w PlayerDataService (pole opcjonalne — brak = tryb
-- dobierany automatycznie po urządzeniu). Stan jedzie do klienta atrybutem gracza
-- `Config.Graphics.AttributeName`, ustawianym po wczytaniu danych i po każdej zmianie —
-- atrybut nie gubi się jak RemoteEvent, gdy klient jeszcze nie słucha (hard rule 9).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)

local SettingsService = {}

local GFX = Config.Graphics

local lastAppliedAt: { [Player]: number } = {}
-- Wybór zrobiony w TEJ sesji. Gdy gracz kliknie, zanim wczytają się jego dane (DataStore
-- potrafi się spóźnić o kilka sekund), późniejsze „loaded” nie może cofnąć kliknięcia
-- do starego zapisu — zamiast tego dopisujemy świeży wybór do wczytanych danych.
local chosen: { [Player]: string } = {}
-- Ostatni wybór czekający na koniec limitu. Kliknięcie w trakcie limitu NIE przepada:
-- zapisujemy najnowszy wybór, gdy limit minie — „kliknąłem Pełny, a zapisał się
-- Ziemniak” wkurza bardziej niż pół sekundy zwłoki.
local pendingMode: { [Player]: string } = {}
local initialized = false

local function isValidMode(mode: any): boolean
	return typeof(mode) == "string" and GFX.Profiles[mode] ~= nil
end

local apply: (Player, string) -> ()

local function publish(player: Player, data: any)
	local fresh = chosen[player]
	if fresh then
		apply(player, fresh)
		return
	end
	local settings = if type(data) == "table" then data.settings else nil
	local mode = if type(settings) == "table" then settings.graphics else nil
	player:SetAttribute(GFX.AttributeName, if isValidMode(mode) then mode else nil)
end

function apply(player: Player, mode: string)
	lastAppliedAt[player] = os.clock()
	chosen[player] = mode
	-- Zapis w pamięci; DataStore dostanie go przy auto-save / wyjściu (bez kosztu limitu).
	-- Gdy dane gracza jeszcze się nie wczytały, update zwraca false — wybór i tak działa
	-- do końca sesji dzięki atrybutowi, tylko się nie zapisze.
	local saved = PlayerDataService.update(player, function(data)
		if type(data.settings) ~= "table" then
			data.settings = {}
		end
		data.settings.graphics = mode
		return data
	end)
	player:SetAttribute(GFX.AttributeName, mode)
	print(("[Settings] %s tryb grafiki → %s%s"):format(player.Name, mode, if saved then "" else " (dane niewczytane — bez zapisu)"))
end

local function onSetGraphicsMode(player: Player, mode: any)
	if not isValidMode(mode) then return end
	local wait = Config.RateLimits.SetGraphicsMode - (os.clock() - (lastAppliedAt[player] or 0))
	if wait <= 0 then
		apply(player, mode)
		return
	end
	-- W trakcie limitu: zapamiętaj NAJNOWSZY wybór i zapisz go po upływie limitu.
	local alreadyScheduled = pendingMode[player] ~= nil
	pendingMode[player] = mode
	if alreadyScheduled then return end
	task.delay(wait, function()
		local latest = pendingMode[player]
		pendingMode[player] = nil
		if latest and player.Parent then
			apply(player, latest)
		end
	end)
end

function SettingsService.init()
	if initialized then return end
	initialized = true

	PlayerDataService.subscribe(function(eventKey: string, player: Player, _oldData: any, newData: any)
		if eventKey == "loaded" or eventKey == "loaded_default" then
			publish(player, newData)
		end
	end)
	Remotes.SetGraphicsMode.OnServerEvent:Connect(onSetGraphicsMode)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAppliedAt[player] = nil
		pendingMode[player] = nil
		chosen[player] = nil
	end)
end

return SettingsService
