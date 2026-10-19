--!strict
-- BridgeService.luau
-- Server-authoritative budowanie mostu. Klient w build mode wybiera position+rotationY
-- myszą i klika LMB → BuildBridge Remote → server validate + consume + spawn mostu z fizyką.
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
--   - Model `ReplicatedStorage.<def.worldModel>` (dziś "Bridge", 12 desek). Brak modelu = prosty
--     Part z ItemDefinitions.
--   - FIZYKA OD POSTAWIENIA (decyzja Kacpra 01.10; do tego dnia most był zakotwiczoną
--     „konstrukcją”): deski spawane w jedną bryłę, która leży na tym, na czym ją położono.
--     Działa tylko oparta o coś końcami; bomba odrzuca ją w całości (DestructionService pcha
--     niezakotwiczone bryły — jedna prędkość na bryłę). Świadome skutki zaakceptowane przez
--     Kacpra: na lawie (bez kolizji) wpada na dno, wysunięta nad przepaść się przechyla.
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
-- SABOTAŻ PvP: bomba odrzuca most (od 01.10 — wcześniej go łamała). ActiveBridges NIE może
-- trafić na listę chronionych rzeczy w `Destructible`, inaczej sabotaż po cichu zniknie
-- z gry (patrz też Locked=false przy spawnie mostu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local ItemService = require(script.Parent.ItemService)
local LoadoutService = require(script.Parent.LoadoutService)
local LavaService = require(script.Parent.LavaService)
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
--   Anchored — tylko na czas ustawiania: `makePhysical` spawa deski i odkotwicza je dopiero,
--     gdy stoją na miejscu (spaw zapamiętuje układ z chwili utworzenia).
--   Locked=false — `Locked` to w tym projekcie konwencja „nie ruszaj tego" (tak chronimy
--     Baseplate i lawę). Gdyby Kacper kliknął Lock na modelu w Studio, most stałby się
--     niezniszczalny i sabotaż PvP zniknąłby po cichu. Wymuszamy przy każdym spawnie.
local function applyBridgeProperties(part: BasePart)
	part.Anchored = true
	part.CanCollide = true
	part.Locked = false
end

local function isCharacterPart(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Ustawiony most → jedna bryła fizyczna. Zwraca korzeń (największa deska). Deska, która przy
-- postawieniu utkwiła w murku czy gzymsie dachu, dostaje NoCollisionConstraint z tym, w czym
-- utkwiła — inaczej silnik wypycha bryłę „wybuchowo” i most wylatuje w powietrze (ta sama
-- lekcja co grupy kolapsu, test 25.09). Z postaciami NIGDY — gracz przeleciałby przez most
-- na zawsze. Z terenem też nie: to JEDEN part na całą mapę, most przeleciałby przez świat.
-- Woła się PO wstawieniu do Workspace, póki deski są zakotwiczone: `GetPartsInPart` sprawdza
-- prawdziwy kształt. Zapytanie po pudełku obrysu łapałoby przekrzywiony dach, na którym most
-- LEŻY (obrys obróconego parta wystaje ponad jego powierzchnię) — most przeleciałby przez dach.
local function makePhysical(bridge: Instance): BasePart
	local parts: { BasePart } = {}
	if bridge:IsA("BasePart") then
		table.insert(parts, bridge)
	end
	for _, d in ipairs(bridge:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local root: BasePart = if bridge:IsA("BasePart") then bridge else (Utils.largestPart(bridge) or parts[1])

	local inset = Vector3.one * (Config.Bridge.SpawnOverlapInset * 2)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { bridge }
	overlap.RespectCanCollide = true
	for _, p in ipairs(parts) do
		-- Deska zwężona na czas zapytania (w tej samej klatce — replikacja widzi tylko wynik),
		-- żeby leżenie NA dachu nie liczyło się jako utknięcie.
		local full = p.Size
		p.Size = (full - inset):Max(Vector3.one * 0.05)
		local hits = Workspace:GetPartsInPart(p, overlap)
		p.Size = full
		for _, hit in ipairs(hits) do
			if not hit:IsA("Terrain") and not isCharacterPart(hit) then
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = p
				nc.Part1 = hit
				nc.Parent = p
			end
		end
	end

	-- Spawy, potem odkotwiczenie (kolejność opisana przy Utils.weldModel). Deski stoją już
	-- w Workspace, ale zakotwiczone, więc nie ma klatki, w której byłyby luźne.
	Utils.weldModel(bridge, root)
	root.Anchored = false -- weldModel odkotwicza potomków; most-Part (bez modelu) to sam korzeń
	return root
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

	-- Na lawie (01.10): most z fizyką utonąłby w niej od razu, a gracz straciłby item za nic.
	-- Ten sam próg co ghost w BridgeController — PRZED consume.
	local dims = ItemDefinitions.worldSize(ITEM_ID) or Vector3.new(def.width, def.thickness, def.length)
	if (anchorPos :: Vector3).Y - dims.Y * 0.5 <= LavaService.getSurfaceY() + Config.Bridge.LavaMargin then
		Remotes.BridgeResult:FireClient(player, false, "on_lava")
		log(player, "odrzucony", "na lawie")
		return
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
	-- (`dims` policzone wyżej, przy sprawdzaniu lawy.)
	local rad = math.rad(rotationY :: number)
	local forward = Vector3.new(math.sin(rad), 0, math.cos(rad))
	local centerPos = (anchorPos :: Vector3) + forward * (dims.Z * 0.5)

	-- Spawn mostu: ustawiony i zakotwiczony → do Workspace → bryła fizyczna (kolejność
	-- wymagana przez `makePhysical`).
	local bridge = makeBridge(centerPos, rotationY :: number, def)
	bridge.Parent = getOrCreateActiveFolder()
	local root = makePhysical(bridge)
	-- Fizyka na SERWERZE na stałe. Silnik oddaje niezakotwiczoną bryłę najbliższemu graczowi,
	-- a bryła z kolizją należąca do klienta = exploit (przesunąć most pod siebie nad lawą;
	-- to samo pilnuje CollapseService dla spadających pięter). Koszt: przy lagu chodzenie po
	-- moście, który akurat się rusza, może lekko drżeć.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

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
		-- Tylko item z loadoutu (18.10) — inaczej oszust wyciąga wszystko, co ma.
		if not LoadoutService.canEquip(player, ITEM_ID) then return end
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
