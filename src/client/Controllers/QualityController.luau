--!strict
-- QualityController.luau
-- Tryb grafiki gracza (NOWY 2026-09-23): "Potato" (Ziemniak) albo "Full" (Pełny).
-- Pomysł Kacpra: „ziemniak” — minimum graficzne na telefon — i coś lepszego dla tych, co na
-- mocnym PC chcą zobaczyć rozpierdalanie.
--
-- Tryb jest CZYSTO KOSMETYCZNY i wyłącznie po stronie klienta: serwer robi dla wszystkich
-- to samo (te same dziury, te same płyty), a tryb decyduje, ile gruzu, odłamków i efektów
-- ten klient dorysowuje u siebie. Liczby: `Config.Graphics.Profiles`. Czytają je
-- DebrisFXController i ExplosionFXController przy KAŻDYM wybuchu (`profile()`), więc zmiana
-- działa od następnej bomby, bez restartu.
--
-- Skąd bierze się tryb (w tej kolejności):
--   1. zapisany wybór z ustawień — atrybut gracza `Config.Graphics.AttributeName`, który
--      serwer (SettingsService) ustawia po wczytaniu danych
--   2. wybór zrobiony w tej sesji, zanim serwer go potwierdził
--   3. automat: telefon / konsola → Ziemniak, PC → Pełny; na PC Ziemniak także wtedy,
--      gdy gracz sam zjechał suwakiem grafiki Robloxa nisko
--
-- UI (buduje Kacper w StarterGui — kontrakt w `Config.Graphics.UI`): panel `Settings`
-- z przyciskami `GraphicsPotato` / `GraphicsFull` (i opcjonalnym `Close`), przycisk
-- `SettingsButton` w HUD otwierający panel. Wszystko opcjonalne — bez UI działa automat.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Dev = require(ReplicatedStorage.Shared.Modules.Dev)

local QualityController = {}

local GFX = Config.Graphics
local UI = GFX.UI
local player = Players.LocalPlayer

export type Profile = typeof(Config.Graphics.Profiles.Full)

local mode: string = GFX.DefaultDesktop
local localChoice: string? = nil

local changedEvent = Instance.new("BindableEvent")
-- (mode: string) — po każdej zmianie trybu.
QualityController.Changed = changedEvent.Event

local function isValid(m: any): boolean
	return typeof(m) == "string" and GFX.Profiles[m] ~= nil
end

local function autoMode(): string
	if GuiService:IsTenFootInterface() then
		return GFX.DefaultConsole
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return GFX.DefaultTouch
	end
	local ok, level = pcall(function()
		return (UserSettings() :: any):GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic
		and (level :: Enum.SavedQualitySetting).Value <= GFX.LowQualityLevel
	then
		return "Potato"
	end
	return GFX.DefaultDesktop
end

local function resolve(): string
	local saved = player:GetAttribute(GFX.AttributeName)
	if isValid(saved) then
		return saved :: string
	end
	if localChoice then
		return localChoice
	end
	return autoMode()
end

function QualityController.get(): string
	return mode
end

function QualityController.isPotato(): boolean
	return mode == "Potato"
end

function QualityController.profile(): Profile
	return (GFX.Profiles :: any)[mode] :: Profile
end

-- ============================================================================
-- UI ustawień (kontrakt Config.Graphics.UI)
-- ============================================================================

-- Przyciski trybu, które znamy (panel bywa odtwarzany przy respawnie, gdy ResetOnSpawn
-- zostało na true — wtedy dochodzą nowe instancje, stare znikają same).
local modeButtons: { [GuiButton]: string } = setmetatable({}, { __mode = "k" }) :: any
local boundButtons: { [GuiButton]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function refreshMarkers()
	for button, buttonMode in pairs(modeButtons) do
		local marker = button:FindFirstChild(UI.SelectedMarker)
		if marker and marker:IsA("GuiObject") then
			marker.Visible = (buttonMode == mode)
		end
	end
end

local function setMode(newMode: string)
	if newMode == mode then
		refreshMarkers()
		return
	end
	mode = newMode
	refreshMarkers()
	changedEvent:Fire(mode)
	print(("[Quality] tryb grafiki: %s"):format(mode))
end

-- Wybór gracza (UI / klawisz dev). Działa od razu lokalnie, serwer go tylko zapisuje.
function QualityController.set(newMode: string)
	if not isValid(newMode) then return end
	localChoice = newMode
	setMode(newMode)
	Remotes.SetGraphicsMode:FireServer(newMode)
end

local function settingsGui(): ScreenGui?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(UI.ScreenGui)
	if gui and gui:IsA("ScreenGui") then
		return gui
	end
	return nil
end

local function bindButton(inst: Instance)
	if not inst:IsA("GuiButton") or boundButtons[inst] then return end
	local button = inst :: GuiButton
	local name = button.Name
	if name == UI.PotatoButton or name == UI.FullButton then
		local buttonMode = if name == UI.PotatoButton then "Potato" else "Full"
		boundButtons[button] = true
		modeButtons[button] = buttonMode
		button.Activated:Connect(function()
			QualityController.set(buttonMode)
		end)
		refreshMarkers()
	elseif name == UI.OpenButton then
		boundButtons[button] = true
		button.Activated:Connect(function()
			local gui = settingsGui()
			if gui then
				gui.Enabled = not gui.Enabled
			end
		end)
	elseif name == UI.CloseButton and button:FindFirstAncestor(UI.ScreenGui) then
		-- `Close` tylko wewnątrz panelu ustawień — inne okna też mogą mieć swój `Close`.
		boundButtons[button] = true
		button.Activated:Connect(function()
			local gui = settingsGui()
			if gui then
				gui.Enabled = false
			end
		end)
	end
end

local function watchGui(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		bindButton(d)
	end
	root.DescendantAdded:Connect(bindButton)
end

-- ============================================================================
-- Init
-- ============================================================================

local initialized = false
function QualityController.init()
	if initialized then return end
	initialized = true

	mode = resolve()
	print(("[Quality] tryb grafiki: %s (%s)"):format(
		mode,
		if isValid(player:GetAttribute(GFX.AttributeName)) then "zapisany wybór" else "automat"
	))

	player:GetAttributeChangedSignal(GFX.AttributeName):Connect(function()
		setMode(resolve())
	end)

	-- UI podpinamy w osobnym wątku: PlayerGui pojawia się dopiero po spawnie, a kolejne
	-- kontrolery nie mogą na to czekać.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		watchGui(playerGui)
	end)

	-- Klawisz testowy (tylko dev): porównanie trybów, zanim stanie panel ustawień.
	if Dev.isDev(player) then
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or input.KeyCode ~= Config.Dev.GraphicsToggleKey then return end
			QualityController.set(if mode == "Potato" then "Full" else "Potato")
		end)
		print(("[Dev] %s = przełącz tryb grafiki (Ziemniak ↔ Pełny)"):format(Config.Dev.GraphicsToggleKey.Name))
	end
end

return QualityController
