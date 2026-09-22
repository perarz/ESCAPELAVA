--!strict
-- ItemDefinitions.luau
-- Single source of truth dla itemów (sklep + inventory + use).
-- Każda zmiana ceny/stacka tutaj — nie w services.

local Utils = require(script.Parent.Utils)

local ItemDefinitions = {}

ItemDefinitions.bomb = {
	id = "bomb",
	name = "Bomba",
	price = 50,
	desc = "Rzuć i wysadź ściany, filary oraz graczy. Wybuch niszczy teren.",
	-- Nazwa modelu na wystawie w scenie sklepu (Workspace.<Config.Shop.SceneName>
	-- .<Config.Shop.ItemsFolder>.<sceneModel>). Kamera celuje w ten model; brak modelu
	-- = item po prostu nie pojawia się w sklepie (z warnem, nie z błędem).
	sceneModel = "Bomb",
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
	damagePercent = 0.5,    -- 50% MaxHealth w epicentrum (skaluje liniowo do 0)
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
	-- icon = "rbxassetid://..."  -- placeholder Day 4+
}

ItemDefinitions.bridge_builder = {
	id = "bridge_builder",
	name = "Most",
	price = 100,
	desc = "Postaw kładkę nad lawą albo dziurą. Przejście dla całej ekipy.",
	sceneModel = "Blueprint",
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

-- Kolejność wyświetlania w sklepie (porządek deterministyczny)
ItemDefinitions.shopOrder = { "bomb", "bridge_builder" }

-- Realny rozmiar rzeczy, którą item stawia w świecie (`worldModel`), z fallbackiem na
-- wymiary wpisane w definicji. TUTAJ, a nie w każdym serwisie osobno, bo odpowiedź MUSI
-- być identyczna po stronie serwera (który stawia most) i klienta (który rysuje jego
-- ghost i liczy, gdzie wypadnie środek). Dwie kopie tego wzoru = podgląd pokazujący co
-- innego niż to, co powstanie — czyli most budowany obok krawędzi, na którą celował gracz.
-- Zwraca (szerokość X, grubość Y, długość Z).
function ItemDefinitions.worldSize(itemId: string): Vector3?
	local def = ItemDefinitions[itemId]
	if type(def) ~= "table" then return nil end
	if def.worldModel then
		local size = Utils.assetSize(def.worldModel)
		if size then return size end
	end
	if def.width and def.thickness and def.length then
		return Vector3.new(def.width, def.thickness, def.length)
	end
	return nil
end

function ItemDefinitions.get(itemId: string)
	return ItemDefinitions[itemId]
end

function ItemDefinitions.exists(itemId: string): boolean
	return ItemDefinitions[itemId] ~= nil
end

return ItemDefinitions
