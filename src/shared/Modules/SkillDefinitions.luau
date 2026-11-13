--!strict
-- SkillDefinitions.luau (09.11) — JEDYNA lista pól drzewka umiejętności i nagród rebirthów.
-- Czytają ją serwer (SkillService: walidacja, bonusy), panel (SkillTreeController) i sklep.
-- Plan, decyzje Kacpra i uzasadnienie liczb: docs/SKILLS_PLAN.md.
--
-- KSZTAŁT: korzeń `start`, od niego odnogi po dwa poziomy; poziom II wymaga poziomu I.
-- Poziom I kosztuje kasę, poziom II kasę i wymaganie liczone OD OSTATNIEGO REBIRTHU
-- (StatsService, licznik `cycle`). Odnoga jest dostępna od rebirthu `branches[x].rebirth`.
--
-- EFEKT to lista `{ kind, value }`; SkillService sumuje `value` po kupionych polach:
--   speed   ułamek chodu i sprintu        (MovementController + limit w AntiCheatService)
--   stamina ułamek maksymalnej staminy    (MovementController)
--   lava    ułamek mniej obrażeń od lawy  (LavaService)
--   tough   ułamek mniej obrażeń od wybuchów i upadku poniżej śmiertelnego (BombService, FallDamageService)
--   greed   ułamek więcej kasy za przetrwanie i kill (RewardsService, KillService)
--   force   poziom dziury wybijanej pchnięciem (PushService, Config.Skills.Force.Levels)
--   push    ułamek więcej siły pchnięcia gracza (PushService)
--
-- Zmiana ceny, wymagania albo wartości = tylko ten plik. Nowy rodzaj efektu trzeba też
-- podpiąć w serwisie, który go stosuje.

export type Effect = { kind: string, value: number }
export type Requirement = { stat: string, count: number }
export type Node = {
	id: string,
	branch: string,          -- "start" albo klucz z `branches`
	level: number,           -- 0 = korzeń, 1, 2
	requires: string?,       -- pole, które trzeba mieć wcześniej
	price: number,           -- liczba całkowita (CashService.purchase)
	requirement: Requirement?,
	effects: { Effect },
	title: string,
	desc: string,
}
export type Branch = {
	id: string,
	title: string,
	rebirth: number,         -- od którego rebirthu odnoga jest dostępna
	color: Color3,
	icon: string,
}

local SkillDefinitions = {}

-- Ikony: game-icons.net (Lorc, Delapouite), CC BY 3.0 — podpis w opisie gry (DO_RELEASE).
-- Białe z czarnym obrysem; kolor odnogi nadaje `ImageColor3`.
SkillDefinitions.icons = {
	start = "rbxassetid://93905985234522",   -- wizard-staff
	rebirth = "rbxassetid://138067380664051", -- cycle
	lock = "rbxassetid://72783047857523",     -- padlock
}

-- Kolejność = kolejność odnóg w panelu (pierwsza do góry, dalej zgodnie z zegarem).
SkillDefinitions.branchOrder = { "speed", "stamina", "lava", "tough", "greed", "force" }

SkillDefinitions.branches = {
	speed = {
		id = "speed", title = "SPEED", rebirth = 0,
		color = Color3.fromRGB(255, 220, 50), icon = "rbxassetid://71623328175568", -- sprint
	},
	stamina = {
		id = "stamina", title = "STAMINA", rebirth = 0,
		color = Color3.fromRGB(90, 220, 80), icon = "rbxassetid://98337319713905", -- lungs
	},
	lava = {
		id = "lava", title = "LAVA SKIN", rebirth = 1,
		color = Color3.fromRGB(255, 130, 30), icon = "rbxassetid://83252931225082", -- fire-shield
	},
	tough = {
		id = "tough", title = "TOUGHNESS", rebirth = 2,
		color = Color3.fromRGB(110, 160, 215), icon = "rbxassetid://133442847526088", -- heavy-helm
	},
	greed = {
		id = "greed", title = "GREED", rebirth = 3,
		color = Color3.fromRGB(255, 195, 40), icon = "rbxassetid://137538707406156", -- two-coins
	},
	force = {
		id = "force", title = "FORCE", rebirth = 4,
		color = Color3.fromRGB(175, 105, 255), icon = "rbxassetid://92012252540188", -- punch
	},
} :: { [string]: Branch }

-- Kolor korzenia (różdżka maga).
SkillDefinitions.startColor = Color3.fromRGB(200, 150, 255)

