--!strict
-- KillMessageController.luau (10.10) — komunikat „YOU KILLED <nick>” + nagroda, tylko dla zabójcy.
--
-- Projekt z Figmy (węzeł `54:2`), decyzje Kacpra 10.10: środek ekranu nad połową, nick ofiary
-- = DisplayName, kwota = prawdziwa nagroda z serwera (`Config.Rewards.Kill`), stary killfeed
-- dla wszystkich (KillFeedController, UI budowane w kodzie) USUNIĘTY.
--
-- KONTRAKT (UI w Studio — tu tylko tekst i animacja):
--   HUD.KillMessage (GuiObject, Visible=false w Studio — pokazuje go kod)
--     … KillLabel (TextLabel, RichText) — tekst; „KILLED” kolorem `Config.KillMessage.KilledColor`
--     … RewardLabel (TextLabel, opcjonalny) — „+25$”
--     … Pop (UIScale, opcjonalny) — wskok przy pokazaniu
--   Cienie `<Nazwa>Shadow` kopiuje TextShadowController (dla RichText bez znaczników).
--   Wygląd (czaszki, kolory, obrysy, pozycja) ustawia się w Studio.
--
-- Kolejne zabójstwo, gdy komunikat jeszcze wisi = nowy tekst i wskok od nowa (żeton `shownAt`).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CFG = Config.KillMessage

local KillMessageController = {}

local localPlayer = Players.LocalPlayer

local root: GuiObject? = nil
local killLabel: TextLabel? = nil
local rewardLabel: TextLabel? = nil
local pop: UIScale? = nil
-- Przezroczystości ustawione w Studio = stan „w pełni widoczny”; wygaszanie wraca do 1.
local fadeTargets: { { inst: Instance, prop: string, base: number } } = {}
local fading: { Tween } = {}
local shownAt = 0
local initialized = false

local function escapeRich(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

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

local function show(victimName: string, reward: number)
	local gui = root
	if not gui then return end
	if killLabel then
		killLabel.Text = ('YOU <font color="#%s">KILLED</font> %s'):format(CFG.KilledColor:ToHex(), escapeRich(victimName))
	end
	if rewardLabel then
		rewardLabel.Text = ("+%d$"):format(reward)
		rewardLabel.Visible = reward > 0
	end

	-- Wygaszanie poprzedniego komunikatu mogło jeszcze trwać — bez Cancel nadpisałoby nowy.
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

function KillMessageController.init()
	if initialized then return end
	initialized = true
	-- Listener PRZED WaitForChild (hard rule 9). Zabójstwo przed załadowaniem HUD — pomijamy.
	Remotes.PlayerKilled.OnClientEvent:Connect(function(killer: Player?, victim: Player?, _weapon: string?, reward: number?)
		if killer ~= localPlayer then return end
		if typeof(victim) ~= "Instance" or not victim:IsA("Player") then return end
		show(victim.DisplayName, if type(reward) == "number" then reward else 0)
	end)

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("HUD")
		local gui = hud and hud:WaitForChild("KillMessage", 5)
		if not (gui and gui:IsA("GuiObject")) then
			warn("[KillMessageController] HUD.KillMessage nie istnieje — komunikat zabójstwa wyłączony")
			return
		end
		local k = gui:FindFirstChild("KillLabel", true)
		local r = gui:FindFirstChild("RewardLabel", true)
		local p = gui:FindFirstChild("Pop", true)
		killLabel = if k and k:IsA("TextLabel") then k else nil
		rewardLabel = if r and r:IsA("TextLabel") then r else nil
		pop = if p and p:IsA("UIScale") then p else nil
		if not killLabel then warn("[KillMessageController] brak KillLabel w HUD.KillMessage") end
		collectFadeTargets(gui)
		gui.Visible = false
		root = gui
	end)
end

return KillMessageController
