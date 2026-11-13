--!strict
-- SkillService.luau (09.11) — właściciel drzewka umiejętności i rebirthów (plan: docs/SKILLS_PLAN.md).
--
-- STAN (zapis: `data.skills = { nodes = { [nodeId] = true }, rebirths = n }`) zmienia tylko ten
-- serwis. Reszta gry pyta przez `getBonus` / `cashMultiplier` / `getRebirths` — serwer liczy
-- obrażenia, limit prędkości i kasę ZE SWOJEGO stanu. Atrybuty gracza (`Config.Skills.*Attribute`)
-- są tylko dla klienta: ruch w MovementController i wyświetlanie. Podmieniony atrybut u klienta
-- nie replikuje się na serwer, a szybszy bieg i tak złapie AntiCheatService (limit stąd).
--
-- ZAKUP POLA: kasa i pole w JEDNEJ podmianie danych (CashService.purchase, jak kosmetyki) —
-- autosave ani wyjście gracza nie zobaczą kasy wydanej bez pola. Powód w logu: `skill_<id>`.
-- REBIRTH: jedna mutacja — puste drzewko, licznik +1, statystyki „od rebirthu” na zero.
-- Zabiera TYLKO drzewko; kasa, itemy i kosmetyki zostają.
--
-- GDZIE: przy magu (odległość liczona na serwerze, zasada 3). Bez bramki „tylko lobby”: mag stoi
-- 500 studów od mapy, więc żywy uczestnik rundy tam nie dojdzie, a pomijający rundę albo
-- odrodzony w lobby ma kupować także w jej trakcie (bonus działa od razu, rebirth od razu go
-- zdejmuje — anty-cheat czyta ten sam stan).
--
-- BONUSY są liczone raz przy zmianie i trzymane w pamięci: `getBonus` wołają lawa (co klatkę
-- na gracza), wybuchy i anty-cheat, więc nie może sumować definicji przy każdym pytaniu.
--
-- API:
--   SkillService.getBonus(player, kind) -> number   (0, gdy brak danych)
--   SkillService.cashMultiplier(player) -> number   (1 + GREED + rebirthy)
--   SkillService.getRebirths(player) -> number
--   SkillService.replicateTo(player)                — stan dla klienta (ClientReady, zmiany)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local SkillDefinitions = require(ReplicatedStorage.Shared.Modules.SkillDefinitions)
local PlayerDataService = require(script.Parent.PlayerDataService)
local CashService = require(script.Parent.CashService)
local StatsService = require(script.Parent.StatsService)

local SkillService = {}

local CFG = Config.Skills
-- Sufit wpisów w zapisie: definicji jest kilkanaście; chroni przed śmieciami w uszkodzonym save.
local MAX_NODES = 64

type State = { nodes: { [string]: boolean }, rebirths: number }
type Cached = { bonus: { [string]: number }, rebirths: number }

local cached: { [Player]: Cached } = {}
local windows: { [Player]: { started: number, count: number } } = {}
local mageCache: Model? = nil

-- Nieznane id zostaje w zapisie (pole wycofane z definicji nie może po cichu zabrać zapłaconego
-- ulepszenia, gdyby wróciło), ale nic nie daje i nie liczy się do rebirthu.
local function sanitize(raw: any): State
	local state: State = { nodes = {}, rebirths = 0 }
	if type(raw) ~= "table" then return state end
	if type(raw.nodes) == "table" then
		local count = 0
		for id, owned in pairs(raw.nodes) do
			if type(id) == "string" and #id <= 64 and owned == true and count < MAX_NODES then
				state.nodes[id] = true
				count += 1
			end
		end
	end
	local rebirths = raw.rebirths
	if type(rebirths) == "number" and rebirths == rebirths and rebirths >= 0 and rebirths < math.huge then
		state.rebirths = math.floor(rebirths)
	end
	return state
end

local function computeBonus(state: State): { [string]: number }
	local bonus: { [string]: number } = {}
	for id in pairs(state.nodes) do
		local node = SkillDefinitions.get(id)
		-- Pole z odnogi, której ten rebirth jeszcze nie odblokował, nie działa (uszkodzony zapis).
		if node and SkillDefinitions.isUnlocked(node, state.rebirths) then
			for _, effect in ipairs(node.effects) do
				bonus[effect.kind] = (bonus[effect.kind] or 0) + effect.value
			end
		end
	end
	return bonus
end

-- Przelicza bonusy z zapisu i wystawia atrybuty dla klienta. Po KAŻDEJ zmianie stanu.
local function refresh(player: Player)
	local data = PlayerDataService.get(player)
	if not data or player.Parent ~= Players then
		cached[player] = nil
		return
	end
	local state = sanitize(data.skills)
	local bonus = computeBonus(state)
	cached[player] = { bonus = bonus, rebirths = state.rebirths }
	player:SetAttribute(CFG.SpeedAttribute, bonus.speed or 0)
	player:SetAttribute(CFG.StaminaAttribute, bonus.stamina or 0)
	player:SetAttribute(CFG.RebirthsAttribute, state.rebirths)
