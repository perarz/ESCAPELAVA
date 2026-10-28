--!strict
-- Round transitions: cover teleport during PREPARING, show shared-clock 3/2/1,
-- cover cleanup after FINISHING, unveil lobby once the survivors' teleport settles.
-- Visual templates live in StarterGui; flow tokens cancel obsolete sequences.
-- No camera manipulation. AliveChanged(true) confirms the round teleport.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CFG = Config.RoundTransition

local RoundTransitionController = {}

local player = Players.LocalPlayer

type Target = { obj: GuiObject, bg: number, text: number?, image: number? }

local gui: ScreenGui? = nil
local targets: { Target } = {}
local alpha = 0 -- 0 = niewidoczna, 1 = w pełni zakrywa
local fadeToken = 0 -- nowy fade unieważnia poprzedni
local flowToken = 0 -- nowy stan gry unieważnia poprzednią sekwencję
local aliveAt = -math.huge
local lastState: string? = nil
local countdownGui: ScreenGui? = nil
local countdownTween: Tween? = nil
local countdownConnection: RBXScriptConnection? = nil

local function hideCountdown()
	if countdownTween then countdownTween:Cancel(); countdownTween = nil end
	if countdownConnection then countdownConnection:Disconnect(); countdownConnection = nil end
	if countdownGui then countdownGui.Enabled = false end
end

