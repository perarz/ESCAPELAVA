--!strict
-- KillFeedController.luau
-- Prosty killfeed w prawym górnym rogu. Słucha Remotes.PlayerKilled i dodaje wpis
-- "killer killed victim" na kilka sekund. Kacper podmieni styling gdy będzie chciał.
--
-- Server side: KillService.processDeath fires PlayerKilled(killer, victim, weapon, reward).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local KillFeedController = {}

local ENTRY_DURATION = 4
local FADE_TIME = 0.4
local MAX_ENTRIES = 5

local screenGui: ScreenGui? = nil
local container: Frame? = nil

local function ensureUI()
	if screenGui and screenGui.Parent then return end
	local pgui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local sg = Instance.new("ScreenGui")
	sg.Name = "KillFeed"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 18
	sg.Parent = pgui

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -20, 0, 20)
	frame.Size = UDim2.new(0, 380, 0, 300)
	frame.BackgroundTransparency = 1
	frame.Parent = sg

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame

	screenGui = sg
	container = frame
end

local orderCounter = 0

local function trimOldest()
	local ctr = container :: Frame
	local entries: { Instance } = {}
	for _, c in ipairs(ctr:GetChildren()) do
		if c:IsA("TextLabel") then table.insert(entries, c) end
	end
	while #entries > MAX_ENTRIES do
		-- Znajdź najniższy LayoutOrder (najstarszy) i usuń
		local oldest = entries[1]
		for _, e in ipairs(entries) do
			if (e :: TextLabel).LayoutOrder < (oldest :: TextLabel).LayoutOrder then
				oldest = e
			end
		end
		oldest:Destroy()
		for i, e in ipairs(entries) do
			if e == oldest then table.remove(entries, i) break end
		end
	end
end

local function addEntry(killerName: string, victimName: string, weapon: string)
	ensureUI()
	local ctr = container :: Frame

	orderCounter += 1

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 26)
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.5
	label.BorderSizePixel = 0
	label.Text = ("%s killed %s"):format(killerName, victimName)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.LayoutOrder = orderCounter
	label.Parent = ctr

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label

	trimOldest()

	task.delay(ENTRY_DURATION - FADE_TIME, function()
		if not label.Parent then return end
		local ti = TweenInfo.new(FADE_TIME)
		TweenService:Create(label, ti, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.delay(FADE_TIME + 0.05, function()
			if label.Parent then label:Destroy() end
		end)
	end)
end

function KillFeedController.init()
	Remotes.PlayerKilled.OnClientEvent:Connect(function(killer: Player?, victim: Player?, weapon: string?, _reward: number?)
		if typeof(killer) ~= "Instance" or not killer:IsA("Player") then return end
		if typeof(victim) ~= "Instance" or not victim:IsA("Player") then return end
		addEntry(killer.Name, victim.Name, type(weapon) == "string" and weapon or "?")
	end)
end

return KillFeedController
