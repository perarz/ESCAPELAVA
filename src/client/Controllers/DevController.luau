--!strict
-- DevController.luau
-- Klawisze trybu testowego (Config.Dev). Sam w sobie NIE daje żadnych uprawnień —
-- wysyła tylko Remotes.DevCommand, a DevService po stronie serwera i tak weryfikuje
-- `Dev.isDev(player)`. Sprawdzenie po stronie klienta jest wyłącznie po to, żeby
-- zwykły gracz nie generował ruchu sieciowego, który zostanie odrzucony.
--
--   Config.Dev.SkipKey     → pomiń bieżącą fazę / stan (LOBBY → runda w kilka klików)
--   Config.Dev.EndRoundKey → natychmiast zakończ rundę (restore mapy + nagrody)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Dev = require(ReplicatedStorage.Shared.Modules.Dev)

local DevController = {}

local localPlayer = Players.LocalPlayer

local function onInput(input: InputObject, gameProcessed: boolean)
	-- gameProcessed = gracz pisze na czacie / klika w UI. Bez tego "p" w wiadomości
	-- skipowałoby fazę.
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == Config.Dev.SkipKey then
		Remotes.DevCommand:FireServer("skip")
	elseif input.KeyCode == Config.Dev.EndRoundKey then
		Remotes.DevCommand:FireServer("endRound")
	end
end

local initialized = false
function DevController.init()
	if initialized then return end
	initialized = true

	if not Dev.isDev(localPlayer) then return end

	UserInputService.InputBegan:Connect(onInput)
	print(("[Dev] klawisze aktywne: %s = skip fazy, %s = koniec rundy"):format(
		Config.Dev.SkipKey.Name,
		Config.Dev.EndRoundKey.Name
	))
end

return DevController
