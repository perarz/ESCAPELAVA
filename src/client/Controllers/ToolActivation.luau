--!strict
-- Jeden obserwator narzędzi zamiast osobnej kopii dla każdego itemu.
-- Reparentowanie tego samego Toola nie może pomnażać listenerów Activated.
--
-- ⚠️ KLIK NA PC IDZIE Z MYSZY, NIE Z SAMEGO `Tool.Activated` (02.11). Po użyciu itemu i szybkiej
-- zmianie na inny Roblox potrafi nie wołać Activated nowego narzędzia, aż do ponownego
-- wyciągnięcia — klik dochodzi do świata (gameProcessed=false), Tool jest w ręce. Zmierzone
-- 25.10 przy C4 (log DIAG, RPG → C4) i 01–02.11 przy RPG po napoju i napoju po haku (zero linii
-- „klik” przy puszce/wyrzutni w ręce). Dlatego LPM / R2 bez gameProcessed woła item wprost;
-- Activated zostaje drogą dotyku, a ten sam klik z obu stron liczy się raz (`ActivationDedupe`).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local player = Players.LocalPlayer
local ToolActivation = {}

local callbacks: { [string]: () -> () } = {}
local toolConnections: { [Tool]: RBXScriptConnection } = {}
local lastFiredAt: { [Tool]: number } = {}
local characterConnections: { RBXScriptConnection } = {}
local character: Model? = nil
local initialized = false

-- Jedno użycie trzymanego itemu, bez względu na to, która droga przyszła pierwsza.
local function fire(tool: Tool)
	-- Stary sygnał może być już w kolejce, gdy Tool zmieni rodzica.
	if tool.Parent ~= player.Character then return end
	local activate = callbacks[tool.Name]
	if not activate then return end
	local now = os.clock()
	if now - (lastFiredAt[tool] or -math.huge) < Config.ItemEquip.ActivationDedupe then return end
	lastFiredAt[tool] = now
	activate()
end

local function heldTool(): Tool?
	local char = player.Character
	if not char then return nil end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and callbacks[child.Name] then return child end
	end
	return nil
end

local function unhook(tool: Tool)
	local connection = toolConnections[tool]
	if connection then connection:Disconnect() end
	toolConnections[tool] = nil
	lastFiredAt[tool] = nil
end

local function hook(child: Instance)
	if not child:IsA("Tool") or not callbacks[child.Name] or toolConnections[child] then return end
	toolConnections[child] = child.Activated:Connect(function()
		fire(child)
	end)
end

local function detach()
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
	for tool in pairs(toolConnections) do unhook(tool) end
	character = nil
end

local function attach(model: Model)
	detach()
	character = model
	table.insert(characterConnections, model.ChildAdded:Connect(hook))
	table.insert(characterConnections, model.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then unhook(child) end
	end))
	for _, child in ipairs(model:GetChildren()) do hook(child) end
end

function ToolActivation.bind(toolName: string, activate: () -> ())
	callbacks[toolName] = activate
	if not initialized then
		initialized = true
		player.CharacterAdded:Connect(attach)
		player.CharacterRemoving:Connect(function(model)
			if character == model then detach() end
		end)
		if player.Character then attach(player.Character) end
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then return end -- czat, pole tekstowe, klik w przycisk HUD
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
				local tool = heldTool()
				if tool then fire(tool) end
			end
		end)
	elseif character then
		-- Kolejny kontroler może wystartować, gdy jego Tool już jest w postaci.
		for _, child in ipairs(character:GetChildren()) do hook(child) end
	end
end

return ToolActivation
