--!strict
-- C4Service.luau (25.10) — C4: rzucasz ładunki, przyklejają się do mapy, odpalasz wszystkie naraz.
--
-- Decyzje Kacpra 25.10: C4 = zaplanowana „sticky bomb” (model z wystawy); przykleja się tylko do
-- mapy, nie do graczy; naraz najwyżej Config.C4.MaxActive (3); odpala klawisz G na PC i przycisk
-- na telefonie; śmierć = ładunki znikają bez wybuchu. Wybuch jak bomba (BombService.explodeAt).
-- Po pierwszym teście: rzucany (Config.C4.Throw*); po drugim — wysokim łukiem jak granat
-- i z zamachem ręki (gest rysują klienci: C4Controller, `Config.C4.Swing`).
--
-- Flow:
--   1. EquipItem("c4") → Tool `C4Tool` (model ReplicatedStorage.C4)
--   2. Tool.Activated → C4Controller wysyła ThrowC4(punkt, w który celuje mysz)
--   3. Serwer: typ/NaN, żywy, nie ragdoll, cooldown, Tool w ręce, count, limit → consume →
--      ładunek w Workspace.ActiveCharges leci z dłoni; lot liczy serwer promieniem co klatkę
--      (postacie przelatuje), pierwsza trafiona część mapy = przyklejenie
--   4. DetonateC4 → wszystkie ładunki gracza wybuchają po kolei (Config.C4.ChainDelay)
--
-- DLACZEGO LOT Z PROMIENI, A NIE FIZYCZNY POCISK (jak RpgService): fizyczna kostka odbija się
-- i toczy, zanim zdążymy ją przykleić, a przy 90 stud/s przeskakuje cienką ścianę między
-- klatkami. Promień z odcinka klatki trafia dokładnie w miejsce styku.
--
-- ⚠️ ŁADUNEK NIE JEST PRZYSPAWANY DO MAPY. Destrukcja i kolaps czytają połączenia części
-- (`GetJoints`) — spaw do ściany wciągnąłby ładunek w ich grupy (kolaps, przekazanie klientom,
-- kasowanie). Ładunek jest zakotwiczony, bez kolizji, dotyku i promieni, a ten serwis sam
-- pilnuje, na czym wisi (`host`) — także przy zawaleniu (pytanie Kacpra 25.10):
--   - host stoi → ładunek stoi; host zniknął albo punkt styku już na nim nie leży (wybuch
--     przyciął ścianę) → ładunek spada
--   - host się rusza (grupa kolapsu, most, gruz) → ładunek jedzie z nim (CFrame co klatkę)
--   - spada → tym samym lotem co po rzucie (z zerową prędkością); trafi coś → przykleja się
--     tam; nic po MaxFlightTime (poza mapą) → znika bez wybuchu. Odpalić można też w locie.
-- Lawa nie jest wyjątkiem: zalany ładunek dalej działa (bomba w lawie też wybucha na dnie).
--
-- ⚠️ CLEANUP: śmierć (Humanoid.Died — od razu, nie po 2 s leżenia), CharacterRemoving,
-- PlayerRemoving i RoundEnded — wybuch po odbudowie mapy rozwaliłby świeże budynki.

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
local BombService = require(script.Parent.BombService)

local C4Service = {}

local ITEM_ID = "c4"
local TOOL_NAME = "C4Tool"
local FOLDER_NAME = "ActiveCharges"
local SURFACE_GAP = 0.02 -- spód kostki tuż nad powierzchnią, nie w niej
local CFG = Config.C4

type Charge = {
	owner: Player,
	root: Model,
	primary: BasePart,
	light: PointLight,
	size: Vector3,        -- bbox modelu w układzie `primary`
	boxOffset: CFrame,    -- środek bbox w układzie `primary`
	contact: Vector3,     -- punkt styku z hostem w układzie `primary`
	normal: Vector3,      -- „od ściany” w układzie `primary`
	along: Vector3,       -- długi bok w świecie (oś koziołkowania; po upadku leży tak samo)
	host: BasePart?,
	offset: CFrame?,      -- `primary` w układzie hosta, gdy host się rusza
	vel: Vector3?,        -- nie-nil = leci (rzut albo spadanie)
	flightStarted: number,
	nextCheck: number,
}

