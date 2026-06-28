--!strict
-- CashPopupController.luau
-- Floating popup "+10$" / "-50$" nad CashLabel. Każdy CashChanged z delta != 0 spawnuje
-- nowy popup w slocie 1 (najbliżej CashLabel); istniejące przesuwają się w górę o jeden slot.
-- Stack maks Config.Cash.Popup.MaxSlots, najstarszy wycieka z skróconym fade-out (overflow).
--
-- KONTRAKT NAZW (Kacper w Studio):
--   StarterGui.HUD.CashPopupTemplate (TextLabel, Visible=false)
--     - Pozycja: tam gdzie ma się pojawiać slot 1 (tuż nad CashLabel)
--     - Font / TextSize / TextStrokeColor3 / wygląd — Kacper ustawia jak chce
--     - Kod nadpisuje TYLKO: Text, TextColor3, Position, TextTransparency, TextStrokeTransparency
--     - Może mieć UIStroke / UIScale jako children — clone je zachowa
--
-- Performance: max 4 popupów na ekranie, każdy ~3-4 tweeny w lifecycle. Pomijalne.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CashPopupController = {}

local POPUP_CFG = Config.Cash.Popup

type Popup = {
	label: TextLabel,
	scale: UIScale,
	basePos: UDim2,
	slot: number,           -- 1 = najnowszy (najbliżej CashLabel)
	fadeThread: thread?,    -- delayed fade-out (cancel gdy overflow)
	dead: boolean,          -- guard żeby nie odpalić destroy dwa razy
}

local localPlayer = Players.LocalPlayer
local template: TextLabel? = nil
local activePopups: { Popup } = {}    -- index 1 = najnowszy

local function findTemplate(): TextLabel?
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HUD", 10)
	if not hud then
		warn("[CashPopup] PlayerGui.HUD nie istnieje — popup nieaktywny")
		return nil
	end
	local found = hud:FindFirstChild("CashPopupTemplate", true)
	if found and found:IsA("TextLabel") then
		return found
	end
	warn("[CashPopup] HUD.CashPopupTemplate (TextLabel) nie istnieje — popup nieaktywny. " ..
		"Postaw TextLabel o tej nazwie w StarterGui.HUD (Visible=false).")
	return nil
end

local function slotTargetPos(basePos: UDim2, slot: number): UDim2
	-- Slot 1 = basePos, każdy kolejny wyżej o SpacingPixels.
	return basePos + UDim2.fromOffset(0, -(slot - 1) * POPUP_CFG.SpacingPixels)
end

local function killPopup(popup: Popup, fast: boolean)
	if popup.dead then return end
	popup.dead = true
	if popup.fadeThread then
		-- Cancel TYLKO jeśli to nie jest aktualnie wykonujący się thread (czyli wywołanie
		-- killPopup z task.delay callback). task.cancel na running thread rzuca error
		-- "cannot cancel thread" → przerywa killPopup → popup zostaje permanentnie na HUD.
		if popup.fadeThread ~= coroutine.running() then
			pcall(task.cancel, popup.fadeThread)
		end
		popup.fadeThread = nil
	end

	-- Usuń z listy aktywnych (jeśli jeszcze tam jest)
	for i, p in ipairs(activePopups) do
		if p == popup then
			table.remove(activePopups, i)
			break
		end
	end

	local duration = fast and POPUP_CFG.OverflowFadeTime or POPUP_CFG.FadeOutTime
	local targetPos = popup.label.Position + UDim2.fromOffset(0, -POPUP_CFG.DriftUpPixels)
	local tween = TweenService:Create(
		popup.label,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = targetPos,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	tween:Play()
	tween.Completed:Connect(function()
		popup.label:Destroy()
	end)
end

local function spawnPopup(tmpl: TextLabel, delta: number)
	local label = tmpl:Clone()
	label.Name = "CashPopup"
	label.Visible = true

	-- Format: "+10$" / "-50$" — sign zachowany dla negative (delta już ma minus).
	local sign = delta > 0 and "+" or ""
	label.Text = sign .. tostring(delta) .. "$"
	label.TextColor3 = delta > 0 and POPUP_CFG.ColorPositive or POPUP_CFG.ColorNegative
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0

	-- UIScale do pop-in animation. Jeśli template miał własny UIScale, dopisujemy drugi —
	-- nie konflikt, Roblox mnoży scale (UIScale collect multiplicatively).
	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = label

	local basePos = tmpl.Position
	label.Position = basePos
	label.Parent = tmpl.Parent

	local popup: Popup = {
		label = label,
		scale = scale,
		basePos = basePos,
		slot = 1,
		fadeThread = nil,
		dead = false,
	}

	-- Wszystkie istniejące popupy → slot += 1, tween do nowej pozycji.
	for _, existing in ipairs(activePopups) do
		existing.slot += 1
		TweenService:Create(
			existing.label,
			TweenInfo.new(POPUP_CFG.SlotTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = slotTargetPos(existing.basePos, existing.slot) }
		):Play()
	end

	-- Nowy popup na początek listy (index 1 = newest).
	table.insert(activePopups, 1, popup)

	-- Overflow handling: cokolwiek w slot > MaxSlots dostaje fast-fade.
	-- Iteracja od końca, bo killPopup robi table.remove.
	for i = #activePopups, 1, -1 do
		local p = activePopups[i]
		if p.slot > POPUP_CFG.MaxSlots then
			killPopup(p, true)
		end
	end

	-- Pop-in: scale 0.7 → 1.0 z Back EaseOut (lekki overshoot).
	TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CFG.PopInTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.0 }
	):Play()

	-- Po pop-in + steady → fade-out lifecycle. Nilujemy fadeThread PRZED killPopup żeby
	-- guard "fadeThread ~= coroutine.running()" miał zerową szansę odpalić cancel.
	popup.fadeThread = task.delay(POPUP_CFG.PopInTime + POPUP_CFG.SteadyTime, function()
		popup.fadeThread = nil
		killPopup(popup, false)
	end)
end

function CashPopupController.init()
	template = findTemplate()
	if not template then return end
	template.Visible = false  -- ensure (Kacper mógł zapomnieć)

	Remotes.CashChanged.OnClientEvent:Connect(function(_balance: number, delta: number?, _reason: string?)
		if not delta or delta == 0 then return end
		if not template then return end
		spawnPopup(template, delta)
	end)
end

return CashPopupController
