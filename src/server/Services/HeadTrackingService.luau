--!strict
-- HeadTrackingService.luau
-- Relay aim głowy (yaw + pitch) z klienta gracza X do graczy w pobliżu X.
-- Czysto kosmetyczne (gracz widzi gdzie inny gracz "celuje wzrokiem") — żadnego
-- gameplay impactu. Mimo to walidujemy + clampujemy + rate-limitujemy bo:
--   1. Klient kłamie (zasada 7) — exploiter mógłby spamować lub wysyłać NaN/huge floats
--   2. Bandwidth — 20 graczy × 60Hz × FireAll = 24k events/s = niepotrzebny load
--
-- Flow:
--   Klient X (~10Hz): Remotes.HeadAim:FireServer(yaw, pitch)
--   Server: typecheck → rate limit (max 15Hz per gracz) → clamp do max angles
--   Server: FireClient(Y, X, yaw, pitch) tylko dla Y w zasięgu X (A-11, 02.11)
--   Klient Y odbiera: zapisz target yaw/pitch dla X → MovementController lerpuje + aplikuje
--   na X.Character.Neck/Waist C0; Transform jest nadpisywany przez Animatora.
--
-- Zasięg (`audience`) liczy pętla co `ReplicateSweepInterval`, nie każdy pakiet. Odbiorca,
-- który właśnie wszedł w zasięg (albo nadawca ma nową postać), dostaje od razu ostatnią pozę —
-- inaczej stojący nieruchomo nadawca (dead zone niżej) zostałby u niego z głową na wprost.

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

local RANGE = CFG_HT.ReplicateRange
local LEAVE_RANGE = RANGE + CFG_HT.ReplicateRangeHysteresis

local lastFireTime: { [Player]: number } = {}
local lastSentYaw: { [Player]: number } = {}
local lastSentPitch: { [Player]: number } = {}
-- audience[nadawca][odbiorca] = postać nadawcy, dla której odbiorca ma aktualną pozę.
local audience: { [Player]: { [Player]: Model } } = {}
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

	-- Pętla FireClient zamiast FireAllClients: wywołań po stronie serwera jest więcej, ale
	-- koszt to pakiet DO KAŻDEGO odbiorcy, a gracz po drugiej stronie mapy obrotu głowy
	-- i tak nie zobaczy. Nadawcy nie ma w audience — nie dostaje echa.
	local list = audience[player]
	if not list then return end
	for receiver in pairs(list) do
		Remotes.HeadAim:FireClient(receiver, player, clampedYaw, clampedPitch)
	end
end

local function rootPosition(player: Player): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function sweepAudience()
	local players = Players:GetPlayers()
	local positions: { [Player]: Vector3 } = {}
	for _, p in ipairs(players) do
		local pos = rootPosition(p)
		if pos then positions[p] = pos end
	end
	for _, sender in ipairs(players) do
		local list = audience[sender]
		if not list then
			list = {}
			audience[sender] = list
		end
		local from = positions[sender]
		local char = sender.Character
		for _, receiver in ipairs(players) do
			if receiver == sender then continue end
			local to = positions[receiver]
			local dist = if from and to then (from - to).Magnitude else math.huge
			local known = list[receiver]
			if known and dist > LEAVE_RANGE then
				list[receiver] = nil
			elseif char and dist <= (if known then LEAVE_RANGE else RANGE) and known ~= char then
				-- Nowy w zasięgu albo nadawca po respawnie: klient zaczyna nową postać od głowy
				-- na wprost, a kolejny pakiet przyjdzie dopiero po ruchu > MIN_ANGLE_DELTA.
				list[receiver] = char :: Model
				local yaw, pitch = lastSentYaw[sender], lastSentPitch[sender]
				if yaw and pitch then
					Remotes.HeadAim:FireClient(receiver, sender, yaw, pitch)
				end
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	lastFireTime[player] = nil
	lastSentYaw[player] = nil
	lastSentPitch[player] = nil
	audience[player] = nil
	for _, list in pairs(audience) do
		list[player] = nil
	end
end

function HeadTrackingService.init()
	if initialized then return end
	initialized = true

	Remotes.HeadAim.OnServerEvent:Connect(handleHeadAim)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	task.spawn(function()
		while true do
			task.wait(CFG_HT.ReplicateSweepInterval)
			-- Błąd jednego przebiegu nie może na zawsze wyłączyć ruchu głów.
			local ok, err = pcall(sweepAudience)
			if not ok then
				warn("[HeadTracking] sweep: " .. tostring(err))
			end
		end
	end)
end

return HeadTrackingService
