--!strict
-- AirstrikeService.luau (24.11) — nalot rakietowy na jeden budynek.
--
-- Decyzje Kacpra 24.11: syrena i napis ~8 s wcześniej BEZ podania budynku; 5–10 rakiet wg
-- wielkości budynku, każda mocniejsza od RPG; cel losowy, budynki z graczami mają większą szansę;
-- rani każdego w zasięgu, zabójstwo nikomu się nie liczy.
--
-- Flow (`strike` woła RoundEventService, on też ogłasza alarm):
--   1. Alarm: losujemy budynek OD RAZU i trzymamy go tylko na serwerze. Nie przy starcie rakiet:
--      cel ma być tam, gdzie gracze stali w chwili alarmu, więc ucieczka przez te 8 s coś daje.
--   2. `FlightTime` przed uderzeniem: salwa. Cały plan lotu idzie do klientów jednym eventem.
--   3. Lot liczy SERWER promieniem na odcinku klatki (jak RpgService — to samo uzasadnienie), więc
--      kolejne rakiety wlatują w dziury po poprzednich. Trafienie = BombService.explodeAt.
--
-- Rakieta nie ma sprawcy: `Config.Airstrike.Blast.hurtsWithoutAttacker` każe BombService ranić
-- mimo to. Osłona, TOUGHNESS, ragdoll i okno anty-cheata działają jak przy bombie.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local BombService = require(script.Parent.BombService)
local GameLoopService = require(script.Parent.GameLoopService)
local LavaService = require(script.Parent.LavaService)
local PlayerService = require(script.Parent.PlayerService)
local StructuralService = require(script.Parent.StructuralService)

local CFG = Config.Airstrike

local AirstrikeService = {}

type Rec = StructuralService.Rec
type Aim = { origin: Vector3, dir: Vector3 }
type Rocket = {
	id: number,
	origin: Vector3,
	dir: Vector3,
	launchAt: number, -- czas serwera
	pos: Vector3,
	params: RaycastParams,
}

local rockets: { [number]: Rocket } = {}
local nextId = 0
-- Rośnie po każdej rundzie: alarm z poprzedniej nie może wystrzelić w świeżo odbudowaną mapę.
local roundToken = 0
local rng = Random.new()
local initialized = false

local function log(msg: string)
	print("[Airstrike] " .. msg)
end

-- ── Wybór budynku ────────────────────────────────────────────────────────────────────

-- Budynek jest jeszcze celem, gdy wystaje nad lawę: losowe promienie z góry w jego obrys, liczy
-- się tylko trafienie w JEGO części. Zburzony albo zalany odpada sam, bez osobnej listy.
local function isStanding(rec: Rec, lavaY: number): boolean
	local minY = lavaY + CFG.MinAboveLava
	local top = rec.max.Y + 10
	if top <= minY then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { rec.folder }
	local hits = 0
	for _ = 1, CFG.ScanRays do
		local from = Vector3.new(rng:NextNumber(rec.min.X, rec.max.X), top, rng:NextNumber(rec.min.Z, rec.max.Z))
		if Workspace:Raycast(from, Vector3.new(0, minY - top, 0), params) then
			hits += 1
		end
	end
	return hits >= CFG.ScanRays * CFG.MinStanding
end

local function isOccupied(rec: Rec): boolean
	local m = CFG.OccupiedMargin
	for _, player in ipairs(PlayerService.getAliveList()) do
		local root = Utils.getRoot(player)
		if root then
			local p = root.Position
			if p.X > rec.min.X - m and p.X < rec.max.X + m and p.Z > rec.min.Z - m and p.Z < rec.max.Z + m
				and p.Y > rec.min.Y - m and p.Y < rec.max.Y + CFG.OccupiedAbove then
				return true
			end
		end
	end
	return false
end

