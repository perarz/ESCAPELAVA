-- ESCAPE LAVA — testy solvera i plannera (destrukcja v4, fazy B/C). DESTRUCTION_PLAN.md → „v4”.
-- Wklej CAŁY plik w Command Bar w Studio (EDIT mode, nie Play). Wymaga `rojo serve`.
--
-- CO ROBI: liczy na danych OrangeBuilding scenariusze z debaty — nietknięty budynek, dziura
-- w stropie, kilka dziur, osłabianie słupa dwiema bombami, jeden słup przecięty, bomby
-- w parter aż do upadku wieży, dwie bomby w jednej klatce, bomba w spadającą grupę.
-- Mapa się NIE zmienia i nic naprawdę nie spada — to obliczenia, wynik w Output.
-- Na koniec pokazuje kolorami stan po bombach w parter (S6):
--   blada zieleń — stoi | pomarańcz — osłabiony (rysy) | czerwień — zniszczony
--   inne kolory — spadający, każda GRUPA (przyszła bryła fizyki) w innym kolorze
-- Schowanie kolorów: workspace.StructureDebug:Destroy()

local BUILDING = "OrangeBuilding"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

assert(not game:GetService("RunService"):IsRunning(), "StructureTests: zatrzymaj Play i uruchom w trybie EDIT")
assert(ServerScriptService:FindFirstChild("Server"), "StructureTests: brak ServerScriptService.Server — czy `rojo serve` jest połączony?")

-- Klony: `require` w Studio trzyma STARĄ wersję modułu między uruchomieniami (hard rule 14).
-- Cały folder zachowuje script.Parent.Utils i daje świeże definicje bomby
-- przy każdym uruchomieniu; stary cache nie może zafałszować wyniku.
local Modules = ReplicatedStorage.Shared.Modules:Clone()
local Config = require(Modules.Config)
local Fracture = require(Modules.Fracture)
local ItemDefinitions = require(Modules.ItemDefinitions)
local Structure = ServerScriptService.Server.Structure:Clone()
local Tests = require(Structure.StructureTests)

local building = workspace.Map.Map.Map.Buildings:FindFirstChild(BUILDING)
assert(building, "nie ma budynku " .. BUILDING)

local report, state, plan = Tests.runOrange(building, Config, Fracture, ItemDefinitions.bomb.destruction)
print(report)
Tests.show(state, plan)
Structure:Destroy()
Modules:Destroy()
