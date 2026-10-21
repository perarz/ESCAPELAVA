--!strict
-- CarService.luau
-- AUTA (27.09, decyzja Kacpra: „wybucha + ogień”) — JEDYNY właściciel stanu aut po wybuchu.
--
-- Party aut są `Locked` (kontrakt „wybuch nie tyka”: zwykła destrukcja cięłaby je na dziury,
-- a 72 z 98 części to drobnica, która rozsypałaby się osobno), więc bomba pomijała auta
-- w całości. Teraz DestructionService zgłasza tu auto, którego najbliższa część jest w zasięgu
-- DZIURY wybuchu, a auto wybucha jako całość — razem z bombą (`Cars.Delay` = 0; klatkę później,
-- bo wprost z wnętrza wybuchu bomby weszłoby w jej niedokończoną destrukcję):
--   1. rozlatuje się na kawałki u klientów (przekazanie `shatter` — serwer je kasuje),
--   2. na jego miejscu płonie ogień (`Remotes.CarFire`, SAM efekt: nie rani, nie rozprzestrzenia
--      się — pożary jako mechanika są poza v1.0),
--   3. wybucha tą samą ścieżką co bomba (`BombService.explodeAt`: otoczenie + gracze, kill dla
--      rzucającego), tylko słabiej (`Cars.Blast`). Auto obok w zasięgu dziury — łańcuchowo.
-- 21.10: BECZKI (folder `Barrels`) idą tym samym torem z własnym profilem (`Cars.Profiles`):
-- mocniejszy wybuch (1,3× bomby), krótszy ogień; odpala je też pchnięcie (PushService).
-- Każde auto wybucha RAZ. Po rundzie MapService podmienia mapę na świeże klony, a słabe
-- klucze czyszczą się same.
--
-- Wybuch i przekazanie klientom są WSTRZYKIWANE w init.server: DestructionService woła
-- CarService, a BombService woła DestructionService — bezpośredni require = cykl.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local CarService = {}

local CARS = Config.Destruction.Cars

export type Injected = {
	-- Wybuch jak bomby: otoczenie (DestructionService.detonate) + gracze + BlastFX.
	explode: (center: Vector3, def: any, attacker: Player?) -> (),
	-- Instancje do rozpadu u klientów (kawałki lecą od wybuchu), serwer kasuje po chwili.
	shatter: (list: { Instance }, center: Vector3) -> (),
}

local deps: Injected? = nil

-- Siła wybuchu i czas ognia dla modelu: profil folderu (beczki) albo domyślny (auta).
local function profileOf(model: Instance): (any, number)
	local parent = model.Parent
	local profile = parent and (CARS.Profiles :: any)[parent.Name]
	if profile then
		return profile.Blast, profile.FireTime
	end
	return CARS.Blast, CARS.FireTime
end
local exploded: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function CarService.hasExploded(car: Instance): boolean
	return exploded[car] == true
end

-- Zapala auto trafione wybuchem. Idempotentne: auto trafione naraz przez kilka bomb albo
-- przez sąsiada w łańcuchu wybucha jeden raz.
function CarService.ignite(car: Model, attacker: Player?)
	if exploded[car] or not deps then
		return
	end
	exploded[car] = true
	task.delay(CARS.Delay, function()
		if not car.Parent or not deps then
			return
		end
		local blast, fireTime = profileOf(car)
		local cf, size = car:GetBoundingBox()
		local center = cf.Position
		-- Najpierw auto do klientów: jego części są wtedy „w przekazaniu” i własny wybuch ich
		-- nie liczy (ani jako osłony, ani jako celu).
		deps.shatter({ car }, center)
		Remotes.CarFire:FireAllClients(cf, size, fireTime)
		deps.explode(center, blast, attacker)
	end)
end

-- Beczka przy zawaleniu (21.10, Kacper: „spada i przy kontakcie wybucha”). DestructionService
-- zamiast przekazać ją klientom woła to: model spina się w jedną bryłę i spada FIZYKĄ SERWERA
-- (serwer musi znać miejsce i chwilę uderzenia), a wybucha, gdy po spadku `MinDrop` przestaje
-- lecieć w dół — czyli uderzyła. Po prędkości, nie po Touched: na starcie beczka dotyka własnej,
-- też spadającej podłogi. Sufit `MaxTime` (zaklinowana, wpadła w lawę bez dna) = wybuch i tak.
-- Bez sprawcy: zawalenie nie przenosi informacji, kto je spowodował.
local falling: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

function CarService.drop(model: Model)
	if exploded[model] or falling[model] or not model.Parent then
		return
	end
	local primary = model.PrimaryPart or Utils.largestPart(model)
	if not primary then
		CarService.ignite(model, nil)
		return
	end
	falling[model] = true
	Utils.weldModel(model, primary) -- spina i odkotwicza
	pcall(function()
		primary:SetNetworkOwner(nil) -- fizyka serwera: klient nie decyduje, gdzie uderzyła
	end)
	local FALL = CARS.Fall
	local startY = primary.Position.Y
	local startedAt = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent or not primary.Parent or exploded[model] then
			if conn then conn:Disconnect() end
			return
		end
		local dropped = startY - primary.Position.Y
		local landed = dropped >= FALL.MinDrop and primary.AssemblyLinearVelocity.Y > -FALL.StopSpeed
		if landed or os.clock() - startedAt > FALL.MaxTime then
			if conn then conn:Disconnect() end
			CarService.ignite(model, nil)
		end
	end)
end

function CarService.inject(injected: Injected)
	deps = injected
end

return CarService