local function pickBuilding(): Rec?
	local lavaY = LavaService.getSurfaceY()
	local pool: { { rec: Rec, weight: number } } = {}
	local total = 0
	for _, rec in pairs(StructuralService.buildings()) do
		if not isStanding(rec, lavaY) then continue end
		local weight = if isOccupied(rec) then CFG.OccupiedWeight else 1
		table.insert(pool, { rec = rec, weight = weight })
		total += weight
	end
	local r = rng:NextNumber() * total
	for _, entry in ipairs(pool) do
		r -= entry.weight
		if r <= 0 then return entry.rec end
	end
	return if #pool > 0 then pool[#pool].rec else nil
end

-- ── Celowanie ────────────────────────────────────────────────────────────────────────

-- Rakieta trafia w ludzi (jak RPG), nie w kasę, luźny gruz ani niewidzialną barierę na skraju
-- mapy (stoi do Y ~151, a salwa leci z boku i z góry).
local function flightParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local ignore: { Instance } = {}
	for _, name in ipairs({ "BlastDebris", "ActiveCash" }) do
		local folder = Workspace:FindFirstChild(name)
		if folder then table.insert(ignore, folder) end
	end
	local barriers = Utils.barrierFolder()
	if barriers then table.insert(ignore, barriers) end
	params.FilterDescendantsInstances = ignore
	return params
end

-- Kierunek lotu: `tilt` stopni od pionu, z kierunku świata `azimuth`.
local function flightDir(azimuth: number, tiltDegrees: number): Vector3
	local tilt = math.rad(tiltDegrees)
	local side = Vector3.new(math.cos(azimuth), 0, math.sin(azimuth))
	return (side * math.sin(tilt) - Vector3.yAxis * math.cos(tilt)).Unit
end

-- Tor, którego PIERWSZE trafienie to ten budynek (losowe punkty w jego bryle nad lawą). Start
-- cofnięty od trafienia o drogę z `FlightTime`, więc rakieta uderza dokładnie o czasie z alarmu.
local function aim(rec: Rec, azimuth: number, lavaY: number, params: RaycastParams): Aim?
	local flight = CFG.Speed * CFG.FlightTime
	local lowY = math.min(math.max(rec.min.Y, lavaY + 1), rec.max.Y)
	for _ = 1, CFG.AimTries do
		local dir = flightDir(azimuth, CFG.TiltDegrees + rng:NextNumber(-CFG.TiltJitter, CFG.TiltJitter))
		local point = Vector3.new(
			rng:NextNumber(rec.min.X, rec.max.X),
			rng:NextNumber(lowY, rec.max.Y),
			rng:NextNumber(rec.min.Z, rec.max.Z)
		)
		local hit = Workspace:Raycast(point - dir * flight, dir * (flight + 80), params)
		if hit and hit.Position.Y > lavaY and hit.Instance:IsDescendantOf(rec.folder) then
			return { origin = hit.Position - dir * flight, dir = dir }
		end
	end
	return nil
end

local function planSalvo(rec: Rec, params: RaycastParams): { Aim }
	local lavaY = LavaService.getSurfaceY()
	local size = rec.max - rec.min
	local count = math.clamp(math.round(size.X * size.Z / CFG.AreaPerRocket), CFG.MinRockets, CFG.MaxRockets)
	local start = rng:NextNumber(0, math.pi * 2)
	local best: { Aim } = {}
	for k = 1, CFG.Azimuths do
		local azimuth = start + (k - 1) * math.pi * 2 / CFG.Azimuths
		local aims: { Aim } = {}
		for _ = 1, count do
			local a = aim(rec, azimuth, lavaY, params)
			if a then table.insert(aims, a) end
		end
		if #aims > #best then best = aims end
		if #best == count then break end
	end
	return best
end

-- ── Salwa i lot ──────────────────────────────────────────────────────────────────────

