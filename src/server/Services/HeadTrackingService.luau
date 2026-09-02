--!strict
-- HeadTrackingService.luau
-- Relay aim głowy (yaw + pitch) z klienta gracza X do wszystkich innych klientów.
-- Czysto kosmetyczne (gracz widzi gdzie inny gracz "celuje wzrokiem") — żadnego
-- gameplay impactu. Mimo to walidujemy + clampujemy + rate-limitujemy bo:
--   1. Klient kłamie (zasada 7) — exploiter mógłby spamować lub wysyłać NaN/huge floats
--   2. Bandwidth — 20 graczy × 60Hz × FireAll = 24k events/s = niepotrzebny load
--
-- Flow:
--   Klient X (~10Hz): Remotes.HeadAim:FireServer(yaw, pitch)
--   Server: typecheck → rate limit (max 15Hz per gracz) → clamp do max angles
--   Server: FireClient(p, X, yaw, pitch) dla każdego p ≠ X
--   Klient Y odbiera: zapisz target yaw/pitch dla X → MovementController lerpuje + aplikuje
--   na X.Character.Neck/Waist Transform w BindToRenderStep (po animatorze).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local HeadTrackingService = {}

local CFG_HT = Config.Movement.HeadTrack
-- Rate akceptowany przez serwer = dokładnie tyle, ile klient ma wysyłać (+5% na jitter
-- zegara). Wcześniej było 1.5× "na odchyłki" — ale każdy przyjęty pakiet idzie
-- FireAllClients, więc ta zapasowa połowa to były setki wiadomości na sekundę wysyłane
-- do KAŻDEGO klienta za coś czysto kosmetycznego (20 nadawców × 15 Hz × 20 odbiorców
-- ≈ 6000 wiadomości/s na serwer).
local MAX_RATE_HZ = CFG_HT.ReplicateHz * 1.05
local MIN_INTERVAL = 1 / MAX_RATE_HZ

-- Poniżej tego progu zmiana kąta jest niewidoczna gołym okiem — gracz stojący nieruchomo
-- przestaje generować jakikolwiek ruch sieciowy zamiast pompować 10 pakietów/s w kółko.
local MIN_ANGLE_DELTA = math.rad(2)

local MAX_YAW_RAD = math.rad(CFG_HT.MaxYawDegrees)
local MAX_PITCH_RAD = math.rad(CFG_HT.MaxPitchDegrees)

local lastFireTime: { [Player]: number } = {}
local lastSentYaw: { [Player]: number } = {}
local lastSentPitch: { [Player]: number } = {}
local initialized = false

local function isValidAngle(n: any): boolean
	if type(n) ~= "number" then return false end
	if n ~= n then return false end  -- NaN
	if math.abs(n) > 100 then return false end  -- absurd value — clamp by silnie ją "naprawił", ale to red flag
	return true
end

local function handleHeadAim(player: Player, yaw: any, pitch: any)
	if not isValidAngle(yaw) or not isValidAngle(pitch) then return end

	local now = os.clock()
	local last = lastFireTime[player] or 0
	if now - last < MIN_INTERVAL then
		-- Rate limit: silent drop (klient nie spammuje legalnie, nie warto mu mówić).
		return
	end
	lastFireTime[player] = now

	-- Clamp do dozwolonych kątów (anti-cheat: klient mógłby wysłać 180° i wykręcić głowę
	-- do tyłu jak Exorcist; też zabezpiecza przed reasonable but max-angles cheese).
	local clampedYaw = math.clamp(yaw :: number, -MAX_YAW_RAD, MAX_YAW_RAD)
	local clampedPitch = math.clamp(pitch :: number, -MAX_PITCH_RAD, MAX_PITCH_RAD)

	-- Dead zone: nie rozsyłamy ruchu, którego i tak nikt nie zobaczy. Klient interpoluje
	-- do ostatniej wartości, więc pominięty pakiet niczego nie psuje.
	local prevYaw = lastSentYaw[player]
	local prevPitch = lastSentPitch[player]
	if prevYaw and prevPitch
		and math.abs(clampedYaw - prevYaw) < MIN_ANGLE_DELTA
		and math.abs(clampedPitch - prevPitch) < MIN_ANGLE_DELTA then
		return
	end
	lastSentYaw[player] = clampedYaw
	lastSentPitch[player] = clampedPitch

	-- FireAllClients zamiast pętli FireClient: 1 wywołanie zamiast N-1 (20 graczy × 10Hz
	-- = ~3800 → ~200 calli/s server-side). Sender dostaje echo własnych danych, ale klient
	-- i tak je odrzuca (guard `sourcePlayer == localPlayer` w MovementController).
	Remotes.HeadAim:FireAllClients(player, clampedYaw, clampedPitch)
end

local function onPlayerRemoving(player: Player)
	lastFireTime[player] = nil
	lastSentYaw[player] = nil
	lastSentPitch[player] = nil
end

function HeadTrackingService.init()
	if initialized then return end
	initialized = true

	Remotes.HeadAim.OnServerEvent:Connect(handleHeadAim)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return HeadTrackingService
