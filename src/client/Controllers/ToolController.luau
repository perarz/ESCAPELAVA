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

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local ToolController = {}

local localPlayer = Players.LocalPlayer

local function hookTool(tool: Tool)
	if tool.Name ~= "BombTool" then return end

	tool.Activated:Connect(function()
		local char = localPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then return end

		local mouse = localPlayer:GetMouse()
		local target = mouse.Hit and mouse.Hit.Position
		if not target then return end

		local direction = target - hrp.Position
		if direction.Magnitude < 0.1 then return end

		Remotes.ThrowBomb:FireServer(direction.Unit)
	end)
end

local function hookCharacter(char: Model)
	-- Tool może być parent'ed do character w dowolnym momencie (equip)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookTool(child)
		end
	end)
	-- Pre-existing Tools (rare, ale dla pewności)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			hookTool(c)
		end
	end
end

function ToolController.init()
	if localPlayer.Character then
		hookCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(hookCharacter)
end

return ToolController
