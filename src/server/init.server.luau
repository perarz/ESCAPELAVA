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
local LoadoutService = require(script.Services.LoadoutService)
local SettingsService = require(script.Services.SettingsService)
local CosmeticsService = require(script.Services.CosmeticsService)
local ShopService = require(script.Services.ShopService)
local DebrisService = require(script.Services.DebrisService)
local PropService = require(script.Services.PropService)
local CarService = require(script.Services.CarService)
local StructuralService = require(script.Services.StructuralService)
local CollapseService = require(script.Services.CollapseService)
local DestructionService = require(script.Services.DestructionService)
local BombService = require(script.Services.BombService)
local MapService = require(script.Services.MapService)
local PushService = require(script.Services.PushService)
local CashPickupService = require(script.Services.CashPickupService)
local BridgeService = require(script.Services.BridgeService)
local GrappleService = require(script.Services.GrappleService)
local EnergyDrinkService = require(script.Services.EnergyDrinkService)
local RpgService = require(script.Services.RpgService)
local C4Service = require(script.Services.C4Service)
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
LoadoutService.init()
SettingsService.init()
CosmeticsService.init() -- restores purchased accessories after AppearanceService finishes the base look
-- Debris → Structural → Destruction → Collapse → Bomb. DESTRUCTION_PLAN.md (v3 + „v4”).
-- Debris pierwszy (rejestr gruzu, collision group, pętla usypiania). Structural (v4) buduje
-- budynki z `Config.Structure.Buildings` przy starcie i na początku każdego lobby — przed
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
-- Auta (27.09): wybuch jak bomby i rozpad u klientów wstrzyknięte — DestructionService woła
-- CarService, BombService woła DestructionService (bezpośredni require = cykl).
CarService.inject({
	explode = BombService.explodeAt,
	shatter = DestructionService.shatterToClients,
})
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
EnergyDrinkService.init()
RpgService.init()
C4Service.init()
HeadTrackingService.init()
AntiCheatService.init()
-- FallDamage po PlayerService (czyta getAliveList) i po GameLoopService (czyta stan).
FallDamageService.init()
RewardsService.init()
LeaderstatsService.init()
DevService.init()

-- STAN STARTOWY KLIENTA (paczka 3, 18.10; przegląd 29.09 B-1/A-8). Dawniej `task.delay(1)`
-- w trzech miejscach zgadywało, że klient już słucha — wolny telefon nie słuchał, a
-- RemoteEvent nie buforuje (zasada 9), więc gracz widział „0$”, pusty pasek i „LOBBY”
-- w trakcie rundy. Teraz klient MÓWI, że ma listenery, i dopiero wtedy dostaje stan.
-- Kolejność z wczytaniem danych obojętna: przed „loaded” kasa i itemy wychodzą z
-- subskrypcji w CashService / ItemService, po — stąd.
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Config = require(ReplicatedStorage.Shared.Modules.Config)

local readyPlayers: { [Player]: boolean } = {}

local function sendInitialState(player: Player)
	GameLoopService.replicateTo(player)
	CashService.replicateTo(player)
	ItemService.replicateTo(player)
	LoadoutService.replicateTo(player)
	SettingsService.replicateTo(player)
	CosmeticsService.replicateTo(player)
end

Remotes.ClientReady.OnServerEvent:Connect(function(player: Player)
	-- Raz na sesję gracza = limit (zasada 4): kolejne wywołania nic nie kosztują.
	if readyPlayers[player] then return end
	readyPlayers[player] = true
	sendInitialState(player)
end)
Players.PlayerRemoving:Connect(function(player: Player)
	readyPlayers[player] = nil
end)

local function fallback(player: Player)
	task.delay(Config.Game.ClientReadyFallback, function()
		if player.Parent and not readyPlayers[player] then
			warn(("[Server] %s bez ClientReady po %ds — wysyłam stan startowy na ślepo")
				:format(player.Name, Config.Game.ClientReadyFallback))
			sendInitialState(player)
		end
	end)
end
Players.PlayerAdded:Connect(fallback)
for _, p in ipairs(Players:GetPlayers()) do
	fallback(p)
end

GameLoopService.start()

print("[Server] ESCAPE LAVA bootstrap done.")
