--!strict
-- RoundSkipState.luau (06.11) — odczyt pomijania rund po stronie klienta. Prawdę trzyma serwer
-- (RoundSkipService) w atrybutach gracza; tu jest tylko jedno miejsce, które je czyta. Helper bez
-- `init`, bez yieldu, więc mogą go wołać kontrolery zanim stanie UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local RoundSkipState = {}

local CFG = Config.RoundSkip
local player = Players.LocalPlayer

-- Przełącznik gracza: chce pomijać rundy.
function RoundSkipState.wantsSkip(): boolean
	return player:GetAttribute(CFG.WantsAttribute) == true
end

-- Bieżąca runda idzie bez niego: stoi w lobby i ma wszystko, co w lobby.
function RoundSkipState.isSittingOut(): boolean
	return player:GetAttribute(CFG.SittingOutAttribute) == true
end

function RoundSkipState.onChanged(cb: () -> ())
	player:GetAttributeChangedSignal(CFG.WantsAttribute):Connect(cb)
	player:GetAttributeChangedSignal(CFG.SittingOutAttribute):Connect(cb)
end

return RoundSkipState