local function launch(rec: Rec)
	local params = flightParams()
	local target = rec
	local aims = planSalvo(target, params)
	if #aims == 0 then
		-- Budynek zdążył runąć między alarmem a salwą — alarm już był, więc bierzemy inny.
		local other = pickBuilding()
		if other then
			target = other
			aims = planSalvo(target, params)
		end
	end
	if #aims == 0 then
		log("brak budynku do trafienia — nalot bez rakiet")
		return
	end

	local now = Workspace:GetServerTimeNow()
	local payload: { { id: number, origin: Vector3, dir: Vector3, at: number } } = {}
	for i, a in ipairs(aims) do
		nextId += 1
		-- Pierwsza bez rozrzutu: to ona ma uderzyć w sekundzie z odliczania.
		local jitter = if i == 1 then 0 else rng:NextNumber(-CFG.IntervalJitter, CFG.IntervalJitter)
		local launchAt = now + (i - 1) * CFG.Interval + jitter
		rockets[nextId] = {
			id = nextId,
			origin = a.origin,
			dir = a.dir,
			launchAt = launchAt,
			pos = a.origin,
			params = params,
		}
		table.insert(payload, { id = nextId, origin = a.origin, dir = a.dir, at = launchAt })
	end
	Remotes.AirstrikeRockets:FireAllClients(payload)
	log(("salwa: %d rakiet w %s"):format(#aims, target.id))
end

local function explode(rocket: Rocket, center: Vector3)
	rockets[rocket.id] = nil
	Remotes.AirstrikeRocketEnded:FireAllClients(rocket.id)
	-- `task.spawn`: destrukcja potrafi odczekać klatkę na budżet, a woła to pętla lotu (zasada 8b).
	task.spawn(BombService.explodeAt, center, CFG.Blast, nil)
end

local function step()
	if next(rockets) == nil then return end
	local now = Workspace:GetServerTimeNow()
	local lavaY = LavaService.getSurfaceY()
	for _, rocket in pairs(rockets) do
		local t = now - rocket.launchAt
		if t <= 0 then continue end
		local distance = math.min(CFG.Speed * t, CFG.MaxRange)
		local from = rocket.pos
		local to = rocket.origin + rocket.dir * distance
		local delta = to - from
		local hit = Workspace:Raycast(from, delta, rocket.params)
		-- Tafla lawy nie łapie promieni (`CanQuery = false`) — bez tego rakieta przelatywałaby pod nią.
		local lavaHit: Vector3? = nil
		if from.Y > lavaY and to.Y <= lavaY then
			lavaHit = from + rocket.dir * ((from.Y - lavaY) / -rocket.dir.Y)
		end
		if hit and (not lavaHit or (hit.Position - from).Magnitude <= (lavaHit - from).Magnitude) then
			explode(rocket, hit.Position + hit.Normal * CFG.HitBackoff)
		elseif lavaHit then
			explode(rocket, lavaHit)
		elseif distance >= CFG.MaxRange then
			explode(rocket, to)
		else
			rocket.pos = to
		end
	end
end

-- Zwraca czas serwera pierwszego uderzenia (do alarmu) albo nil, gdy nie ma czego trafić.
function AirstrikeService.strike(): number?
	local rec = pickBuilding()
	if not rec then
		log("żaden budynek nie wystaje nad lawę — nalot pominięty")
		return nil
	end
	local token = roundToken
	log(("alarm — cel %s"):format(rec.id))
	task.delay(CFG.Warning - CFG.FlightTime, function()
		if token ~= roundToken or GameLoopService.getState() ~= GameLoopService.STATE.ROUND then return end
		launch(rec)
	end)
	return Workspace:GetServerTimeNow() + CFG.Warning
end

function AirstrikeService.init()
	if initialized then return end
	initialized = true

	RunService.Heartbeat:Connect(step)
	-- Rakiety w locie: wybuch po odbudowie mapy rozwaliłby świeże budynki (lekcja z BombService).
	-- Kopie u klientów sprząta AirstrikeController na zmianie stanu gry.
	GameLoopService.RoundEnded:Connect(function()
		roundToken += 1
		table.clear(rockets)
	end)
end

return AirstrikeService