end

function SkillService.getBonus(player: Player, kind: string): number
	local entry = cached[player]
	return if entry then entry.bonus[kind] or 0 else 0
end

function SkillService.getRebirths(player: Player): number
	local entry = cached[player]
	return if entry then entry.rebirths else 0
end

-- Mnożnik nagród za przetrwanie i kill. GREED i rebirthy DODAJĄ się do siebie (decyzja z planu).
function SkillService.cashMultiplier(player: Player): number
	local entry = cached[player]
	if not entry then return 1 end
	local fromRebirths = math.min(entry.rebirths * CFG.RebirthCashBonus, CFG.RebirthCashBonusMax)
	return 1 + (entry.bonus.greed or 0) + fromRebirths
end

function SkillService.replicateTo(player: Player)
	local data = PlayerDataService.get(player)
	if not data or player.Parent ~= Players then return end
	local state = sanitize(data.skills)
	local owned: { string } = {}
	for id in pairs(state.nodes) do
		if SkillDefinitions.get(id) then table.insert(owned, id) end
	end
	Remotes.SkillsChanged:FireClient(player, owned, state.rebirths, StatsService.snapshot(player))
end

-- ── Mag ────────────────────────────────────────────────────────────────────────

local function findMage(): Model?
	if mageCache and mageCache.Parent then return mageCache end
	mageCache = nil
	local tower = Workspace:FindFirstChild(CFG.TowerModelName)
	local mage = tower and tower:FindFirstChild(CFG.MageName, true)
	if mage and mage:IsA("Model") then
		mageCache = mage
		return mage
	end
	return nil
end

local function mageAnchor(): BasePart?
	local mage = findMage()
	if not mage then return nil end
	local root = mage:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	return mage.PrimaryPart or mage:FindFirstChildWhichIsA("BasePart")
end

-- Prompt jest elementem FUNKCJONALNYM (bez niego panelu nie da się otworzyć), więc tworzymy go
-- sami, jak sklep. Własny prompt Kacpra o tej samej nazwie zostaje nietknięty.
local function ensurePrompt()
	local mage = findMage()
	local anchor = mageAnchor()
	if not mage or not anchor then
		warn(("[Skill] nie znalazłem %s pod Workspace.%s — drzewka nie da się otworzyć"):format(
			CFG.MageName, CFG.TowerModelName))
		return
	end
	local existing = mage:FindFirstChild(CFG.PromptName, true)
	if existing and existing:IsA("ProximityPrompt") then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CFG.PromptName
	prompt.ActionText = CFG.PromptActionText
	prompt.ObjectText = CFG.PromptObjectText
	prompt.KeyboardKeyCode = Config.Shop.PromptKeyCode
	prompt.MaxActivationDistance = CFG.PromptMaxDistance
	-- Mag stoi za ladą, między świecami i księgami — z linią wzroku prompt znikałby losowo.
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	print(("[Skill] utworzono %s na %s"):format(CFG.PromptName, anchor:GetFullName()))
end

-- ── Walidacja wspólna dla zakupu i rebirthu ────────────────────────────────────

local function atMage(player: Player): (boolean, string?)
	if player.Parent ~= Players then return false, "player_left" end
	if not PlayerDataService.isWritable(player) then return false, "data_not_ready" end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and character.Parent and humanoid and humanoid.Health > 0
		and root and root:IsA("BasePart")) then
		return false, "character_unavailable"
	end
	local anchor = mageAnchor()
	if not anchor then return false, "mage_unavailable" end
	-- Zapis `not (a <= b)` odrzuca też NaN w pozycji.
	if not ((anchor.Position - root.Position).Magnitude <= CFG.InteractDistance) then
		return false, "too_far"
	end
	return true, nil
end

-- Rebirth nie rusza kasy, więc nie przechodzi przez CashService — log w tym samym formacie
-- (czas + powód, zasada 6) wypisujemy tutaj.
local function log(player: Player, reason: string, detail: string)
	print(("[Skill] %s (%s) %s  unix_ms=%d"):format(
		player.Name, reason, detail, DateTime.now().UnixTimestampMillis))
end

-- ── Zakup pola ─────────────────────────────────────────────────────────────────

-- Wszystko, co decyduje o zakupie, w jednym miejscu: tę samą funkcję woła kontrola przed
-- transakcją i `prepare` w jej środku (stan mógł się zmienić między nimi).
local function unlockRejection(player: Player, node: SkillDefinitions.Node, state: State): string?
	if not SkillDefinitions.isUnlocked(node, state.rebirths) then return "branch_locked" end
	if state.nodes[node.id] then return "already_owned" end
	if node.requires and not state.nodes[node.requires] then return "missing_previous" end
	local requirement = node.requirement
	if requirement and StatsService.getCycle(player, requirement.stat) < requirement.count then
		return "requirement_not_met"
	end
	return nil
