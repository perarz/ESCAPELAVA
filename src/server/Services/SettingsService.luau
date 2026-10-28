--!strict
-- SettingsService.luau
-- Ustawienia gracza (26.10, panel ustawień; decyzje Kacpra: strona kamery i efekty kamery,
-- zapis na koncie). JEDYNY właściciel `data.settings`. Same ustawienia działają u klienta
-- (kamerą steruje MovementController) — serwer pilnuje tylko poprawnych wartości i je pamięta.
-- Zapis idzie razem z resztą danych (PlayerDataService: auto-save / wyjście), więc klikanie
-- w panelu nie kosztuje żadnego zapytania do DataStore.
--
-- Wzorzec jak LoadoutService: klient wysyła CAŁY stan po krótkim opóźnieniu (SettingsState),
-- serwer sprowadza każde znane pole do dozwolonej wartości, a odrzuconą prośbę odbija
-- aktualnym stanem — klient nigdy nie zostaje z ustawieniem, którego serwer nie zna.
--
-- API:
--   SettingsService.replicateTo(player) — stan startowy po `ClientReady`

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)

local SettingsService = {}

local OPTIONS = Config.Settings.Options
local lastSetAt: { [Player]: number } = {}

-- Dowolne wejście (zapis z DataStore albo payload klienta) → każde znane pole z dozwoloną
-- wartością, reszta domyślna. Nieznane pola odpadają — także `settings.graphics` z dawnych
-- trybów grafiki (23.09–08.10), które mogą jeszcze siedzieć w starych zapisach.
local function sanitize(raw: any): { [string]: any }
	local src = if type(raw) == "table" then raw else {}
	local out: { [string]: any } = {}
	for key, opt in pairs(OPTIONS) do
		local v = src[key]
		out[key] = if v ~= nil and table.find(opt.Values, v) ~= nil then v else opt.Default
	end
	return out
end

local function same(a: { [string]: any }, b: { [string]: any }): boolean
	for key in pairs(OPTIONS) do
		if a[key] ~= b[key] then return false end
	end
	return true
end

function SettingsService.replicateTo(player: Player)
	local data = PlayerDataService.get(player)
	if data then
		Remotes.SettingsChanged:FireClient(player, sanitize(data.settings))
	end
end

local function onSetSettings(player: Player, raw: any)
	-- Klient zbiera szybkie kliknięcia i wysyła ostatni stan, więc limit nie dotyka człowieka.
	local now = os.clock()
	if now - (lastSetAt[player] or 0) < Config.RateLimits.SetSettings * Config.RateLimits.ServerTolerance then
		SettingsService.replicateTo(player)
		return
	end
	lastSetAt[player] = now

	local data = PlayerDataService.get(player)
	if not data then return end
	local wanted = sanitize(raw)
	if not same(wanted, sanitize(data.settings)) then
		PlayerDataService.update(player, function(d)
			d.settings = wanted
			return d
		end)
	end
	Remotes.SettingsChanged:FireClient(player, wanted)
end

local initialized = false
function SettingsService.init()
	if initialized then return end
	initialized = true

	-- Po wczytaniu od razu do klienta; gdyby jeszcze nie słuchał, dostanie stan z `ClientReady`.
	PlayerDataService.subscribe(function(eventKey, player)
		if eventKey == "loaded" or eventKey == "loaded_default" then
			SettingsService.replicateTo(player)
		end
	end)

	Remotes.SetSettings.OnServerEvent:Connect(onSetSettings)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSetAt[player] = nil
	end)
end

return SettingsService
