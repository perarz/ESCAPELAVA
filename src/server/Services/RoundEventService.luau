--!strict
-- RoundEventService.luau (24.11) — KIEDY dzieje się coś w rundzie. Sam nie wie nic o skrzyniach
-- ani rakietach: losuje chwile z okien `Config.RoundEvents.Schedule`, woła właściciela wydarzenia
-- i ogłasza je klientom (napis, odliczanie, syrena — RoundEventController).
--
-- Nowe wydarzenie = wpis w Schedule i Messages oraz handler niżej. Handler zwraca czas serwera
-- chwili wydarzenia (do odliczania) albo nil, gdy nie miało gdzie się odbyć — wtedy nic nie
-- ogłaszamy, żeby napis nigdy nie obiecał czegoś, czego nie będzie.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local AirstrikeService = require(script.Parent.AirstrikeService)
local GameLoopService = require(script.Parent.GameLoopService)
local LowGravityService = require(script.Parent.LowGravityService)
local SupplyDropService = require(script.Parent.SupplyDropService)
local TrainService = require(script.Parent.TrainService)

local CFG = Config.RoundEvents

local RoundEventService = {}

local HANDLERS: { [string]: () -> number? } = {
	SupplyDrop = SupplyDropService.drop,
	Airstrike = AirstrikeService.strike,
	Train = TrainService.run,
	LowGravity = LowGravityService.start,
}

-- Rośnie przy każdej zmianie stanu gry: zaplanowane wydarzenia z poprzedniej rundy nic nie robią.
local planToken = 0
local rng = Random.new()
local initialized = false

local function log(msg: string)
	print("[RoundEvent] " .. msg)
end

-- Uruchamia wydarzenie teraz. Poza planem woła to tylko DevService (po walidacji uprawnień).
function RoundEventService.trigger(kind: string): boolean
	local handler = HANDLERS[kind]
	if not handler then return false end
	if GameLoopService.getState() ~= GameLoopService.STATE.ROUND then return false end
	-- pcall: błąd jednego wydarzenia nie może zabrać rundzie następnych.
	local ok, result = pcall(handler)
	if not ok then
		warn(("[RoundEvent] %s padło: %s"):format(kind, tostring(result)))
		return false
	end
	if type(result) ~= "number" then
		log(kind .. " — nie odbyło się")
		return false
	end
	Remotes.RoundEvent:FireAllClients(kind, result)
	log(kind)
	return true
end

local function planRound()
	if not CFG.Enabled then return end
	local token = planToken
	for _, entry in ipairs(CFG.Schedule) do
		if rng:NextNumber() > (entry.Chance or 1) then continue end
		local at = Config.Lava.RoundDuration * rng:NextNumber(entry.From, entry.To)
		task.delay(at, function()
			if token == planToken then
				RoundEventService.trigger(entry.Event)
			end
		end)
	end
end

function RoundEventService.init()
	if initialized then return end
	initialized = true

	GameLoopService.StateChanged:Connect(function(newState: string)
		planToken += 1
		if newState == GameLoopService.STATE.ROUND then
			planRound()
		end
	end)
end

return RoundEventService