end

local function unlock(player: Player, nodeId: any): (boolean, string?)
	if type(nodeId) ~= "string" or #nodeId > 64 then return false, "unknown_node" end
	local node = SkillDefinitions.get(nodeId)
	if not node then return false, "unknown_node" end
	local allowed, reason = atMage(player)
	if not allowed then return false, reason end
	local data = PlayerDataService.get(player)
	local rejected = unlockRejection(player, node, sanitize(data.skills))
	if rejected then return false, rejected end

	-- `prepare` tylko buduje nowy stan: bez yieldów i bez zmiany wejścia (kontrakt CashService).
	local bought, failure = CashService.purchase(player, node.price, "skill_" .. node.id, function(current)
		local state = sanitize(current.skills)
		local again = unlockRejection(player, node, state)
		if again then return nil, again end
		state.nodes[node.id] = true
		local replacement = table.clone(current)
		replacement.skills = state
		return replacement, nil
	end)
	if not bought then return false, failure end
	-- Bonus działa od razu: przeliczenie przed odpowiedzią do klienta. Log transakcji z czasem
	-- i powodem `skill_<id>` wypisał już CashService.
	refresh(player)
	return true, nil
end

-- ── Rebirth ────────────────────────────────────────────────────────────────────

local function rebirth(player: Player): (boolean, string?)
	local allowed, reason = atMage(player)
	if not allowed then return false, reason end
	local done = false
	local newCount = 0
	-- Mutator dostaje ŻYWĄ tabelę i nie może yieldować. Warunek sprawdzany w środku, na tym
	-- samym stanie, który zaraz zmienimy — dwa szybkie kliknięcia nie zrobią dwóch rebirthów.
	PlayerDataService.update(player, function(current)
		local state = sanitize(current.skills)
		if not SkillDefinitions.isComplete(state.nodes, state.rebirths) then return nil end
		newCount = state.rebirths + 1
		current.skills = { nodes = {}, rebirths = newCount }
		StatsService.resetCycleIn(current)
		done = true
		return current
	end)
	if not done then return false, "not_complete" end
	refresh(player)
	log(player, "rebirth_" .. newCount, "drzewko wyzerowane, kasa/itemy/kosmetyki bez zmian")
	return true, nil
end

-- ── Remote'y ───────────────────────────────────────────────────────────────────

-- Okno jednej sekundy na gracza: sufit na spam, nie cooldown (ponad limit prośba znika po cichu).
local function allowRequest(player: Player): boolean
	local now = os.clock()
	local window = windows[player]
	if not window then
		windows[player] = { started = now, count = 1 }
		return true
	end
	if now - window.started >= 1 then
		window.started, window.count = now, 1
		return true
	end
	window.count += 1
	return window.count <= CFG.RequestsPerSecond
end

-- Najpierw stan, potem wynik (jak kosmetyki): klient animuje zakup na już aktualnym drzewku.
local function reply(player: Player, action: string, id: any, success: boolean, reason: string?)
	SkillService.replicateTo(player)
	-- Nie odbijamy klientowi dowolnie dużego / egzotycznego payloadu.
	local safeId = if type(id) == "string" and #id <= 64 then id else ""
	Remotes.SkillResult:FireClient(player, success, action, safeId, reason)
end

local initialized = false
function SkillService.init()
	if initialized then return end
	initialized = true

	PlayerDataService.subscribe(function(eventKey, player, _old, _data)
		if eventKey ~= "loaded" and eventKey ~= "loaded_default" then return end
		if player.Parent ~= Players then return end
		PlayerDataService.update(player, function(current)
			current.skills = sanitize(current.skills)
			return current
		end)
		refresh(player)
		SkillService.replicateTo(player)
	end)
	-- Statystyka się zmieniła (kill, koniec rundy) → panel dostaje nowy postęp wymagań.
	StatsService.onChanged(function(player)
		SkillService.replicateTo(player)
	end)

	Remotes.UnlockSkill.OnServerEvent:Connect(function(player, nodeId)
		if not allowRequest(player) then return end
		local success, reason = unlock(player, nodeId)
		reply(player, "unlock", nodeId, success, reason)
	end)
	Remotes.Rebirth.OnServerEvent:Connect(function(player)
		if not allowRequest(player) then return end
		local success, reason = rebirth(player)
		reply(player, "rebirth", "", success, reason)
	end)
	Players.PlayerRemoving:Connect(function(player)
		cached[player] = nil
		windows[player] = nil
	end)

	ensurePrompt()
end

return SkillService
