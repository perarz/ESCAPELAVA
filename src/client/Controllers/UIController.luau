--!strict
-- UIController.luau
-- KOD NIE BUDUJE ScreenGui — Kacper stawia HUD ręcznie w StarterGui.
-- Ten controller tylko aktualizuje .Text labelów które tam są.
--
-- KONTRAKT NAZW (Kacper buduje w StarterGui):
--   StarterGui.HUD (ScreenGui, ResetOnSpawn=false)
--     └── RoundTimer (Frame, od 10.10 projekt z Figmy — labele szukane po nazwie w całym HUD)
--         ├── Title.State.StateLabel (TextLabel) — stan: "LOBBY" / "ROUND" / "ROUND OVER" (GET READY usunięte 11.10)
--         │   (szerokość z tekstu, kreski LineLeft/LineRight trzyma przy nim UIListLayout)
--         ├── TimerLabel (TextLabel) — countdown aktualnego stanu/fazy: "1:23"
--         ├── *Shadow — cienie, tekst kopiuje TextShadowController
--         └── Pop (UIScale, opcjonalny) w `Title` i w `Timer` — wskok (11.10, `Config.UI.Timer`):
--             napis stanu przy każdej zmianie stanu, czas co sekundę w końcówce odliczania,
--             wtedy też gradient czasu robi się czerwony (oryginał ze Studio wraca po końcówce)
--         (CashLabel — od 10.10 pisze go CashCounterController: banknoty i płynna liczba)
--
-- Jeśli któryś element nie istnieje — warn raz, nie crashujemy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local UIController = {}

local localPlayer = Players.LocalPlayer
local CFG_T = Config.UI.Timer

local stateName: string = "LOBBY"
local stateDuration: number = 0
local stateStartedAt: number = os.clock()


local function findDescendantLabel(root: Instance, name: string): TextLabel?
	-- Szukamy po nazwie w CAŁYM drzewie HUD (Kacper może umieścić labele gdziekolwiek).
	local found = root:FindFirstChild(name, true)
	if found and found:IsA("TextLabel") then
		return found
	end
	return nil
end

local function findLabels(): (TextLabel?, TextLabel?)
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local hud = playerGui:WaitForChild("HUD", 10)
	if not hud then
		warn("[UIController] PlayerGui.HUD (ScreenGui) nie istnieje — HUD nieaktywny")
		return nil, nil
	end

	local stateLabel = findDescendantLabel(hud, "StateLabel")
	local timerLabel = findDescendantLabel(hud, "TimerLabel")

	if not stateLabel then warn("[UIController] HUD.*.StateLabel nie istnieje (TextLabel)") end
	if not timerLabel then warn("[UIController] HUD.*.TimerLabel nie istnieje (TextLabel)") end
	return stateLabel, timerLabel
end

-- Zwraca (napis stanu, tekst czasu, pozostałe sekundy albo nil, gdy nie ma odliczania).
local function computeText(): (string, string, number?)
	-- 1 licznik na całą rundę — TimerLabel pokazuje czas pozostały aktualnego stanu.
	-- W ROUND stateDuration = `Config.Lava.RoundDuration` (runda bez faz od 11.10).
	local remaining = math.max(stateDuration - (os.clock() - stateStartedAt), 0)
	if stateName == "ROUND" then
		return "ROUND", Utils.formatTime(remaining), remaining
	elseif stateName == "POST_ROUND" then
		return "ROUND OVER", Utils.formatTime(remaining), remaining
	else
		-- LOBBY: countdown do startu rundy; duration=0 = czekamy na MinPlayers.
		if stateDuration > 0 then
			return "LOBBY", Utils.formatTime(remaining), remaining
		end
		return "LOBBY", ("Players: %d"):format(#Players:GetPlayers()), nil
	end
end

-- Pierwszy `UIScale` o nazwie Pop w przodkach etykiety (Title / Timer), do wskoku.
local function findPop(label: Instance?): UIScale?
	local node = label and label.Parent
	while node and not node:IsA("ScreenGui") do
		local p = node:FindFirstChild("Pop")
		if p and p:IsA("UIScale") then
			return p
		end
		node = node.Parent
	end
	return nil
end

local function popScale(scale: UIScale?, peak: number, time: number)
	if not scale then return end
	scale.Scale = peak
	TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function UIController.init()
	-- Podpinamy listenery PRZED findLabels (które yielduje na WaitForChild),
	-- żeby nie stracić eventów stanu, które server fires podczas naszego yieldu.
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string, duration: number)
		stateName = newState
		stateDuration = duration or 0
		stateStartedAt = os.clock()
	end)

	local stateLabel, timerLabel = findLabels()

	local statePop = findPop(stateLabel)
	local timerPop = findPop(timerLabel)
	local gradient = timerLabel and timerLabel:FindFirstChildOfClass("UIGradient")
	local normalColor = gradient and gradient.Color
	local urgentColor = ColorSequence.new(CFG_T.UrgentTop, CFG_T.UrgentBottom)
	local wasUrgent = false
	local lastSecond: number? = nil

	RunService.Heartbeat:Connect(function()
		local stateText, timerText, remaining = computeText()
		if stateLabel and stateLabel.Text ~= stateText then
			stateLabel.Text = stateText
			popScale(statePop, CFG_T.StatePop, CFG_T.StatePopTime)
		end
		if timerLabel then timerLabel.Text = timerText end

		-- Końcówka odliczania (poza ROUND OVER — tam nic nie grozi): czerwony gradient i wskok
		-- przy każdej nowej sekundzie.
		local urgent = remaining ~= nil and stateName ~= "POST_ROUND" and remaining > 0
			and remaining <= CFG_T.UrgentSeconds
		if urgent ~= wasUrgent then
			wasUrgent = urgent
			if gradient and normalColor then
				gradient.Color = if urgent then urgentColor else normalColor
			end
		end
		local second = if remaining then math.ceil(remaining) else nil
		if urgent and second ~= lastSecond then
			popScale(timerPop, CFG_T.TickPop, CFG_T.TickPopTime)
		end
		lastSecond = second
	end)
end

return UIController
