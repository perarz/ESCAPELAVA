-- Studio Edit only. One-time migration; original carriers are retained outside Workspace.
assert(not game:GetService("RunService"):IsRunning(), "Run in Edit mode")
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("InteriorLightingBackup_20261007"), "Migration already applied")
local buildings = assert(workspace.Map:FindFirstChild("Buildings", true))
local plans = {}
for _, old in buildings:GetDescendants() do
	if old:IsA("BasePart") and old.Transparency == 1 and old:FindFirstChildWhichIsA("Light") then
		assert(#old:GetChildren() == 1 and old:GetChildren()[1]:IsA("PointLight"), "Unexpected light carrier contents")
		local building = old
		while building.Parent ~= buildings do building = building.Parent end
		local origin = old.Position
		if building.Name == "GreenBuilding" then origin = Vector3.new(origin.X, origin.Y, -180) end
		local geometry = {}
		for _, part in building:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency == 0
				and not part:FindFirstAncestor("Decorations") and not part:FindFirstAncestor("Lights") then
				table.insert(geometry, part)
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = geometry
		local hit = workspace:Raycast(origin, Vector3.new(0, 15, 0), params)
		assert(hit and hit.Normal.Y < -0.99, "Missing flat ceiling: " .. building.Name)
		table.insert(plans, {old = old, building = building, position = hit.Position, ceiling = hit.Instance})
	end
end
assert(#plans == 7, "Expected exactly seven legacy light carriers")
table.sort(plans, function(a, b)
	if a.building.Name ~= b.building.Name then return a.building.Name < b.building.Name end
	return a.position.Y < b.position.Y
end)

local function makeLamp(variant)
	local model = Instance.new("Model")
	model.Name = variant
	model:SetAttribute("InteriorLampVersion", 1)
	local function part(name, size, position, color, material, cylinder)
		local p = Instance.new("Part")
		p.Name, p.Size = name, size
		p.CFrame = CFrame.new(position) * (cylinder and CFrame.Angles(0, 0, math.pi / 2) or CFrame.identity)
		if cylinder then p.Shape = Enum.PartType.Cylinder end
		-- Obudowy studsowe jak cała mapa (Kacper 08.10: „zmień na studsowe”), świecąca część
		-- zostaje Neonem — plastik nie świeci. `material` niżej to dalej opis wzoru (Metal = obudowa).
		p.Color = color
		if material == Enum.Material.Neon then
			p.Material, p.MaterialVariant = material, ""
		else
			p.Material, p.MaterialVariant = Enum.Material.Plastic, "Studs"
		end
		p.Anchored, p.CanCollide, p.CanTouch = true, false, false
		p.CanQuery, p.Locked = true, false
		p.CastShadow = material ~= Enum.Material.Neon
		for _, face in {"Top", "Bottom", "Left", "Right", "Front", "Back"} do
			p[face .. "Surface"] = Enum.SurfaceType.Smooth
		end
		p.Parent = model
		return p
	end
	local dark = Color3.fromRGB(48, 53, 59)
	local silver = Color3.fromRGB(179, 185, 190)
	local white = Color3.fromRGB(245, 245, 245)
	local body, diffuser
	if variant == "LinearSlim" then
		body = part("Housing", Vector3.new(6.4, .24, .85), Vector3.new(0, -.12, 0), silver, Enum.Material.Metal)
		diffuser = part("Diffuser", Vector3.new(5.9, .18, .60), Vector3.new(0, -.32, 0), white, Enum.Material.Neon)
		for _, x in {-3.08, 3.08} do
			part("EndCap", Vector3.new(.24, .34, .85), Vector3.new(x, -.17, 0), dark, Enum.Material.Metal)
		end
	elseif variant == "LinearIndustrial" then
		body = part("Housing", Vector3.new(7.2, .30, 1.35), Vector3.new(0, -.15, 0), dark, Enum.Material.Metal)
		diffuser = part("Diffuser", Vector3.new(6.6, .22, .95), Vector3.new(0, -.40, 0), white, Enum.Material.Neon)
		for _, z in {-.61, .61} do
			part("SideRail", Vector3.new(7.2, .25, .13), Vector3.new(0, -.41, z), silver, Enum.Material.Metal)
		end
		for _, x in {-3.48, -1.65, 1.65, 3.48} do
			part("RetainingClip", Vector3.new(.13, .10, 1.35), Vector3.new(x, -.55, 0), dark, Enum.Material.Metal)
		end
	else
		body = part("Housing", Vector3.new(.24, 2.8, 2.8), Vector3.new(0, -.12, 0), dark, Enum.Material.Metal, true)
		part("Rim", Vector3.new(.18, 2.6, 2.6), Vector3.new(0, -.31, 0), silver, Enum.Material.Metal, true)
		diffuser = part("Diffuser", Vector3.new(.16, 2.3, 2.3), Vector3.new(0, -.46, 0), white, Enum.Material.Neon, true)
	end
	local light = Instance.new("PointLight")
	light.Name, light.Color = "LampLight", Color3.new(1, 1, 1)
	light.Brightness, light.Range, light.Shadows = 1.5, 40, false
	light.Parent = diffuser
	model.PrimaryPart = body
	model.WorldPivot = CFrame.identity
	return model
end

-- Build off-map first; no originals are removed until every new fixture exists.
local templates = Instance.new("Folder")
templates.Name = "InteriorLampTemplates"
assert(not storage:FindFirstChild(templates.Name), "Template folder already exists")
for _, name in {"LinearSlim", "LinearIndustrial", "RoundCeiling"} do
	makeLamp(name).Parent = templates
end
for i, plan in plans do
	local variant = if plan.building.Name == "GreenBuilding" then (if i % 2 == 1 then "LinearSlim" else "LinearIndustrial")
		elseif plan.building.Name == "OldBuilding1" then "LinearIndustrial" else "RoundCeiling"
	local model = templates[variant]:Clone()
	-- Translate from the ceiling contact plane, independent of PrimaryPart pivot.
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then p.CFrame = CFrame.new(plan.position) * p.CFrame end
	end
	model.Name = variant .. "_" .. string.format("%02d", i)
	model:SetAttribute("OriginalLightPosition", plan.old.Position)
	model.Diffuser.LampLight.Brightness = plan.old:FindFirstChildWhichIsA("Light").Brightness
	model.Diffuser.LampLight.Range = plan.old:FindFirstChildWhichIsA("Light").Range
	plan.model = model
end
local backup = Instance.new("Folder")
backup.Name = "InteriorLightingBackup_20261007"
backup.Parent = storage
templates.Parent = storage
for i, plan in plans do
	local folder = plan.building:FindFirstChild("Decorations")
	if not folder then folder = Instance.new("Folder"); folder.Name = "Decorations"; folder.Parent = plan.building end
	-- A model directly under Decorations remains one prop in the existing destruction system.
	plan.model.Parent = folder
	local entry = Instance.new("Folder")
	entry.Name = plan.building.Name .. "_" .. i
	entry.Parent = backup
	local parentRef = Instance.new("ObjectValue")
	parentRef.Name, parentRef.Value, parentRef.Parent = "OriginalParent", plan.old.Parent, entry
	plan.old.Parent = entry
end
game:GetService("Selection"):Set({plans[1].model})
return "Installed 7 ceiling fixtures; 3 reusable templates; originals retained in ServerStorage."
