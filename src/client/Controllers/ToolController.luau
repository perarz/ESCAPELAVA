--!strict
-- ToolController.luau
-- Nasłuchuje na Character.ChildAdded → jeśli Tool (BombTool) equipped, podpina Tool.Activated.
-- Gdy Activated: bierze Mouse.Hit jako kierunek i fires ThrowBomb(direction) do serwera.
--
-- Logika throwu została z InputController bo Tool jest standardowym sposobem w Roblox
-- na "trzymanie itemu" — gracz widzi go w ręku, anim ramienia, mobile button on screen
-- pojawia się automatycznie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local CooldownBarController = require(script.Parent.CooldownBarController)
local ItemEquipController = require(script.Parent.ItemEquipController)

local ToolActivation = require(script.Parent.ToolActivation)

local ToolController = {}

local localPlayer = Players.LocalPlayer
local lastThrowAt = 0

-- ⚠️ Pasek cooldownu leciał OPTYMISTYCZNIE — klient odpalał go przy kliknięciu, nie po
-- potwierdzeniu serwera. Poza rundą serwer rzut odrzuca, więc bomba się nie pojawiała,
-- a pasek i tak jechał (zgłoszone 2026-09-21). Trzymamy stan gry i nie ruszamy nic poza
-- ROUND. Serwer waliduje niezależnie — to jest tylko szczerość interfejsu.
local gameState = ""
Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
	gameState = newState
end)

local function onActivated()
	-- ⚠️ Pusty stan = jeszcze nie wiemy (gracz wszedł, `replicateTo` mogło nie dojechać
	-- przed podpięciem tego listenera). Wtedy NIE blokujemy — inaczej dołączający
	-- w trakcie rundy nie mógłby rzucać aż do następnej zmiany stanu, czyli nawet
	-- kilka minut. Serwer i tak waliduje; to jest tylko szczerość paska cooldownu.
	if gameState ~= "" and gameState ~= "ROUND" then return end

	local now = os.clock()
	local cd = Config.RateLimits.BombThrow
	if now - lastThrowAt < cd then return end

	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end

	local mouse = localPlayer:GetMouse()
	local target = mouse.Hit and mouse.Hit.Position
	if not target then return end

	local direction = target - hrp.Position
	if direction.Magnitude < 0.1 then return end

	lastThrowAt = now
	ItemEquipController.cancel()
	Remotes.ThrowBomb:FireServer(direction.Unit)
	CooldownBarController.trigger("bomb", cd)
end



function ToolController.init()
	ToolActivation.bind("BombTool", onActivated)
end

return ToolController
