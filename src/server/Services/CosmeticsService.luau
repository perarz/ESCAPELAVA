--!strict
-- Owns permanent cosmetic ownership/equipment. Previewing is client-only; only these
-- validated intents may change the saved outfit or charge the player's existing cash.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Definitions = require(ReplicatedStorage.Shared.Modules.CosmeticDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)
local CashService = require(script.Parent.CashService)
local AppearanceService = require(script.Parent.AppearanceService)
local GameLoopService = require(script.Parent.GameLoopService)

local CosmeticsService = {}
type State = { owned: { [string]: boolean }, equipped: { [string]: string } }
local windows: { [Player]: { started: number, count: number } } = {}
local prompt: ProximityPrompt? = nil

local function sanitize(raw: any): State
	local state: State = { owned = {}, equipped = {} }
	if type(raw) ~= "table" then return state end
	if type(raw.owned) == "table" then
		for id, owned in pairs(raw.owned) do
			-- A temporarily removed catalog entry must not erase a paid entitlement.
			if type(id) == "string" and #id <= 64 and owned == true then
				state.owned[id] = true
			end
		end
	end
	if type(raw.equipped) == "table" then
		for _, category in ipairs(Definitions.categories) do
			local id = raw.equipped[category]
			local def = if type(id) == "string" then Definitions.get(id) else nil
			if def and def.category == category and state.owned[id] then
				state.equipped[category] = id
			end
		end
	end
	return state
end

function CosmeticsService.replicateTo(player: Player)
	local data = PlayerDataService.get(player)
	if data and player.Parent == Players then
		Remotes.CosmeticsChanged:FireClient(player, sanitize(data.cosmetics))
	end
end

local function applyToCharacter(player: Player, character: Model)
	if player.Character ~= character or player.Parent ~= Players then return end
	local data = PlayerDataService.get(player)
	if not data then return end
	local state = sanitize(data.cosmetics)
	Definitions.remove(character)
	for _, category in ipairs(Definitions.categories) do
		local id = state.equipped[category]
		if id then
			local mounted, accessory, reason = pcall(Definitions.mount, character, id)
			if not mounted or not accessory then
				warn(("[Cosmetics] %s: %s could not be restored (%s)"):format(
					player.Name, id, tostring(if mounted then reason else accessory)))
			end
		end
	end
end

local function npcAnchor(): BasePart?
	local lobby = Workspace:FindFirstChild("Lobby")
	local stall = lobby and lobby:FindFirstChild(Config.Cosmetics.ShopModelName, true)
	local npc = stall and stall:FindFirstChild(Config.Cosmetics.NpcName, true)
	if not npc or not npc:IsA("Model") then return nil end
	local root = npc:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	return npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart")
end

local function livingCharacter(player: Player): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and character.Parent and humanoid and humanoid.Health > 0 then return character end
	return nil
end

local function lobbyOnly(player: Player): (boolean, string?)
	if player.Parent ~= Players then return false, "player_left" end
	if GameLoopService.getState() ~= GameLoopService.STATE.LOBBY then return false, "lobby_only" end
	if not PlayerDataService.isWritable(player) then return false, "data_not_ready" end
	if not livingCharacter(player) then return false, "character_unavailable" end
	return true, nil
end

local function buy(player: Player, id: any): (boolean, string?)
	if type(id) ~= "string" or #id > 64 or not Definitions.get(id) then return false, "unknown_item" end
	local allowed, reason = lobbyOnly(player)
	if not allowed then return false, reason end
	local anchor = npcAnchor()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not anchor or not root or not root:IsA("BasePart") then return false, "shop_unavailable" end
	if not ((anchor.Position - root.Position).Magnitude <= Config.Cosmetics.InteractDistance) then
		return false, "too_far"
	end
	if not character or not Definitions.canMount(character, id) then return false, "asset_unavailable" end
	local price = Definitions.getPrice(id)
	if price == nil then return false, "price_unavailable" end
	local data = PlayerDataService.get(player)
	if sanitize(data.cosmetics).owned[id] then return false, "already_owned" end
	local def = Definitions.get(id) :: Definitions.Definition
	-- This callback only constructs replacements. No yields, asset work or broadcasts
	-- between the ownership check and the single cash+ownership+outfit state commit.
	-- Buying is wearing (Kacper 27.10): a second EQUIP click after paying only annoyed.
	local bought, failure = CashService.purchase(player, price, "buy_cosmetic_" .. id, function(current)
		local state = sanitize(current.cosmetics)
		if state.owned[id] then return nil, "already_owned" end
		state.owned[id] = true
		state.equipped[def.category] = id
		local replacement = table.clone(current)
		replacement.cosmetics = state
		return replacement, nil
	end)
	if bought and player.Character == character then
		-- The saved outfit is already committed; a failed mount is restored on the next spawn.
		local mounted, accessory, reason = pcall(Definitions.mount, character, id)
		if not mounted or not accessory then
			warn(("[Cosmetics] %s: bought %s but mount failed (%s)"):format(
				player.Name, id, tostring(if mounted then reason else accessory)))
		end
	end
	return bought, failure
