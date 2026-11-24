--!strict
-- LowGravityController.luau (24.11) — niska grawitacja u TEGO gracza. Serwer (LowGravityService)
-- podaje w atrybucie Workspace tylko czas końca; grawitację i wysokość skoku zmieniamy lokalnie, bo
-- fizykę własnej postaci i tak liczy klient. Tylko uczestnik rundy: w lobby i przy obserwowaniu nic
-- się nie zmienia. Serwerowe bomby i zawalenia lecą po swojemu.
--
-- Stan liczony co klatkę z warunków (jak celowanie RPG), a nie ze zdarzeń: koniec czasu, śmierć,
-- koniec rundy i nowa postać same przywracają normalne wartości — nic nie może „zostać” włączone.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.LowGravity

local LowGravityController = {}

local localPlayer = Players.LocalPlayer
local applied = false
local normalGravity = 0
local boosted: Humanoid? = nil
local normalJump = 0
local tint: ColorCorrectionEffect? = nil
local initialized = false

local function setTint(on: boolean)
	local effect = tint
	if not effect then
		effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "LowGravityTint"
		effect.Parent = Lighting
		tint = effect
	end
	TweenService:Create(effect, TweenInfo.new(CFG.TintTime), {
		TintColor = if on then CFG.TintColor else Color3.new(1, 1, 1),
		Brightness = if on then CFG.TintBrightness else 0,
	}):Play()
end

local function restoreJump()
	local hum = boosted
	boosted = nil
	if hum and hum.Parent then hum.JumpHeight = normalJump end
end

local function wanted(): boolean
	if localPlayer:GetAttribute(Config.Spectate.ParticipantAttribute) ~= true then return false end
	local until_ = Workspace:GetAttribute(CFG.UntilAttribute)
	return type(until_) == "number" and Workspace:GetServerTimeNow() < until_
end

local function update()
	local on = wanted()
	if on ~= applied then
		applied = on
		if on then
			normalGravity = Workspace.Gravity
			Workspace.Gravity = normalGravity * CFG.GravityFactor
		else
			Workspace.Gravity = normalGravity
			restoreJump()
		end
		setTint(on)
	end
	if not on then return end
	-- Nowa postać w trakcie (nie powinna się zdarzyć w rundzie) dostaje skok od nowa.
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum ~= boosted then
		restoreJump()
		normalJump = hum.JumpHeight
		hum.JumpHeight = normalJump * CFG.JumpFactor
		boosted = hum
	end
end

function LowGravityController.init()
	if initialized then return end
	initialized = true
	RunService.Heartbeat:Connect(update)
end

return LowGravityController
