--!strict
-- ItemPickupService.luau (13.11) — itemy porozrzucane po mapie, podnoszone na E.
--
-- Decyzje Kacpra 13.11: ~20 spotów głównie na piętrach budynków (nie aż tak łatwo dostępne),
-- co rundę losowo ~połowa, czym droższy item, tym rzadszy, podniesienie = ProximityPrompt E,
-- item idzie do inventory jak kupiony. Sloty w rundzie się NIE zmieniają: item, który jest już
-- w loadoucie, da się użyć od razu (+1 sztuka), reszta czeka na lobby.
--
-- KONTRAKT STUDIO: `Workspace.Map.Locked.ItemSpawns/*` — BasePart markery (niewidzialne,
-- bez kolizji) leżące na podłodze. Pozycje bierzemy RAZ na starcie (jak CashPickupService):
-- Locked nie jest odtwarzany przez MapService ani ruszany przez wybuchy.
-- Model itemu: `ReplicatedStorage.<ItemDefinitions[id].toolModel>` (ten sam, co w ręce).
--
-- Własność: ten serwis trzyma TYLKO leżące itemy (folder `Workspace.ActiveItemPickups`).
-- Inventory należy do ItemService (give), sloty do LoadoutService — tu ich nie ruszamy.
--
-- Skala: ~10 modeli na serwer, prompt silnika (zero pracy na tick po stronie serwera poza
-- sprawdzeniem podłogi 2×/s), jeden FireAllClients na podniesienie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local GameLoopService = require(script.Parent.GameLoopService)
local ItemService = require(script.Parent.ItemService)
local LavaService = require(script.Parent.LavaService)
local PlayerService = require(script.Parent.PlayerService)

local CFG = Config.ItemPickup

local ItemPickupService = {}

local ACTIVE_FOLDER_NAME = "ActiveItemPickups"
local PROMPT_NAME = "ItemPickupPrompt"

-- building = atrybut `Building` markera (nil = marker bez przypisania, losowany ułamkiem).
type Spot = { pos: Vector3, building: string? }
local spots: { Spot } = {}
local activeFolder: Folder? = nil
local heartbeatConn: RBXScriptConnection? = nil
local roundActive = false
local lastPickupAt: { [Player]: number } = {}
local initialized = false

local function log(msg: string)
	print("[ItemPickup] " .. msg)
end

local function getActiveFolder(): Folder
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

