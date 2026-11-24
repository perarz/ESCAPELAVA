--!strict
-- SupplyDropService.luau (24.11) — zrzut zaopatrzenia: skrzynia na spadochronie na dach.
--
-- Decyzje Kacpra 24.11: losowy dach nad lawą, 2 na rundę (kiedy — RoundEventService); E otwiera
-- od razu, 3 rzadkie itemy wysypują się dookoła i każdy może któryś złapać.
--
-- KONTRAKT STUDIO:
--   `ReplicatedStorage.SupplyCrate` (Model, PrimaryPart, pivot = ŚRODEK SPODU skrzyni), w środku
--     opcjonalny `Parachute` (Model/Folder) — znika po lądowaniu.
--   `Workspace.Map.Locked.SupplyDropSpawns/*` — BasePart markery na dachach (niewidzialne, bez
--     kolizji i promieni), nad nimi gołe niebo. Pozycje bierzemy RAZ na starcie, jak ItemPickup.
--
-- KTO CO RUSZA: model na serwerze stoi od razu w miejscu lądowania, a opadanie rysuje każdy klient
-- u siebie z atrybutów (SupplyDropController) — bez replikowania pozycji co klatkę. Atrybuty:
--   Land (CFrame) · FromY (number) · DropStart, DropEnd (czas serwera) · Opened (bool)
-- Kolizja i prompt włączają się dopiero po lądowaniu. Leżące itemy oddajemy ItemPickupService —
-- to on wie, jak się je podnosi i kiedy znikają.
--
-- `Locked = true` na częściach: skrzyni nie tnie żaden wybuch (Destructible.isProtected), a podłoga
-- pod nią może zniknąć — wtedy spada niżej, a w lawie przepada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)

local GameLoopService = require(script.Parent.GameLoopService)
local ItemPickupService = require(script.Parent.ItemPickupService)
local LavaService = require(script.Parent.LavaService)
local PlayerService = require(script.Parent.PlayerService)

local CFG = Config.SupplyDrop

local SupplyDropService = {}

local PROMPT_NAME = "SupplyCratePrompt"

type Drop = {
	model: Model,
	land: Vector3,   -- środek spodu na podłodze
	dropEnd: number, -- czas serwera lądowania
	landed: boolean,
	solid: boolean,
	opened: boolean,
	height: number,  -- wysokość skrzyni bez spadochronu
	parts: { BasePart }, -- części skrzyni (bez spadochronu)
}

local spawns: { Vector3 } = {}
local drops: { [Model]: Drop } = {}
local usedThisRound: { Vector3 } = {}
local activeFolder: Folder? = nil
local rng = Random.new()
local initialized = false

local function log(msg: string)
	print("[SupplyDrop] " .. msg)
end

local function getActiveFolder(): Folder
	if activeFolder and activeFolder.Parent then return activeFolder end
	local existing = Workspace:FindFirstChild(CFG.ActiveFolder)
	if existing and existing:IsA("Folder") then
		activeFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = CFG.ActiveFolder
	folder.Parent = Workspace
	activeFolder = folder
	return folder
end

