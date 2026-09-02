--!strict
-- CashController.luau
-- Klient-side animacja cash w grze:
--   1. Idle hover + spin — gdy cash leży na mapie, lekko unosi się i obraca.
--      Klient renderuje LOKALNIE (server-side cash jest anchored na fixed Position;
--      magnet detection liczy się z tej fixed pozycji, klient wizualizuje "bujanie"
--      na własną rękę). Deterministyczny seed z position XYZ → wszyscy klienci widzą
--      identyczny hover dla każdego cash (brak desync między oczami).
--
--   2. Pickup po łuku — gdy server fires Remotes.CashCollected, klient spawnuje
--      lokalną kopię "ghost" cash i animuje ją po krzywej Beziera kwadratowej:
--      P(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
--      P0 = startPos (server-side cash position), P2 = player HRP, P1 = midpoint
--      podniesiony o Lift. EaseOut Back na alpha → smooth elastic feel.
--      Plus spin podczas lotu (PickupSpinTurns × 2π).
--
-- Performance: tracking jednorazowy per cash (ChildAdded → tabela state), Heartbeat
-- jedna pętla po N cash. 10 cash × 60Hz × kilka operacji CFrame = pomijalne.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CashController = {}

local TEMPLATE_NAME = "Cash"
local ACTIVE_FOLDER_NAME = "ActiveCash"

local function getTemplate(): Instance?
	return ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
end

local function makeDefaultVisual(): BasePart
	local part = Instance.new("Part")
	part.Name = "CashGhost"
	part.Size = Config.Cash.DefaultSize
	part.Color = Config.Cash.DefaultColor
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

-- =========================================================================
-- IDLE HOVER + SPIN
-- =========================================================================

type CashTrack = {
	instance: Instance,
	root: BasePart,
	baseCF: CFrame,         -- "kotwica" — pozycja jaką nadał server
	seed: number,            -- faza hoveru (różna per cash → nie pulsują w unison)
	isModel: boolean,
}

local trackedCash: { [Instance]: CashTrack } = {}

local function stableSeed(pos: Vector3): number
	-- Deterministyczne hash-owanie pozycji do fazy hoveru. Brak math.random — wszyscy
	-- klienci dostają identyczną wartość dla tego samego cash.
	return (pos.X * 0.13714 + pos.Y * 0.29321 + pos.Z * 0.46193) % (math.pi * 2)
end

local function resolveRoot(instance: Instance): BasePart?
	if instance:IsA("BasePart") then return instance end
	if instance:IsA("Model") then
		local primary = instance.PrimaryPart
		if primary then return primary end
		-- Brak PrimaryPart → szukamy nazwy "CashRoot" (server-side prepareCashInstance
		-- ustawia ją). Fallback: pierwszy BasePart.
		local rootByName = instance:FindFirstChild("CashRoot")
		if rootByName and rootByName:IsA("BasePart") then
			instance.PrimaryPart = rootByName
			return rootByName
		end
		for _, d in ipairs(instance:GetDescendants()) do
			if d:IsA("BasePart") then
				instance.PrimaryPart = d
				return d
			end
		end
	end
	return nil
end

local function trackCash(instance: Instance)
	if trackedCash[instance] then return end
	local root = resolveRoot(instance)
	if not root then return end

	local baseCF: CFrame
	if instance:IsA("Model") then
		baseCF = instance:GetPivot()
	else
		baseCF = root.CFrame
	end

	trackedCash[instance] = {
		instance = instance,
		root = root,
		baseCF = baseCF,
		seed = stableSeed(baseCF.Position),
		isModel = instance:IsA("Model"),
	}
end

local function untrackCash(instance: Instance)
	trackedCash[instance] = nil
end

local function startIdleAnimation()
	-- Subskrybuj ChildAdded/Removed na ActiveCash żeby od razu łapać nowe cash bez polling.
	local folder = Workspace:WaitForChild(ACTIVE_FOLDER_NAME, 30)
	if not folder then
		warn("[Cash] Workspace.ActiveCash nie pojawił się — idle animacja nieaktywna")
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		trackCash(child)
	end
	folder.ChildAdded:Connect(trackCash)
	folder.ChildRemoved:Connect(untrackCash)

	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local twoPiHz = math.pi * 2 * Config.Cash.HoverFrequency
		local spinSpeed = Config.Cash.SpinSpeed
		local amp = Config.Cash.HoverAmplitude

		for instance, track in pairs(trackedCash) do
			if not instance.Parent then
				trackedCash[instance] = nil
				continue
			end
			-- Hover: sin( (t + seed) * 2πf ) * amplitude
			local hoverY = math.sin(t * twoPiHz + track.seed) * amp
			-- Spin: ciągły obrót wokół Y, też z seed offsetem żeby nie były w fazie.
			local spin = t * spinSpeed + track.seed
			local newCF = track.baseCF
				* CFrame.new(0, hoverY, 0)
				* CFrame.Angles(0, spin, 0)
			if track.isModel then
				(instance :: Model):PivotTo(newCF)
			else
				track.root.CFrame = newCF
			end
		end
	end)
end

-- =========================================================================
-- PICKUP — łuk z Beziera
-- =========================================================================

