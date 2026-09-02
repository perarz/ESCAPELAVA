--!strict
-- CashDigitsController.luau
-- Licznik kasy renderowany OBRAZKAMI cyfr (sprite strip 0-9 + "$") zamiast TextLabel.
-- Powód: Roblox nie umie teksturować glifów fontu, a design wymaga tekstury studs
-- W literach (jak kafelki HUD / stamina bar). Sprite: studs + zielony gradient + kontur.
--
-- Działanie:
--   * Kontener "CashDigits" (Frame) w HUD — jeśli Kacper postawi własny w Studio,
--     kod go użyje (pozycję/kotwicę kontroluje Kacper); brak → tworzony default
--     w lewym-dolnym rogu (tam gdzie stał CoinLabel).
--   * Remotes.CashChanged → przerysowanie: pool ImageLabelów (bez churnu instancji),
--     ImageRectOffset wybiera znak ze stripa.
--   * CoinLabel zostaje UKRYTY (nośnik danych dla UIController, nie usuwamy — łatwy
--     powrót przez Config.Cash.DigitDisplay.Enabled = false).
--   * HudScale (HudScaleController) skaluje kontener jak każdy top-level element HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CashDigitsController = {}

local CFG = Config.Cash.DigitDisplay

local CHAR_INDEX: { [string]: number } = {
	["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4,
	["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
	["$"] = 10,
}

local container: Frame? = nil
local pool: { ImageLabel } = {}
local currentBalance = 0
local initialized = false

local function digitWidth(): number
	return math.floor(CFG.DigitHeight * CFG.CellWidth / CFG.CellHeight + 0.5)
end

local function render()
	local frame = container
	if not frame then return end

	local text = tostring(currentBalance) .. "$"
	local w = digitWidth()
	local step = w + CFG.Spacing

	-- Pool: dokładaj brakujące ImageLabele, nadmiarowe chowaj (bez Destroy — balance
	-- zmienia się często przy zbieraniu cashu, churn instancji niepotrzebny).
	for i = 1, #text do
		local label = pool[i]
		if not label then
			label = Instance.new("ImageLabel")
			label.Name = "Digit" .. i
			label.BackgroundTransparency = 1
			label.BorderSizePixel = 0
			label.Image = CFG.AssetId
			label.ImageRectSize = Vector2.new(CFG.CellWidth, CFG.CellHeight)
			label.Size = UDim2.fromOffset(w, CFG.DigitHeight)
			label.Parent = frame
			pool[i] = label
		end
		local ch = text:sub(i, i)
		local index = CHAR_INDEX[ch] or 0
		label.ImageRectOffset = Vector2.new(index * CFG.CellWidth, 0)
		label.Position = UDim2.fromOffset((i - 1) * step, 0)
		label.Visible = true
	end
	for i = #text + 1, #pool do
		pool[i].Visible = false
	end

	-- Kontener obejmuje znaki (przydatne przy ręcznym pozycjonowaniu w Studio).
	frame.Size = UDim2.fromOffset(#text * step - CFG.Spacing, CFG.DigitHeight)
end

local function setupUI()
	local pgui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = pgui:WaitForChild("HUD", 10)
	if not hud then
		warn("[CashDigits] PlayerGui.HUD nie istnieje — licznik nieaktywny")
		return
	end

	-- Kacper może postawić własny kontener (pozycja/kotwica z Studio). Fallback: default.
	local existing = hud:FindFirstChild("CashDigits")
	if existing and existing:IsA("Frame") then
		container = existing
	else
		local frame = Instance.new("Frame")
		frame.Name = "CashDigits"
		frame.AnchorPoint = Vector2.new(0, 1)
		frame.Position = UDim2.new(0, 22, 1, -18)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = hud -- HudScaleController.ChildAdded nada UIScale
		container = frame
	end

	-- Stary tekstowy licznik znika z ekranu (dane dla UIController dalej płyną).
	local coin = hud:FindFirstChild("CoinLabel", true)
	if coin and coin:IsA("TextLabel") then
		coin.Visible = false
	end

	render()
end

local function watchLeaderstats()
	-- Init tego kontrolera jest OSTATNI w łańcuchu (po yieldujących kontrolerach) —
	-- pierwszy CashChanged po joinie potrafi przelecieć ZANIM podepniemy listener
	-- (zasada 9: RemoteEvent nie buforuje). Leaderstats.Cash to replikowany IntValue
	-- (mirror PlayerDataService) — wartości nie da się "przegapić". Remote zostaje
	-- jako szybka ścieżka update'u, leaderstats jako źródło stanu początkowego.
	local stats = Players.LocalPlayer:WaitForChild("leaderstats", 15)
	local cash = stats and stats:WaitForChild("Cash", 15)
	if not cash or not cash:IsA("IntValue") then
		warn("[CashDigits] brak leaderstats.Cash — licznik zaktualizuje się dopiero przy zmianie kasy")
		return
	end
	currentBalance = cash.Value
	render()
	cash:GetPropertyChangedSignal("Value"):Connect(function()
		currentBalance = cash.Value
		render()
	end)
end

function CashDigitsController.init()
	if initialized then return end
	initialized = true
	if not CFG.Enabled then return end

	Remotes.CashChanged.OnClientEvent:Connect(function(balance: number, _delta: number?, _reason: string?)
		if type(balance) ~= "number" then return end
		currentBalance = math.max(0, math.floor(balance))
		render()
	end)

	task.spawn(setupUI)
	task.spawn(watchLeaderstats)
end

return CashDigitsController
