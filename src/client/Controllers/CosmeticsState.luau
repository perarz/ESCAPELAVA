--!strict
-- Server snapshots are authoritative; preview selection never changes this state.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local State = {}
local owned: { [string]: boolean } = {}
local equipped: { [string]: string } = {}
local ready = false
local listeners: { () -> () } = {}
function State.isReady(): boolean return ready end
function State.owns(id: string): boolean return owned[id] == true end
function State.equipped(category: string): string? return equipped[category] end
function State.outfit(): { [string]: string } return table.clone(equipped) end
function State.onChanged(callback: () -> ()) table.insert(listeners, callback) end
local initialized = false
function State.init()
	if initialized then return end
	initialized = true
	Remotes.CosmeticsChanged.OnClientEvent:Connect(function(raw: any)
		if type(raw) ~= "table" or type(raw.owned) ~= "table" or type(raw.equipped) ~= "table" then return end
		owned, equipped = {}, {}
		for id, value in pairs(raw.owned) do
			if type(id) == "string" and value == true then owned[id] = true end
		end
		for category, id in pairs(raw.equipped) do
			if type(category) == "string" and type(id) == "string" and owned[id] then equipped[category] = id end
		end
		ready = true
		for _, callback in ipairs(listeners) do task.spawn(callback) end
	end)
end
return State
