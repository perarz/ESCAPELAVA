--!strict
-- Mikro-animacje przycisków HUD (13.11, Kacper: „COSMETICS się nie powiększa, zrób mikro animacje
-- SKIP ROUND i SPECTATE”). Wszystkie liczby w `Config.HudButtonFx`.
--   hook      — hover rośnie, wciśnięcie ściska, klik odbija (jak INVENTORY); UIScale „Pop” na przycisku
--   skip      — ikona SKIP przesuwa się do przodu przy hover, „strzela” po kliknięciu i co chwilę zachęca
--   spectate  — źrenica oka patrzy za kursorem, klik = mrugnięcie, co kilka sekund mruga sama
-- Moduł niczego nie tworzy w UI poza `UIScale` (jak `InventoryController.scaleOf`); układ i wygląd
-- przycisków zostają w Studio.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.HudButtonFx

local HudButtonFx = {}

type Hooks = { onEnter: (() -> ())?, onLeave: (() -> ())?, onClick: (() -> ())? }

local function scaleOf(obj: Instance, name: string): UIScale
	local s = obj:FindFirstChild(name)
	if s and s:IsA("UIScale") then return s end
	local created = Instance.new("UIScale")
	created.Name = name
	created.Parent = obj
	return created
end

-- Zwraca funkcję „czy kursor jest na przycisku” (dla pętli bezczynności).
function HudButtonFx.hook(btn: GuiButton, hooks: Hooks?): () -> boolean
	local scale = scaleOf(btn, "Pop")
	local hovered = false
	local function to(value: number, time: number, style: Enum.EasingStyle?)
		TweenService:Create(scale, TweenInfo.new(time, style or Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = value,
		}):Play()
	end
	btn.MouseEnter:Connect(function()
		-- Dotyk nie ma najechania, a wyszarzony przycisk (Active = false) nie reaguje.
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch or not btn.Active then return end
		hovered = true
		to(CFG.HoverScale, CFG.HoverTime)
		if hooks and hooks.onEnter then hooks.onEnter() end
	end)
	btn.MouseLeave:Connect(function()
		if not hovered then return end
		hovered = false
		to(1, CFG.HoverTime)
		if hooks and hooks.onLeave then hooks.onLeave() end
	end)
	btn.MouseButton1Down:Connect(function()
		if btn.Active then to(CFG.PressScale, CFG.PressTime, Enum.EasingStyle.Quad) end
	end)
	btn.Activated:Connect(function()
		scale.Scale = CFG.PressScale
		to(if hovered then CFG.HoverScale else 1, CFG.PopTime)
		if hooks and hooks.onClick then hooks.onClick() end
	end)
	return function() return hovered end
end

function HudButtonFx.skip(btn: GuiButton)
	local icon = btn:FindFirstChild("SkipIcon")
	if not (icon and icon:IsA("GuiObject")) then
		HudButtonFx.hook(btn)
		return
	end
	local base = icon.Position
	local function nudge(px: number, time: number, style: Enum.EasingStyle)
		TweenService:Create(icon, TweenInfo.new(time, style, Enum.EasingDirection.Out), {
			Position = base + UDim2.fromOffset(px, 0),
		}):Play()
	end
	local isHovered: () -> boolean
	isHovered = HudButtonFx.hook(btn, {
		onEnter = function() nudge(CFG.SkipHoverNudge, CFG.SkipNudgeTime, Enum.EasingStyle.Quad) end,
		onLeave = function() nudge(0, CFG.SkipNudgeTime, Enum.EasingStyle.Quad) end,
		onClick = function()
			-- Odskok w tył i wystrzał w przód: ikona „skacze” do następnej rundy.
			icon.Position = base + UDim2.fromOffset(-CFG.SkipClickNudge, 0)
			nudge(if isHovered() then CFG.SkipHoverNudge else 0, CFG.SkipClickTime, Enum.EasingStyle.Back)
		end,
	})
	-- Co kilka sekund lekkie „szturchnięcie”, żeby przycisk było widać; tylko gdy nikt nie najeżdża.
	task.spawn(function()
		while btn.Parent do
			task.wait(CFG.SkipIdleEvery)
			if btn.Visible and btn.Active and not isHovered() then
				nudge(CFG.SkipIdleNudge, CFG.SkipNudgeTime, Enum.EasingStyle.Quad)
				task.wait(CFG.SkipNudgeTime + 0.05)
				if not isHovered() then nudge(0, CFG.SkipClickTime, Enum.EasingStyle.Back) end
			end
		end
	end)
end

function HudButtonFx.spectate(btn: GuiButton)
	local eye = btn:FindFirstChild("Eye")
	local pupil = eye and eye:FindFirstChild("Pupil")
	if not (eye and eye:IsA("GuiObject") and pupil and pupil:IsA("GuiObject")) then
		HudButtonFx.hook(btn)
		return
	end
	local eyeObj, pupilObj = eye :: GuiObject, pupil :: GuiObject
	local baseSize = pupilObj.Size
	local offset = Vector2.zero
	local tracking: RBXScriptConnection? = nil
	local blinking = false

	local function blink()
		if blinking then return end
		blinking = true
		local down = TweenService:Create(pupilObj, TweenInfo.new(CFG.EyeBlinkTime, Enum.EasingStyle.Quad), {
			Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset, baseSize.Y.Scale, 3),
		})
		down:Play()
		down.Completed:Wait()
		TweenService:Create(pupilObj, TweenInfo.new(CFG.EyeBlinkTime * 1.4, Enum.EasingStyle.Back), { Size = baseSize }):Play()
		task.wait(CFG.EyeBlinkTime * 1.4)
		blinking = false
	end

	local function stopTracking()
		if tracking then tracking:Disconnect(); tracking = nil end
		offset = Vector2.zero
		TweenService:Create(pupilObj, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	end
	local function startTracking()
		if tracking then return end
		tracking = RunService.RenderStepped:Connect(function(dt: number)
			-- Kursor względem środka oka, w pikselach układu przycisku (UIScale rodziców je skaluje).
			local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
			local center = eyeObj.AbsolutePosition + eyeObj.AbsoluteSize / 2
			local k = math.max(0.01, eyeObj.AbsoluteSize.X / math.max(1, eyeObj.Size.X.Offset))
			local delta = (mouse - center) / k
			local target = if delta.Magnitude > CFG.EyeRadius then delta.Unit * CFG.EyeRadius else delta * 0.6
			offset = offset:Lerp(target, 1 - math.exp(-CFG.EyeFollowRate * dt))
			pupilObj.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		end)
	end

	HudButtonFx.hook(btn, {
		onEnter = startTracking,
		onLeave = stopTracking,
		onClick = function() task.spawn(blink) end,
	})
	btn:GetPropertyChangedSignal("Visible"):Connect(function() if not btn.Visible then stopTracking() end end)
	-- Mruga sama co kilka sekund, tylko gdy przycisk jest widoczny i aktywny.
	task.spawn(function()
		local rng = Random.new()
		while btn.Parent do
			task.wait(rng:NextNumber(CFG.EyeIdleBlinkMin, CFG.EyeIdleBlinkMax))
			if btn.Visible and btn.Active then blink() end
		end
	end)
end

return HudButtonFx
