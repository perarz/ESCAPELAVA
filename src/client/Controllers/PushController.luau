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

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local PushController = {}

local CLIENT_COOLDOWN = 4  -- match server-side
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
		if now - lastPushAt < CLIENT_COOLDOWN then return end
		lastPushAt = now

		Remotes.Push:FireServer()
	end)

	Remotes.Pushed.OnClientEvent:Connect(function(velocity)
		if typeof(velocity) ~= "Vector3" then return end
		applyPushVelocity(velocity)
	end)
end

return PushController
