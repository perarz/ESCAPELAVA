--!strict
-- Dev.luau
-- Single source of truth: KTO ma uprawnienia dev. Shared, bo pytają o to obie strony —
-- serwer (walidacja każdej dev-akcji) i klient (czy w ogóle podpinać keybindy).
--
-- ZASADA BEZPIECZEŃSTWA: klient NIGDY nie decyduje o uprawnieniach. To że
-- DevController podpina klawisze u kogoś, nie daje mu nic — DevService i tak
-- sprawdza `Dev.isDev(player)` po swojej stronie przy każdym poleceniu.
-- Klientowa kopia sprawdzenia jest wyłącznie po to, żeby zwykły gracz nie wysyłał
-- ruchu sieciowego, który i tak zostanie odrzucony.
--
-- Wyłączenie całego trybu: Config.Dev.Enabled = false (jedna flaga, patrz Config).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local Dev = {}

-- Nicki z Configu w lowercase — porównanie case-insensitive, żeby literówka
-- w wielkości liter nie kosztowała sesji debugowania "czemu nie mam bomb".
local allowList: { [string]: boolean } = {}
for _, name in ipairs(Config.Dev.Usernames) do
	allowList[string.lower(name)] = true
end

function Dev.isEnabled(): boolean
	return Config.Dev.Enabled
end

function Dev.isDev(player: Player?): boolean
	if not Config.Dev.Enabled then return false end
	if not player then return false end
	if Config.Dev.AllowInStudio and RunService:IsStudio() then return true end
	return allowList[string.lower(player.Name)] == true
end

-- Czy dev tego gracza ma mieć nieskończone itemy (osobna gałka od samego bycia devem).
function Dev.hasInfiniteItems(player: Player?): boolean
	return Config.Dev.InfiniteItems and Dev.isDev(player)
end

return Dev
