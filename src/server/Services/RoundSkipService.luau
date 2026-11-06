--!strict
-- RoundSkipService.luau (06.11) — kto pomija rundy (Kacper: „ktoś nie chce brać udziału”).
-- Jedyny właściciel tego stanu. PlayerService czyta go przy starcie rundy, a sklep, ekwipunek
-- i kosmetyki pytają, czy gracz stoi w lobby mimo trwającej rundy.
--
-- DWA RÓŻNE STANY:
--   `wants`      — przełącznik gracza. Trwa do odkliknięcia, można go zmienić w każdej chwili.
--   `sittingOut` — ta runda idzie bez niego. Ustala się RAZ, na końcu odliczania w lobby (`lockIn`),
--                  i trzyma do następnego lobby. Dzięki temu kliknięcie w trakcie rundy zmienia
--                  dopiero następną, a gracz na mapie nie dostaje uprawnień gracza z lobby.
--
-- Klient czyta oba stany z atrybutów gracza (bez osobnego Remote'a: dołączający dostaje je sam).
-- Atrybut `SittingOut` jest ustawiany PRZED `PREPARING`, więc zasłona i sklep klienta wiedzą
-- o tym, zanim dojdzie zmiana stanu gry. Stan żyje tylko w tej sesji gracza; bez zapisu w danych.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local RoundSkipService = {}

local CFG = Config.RoundSkip

local wants: { [Player]: boolean } = {}
local sittingOut: { [Player]: boolean } = {}
local lastSetAt: { [Player]: number } = {}
local initialized = false

function RoundSkipService.wantsSkip(player: Player): boolean
	return wants[player] == true
end

function RoundSkipService.isSittingOut(player: Player): boolean
	return sittingOut[player] == true
end

-- Koniec odliczania w lobby: chętni do pominięcia zostają w lobby na całą tę rundę.
function RoundSkipService.lockIn()
	local count = 0
	for player in pairs(wants) do
		if player.Parent == Players then
			sittingOut[player] = true
			player:SetAttribute(CFG.SittingOutAttribute, true)
			count += 1
		end
	end
	if count > 0 then
		print(("[RoundSkip] ta runda bez %d gracz(y)"):format(count))
	end
end

-- Nowe lobby: runda się skończyła, wszyscy znów są w tej samej sytuacji.
function RoundSkipService.releaseAll()
	for player in pairs(sittingOut) do
		player:SetAttribute(CFG.SittingOutAttribute, nil)
	end
	table.clear(sittingOut)
end

function RoundSkipService.init()
	if initialized then return end
	initialized = true
	Remotes.SetSkipRound.OnServerEvent:Connect(function(player: Player, value: any)
		if typeof(value) ~= "boolean" then return end
		local now = os.clock()
		if now - (lastSetAt[player] or 0) < Config.RateLimits.SetSkipRound * Config.RateLimits.ServerTolerance then
			return -- przycisk pokazuje atrybut, więc odrzucone kliknięcie niczego nie rozjedzie
		end
		lastSetAt[player] = now
		wants[player] = if value then true else nil
		player:SetAttribute(CFG.WantsAttribute, if value then true else nil)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		wants[player] = nil
		sittingOut[player] = nil
		lastSetAt[player] = nil
	end)
end

return RoundSkipService
