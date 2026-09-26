--!strict
-- Server bootstrap. Kolejność zależności:
--   Remotes (folder) → LavaService (Lava part) → PlayerService (getAliveCountProvider)
--   → GameLoopService.start()
-- Brak _G. Komunikacja przez require + BindableEvents w GameLoopService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Force-init Remotes folder na serwerze (tworzy RemoteEventy).
require(ReplicatedStorage.Shared.Modules.Remotes)

local PlayerDataService = require(script.Services.PlayerDataService)
local LavaService = require(script.Services.LavaService)
local AppearanceService = require(script.Services.AppearanceService)
local PlayerService = require(script.Services.PlayerService)
local GameLoopService = require(script.Services.GameLoopService)
local CashService = require(script.Services.CashService)
local ItemService = require(script.Services.ItemService)
local ShopService = require(script.Services.ShopService)
local SettingsService = require(script.Services.SettingsService)
local DebrisService = require(script.Services.DebrisService)
local PropService = require(script.Services.PropService)
local StructuralService = require(script.Services.StructuralService)
local CollapseService = require(script.Services.CollapseService)
local DestructionService = require(script.Services.DestructionService)
local BombService = require(script.Services.BombService)
local MapService = require(script.Services.MapService)
local PushService = require(script.Services.PushService)
local CashPickupService = require(script.Services.CashPickupService)
local BridgeService = require(script.Services.BridgeService)
local GrappleService = require(script.Services.GrappleService)
local HeadTrackingService = require(script.Services.HeadTrackingService)
local AntiCheatService = require(script.Services.AntiCheatService)
local RagdollService = require(script.Services.RagdollService)
local FallDamageService = require(script.Services.FallDamageService)
local RewardsService = require(script.Services.RewardsService)
local LeaderstatsService = require(script.Services.LeaderstatsService)
local DevService = require(script.Services.DevService)
-- Ragdoll: toolbox ARTFVL ragdoll (folder w Workspace.Ragdoll Script... → StarterGui → PlayerGui)

-- KOLEJNOŚĆ MA ZNACZENIE:
--   PlayerDataService najpierw — Cash/Item zarejestrują się jako subscribers PRZED
--   pierwszym PlayerAdded, żeby nie zgubić eventu "loaded".
--   MapService snapshot PRZED pierwszą rundą (bomby nie zdążą zmodyfikować mapy
--   zanim zrobimy clone) — w praktyce wszystko init przed GameLoopService.start().
--   CashPickupService po LavaService — czyta wysokość lawy przez LavaService.getSurfaceY()
--   (magnet tick kasuje cash zalany lawą), więc part musi już istnieć.
PlayerDataService.init()
CashService.init()
ItemService.init()
-- Subskrybent "loaded" jak Cash/Item — musi być przed pierwszym PlayerAdded, inaczej
-- zapisany tryb grafiki gracza nie dojedzie do klienta (atrybut ustawiany po wczytaniu).
SettingsService.init()
-- Debris → Structural → Destruction → Collapse → Bomb. DESTRUCTION_PLAN.md (v3 + „v4”).
-- Debris pierwszy (rejestr gruzu, collision group, pętla usypiania). Structural (v4) buduje
-- budynki z `Config.Structure.Buildings` przy starcie i na każdym COUNTDOWN — przed
-- Destruction, która pyta go, czy part należy do budynku v4. Collapse (wykonawca v4)
-- dostaje od Destruction przekazanie klientom wstrzyknięte, bo Destruction woła Collapse
-- (bezpośredni require w obie strony = cykl). Wszystko przed BombService.
DebrisService.init()
PropService.init()
StructuralService.init()
DestructionService.init()
CollapseService.init({
	handOff = DestructionService.handOffToClients,
	dropResting = DestructionService.dropResting,
})
BombService.init()
LavaService.init()
-- PRZED PlayerService: ten spawnuje graczy, a spawn idzie już przez AppearanceService.
AppearanceService.init()
-- ⚠️ TEŻ PRZED PlayerService, i to jest WARUNEK DZIAŁANIA WYWROTKI, nie porządki.
-- `RagdollService.init` przenosi folder `ragdoll` do `StarterGui`, a Roblox kopiuje
-- StarterGui do PlayerGui w momencie SPAWNU. Kto zaspawnuje wcześniej, nie dostanie
-- folderu nigdy — i dokładnie to trafiało hosta (wchodzi pierwszy), dając objaw
-- „ragdoll działa tylko na kolegę". Przy okazji licznik generacji istnieje, zanim
-- Bomb/FallDamage zaczną zlecać wywrotki.
RagdollService.init()
PlayerService.init()
ShopService.init()
MapService.init()
PushService.init()
CashPickupService.init()
BridgeService.init()
GrappleService.init()
HeadTrackingService.init()
AntiCheatService.init()
-- FallDamage po PlayerService (czyta getAliveList) i po GameLoopService (czyta stan).
FallDamageService.init()
RewardsService.init()
LeaderstatsService.init()
DevService.init()

-- Replikuj aktualny state do nowych graczy żeby HUD nie utknął na default tekście
-- (klient yielduje na WaitForChild HUD i może minąć pierwszy setState).
local function replicate(player: Player)
	-- Trochę poczekać żeby klient miał czas na podpięcie OnClientEvent.
	task.delay(1, function()
		if player.Parent then
			GameLoopService.replicateTo(player)
		end
	end)
end
Players.PlayerAdded:Connect(replicate)
for _, p in ipairs(Players:GetPlayers()) do
	replicate(p)
end

GameLoopService.start()

print("[Server] ESCAPE LAVA bootstrap done.")
