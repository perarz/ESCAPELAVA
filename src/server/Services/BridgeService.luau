--!strict
-- BridgeService.luau
-- Server-authoritative budowanie mostu. Klient w build mode wybiera position+rotationY
-- myszą i klika LMB → BuildBridge Remote → server validate + consume + spawn anchored Part.
--
-- Flow:
--   1. Klient klika hotbar slot z bridge_builder → HotbarController fires EquipItem("bridge_builder")
--   2. Server BridgeService.onEquip → validate alive + count > 0 → fire BridgeBuildMode(true)
--   3. Klient enters build mode (BridgeController) — ghost preview podąża za myszą, R obraca
--   4. Klient LMB → fires BuildBridge(position, rotationY)
--   5. Server validate (alive, count > 0, distance ≤ max, typecheck) → atomic consume → spawn
--   6. Po consume jeśli count == 0 → fire BridgeBuildMode(false) (forced exit), inaczej zostaje
--   7. UnequipItem → BridgeService.onUnequip → fire BridgeBuildMode(false)
--
-- Most:
--   - Anchored BasePart 10×1×2 (width × thickness × length) z ItemDefinitions.bridge_builder
--   - Wood material, brown color (default; Kacper może podrzucić ReplicatedStorage.BridgeTemplate)
--   - W Workspace.ActiveBridges folder (osobno od Map żeby MapService nie tknął, ale TEŻ żeby
--     bombs.isProtected NIE pomijał — chcemy żeby bomba mogła wybić most)
--   - Cleanup po RoundEnded (jak ActiveCash)
--
-- Decyzja "bomba niszczy most": NIE dodaję ActiveBridges do isProtected w BombService.
-- Bomba unanchorzuje most + impulse — gracz może go zrzucić w lawę PvP sabotaż.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local ItemService = require(script.Parent.ItemService)
local PlayerService = require(script.Parent.PlayerService)
local GameLoopService = require(script.Parent.GameLoopService)

local BridgeService = {}

local ACTIVE_FOLDER_NAME = "ActiveBridges"
local TEMPLATE_NAME = "BridgeTemplate"
local ITEM_ID = "bridge_builder"

local activeFolder: Folder? = nil
local initialized = false

local function log(player: Player, action: string, extra: string?)
	print(("[Bridge] %s %s%s"):format(player.Name, action, extra and (" — " .. extra) or ""))
end