local equippedTools: { [Player]: Tool } = {}
local lastThrowAt: { [Player]: number } = {}
local lastDetonateAt: { [Player]: number } = {}
local lastEquipAt: { [Player]: number } = {}
local charges: { [Player]: { Charge } } = {} -- kolejność przyklejenia = kolejność wybuchów
local diedConns: { [Player]: RBXScriptConnection } = {}
-- RoundEnded podbija żeton: łańcuch wybuchów w toku nie może wybuchnąć na odbudowanej mapie.
local roundToken = 0
local folder: Folder

local function log(player: Player, action: string, extra: string?)
	print(("[C4] %s %s%s"):format(player.Name, action, extra and (" " .. extra) or ""))
end

local function setCount(player: Player)
	local list = charges[player]
	local n = if list then #list else 0
	player:SetAttribute(CFG.CountAttribute, if n > 0 then n else nil)
end

-- ── C4 w ręce ────────────────────────────────────────────────────────────────────────
-- Dłoń trzyma środek kostki (największa bryła modelu to jedna z dwóch belek, nie środek).
local function heldGrip(model: Model, handle: BasePart): CFrame
	local r = CFG.GripRotation
	local center = model:GetBoundingBox().Position
	return CFrame.new(handle.CFrame:PointToObjectSpace(center))
		* CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

local function removeTool(player: Player)
	local tool = equippedTools[player]
	if tool then
		tool:Destroy()
		equippedTools[player] = nil
	end
end

local function giveTool(player: Player)
	removeTool(player)
	local def = ItemDefinitions.get(ITEM_ID)
	local template = if def and def.toolModel then Utils.getAsset(def.toolModel) else nil
	if not (template and template:IsA("Model")) then
		-- Bez modelu nie ma Toola, a bez Toola nie ma czym przyklejać. Głośno: brak w placu.
		warn(("[C4] brak modelu %s w ReplicatedStorage — C4 nie da się wyciągnąć")
			:format(tostring(def and def.toolModel)))
		return
	end
	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then
		return
	end
	local tool = Utils.makeHeldTool(template, TOOL_NAME, ITEM_ID, heldGrip)
	if not tool then
		return
	end
	tool.Parent = char
	equippedTools[player] = tool
end

function C4Service.unequip(player: Player)
	removeTool(player)
end

-- ── Geometria ładunku ────────────────────────────────────────────────────────────────
-- Kierunek prostopadły do `normal`, możliwie blisko `hint` (bok gracza) — długi bok kostki
-- leży wzdłuż niego, czyli poziomo przed graczem na ścianie i w poprzek na podłodze.
local function perpendicular(normal: Vector3, hint: Vector3, fallback: Vector3): Vector3
	local v = hint - normal * hint:Dot(normal)
	if v.Magnitude < 0.1 then
		v = fallback - normal * fallback:Dot(normal)
	end
	if v.Magnitude < 0.1 then
		v = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis)
	end
	return v.Unit
end

-- Ramka bbox, w której najcieńsza oś modelu (spód kostki) patrzy wzdłuż `normal`, a najdłuższa
-- wzdłuż `along`. Liczona z rozmiaru, nie z nazw części — działa przy każdym obrocie modelu
-- Kacpra na wystawie.
local function surfaceFrame(size: Vector3, center: Vector3, normal: Vector3, along: Vector3): CFrame
	local dims = { size.X, size.Y, size.Z }
	local thin, long = 1, 1
	for i = 2, 3 do
		if dims[i] < dims[thin] then thin = i end
		if dims[i] > dims[long] then long = i end
	end
	if long == thin then
		long = thin % 3 + 1
	end
	local third = 6 - thin - long
	local cols: { Vector3 } = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	cols[thin] = normal
	cols[long] = along
	-- (thin, long, third) w kolejności X→Y→Z (cyklicznie) → third = thin × long; inaczej odwrotnie,
	-- żeby układ został prawoskrętny (lustrzany CFrame przekręca model).
	cols[third] = if long == thin % 3 + 1 then normal:Cross(along) else along:Cross(normal)
	return CFrame.fromMatrix(center, cols[1], cols[2], cols[3])
end