local function bezierQuad(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local u = 1 - t
	return (u * u) * p0 + (2 * u * t) * p1 + (t * t) * p2
end

local function easedAlpha(rawT: number): number
	-- TweenService GetValue: identyczna interpolacja jak normalne TweenInfo.
	-- Sine.InOut: gentle acceleration + gentle deceleration, brak overshootu — najbardziej
	-- smooth feel. Cash "płynnie" leci po łuku zamiast wskakiwać sztywno na końcu.
	return TweenService:GetValue(math.clamp(rawT, 0, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

local function makeGhost(): (Instance?, BasePart?)
	local template = getTemplate()
	local instance: Instance = template and template:Clone() or makeDefaultVisual()

	local parts: { BasePart } = {}
	if instance:IsA("Model") then
		for _, d in ipairs(instance:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
	elseif instance:IsA("BasePart") then
		table.insert(parts, instance :: BasePart)
	end
	for _, p in ipairs(parts) do
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end

	local root = resolveRoot(instance)
	if not root then
		instance:Destroy()
		return nil, nil
	end
	return instance, root
end

local function computeArcLift(distance: number): number
	local frac = distance * Config.Cash.PickupArcLiftFraction
	return math.clamp(frac, Config.Cash.PickupArcMinLift, Config.Cash.PickupArcMaxLift)
end

local function attachPickupTrail(root: BasePart)
	-- Złota wstęga za cashem w locie. Trail ciągnie się między dwoma attachmentami
	-- (pionowy odstęp = szerokość wstęgi) i wygasa sam — ginie razem z ghostem.
	local cfg = Config.Cash.PickupTrail
	if not cfg.Enabled then return end

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, cfg.AttachmentSpread, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -cfg.AttachmentSpread, 0)
	a1.Parent = root

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(cfg.ColorStart, cfg.ColorEnd)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.StartTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0) -- wstęga zwęża się ku ogonowi
	trail.Lifetime = cfg.Lifetime
	trail.FaceCamera = true
	trail.LightEmission = cfg.LightEmission
	trail.Parent = root
end

local function animatePickup(targetPlayer: Player, fromPos: Vector3)
	local char = targetPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end

	local ghostInstance, ghostRoot = makeGhost()
	if not ghostInstance or not ghostRoot then return end

	attachPickupTrail(ghostRoot)
	ghostInstance.Parent = Workspace

	-- Server podaje `fromPos` = pozycja anchored cash (baza, bez hover offsetu). Klient
	-- widział cash w base + hoverY. Żeby ghost nie "teleportował" o ±HoverAmplitude na
	-- start animacji, replikujemy ten sam offset hover lokalnie. Wszystkie klienty są
	-- ~zsynchronizowane na os.clock() (mała różnica nieistotna wizualnie).
	local twoPiHz = math.pi * 2 * Config.Cash.HoverFrequency
	local seed = stableSeed(fromPos)
	local startHover = math.sin(os.clock() * twoPiHz + seed) * Config.Cash.HoverAmplitude
	local startPos = fromPos + Vector3.new(0, startHover, 0)
	local targetPos = hrp.Position
	-- Midpoint Beziera: środek + lift. Lift skaluje z dystansem (krótkie pickup = mały
	-- garbiczek, długi = wysoki łuk), ale capowane żeby nie strzelać w kosmos.
	local distance = (targetPos - startPos).Magnitude
	local lift = computeArcLift(distance)
	local mid = (startPos + targetPos) * 0.5 + Vector3.new(0, lift, 0)

	local duration = Config.Cash.MagnetSpeed
	local spinTotal = math.pi * 2 * Config.Cash.PickupSpinTurns
	local isModel = ghostInstance:IsA("Model")

	local t0 = os.clock()
	local conn: RBXScriptConnection?

	conn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - t0
		local rawAlpha = math.min(elapsed / duration, 1)
		local alpha = easedAlpha(rawAlpha)

		-- HRP może się ruszać (gracz dalej biegnie) — re-target na bieżącą pozycję.
		-- Aktualizujemy też mid żeby łuk dalej "celował" tam gdzie gracz jest teraz.
		local currentTarget = (hrp.Parent and hrp:IsA("BasePart")) and hrp.Position or targetPos
		local currentMid = (startPos + currentTarget) * 0.5 + Vector3.new(0, lift, 0)

		local pos = bezierQuad(startPos, currentMid, currentTarget, alpha)
		-- Spin liniowy względem rawAlpha (nie eased) — wygląda naturalniej.
		local spin = spinTotal * rawAlpha
		local cf = CFrame.new(pos) * CFrame.Angles(0, spin, math.sin(rawAlpha * math.pi) * 0.3)

		if isModel then
			(ghostInstance :: Model):PivotTo(cf)
		else
			ghostRoot.CFrame = cf
		end

		if rawAlpha >= 1 then
			if conn then conn:Disconnect() end
			ghostInstance:Destroy()
		end
	end)

	Debris:AddItem(ghostInstance, duration + 1)
end

function CashController.init()
	-- Listener PRZED yieldem (zasada 9). startIdleAnimation yielduje na WaitForChild
	-- (do 30s) — synchronicznie blokowałby CAŁY łańcuch initów kontrolerów w init.client
	-- (Movement, CooldownBar, KillFeed...) przy wolnej replikacji ActiveCash.
	Remotes.CashCollected.OnClientEvent:Connect(function(player: Player, fromPosition: Vector3)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
		if typeof(fromPosition) ~= "Vector3" then return end
		animatePickup(player, fromPosition)
	end)

	task.spawn(startIdleAnimation)
end

return CashController
