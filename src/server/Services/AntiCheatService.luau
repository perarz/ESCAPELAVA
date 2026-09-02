--!strict
-- AntiCheatService.luau
-- Server-side detekcja speedhacka/teleportu dla żywych graczy w ROUND.
--
-- DLACZEGO NIE Humanoid.WalkSpeed (poprzednia wersja):
--   Zmierzone w Studio 2026-08-11 — klient ustawił sobie WalkSpeed = 100, serwer w tej
--   samej chwili czytał 16. Właściwości Humanoida ustawione lokalnie NIE replikują się
--   na serwer, więc cap na WalkSpeed nie wykrywał absolutnie niczego. Jedyne, czego
--   klient nie może sfałszować, to gdzie jego postać faktycznie JEST — bo tę pozycję
--   serwer widzi przez replikację fizyki. Dlatego mierzymy przebytą drogę.
--
-- Model:
--   * Co CheckIntervalSec próbkujemy pozycję poziomą (Y ignorujemy — spadanie i skoki
--     to nie jest prędkość biegu, a lawa i tak załatwia spadających).
--   * Prędkość > SprintSpeed + SpeedTolerance = jeden "strike". Strikes pod rząd = kara.
--     Pojedynczy przekroczony pomiar to prawie zawsze fizyka (gruz, zbieg ze skarpy),
--     a nie cheat — cheater przekracza limit w każdej próbce.
--   * Impulsy nadane PRZEZ SERWER (knockback bomby, push) dają okno bezkarności —
--     inaczej gracz zdmuchnięty własną bombą leciałby 450 stud/s i został ukarany.
--   * Teleporty własne (start rundy, powrót do lobby, respawn) kasują próbkę, bo skok
--     pozycji to nie ruch gracza.
--
-- Kara: kill zamiast kick — mniej inwazyjne przy ewentualnym false positive i nie generuje
-- fali rozłączeń, a i tak wyrzuca cheatera z rundy.
--
-- Public API:
--   AntiCheatService.grantGrace(player, seconds) — woła każdy serwis nadający impuls

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local GameLoopService = require(script.Parent.GameLoopService)
local PlayerService = require(script.Parent.PlayerService)

local AntiCheatService = {}

type Sample = {
	position: Vector3,
	at: number,
	strikes: number,
}

local samples: { [Player]: Sample } = {}
local graceUntil: { [Player]: number } = {}
local accumulator = 0
local initialized = false

local function maxAllowedSpeed(): number
	return Config.Movement.SprintSpeed + Config.AntiCheat.SpeedTolerance
end

-- Okno bezkarności. Woła BombService (knockback) i PushService — wszystko, co serwer
-- sam robi z prędkością gracza. Wydłuża istniejące okno, nigdy go nie skraca.
function AntiCheatService.grantGrace(player: Player, seconds: number?)
	local duration = seconds or Config.AntiCheat.GraceAfterImpulseSec
	local until_ = os.clock() + duration
	if until_ > (graceUntil[player] or 0) then
		graceUntil[player] = until_
	end
end

local function clearSample(player: Player)
	samples[player] = nil
end

local function punish(player: Player, speed: number)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	warn(("[AntiCheat] %s — %.1f stud/s (limit %.1f) przez %d próbki z rzędu, killing"):format(
		player.Name, speed, maxAllowedSpeed(), Config.AntiCheat.Strikes))
	if hum then
		hum:TakeDamage(hum.MaxHealth)
	end
	clearSample(player)
end

local function checkPlayer(player: Player, now: number)
	if not PlayerService.isAlive(player) then
		clearSample(player)
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		clearSample(player)
		return
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		clearSample(player)
		return
	end

	local previous = samples[player]
	if not previous then
		samples[player] = { position = hrp.Position, at = now, strikes = 0 }
		return
	end

	local dt = now - previous.at
	if dt < 0.5 then return end

	-- W oknie bezkarności tylko odświeżamy próbkę — gracz leci po serwerowym impulsie.
	if now < (graceUntil[player] or 0) then
		previous.position = hrp.Position
		previous.at = now
		previous.strikes = 0
		return
	end

	local from = previous.position
	local to = hrp.Position
	local horizontal = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	local speed = horizontal / dt

	if speed > maxAllowedSpeed() then
		previous.strikes += 1
		if previous.strikes >= Config.AntiCheat.Strikes then
			punish(player, speed)
			return
		end
	else
		previous.strikes = 0
	end

	previous.position = to
	previous.at = now
end

local function tick()
	if GameLoopService.getState() ~= GameLoopService.STATE.ROUND then return end
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		checkPlayer(p, now)
	end
end

local function onPlayerAdded(player: Player)
	-- Respawn/teleport = skok pozycji, nie ruch. Bez kasowania próbki start rundy
	-- (PivotTo na drugi koniec mapy) wyglądałby jak teleport-hack.
	player.CharacterAdded:Connect(function()
		clearSample(player)
	end)
end

local function onPlayerRemoving(player: Player)
	samples[player] = nil
	graceUntil[player] = nil
end

function AntiCheatService.init()
	if initialized then return end
	initialized = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerAdded(p)
	end

	-- Każda zmiana stanu gry przenosi graczy (round spawn, powrót do lobby) — kasujemy
	-- wszystkie próbki, żeby teleport serwera nie policzył się jako ruch gracza.
	GameLoopService.StateChanged:Connect(function()
		table.clear(samples)
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator >= Config.AntiCheat.CheckIntervalSec then
			accumulator = 0
			tick()
		end
	end)
end

return AntiCheatService
