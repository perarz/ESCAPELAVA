--!strict
-- ItemDefinitions.luau
-- Single source of truth dla itemów (sklep + inventory + use).
-- Każda zmiana ceny/stacka tutaj — nie w services.

local Utils = require(script.Parent.Utils)

local ItemDefinitions = {}

ItemDefinitions.bomb = {
	id = "bomb",
	name = "Bomb", -- 10.10: nazwy itemów po angielsku (decyzja Kacpra)
	-- Ikona w slocie paska (10.10): z output/inventory-icons-v1, zmniejszona do 512 px (ostra
	-- przy każdej skali slotu), wgrana na konto Kacpra.
	icon = "rbxassetid://130438008648276", -- 19.10: render modelu z gry + czarny obrys (output/inventory-icons-v2)
	price = 50,
	-- 18.10: opisy po angielsku (decyzja Kacpra) — Fredoka nie ma polskich znaków (ć, ź, ś
	-- rysowały się zastępczą czcionką). Czyta je sklep i panel INVENTORY.
	desc = "Throw it to blast walls, pillars and players. The explosion wrecks the map.",
	-- Nazwa modelu na wystawie w scenie sklepu (Workspace.<Config.Shop.SceneName>
	-- .<Config.Shop.ItemsFolder>.<sceneModel>). Kamera celuje w ten model; brak modelu
	-- = item po prostu nie pojawia się w sklepie (z warnem, nie z błędem).
	sceneModel = "Bomb",
	-- Paski cech w ekwipunku (18.10, 0-5). Balans liczb: Claude + review Kacpra.
	stats = { power = 5, range = 3, mobility = 1 },
	-- Model z ReplicatedStorage używany JAKO PRZEDMIOT: w ręce (Handle Toola) i jako lecący
	-- pocisk. Jeden model do obu, bo to ta sama bomba — gracz rzuca dokładnie tym, co trzymał.
	-- Brak modelu = kod buduje starą kulę z kodu (fallback, nic się nie wywala).
	toolModel = "Bomb",
	-- Inventory nowy schema: { itemId = count } — gracz może mieć dowolnie dużo per item type.
	-- maxStack tylko jako sanity cap (przyszłe — gdyby balans wymagał).
	maxStack = 9999,
	-- Cooldown rzutu jest w Config.RateLimits.BombThrow (server enforce + klient mirror).
	-- Throw mechanics:
	throwSpeed = 60,        -- stud/s forward (kierunek LookVector lub mouseDir)
	throwLift = 20,         -- stud/s upward — lekki łuk
	fuse = 2.5,             -- sekundy zanim eksploduje (zawsze, niezależnie od kolizji)
	-- Zachowanie po dropie: bomba ma szybko przystanąć, nie odjeżdżać z miejsca celu.
	-- Kula toczy się w Robloxie bez końca (brak rolling resistance), stąd ręczne tłumienie.
	-- NIE freeze — bomba dalej jest fizyczna.
	bounciness = 0.05,      -- elasticity; default 0.5 → bomba skakała po lądowaniu
	rollDamping = 0.90,     -- mnożnik prędkości per klatkę (60Hz) gdy bomba PRZY ZIEMI
	                        -- (raycast). Mniejszy = szybciej staje (0.90 ≈ stop w ~0.5s).
	                        -- 1 = tłumienie wyłączone. W locie nietykane — rzut pełnej długości.
	-- Detonation (gracze — BombService.applyDamageAndKnockback):
	blastRadius = 22,       -- stud (damage zasięg dla humanoidów)
	damagePercent = 0.6,    -- 60% MaxHealth w epicentrum (skaluje liniowo do 0); 10.10: było 0.5, +20% (Kacper)
	knockbackForce = 450,   -- velocity stud/s w epicentrum
	knockbackMinT = 0.35,   -- min multiplier — nawet daleko gracz dostanie push 35% × force
	ragdollDuration = 2,    -- sek, PlatformStand=true (postać leci jak ragdoll)
	-- Destrukcja geometrii (system v2 — DestructionService, plan: DESTRUCTION_PLAN.md).
	-- Tu tylko "jak mocna jest TA bomba"; kształt wyrzutu, cięcie i budżety = Config.Destruction.
	-- nil/brak tabeli = item nie rusza otoczenia.
	destruction = {
		radius = 24,      -- zasięg działania na geometrię (dystans do POWIERZCHNI parta)
		damage = 160,     -- dmg strukturalny w epicentrum, liniowo do 0 na krawędzi.
		                  -- Wall HP=100 → niszczy ściany do ~9 stud, dalej tylko rani
		                  -- (attribute DestrHP; kolejna bomba w to samo miejsce dobija).
		                  -- 2026-08-12: próba nerfu do 130 + sufit wyrwy popsuła ściany
		                  -- (za małe odpryski) — przywrócone do 160 i sufit skasowany.
		impulse = 95,     -- prędkość gruzu w epicentrum (stud/s)
		minImpulseT = 0.1, -- floor falloffu impulsu — krawędź ma drgnąć, nie stać
		-- ⚠️ ZMIERZONE NA MAPIE 2026-09-21 (367 szyb, 40 losowych epicentrów):
		--   promień 24 -> średnio  8.1 szyby (max 16)
		--   promień 35 -> średnio 16.6 szyby (max 33)   <- TU JESTEŚMY
		--   promień 60 -> średnio 40.3 szyby (max 72)   <- było
		-- Zejście z 60 na 35 na prośbę „łatwo, ale mniejszy obszar": szkło dalej pada
		-- DUŻO dalej niż ściany (promień wybuchu to 24) i nadal przez ściany, ale jedna
		-- bomba przestaje rozbierać pół dzielnicy.
		-- 📌 Drugi powód dla 35: max 33 mieści się pod `FX.GlassMaxPanes` = 40, więc KAŻDA
		-- stłuczona szyba dostaje odłamki. Przy 60 sufit ucinał payload i część szyb
		-- znikała bez efektu — gracz widział, że coś zniknęło, ale nie widział czym.
		glassRadius = 35, -- szyby (Material Glass) tłuką się w TYM promieniu — także na
		                  -- sąsiednich budynkach, bez occlusion (fala "przez okna")
	},
}

