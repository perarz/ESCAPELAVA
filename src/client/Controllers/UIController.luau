--!strict
-- UIController.luau
-- KOD NIE BUDUJE ScreenGui — Kacper stawia HUD ręcznie w StarterGui.
-- Ten controller tylko aktualizuje .Text labelów które tam są.
--
-- KONTRAKT NAZW (Kacper buduje w StarterGui):
--   StarterGui.HUD (ScreenGui, ResetOnSpawn=false)
--     └── Main (Frame, dowolny layout/wygląd)
--         ├── StateLabel (TextLabel) — pokazuje stan: "LOBBY" / "GET READY" / "ROUND" / "ROUND OVER"
--         ├── TimerLabel (TextLabel) — countdown aktualnego stanu/fazy: "1:23"
--         ├── PhaseListLabel (TextLabel, RichText=true, opcjonalny) — lista faz z aktualną
--         │   podświetloną, np. "Spawn › <b>Easy</b> › Mid › Hard › Endgame". Widoczny tylko w ROUND.
--         └── CashLabel (TextLabel, opcjonalny) — balans kasy gracza, np. "250$"
--
-- Jeśli któryś element nie istnieje — warn raz, nie crashujemy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local UIController = {}

local localPlayer = Players.LocalPlayer

local stateName: string = "LOBBY"
local stateDuration: number = 0
local stateStartedAt: number = os.clock()

local phaseName: string = ""
local phaseDuration: number = 0
local phaseStartedAt: number = 0
local phaseActive: boolean = false

local cashBalance: number = 0

local function findDescendantLabel(root: Instance, name: string): TextLabel?
	-- Szukamy po nazwie w CAŁYM drzewie HUD (Kacper może umieścić labele gdziekolwiek).
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("TextLabel") then
		return found
	end
	return nil
end

local function findLabels(): (TextLabel?, TextLabel?, TextLabel?, TextLabel?)
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local hud = playerGui:WaitForChild("HUD", 10)
	if not hud then
		warn("[UIController] PlayerGui.HUD (ScreenGui) nie istnieje — HUD nieaktywny")
		return nil, nil, nil, nil
	end

	local stateLabel = findDescendantLabel(hud, "StateLabel")
	local timerLabel = findDescendantLabel(hud, "TimerLabel")
	local phaseListLabel = findDescendantLabel(hud, "PhaseListLabel")
	-- Backward-compat: stara nazwa "CoinLabel" w HUD wciąż działa, ale preferowana "CashLabel".
	local cashLabel = findDescendantLabel(hud, "CashLabel") or findDescendantLabel(hud, "CoinLabel")

	if not stateLabel then warn("[UIController] HUD.*.StateLabel nie istnieje (TextLabel)") end
	if not timerLabel then warn("[UIController] HUD.*.TimerLabel nie istnieje (TextLabel)") end
	-- phaseListLabel i cashLabel są opcjonalne — bez warna

	return stateLabel, timerLabel, phaseListLabel, cashLabel
end

local function buildPhaseList(currentPhase: string): string
	-- RichText: aktualna faza w bold + pomarańczowy, reszta jaśniej-szara.
	local parts = {}
	for _, phase in ipairs(Config.Lava.Phases) do
		if phase.Name == currentPhase then
			table.insert(parts, ('<b><font color="#ffaa33">%s</font></b>'):format(phase.Name))
		else
			table.insert(parts, ('<font color="#888888">%s</font>'):format(phase.Name))
		end
	end
	return table.concat(parts, ' <font color="#555555">›</font> ')
end

local function computeText(): (string, string, string)
	-- 1 licznik na całą rundę — TimerLabel pokazuje czas pozostały aktualnego stanu.
	-- W ROUND stateDuration to suma wszystkich faz (z GameLoopService.totalRoundDuration).
	if stateName == "ROUND" then
		local remaining = stateDuration - (os.clock() - stateStartedAt)
		return "ROUND", Utils.formatTime(math.max(remaining, 0)), ""
	elseif stateName == "COUNTDOWN" then
		local remaining = stateDuration - (os.clock() - stateStartedAt)
		return "GET READY", Utils.formatTime(math.max(remaining, 0)), ""
	elseif stateName == "POST_ROUND" then
		local remaining = stateDuration - (os.clock() - stateStartedAt)
		return "ROUND OVER", Utils.formatTime(math.max(remaining, 0)), ""
	else
		-- LOBBY: countdown do startu rundy
		if stateDuration > 0 then
			local remaining = stateDuration - (os.clock() - stateStartedAt)
			return "LOBBY", Utils.formatTime(math.max(remaining, 0)), ""
		end
		return "LOBBY", ("Players: %d"):format(#Players:GetPlayers()), ""
	end
end

function UIController.init()
	-- Podpinamy listenery PRZED findLabels (które yielduje na WaitForChild),
	-- żeby nie stracić eventów state/phase które server fires podczas naszego yieldu.
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string, duration: number)
		stateName = newState
		stateDuration = duration or 0
		stateStartedAt = os.clock()
		if newState ~= "ROUND" then
			phaseActive = false
		end
	end)

	Remotes.PhaseChanged.OnClientEvent:Connect(function(name: string, _index: number, duration: number)
		phaseName = name
		phaseDuration = duration
		phaseStartedAt = os.clock()
		phaseActive = true
	end)

	Remotes.CashChanged.OnClientEvent:Connect(function(balance: number, _delta: number?, _reason: string?)
		cashBalance = balance
	end)

	local stateLabel, timerLabel, phaseListLabel, cashLabel = findLabels()

	RunService.Heartbeat:Connect(function()
		local stateText, timerText, phaseListText = computeText()
		if stateLabel then stateLabel.Text = stateText end
		if timerLabel then timerLabel.Text = timerText end
		if phaseListLabel then
			phaseListLabel.Text = phaseListText
			phaseListLabel.Visible = phaseListText ~= ""
		end
		if cashLabel then
			cashLabel.Text = tostring(cashBalance) .. "$"
		end
	end)
end

return UIController