local function showCountdown(endsAt: number)
	hideCountdown()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local sg = pg and pg:FindFirstChild("RoundCountdown")
	if not (sg and sg:IsA("ScreenGui")) then warn("[RoundTransition] missing StarterGui.RoundCountdown"); return end
	countdownGui = sg
	local holder = sg:FindFirstChild("Digits")
	local pop = holder and holder:FindFirstChild("Pop")
	if not (holder and holder:IsA("Frame") and pop and pop:IsA("UIScale")) then return end
	local lastDigit = -1
	sg.Enabled = true
	local function draw()
		local remaining = math.clamp(math.ceil(endsAt-Workspace:GetServerTimeNow()),0,Config.Game.StartCountdown)
		if remaining == 0 then hideCountdown(); return end
		local camera = Workspace.CurrentCamera
		if camera then
			local side = math.min(camera.ViewportSize.X,camera.ViewportSize.Y)*CFG.CountdownScale
			holder.Size = UDim2.fromOffset(side,side)
		end
		local image = holder:FindFirstChild(tostring(remaining))
		local ready = image and image:IsA("ImageLabel") and ContentProvider:GetAssetFetchStatus(image.Image) == Enum.AssetFetchStatus.Success
		for _,child in holder:GetChildren() do
			if child:IsA("ImageLabel") then child.Visible = ready == true and child == image end
		end
		local fallback = holder:FindFirstChild("Fallback")
		if fallback and fallback:IsA("TextLabel") then
			fallback.Visible = not ready
			fallback.Text = tostring(remaining)
			if image and image:IsA("ImageLabel") then fallback.TextColor3 = image.ImageColor3 end
			local fit = fallback:FindFirstChild("Fit")
			if fit and fit:IsA("UIScale") then fit.Scale = holder.Size.X.Offset/100 end
		end
		local shadow = holder:FindFirstChild("FallbackShadow")
		if shadow and shadow:IsA("TextLabel") and fallback and fallback:IsA("TextLabel") then
			shadow.Visible = fallback.Visible
			shadow.Text = fallback.Text
			local fit = shadow:FindFirstChild("Fit")
			if fit and fit:IsA("UIScale") then fit.Scale = holder.Size.X.Offset/100 end
		end
		if remaining == lastDigit then return end
		lastDigit = remaining
		if countdownTween then countdownTween:Cancel() end
		pop.Scale = CFG.CountdownStartScale
		countdownTween = TweenService:Create(pop,TweenInfo.new(CFG.CountdownPopTime,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
		countdownTween:Play()
	end
	countdownConnection = RunService.RenderStepped:Connect(draw)
	draw()
end

local function ensureGui(): boolean
	if gui and gui.Parent then return true end
	local pgui = player:FindFirstChildOfClass("PlayerGui")
	if not pgui then return false end

	local sg = pgui:FindFirstChild("RoundTransition")
	if sg and sg:IsA("ScreenGui") then
		-- Kopia ze StarterGui odświeżyłaby się przy LoadCharacter na starcie rundy — czyli
		-- w środku przejścia (hard rule 10).
		sg.ResetOnSpawn = false
	else
		warn("[RoundTransition] missing StarterGui.RoundTransition")
		return false
	end
	local screen = sg :: ScreenGui
	screen.IgnoreGuiInset = true
	-- Pod ekranem ładowania (ReplicatedFirst, int32 max), nad całym HUD-em.
	screen.DisplayOrder = 2147483000

	targets = {}
	for _, d in ipairs(screen:GetDescendants()) do
		if d:IsA("GuiObject") then
			local t: Target = { obj = d, bg = d.BackgroundTransparency }
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				t.text = d.TextTransparency
			elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
				t.image = d.ImageTransparency
			end
			table.insert(targets, t)
		end
	end
	gui = screen
	return true
end

local function apply(a: number)
	alpha = a
	local screen = gui
	if not screen then return end
	screen.Enabled = a > 0
	for _, t in ipairs(targets) do
		-- Przezroczystość z Properties to stan a = 1; a = 0 → w pełni przezroczyste.
		t.obj.BackgroundTransparency = 1 - (1 - t.bg) * a
		if t.text then
			(t.obj :: any).TextTransparency = 1 - (1 - t.text) * a
		end
		if t.image then
			(t.obj :: any).ImageTransparency = 1 - (1 - t.image) * a
		end
	end
end

-- Liniowo od bieżącej wartości — przerwany fade nie skacze.
local function fadeTo(target: number, duration: number)
	if not ensureGui() then return end
	fadeToken += 1
	local token = fadeToken
	local from = alpha
	if duration <= 0 or from == target then
		apply(target)
		return
	end
	local started = os.clock()
	task.spawn(function()
		while token == fadeToken do
			local k = math.clamp((os.clock() - started) / duration, 0, 1)
			apply(from + (target - from) * k)
			if k >= 1 then break end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function groundUnder(char: Model): boolean
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	return Workspace:Raycast(hrp.Position, Vector3.new(0, -60, 0), params) ~= nil
end

-- Start rundy: zakryj (jeśli odliczanie nie zdążyło), poczekaj na teleport i oświetlenie.
local function runRoundEntry(token: number)
	local roundAt = os.clock()
	local deadline = roundAt + CFG.PrepareMaxHold
	fadeTo(1, 0)

	local signalDeadline = deadline
	-- `aliveAt` ≥ chwila ROUND minus margines: sygnał mógł przyjść tuż przed tym wątkiem.
	while aliveAt < roundAt - 0.5 and os.clock() < signalDeadline do
		task.wait(0.05)
		if token ~= flowToken then return end
	end
	if aliveAt >= roundAt - 0.5 then
		-- Grunt pod nogami: przy wyłączonym streamingu jest od razu; to tylko bezpiecznik,
		-- gdyby streaming wrócił — nie odsłaniamy gracza nad pustką.
		while os.clock() < deadline do
			local char = player.Character
			if char and groundUnder(char) then break end
			task.wait(0.05)
			if token ~= flowToken then return end
		end
		local settleEnd = math.min(os.clock() + CFG.SettleTime, deadline)
		while os.clock() < settleEnd do
			task.wait(0.05)
			if token ~= flowToken then return end
		end
	end
	if token ~= flowToken then return end
	fadeTo(0, CFG.FadeOutTime)
end

local function onState(newState: string, duration: number?, endsAt: number?)
	hideCountdown()
	flowToken += 1
	local token = flowToken
	local fromRound = newState == "LOBBY" and lastState == "RESETTING"
	lastState = newState

	if newState == "LOBBY" then
		if fromRound then
			-- Prosto z rundy (od 26.10 bez POST_ROUND): zasłona trzyma się ExitHold, aż serwer
			-- przeniesie ocalałych do lobby i ruszy odbudowa mapy — dopiero wtedy odsłaniamy.
			fadeTo(1, 0)
			task.delay(CFG.ExitHold, function()
				if token == flowToken then fadeTo(0, CFG.FadeOutTime) end
			end)
		elseif alpha > 0 then
			-- Zasłona z przerwanego odliczania (ktoś wyszedł) nie zostaje na ekranie.
			fadeTo(0, CFG.FadeOutTime)
		end
		if (duration or 0) > 0 then
			-- Lobby z odliczaniem: ściemnianie tak, żeby skończyło się razem z nim.
			local lead = math.max((duration or 0) - CFG.FadeInTime, 0)
			task.delay(lead, function()
				if token == flowToken then
					fadeTo(1, CFG.FadeInTime)
				end
			end)
		end
	elseif newState == "PREPARING" then
		task.spawn(runRoundEntry, token)
	elseif newState == "COUNTDOWN" then
		fadeTo(0, 0)
		showCountdown(endsAt or (Workspace:GetServerTimeNow()+(duration or Config.Game.StartCountdown)))
	elseif newState == "RESETTING" then
		fadeTo(1, CFG.FadeInTime)
	elseif alpha > 0 then
		-- Odliczanie przerwane albo inny stan — nie zostawiamy ciemnego ekranu.
		fadeTo(0, CFG.FadeOutTime)
	end
end

local initialized = false
function RoundTransitionController.init()
	if initialized then return end
	initialized = true

	-- Listenery od razu (hard rule 9) — GUI dopiero, gdy będzie potrzebne.
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: any, duration: any, endsAt: any)
		if typeof(newState) ~= "string" then return end
		onState(newState, if typeof(duration) == "number" then duration else nil,
			if typeof(endsAt) == "number" then endsAt else nil)
	end)
	task.spawn(function()
		local pg = player:WaitForChild("PlayerGui")
		local digits = pg:WaitForChild("RoundCountdown",10)
		if digits then pcall(function() ContentProvider:PreloadAsync({digits}) end) end
	end)
	Remotes.AliveChanged.OnClientEvent:Connect(function(isAlive: any)
		if isAlive == true then
			aliveAt = os.clock()
		end
	end)
end

return RoundTransitionController