ItemDefinitions.bridge_builder = {
	id = "bridge_builder",
	name = "Bridge",
	icon = "rbxassetid://97542975966293",
	price = 100,
	desc = "Build a plank over lava or a gap. Anyone can cross it.",
	sceneModel = "Blueprint",
	stats = { power = 0, range = 2, mobility = 4 },
	-- Blueprint trzymany w ręce w trybie budowania (Tool) …
	toolModel = "Blueprint",
	-- … a to jest most, który realnie staje na mapie.
	worldModel = "Bridge",
	maxStack = 9999,
	-- Bridge mechanics (server-side validate)
	-- ⚠️ WYMIARY TO TYLKO FALLBACK. Gdy `worldModel` istnieje, prawdziwe wymiary czyta się
	-- z jego bounding boxa (`Utils.assetSize`) — i serwer, i klient, więc ghost pokazuje
	-- dokładnie to, co powstanie. Model Kacpra ma dziś 5.72 × 0.50 × 13.25, czyli most jest
	-- DŁUŻSZY i SZERSZY niż te liczby. Chcesz inny rozmiar mostu → przeskaluj model
	-- w Studio (Model:ScaleTo), nie ruszaj tych pól: asset jest źródłem prawdy.
	-- ⚠️ Większy most niż dawne 10×2 jest ZAMIERZONY (decyzja Kacpra 2026-09-20) — nie
	-- "naprawiać" tego z powrotem, gdy ktoś zauważy rozjazd między tymi liczbami a grą.
	length = 10,             -- stud (Z axis, long side)
	width = 2,               -- stud (X axis)
	thickness = 1,           -- stud (Y axis)
	color = Color3.fromRGB(115, 80, 50),  -- brown wood
	material = Enum.Material.Wood,
	rotateSnapDegrees = 45,  -- klient: R obraca o tyle stopni
	maxBuildDistance = 20,   -- stud (server-side anti-cheat)
}

ItemDefinitions.grapple = {
	id = "grapple",
	name = "Grapple",
	icon = "rbxassetid://101471002129173",
	price = 40,
	desc = "Aim at a wall or roof and get yanked right there. One use.",
	-- Wystawa w scenie sklepu: model Kacpra stoi już w WeaponShopScene.Decorations.
	-- Markera kamery przy nim NIE MA, więc kadr liczy się z bounding boxa (AutoCamera*).
	-- Postawienie markera obok modelu przejmie kadr bez żadnej zmiany w kodzie.
	sceneModel = "HandHook",
	stats = { power = 0, range = 5, mobility = 5 },
	-- Ten sam model trafia do ręki. W przeciwieństwie do bomby hak NIE jest pociskiem —
	-- nic nie leci, więc Handle jest wyłącznie uchwytem i nie niesie żadnej fizyki.
	-- ⚠️ Największa bryła tego modelu to płaski Union 0.09 × 1.80 × 1.80, czyli
	-- `Utils.largestPart` wybierze na Handle dysk. Dla trzymanego przedmiotu to bez
	-- znaczenia (Massless + weld), ale gdyby hak kiedyś miał wystrzeliwać fizyczny grot,
	-- nośnika fizyki trzeba będzie wskazać jawnie — tak jak bomba wskazuje swoją kulę.
	toolModel = "HandHook",
	maxStack = 9999,
	-- Cała mechanika (zasięg, czas lotu, clampy) siedzi w Config.Grapple — tutaj nic
	-- nie dublujemy, bo to są liczby do strojenia, a nie kontrakt itemu.
}

