--!strict
-- LowGravityService.luau (24.11) — 10 s niskiej grawitacji dla uczestników rundy.
--
-- Decyzje Kacpra 24.11: skok ~3× wyższy i wolne opadanie, upadki nie ranią; bomby, gruz i lawa bez
-- zmian. Grawitacji serwera NIE ruszamy: liczy z niej zawalenia, bomby i beczki. Ruch postaci
-- symuluje jej klient, więc to LowGravityController zmienia grawitację u siebie — serwer trzyma
-- tylko czas końca (atrybut Workspace, więc dołączający też go dostaje) i wyłącza obrażenia.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local GameLoopService = require(script.Parent.GameLoopService)

local CFG = Config.LowGravity

local LowGravityService = {}

local endsAt = 0 -- czas serwera
local initialized = false

-- Upadki nie ranią w trakcie i jeszcze chwilę po (FallDamageService).
function LowGravityService.suppressesFalls(): boolean
	return endsAt > 0 and Workspace:GetServerTimeNow() < endsAt + CFG.FallGrace
end

-- Zwraca czas serwera KOŃCA (napis odlicza do niego).
function LowGravityService.start(): number?
	endsAt = Workspace:GetServerTimeNow() + CFG.Duration
	Workspace:SetAttribute(CFG.UntilAttribute, endsAt)
	return endsAt
end

function LowGravityService.init()
	if initialized then return end
	initialized = true

	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState ~= GameLoopService.STATE.ROUND then
			endsAt = 0
			Workspace:SetAttribute(CFG.UntilAttribute, nil)
		end
	end)
end

return LowGravityService