local function thinHalf(size: Vector3): number
	return math.min(size.X, size.Y, size.Z) * 0.5
end

-- Połowa grubości obróconego bbox wzdłuż kierunku `dir` (jednostkowy) — o tyle promień lotu
-- wybiega przed środek kostki, żeby jej brzeg nie wchodził w ścianę.
local function halfExtent(box: CFrame, size: Vector3, dir: Vector3): number
	return (math.abs(box.XVector:Dot(dir)) * size.X + math.abs(box.YVector:Dot(dir)) * size.Y
		+ math.abs(box.ZVector:Dot(dir)) * size.Z) * 0.5
end

-- Promień przyklejania i spadania: tylko mapa. Postacie, inne ładunki i leżąca kasa pomijane;
-- lawa (`CanQuery = false`) sama przepuszcza promień na dno.
local function castParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local ignore: { Instance } = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local cash = Workspace:FindFirstChild("ActiveCash")
	if cash then
		table.insert(ignore, cash)
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- Ustawia środek bbox ładunku w `frame` i zapamiętuje, gdzie ten środek leży względem `primary`.
local function place(c: Charge, frame: CFrame)
	Utils.setModelCenter(c.root, frame)
	c.boxOffset = c.primary.CFrame:ToObjectSpace(frame)
end

-- Kładzie ładunek płasko na trafionej powierzchni i zapamiętuje, na czym wisi.
local function stick(c: Charge, hit: RaycastResult)
	local normal = hit.Normal
	local along = perpendicular(normal, c.along, Vector3.zAxis)
	place(c, surfaceFrame(c.size, hit.Position + normal * (thinHalf(c.size) + SURFACE_GAP), normal, along))
	local cf = c.primary.CFrame
	c.contact = cf:PointToObjectSpace(hit.Position)
	c.normal = cf:VectorToObjectSpace(normal)
	c.along = along
	c.host = if hit.Instance:IsA("BasePart") then hit.Instance else nil
	c.offset = nil
	c.vel = nil
	c.nextCheck = 0
end

-- Ładunek z modelu Kacpra: zakotwiczona największa bryła, reszta na weldach WEWNĄTRZ modelu
-- (żadnego połączenia z mapą). Bez kolizji, dotyku i promieni (CanQuery dopiero po CanCollide —
-- lekcja 10), `Locked` = nietykalny dla destrukcji (Destructible) — inny wybuch go nie potnie.
local function buildCharge(owner: Player, hint: Vector3): Charge?
	local def = ItemDefinitions.get(ITEM_ID)
	local template = if def and def.toolModel then Utils.getAsset(def.toolModel) else nil
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	local primary = model.PrimaryPart or Utils.largestPart(model)
	if not primary then
		model:Destroy()
		return nil
	end
	model.Name = "C4Charge"
	model.PrimaryPart = primary
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.Locked = true
		end
	end
	Utils.weldModel(model, primary)
	primary.Anchored = true

	local light = Instance.new("PointLight")
	light.Color = CFG.LightColor
	light.Range = CFG.LightRange
	light.Brightness = CFG.LightBrightness
	light.Parent = primary

	local _bb, size = model:GetBoundingBox()
	return {
		owner = owner,
		root = model,
		primary = primary,
		light = light,
		size = size,
		boxOffset = CFrame.identity,
		contact = Vector3.zero,
		normal = Vector3.yAxis,
		along = hint,
		host = nil,
		offset = nil,
		vel = nil,
		flightStarted = 0,
		nextCheck = 0,
	}
end

-- Środek wybuchu: środek kostki odsunięty od ściany (jak RPG HitBackoff — nie w ścianie).
local function blastCenter(c: Charge): Vector3
	local cf = c.primary.CFrame
	return (cf * c.boxOffset).Position + cf:VectorToWorldSpace(c.normal) * CFG.BlastBackoff
end

-- ── Pilnowanie podłoża ───────────────────────────────────────────────────────────────
local function onHost(c: Charge, host: BasePart): boolean
	local p = host.CFrame:PointToObjectSpace(c.primary.CFrame * c.contact)
	local h = host.Size * 0.5 + Vector3.one * CFG.HostMargin
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

