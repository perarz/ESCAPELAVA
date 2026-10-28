--!strict
-- Catalog IDs are also saved ownership IDs. Keep them stable when replacing models.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Config)

export type Definition = {
	id: string,
	name: string,
	category: string,
	modelName: string,
	bodyPart: string,
	attachmentName: string,
	rarity: string, -- key in Config.Cosmetics.UI.Rarities
}

local CosmeticDefinitions = {}
CosmeticDefinitions.categories = { "Head", "Face", "Torso", "Back" }
CosmeticDefinitions.shopOrder = { "HalloweenPumpkin", "KevlarVest", "SchoolBackpack" }

local definitions: { [string]: Definition } = {
	HalloweenPumpkin = {
		id = "HalloweenPumpkin", name = "Pumpkin Hood", category = "Head",
		modelName = "HalloweenPumpkin", bodyPart = "Head", attachmentName = "HatAttachment", rarity = "Halloween",
	},
	KevlarVest = {
		id = "KevlarVest", name = "Kevlar Vest", category = "Torso",
		modelName = "KevlarVest", bodyPart = "UpperTorso", attachmentName = "BodyFrontAttachment", rarity = "Epic",
	},
	SchoolBackpack = {
		id = "SchoolBackpack", name = "School Backpack", category = "Back",
		modelName = "SchoolBackpack", bodyPart = "UpperTorso", attachmentName = "BodyBackAttachment", rarity = "Rare",
	},
}

function CosmeticDefinitions.get(id: string): Definition?
	return definitions[id]
end

function CosmeticDefinitions.getPrice(id: string): number?
	if not definitions[id] then return nil end
	local price = Config.Cosmetics.Prices[id]
	if type(price) ~= "number" or price ~= price or price < 0 or price == math.huge or price % 1 ~= 0 then
		return nil
	end
	return price
end

-- A missing/broken asset must not be sold as an invisible product. Validation is shared
-- with previews, so the client and server agree about which imported files are usable.
function CosmeticDefinitions.getTemplate(id: string): Accessory?
	local def = definitions[id]
	if not def then return nil end
	local folder = ReplicatedStorage:FindFirstChild(Config.Cosmetics.AssetFolder)
	local asset = folder and folder:FindFirstChild(def.modelName)
	if not asset or not asset:IsA("Accessory") or not asset.Archivable then return nil end
	local handle = asset:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") or not handle.Archivable then return nil end
	local attachment = handle:FindFirstChild(def.attachmentName)
	if not attachment or not attachment:IsA("Attachment") or not attachment.Archivable then return nil end
	-- The existing ragdoll reads the FIRST Handle attachment. Reject ambiguous imports
	-- instead of letting the outfit mount one anchor while ragdoll constrains another.
	if handle:FindFirstChildOfClass("Attachment") ~= attachment then return nil end
	for _, child in ipairs(asset:GetDescendants()) do
		if child:IsA("LuaSourceContainer") or (child:IsA("BasePart") and not child.Archivable) then
			return nil
		end
	end
	return asset
end

function CosmeticDefinitions.remove(character: Model, category: string?)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and child:GetAttribute("CosmeticId") ~= nil
			and (category == nil or child:GetAttribute("CosmeticCategory") == category) then
			local constraints = character:FindFirstChild("RagdollConstraints")
			if constraints then
				for _, constraint in ipairs(constraints:GetChildren()) do
					if constraint:IsA("Constraint") then
						local a0, a1 = constraint.Attachment0, constraint.Attachment1
						if (a0 and a0:IsDescendantOf(child)) or (a1 and a1:IsDescendantOf(child)) then
							constraint:Destroy()
						end
					end
				end
			end
			child:Destroy()
		end
	end
end

function CosmeticDefinitions.canMount(character: Model, id: string): boolean
	local def = definitions[id]
	if not def or not CosmeticDefinitions.getTemplate(id) then return false end
	local body = character:FindFirstChild(def.bodyPart)
	local target = body and body:FindFirstChild(def.attachmentName)
	return body ~= nil and body:IsA("BasePart") and target ~= nil and target:IsA("Attachment")
end

-- Both the real character and the dressing-room copy use the same attachment transform.
-- No HumanoidDescription, resizing, body material changes or gameplay physics here.
function CosmeticDefinitions.mount(character: Model, id: string): (Accessory?, string?)
	local def = definitions[id]
	local template = CosmeticDefinitions.getTemplate(id)
	if not def or not template then return nil, "asset_unavailable" end
	local body = character:FindFirstChild(def.bodyPart)
	local target = body and body:FindFirstChild(def.attachmentName)
	if not body or not body:IsA("BasePart") or not target or not target:IsA("Attachment") then
		return nil, "attachment_missing"
	end
	local accessory = template:Clone()
	local handle = accessory:FindFirstChild("Handle") :: BasePart
	local attachment = handle:FindFirstChild(def.attachmentName) :: Attachment
	local transform = target.WorldCFrame * attachment.CFrame:Inverse() * handle.CFrame:Inverse()
	-- Imported models may contain stale external welds or collidable decoration. Rebuild
	-- a rigid assembly before parenting, so no loose piece can enter character physics.
	for _, child in ipairs(accessory:GetDescendants()) do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") or child:IsA("Constraint") then
			child:Destroy()
		end
	end
	for _, child in ipairs(accessory:GetDescendants()) do
		if child:IsA("BasePart") then
			child.CFrame = transform * child.CFrame
			child.Anchored = false
			child.Massless = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			if child ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = handle, child
				weld.Parent = handle
			end
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "AccessoryWeld"
	weld.Part0, weld.Part1 = handle, body
	weld.C0, weld.C1 = attachment.CFrame, target.CFrame
	weld.Parent = handle
	accessory:SetAttribute("CosmeticId", id)
	accessory:SetAttribute("CosmeticCategory", def.category)
	CosmeticDefinitions.remove(character, def.category)
	accessory.Parent = character
	return accessory, nil
end

return CosmeticDefinitions
