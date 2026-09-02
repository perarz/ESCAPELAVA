--!strict
-- PushController.luau
-- Dwie role:
--   1. F key → FireServer Push remote. Server jest authoritative (cooldown 4s, target
--      selection, alive check). Lokalny soft-cooldown żeby nie spamować RPC.
--   2. Odbiera Pushed (server → klient targetu) i aplikuje velocity na własnym HRP.
--      Server NIE może bezpośrednio ustawić velocity na character'ze gracza
--      (NetworkOwner=LocalPlayer → klient nadpisuje natychmiast).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local CooldownBarController = require(script.Parent.CooldownBarController)
local MovementController = require(script.Parent.MovementController)

local PushController = {}

local lastPushAt = 0

local localPlayer = Players.LocalPlayer

local function applyPushVelocity(velocity: Vector3)
	local char = localPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end
	hrp.AssemblyLinearVelocity = velocity
end

function PushController.init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode ~= Enum.KeyCode.F then return end

		local now = os.clock()
		local cd = Config.RateLimits.Push
		if now - lastPushAt < cd then return end
		lastPushAt = now

		Remotes.Push:FireServer()
		CooldownBarController.trigger("push", cd)
	end)

	Remotes.Pushed.OnClientEvent:Connect(function(velocity)
		if typeof(velocity) ~= "Vector3" then return end
		applyPushVelocity(velocity)
		-- Feedback trafienia: krótki shake — czujesz że ktoś Cię pchnął, nie "samo się poleciało".
		MovementController.screenShake(Config.Push.HitShakeIntensity, Config.Push.HitShakeDuration)
	end)
end

return PushController
