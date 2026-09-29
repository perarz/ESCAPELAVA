--!strict
-- BridgeService.luau
-- Server-authoritative budowanie mostu. Klient w build mode wybiera position+rotationY
-- myszą i klika LMB → BuildBridge Remote → server validate + consume + spawn anchored Part.
--
-- Flow:
--   1. Klient klika hotbar slot z bridge_builder → HotbarController fires EquipItem("bridge_builder")
--   2. Server BridgeService.onEquip → validate alive + count > 0 → fire BridgeBuildMode(true)
--   3. Klient enters build mode (BridgeController) — ghost preview podąża za myszą, R obraca
--   4. Klient LMB → fires BuildBridge(anchorPos, rotationY); anchorPos = bliższa krawędź mostu
--      (= pozycja kursora), NIE centrum. Server liczy centrum = anchor + length/2 wzdłuż +Z.
--   5. Server validate (alive, count > 0, anchor-distance ≤ max, typecheck) → consume → spawn
--   6. Po consume jeśli count == 0 → fire BridgeBuildMode(false) (forced exit), inaczej zostaje
--   7. UnequipItem → BridgeService.onUnequip → fire BridgeBuildMode(false)
--
-- Most:
--   - Model `ReplicatedStorage.<def.worldModel>` (dziś "Bridge", 12 desek), wszystkie party
--     ANCHORED — most to konstrukcja, nie gruz. Brak modelu = prosty Part z ItemDefinitions.
--   - WYMIARY BIERZE SIĘ Z MODELU (`ItemDefinitions.worldSize`), nie z liczb w definicji:
--     asset Kacpra jest źródłem prawdy, a klient liczy ghost tą samą funkcją.
--   - W Workspace.ActiveBridges folder (osobno od Map, żeby MapService go nie tknął)
--   - Cleanup po RoundEnded (jak ActiveCash)
--
-- Blueprint w ręce: wejście w build mode daje graczowi Tool z modelem `def.toolModel`,
-- żeby z zewnątrz było widać, że ten człowiek stawia mosty. Tool nie ma własnej akcji —
-- budowaniem steruje BridgeController (LMB przez UserInputService), więc Tool.Activated
-- celowo nie jest podpięty.
--
-- DECYZJA DESIGNOWA "bomba niszczy most" jest nadal aktualna, ale od 2026-08-11 nie ma
-- jej czym wykonać — destrukcja otoczenia została usunięta i idzie do napisania od nowa.
-- Nowy system wybuchów MUSI omijać ActiveBridges przy budowaniu listy chronionych rzeczy,
-- inaczej sabotaż PvP po cichu zniknie z gry (patrz też Locked=false przy spawnie mostu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local ItemService = require(script.Parent.ItemService)
local PlayerService = require(script.Parent.PlayerService)
local GameLoopService = require(script.Parent.GameLoopService)

local BridgeService = {}

local ACTIVE_FOLDER_NAME = "ActiveBridges"
local ITEM_ID = "bridge_builder"

local activeFolder: Folder? = nil
-- Tool z blueprintem trzymany w ręce podczas build mode (per gracz).
local equippedTools: { [Player]: Tool } = {}
local initialized = false
-- Rate limit per gracz (anti-spam BuildBridge). Klient mirrors z Config.RateLimits.BridgeBuild.
local lastBuildAt: { [Player]: number } = {}
-- Rate limit EquipItem/UnequipItem — spam hotbar clickowania.
local lastEquipAt: { [Player]: number } = {}

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

-- Właściwości wymuszane na KAŻDEJ desce mostu.
--   Anchored — most to konstrukcja. Nieanchorowany part DestructionService traktuje jak
--     gruz (dostaje impuls zamiast pękać) i jeszcze warnuje o błędzie kontraktu mapy.
--   Locked=false — `Locked` to w tym projekcie konwencja „nie ruszaj tego" (tak chronimy
--     Baseplate i lawę). Gdyby Kacper kliknął Lock na modelu w Studio, most stałby się
--     niezniszczalny i sabotaż PvP zniknąłby po cichu. Wymuszamy przy każdym spawnie.
local function applyBridgeProperties(part: BasePart)
	part.Anchored = true
	part.CanCollide = true
	part.Locked = false
