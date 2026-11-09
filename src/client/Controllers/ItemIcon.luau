--!strict
-- Model icons work before an uploaded texture is available. The same model is used
-- in the hand and inventory; no network requests or per-frame rendering setup.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Definitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemIcon = {}

function ItemIcon.set(icon: ImageLabel, itemId: string?, transparency: number): boolean
	local def = itemId and Definitions.get(itemId)
	icon.Image = if def and type(def.icon) == "string" then def.icon else ""
	icon.ImageTransparency = transparency
	local existing = icon:FindFirstChild("ModelIcon")
	local modelName = def and def.iconModel
	if icon.Image ~= "" or not modelName then
		if existing then existing:Destroy() end
		return icon.Image ~= ""
	end
	if existing and existing:GetAttribute("ItemId") ~= itemId then
		existing:Destroy()
		existing = nil
	end
	if existing and existing:IsA("ViewportFrame") then
		existing.ImageTransparency = transparency
		return true
	end
	local template = ReplicatedStorage:FindFirstChild(modelName)
	if not template or not template:IsA("Model") then return false end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelIcon"
	viewport:SetAttribute("ItemId", itemId)
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ZIndex = icon.ZIndex
	viewport.Ambient = Config.UI.ModelIcon.Ambient
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Config.UI.ModelIcon.LightDirection
	viewport.ImageTransparency = transparency
	local model = template:Clone()
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BaseScript") then child:Destroy()
		elseif child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide, child.CanTouch, child.CanQuery = false, false, false
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = Config.UI.ModelIcon.FOV
	local distance = size.Magnitude * Config.UI.ModelIcon.DistanceFactor
	camera.CFrame = CFrame.lookAt(cf.Position + Config.UI.ModelIcon.Direction.Unit * distance, cf.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = icon
	return true
end

return ItemIcon