local nodes: { Node } = {
	{
		id = "start", branch = "start", level = 0, price = 150,
		effects = { { kind = "speed", value = 0.05 } },
		title = "START", desc = "+5% walk and sprint speed.",
	},
	{
		id = "speed_1", branch = "speed", level = 1, requires = "start", price = 300,
		effects = { { kind = "speed", value = 0.025 } },
		title = "SPEED I", desc = "+2.5% walk and sprint speed.",
	},
	{
		id = "speed_2", branch = "speed", level = 2, requires = "speed_1", price = 800,
		requirement = { stat = "survived", count = 10 },
		effects = { { kind = "speed", value = 0.025 } },
		title = "SPEED II", desc = "+2.5% walk and sprint speed.",
	},
	{
		id = "stamina_1", branch = "stamina", level = 1, requires = "start", price = 250,
		effects = { { kind = "stamina", value = 0.15 } },
		title = "STAMINA I", desc = "+15% stamina.",
	},
	{
		id = "stamina_2", branch = "stamina", level = 2, requires = "stamina_1", price = 700,
		requirement = { stat = "played", count = 15 },
		effects = { { kind = "stamina", value = 0.15 } },
		title = "STAMINA II", desc = "+15% stamina.",
	},
	{
		id = "lava_1", branch = "lava", level = 1, requires = "start", price = 300,
		effects = { { kind = "lava", value = 0.1 } },
		title = "LAVA SKIN I", desc = "Lava hurts you 10% less.",
	},
	{
		id = "lava_2", branch = "lava", level = 2, requires = "lava_1", price = 800,
		requirement = { stat = "played", count = 20 },
		effects = { { kind = "lava", value = 0.1 } },
		title = "LAVA SKIN II", desc = "Lava hurts you 10% less.",
	},
	{
		id = "tough_1", branch = "tough", level = 1, requires = "start", price = 350,
		effects = { { kind = "tough", value = 0.1 } },
		title = "TOUGHNESS I", desc = "-10% damage from explosions and falls.",
	},
	{
		id = "tough_2", branch = "tough", level = 2, requires = "tough_1", price = 900,
		requirement = { stat = "kills", count = 10 },
		effects = { { kind = "tough", value = 0.1 } },
		title = "TOUGHNESS II", desc = "-10% damage from explosions and falls.",
	},
	{
		id = "greed_1", branch = "greed", level = 1, requires = "start", price = 400,
		effects = { { kind = "greed", value = 0.1 } },
		title = "GREED I", desc = "+10% cash for surviving and kills.",
	},
	{
		id = "greed_2", branch = "greed", level = 2, requires = "greed_1", price = 1000,
		requirement = { stat = "kills", count = 25 },
		effects = { { kind = "greed", value = 0.1 } },
		title = "GREED II", desc = "+10% cash for surviving and kills.",
	},
	{
		id = "force_1", branch = "force", level = 1, requires = "start", price = 500,
		effects = { { kind = "force", value = 1 } },
		title = "FORCE I", desc = "Your push (F) punches a hole in the wall in front of you.",
	},
	{
		id = "force_2", branch = "force", level = 2, requires = "force_1", price = 1200,
		requirement = { stat = "kills", count = 15 },
		effects = { { kind = "force", value = 1 }, { kind = "push", value = 0.2 } },
		title = "FORCE II", desc = "A bigger hole and 20% stronger pushes.",
	},
}

local byId: { [string]: Node } = {}
for _, node in ipairs(nodes) do
	assert(byId[node.id] == nil, "SkillDefinitions: powtórzone id " .. node.id)
	assert(node.price % 1 == 0 and node.price >= 0, "SkillDefinitions: cena musi być liczbą całkowitą")
	byId[node.id] = node
	table.freeze(node.effects)
	table.freeze(node)
end
for _, node in ipairs(nodes) do
	assert(node.requires == nil or byId[node.requires :: string] ~= nil,
		"SkillDefinitions: nieznane pole w `requires` dla " .. node.id)
	assert(node.branch == "start" or SkillDefinitions.branches[node.branch] ~= nil,
		"SkillDefinitions: nieznana odnoga dla " .. node.id)
end

-- Kolejność: korzeń, potem odnogi poziomami. Panel buduje pola w tej kolejności.
SkillDefinitions.nodes = nodes
-- Statystyki, które mogą być wymaganiem (StatsService prowadzi dokładnie te).
SkillDefinitions.stats = { "kills", "survived", "played" }

function SkillDefinitions.get(id: string): Node?
	return byId[id]
end

-- Od ilu rebirthów pole jest w ogóle do kupienia (korzeń: od zera).
function SkillDefinitions.rebirthOf(node: Node): number
	local branch = SkillDefinitions.branches[node.branch]
	return if branch then branch.rebirth else 0
end

function SkillDefinitions.isUnlocked(node: Node, rebirths: number): boolean
	return rebirths >= SkillDefinitions.rebirthOf(node)
end

-- Czy gracz ma wszystko, co jest dla niego odblokowane (warunek rebirthu).
-- Zwraca też (kupione, potrzebne) do napisu na przycisku.
function SkillDefinitions.isComplete(owned: { [string]: boolean }, rebirths: number): (boolean, number, number)
	local have, need = 0, 0
	for _, node in ipairs(nodes) do
		if SkillDefinitions.isUnlocked(node, rebirths) then
			need += 1
			if owned[node.id] then have += 1 end
		end
	end
	return need > 0 and have >= need, have, need
end

-- Odnogi, które odblokowuje rebirth numer `rebirth` (nagroda pokazywana przed i po rebirthie).
-- Itemy z rebirthu mają pole `requiresRebirth` w ItemDefinitions — sklep liczy je sam.
function SkillDefinitions.branchesAt(rebirth: number): { Branch }
	local list: { Branch } = {}
	for _, id in ipairs(SkillDefinitions.branchOrder) do
		local branch = SkillDefinitions.branches[id]
		if branch.rebirth == rebirth then table.insert(list, branch) end
	end
	return list
end

return SkillDefinitions