end

local function makeBridge(position: Vector3, rotationY: number, def: any): Instance
	local cf = CFrame.new(position) * CFrame.Angles(0, math.rad(rotationY), 0)
	local template = if def.worldModel then Utils.getAsset(def.worldModel) else nil

	if template and template:IsA("Model") then
		local model = template:Clone()
		model.Name = "Bridge"
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				applyBridgeProperties(d)
			end
		end
		-- Środek BOUNDING BOXA w `cf`, nie pivot — patrz Utils.setModelCenter.
		Utils.setModelCenter(model, cf)
		return model
	end

	if template and template:IsA("BasePart") then
		local part = template:Clone() :: BasePart
		part.Name = "Bridge"
		applyBridgeProperties(part)
		part.CFrame = cf
		return part
	end

	if def.worldModel then
		warn(("[Bridge] brak ReplicatedStorage.%s — stawiam prosty Part z ItemDefinitions"):format(
			def.worldModel))
	end
	local bridge = Instance.new("Part")
	bridge.Name = "Bridge"
	bridge.Size = Vector3.new(def.width, def.thickness, def.length)
	bridge.Material = def.material or Config.Bridge.DefaultMaterial
	bridge.Color = def.color or Config.Bridge.DefaultColor
	bridge.TopSurface = Enum.SurfaceType.Smooth
	bridge.BottomSurface = Enum.SurfaceType.Smooth
	applyBridgeProperties(bridge)
	bridge.CFrame = cf
	return bridge
end

-- Tool z blueprintem — czysto wizualny sygnał „ten gracz stawia mosty". Budowanie
-- obsługuje BridgeController; Tool.Activated celowo bez listenera.
local function giveBlueprintTool(player: Player, def: any)
	local existing = equippedTools[player]
	if existing then
		existing:Destroy()
		equippedTools[player] = nil
	end
	local template = if def.toolModel then Utils.getAsset(def.toolModel) else nil
	if not (template and template:IsA("Model")) then
		return -- brak modelu = po prostu brak przedmiotu w ręce, build mode działa dalej
	end
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then
		return
	end

	local model = template:Clone()
	local primary = model.PrimaryPart or Utils.largestPart(model)
	if not primary then
		model:Destroy()
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = "BlueprintTool"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("ItemId", ITEM_ID)

	primary.Name = "Handle"
	local parts: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			table.insert(parts, d)
		end
	end
	Utils.weldModel(model, primary)
	for _, p in ipairs(parts) do
		p.Parent = tool
	end
	for _, leftover in ipairs(model:GetChildren()) do
		leftover.Parent = tool
	end
	model:Destroy()

	tool.Parent = char
	equippedTools[player] = tool
end

local function removeBlueprintTool(player: Player)
	local tool = equippedTools[player]
	if tool then
		tool:Destroy()
		equippedTools[player] = nil
	end
end

local function enterBuildMode(player: Player)
	-- Server validate ZANIM przepuści klienta w build mode. Klient i tak nie buduje sam —
	-- to tylko sygnał "OK, możesz pokazać preview". BuildBridge jest re-validated.
	if not PlayerService.isAlive(player) then return end
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end
	local def = ItemDefinitions.get(ITEM_ID)
	if def then
		giveBlueprintTool(player, def)
	end
	Remotes.BridgeBuildMode:FireClient(player, true)
	log(player, "enter build mode", ("count=%d"):format(ItemService.getCount(player, ITEM_ID)))
end

local function exitBuildMode(player: Player)
	removeBlueprintTool(player)
	Remotes.BridgeBuildMode:FireClient(player, false)
