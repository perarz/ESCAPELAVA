-- Edit migration for interior lights stored outside their owning building folders.
assert(not game:GetService("RunService"):IsRunning(), "Edit required")
local storage = game:GetService("ServerStorage")
local templates = assert(storage:FindFirstChild("InteriorLampTemplates"))
assert(not storage:FindFirstChild("InteriorLightingOutsideBackup_20261007"), "Already migrated")
local buildings = assert(workspace.Map:FindFirstChild("Buildings", true))
local geometry = {}
for _, building in buildings:GetChildren() do
	local parts = {}
	for _, p in building:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency == 0 and not p:FindFirstAncestor("Decorations")
			and not p:FindFirstAncestor("Lights") then table.insert(parts, p) end
	end
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Include, parts
	geometry[building] = params
end
local plans = {}
for _, old in workspace.Map:GetDescendants() do
	if old:IsA("BasePart") and old.Transparency == 1 and old:FindFirstChildWhichIsA("Light") then
		assert(#old:GetChildren() == 1 and old:GetChildren()[1]:IsA("PointLight"), "Unexpected carrier contents")
		local candidates = {}
		for building, params in geometry do
			local hit = workspace:Raycast(old.Position, Vector3.new(0, 25, 0), params)
			if hit and hit.Normal.Y < -.99 then table.insert(candidates, {building = building, hit = hit}) end
		end
		assert(#candidates == 1, "Ambiguous/missing ceiling: " .. old:GetFullName())
		local c = candidates[1]
		table.insert(plans, {old = old, building = c.building, position = c.hit.Position})
	end
end
assert(#plans == 45, "Expected 45 external interior carriers; got " .. #plans)
table.sort(plans, function(a, b)
	if a.building.Name ~= b.building.Name then return a.building.Name < b.building.Name end
	if a.position.Y ~= b.position.Y then return a.position.Y < b.position.Y end
	return a.position.X < b.position.X
end)
-- Preflight the full mounting footprint before removing any light.
for i, plan in plans do
	local variant = if plan.building.Name == "PupleHotel" then "RoundCeiling"
		elseif i % 2 == 0 then "LinearIndustrial" else "LinearSlim"
	local extent = if variant == "RoundCeiling" then Vector3.new(1.4, 0, 1.4)
		elseif variant == "LinearIndustrial" then Vector3.new(3.6, 0, .675) else Vector3.new(3.2, 0, .425)
	local function fits(position)
		for _, x in {-1, 0, 1} do for _, z in {-1, 0, 1} do
			local origin = position + extent * Vector3.new(x, 0, z) - Vector3.new(0, .1, 0)
			local hit = workspace:Raycast(origin, Vector3.new(0, .2, 0), geometry[plan.building])
			if not hit or hit.Normal.Y >= -.99 then return false end
		end end
		return true
	end
	if not fits(plan.position) then
		local best, distance
		for y = 0, 2, .5 do for x = -8, 8 do for z = -8, 8 do
			local d = x*x + z*z + y*y
			local candidate = plan.position + Vector3.new(x, y, z)
			if (not distance or d < distance) and fits(candidate) then best, distance = candidate, d end
		end end end
		assert(best, "No complete mounting surface: " .. plan.building.Name)
		plan.position = best
	end
	local model = templates[variant]:Clone()
	model.Name = variant .. "_External_" .. string.format("%02d", i)
	model:SetAttribute("OriginalLightPosition", plan.old.Position)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then p.CFrame = CFrame.new(plan.position) * p.CFrame end
	end
	local previous = plan.old:FindFirstChildWhichIsA("Light")
	model.Diffuser.LampLight.Brightness = previous.Brightness
	model.Diffuser.LampLight.Range = previous.Range
	plan.model = model
end
local backup = Instance.new("Folder")
backup.Name, backup.Parent = "InteriorLightingOutsideBackup_20261007", storage
local counts = {}
for i, plan in plans do
	local decor = plan.building:FindFirstChild("Decorations")
	if not decor then decor = Instance.new("Folder"); decor.Name = "Decorations"; decor.Parent = plan.building end
	plan.model.Parent = decor
	local entry = Instance.new("Folder")
	entry.Name, entry.Parent = plan.building.Name .. "_" .. i, backup
	local ref = Instance.new("ObjectValue")
	ref.Name, ref.Value, ref.Parent = "OriginalParent", plan.old.Parent, entry
	plan.old.Parent = entry
	counts[plan.building.Name] = (counts[plan.building.Name] or 0) + 1
end
return game:GetService("HttpService"):JSONEncode(counts)