-- 20.10, decyzje Kacpra: łyk w biegu, 10 s nieskończonej staminy, pasek mieni się kolorami,
-- 25$. Liczby efektu w Config.EnergyDrink; serwer: EnergyDrinkService.
ItemDefinitions.energy_drink = {
	id = "energy_drink",
	name = "Energy Drink",
	icon = "rbxassetid://77399251372698", -- 20.10: render z gry + czarny obrys (output/inventory-icons-v2)
	price = 25,
	desc = "Drink it on the run: unlimited stamina for 10 seconds. One use.",
	-- Model Kacpra z wystawy; ten sam model trafia do ręki (kopia w ReplicatedStorage).
	sceneModel = "EnergyDrink",
	toolModel = "EnergyDrink",
	stats = { power = 0, range = 0, mobility = 4 },
	maxStack = 9999,
}

-- 20.10, decyzje Kacpra: rakieta prosto i szybko, wybuch przy pierwszym trafieniu, słabszy od
-- bomby, 1 rakieta = 75$, własny wybuch jak bomba rzucającego (rocket jump usunięty 21.10). Lot: Config.Rpg,
-- serwer: RpgService. Pola wybuchu jak w `bomb`, bo czyta je ta sama ścieżka
-- (BombService.explodeAt) — ~70% bomby: przewagą RPG jest zasięg i wybuch od razu.
ItemDefinitions.rpg = {
	id = "rpg",
	name = "RPG",
	icon = "rbxassetid://139499438619574", -- 20.10: render z gry + czarny obrys (output/inventory-icons-v2)
	price = 75,
	desc = "Fire a rocket straight where you aim. It blows up on the first thing it hits. One shot.",
	sceneModel = "Rpg",
	-- Cała wyrzutnia w ręce; leci tylko jej głowica (Config.Rpg.RocketPartName).
	toolModel = "Rpg",
	stats = { power = 4, range = 5, mobility = 1 },
	maxStack = 9999,
	blastRadius = 16,       -- bomba 22
	damagePercent = 0.42,   -- bomba 0.6
	knockbackForce = 320,   -- bomba 450
	knockbackMinT = 0.35,
	ragdollDuration = 1.6,  -- bomba 2
	destruction = {
		radius = 18,        -- bomba 24
		damage = 115,       -- bomba 160 (ściana ma 100 HP — dziura mniejsza, ale jest)
		impulse = 70,       -- bomba 95
		minImpulseT = 0.1,
		glassRadius = 25,   -- bomba 35
	},
}

-- Kolejność wyświetlania w sklepie (porządek deterministyczny)
ItemDefinitions.shopOrder = { "bomb", "bridge_builder", "grapple", "energy_drink", "rpg" }

-- Realny rozmiar rzeczy, którą item stawia w świecie (`worldModel`), z fallbackiem na
-- wymiary wpisane w definicji. TUTAJ, a nie w każdym serwisie osobno, bo odpowiedź MUSI
-- być identyczna po stronie serwera (który stawia most) i klienta (który rysuje jego
-- ghost i liczy, gdzie wypadnie środek). Dwie kopie tego wzoru = podgląd pokazujący co
-- innego niż to, co powstanie — czyli most budowany obok krawędzi, na którą celował gracz.
-- Zwraca (szerokość X, grubość Y, długość Z).
function ItemDefinitions.worldSize(itemId: string): Vector3?
	local def = ItemDefinitions.get(itemId)
	if not def then return nil end
	if def.worldModel then
		local size = Utils.assetSize(def.worldModel)
		if size then return size end
	end
	if def.width and def.thickness and def.length then
		return Vector3.new(def.width, def.thickness, def.length)
	end
	return nil
end

-- Tylko prawdziwa definicja itemu. W tej samej tabeli leżą też `shopOrder`, `worldSize`,
-- `get` i `exists`, więc gołe `ItemDefinitions[itemId]` dla `"shopOrder"` zwracało listę,
-- a klient wysyłający `BuyItem("shopOrder")` wywracał handler sklepu na `def.price`
-- (przegląd 29.09, A-10/B-7). Definicja ma zawsze `id` równe swojemu kluczowi.
function ItemDefinitions.get(itemId: string)
	local def = ItemDefinitions[itemId]
	if type(def) == "table" and def.id == itemId then
		return def
	end
	return nil
end

function ItemDefinitions.exists(itemId: string): boolean
	return ItemDefinitions.get(itemId) ~= nil
end

return ItemDefinitions
