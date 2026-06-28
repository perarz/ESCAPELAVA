--!strict
-- Server bootstrap. Kolejność zależności:
--   Remotes (folder) → PlaceholderMap (geometria) → LavaService (Lava part)
--   → PlayerService (slot na getAliveCountProvider) → GameLoopService.start()
-- Brak _G. Komunikacja przez require + BindableEvents w GameLoopService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Force-init Remotes folder na serwerze (tworzy RemoteEventy).
require(ReplicatedStorage.Shared.Modules.Remotes)

local PlayerDataService = require(script.Services.PlayerDataService)
local LavaService = require(script.Services.LavaService)
local PlayerService = require(script.Services.PlayerService)
local GameLoopService = require(script.Services.GameLoopService)
local CashService = require(script.Services.CashService)
local ItemService = require(script.Services.ItemService)
local ShopService = require(script.Services.ShopService)
local BombService = require(script.Services.BombService)
local MapService = require(script.Services.MapService)
local PushService = require(script.Services.PushService)
local CashPickupService = require(script.Services.CashPickupService)
local BridgeService = require(script.Services.BridgeService)
-- Ragdoll: toolbox ARTFVL ragdoll (folder w Workspace.Ragdoll Script... → StarterGui → PlayerGui)

-- KOLEJNOŚĆ MA ZNACZENIE:
--   PlayerDataService najpierw — Cash/Item zarejestrują się jako subscribers PRZED
--   pierwszym PlayerAdded, żeby nie zgubić eventu "loaded".
--   BombService po ItemService — rejestruje się jako use handler.
--   MapService snapshot PRZED pierwszą rundą (bomby nie zdążą zmodyfikować mapy
--   zanim zrobimy clone) — w praktyce wszystko init przed GameLoopService.start().
--   CashPickupService po LavaService — attachLavaListener czeka na LavaPart.
PlayerDataService.init()
CashService.init()
ItemService.init()
BombService.init()
LavaService.init()
PlayerService.init()
ShopService.init()
MapService.init()
PushService.init()
CashPickupService.init()
BridgeService.init()

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
