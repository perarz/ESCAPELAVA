--!strict
-- Jeden obserwator narzędzi zamiast osobnej kopii dla każdego itemu.
-- Reparentowanie tego samego Toola nie może pomnażać listenerów Activated.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local ToolActivation = {}

local callbacks: { [string]: () -> () } = {}
local toolConnections: { [Tool]: RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local character: Model? = nil
local initialized = false

local function unhook(tool: Tool)
	local connection = toolConnections[tool]
	if connection then connection:Disconnect() end
	toolConnections[tool] = nil
end

local function hook(child: Instance)
	if not child:IsA("Tool") or not callbacks[child.Name] or toolConnections[child] then return end
	toolConnections[child] = child.Activated:Connect(function()
		-- Stary sygnał może być już w kolejce, gdy Tool zmieni rodzica.
		if child.Parent ~= player.Character then return end
		local activate = callbacks[child.Name]
		if activate then activate() end
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
	elseif character then
		-- Kolejny kontroler może wystartować, gdy jego Tool już jest w postaci.
		for _, child in ipairs(character:GetChildren()) do hook(child) end
	end
end

return ToolActivation