local function takeSpawnSnapshot()
	local map = Workspace:FindFirstChild("Map")
	local locked = map and map:FindFirstChild("Locked")
	local spawns = locked and locked:FindFirstChild("ItemSpawns")
	if not spawns then
		warn("[ItemPickup] brak Workspace.Map.Locked.ItemSpawns — itemy nie będą leżeć na mapie")
		return
	end
	local list: { Spot } = {}
	for _, child in ipairs(spawns:GetChildren()) do
		if child:IsA("BasePart") then
			local b = child:GetAttribute("Building")
			table.insert(list, {
				pos = child.Position + Vector3.new(0, CFG.HeightOffset, 0),
				building = if type(b) == "string" and b ~= "" then b else nil,
			})
		end
	end
	spots = list
	log(("snapshot: %d spotów"):format(#list))
end

-- Pula z wagami liczona przy każdej rundzie: tanie, a zmiana ceny / Exclude w Config działa
-- bez restartu logiki. Item bez modelu w ReplicatedStorage pomijamy (nie ma czego pokazać).
local function buildPool(): ({ { id: string, weight: number } }, number)
	local pool = {}
	local total = 0
	for _, id in ipairs(ItemDefinitions.shopOrder) do
		local def = ItemDefinitions.get(id)
		if not def or table.find(CFG.Exclude, id) then continue end
		if not (def.toolModel and ReplicatedStorage:FindFirstChild(def.toolModel)) then continue end
		local price = math.max(1, def.price or CFG.ReferencePrice)
		local weight = (CFG.ReferencePrice / price) ^ CFG.RarityExponent * (CFG.WeightBoost[id] or 1)
		table.insert(pool, { id = id, weight = weight })
		total += weight
	end
	return pool, total
end

local function rollItem(pool: { { id: string, weight: number } }, total: number): string?
	if #pool == 0 then return nil end
	local r = math.random() * total
	for _, entry in ipairs(pool) do
		r -= entry.weight
		if r <= 0 then return entry.id end
	end
	return pool[#pool].id
end

-- Klon modelu z ręki jako znalezisko: bez skryptów, zakotwiczony, bez kolizji i BEZ promieni
-- (lekcja 10 z CLAUDE: niewidzialny dla haka/celownika drabiny, nie łapie wybuchów).
local function makePickup(itemId: string, position: Vector3): Model?
	local def = ItemDefinitions.get(itemId)
	local template = def and def.toolModel and ReplicatedStorage:FindFirstChild(def.toolModel)
	if not (template and template:IsA("Model")) then return nil end

	local model = template:Clone()
	local largest: BasePart? = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			if not largest or d.Size.Magnitude > largest.Size.Magnitude then
				largest = d
			end
		end
	end
	if not largest then
		model:Destroy()
		return nil
	end
	if not model.PrimaryPart then
		model.PrimaryPart = largest
	end

	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		local factor = math.clamp((CFG.Sizes[itemId] or CFG.DisplaySize) / longest, CFG.MinScale, CFG.MaxScale)
		model:ScaleTo(model:GetScale() * factor)
	end
	-- Środek bryły (nie pivot — pivot modelu z ręki bywa w uchwycie) dokładnie nad markerem.
	local boxCf = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + (position - boxCf.Position))

	model.Name = "ItemPickup"
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("Collected", false)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = CFG.PromptActionText
	prompt.ObjectText = def.name
	prompt.KeyboardKeyCode = CFG.PromptKey
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = CFG.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	return model
end

local function characterList(): { Instance }
	local list: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	return list
end

-- Linia wzroku serwera: od głowy gracza do środka itemu nic stałego po drodze.
-- Bez tego prompt (silnikowy, bez linii wzroku) dałoby się odpalić przez cienką ścianę.
local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = characterList()
	table.insert(exclude, getActiveFolder())
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(from, to - from, params)
	return hit == nil
end

local function tryPickup(model: Model, player: Player)
	if not roundActive or model:GetAttribute("Collected") or not model.Parent then return end
	if not PlayerService.isAlive(player) then return end

	local now = os.clock()
	if now - (lastPickupAt[player] or 0) < CFG.MinInterval then return end

	local char = player.Character
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	local root = model.PrimaryPart
	if not (head and head:IsA("BasePart") and root) then return end
	local itemPos = model:GetBoundingBox().Position
	local maxDist = CFG.PromptDistance + CFG.ServerDistanceTolerance
	if (head.Position - itemPos).Magnitude > maxDist + 2 then return end -- głowa ~2 nad HRP
	if not hasLineOfSight(head.Position, itemPos) then return end

	local itemId = model:GetAttribute("ItemId")
	if type(itemId) ~= "string" then return end

	-- Blokada PRZED give: drugi Triggered (drugi gracz w tej samej klatce) odbija się tutaj.
	model:SetAttribute("Collected", true)
	lastPickupAt[player] = now
	local ok, reason = ItemService.give(player, itemId, 1)
	if not ok then
		-- Item wraca na miejsce dla innych; inventory_full przy maxStack 9999 praktycznie nie
		-- wystąpi, data_not_loaded to gracz w trakcie wczytywania danych.
		model:SetAttribute("Collected", false)
		warn(("[ItemPickup] %s nie dostał %s (%s)"):format(player.Name, itemId, tostring(reason)))
		return
	end
	log(("%s podniósł %s"):format(player.Name, itemId))
	Remotes.ItemPickedUp:FireAllClients(player, itemId, itemPos)
	model:Destroy()
end

local function place(model: Model)
	local prompt = model.PrimaryPart and model.PrimaryPart:FindFirstChild(PROMPT_NAME)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player: Player)
			tryPickup(model, player)
		end)
	end
	model.Parent = getActiveFolder()
end

-- Item położony w trakcie rundy poza spotami (24.11: wysypany ze skrzyni zrzutu). `floorPos` =
-- punkt na podłodze; `from` (opcjonalny) = skąd wylatuje — klienci rysują łuk, serwer stawia item
-- od razu na miejscu. Dalej żyje jak każdy inny: prompt, lawa, utrata podłogi.
function ItemPickupService.spawnAt(itemId: string, floorPos: Vector3, from: Vector3?): boolean
	if not roundActive then return false end
	local model = makePickup(itemId, floorPos + Vector3.new(0, CFG.MarkerHeight + CFG.HeightOffset, 0))
	if not model then return false end
	if from then
		model:SetAttribute("BurstFrom", from)
		model:SetAttribute("BurstAt", Workspace:GetServerTimeNow())
	end
	place(model)
	return true