local function takeSpawnSnapshot()
	local map = Workspace:FindFirstChild("Map")
	local locked = map and map:FindFirstChild("Locked")
	local folder = locked and locked:FindFirstChild(CFG.SpawnsFolder)
	if not folder then
		warn(("[SupplyDrop] brak Workspace.Map.Locked.%s — zrzutów nie będzie"):format(CFG.SpawnsFolder))
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(spawns, child.Position)
		end
	end
	log(("snapshot: %d miejsc"):format(#spawns))
end

-- Promień w świat stały: bez postaci, skrzyń i leżących itemów.
local function worldParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local ignore: { Instance } = { getActiveFolder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- ── Miejsce ──────────────────────────────────────────────────────────────────────────

-- Realna powierzchnia pod markerem (dach mógł zostać zburzony) albo nil.
local function surfaceAt(marker: Vector3, lavaY: number, params: RaycastParams): Vector3?
	local from = marker + Vector3.new(0, CFG.SurfaceTolerance, 0)
	local hit = Workspace:Raycast(from, Vector3.new(0, -2 * CFG.SurfaceTolerance, 0), params)
	if not hit or hit.Normal.Y < 0.7 then return nil end
	if hit.Position.Y < lavaY + CFG.LavaMargin then return nil end
	return hit.Position
end

local function pickLanding(): Vector3?
	local lavaY = LavaService.getSurfaceY()
	local params = worldParams()
	local free: { Vector3 } = {}
	local any: { Vector3 } = {}
	for _, marker in ipairs(spawns) do
		local pos = surfaceAt(marker, lavaY, params)
		if not pos then continue end
		table.insert(any, pos)
		local far = true
		for _, used in ipairs(usedThisRound) do
			if (used - pos).Magnitude < CFG.MinSpacing then
				far = false
				break
			end
		end
		if far then table.insert(free, pos) end
	end
	local pool = if #free > 0 then free else any
	return if #pool > 0 then pool[rng:NextInteger(1, #pool)] else nil
end

-- ── Loot ─────────────────────────────────────────────────────────────────────────────

local function weightedPick(weights: { [string]: number }): string?
	local total = 0
	for _, w in pairs(weights) do total += w end
	if total <= 0 then return nil end
	local r = rng:NextNumber() * total
	for id, w in pairs(weights) do
		r -= w
		if r <= 0 then return id end
	end
	return (next(weights))
end

-- Pierwszy item z gwarantowanych (EPIC/LEGENDARY), reszta z puli — bez powtórzeń, żeby trzy osoby
-- przy skrzyni miały o co walczyć.
local function rollLoot(): { string }
	local pool: { [string]: number } = {}
	for id, w in pairs(CFG.Weights) do
		if ItemDefinitions.exists(id) and w > 0 then pool[id] = w end
	end
	local guaranteed: { [string]: number } = {}
	for _, id in ipairs(CFG.Guaranteed) do
		guaranteed[id] = pool[id]
	end
	local out: { string } = {}
	for i = 1, CFG.LootCount do
		local id = if i == 1 then (weightedPick(guaranteed) or weightedPick(pool)) else weightedPick(pool)
		if not id then break end
		pool[id] = nil
		table.insert(out, id)
	end
	return out
end

-- Miejsce na podłodze w kierunku `angle` od skrzyni: ściana skraca promień, brak podłogi (krawędź
-- dachu) cofa do połowy, a w ostateczności pod samą skrzynię.
local function spillSpot(drop: Drop, angle: number, params: RaycastParams): Vector3
	local mid = drop.land + Vector3.new(0, 1.5, 0)
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local wall = Workspace:Raycast(mid, dir * (CFG.SpillRadius + 1), params)
	local reach = if wall then math.max((wall.Position - mid).Magnitude - 1, 0) else CFG.SpillRadius
	for _, factor in ipairs({ 1, 0.5 }) do
		local down = Workspace:Raycast(mid + dir * (reach * factor), Vector3.new(0, -4, 0), params)
		if down then return down.Position end
	end
	return drop.land
end

-- ── Cykl życia skrzyni ───────────────────────────────────────────────────────────────

local function remove(drop: Drop)
	drops[drop.model] = nil
	drop.model:Destroy()
end

local function promptOf(drop: Drop): ProximityPrompt?
	local primary = drop.model.PrimaryPart
	local prompt = primary and primary:FindFirstChild(PROMPT_NAME)
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

local function setSolid(drop: Drop, solid: boolean)
	drop.solid = solid
	for _, p in ipairs(drop.parts) do
		-- Kolejność: `CanQuery = false` działa tylko przy `CanCollide = false` (lekcja 10).
		p.CanCollide = solid
		p.CanQuery = solid
	end
end

-- Ktoś stoi w miejscu skrzyni → kolizja poczeka, inaczej silnik wystrzeliłby go z środka.
local function isClear(drop: Drop): boolean
	local center = drop.land + Vector3.new(0, drop.height * 0.5, 0)
	local reach = drop.height + 3
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - center).Magnitude < reach then
			return false
		end
	end
	return true
end

local function open(drop: Drop, player: Player)
	if drop.opened or not drop.landed or not drop.model.Parent then return end
	if not PlayerService.isAlive(player) then return end

	local char = player.Character
	local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if not (head and head:IsA("BasePart")) then return end
	local center = drop.land + Vector3.new(0, drop.height * 0.5, 0)
	if (head.Position - center).Magnitude > CFG.PromptDistance + CFG.ServerDistanceTolerance + 2 then return end
	-- Przez strop nie otwierasz: między głową a skrzynią nic stałego (sama skrzynia pominięta).
	local params = worldParams()
	if Workspace:Raycast(head.Position, center - head.Position, params) then return end

	-- Blokada PRZED wszystkim, co mogłoby oddać sterowanie: drugi gracz w tej samej klatce odpada tu.
	drop.opened = true
	local prompt = promptOf(drop)
	if prompt then prompt:Destroy() end
	setSolid(drop, false)
	drop.model:SetAttribute("Opened", true)

	local loot = rollLoot()
	local start = rng:NextNumber(0, math.pi * 2)
	for i, itemId in ipairs(loot) do
		local spot = spillSpot(drop, start + (i - 1) * math.pi * 2 / #loot, params)
		ItemPickupService.spawnAt(itemId, spot, center)
	end
	log(("%s otworzył skrzynię: %s"):format(player.Name, table.concat(loot, ", ")))
	task.delay(CFG.OpenLinger, function()
		if drop.model.Parent then remove(drop) end
	end)
end

local function land(drop: Drop)
	drop.landed = true
	local primary = drop.model.PrimaryPart
	if primary and not promptOf(drop) then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = CFG.PromptActionText
		prompt.ObjectText = CFG.PromptObjectText
		prompt.KeyboardKeyCode = Config.ItemPickup.PromptKey
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = CFG.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("TitleColor", CFG.Color) -- PromptController
		prompt.Triggered:Connect(function(player: Player)
			open(drop, player)
		end)
		prompt.Parent = primary
	end
	-- Spadochron znika po złożeniu u klientów (ParachuteFold).
	local chute = drop.model:FindFirstChild(CFG.ParachuteName)
	if chute then
		task.delay(CFG.ParachuteFold + 0.2, function()
			chute:Destroy()
		end)
	end
end

-- Ustawia tor opadania: atrybuty dla klientów, model serwera od razu na miejscu.
local function beginFall(drop: Drop, from: number, to: Vector3, duration: number)
	local now = Workspace:GetServerTimeNow()
	drop.land = to
	drop.dropEnd = now + duration
	drop.landed = false
	local rotation = drop.model:GetPivot().Rotation
	local cf = CFrame.new(to) * rotation
	drop.model:PivotTo(cf)
	drop.model:SetAttribute("Land", cf)
	drop.model:SetAttribute("FromY", from)
	drop.model:SetAttribute("DropStart", now)
	drop.model:SetAttribute("DropEnd", drop.dropEnd) -- ostatni: klient czyta resztę, gdy zobaczy ten
end

local function maintain()
	if next(drops) == nil then return end
	local now = Workspace:GetServerTimeNow()
	local lavaY = LavaService.getSurfaceY()
	local params = worldParams()
	for _, drop in pairs(drops) do
		if drop.opened then continue end
		if lavaY > drop.land.Y + CFG.LavaSink then
			log("skrzynia zalana lawą")
			remove(drop)
			continue
		end
		if not drop.landed then
			if now >= drop.dropEnd then land(drop) end
			continue
		end
		local above = drop.land + Vector3.new(0, 1, 0)
		if not Workspace:Raycast(above, Vector3.new(0, -(1 + CFG.SupportProbe), 0), params) then
			-- Podłoga zniknęła (wybuch, kolaps): spada na to, co jest niżej, albo przepada w lawie.
			local below = Workspace:Raycast(above, Vector3.new(0, lavaY - above.Y, 0), params)
			if not below then
				log("skrzynia straciła podłogę i wpadła w lawę")
				remove(drop)
				continue
			end
			local prompt = promptOf(drop)
			if prompt then prompt:Destroy() end
			setSolid(drop, false)
			local from = drop.land.Y
			beginFall(drop, from, below.Position, math.max((from - below.Position.Y) / CFG.CollapseFallSpeed, 0.15))
			continue
		end
		if not drop.solid and isClear(drop) then setSolid(drop, true) end
	end
end

-- Zwraca czas serwera lądowania (do napisu) albo nil, gdy nie ma dachu nad lawą albo modelu.
function SupplyDropService.drop(): number?
	local template = ReplicatedStorage:FindFirstChild(CFG.CrateModel)
	if not (template and template:IsA("Model") and template.PrimaryPart) then
		warn(("[SupplyDrop] brak ReplicatedStorage.%s (Model z PrimaryPart) — zrzut pominięty"):format(CFG.CrateModel))
		return nil
	end
	local landing = pickLanding()
	if not landing then
		log("żaden dach nie wystaje dość nad lawę — zrzut pominięty")
		return nil
	end

	local model = template:Clone()
	local chute = model:FindFirstChild(CFG.ParachuteName)
	local parts: { BasePart } = {}
	local low, high = math.huge, -math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Locked = true
			if not (chute and d:IsDescendantOf(chute)) then
				table.insert(parts, d)
				low = math.min(low, d.Position.Y - d.Size.Y * 0.5)
				high = math.max(high, d.Position.Y + d.Size.Y * 0.5)
			end
		end
	end
	model.Name = CFG.CrateModel
	model:PivotTo(CFrame.new(landing) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local drop: Drop = {
		model = model,
		land = landing,
		dropEnd = 0,
		landed = false,
		solid = false,
		opened = false,
		height = math.max(high - low, 1),
		parts = parts,
	}
	model:SetAttribute("Opened", false)
	beginFall(drop, landing.Y + CFG.FallHeight, landing, CFG.FallTime)
	drops[model] = drop
	table.insert(usedThisRound, landing)
	model.Parent = getActiveFolder()
	log(("zrzut na (%.0f, %.0f, %.0f)"):format(landing.X, landing.Y, landing.Z))
	return drop.dropEnd
end

local function clear()
	for _, drop in pairs(drops) do
		drop.model:Destroy()
	end
	table.clear(drops)
	table.clear(usedThisRound)
end

function SupplyDropService.init()
	if initialized then return end
	initialized = true

	takeSpawnSnapshot()
	getActiveFolder()

	local interval = 1 / CFG.CheckHz
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < interval then return end
		acc = 0
		maintain()
	end)

	-- Jak kasa i itemy: sprzątanie na wejściu do lobby (w FINISHING runda ma być jeszcze widoczna).
	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState == GameLoopService.STATE.LOBBY or newState == GameLoopService.STATE.PREPARING then
			clear()
		end
	end)
end

return SupplyDropService
