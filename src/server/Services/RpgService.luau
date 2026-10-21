--!strict
-- RpgService.luau (20.10) — RPG: celujesz, rakieta leci PROSTO i wybucha na pierwszej rzeczy,
-- w którą trafi. Etap 1 (decyzja Kacpra „wprowadzajmy powoli”): item, strzał, lot, wybuch.
-- 21.10: rocket jump zrobiony i USUNIĘTY na prośbę Kacpra — własna rakieta działa jak bomba rzucającego.
--
-- Decyzje Kacpra 20.10: prosto i szybko (Config.Rpg.Speed), wybuch słabszy od bomby
-- (ItemDefinitions.rpg), 1 rakieta = 1 strzał za 75$, własny wybuch jak przy bombie.
--
-- Flow:
--   1. EquipItem("rpg") → Tool `RpgTool` (model ReplicatedStorage.Rpg — cała wyrzutnia)
--   2. Tool.Activated → RpgController wysyła FireRpg(punkt, w który celuje mysz)
--   3. Serwer waliduje (typ, NaN, żywy, nie ragdoll, cooldown, Tool w ręce, count) → consume
--   4. Lot liczy SERWER: co Heartbeat promień na odcinku, który rakieta przeleciała w tej
--      klatce. Trafienie (świat, most, gracz) albo tafla lawy albo koniec zasięgu = wybuch
--   5. Remotes.RocketFired / RocketExploded → klienci rysują rakietę u siebie po tej samej
--      prostej; sam wybuch to BombService.explodeAt (otoczenie przed graczami, kill strzelcowi)
--
-- DLACZEGO PROMIENIE NA SERWERZE, A NIE FIZYCZNY POCISK: przy 120 stud/s fizyczna rakieta
-- przeskakuje cienką ścianę między klatkami (Touched nie odpala), a z network ownership klienta
-- strzelec decydowałby, gdzie wybucha. Promień z odcinka klatki nie przegapi niczego, a klient
-- nie ma tu nic do powiedzenia poza kierunkiem.
--
-- ⚠️ CLEANUP NA `RoundEnded`: Tool w ręce ocalałych (nie dostają nowej postaci) i rakiety
-- w locie — wybuch po odbudowie mapy rozwaliłby świeże budynki (lekcja z BombService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local ItemService = require(script.Parent.ItemService)
local LoadoutService = require(script.Parent.LoadoutService)
local PlayerService = require(script.Parent.PlayerService)
local GameLoopService = require(script.Parent.GameLoopService)
local RagdollService = require(script.Parent.RagdollService)
local LavaService = require(script.Parent.LavaService)
local BombService = require(script.Parent.BombService)

local RpgService = {}

local ITEM_ID = "rpg"
local TOOL_NAME = "RpgTool"
local CFG = Config.Rpg

type Rocket = {
	id: number,
	shooter: Player,
	pos: Vector3,
	dir: Vector3,
	traveled: number,
	params: RaycastParams,
}

local equippedTools: { [Player]: Tool } = {}
local lastFireAt: { [Player]: number } = {}
local lastEquipAt: { [Player]: number } = {}
local rockets: { [number]: Rocket } = {}
local nextId = 0

local function log(player: Player, action: string, extra: string?)
	print(("[Rpg] %s %s%s"):format(player.Name, action, extra and (" " .. extra) or ""))
end

-- ── Wyrzutnia w ręce ─────────────────────────────────────────────────────────────────
-- Chwyt liczony z GEOMETRII modelu, póki stoi w całości: lufa (od środka modelu do głowicy)
-- ma iść do przodu ręki, „góra” wystawy do góry, a dłoń trzyma rękojeść pod lufą. Liczba
-- z obrotem na sztywno (jak przy puszce) rozjechałaby się przy każdej zmianie modelu.
-- Układ uchwytu w dłoni R15 przy trzymanym itemie: −Z = do przodu, +Y = do góry.
local function launcherGrip(model: Model, handle: BasePart): CFrame
	local center = model:GetBoundingBox().Position
	local rocket = model:FindFirstChild(CFG.RocketPartName, true)
	local forward = if rocket and rocket:IsA("BasePart")
		then (rocket.Position - center)
		else handle.CFrame.LookVector
	local up = Vector3.yAxis
	forward = (forward - up * forward:Dot(up))
	if forward.Magnitude < 1e-3 then
		return CFrame.identity
	end
	forward = forward.Unit
	local back = -forward
	local right = up:Cross(back)
	local hold = center + forward * CFG.HoldAlong - up * CFG.HoldBelow
	local h = handle.CFrame
	return CFrame.fromMatrix(h:PointToObjectSpace(hold), h:VectorToObjectSpace(right),
		h:VectorToObjectSpace(up), h:VectorToObjectSpace(back))
end

local function giveTool(player: Player)
	local existing = equippedTools[player]
	if existing then
		existing:Destroy()
		equippedTools[player] = nil
	end

	local def = ItemDefinitions.get(ITEM_ID)
	local template = if def and def.toolModel then Utils.getAsset(def.toolModel) else nil
	if not (template and template:IsA("Model")) then
		warn(("[Rpg] brak modelu %s w ReplicatedStorage — RPG nie da się wyciągnąć")
			:format(tostring(def and def.toolModel)))
		return
	end

	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then
		return
	end

	local tool = Utils.makeHeldTool(template, TOOL_NAME, ITEM_ID, launcherGrip)
	if not tool then
		return
	end
	tool.Parent = char
	equippedTools[player] = tool
end

local function removeTool(player: Player)
	local tool = equippedTools[player]
	if tool then
		tool:Destroy()
		equippedTools[player] = nil
	end
end

function RpgService.unequip(player: Player)
	removeTool(player)
end

-- ── Lot ──────────────────────────────────────────────────────────────────────────────
local function buildParams(char: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	-- Inni gracze ZOSTAJĄ w promieniu — trafienie w człowieka to wybuch na nim.
	local ignore: { Instance } = { char }
	local debris = Workspace:FindFirstChild("BlastDebris")
	if debris then table.insert(ignore, debris) end
	local cash = Workspace:FindFirstChild("ActiveCash")
	if cash then table.insert(ignore, cash) end
	params.FilterDescendantsInstances = ignore
	return params
end

local function explode(rocket: Rocket, center: Vector3)
	rockets[rocket.id] = nil
	Remotes.RocketExploded:FireAllClients(rocket.id, center)
	local def = ItemDefinitions.get(ITEM_ID)
	if not def then return end
	-- Strzelec = sprawca (kill i nagroda dla niego). Własny wybuch traktuje go jak bomba
	-- rzucającego (21.10, Kacper: „wyjeb jumpa, po prostu jak bomba” — rocket jump usunięty).
	local shooter = if rocket.shooter.Parent then rocket.shooter else nil
	-- `task.spawn`: destrukcja potrafi odczekać klatkę na budżet CPU, a to woła pętla lotu —
	-- yield w niej wstrzymałby pozostałe rakiety w połowie przechodzenia po tabeli (zasada 8b).
	task.spawn(BombService.explodeAt, center, def, shooter)
end

local function step(dt: number)
	if next(rockets) == nil then return end
	local lavaY = LavaService.getSurfaceY()
	for _, rocket in pairs(rockets) do
		local len = math.min(CFG.Speed * dt, CFG.MaxRange - rocket.traveled)
		local from = rocket.pos
		local to = from + rocket.dir * len
		local hit = Workspace:Raycast(from, rocket.dir * len, rocket.params)
		-- Tafla lawy nie łapie promieni (`CanQuery = false`) — bez tego rakieta w lawę
		-- przelatywała pod nią i wybuchała na ulicy na dnie.
		local lavaHit: Vector3? = nil
		if from.Y > lavaY and to.Y <= lavaY and rocket.dir.Y < 0 then
			lavaHit = from + rocket.dir * ((from.Y - lavaY) / -rocket.dir.Y)
		end
		if hit and (not lavaHit or (hit.Position - from).Magnitude <= (lavaHit - from).Magnitude) then
			explode(rocket, hit.Position + hit.Normal * CFG.HitBackoff)
		elseif lavaHit then
			explode(rocket, lavaHit)
		else
			rocket.pos = to
			rocket.traveled += len
			if rocket.traveled >= CFG.MaxRange - 1e-3 then
				explode(rocket, to)
			end
		end
	end
end

-- ── Strzał ───────────────────────────────────────────────────────────────────────────
local function handleFire(player: Player, targetPos: any)
	-- 1. Typecheck — klient kłamie (hard rule: server validate WSZYSTKO).
	if typeof(targetPos) ~= "Vector3" then return end
	if targetPos ~= targetPos then return end -- NaN

	-- 2. Żywy gracz w rundzie, nie w ragdollu (klient blokuje to samo, nie ufamy mu).
	if not PlayerService.isAlive(player) then return end
	if RagdollService.isRagdolled(player) then return end

	-- 3. Cooldown zużywany na PRÓBIE.
	local now = os.clock()
	if now - (lastFireAt[player] or 0) < Config.RateLimits.Rpg * Config.RateLimits.ServerTolerance then return end
	lastFireAt[player] = now

	-- 4. Strzela tym, co TRZYMA (equip pilnuje loadoutu) i ma czym.
	local tool = equippedTools[player]
	local char = player.Character
	if not (tool and char and tool.Parent == char) then return end
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end
	local hrp = Utils.getRoot(player)
	if not hrp then return end

	-- 5. Start lotu liczy serwer z pozycji gracza; z punktu klienta bierze tylko KIERUNEK.
	local origin = hrp.Position + Vector3.new(0, CFG.MuzzleHeight, 0)
	local delta = targetPos - origin
	if delta.Magnitude < 0.5 then return end
	local dir = delta.Unit

	-- 6. Zużycie PRZED lotem (atomic, race-safe — jak hak i most).
	if not ItemService.consume(player, ITEM_ID, 1) then return end

	nextId += 1
	local rocket: Rocket = {
		id = nextId,
		shooter = player,
		pos = origin,
		dir = dir,
		traveled = 0,
		params = buildParams(char),
	}
	rockets[rocket.id] = rocket
	Remotes.RocketFired:FireAllClients(rocket.id, player, origin, dir, CFG.Speed,
		Workspace:GetServerTimeNow(), CFG.MaxRange / CFG.Speed)

	-- Ostatnia rakieta → wyrzutnia znika z ręki (jak hak); dopóki coś zostało, zostaje.
	local left = ItemService.getCount(player, ITEM_ID)
	if left <= 0 then
		removeTool(player)
	end
	log(player, "strzał", ("dir=%s zostało=%d"):format(tostring(dir), left))
end

-- ── Equip / unequip ──────────────────────────────────────────────────────────────────
local function onEquipItem(player: Player, itemId: any)
	if itemId ~= ITEM_ID then
		-- Gracz wyciąga INNY item — wyrzutnię chowamy (każdy serwis itemu tak robi).
		removeTool(player)
		return
	end
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now

	if not PlayerService.isAlive(player) then return end
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end
	if not LoadoutService.canEquip(player, ITEM_ID) then return end -- tylko z loadoutu (18.10)

	giveTool(player)
end

local function onUnequipItem(player: Player)
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now
	removeTool(player)
end

local initialized = false
function RpgService.init()
	if initialized then return end
	initialized = true

	Remotes.FireRpg.OnServerEvent:Connect(handleFire)
	Remotes.EquipItem.OnServerEvent:Connect(onEquipItem)
	Remotes.UnequipItem.OnServerEvent:Connect(onUnequipItem)
	RunService.Heartbeat:Connect(step)

	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			removeTool(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	-- Rakieta wyjścia gracza leci dalej i wybucha (bez sprawcy — `explode` sprawdza Parent).
	Players.PlayerRemoving:Connect(function(player)
		removeTool(player)
		lastFireAt[player] = nil
		lastEquipAt[player] = nil
	end)

	GameLoopService.RoundEnded:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			removeTool(player)
		end
		for id in pairs(rockets) do
			Remotes.RocketExploded:FireAllClients(id, nil)
		end
		table.clear(rockets)
	end)
end

return RpgService