end

local function spawnRoundItems()
	local folder = getActiveFolder()
	folder:ClearAllChildren()
	if #spots == 0 then return end

	local pool, total = buildPool()
	if #pool == 0 then
		warn("[ItemPickup] pusta pula itemów (brak modeli w ReplicatedStorage?)")
		return
	end

	-- Wybór: z każdego budynku PerBuilding losowych spotów, z markerów bez budynku ułamek.
	-- Tasowanie całej listy raz, potem branie po kolei — każdy budynek dostaje losowy podzbiór.
	local shuffled = table.clone(spots)
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local loose = 0
	for _, s in ipairs(shuffled) do
		if not s.building then loose += 1 end
	end
	local looseTarget = math.floor(loose * CFG.SpawnFraction + 0.5)
	local perBuilding: { [string]: number } = {}
	local positions: { Vector3 } = {}
	for _, s in ipairs(shuffled) do
		if s.building then
			local n = perBuilding[s.building] or 0
			if n < CFG.PerBuilding then
				perBuilding[s.building] = n + 1
				table.insert(positions, s.pos)
			end
		elseif looseTarget > 0 then
			looseTarget -= 1
			table.insert(positions, s.pos)
		end
	end
	local target = #positions

	local lavaY = LavaService.getSurfaceY()
	local spawned, counts = 0, {}
	for i = 1, target do
		local pos = positions[i]
		if pos.Y < lavaY + CFG.LavaSafetyMargin then continue end
		local itemId = rollItem(pool, total)
		local model = itemId and makePickup(itemId, pos)
		if model and itemId then
			place(model)
			spawned += 1
			counts[itemId] = (counts[itemId] or 0) + 1
		end
	end
	local parts = {}
	for id, n in pairs(counts) do table.insert(parts, ("%s×%d"):format(id, n)) end
	log(("runda: %d itemów (%s)"):format(spawned, table.concat(parts, ", ")))
end

-- Lawa i zniszczona podłoga. Lawę porównujemy pozycyjnie (jak kasa), podłogę promieniem:
-- item na piętrze, które zawaliło się od bomby, nie może wisieć w powietrzu.
local function maintenanceTick()
	local folder = activeFolder
	if not folder then return end
	local children = folder:GetChildren()
	if #children == 0 then return end

	local lavaY = LavaService.getSurfaceY()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = characterList()
	table.insert(exclude, folder)
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local probe = Vector3.new(0, -(CFG.HeightOffset + CFG.SupportProbe), 0)

	for _, child in ipairs(children) do
		if not child:IsA("Model") or child:GetAttribute("Collected") then continue end
		local pos = child:GetBoundingBox().Position
		if pos.Y < lavaY then
			child:Destroy()
		elseif not Workspace:Raycast(pos, probe, params) then
			log(("%s stracił podłogę — znika"):format(tostring(child:GetAttribute("ItemId"))))
			child:Destroy()
		end
	end
end

local function startRound()
	if roundActive then return end
	spawnRoundItems()
	roundActive = true
	if not heartbeatConn then
		local interval = 1 / CFG.SupportCheckHz
		local acc = 0
		heartbeatConn = RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc >= interval then
				acc = 0
				maintenanceTick()
			end
		end)
	end
end

local function endRound()
	roundActive = false
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	if activeFolder then
		activeFolder:ClearAllChildren()
	end
end

function ItemPickupService.init()
	if initialized then return end
	initialized = true

	takeSpawnSnapshot()
	getActiveFolder()

	-- Tak samo jak kasa: start z rundą, sprzątanie w lobby. Gracz dołączający w trakcie widzi
	-- leżące itemy sam (modele w Workspace replikują się), nic do replicateTo.
	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState == GameLoopService.STATE.ROUND then
			startRound()
		elseif newState == GameLoopService.STATE.LOBBY then
			endRound()
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastPickupAt[player] = nil
	end)
end

return ItemPickupService
