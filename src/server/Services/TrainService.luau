--!strict
-- TrainService.luau (24.11) — pociąg przejeżdżający po torach nad miastem.
--
-- Decyzje Kacpra 24.11: uderzony traci 60% HP, leci do przodu i się przewraca; na dachu można stać
-- i jechać; zburzone tory = pociąg nie przyjeżdża; wyjeżdża z czarnego tunelu i znika w drugim.
--
-- DLACZEGO NA SERWERZE NIE MA MODELU: zakotwiczony model przesuwany co klatkę replikuje się
-- skokami, a postać i tak symuluje jej klient. Każdy klient rusza własną kopią z czasu serwera
-- (TrainController, wspólny wzór w TrainPath), a serwer liczy z tego samego wzoru, kogo pociąg
-- uderzył i kto jedzie na dachu. Skład jest u wszystkich identyczny, więc dach klienta to nie
-- „coś, czego inny nie ma” (lekcja 10).
--
-- Serwer widzi pasażera jako lecącego nad torami: upadek liczy się od dachu pociągu (tak ma być),
-- a prędkość 60 stud/s pokrywa okno anty-cheata odnawiane, dopóki jedzie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local TrainPath = require(ReplicatedStorage.Shared.Modules.TrainPath)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local AntiCheatService = require(script.Parent.AntiCheatService)
local GameLoopService = require(script.Parent.GameLoopService)
local LavaService = require(script.Parent.LavaService)
local PlayerService = require(script.Parent.PlayerService)
local RagdollService = require(script.Parent.RagdollService)

local CFG = Config.Train

local TrainService = {}

type Active = { run: TrainPath.Run, departAt: number, hit: { [Player]: boolean } }
local active: Active? = nil
local rng = Random.new()
local initialized = false

local function log(msg: string)
	print("[Train] " .. msg)
end

-- Obie szyny leżą na całej długości? Promień w dół na każdej szynie, tylko w części torów —
-- gruz leżący na torze ani strop pod nim szyny nie udają.
local function trackIntact(run: TrainPath.Run): boolean
	local map = Workspace:FindFirstChild("Map")
	local rails = map and map:FindFirstChild(CFG.RailsFolder, true)
	if not rails then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { rails }
	local side = run.dir:Cross(Vector3.yAxis).Unit * CFG.RailOffset
	for s = 0, run.length, CFG.TrackStep do
		local point = run.start + run.dir * s + Vector3.new(0, 2, 0)
		if not Workspace:Raycast(point + side, Vector3.new(0, -4, 0), params)
			or not Workspace:Raycast(point - side, Vector3.new(0, -4, 0), params) then
			return false
		end
	end
	return true
end

local function strike(player: Player, hum: Humanoid, run: TrainPath.Run, lateral: number, side: Vector3)
	hum:TakeDamage(hum.MaxHealth * CFG.Damage)
	AntiCheatService.grantGrace(player)
	local sign = if math.abs(lateral) < 0.5 then (if rng:NextNumber() < 0.5 then -1 else 1) else math.sign(lateral)
	local velocity = run.dir * CFG.KnockForward + Vector3.yAxis * CFG.KnockUp + side * (sign * CFG.KnockSide)
	-- Martwym zajmuje się PlayerService.onDeath — dwa systemy na jednej postaci = „zwłoki wstają”.
	if hum.Health > 0 then
		RagdollService.knock(player, velocity, CFG.RagdollDuration)
	end
	Remotes.BombHit:FireClient(player, 1)
	log(("uderzył %s (HP %.0f)"):format(player.Name, hum.Health))
end

local function step()
	local current = active
	if not current then return end
	local now = Workspace:GetServerTimeNow()
	local run = current.run
	local head = TrainPath.headDistance(current.departAt, now - CFG.HitLag)
	if head < 0 then return end
	if TrainPath.finished(run, head) then
		active = nil
		return
	end
	local tail = head - TrainPath.trainLength()
	local side = run.dir:Cross(Vector3.yAxis).Unit
	for _, player in ipairs(PlayerService.getAliveList()) do
		local root = Utils.getRoot(player)
		local hum = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
		if not (root and hum) or hum.Health <= 0 then continue end
		local rel = root.Position - run.start
		local along = rel:Dot(run.dir)
		-- Poza wylotami pociąg jest w tunelu — tam nikogo nie uderza.
		if along < math.max(tail, 0) or along > math.min(head, run.length) then continue end
		local lateral = rel:Dot(side)
		if math.abs(lateral) > CFG.HalfWidth then continue end
		if rel.Y - CFG.FeetOffset < -2 then continue end -- pod torami
		if rel.Y >= CFG.Height - CFG.RiderMargin then
			if rel.Y < CFG.Height + 12 then
				AntiCheatService.grantGrace(player, CFG.RiderGrace)
			end
		elseif not current.hit[player] then
			-- Zapis PRZED skutkami (zasada 8b).
			current.hit[player] = true
			strike(player, hum, run, lateral, side)
		end
	end
end

-- Zwraca czas serwera wyjazdu z tunelu albo nil, gdy pociąg nie przyjedzie.
function TrainService.run(): number?
	if active then return nil end
	local reverse = rng:NextNumber() < 0.5
	local run = TrainPath.get(reverse)
	if not run then
		warn(("[Train] brak Workspace.Map.Locked.%s.West/East.Mouth — pociągu nie będzie"):format(CFG.TunnelsFolder))
		return nil
	end
	if LavaService.getSurfaceY() > run.start.Y - CFG.LavaMargin then
		log("lawa za blisko torów — nie przyjeżdża")
		return nil
	end
	if not trackIntact(run) then
		log("tory zburzone — nie przyjeżdża")
		return nil
	end
	local departAt = Workspace:GetServerTimeNow() + CFG.Warning
	active = { run = run, departAt = departAt, hit = {} }
	Remotes.TrainRun:FireAllClients(reverse, departAt)
	log(("jedzie %s"):format(if reverse then "East → West" else "West → East"))
	return departAt
end

function TrainService.init()
	if initialized then return end
	initialized = true

	RunService.Heartbeat:Connect(step)
	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState ~= GameLoopService.STATE.ROUND then
			active = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local current = active
		if current then current.hit[player] = nil end
	end)
end

return TrainService
