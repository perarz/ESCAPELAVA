--!strict
-- SettingsController.luau — panel ustawień (26.10). Zębatka `HUD.SettingsCorner.SettingsButton` (prawy górny róg od 27.10)
-- otwiera i zamyka `StarterGui.Settings.Panel`; każdy przycisk panelu z atrybutami `Setting`
-- (klucz z Config.Settings.Options) i `Value` ustawia tę wartość w SettingsState. Wybrany ma
-- zielony gradient `Fill`, pozostałe szary — jak BUY / NOT ENOUGH $ w sklepie.
--
-- Wygląd stoi w Studio (UI_RULES); kod tylko klika, koloruje i animuje. Nowa opcja = wpis w
-- Config.Settings + para przycisków w Studio — bez zmian tutaj.
-- Panel działa też w rundzie (to ustawienia kamery). Klik w przycisk GUI przychodzi jako
-- `gameProcessed`, więc nie odpala itemu w ręce (C4 i reszta to sprawdzają).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local SettingsState = require(script.Parent.SettingsState)

local SettingsController = {}

local CFG = Config.Settings
local player = Players.LocalPlayer

type Entry = { button: GuiButton, key: string, value: any }

local panel: GuiObject? = nil
local pop: UIScale? = nil
local isOpen = false
local entries: { Entry } = {}

local function tween(inst: Instance, time: number, style: Enum.EasingStyle, goal: { [string]: any })
	TweenService:Create(inst, TweenInfo.new(time, style, Enum.EasingDirection.Out), goal):Play()
end

-- Najechanie powiększa, klik krótko wciska (UIScale o nazwie `scaleName`, postawiony w Studio).
local function hookHover(button: GuiButton, scaleName: string)
	local s = button:FindFirstChild(scaleName)
	if not (s and s:IsA("UIScale")) then return end
	local hovered = false
	button.MouseEnter:Connect(function()
		hovered = true
		tween(s, CFG.HoverTime, Enum.EasingStyle.Quad, { Scale = CFG.HoverScale })
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		tween(s, CFG.HoverTime, Enum.EasingStyle.Quad, { Scale = 1 })
	end)
	button.Activated:Connect(function()
		s.Scale = CFG.PressScale
		tween(s, CFG.HoverTime * 2, Enum.EasingStyle.Back, { Scale = if hovered then CFG.HoverScale else 1 })
	end)
end

local function refresh()
	for _, e in ipairs(entries) do
		local fill = e.button:FindFirstChild("Fill")
		local grad = fill and fill:FindFirstChildOfClass("UIGradient")
		if grad then
			local colors = if SettingsState.get(e.key) == e.value then CFG.SelectedColors else CFG.IdleColors
			grad.Color = ColorSequence.new(colors[1], colors[2])
		end
	end
end

local function setOpen(on: boolean)
	if on and player:GetAttribute("CosmeticsOpen") == true then return end
	isOpen = on
	local p = panel
	if not p then return end
	p.Visible = on
	if on and pop then
		pop.Scale = CFG.OpenScale
		tween(pop, CFG.OpenTime, Enum.EasingStyle.Back, { Scale = 1 })
	end
end

local initialized = false
function SettingsController.init()
	if initialized then return end
	initialized = true
	player:GetAttributeChangedSignal("CosmeticsOpen"):Connect(function()
		if player:GetAttribute("CosmeticsOpen") == true then setOpen(false) end
	end)
	SettingsState.onChanged(refresh)

	task.spawn(function()
		local pg = player:WaitForChild("PlayerGui")
		local gui = pg:WaitForChild("Settings", 30)
		local p = gui and gui:FindFirstChild("Panel")
		if not (p and p:IsA("GuiObject")) then
			warn("[Settings] brak StarterGui.Settings.Panel — panel ustawień nieaktywny")
			return
		end
		panel = p
		p.Visible = false
		local body = p:FindFirstChild("Body")
		local s = body and body:FindFirstChild("Pop")
		pop = if s and s:IsA("UIScale") then s else nil

		for _, d in ipairs(p:GetDescendants()) do
			local key = d:GetAttribute("Setting")
			local value = d:GetAttribute("Value")
			if d:IsA("GuiButton") and type(key) == "string" and value ~= nil then
				if not CFG.Options[key] then
					warn(("[Settings] przycisk %s: nieznane ustawienie '%s'"):format(d:GetFullName(), key))
				else
					table.insert(entries, { button = d, key = key, value = value })
					d.Activated:Connect(function()
						SettingsState.set(key, value)
					end)
					hookHover(d, "Hover")
				end
			end
		end
		refresh()

		local close = p:FindFirstChild("CloseButton", true)
		if close and close:IsA("GuiButton") then
			close.Activated:Connect(function() setOpen(false) end)
			hookHover(close, "Hover")
		end

		local hud = pg:WaitForChild("HUD", 30)
		local gear = hud and hud:FindFirstChild("SettingsButton", true)
		if gear and gear:IsA("GuiButton") then
			gear.Activated:Connect(function() setOpen(not isOpen) end)
			hookHover(gear, "Pop")
		else
			warn("[Settings] brak HUD.*.SettingsButton — panelu nie da się otworzyć")
		end
	end)
end

return SettingsController
