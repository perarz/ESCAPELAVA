--!strict
-- Disposable local models only. Strip executable/physical state BEFORE parenting.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Definitions = require(ReplicatedStorage.Shared.Modules.CosmeticDefinitions)
local CFG = Config.Cosmetics.UI
local Preview = {}

function Preview.freeze(model: Model)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide, child.CanTouch, child.CanQuery = false, false, false
			child.AssemblyLinearVelocity, child.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
	end
end

function Preview.character(neutral: boolean): Model?
	local source = if neutral then StarterPlayer:FindFirstChild("StarterCharacter") else Players.LocalPlayer.Character
	if not source or not source:IsA("Model") then return nil end
	local archivable = source.Archivable
	source.Archivable = true
	local ok, clone = pcall(function() return source:Clone() end)
	source.Archivable = archivable
	if not ok or not clone then return nil end
	local model = clone :: Model
	local standing = StarterPlayer:FindFirstChild("StarterCharacter")
	-- The preview is an anchored pose: live neck/waist C0 and ragdoll joints
	-- must not survive alongside the independently restored body CFrames.
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("LuaSourceContainer") or child:IsA("Tool") or child:IsA("Accessory")
			or child:IsA("BillboardGui") or child:IsA("SurfaceGui") or child:IsA("Sound")
			or child:IsA("ParticleEmitter") or child:IsA("Trail") or child:IsA("Beam")
			or child:IsA("Constraint") or child:IsA("JointInstance") or child:IsA("Animator") then
			child:Destroy()
		elseif child:IsA("BasePart") then
			local rest = standing and standing:FindFirstChild(child.Name)
			-- Runtime ragdoll helper parts retain world-space positions when the body is
			-- reset to the template pose, corrupting the fitting camera bounding box.
			if child.Parent ~= model or not rest or not rest:IsA("BasePart") then
				child:Destroy()
				continue
			end
			child.PivotOffset = rest.PivotOffset
			child.LocalTransparencyModifier = 0
			if neutral and child.Name ~= "HumanoidRootPart" then child.Color = CFG.MannequinColor end
			-- Our characters share StarterCharacter geometry. Retain the player's colours,
			-- but pose body parts from that rig instead of freezing a running/weapon pose.
			if child.Parent == model and rest and rest:IsA("BasePart") then child.CFrame = rest.CFrame end
		elseif child:IsA("Bone") then
			-- Dynamic heads retain their animated deformation when cloned mid-frame.
			child.Transform = CFrame.identity
		end
	end
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then model.PrimaryPart = rootPart end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.AutoRotate = false
		-- Measured in Play 27.10: once parented, automatic scaling shrank the dynamic head
		-- to 1x1x1 and rebuilt the rig, leaving a 0.09 stud gap under the head. Edit never
		-- runs it, so the static check there looked correct.
		hum.AutomaticScalingEnabled = false
	end
	model.Name = "CosmeticsPreview"
	Preview.freeze(model)
	return model
end

function Preview.outfit(model: Model, outfit: { [string]: string }, selected: string?): boolean
	Definitions.remove(model)
	local selectedDef = if selected then Definitions.get(selected) else nil
	local selectedMounted = selected == nil
	for _, category in ipairs(Definitions.categories) do
		local id = if selectedDef and selectedDef.category == category then selected else outfit[category]
		if id then
			local accessory = Definitions.mount(model, id)
			if id == selected then selectedMounted = accessory ~= nil end
		end
	end
	Preview.freeze(model)
	return selectedMounted
end

-- Returns availability and the point the catalog sways its camera around.
function Preview.card(viewport: ViewportFrame, id: string): (boolean, Vector3)
	viewport:ClearAllChildren()
	local model = Preview.character(true)
	if not model then return false, Vector3.zero end
	local accessory = Definitions.mount(model, id)
	Preview.freeze(model)
	model:PivotTo(CFrame.identity)
	if accessory then
		-- Item-shop tile: the item alone and large. Mounting on the rig first keeps its worn
		-- orientation; the body is then dropped (a grey, cropped mannequin sold nothing).
		for _, child in ipairs(model:GetChildren()) do
			if child ~= accessory then child:Destroy() end
		end
	end
	-- Until the imported asset is available, show an explicitly labelled neutral
	-- mannequin rather than a blank colour tile. It is never a purchasable substitute.
	local world = Instance.new("WorldModel")
	model.Parent = world
	world.Parent = viewport
	local def = Definitions.get(id)
	local box, size = model:GetBoundingBox()
	local center = box.Position
	local direction = if def and def.category == "Back" then CFG.CardBackView else CFG.CardFrontView
	local distance = size.Magnitude / 2 / math.tan(math.rad(CFG.CardFov / 2)) * CFG.CardDistanceFactor
	local cam = Instance.new("Camera")
	cam.FieldOfView = CFG.CardFov
	cam.CFrame = CFrame.lookAt(center + direction.Unit * distance, center)
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	viewport.Ambient, viewport.LightColor, viewport.LightDirection = CFG.CardAmbient, CFG.CardLight, CFG.CardLightDirection
	return accessory ~= nil, center
end

return Preview