-- Rzut (prędkość z ręki) albo spadanie po utracie podłoża (prędkość zero) — ten sam lot.
local function launch(c: Charge, vel: Vector3, now: number)
	c.host = nil
	c.offset = nil
	c.vel = vel
	c.flightStarted = now
end

-- Jedna klatka lotu. false = poleciał poza mapę (do usunięcia, bez wybuchu).
local function fly(c: Charge, dt: number, now: number, params: RaycastParams): boolean
	if now - c.flightStarted > CFG.MaxFlightTime then
		log(c.owner, "ładunek poza mapą — znika")
		return false
	end
	local v = c.vel :: Vector3
	v = Vector3.new(v.X, math.max(v.Y - CFG.Gravity * dt, -CFG.FallMaxSpeed), v.Z)
	c.vel = v
	local move = v * dt
	local dist = move.Magnitude
	if dist < 1e-4 then return true end
	local dir = move / dist
	local box = c.primary.CFrame * c.boxOffset
	local hit = Workspace:Raycast(box.Position, dir * (dist + halfExtent(box, c.size, dir)), params)
	if hit then
		stick(c, hit)
		log(c.owner, "przyklejony", ("na %s"):format(hit.Instance:GetFullName()))
		return true
	end
	-- Koziołkowanie wokół długiego boku w świecie (bok gracza przy rzucie).
	local spun = CFrame.new(box.Position + move) * CFrame.fromAxisAngle(c.along, CFG.Spin * dt) * box.Rotation
	c.primary.CFrame = spun * c.boxOffset:Inverse()
	return true
end

-- Jedna klatka życia ładunku. false = do usunięcia.
local function update(c: Charge, dt: number, now: number, params: RaycastParams?): boolean
	if not c.primary.Parent then
		return false
	end
	-- Dioda: wszystkie ładunki migają razem — prościej wypatrzyć zestaw.
	local on = math.floor(now * CFG.BlinkHz * 2) % 2 == 0
	if c.light.Enabled ~= on then
		c.light.Enabled = on
	end

	if c.vel then
		return fly(c, dt, now, params :: RaycastParams)
	end

	local host = c.host
	if host and not host.Anchored and host.Parent then
		-- Host jedzie (kolaps, most, gruz) — offset łapiemy w pierwszej klatce ruchu, nie przy
		-- przyklejeniu: stojący host mógł w międzyczasie zostać przycięty i przesunięty.
		local offset = c.offset
		if not offset then
			offset = host.CFrame:ToObjectSpace(c.primary.CFrame)
			c.offset = offset
		end
		local target = host.CFrame * (offset :: CFrame)
		local cur = c.primary.CFrame
		-- Bez zapisu, gdy nic się nie zmieniło: każdy zapis CFrame to pakiet do wszystkich graczy.
		if (target.Position - cur.Position).Magnitude > 0.005 or target.LookVector:Dot(cur.LookVector) < 0.99999
			or target.UpVector:Dot(cur.UpVector) < 0.99999 then
			c.primary.CFrame = target
		end
	end

	if now >= c.nextCheck then
		c.nextCheck = now + CFG.CheckInterval
		if not host or not host:IsDescendantOf(Workspace) then
			-- Rozsypał się w drobny gruz (serwer kasuje, klienci animują), spłonął, zniknął.
			launch(c, Vector3.zero, now)
		elseif host.Anchored then
			-- Osiadł albo stał od początku: dalej trzymamy pozycję, ale wybuch mógł przyciąć
			-- ścianę tak, że w miejscu ładunku jest już powietrze.
			c.offset = nil
			if not onHost(c, host) then
				launch(c, Vector3.zero, now)
			end
		end
	end
	return true
end

local function step(dt: number)
	if next(charges) == nil then return end
	local now = os.clock()
	-- Pętla nie yielduje: wszystkie loty widzą ten sam zestaw postaci. Nowa klatka
	-- buduje go od nowa, żeby respawn nie zostawił starej postaci w filtrze.
	local params: RaycastParams? = nil
	for owner, list in pairs(charges) do
		local changed = false
		for i = #list, 1, -1 do
			local c = list[i]
			if c.vel and not params then params = castParams() end
			if not update(c, dt, now, params) then
				c.root:Destroy()
				table.remove(list, i)
				changed = true
			end
		end
		if changed then
			if #list == 0 then
				charges[owner] = nil
			end
			setCount(owner)
		end
	end
