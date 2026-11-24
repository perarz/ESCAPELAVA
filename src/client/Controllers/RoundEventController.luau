--!strict
-- RoundEventController.luau (24.11) — ogłoszenie wydarzenia rundy: napis na górze ekranu, odliczanie
-- i syrena nalotu. Kiedy i co — decyduje serwer (RoundEventService), tu tylko `Remotes.RoundEvent`.
-- Samą skrzynię rysuje SupplyDropController, rakiety — AirstrikeController.
--
-- Widzą i słyszą to uczestnicy rundy i obserwujący. Kto siedzi w lobby (SKIP, śmierć), tego nie
-- dotyczy — syrena w sklepie tylko by przeszkadzała.
--
-- KONTRAKT (UI w Studio — tu tylko tekst i animacja):
--   HUD.EventMessage (GuiObject, Visible=false w Studio — pokazuje go kod)
--     … TitleLabel (TextLabel) — „AIR RAID!”, kolor z Config
--     … InfoLabel (TextLabel) — „MISSILES HIT A BUILDING IN 8”
--     … Pop (UIScale, opcjonalny) — wskok przy pokazaniu i przy każdej sekundzie
--   Cienie `<Nazwa>Shadow` kopiuje TextShadowController. Brak UI = wydarzenia działają bez napisu.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CFG = Config.RoundEvents
local MSG = CFG.Message
local SIREN = CFG.Siren
local MESSAGES: { [string]: any } = CFG.Messages :: any

local RoundEventController = {}

local localPlayer = Players.LocalPlayer

local root: GuiObject? = nil
local titleLabel: TextLabel? = nil
local infoLabel: TextLabel? = nil
local pop: UIScale? = nil
-- Przezroczystości ustawione w Studio = stan „w pełni widoczny”; wygaszanie wraca do 1.
local fadeTargets: { { inst: Instance, prop: string, base: number } } = {}
local fading: { Tween } = {}
local shownToken = 0 -- żeton: nowe ogłoszenie unieważnia odliczanie i wygaszanie poprzedniego
local siren: Sound? = nil
local sirenToken = 0
local initialized = false

local function inRound(): boolean
	return localPlayer:GetAttribute(Config.Spectate.ParticipantAttribute) == true
		or localPlayer:GetAttribute(Config.Spectate.ActiveAttribute) == true
end

-- ── Syrena ───────────────────────────────────────────────────────────────────────────

local function stopSiren()
	sirenToken += 1
	local token = sirenToken
	local s = siren
	if not (s and s.IsPlaying) then return end
	local tw = TweenService:Create(s, TweenInfo.new(SIREN.FadeOut), { Volume = 0 })
	tw.Completed:Connect(function()
		if token == sirenToken then s:Stop() end
	end)
	tw:Play()
end

-- Dźwięk powstaje i wczytuje się przy starcie gry: pierwszy alarm w Play (24.11) grał przez ~0,5 s
-- bez wczytanego pliku, a syrena ma odezwać się równo z napisem.
local function loadSiren()
	if SIREN.SoundId == "" then return end
	local s = Instance.new("Sound")
	s.Name = "AirRaidSiren"
	s.SoundId = SIREN.SoundId
	s.Parent = SoundService
	siren = s
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({ s }) end)
	end)
end

local function playSiren(untilTime: number)
	local s = siren
	if not s then return end
	sirenToken += 1
	local token = sirenToken
	s.Volume = SIREN.Volume
	s.TimePosition = 0
	s:Play()
	task.delay(math.max(untilTime - Workspace:GetServerTimeNow(), 0), function()
		if token == sirenToken then stopSiren() end
	end)
end

-- ── Napis ────────────────────────────────────────────────────────────────────────────

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

local function popTo(peak: number, time: number)
	local p = pop
	if not p then return end
	p.Scale = peak
	TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function resetFade()
	for _, tw in ipairs(fading) do tw:Cancel() end
	table.clear(fading)
	for _, t in ipairs(fadeTargets) do
		(t.inst :: any)[t.prop] = t.base
	end
end

local function fadeOut(token: number)
	local gui = root
	if not gui or token ~= shownToken then return end
	local ti = TweenInfo.new(MSG.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, t in ipairs(fadeTargets) do
		local tw = TweenService:Create(t.inst, ti, { [t.prop] = 1 })
		table.insert(fading, tw)
		tw:Play()
	end
	task.delay(MSG.FadeTime, function()
		if token == shownToken then gui.Visible = false end
	end)
end

local function hide()
	shownToken += 1
	if root then root.Visible = false end
end

local function setInfo(text: string)
	if infoLabel then infoLabel.Text = text end
end

local function show(kind: string, at: number)
	local gui = root
	local m = MESSAGES[kind]
	if not (gui and m) then return end
	shownToken += 1
	local token = shownToken
	resetFade()
	if titleLabel then
		titleLabel.Text = m.Title
		titleLabel.TextColor3 = m.TitleColor
	end
	gui.Visible = true
	popTo(MSG.PopScale, MSG.PopTime)

	if not string.find(m.Info, "%d", 1, true) then
		setInfo(m.Info)
		task.delay(m.ShowTime, function() fadeOut(token) end)
		return
	end
	task.spawn(function()
		local last: number? = nil
		while token == shownToken do
			local left = math.ceil(at - Workspace:GetServerTimeNow())
			if left <= 0 then break end
			if left ~= last then
				setInfo(m.Info:format(left))
				if last then popTo(MSG.TickPop, MSG.TickPopTime) end
				last = left
			end
			task.wait(0.05)
		end
		if token ~= shownToken then return end
		if m.AfterInfo then
			setInfo(m.AfterInfo)
			popTo(MSG.PopScale, MSG.PopTime)
			task.wait(m.AfterTime)
		end
		fadeOut(token)
	end)
end

function RoundEventController.init()
	if initialized then return end
	initialized = true

	-- Listenery PRZED WaitForChild (hard rule 9).
	Remotes.RoundEvent.OnClientEvent:Connect(function(kind: string?, at: number?)
		if type(kind) ~= "string" or type(at) ~= "number" or not inRound() then return end
		show(kind, at)
		local m = MESSAGES[kind]
		if m and m.Siren then playSiren(at) end
	end)
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
		if newState ~= "ROUND" then
			hide()
			stopSiren()
		end
	end)
	loadSiren()

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("HUD")
		local gui = hud:WaitForChild("EventMessage", 5)
		if not (gui and gui:IsA("GuiObject")) then
			warn("[RoundEventController] HUD.EventMessage nie istnieje — napis wydarzeń wyłączony")
			return
		end
		local t = gui:FindFirstChild("TitleLabel", true)
		local i = gui:FindFirstChild("InfoLabel", true)
		local p = gui:FindFirstChild("Pop", true)
		titleLabel = if t and t:IsA("TextLabel") then t else nil
		infoLabel = if i and i:IsA("TextLabel") then i else nil
		pop = if p and p:IsA("UIScale") then p else nil
		collectFadeTargets(gui)
		gui.Visible = false
		root = gui
	end)
end

return RoundEventController
