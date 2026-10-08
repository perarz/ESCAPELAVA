-- ESCAPE LAVA — tag "Ladder" na drabinach (08.10, przyciaganie do drabiny)
-- Wklej CALY plik w Command Bar w Studio (EDIT mode, nie Play). ⚠️ Po uruchomieniu Cmd+S.
--
-- PO CO: LadderController (klient) przyciaga postac do drabiny, a FallDamageService (serwer)
-- traktuje drabine jak grunt. Oba rozpoznaja drabine po tagu `Config.Ladder.Tag` = "Ladder".
-- Ten skrypt stawia tag na szynach i szczeblach wszystkich drabin w Workspace.Map.
--
-- KONTRAKT (zmierzone 08.10): 6 drabin = 12 szyn + szczeble.
--   SZYNA   = pionowy part, przekroj <= 1.3 x 1.3, wysokosc >= 8.
--   SZCZEBEL = poziomy part dotykajacy szyny: grubosc <= 1.2 w pionie i w jednej osi poziomej,
--              dlugosc 2..8 (na mapie 4..6 x 1 x 1, co 2 study).
--   Drabina = szyna, przy ktorej jest co najmniej 5 szczebli.
--   Modele `Leader` w PurpleSchool / CyanOffice / GreenBuilding / PupleHotel + drabiny
--   w OrangeBuilding.Building i OldBuilding2.Model.
-- ⚠️ IDENTYFIKACJA PO KSZTALCIE, NIE PO TAGU (ta sama lekcja co LAMPS_LIGHTS: finder oparty
-- na wlasciwosci, ktora skrypt ustawia, znajduje zero dokladnie wtedy, kiedy jest potrzebny).
-- Nowa drabina postawiona w Studio = uruchomic skrypt jeszcze raz (jest idempotentny).
--
-- TRYB 1 = raport (nic nie zmienia), TRYB 2 = postaw tagi, TRYB 3 = zdejmij wszystkie tagi "Ladder".

local TRYB = 1

local CollectionService = game:GetService("CollectionService")
local TAG = "Ladder"
local MIN_RUNGS = 5

local function worldDims(p)
	local cf, s = p.CFrame, p.Size
	local e = Vector3.zero
	for _, a in ipairs({ cf.RightVector * s.X, cf.UpVector * s.Y, cf.LookVector * s.Z }) do
		e += Vector3.new(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
	end
	return e
end

if TRYB == 3 then
	local n = 0
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		CollectionService:RemoveTag(inst, TAG)
		n += 1
	end
	print(("[LADDERS] TRYB 3: zdjeto tag z %d obiektow"):format(n))
	return
end

local rails = {}
for _, d in ipairs(workspace.Map:GetDescendants()) do
	if d:IsA("BasePart") then
		local e = worldDims(d)
		if e.Y >= 8 and e.X <= 1.3 and e.Z <= 1.3 then
			table.insert(rails, d)
		end
	end
end

local ladderParts = {}
local railCount, rungCount = 0, 0
local perParent = {}
for _, rail in ipairs(rails) do
	local e = worldDims(rail)
	local rungs = {}
	for _, t in ipairs(workspace:GetPartBoundsInBox(rail.CFrame, e + Vector3.new(1.2, 0, 1.2))) do
		if t ~= rail and t:IsDescendantOf(workspace.Map) then
			local te = worldDims(t)
			local long = math.max(te.X, te.Z)
			local thin = math.min(te.X, te.Z)
			if te.Y <= 1.2 and thin <= 1.2 and long >= 2 and long <= 8 then
				table.insert(rungs, t)
			end
		end
	end
	if #rungs >= MIN_RUNGS then
		if not ladderParts[rail] then
			ladderParts[rail] = true
			railCount += 1
			local key = rail.Parent:GetFullName()
			perParent[key] = (perParent[key] or 0) + 1
		end
		for _, r in ipairs(rungs) do
			if not ladderParts[r] then
				ladderParts[r] = true
				rungCount += 1
			end
		end
	end
end

for k, v in pairs(perParent) do
	print(("[LADDERS]   %s — szyn %d"):format(k, v))
end
print(("[LADDERS] szyn %d (oczekiwane 12), szczebli %d"):format(railCount, rungCount))
if railCount ~= 12 then
	warn("[LADDERS] liczba szyn inna niz zmierzona 08.10 — sprawdz liste wyzej, zanim dasz TRYB 2")
end

if TRYB == 2 then
	local added = 0
	for part in pairs(ladderParts) do
		if not CollectionService:HasTag(part, TAG) then
			CollectionService:AddTag(part, TAG)
			added += 1
		end
	end
	print(("[LADDERS] TRYB 2: dodano tag do %d partow (razem z tagiem: %d). Teraz Cmd+S."):format(
		added, #CollectionService:GetTagged(TAG)))
end
