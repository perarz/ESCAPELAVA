--!strict
-- WinMessageController.luau (20.10) — komunikat „YOU SURVIVED!” + nagroda, tylko dla ocalałego.
--
-- Zastąpił WinBannerController (baner „NAME WON $100” dla wszystkich, budowany w kodzie, bez
-- limitu linijek — przegląd 29.09, B-21). Decyzje Kacpra 20.10: widzi go TYLKO ocalały, napis
-- „YOU SURVIVED!”, wygląd jak komunikat zabójstwa (`HUD.KillMessage`).
--
-- KONTRAKT (UI w Studio — tu tylko kwota i animacja):
--   HUD.WinMessage (GuiObject, Visible=false w Studio — pokazuje go kod)
--     … WinLabel (TextLabel) — „YOU SURVIVED!”, tekst i złoty gradient ustawione w Studio
--     … RewardLabel (TextLabel, opcjonalny) — „+100$”
--     … Pop (UIScale, opcjonalny) — wskok przy pokazaniu
--   Cienie `<Nazwa>Shadow` kopiuje TextShadowController.
--
-- Oba komunikaty stoją w tym samym miejscu ekranu: zabójstwo tuż przed końcem rundy wisiałoby
-- pod napisem wygranej, więc pokazanie wygranej chowa `HUD.KillMessage`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CFG = Config.WinMessage

local WinMessageController = {}

local localPlayer = Players.LocalPlayer

local root: GuiObject? = nil
local killMessage: GuiObject? = nil
local rewardLabel: TextLabel? = nil
local pop: UIScale? = nil
-- Przezroczystości ustawione w Studio = stan „w pełni widoczny”; wygaszanie wraca do 1.
local fadeTargets: { { inst: Instance, prop: string, base: number } } = {}
local fading: { Tween } = {}
local shownAt = 0
local initialized = false

local function collectFadeTargets(gui: Instance)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") then
			table.insert(fadeTargets, { inst = d, prop = "TextTransparency", base = d.TextTransparency })
		elseif d:IsA("ImageLabel") then
			table.insert(fadeTargets, { inst = d, prop = "ImageTransparency", base = d.ImageTransparency })
		elseif d:IsA("UIStroke") then
			table.insert(fadeTargets, { inst = d, prop = "Transparency", base = d.Transparency })
		end
	end
end

local function show(reward: number)
	local gui = root
	if not gui then return end
	if rewardLabel then
		rewardLabel.Text = ("+%d$"):format(reward)
		rewardLabel.Visible = reward > 0
	end
	if killMessage then
		killMessage.Visible = false
	end

	for _, tw in ipairs(fading) do
		tw:Cancel()
	end
	table.clear(fading)
	for _, t in ipairs(fadeTargets) do
		(t.inst :: any)[t.prop] = t.base
	end
	gui.Visible = true
	if pop then
		pop.Scale = CFG.PopScale
		TweenService:Create(pop, TweenInfo.new(CFG.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	shownAt += 1
	local token = shownAt
	task.delay(CFG.ShowTime, function()
		if token ~= shownAt then return end
		local ti = TweenInfo.new(CFG.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, t in ipairs(fadeTargets) do
			local tw = TweenService:Create(t.inst, ti, { [t.prop] = 1 })
			table.insert(fading, tw)
			tw:Play()
		end
		task.delay(CFG.FadeTime, function()
			if token == shownAt then gui.Visible = false end
		end)
	end)
end

function WinMessageController.init()
	if initialized then return end
	initialized = true
	-- Listener PRZED WaitForChild (hard rule 9). Serwer wysyła listę ocalałych wszystkim —
	-- komunikat pokazuje tylko ten, kto na niej jest.
	Remotes.RoundWon.OnClientEvent:Connect(function(winners: { Player }?, reward: number?)
		if type(winners) ~= "table" or not table.find(winners, localPlayer) then return end
		show(if type(reward) == "number" then reward else 0)
	end)

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("HUD")
		local gui = hud and hud:WaitForChild("WinMessage", 5)
		if not (gui and gui:IsA("GuiObject")) then
			warn("[WinMessageController] HUD.WinMessage nie istnieje — komunikat wygranej wyłączony")
			return
		end
		local r = gui:FindFirstChild("RewardLabel", true)
		local p = gui:FindFirstChild("Pop", true)
		local k = hud:FindFirstChild("KillMessage")
		rewardLabel = if r and r:IsA("TextLabel") then r else nil
		pop = if p and p:IsA("UIScale") then p else nil
		killMessage = if k and k:IsA("GuiObject") then k else nil
		collectFadeTargets(gui)
		gui.Visible = false
		root = gui
	end)
end

return WinMessageController
