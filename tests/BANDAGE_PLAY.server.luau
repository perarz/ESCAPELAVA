-- Studio-only integration fixture. Run as a temporary ServerScriptService Script in Play.
-- Uses the live service cache and real remotes, restoring inventory/loadout afterwards.
assert(game:GetService("RunService"):IsStudio(), "Studio test only")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local S = game.ServerScriptService.Server.Services
local Data = require(S.PlayerDataService)
local Items = require(S.ItemService)
local Loadout = require(S.LoadoutService)
local Loop = require(S.GameLoopService)
local Dev = require(RS.Shared.Modules.Dev)
local p = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
while not Data.get(p) or not p.Character do task.wait(.1) end
local data = Data.get(p)
local before = { inventory = table.clone(data.inventory), loadout = table.clone(data.loadout), cash = data.cash }
local infinite = Dev.hasInfiniteItems
local restored = false
local remote = Instance.new("RemoteFunction")
remote.Name = "BandageIntegrationTest"
local results = Instance.new("Folder")
results.Name = "BandageIntegrationResults"
results:SetAttribute("Status", "running")
results.Parent = RS
local function restore()
	if restored then return end
	restored = true
	require(S.BandageService).unequip(p)
	Dev.hasInfiniteItems = infinite
	Data.update(p, function(d)
		d.inventory, d.loadout, d.cash = before.inventory, before.loadout, before.cash
		return d
	end)
	Items.replicateTo(p)
	Loadout.replicateTo(p)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root then root.Anchored = false end
end
Dev.hasInfiniteItems = function(who) return who ~= p and infinite(who) end
Data.update(p, function(d)
	d.inventory.bandage = 8
	d.inventory.grapple = math.max(1, d.inventory.grapple or 0)
	d.loadout = { "bandage", "grapple", "energy_drink" }
	return d
end)
Items.replicateTo(p)
Loadout.replicateTo(p)
remote.OnServerInvoke = function(who, command, value)
	assert(who == p)
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if command == "safe" then
		c:PivotTo(CFrame.new(c:GetPivot().Position.X, 250, c:GetPivot().Position.Z))
		c.HumanoidRootPart.Anchored = true
	elseif command == "hp" then h.Health = value
	elseif command == "count" then
		Data.update(p, function(d) d.inventory.bandage = value; return d end)
		Items.replicateTo(p)
	elseif command == "ragdoll" then p.PlayerGui.ragdoll.variables.ragdoll.Value = value
	elseif command == "skip" then Loop.devSkip()
	elseif command == "end" then Loop.devEndRound()
	elseif command == "finish" then
		results:SetAttribute("Report", value.report)
		results:SetAttribute("Error", value.error)
		results:SetAttribute("Status", value.ok and "passed" or "failed")
		restore()
	end
	return { state = Loop.getState(), hp = h and h.Health, count = Items.getCount(p, "bandage"),
		started = p:GetAttribute("BandageStart"), tool = c and c:FindFirstChild("BandageTool") ~= nil }
end
remote.Parent = RS
task.delay(120, function()
	if not restored then restore(); results:SetAttribute("Status", "timed_out_restored") end
end)
-- Install BANDAGE_PLAY.client.luau separately through Studio; game Scripts cannot write Source.
