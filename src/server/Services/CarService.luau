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
-- Każde auto wybucha RAZ. Po rundzie MapService podmienia mapę na świeże klony, a słabe
-- klucze czyszczą się same.
--
-- Wybuch i przekazanie klientom są WSTRZYKIWANE w init.server: DestructionService woła
-- CarService, a BombService woła DestructionService — bezpośredni require = cykl.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CarService = {}

local CARS = Config.Destruction.Cars

export type Injected = {
	-- Wybuch jak bomby: otoczenie (DestructionService.detonate) + gracze + BlastFX.
	explode: (center: Vector3, def: any, attacker: Player?) -> (),
	-- Instancje do rozpadu u klientów (kawałki lecą od wybuchu), serwer kasuje po chwili.
	shatter: (list: { Instance }, center: Vector3) -> (),
}

local deps: Injected? = nil
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
		local cf, size = car:GetBoundingBox()
		local center = cf.Position
		-- Najpierw auto do klientów: jego części są wtedy „w przekazaniu” i własny wybuch ich
		-- nie liczy (ani jako osłony, ani jako celu).
		deps.shatter({ car }, center)
		Remotes.CarFire:FireAllClients(cf, size, CARS.FireTime)
		deps.explode(center, CARS.Blast, attacker)
	end)
end

function CarService.inject(injected: Injected)
	deps = injected
end

return CarService
