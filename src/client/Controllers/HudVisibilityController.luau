--!strict
-- HudVisibilityController.luau
-- Chowa przyciski Shop + Daily Rewards gdy gracz AKTYWNIE GRA (state=ROUND i żyje).
-- Martwy spectator / gracz w lobby widzi sklep normalnie (server pozwala spectatorom
-- kupować — ShopService alive check przepuszcza nie-alive w ROUND).
--
-- Visibility rule: hidden = (state == ROUND) and isAlive.
-- isAlive przychodzi z serwera (Remotes.AliveChanged — single source: PlayerService.aliveSet).
-- Fresh join mid-round: klient defaultuje isAlive=false → sklep widoczny (spectator). Server
-- fire'uje AliveChanged(true) tylko przy round spawn, więc default jest zawsze poprawny.
--
-- Przy hide force-zamykamy też ShopMenu (gracz mógł zostawić otwarte w COUNTDOWN).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local HudVisibilityController = {}

-- Nazwy nodes w HUD które chowamy/pokazujemy. Brak node'a = warn raz, reszta działa.
local TOGGLED_NAMES = {
	"ShopButton",
	"ShopbuttonBG",
	"DailyRewardsButton",
	"DailyRewardsButtonBG",
}

local localPlayer = Players.LocalPlayer

local isRound = false
local isAlive = false
local refs: { GuiObject } = {}
local menusToClose: { GuiObject } = {}
local refsReady = false
local warnedMissing: { [string]: boolean } = {}

local function apply()
	if not refsReady then return end
	local hidden = isRound and isAlive
	for _, node in ipairs(refs) do
		node.Visible = not hidden
	end
	if hidden then
		-- Zamknij menu jeśli gracz zostawił otwarte przed startem rundy.
		for _, m in ipairs(menusToClose) do
			m.Visible = false
		end
	end
end

local function findRefs()
	-- Yield-safe; task.spawn z init(). Listenery już podpięte — stan aplikuje się po znalezieniu.
	local pgui = localPlayer:WaitForChild("PlayerGui")
	local hud = pgui:WaitForChild("HUD", 10)
	if not hud then
		warn("[HudVisibility] PlayerGui.HUD nie istnieje — hide sklepu w rundzie nieaktywny")
		return
	end

	for _, name in ipairs(TOGGLED_NAMES) do
		local node = hud:FindFirstChild(name, true)
		if node and node:IsA("GuiObject") then
			table.insert(refs, node)
		elseif not warnedMissing[name] then
			warnedMissing[name] = true
			warn(("[HudVisibility] HUD.%s nie istnieje — pomijam"):format(name))
		end
	end

	for _, menuName in ipairs({ "ShopMenu", "DailyRewardsMenu" }) do
		local menu = hud:FindFirstChild(menuName, true)
		if menu and menu:IsA("GuiObject") then
			table.insert(menusToClose, menu)
		end
	end

	refsReady = true
	apply()
end

function HudVisibilityController.init()
	-- Listenery PRZED WaitForChild (zasada 9 — RemoteEvent nie buforuje).
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
		isRound = newState == "ROUND"
		if not isRound then
			-- Poza rundą alive status jest nieistotny; reset eliminuje stale-true
			-- (survivor po POST_ROUND nie dostaje osobnego AliveChanged(false)).
			isAlive = false
		end
		apply()
	end)

	Remotes.AliveChanged.OnClientEvent:Connect(function(alive: boolean)
		if type(alive) ~= "boolean" then return end
		isAlive = alive
		apply()
	end)

	task.spawn(findRefs)
end

return HudVisibilityController
