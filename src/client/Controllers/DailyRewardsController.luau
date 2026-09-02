--!strict
-- DailyRewardsController.luau
-- Menu daily rewards: toggle z DailyRewardsButton, render 7 dni z template'a,
-- CLAIM button → Remotes.ClaimDaily. Stan (streak/claimedToday/countdown) przychodzi
-- z serwera przez DailyRewardsInfo — klient tylko wyświetla i odlicza lokalnie.
--
-- KONTRAKT STUDIO (Kacper stawia, kod szuka rekurencyjnie pod HUD):
--   StarterGui.HUD.DailyRewardsMenu (Frame, Visible=false)
--     ├── CloseButton (GuiButton — może być zagnieżdżony np. w header Frame)
--     ├── StatusLabel (TextLabel) — "Day N ready!" / "Next in 12:34:56"
--     ├── Days (Frame z UIListLayout)
--     │     └── DayTemplate (Frame, Visible=false) — kod klonuje ×7
--     │           ├── DayNumber (TextLabel)     — "1".."7"
--     │           ├── RewardAmount (TextLabel)  — "$50".."$500"
--     │           └── Checkmark (GuiObject)     — Visible=true gdy dzień odebrany
--     └── ClaimButton (GuiButton) — kod ustawia Text gdy to TextButton
--
-- Brak któregokolwiek node'a = warn raz + feature degraduje (menu bez tej części działa).
--
-- ZNANE OGRANICZENIE: gracz online przez północ UTC bez claima widzi stale streak aż do
-- claim/rejoin — server waliduje przy claimie, więc max co widzi to zły numer dnia w UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local ButtonFX = require(script.Parent.ButtonFX)

local DailyRewardsController = {}

local localPlayer = Players.LocalPlayer

-- Server state (ostatni DailyRewardsInfo) + moment odbioru (do lokalnego odliczania).
local streak = 0
local claimedToday = false
local secondsToNext = 0
local infoReceivedAt = 0
local hasInfo = false

-- UI refs
local menu: GuiObject? = nil
local statusLabel: TextLabel? = nil
local claimButton: GuiButton? = nil
local dayTiles: { { checkmark: GuiObject? } } = {}
local uiReady = false

local lastClaimSentAt = 0

local MAX_DAYS = 7

local function remainingSeconds(): number
	if not hasInfo then return 0 end
	return math.max(0, secondsToNext - (os.clock() - infoReceivedAt))
end

local function canClaimNow(): boolean
	-- Po odliczeniu do zera północ minęła — nowy dzień, można claimować niezależnie
	-- od claimedToday z (już nieaktualnego) info.
	return hasInfo and (not claimedToday or remainingSeconds() <= 0)
end

local function nextClaimDay(): number
	-- Dzień który gracz odbierze przy następnym claimie (do tekstu na buttonie).
	-- Cap MAX_DAYS tylko wizualnie — server liczy prawdziwy streak.
	return math.min(streak + 1, MAX_DAYS)
end

