--!strict
-- A bandage is paid for only after the uninterrupted server-timed wrap finishes.
-- Attributes replicate the gesture; they never authorize healing or consumption.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local ItemService = require(script.Parent.ItemService)
local LoadoutService = require(script.Parent.LoadoutService)
local PlayerService = require(script.Parent.PlayerService)
local GameLoopService = require(script.Parent.GameLoopService)
local RagdollService = require(script.Parent.RagdollService)

local BandageService = {}
local CFG = Config.Bandage
local ITEM_ID = "bandage"

type Wrap = {
	character: Model,
	humanoid: Humanoid,
	tool: Tool,
	endsAt: number,
	connections: { RBXScriptConnection },
}

local equipped: { [Player]: Tool } = {}
local active: { [Player]: Wrap } = {}
local lastUseAt: { [Player]: number } = {}
local lastEquipAt: { [Player]: number } = {}
local characterRemoving: { [Player]: RBXScriptConnection } = {}
local initialized = false

local function cancel(player: Player, expected: Wrap?)
	local wrap = active[player]
	if expected and wrap ~= expected then return end
	active[player] = nil
	if wrap then
		for _, connection in ipairs(wrap.connections) do connection:Disconnect() end
	end
	player:SetAttribute(CFG.StartAttribute, nil)
	player:SetAttribute(CFG.EndAttribute, nil)
end

local function removeTool(player: Player)
	cancel(player)
	local tool = equipped[player]
	equipped[player] = nil
	if tool then tool:Destroy() end
end

local function valid(player: Player, wrap: Wrap): boolean
	return player.Parent == Players
		and PlayerService.isAlive(player)
		and player.Character == wrap.character
		and wrap.humanoid.Parent == wrap.character
		and wrap.humanoid.Health > 0
		and wrap.humanoid.Health < wrap.humanoid.MaxHealth
		and equipped[player] == wrap.tool
		and wrap.tool.Parent == wrap.character
		and LoadoutService.canEquip(player, ITEM_ID)
		and not RagdollService.isRagdolled(player)
end

local function complete(player: Player, wrap: Wrap)
	if active[player] ~= wrap then return end
	if not valid(player, wrap) then cancel(player, wrap); return end
	-- ItemService.consume updates the in-memory inventory without yielding. Keep the
	-- token until consume + heal finish, so repeated requests cannot overlap them.
	if ItemService.consume(player, ITEM_ID, 1) then
		wrap.humanoid.Health = math.min(wrap.humanoid.MaxHealth, wrap.humanoid.Health + CFG.HealAmount)
	end
	cancel(player, wrap)
	if ItemService.getCount(player, ITEM_ID) <= 0 and equipped[player] == wrap.tool then
		removeTool(player)
	end
end

local function useBandage(player: Player, ...: any)
	-- No client-supplied duration, healing amount or target is accepted.
	if select("#", ...) ~= 0 then return end
	local now = os.clock()
	if now - (lastUseAt[player] or -math.huge) < Config.RateLimits.Bandage * Config.RateLimits.ServerTolerance then return end
	lastUseAt[player] = now
	if active[player] then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tool = equipped[player]
	if not character or not humanoid or not tool then return end
	local wrap: Wrap = {
		character = character,
		humanoid = humanoid,
		tool = tool,
		endsAt = Workspace:GetServerTimeNow() + CFG.UseTime,
		connections = {},
	}
	if not valid(player, wrap) or ItemService.getCount(player, ITEM_ID) <= 0 then return end
	active[player] = wrap
	player:SetAttribute(CFG.StartAttribute, wrap.endsAt - CFG.UseTime)
	player:SetAttribute(CFG.EndAttribute, wrap.endsAt)
	table.insert(wrap.connections, humanoid.Died:Connect(function() cancel(player, wrap) end))
	table.insert(wrap.connections, tool.AncestryChanged:Connect(function()
		if tool.Parent ~= character then cancel(player, wrap) end
	end))
	-- Polling also handles a missing/replaced ragdoll folder. The signal catches
	-- a short knockdown that starts and ends between two polling ticks.
	local gui = player:FindFirstChild("PlayerGui")
	local ragdoll = gui and gui:FindFirstChild("ragdoll")
	local variables = ragdoll and ragdoll:FindFirstChild("variables")
	local flag = variables and variables:FindFirstChild("ragdoll")
	if flag and flag:IsA("BoolValue") then
		table.insert(wrap.connections, flag.Changed:Connect(function(value: boolean)
			if value then cancel(player, wrap) end
		end))
	end
end

local function equip(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then return end
	if itemId ~= ITEM_ID then removeTool(player); return end
	local now = os.clock()
	if now - (lastEquipAt[player] or -math.huge) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now
	if not PlayerService.isAlive(player) or not LoadoutService.canEquip(player, ITEM_ID)
		or ItemService.getCount(player, ITEM_ID) <= 0 then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then return end
	local current = equipped[player]
	if current and current.Parent == character then return end
	local definition = ItemDefinitions.get(ITEM_ID)
	local template = definition and Utils.getAsset(definition.toolModel)
	if not template or not template:IsA("Model") then
		warn("[Bandage] missing ReplicatedStorage.Bandage model")
		return
	end
	local tool = Utils.makeHeldTool(template, CFG.ToolName, ITEM_ID, function()
		local r = CFG.GripRotation
		return CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
	end)
	if not tool then return end
	removeTool(player)
	Utils.holdTool(character, tool)
	equipped[player] = tool
end

function BandageService.unequip(player: Player)
	removeTool(player)
end

function BandageService.init()
	if initialized then return end
	initialized = true
	Remotes.UseBandage.OnServerEvent:Connect(useBandage)
	Remotes.EquipItem.OnServerEvent:Connect(equip)
	Remotes.UnequipItem.OnServerEvent:Connect(function(player: Player)
		-- Cancellation must not be discarded by the equip cooldown: otherwise a
		-- quick switch could heal after the client has already put the roll away.
		removeTool(player)
	end)
	local function watch(player: Player)
		if characterRemoving[player] then return end
		characterRemoving[player] = player.CharacterRemoving:Connect(function() removeTool(player) end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do watch(player) end
	Players.PlayerRemoving:Connect(function(player: Player)
		removeTool(player)
		local connection = characterRemoving[player]
		if connection then connection:Disconnect() end
		characterRemoving[player] = nil
		lastUseAt[player], lastEquipAt[player] = nil, nil
	end)
	GameLoopService.StateChanged:Connect(function(state: string)
		if state == GameLoopService.STATE.ROUND then return end
		for player in pairs(equipped) do removeTool(player) end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < CFG.CheckInterval then return end
		elapsed = 0
		local now = Workspace:GetServerTimeNow()
		for player, wrap in pairs(active) do
			if not valid(player, wrap) then
				cancel(player, wrap)
			elseif now >= wrap.endsAt then
				complete(player, wrap)
			end
		end
	end)
end

return BandageService
