--!strict
-- LadderController.luau (08.10) — niższa prędkość potrzebna do złapania drabiny.
--
-- Zgłoszenie Kacpra: „bez sprintu jestem za wolny, żeby się złapać”. Wspinanie robi silnik
-- Robloxa i przy naszym chodzie 12 (domyślnie 16) często nie łapie, a przy sprincie (20) łapie.
-- Jedyne, co tu robimy: gdy postać idzie w stronę drabiny i jest tuż przed szczeblami, dobijamy
-- jej prędkość W STRONĘ drabiny do `Config.Ladder.GrabSpeed` (= sprint). Nic więcej — obrót,
-- trzymanie, wejście na górze i animacja to zwykły silnik.
--
-- ⛔ ODRZUCONE 08.10 (nie wracać): v1 — dodatkowo obrót przodem i `ChangeState(Climbing)`
-- („puszczając W spadasz”); v2 — własny tryb drabiny z `LinearVelocity`, W/S/wiszenie/odskok
-- (Kacper: „gówno, wyjeb to”).
--
-- Postać jest w fizyce klienta (network ownership), więc prędkość ustawiamy tutaj. GrabSpeed
-- = sprint, więc anty-cheat (limit poziomy) nie widzi różnicy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Ladders = require(ReplicatedStorage.Shared.Modules.Ladders)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local GrappleController = require(script.Parent.GrappleController)
local RagdollState = require(script.Parent.RagdollState)

local CFG = Config.Ladder
local COS_INTENT = math.cos(math.rad(CFG.IntentAngle))
-- Wysokość ciała ponad środkiem HRP (głowa R15) — górna granica pasma szczebli.
local HEAD_ABOVE_HRP = 2.5
-- Szczebel musi być wyżej niż stopy o tyle — inaczej postać stojąca na dachu tuż nad
-- drabiną byłaby pchana z powrotem na krawędź.
local FEET_MARGIN = 0.3

local BOOST_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
}

local LadderController = {}

local localPlayer = Players.LocalPlayer
local initialized = false

local function step()
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp and hrp:IsA("BasePart")) or hum.Health <= 0 then return end
	if not BOOST_STATES[hum:GetState()] then return end
	if RagdollState.isRagdolled(hum) or GrappleController.isFlying() then return end

	local move = hum.MoveDirection
	local flatMove = Vector3.new(move.X, 0, move.Z)
	if flatMove.Magnitude < 0.1 then return end

	local pos = hrp.Position
	local feetY = pos.Y - hrp.Size.Y * 0.5 - hum.HipHeight
	local lava = Utils.lavaSurfaceY()
	if lava and feetY < lava then return end -- w lawie rządzi LavaSwimController

	local rung = Ladders.nearestRung(pos, feetY + FEET_MARGIN, pos.Y + HEAD_ABOVE_HRP, CFG.ReachDistance + 2)
	if not rung or rung.front > CFG.ReachDistance then return end
	local face = -rung.normal
	if flatMove.Unit:Dot(face) < COS_INTENT then return end

	-- Tylko składowa W STRONĘ drabiny, i tylko w górę do GrabSpeed — ruch w bok i pion zostają.
	local v = hrp.AssemblyLinearVelocity
	local toward = v:Dot(face)
	if toward < CFG.GrabSpeed then
		hrp.AssemblyLinearVelocity = v + face * (CFG.GrabSpeed - toward)
	end
end

function LadderController.init()
	if initialized then return end
	initialized = true
	RunService.Heartbeat:Connect(step)
end

return LadderController
