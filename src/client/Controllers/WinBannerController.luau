--!strict
-- WinBannerController.luau
-- Wyświetla banner "NICKNAME WON $100" na środku ekranu po zakończeniu rundy.
-- Słucha Remotes.RoundWon(winners, reward) — jeden label per winner, stack pionowo.
--
-- Kontrakt UI: tworzone dynamicznie w kodzie (żadnych obiektów w Studio dla banner'a).
-- Można to migrować do template'a w StarterGui.HUD.WinBannerTemplate jeśli Kacper chce
-- własny styling (font, gradient, particle) — na razie sensowny default.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local WinBannerController = {}

local BANNER_DURATION = 3.5
local FADE_TIME = 0.5

local screenGui: ScreenGui? = nil
local container: Frame? = nil

local function ensureUI()
	if screenGui and screenGui.Parent then return end
	local pgui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local sg = Instance.new("ScreenGui")
	sg.Name = "WinBanner"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 20
	sg.Parent = pgui

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.35)
	frame.Size = UDim2.new(0, 800, 0, 200)
	frame.BackgroundTransparency = 1
	frame.Parent = sg

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame

	screenGui = sg
	container = frame
end

local function createBanner(text: string)
	ensureUI()
	local ctr = container :: Frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 50)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 42
	label.TextStrokeTransparency = 1
	label.Parent = ctr

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 4
	stroke.Parent = label

	-- Fade-in scale (Back easing) + steady + fade-out.
	label.TextTransparency = 1
	stroke.Transparency = 1
	TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 0 }):Play()

	task.delay(BANNER_DURATION - FADE_TIME, function()
		if not label.Parent then return end
		TweenService:Create(label, TweenInfo.new(FADE_TIME), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(FADE_TIME), { Transparency = 1 }):Play()
		task.delay(FADE_TIME + 0.05, function()
			if label.Parent then label:Destroy() end
		end)
	end)
end

function WinBannerController.init()
	Remotes.RoundWon.OnClientEvent:Connect(function(winners: { Player }?, reward: number?)
		if type(winners) ~= "table" or type(reward) ~= "number" or #winners == 0 then return end
		for _, p in ipairs(winners) do
			if typeof(p) == "Instance" and p:IsA("Player") then
				createBanner(("%s WON $%d"):format(p.Name, reward))
			end
		end
	end)
end

return WinBannerController