end

local function equip(player: Player, category: any, id: any): (boolean, string?)
	if type(category) ~= "string" or not table.find(Definitions.categories, category)
		or type(id) ~= "string" or #id > 64 then
		return false, "invalid_payload"
	end
	local allowed, reason = lobbyOnly(player)
	if not allowed then return false, reason end
	local data = PlayerDataService.get(player)
	local state = sanitize(data.cosmetics)
	local character = player.Character :: Model
	if id ~= "" then
		local def = Definitions.get(id)
		if not def or def.category ~= category then return false, "invalid_category" end
		if not state.owned[id] then return false, "not_owned" end
		local mounted, accessory, mountReason = pcall(Definitions.mount, character, id)
		if not mounted then
			warn(("[Cosmetics] %s: mount failed for %s: %s"):format(player.Name, id, tostring(accessory)))
			return false, "asset_unavailable"
		end
		if not accessory then return false, mountReason end
		state.equipped[category] = id
	else
		Definitions.remove(character, category)
		state.equipped[category] = nil
	end
	PlayerDataService.update(player, function(current)
		current.cosmetics = state
		return current
	end)
	return true, nil
end

local function allowRequest(player: Player): boolean
	local now = os.clock()
	local window = windows[player]
	if not window then
		windows[player] = { started = now, count = 1 }
		return true
	end
	if now - window.started >= 1 then
		window.started, window.count = now, 1
		return true
	end
	window.count += 1
	return window.count <= Config.Cosmetics.RequestsPerSecond
end

local function reply(player: Player, action: string, id: any, success: boolean, reason: string?)
	CosmeticsService.replicateTo(player)
	-- Never reflect an arbitrarily large/exotic client payload back over the network.
	local safeId = if type(id) == "string" and #id <= 64 then id else ""
	Remotes.CosmeticResult:FireClient(player, success, action, safeId, reason)
end

local function ensurePrompt()
	local anchor = npcAnchor()
	if not anchor then
		warn("[Cosmetics] ClothesShop NPC is missing; purchases remain disabled")
		return
	end
	local existing = anchor.Parent and anchor.Parent:FindFirstChild(Config.Cosmetics.PromptName, true)
	if existing and existing:IsA("ProximityPrompt") then
		prompt = existing
	else
		local created = Instance.new("ProximityPrompt")
		created.Name = Config.Cosmetics.PromptName
		created.ActionText = "Shop"
		created.ObjectText = "Cosmetics"
		created.KeyboardKeyCode = Config.Shop.PromptKeyCode
		created.MaxActivationDistance = Config.Cosmetics.PromptMaxDistance
		created.RequiresLineOfSight = false
		created.Parent = anchor
		prompt = created
	end
	if prompt then prompt.Enabled = GameLoopService.getState() == GameLoopService.STATE.LOBBY end
end

local initialized = false
function CosmeticsService.init()
	if initialized then return end
	initialized = true
	AppearanceService.setCosmeticsApplier(applyToCharacter)
	PlayerDataService.subscribe(function(eventKey, player, _old, _data)
		if eventKey ~= "loaded" and eventKey ~= "loaded_default" then return end
		if player.Parent ~= Players then return end
		PlayerDataService.update(player, function(current)
			current.cosmetics = sanitize(current.cosmetics)
			return current
		end)
		CosmeticsService.replicateTo(player)
		if player.Character then applyToCharacter(player, player.Character) end
	end)
	Remotes.BuyCosmetic.OnServerEvent:Connect(function(player, id)
		if not allowRequest(player) then return end
		local success, reason = buy(player, id)
		reply(player, "buy", id, success, reason)
	end)
	Remotes.SetCosmetic.OnServerEvent:Connect(function(player, category, id)
		if not allowRequest(player) then return end
		local success, reason = equip(player, category, id)
		reply(player, "equip", id, success, reason)
	end)
	Players.PlayerRemoving:Connect(function(player)
		windows[player] = nil
	end)
	ensurePrompt()
	GameLoopService.StateChanged:Connect(function(state)
		if prompt and prompt.Parent then prompt.Enabled = state == GameLoopService.STATE.LOBBY end
	end)
end

return CosmeticsService
