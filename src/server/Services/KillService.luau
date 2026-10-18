--!strict
-- KillService.luau
-- Tagowanie "kto ostatnio zaatakował danego humanoida" + credit kill$ gdy umrze.
-- Attackery są zapisywane jako attributes na Humanoid — jeśli victim umiera w oknie
-- Config.Rewards.KillCreditWindowSec sekund, attacker dostaje Config.Rewards.Kill $.
--
-- Public API:
--   KillService.tag(hum, attacker, weapon: "bomb"/"push")
--     — bomba wywołuje przy trafieniu, push wywołuje przy pchnięciu (nawet miss lawy)
--   KillService.processDeath(victim, hum)
--     — wywoływane przez PlayerService.onDeath, czyta attributes i creduje

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local CashService = require(script.Parent.CashService)

local KillService = {}

-- Przedłuża WAŻNY tag, nie tworzy nowego. Po to, żeby śmierć rozciągnięta w czasie
-- (lawa: ~7 s zamiast natychmiast) nie gubiła kredytu za zabójstwo — okno liczenia ma
-- 5 s, więc bez odnawiania „zepchnąłem go do lawy" przestałoby się liczyć.
-- ⚠️ Odnawia TYLKO tag, który jest jeszcze ważny. Wygasły zostaje wygasły — inaczej
-- push sprzed minuty wracałby do gry, gdy ofiara przypadkiem wpadnie do lawy.
function KillService.refreshTag(hum: Humanoid): boolean
	if not hum or hum.Health <= 0 then return false end
	local tagTime = hum:GetAttribute("KillTagTime")
	if type(tagTime) ~= "number" then return false end
	if os.clock() - tagTime > Config.Rewards.KillCreditWindowSec then return false end
	hum:SetAttribute("KillTagTime", os.clock())
	return true
end

function KillService.tag(hum: Humanoid, attacker: Player, weapon: string)
	if not hum or hum.Health <= 0 then return end
	if not attacker or not attacker.Parent then return end
	hum:SetAttribute("KillAttackerId", attacker.UserId)
	hum:SetAttribute("KillWeapon", weapon)
	hum:SetAttribute("KillTagTime", os.clock())
end

function KillService.processDeath(victim: Player, hum: Humanoid)
	local attackerId = hum:GetAttribute("KillAttackerId")
	local tagTime = hum:GetAttribute("KillTagTime")
	if type(attackerId) ~= "number" or type(tagTime) ~= "number" then return end
	if os.clock() - tagTime > Config.Rewards.KillCreditWindowSec then return end

	local attacker = Players:GetPlayerByUserId(attackerId)
	if not attacker or attacker == victim then return end

	local weapon = hum:GetAttribute("KillWeapon")
	local weaponStr = type(weapon) == "string" and weapon or "unknown"
	local reward = Config.Rewards.Kill

	CashService.add(attacker, reward, "kill_" .. weaponStr)
	-- Tylko do zabójcy: komunikat „YOU KILLED” widzi on sam (killfeed dla wszystkich usunięty 10.10).
	Remotes.PlayerKilled:FireClient(attacker, attacker, victim, weaponStr, reward)
end

return KillService
