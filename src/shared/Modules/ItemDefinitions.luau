--!strict
-- ItemDefinitions.luau
-- Single source of truth dla itemów (sklep + inventory + use).
-- Każda zmiana ceny/stacka tutaj — nie w services.

local ItemDefinitions = {}

ItemDefinitions.bomb = {
	id = "bomb",
	name = "Bomb",
	price = 50,
	-- Inventory nowy schema: { itemId = count } — gracz może mieć dowolnie dużo per item type.
	-- maxStack tylko jako sanity cap (przyszłe — gdyby balans wymagał).
	maxStack = 9999,
	cooldown = 2,           -- sekundy między rzutami (per gracz, server-side)
	-- Throw mechanics:
	throwSpeed = 60,        -- stud/s forward (kierunek LookVector lub mouseDir)
	throwLift = 20,         -- stud/s upward — lekki łuk
	fuse = 2.5,             -- sekundy zanim eksploduje (zawsze, niezależnie od kolizji)
	selfImmuneTime = 0.3,   -- sek, bomb nie dotyka rzucającego (żeby nie eksplodowała na nim)
	-- Detonation:
	blastRadius = 22,       -- stud (damage zasięg dla humanoidów)
	damagePercent = 0.5,    -- 50% MaxHealth w epicentrum (skaluje liniowo do 0)
	knockbackForce = 450,   -- velocity stud/s w epicentrum
	knockbackMinT = 0.35,   -- min multiplier — nawet daleko gracz dostanie push 35% × force
	-- Destrukcja środowiska (lokalna — tylko parts blisko epicentrum):
	destructionRadius = 12, -- stud (parts w tym radius dostaną unanchor + impulse)
	destructionImpulse = 60,-- siła odpychania partów od centrum
	ragdollDuration = 2,    -- sek, PlatformStand=true (postać leci jak ragdoll)
	destroyJoints = true,   -- Explosion.DestroyJointRadiusPercent=1 → rozłącza Snap/Weld
	-- icon = "rbxassetid://..."  -- placeholder Day 4+
}

ItemDefinitions.bridge_builder = {
	id = "bridge_builder",
	name = "Most",
	price = 100,
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
