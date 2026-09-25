-- ESCAPE LAVA — StructureBake (destrukcja v4, faza P0). DESTRUCTION_PLAN.md → „v4”.
-- Wklej w Command Bar w Studio (EDIT mode, nie Play). Wymaga działającego `rojo serve`
-- (moduł leży w ServerScriptService.Server.Structure.StructureBake).
--
-- CO ROBI: analizuje JEDEN budynek i pokazuje, jak system widzi jego konstrukcję.
-- NIE zmienia gry. Zapis danych (TRYB 3) to jedyny tryb, który coś zmienia w placu
-- (atrybut SID na partach + ServerStorage.StructureData.<Budynek>) — po nim Cmd+S.
--
-- ⚠️ ZAWSZE wklejaj CAŁY plik. Command Bar nie pamięta zmiennych z poprzedniego
-- uruchomienia — sama linia `Bake.show(result)` da „attempt to index nil”.
-- Schowanie kolorów jedną linią: workspace.StructureDebug:Destroy()
--
-- KOLORY (TRYB 2):
--   zielony   — chunk stoi (ma drogę do podpory); trzy odcienie na zmianę = granice chunków
--   żółty     — chunk stały (Locked albo atrybut StructPermanent = true)
--   czerwony  — NIETKNIĘTY chunk nie ma drogi do podpory → system uznałby, że spada.
--               Naprawa: popraw styk w mapie, ustaw atrybut StructKind (np. "Column")
--               albo świadomie StructPermanent = true
--   jasnoniebieski — listwa/ozdoba (ramy okien, drabina, klocki) doczepiona do chunka:
--               nie jest nośna, spadnie razem z tym, czego dotyka
--   fioletowy — listwa/ozdoba, która niczego nie dotyka (nie wiadomo, z czym ma spaść)

local BUILDING = "OrangeBuilding"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- W Play Command Bar działa po stronie klienta, a klient nie widzi ServerScriptService
-- (zgłoszenie 2026-09-24: „Server is not a valid member of ServerScriptService”).
assert(not game:GetService("RunService"):IsRunning(), "StructureBake: zatrzymaj Play i uruchom w trybie EDIT")
assert(ServerScriptService:FindFirstChild("Server"), "StructureBake: brak ServerScriptService.Server — czy `rojo serve` jest połączony?")

-- :Clone(), bo `require` w Studio trzyma STARĄ wersję modułu między uruchomieniami
-- (hard rule 14) — klon zawsze ładuje to, co jest teraz w skrypcie. Klonujemy CAŁY folder
-- Structure: StructureBake sięga po StructureCore przez `script.Parent`.
local Config = require(ReplicatedStorage.Shared.Modules.Config:Clone())
local Structure = ServerScriptService.Server.Structure:Clone()
local Bake = require(Structure.StructureBake)

local building = workspace.Map.Map.Map.Buildings:FindFirstChild(BUILDING)
assert(building, "nie ma budynku " .. BUILDING)

local result = Bake.analyze(building, Config)
Bake.stress(result, Config) -- najbardziej nośne elementy + szacunek „ile bomb” (kilka sekund)
print(Bake.report(result))

-- ===== TRYB 1: raport (wyżej) — zawsze =====

-- ===== TRYB 2: pokaż kolory =====
Bake.show(result)

-- ===== TRYB 2b: schowaj kolory =====
-- Bake.clear()

-- ===== TRYB 3: ZAPIS (dopiero przy 0 czerwonych), potem Cmd+S =====
-- Bake.write(result, Config)