local function getOrCreateActiveFolder(): Folder
	if activeFolder and activeFolder.Parent then return activeFolder end
	local existing = Workspace:FindFirstChild(ACTIVE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		activeFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = ACTIVE_FOLDER_NAME
	folder.Parent = Workspace
	activeFolder = folder
	return folder
end

local function getHRP(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return nil
end

local function isValidVector3(v: any): boolean
	if typeof(v) ~= "Vector3" then return false end
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then return false end  -- NaN
	if math.abs(v.X) > 1e6 or math.abs(v.Y) > 1e6 or math.abs(v.Z) > 1e6 then return false end
	return true
end

local function isValidNumber(n: any): boolean
	if type(n) ~= "number" then return false end
	if n ~= n then return false end  -- NaN
	if math.abs(n) > 1e6 then return false end
	return true
end

local function makeBridgePart(position: Vector3, rotationY: number, def: any): BasePart
	-- Preferuj asset Kacpra jeśli istnieje (Model lub BasePart) — clone i wymuś properties.
	-- Brak → default BasePart Wood.
	local template = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
	local bridge: BasePart

	if template and template:IsA("BasePart") then
		bridge = template:Clone() :: BasePart
	else
		-- TODO Day 5+: wspierać Model z PrimaryPart (jak Cash). Na razie default Part.
		bridge = Instance.new("Part")
		bridge.Size = Vector3.new(def.width, def.thickness, def.length)
		bridge.Material = def.material or Enum.Material.Wood
		bridge.Color = def.color or Color3.fromRGB(115, 80, 50)
		bridge.TopSurface = Enum.SurfaceType.Smooth
		bridge.BottomSurface = Enum.SurfaceType.Smooth
	end

	bridge.Name = "Bridge"
	bridge.Anchored = true
	bridge.CanCollide = true
	bridge.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(rotationY), 0)
	return bridge
end

local function enterBuildMode(player: Player)
	-- Server validate ZANIM przepuści klienta w build mode. Klient i tak nie buduje sam —
	-- to tylko sygnał "OK, możesz pokazać preview". BuildBridge jest re-validated.
	if not PlayerService.isAlive(player) then return end
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end
	Remotes.BridgeBuildMode:FireClient(player, true)
	log(player, "enter build mode", ("count=%d"):format(ItemService.getCount(player, ITEM_ID)))
end

local function exitBuildMode(player: Player)
	Remotes.BridgeBuildMode:FireClient(player, false)
end

local function handleBuildBridge(player: Player, position: any, rotationY: any)
	-- Typecheck
	if not isValidVector3(position) then
		Remotes.BridgeResult:FireClient(player, false, "invalid_position")
		return
	end
	if not isValidNumber(rotationY) then
		Remotes.BridgeResult:FireClient(player, false, "invalid_rotation")
		return
	end

	-- Alive
	if not PlayerService.isAlive(player) then
		Remotes.BridgeResult:FireClient(player, false, "not_in_round")
		exitBuildMode(player)
		return
	end

	-- Item count
	local count = ItemService.getCount(player, ITEM_ID)
	if count <= 0 then
		Remotes.BridgeResult:FireClient(player, false, "no_items")
		exitBuildMode(player)
		return
	end

	local def = ItemDefinitions.get(ITEM_ID)
	if not def then
		Remotes.BridgeResult:FireClient(player, false, "internal_error")
		return
	end

	-- Distance check (anti-cheat — klient mógłby podać dowolną pozycję)
	local hrp = getHRP(player)
	if not hrp then
		Remotes.BridgeResult:FireClient(player, false, "no_character")
		exitBuildMode(player)
		return
	end
	local distance = ((position :: Vector3) - hrp.Position).Magnitude
	if distance > def.maxBuildDistance then
		Remotes.BridgeResult:FireClient(player, false, "too_far")
		return  -- nie exit — klient widzi czerwony ghost i wie że za daleko
	end

	-- Atomic consume (item gone PRZED spawn → race-safe)
	if not ItemService.consume(player, ITEM_ID, 1) then
		Remotes.BridgeResult:FireClient(player, false, "consume_failed")
		return
	end

	-- Spawn fizyczny most
	local bridge = makeBridgePart(position :: Vector3, rotationY :: number, def)
	bridge.Parent = getOrCreateActiveFolder()

	Remotes.BridgeResult:FireClient(player, true, nil)
	log(player, "built", ("pos=%s rotY=%d°"):format(tostring(position), math.floor(rotationY)))

	-- Jeśli count po consume == 0 → forced exit build mode
	if ItemService.getCount(player, ITEM_ID) <= 0 then
		exitBuildMode(player)
	end
end

local function onEquipItem(player: Player, itemId: any)
	if itemId == ITEM_ID then
		enterBuildMode(player)
	else
		-- Klient przełączył na inny slot — wyłącz nasz build mode jeśli był aktywny.
		-- (Idempotentne; klient już sam w to wchodzi przez ChildSlot logic.)
		exitBuildMode(player)
	end
end

local function onUnequipItem(player: Player)
	exitBuildMode(player)
end

local function onPlayerRemoving(player: Player)
	exitBuildMode(player)
end

local function cleanupAll()
	local folder = activeFolder
	if folder then
		folder:ClearAllChildren()
	end
end

function BridgeService.init()
	if initialized then return end
	initialized = true

	getOrCreateActiveFolder()

	Remotes.EquipItem.OnServerEvent:Connect(onEquipItem)
	Remotes.UnequipItem.OnServerEvent:Connect(onUnequipItem)
	Remotes.BuildBridge.OnServerEvent:Connect(handleBuildBridge)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Cleanup wszystkich postawionych mostów po końcu rundy. Nie czekamy na MapService
	-- bo ActiveBridges jest poza Workspace.Map.
	GameLoopService.RoundEnded:Connect(cleanupAll)
	GameLoopService.StateChanged:Connect(function(newState)
		-- Safety net: gdyby kiedyś RoundEnded zniknął lub nie odpalił, czyść na LOBBY też.
		if newState == GameLoopService.STATE.LOBBY then
			cleanupAll()
		end
	end)
end

return BridgeService