end

local function handleBuildBridge(player: Player, anchorPos: any, rotationY: any)
	-- Rate limit (anti-spam BuildBridge).
	local now = os.clock()
	if now - (lastBuildAt[player] or 0) < Config.RateLimits.BridgeBuild * Config.RateLimits.ServerTolerance then
		Remotes.BridgeResult:FireClient(player, false, "cooldown")
		return
	end

	-- Typecheck (klient wysyła ANCHOR = bliższa krawędź mostu, nie centrum)
	if not isValidVector3(anchorPos) then
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
	-- Liczone od ANCHOR (gdzie gracz "kładzie" most), nie od centrum — inaczej most długi
	-- byłby zawsze "za daleko" mimo że anchor tuż obok gracza.
	local hrp = Utils.getRoot(player)
	if not hrp then
		Remotes.BridgeResult:FireClient(player, false, "no_character")
		exitBuildMode(player)
		return
	end
	local distance = ((anchorPos :: Vector3) - hrp.Position).Magnitude
	if distance > def.maxBuildDistance then
		Remotes.BridgeResult:FireClient(player, false, "too_far")
		return  -- nie exit — klient widzi czerwony ghost i wie że za daleko
	end

	-- Atomic consume (item gone PRZED spawn → race-safe)
	if not ItemService.consume(player, ITEM_ID, 1) then
		Remotes.BridgeResult:FireClient(player, false, "consume_failed")
		return
	end

	-- Rate limit start dopiero po consume (żeby odrzucone requesty nie blokowały gracza).
	lastBuildAt[player] = now

	-- Anchor → centrum (musi być spójne z BridgeController.anchorToCenter). Długość bierze
	-- się z MODELU przez wspólne ItemDefinitions.worldSize — gdyby serwer liczył z liczb
	-- w definicji, a klient z modelu, most stawałby gdzie indziej niż pokazywał ghost.
	local dims = ItemDefinitions.worldSize(ITEM_ID) or Vector3.new(def.width, def.thickness, def.length)
	local rad = math.rad(rotationY :: number)
	local forward = Vector3.new(math.sin(rad), 0, math.cos(rad))
	local centerPos = (anchorPos :: Vector3) + forward * (dims.Z * 0.5)

	-- Spawn fizyczny most
	local bridge = makeBridge(centerPos, rotationY :: number, def)
	bridge.Parent = getOrCreateActiveFolder()

	Remotes.BridgeResult:FireClient(player, true, nil)
	log(player, "built", ("anchor=%s rotY=%d°"):format(tostring(anchorPos), math.floor(rotationY)))

	-- Jeśli count po consume == 0 → forced exit build mode
	if ItemService.getCount(player, ITEM_ID) <= 0 then
		exitBuildMode(player)
	end
end

local function onEquipItem(player: Player, itemId: any)
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now

	if itemId == ITEM_ID then
		enterBuildMode(player)
	else
		-- Klient przełączył na inny slot — wyłącz nasz build mode jeśli był aktywny.
		-- (Idempotentne; klient już sam w to wchodzi przez ChildSlot logic.)
		exitBuildMode(player)
	end
end

local function onUnequipItem(player: Player)
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now
	exitBuildMode(player)
end

local function onPlayerRemoving(player: Player)
	exitBuildMode(player)
	equippedTools[player] = nil
	lastBuildAt[player] = nil
	lastEquipAt[player] = nil
end

-- Śmierć / LoadCharacter zabiera Tool razem z postacią — zostawiona referencja
-- wskazywałaby na zniszczony obiekt i `removeBlueprintTool` udawałby, że coś sprząta.
local function onCharacterRemoving(player: Player)
	equippedTools[player] = nil
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
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function() onCharacterRemoving(player) end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterRemoving:Connect(function() onCharacterRemoving(p) end)
	end

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