local function formatHMS(totalSeconds: number): string
	local s = math.floor(totalSeconds)
	return ("%02d:%02d:%02d"):format(math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

local function render()
	if not uiReady then return end

	local checkedCount = math.min(streak, MAX_DAYS)
	for i, tile in ipairs(dayTiles) do
		local check = tile.checkmark
		if check then
			check.Visible = i <= checkedCount
		end
	end

	local rewards = Config.DailyRewards.Rewards
	if canClaimNow() then
		local day = nextClaimDay()
		local reward = rewards[math.min(day, #rewards)]
		if statusLabel then
			statusLabel.Text = ("Day %d reward ready!"):format(day)
		end
		if claimButton and claimButton:IsA("TextButton") then
			claimButton.Text = ("CLAIM $%d"):format(reward)
		end
	else
		if statusLabel then
			statusLabel.Text = "Next reward in " .. formatHMS(remainingSeconds())
		end
		if claimButton and claimButton:IsA("TextButton") then
			claimButton.Text = "CLAIMED"
		end
	end
end

local function onClaimClicked()
	if not canClaimNow() then return end
	local now = os.clock()
	if now - lastClaimSentAt < Config.RateLimits.DailyClaim then return end
	lastClaimSentAt = now
	Remotes.ClaimDaily:FireServer()
	-- Nie zmieniamy stanu lokalnie — server odpowie świeżym DailyRewardsInfo.
end

local function buildDayTiles(daysContainer: Instance, template: GuiObject)
	local rewards = Config.DailyRewards.Rewards
	for i = 1, MAX_DAYS do
		local tile = template:Clone() :: GuiObject
		tile.Name = "Day" .. i
		tile.Visible = true
		tile.LayoutOrder = i

		local dayNumber = tile:FindFirstChild("DayNumber")
		if dayNumber and dayNumber:IsA("TextLabel") then
			dayNumber.Text = tostring(i)
		end
		local rewardAmount = tile:FindFirstChild("RewardAmount")
		if rewardAmount and rewardAmount:IsA("TextLabel") then
			rewardAmount.Text = ("$%d"):format(rewards[math.min(i, #rewards)])
		end

		local checkmark = tile:FindFirstChild("Checkmark")
		if checkmark and checkmark:IsA("GuiObject") then
			checkmark.Visible = false
			dayTiles[i] = { checkmark = checkmark }
		else
			dayTiles[i] = { checkmark = nil }
		end

		tile.Parent = daysContainer
	end
end

local function setupUI()
	local pgui = localPlayer:WaitForChild("PlayerGui")
	local hud = pgui:WaitForChild("HUD", 10)
	if not hud then
		warn("[DailyRewards] PlayerGui.HUD nie istnieje")
		return
	end

	local menuNode = hud:FindFirstChild("DailyRewardsMenu", true)
	if not menuNode or not menuNode:IsA("GuiObject") then
		warn("[DailyRewards] HUD.DailyRewardsMenu (Frame, Visible=false) nie istnieje — menu nieaktywne. " ..
			"Patrz kontrakt w DailyRewardsController.luau.")
		return
	end
	menu = menuNode

	local status = menuNode:FindFirstChild("StatusLabel", true)
	if status and status:IsA("TextLabel") then
		statusLabel = status
	else
		warn("[DailyRewards] DailyRewardsMenu.StatusLabel (TextLabel) nie istnieje — pomijam")
	end

	local claim = menuNode:FindFirstChild("ClaimButton", true)
	if claim and claim:IsA("GuiButton") then
		claimButton = claim
		claim.Activated:Connect(onClaimClicked)
	else
		warn("[DailyRewards] DailyRewardsMenu.ClaimButton (TextButton) nie istnieje — claim niemożliwy z UI")
	end

	local closeBtn = menuNode:FindFirstChild("CloseButton", true)
	if closeBtn and closeBtn:IsA("GuiButton") then
		closeBtn.Activated:Connect(function()
			menuNode.Visible = false
		end)
	else
		warn("[DailyRewards] DailyRewardsMenu.CloseButton nie istnieje — zamykanie tylko przez toggle")
	end

	local days = menuNode:FindFirstChild("Days", true)
	local template = days and days:FindFirstChild("DayTemplate")
	if days and template and template:IsA("GuiObject") then
		buildDayTiles(days, template)
	else
		warn("[DailyRewards] DailyRewardsMenu.Days.DayTemplate nie istnieje — bez kafelków dni")
	end

	-- Toggle button — DailyRewardsButton to ImageButton (albo Frame z GuiButton w środku,
	-- ten sam pattern co ShopButton).
	-- Rekurencyjnie: DailyRewardsButton siedzi w HUD.SideButtons (UIListLayout), nie płytko pod HUD.
	local toggleContainer = hud:FindFirstChild("DailyRewardsButton", true)
	local toggle: GuiButton? = if toggleContainer and toggleContainer:IsA("GuiButton")
		then toggleContainer :: GuiButton
		else toggleContainer and toggleContainer:FindFirstChildWhichIsA("GuiButton", true)
	if toggle then
		toggle.Activated:Connect(function()
			menuNode.Visible = not menuNode.Visible
			if menuNode.Visible then render() end
		end)
	else
		warn("[DailyRewards] HUD.DailyRewardsButton nie zawiera GuiButton — menu nieotwieralne")
	end

	-- Hover FX na kafelku (ten sam pattern co ShopButton).
	local tile = hud:FindFirstChild("DailyRewardsButtonBG", true) or toggleContainer
	if tile and tile:IsA("GuiObject") then
		ButtonFX.applyTileHover(tile)
	end

	uiReady = true
	render()

	-- Countdown tick — tylko gdy menu otwarte (po co renderować niewidoczne).
	task.spawn(function()
		while true do
			task.wait(1)
			if menuNode.Visible then
				render()
			end
		end
	end)
end

function DailyRewardsController.init()
	-- Listener PRZED setupUI (zasada 9 — WaitForChild yielduje, event mógłby przepaść).
	Remotes.DailyRewardsInfo.OnClientEvent:Connect(function(newStreak: number, newClaimedToday: boolean, newSecondsToNext: number)
		if type(newStreak) ~= "number" or type(newClaimedToday) ~= "boolean" or type(newSecondsToNext) ~= "number" then
			return
		end
		streak = newStreak
		claimedToday = newClaimedToday
		secondsToNext = newSecondsToNext
		infoReceivedAt = os.clock()
		hasInfo = true
		render()
	end)

	task.spawn(setupUI)
end

return DailyRewardsController
