--!strict
-- DevService.luau
-- Serwerowa strona trybu testowego (Config.Dev). JEDYNE miejsce, w którym polecenia
-- dev z klienta zamieniają się w realne akcje — i jedyne, które decyduje, czy wolno.
--
-- Kontrakt: Remotes.DevCommand:FireServer(command: string), command ∈ {"skip", "endRound"}.
-- Każde wywołanie przechodzi przez `Dev.isDev(player)` — hard rule #2 (server authority)
-- obowiązuje tak samo w trybie testowym, bo ten sam kod pojedzie na produkcję z
-- `Config.Dev.Enabled = false` i NIE może dać się obejść przez podrobiony remote.
--
-- Nieskończone itemy NIE są tutaj — siedzą w ItemService (syntetyczne inventory),
-- bo tam jest single source of truth stanu ekwipunku.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Dev = require(ReplicatedStorage.Shared.Modules.Dev)
local GameLoopService = require(script.Parent.GameLoopService)

local DevService = {}

-- Rate limit: klawisz trzymany na repeat nie może zamienić rundy w slideshow stanów.
local lastCommandAt: { [Player]: number } = {}
local COMMAND_COOLDOWN = 0.35

local function onDevCommand(player: Player, command: any)
	if not Dev.isDev(player) then
		-- Cicho. Zwykły gracz nie ma się dowiedzieć, że taki remote w ogóle coś robi.
		return
	end
	if typeof(command) ~= "string" then return end

	local now = os.clock()
	if now - (lastCommandAt[player] or 0) < COMMAND_COOLDOWN then return end
	lastCommandAt[player] = now

	if command == "skip" then
		local what = GameLoopService.devSkip()
		print(("[Dev] %s → skip (%s)"):format(player.Name, what))
	elseif command == "endRound" then
		local ok = GameLoopService.devEndRound()
		print(("[Dev] %s → endRound (%s)"):format(player.Name, ok and "OK" or "nie w rundzie"))
	end
end

local function onPlayerRemoving(player: Player)
	lastCommandAt[player] = nil
end

local initialized = false
function DevService.init()
	if initialized then return end
	initialized = true

	if not Config.Dev.Enabled then
		-- Tryb wyłączony: nie podpinamy nawet listenera. Remote istnieje (Remotes tworzy
		-- wszystkie na starcie), ale nikt go nie słucha.
		return
	end

	-- Głośny warn co boot — flaga dev NIE MOŻE po cichu dojechać na produkcję.
	warn(("[Dev] TRYB TESTOWY WŁĄCZONY (Config.Dev.Enabled=true) — itemy: %s, klawisze: %s=skip, %s=koniec rundy. WYŁĄCZ PRZED LAUNCHEM!"):format(
		Config.Dev.InfiniteItems and "nieskończone" or "normalne",
		Config.Dev.SkipKey.Name,
		Config.Dev.EndRoundKey.Name
	))

	Remotes.DevCommand.OnServerEvent:Connect(onDevCommand)
	game:GetService("Players").PlayerRemoving:Connect(onPlayerRemoving)
end

return DevService
