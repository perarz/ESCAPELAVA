--!strict
-- ItemDefinitions.luau
-- Single source of truth dla itemów (sklep + inventory + use).
-- Każda zmiana ceny/stacka tutaj — nie w services.

local ItemDefinitions = {}

ItemDefinitions.bomb = {
	id = "bomb",
	name = "Bomba",
	price = 50,
	desc = "Rzuć i wysadź ściany, filary oraz graczy. Wybuch niszczy teren.",
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
		glassRadius = 60, -- szyby (Material Glass) tłuką się w TYM promieniu — także na
		                  -- sąsiednich budynkach, bez occlusion (fala "przez okna")
	},
	-- icon = "rbxassetid://..."  -- placeholder Day 4+
}

ItemDefinitions.bridge_builder = {
	id = "bridge_builder",
	name = "Most",
	price = 100,
	desc = "Postaw kładkę nad lawą albo dziurą. Przejście dla całej ekipy.",
	maxStack = 9999,
	-- Bridge mechanics (server-side validate)
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

function ItemDefinitions.get(itemId: string)
	return ItemDefinitions[itemId]
end

function ItemDefinitions.exists(itemId: string): boolean
	return ItemDefinitions[itemId] ~= nil
end

return ItemDefinitions