end

-- Ładunki znikają bez wybuchu: śmierć, wyjście, koniec rundy (decyzja Kacpra 25.10).
local function clearCharges(player: Player)
	local list = charges[player]
	charges[player] = nil
	if list then
		for _, c in ipairs(list) do
			c.root:Destroy()
		end
		log(player, "ładunki znikają", ("(%d)"):format(#list))
	end
	if player.Parent then
		setCount(player)
	end
end

-- ── Rzut ─────────────────────────────────────────────────────────────────────────────
local function handleThrow(player: Player, targetPos: any)
	-- 1. Typecheck — klient kłamie (hard rule: server validate WSZYSTKO).
	if not Utils.isFiniteVector3(targetPos) then return end

	-- 2. Żywy gracz w rundzie, nie w ragdollu (klient blokuje to samo, nie ufamy mu).
	if not PlayerService.isAlive(player) then return end
	if RagdollService.isRagdolled(player) then return end

	-- 3. Cooldown zużywany na PRÓBIE.
	local now = os.clock()
	if now - (lastThrowAt[player] or 0) < Config.RateLimits.C4Throw * Config.RateLimits.ServerTolerance then return end
	lastThrowAt[player] = now

	-- 4. Rzuca to, co TRZYMA (equip pilnuje loadoutu), ma czym i nie przekracza limitu.
	local tool = equippedTools[player]
	local char = player.Character
	if not (tool and char and tool.Parent == char) then return end
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end
	local list = charges[player]
	if list and #list >= CFG.MaxActive then return end
	local hrp = Utils.getRoot(player)
	if not hrp then return end

	-- 5. Z punktu klienta tylko KIERUNEK (od oczu do celu); start z dłoni.
	local head = char:FindFirstChild("Head")
	local eye = if head and head:IsA("BasePart") then head.Position else hrp.Position + Vector3.new(0, 1.5, 0)
	local delta = targetPos - eye
	if delta.Magnitude < 0.1 then return end
	local handle = tool:FindFirstChild("Handle")
	local start = if handle and handle:IsA("BasePart") then handle.Position else eye

	-- 6. Ładunek gotowy PRZED zużyciem — brak modelu nie może zjeść C4.
	local charge = buildCharge(player, hrp.CFrame.RightVector)
	if not charge then
		warn("[C4] brak modelu ładunku — nie rzucam")
		return
	end
	if not ItemService.consume(player, ITEM_ID, 1) then
		charge.root:Destroy()
		return
	end
	-- Kto rzucił: po tym klienci rysują zamach ręki (atrybut jedzie razem z modelem).
	charge.root:SetAttribute(CFG.OwnerAttribute, player.UserId)
	-- Ściana tuż przed nosem: dłoń mogła być już w niej, a promień startujący w środku części
	-- jej nie widzi — sprawdzamy odcinek oczy → dłoń i przyklejamy od razu.
	local reach = start - eye
	local wall = if reach.Magnitude > 0.05 then Workspace:Raycast(eye, reach, castParams()) else nil
	if wall then
		stick(charge, wall)
	else
		place(charge, surfaceFrame(charge.size, start, Vector3.yAxis, perpendicular(Vector3.yAxis, charge.along, Vector3.zAxis)))
		-- Biegnąc rzucasz dalej, ale prędkość postaci (liczona u klienta) ma sufit.
		local inherit = hrp.AssemblyLinearVelocity
		if inherit.Magnitude > CFG.InheritMaxSpeed then
			inherit = inherit.Unit * CFG.InheritMaxSpeed
		end
		launch(charge, delta.Unit * CFG.ThrowSpeed + Vector3.new(0, CFG.ThrowLift, 0) + inherit, now)
	end
	charge.root.Parent = folder
	list = charges[player] or {}
	table.insert(list :: { Charge }, charge)
	charges[player] = list
	setCount(player)

	-- Ostatni C4 → Tool znika (jak RPG); ładunki zostają, odpala je detonator.
	local left = ItemService.getCount(player, ITEM_ID)
	if left <= 0 then
		removeTool(player)
	end
	log(player, "rzut", ("%s aktywne=%d zostało=%d"):format(
		if wall then "w ścianę przed nosem " .. wall.Instance:GetFullName() else "z dłoni",
		#(list :: { Charge }), left))
end

-- ── Odpalenie ────────────────────────────────────────────────────────────────────────
local function handleDetonate(player: Player)
	local now = os.clock()
	if now - (lastDetonateAt[player] or 0) < Config.RateLimits.C4Detonate * Config.RateLimits.ServerTolerance then return end
	lastDetonateAt[player] = now
	-- Tylko żywy w rundzie. Ragdoll NIE blokuje: detonator to przycisk, nie ruch ręki.
	if not PlayerService.isAlive(player) then return end
	local list = charges[player]
	if not list or #list == 0 then return end
	local def = ItemDefinitions.get(ITEM_ID)
	if not def then return end

	-- Stan PRZED wybuchami, które yieldują (zasada 8b): ładunki przestają należeć do gracza,
	-- więc jego śmierć od pierwszego z nich nie skasuje reszty — odpalone znaczy odpalone.
	charges[player] = nil
	setCount(player)
	log(player, "detonacja", ("(%d)"):format(#list))

	local token = roundToken
	task.spawn(function()
		for i, c in ipairs(list) do
			if i > 1 then
				task.wait(CFG.ChainDelay)
			end
			if roundToken ~= token then
				-- Runda skończyła się w trakcie łańcucha — reszta znika bez wybuchu.
				for j = i, #list do
					list[j].root:Destroy()
				end
				return
			end
			if c.primary.Parent then
				local center = blastCenter(c)
				c.root:Destroy()
				-- Gracz, który wyszedł w trakcie łańcucha, nie jest już sprawcą (sam teren).
				local attacker = if player.Parent then player else nil
				-- Osobny wątek: destrukcja potrafi odczekać klatkę na budżet CPU (jak RPG).
				task.spawn(BombService.explodeAt, center, def, attacker)
			end
		end
	end)
end

-- ── Equip / unequip ──────────────────────────────────────────────────────────────────
local function onEquipItem(player: Player, itemId: any)
	if itemId ~= ITEM_ID then
		-- Gracz wyciąga INNY item — C4 chowamy (każdy serwis itemu tak robi). Ładunki zostają.
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
function C4Service.init()
	if initialized then return end
	initialized = true

	-- Folder runtime poza Map (jak ActiveBridges): MapService go nie snapshotuje.
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end

	Remotes.ThrowC4.OnServerEvent:Connect(handleThrow)
	Remotes.DetonateC4.OnServerEvent:Connect(handleDetonate)
	Remotes.EquipItem.OnServerEvent:Connect(onEquipItem)
	Remotes.UnequipItem.OnServerEvent:Connect(onUnequipItem)
	RunService.Heartbeat:Connect(step)

	-- Śmierć: ładunki znikają OD RAZU na Died, nie po ~2 s leżenia (wtedy dopiero CharacterRemoving).
	local function watchCharacter(player: Player, char: Model)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if not (hum and hum:IsA("Humanoid")) or player.Character ~= char then return end
		local old = diedConns[player]
		if old then old:Disconnect() end
		diedConns[player] = hum.Died:Connect(function()
			removeTool(player)
			clearCharges(player)
		end)
	end
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(char)
			watchCharacter(player, char)
		end)
		player.CharacterRemoving:Connect(function()
			removeTool(player)
			clearCharges(player)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeTool(player)
		clearCharges(player)
		local conn = diedConns[player]
		if conn then conn:Disconnect() end
		diedConns[player] = nil
		lastThrowAt[player] = nil
		lastDetonateAt[player] = nil
		lastEquipAt[player] = nil
	end)

	-- Ocalali nie dostają nowej postaci po rundzie (tylko teleport) — bez tego zostawaliby
	-- z C4 w ręce i ładunkami na odbudowanej mapie.
	GameLoopService.RoundEnded:Connect(function()
		roundToken += 1
		for _, player in ipairs(Players:GetPlayers()) do
			removeTool(player)
			clearCharges(player)
		end
		-- Ładunki graczy, którzy wyszli, i wszystko, co zostało poza rejestrem.
		folder:ClearAllChildren()
		table.clear(charges)
	end)
end

return C4Service
