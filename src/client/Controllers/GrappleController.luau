--!strict
-- GrappleController.luau
-- Kliencka strona haka. Trzy role:
--   1. Tool.Activated na `GrappleTool` → FireGrapple(punkt, w który celuje mysz)
--   2. Remotes.Grappled → LOT PO ŁUKU do punktu podanego przez serwer (własna postać)
--   3. Remotes.GrappleFX → lina innego gracza, rysowana lokalnie przez cały jego lot
--
-- ⚠️ LOT PROWADZI KLIENT, NIE SERWER — postać ma network ownership gracza, więc serwerowa
-- siła czy prędkość na HRP zostałaby natychmiast nadpisana (hard rule 12). Serwer decyduje
-- DOKĄD i NAJDŁUŻEJ JAK DŁUGO; tutaj jest tylko wykonanie.
--
-- ⚠️ POSTAĆ JEST PROWADZONA PO ŁUKU, A NIE RZUCANA. Rzut (impuls) przecina punkt z pełną
-- prędkością zamiast się w nim kończyć; lina po prostej kończy się w punkcie, ale wygląda
-- jak winda. Prowadzenie po krzywej z GrappleArc daje łuk ORAZ koniec w punkcie — historia
-- trzech odrzuconych modeli przy Config.Grapple. `LinearVelocity` przy okazji przebija
-- kontroler Humanoida, który na ziemi zjada poziomą prędkość, zanim postać się oderwie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local GrappleArc = require(ReplicatedStorage.Shared.Modules.GrappleArc)
local CooldownBarController = require(script.Parent.CooldownBarController)
local MovementController = require(script.Parent.MovementController)
local RagdollState = require(script.Parent.RagdollState)

local GrappleController = {}

local CFG = Config.Grapple
local localPlayer = Players.LocalPlayer
local lastFireAt = 0

-- ⚠️ Ten sam gate co w ToolController: poza rundą serwer zaczep odrzuca, więc nie ma po co
-- wysyłać RPC. Pusty stan CELOWO przepuszczamy — gracz mógł dołączyć, zanim `replicateTo`
-- dojechało, a blokada trzymałaby go bez itemu przez kilka minut.
local gameState = ""
Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
	gameState = newState
end)

type Flight = {
	arc: GrappleArc.Arc,
	anchor: Vector3,     -- punkt trafienia na powierzchni — wyznacza kierunek wybicia
	deadline: number,    -- twardy sufit od serwera
	startedAt: number,
	stuckFor: number,
	lastVel: Vector3,    -- prędkość po łuku w ostatnim kroku — część zostaje po wyjściu
	attachment: Attachment,
	pull: LinearVelocity,
}

type Rope = {
	shooter: Player,
	anchor: Vector3,
	goal: Vector3,
	deadline: number,
	part: BasePart,
	-- Lina WŁASNEGO lotu kończy się razem z nim (patrz `updateRopes`). U innych graczy
	-- nie znamy ich lotu, więc kończą się po dotarciu do celu albo po czasie.
	flightRef: Flight?,
}

type EndReason = "arrived" | "stuck" | "timeout" | "interrupted" | "replaced"

local flight: Flight? = nil
local activeRopes: { Rope } = {}

local function getCharParts(): (Humanoid?, BasePart?)
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hum, hrp
	end
	return hum, nil
end

-- Czy nasza postać leży jako ragdoll — jedno miejsce dla całego klienta (RagdollState, 29.09).
-- Tu wprowadzone 26.09 („podczas ragdolla da się handhookiem lecieć i kolegę w kosmos
-- wywaliło”); serwer blokuje strzał osobno.
local isRagdolled = RagdollState.isRagdolled

-- ── Lina ─────────────────────────────────────────────────────────────────────────────
-- Czysto lokalny part (wzorzec DebrisFXController): zero replikacji, zero fizyki serwera.
-- ⚠️ `Locked = true` jest WYMAGANE — bez tego `Destructible.canSpawnFXFrom` przepuszcza
-- linę i DebrisFXController próbkuje z niej kolory przy najbliższym wybuchu (ta sama
-- pułapka co przy bąblach lawy).
local function ropeOrigin(shooter: Player): Vector3?
	local char = shooter.Character
	if not char then return nil end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("HumanoidRootPart")
	if hand and hand:IsA("BasePart") then
		return hand.Position
	end
	return nil
end

local function placeRope(part: BasePart, from: Vector3, to: Vector3)
	local delta = to - from
	local dist = delta.Magnitude
	if dist < 0.1 then return end
	part.Size = Vector3.new(CFG.RopeThickness, CFG.RopeThickness, dist)
	part.CFrame = CFrame.lookAt(from + delta * 0.5, to)
end

local function startRope(shooter: Player, anchor: Vector3, goal: Vector3, maxTime: number, flightRef: Flight?)
	local from = ropeOrigin(shooter)
	if not from then return end

	local part = Instance.new("Part")
	part.Name = "GrappleRope"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = CFG.RopeColor
	-- Geometria PRZED wstawieniem do Workspace — inaczej jedna klatka liny w (0, 0, 0).
	placeRope(part, from, anchor)
	part.Parent = Workspace

	table.insert(activeRopes, {
		shooter = shooter,
		anchor = anchor,
		goal = goal,
		deadline = os.clock() + maxTime,
		part = part,
		flightRef = flightRef,
	})
end

local function fadeRope(part: BasePart)
	TweenService:Create(part, TweenInfo.new(CFG.RopeFadeTime), { Transparency = 1 }):Play()
	-- Tween nie kasuje instancji — Debris tak, niezależnie od tego, czy tween dobiegł.
	Debris:AddItem(part, CFG.RopeFadeTime + 0.05)
end

-- RenderStepped, bo to czysty wizual: ustawiamy linę z tych samych pozycji, z których
-- zaraz zostanie wyrenderowana postać — lina nie „zostaje w tyle" za ręką przy 100 stud/s.
local function updateRopes()
	if #activeRopes == 0 then return end
	local now = os.clock()
	for i = #activeRopes, 1, -1 do
		local r = activeRopes[i]
		local from = ropeOrigin(r.shooter)
		local done = from == nil or now >= r.deadline
		if not done and r.flightRef ~= nil and flight ~= r.flightRef then
			-- Nasz lot się skończył (albo zastąpił go nowy zaczep) — lina razem z nim.
			done = true
		end
		if not done and r.flightRef == nil then
			local char = r.shooter.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and (r.goal - hrp.Position).Magnitude <= CFG.ArriveRadius then
				done = true
			end
		end

		if done then
			fadeRope(r.part)
			table.remove(activeRopes, i)
		else
			placeRope(r.part, from :: Vector3, r.anchor)
		end
	end
end

-- ── Lot ──────────────────────────────────────────────────────────────────────────────
local function endFlight(reason: EndReason)
	local f = flight
	if not f then return end
	-- Stan czyścimy PIERWSZY: `flight = nil` jest też sygnałem dla liny (updateRopes).
	flight = nil
	f.pull:Destroy()
	f.attachment:Destroy()

	-- Przy przerwaniu (ragdoll, śmierć, respawn) prędkość przejmuje toolbox albo nie ma
	-- już czego ruszać. Przy zastąpieniu nowym zaczepem nowy lot zaraz ustawi swoją.
	if reason == "interrupted" or reason == "replaced" then return end

	local _, hrp = getCharParts()
	if not hrp then return end

	-- Wybicie W STRONĘ ŚCIANY, w którą trafił hak — to ono przerzuca przez krawędź dachu.
	-- Cel leży przed ścianą (Standoff wzdłuż normalnej), więc kierunek „cel → trafienie"
	-- wskazuje prosto na nią. Przy zaczepie o sam dach trafienie leży POD celem i poziomu
	-- brak — wtedy wybijamy w kierunku lotu.
	local toWall = f.anchor - f.arc.p2
	local flat = Vector3.new(toWall.X, 0, toWall.Z)
	if flat.Magnitude < 0.3 then
		flat = Vector3.new(f.lastVel.X, 0, f.lastVel.Z)
	end
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zero

	-- Część prędkości z końca łuku ZOSTAJE: koniec łuku ma jeszcze ~40-60 stud/s, a zerowanie
	-- jej w jednej klatce czyta się jak szarpnięcie na końcu lotu.
	hrp.AssemblyLinearVelocity = f.lastVel * CFG.ExitCarry
		+ flat * CFG.ExitForward
		+ Vector3.new(0, CFG.ExitUp, 0)
end

local function stepFlight(dt: number)
	local f = flight
	if not f then return end

	local hum, hrp = getCharParts()
	-- `attachment.Parent ~= hrp` łapie respawn: nowa postać ma nowy HRP, a stary lot
	-- skończyłby się timeoutem i wybił NOWĄ postać w powietrze.
	if not (hum and hrp) or hum.Health <= 0 or f.attachment.Parent ~= hrp then
		endFlight("interrupted")
		return
	end
	-- Ragdoll w trakcie lotu (bomba, upadek) — lina i toolbox walczyłyby o prędkość
	-- postaci, a solver wystrzeliwuje bezwładne ciało.
	if isRagdolled(hum) then
		endFlight("interrupted")
		return
	end

	local now = os.clock()
	if now >= f.deadline then
		endFlight("timeout")
		return
	end

	local elapsed = now - f.startedAt
	local u = elapsed / f.arc.duration
	if u >= 1 then
		endFlight("arrived")
		return
	end

	-- Gdzie postać POWINNA być teraz i z jaką prędkością jedzie tam łuk.
	local s, dsdu = GrappleArc.ease(u)
	local target = GrappleArc.point(f.arc, s)
	local along = GrappleArc.derivative(f.arc, s) * (dsdu / f.arc.duration)
	local offset = target - hrp.Position

	f.lastVel = along
	-- Prędkość łuku + poprawka odchyłki. Bez poprawki postać dryfuje od krzywej przez
	-- opóźnienie klatki i kończy lot obok punktu, zamiast w nim.
	f.pull.VectorVelocity = along + offset * CFG.TrackGain

	-- Zahaczenie po drodze: lina ciągnie, a postać odstaje od łuku. Po ODLEGŁOŚCI, nie po
	-- prędkości — tempo na łuku celowo się zmienia, więc „za wolno" nic by nie znaczyło.
	if elapsed >= CFG.StuckGrace then
		if offset.Magnitude > CFG.StuckDistance then
			f.stuckFor += dt
			if f.stuckFor >= CFG.StuckTime then
				endFlight("stuck")
				return
			end
		else
			f.stuckFor = 0
		end
	end
end

local function startFlight(anchor: Vector3, goal: Vector3, maxTime: number)
	local hum, hrp = getCharParts()
	if not (hum and hrp) or hum.Health <= 0 then return end
	-- Wywrotka mogła przyjść między strzałem a potwierdzeniem serwera.
	if isRagdolled(hum) then return end

	-- Nowy zaczep w trakcie lotu zastępuje stary (item jest zużywalny, więc każdy kosztuje).
	endFlight("replaced")

	-- Łuk od AKTUALNEJ pozycji postaci — to ona jest prawdą o tym, gdzie gracz jest.
	-- Serwer liczył z pozycji opóźnionej o ping; różnica pokrywa się w TimeMargin.
	local arc = GrappleArc.plan(hrp.Position, goal)
	if arc.duration <= 0.01 then return end

	local s0, dsdu0 = GrappleArc.ease(0)
	local v0 = GrappleArc.derivative(arc, s0) * (dsdu0 / arc.duration)

	local attachment = Instance.new("Attachment")
	attachment.Name = "GrappleAttachment"
	attachment.Parent = hrp

	local pull = Instance.new("LinearVelocity")
	pull.Name = "GrapplePull"
	pull.Attachment0 = attachment
	pull.RelativeTo = Enum.ActuatorRelativeTo.World
	pull.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	-- Siła skończona celowo — nieograniczona przy zetknięciu z geometrią potrafi wypchnąć
	-- postać przez cienki part. `max(…, 1)`: HRP i głowa mają od toolboxa zerową gęstość,
	-- więc liczymy masę CAŁEGO assembly, ale bez ryzyka, że wyjdzie zero.
	pull.MaxForce = math.max(hrp.AssemblyMass, 1) * Workspace.Gravity * CFG.ForceScale
	pull.VectorVelocity = v0
	pull.Parent = hrp

	local now = os.clock()
	local f: Flight = {
		arc = arc,
		anchor = anchor,
		deadline = now + maxTime,
		startedAt = now,
		stuckFor = 0,
		lastVel = v0,
		attachment = attachment,
		pull = pull,
	}
	flight = f
	startRope(localPlayer, anchor, goal, maxTime, f)
end

-- ── Strzał ───────────────────────────────────────────────────────────────────────────
local function hookTool(tool: Tool)
	if tool.Name ~= "GrappleTool" then return end

	tool.Activated:Connect(function()
		if gameState ~= "" and gameState ~= "ROUND" then return end

		-- Lokalny soft-cooldown: tylko po to, żeby nie zasypywać serwera RPC. Pasek
		-- odpalamy dopiero po POTWIERDZENIU (Remotes.Grappled) — optymistyczny pasek przy
		-- odrzuconym zaczepie to kłamstwo interfejsu, które zgłoszono już przy bombie.
		local now = os.clock()
		if now - lastFireAt < Config.RateLimits.Grapple then return end

		local hum, hrp = getCharParts()
		if not (hum and hrp) then return end
		if isRagdolled(hum) then return end

		local mouse = localPlayer:GetMouse()
		local target = mouse.Hit and mouse.Hit.Position
		if not target then return end
		if (target - hrp.Position).Magnitude < 1 then return end

		lastFireAt = now
		Remotes.FireGrapple:FireServer(target)
	end)
end

local function hookCharacter(char: Model)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookTool(child)
		end
	end)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			hookTool(c)
		end
	end
end

function GrappleController.init()
	if localPlayer.Character then
		hookCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(hookCharacter)
	localPlayer.CharacterRemoving:Connect(function()
		endFlight("interrupted")
	end)

	RunService.Heartbeat:Connect(stepFlight)
	RunService.RenderStepped:Connect(updateRopes)

	Remotes.Grappled.OnClientEvent:Connect(function(anchor, goal, maxTime)
		if typeof(anchor) ~= "Vector3" or typeof(goal) ~= "Vector3" or type(maxTime) ~= "number" then
			return
		end
		startFlight(anchor, goal, maxTime)
		MovementController.screenShake(CFG.ShakeIntensity, CFG.ShakeDuration)
		-- Pasek dopiero TERAZ: serwer potwierdził, że zaczep się odbył i item zszedł.
		CooldownBarController.trigger("grapple", Config.RateLimits.Grapple)
	end)

	Remotes.GrappleFX.OnClientEvent:Connect(function(shooter, anchor, goal, maxTime)
		if typeof(shooter) ~= "Instance" or not shooter:IsA("Player") then return end
		if typeof(anchor) ~= "Vector3" or typeof(goal) ~= "Vector3" or type(maxTime) ~= "number" then
			return
		end
		-- Własną linę mamy już z Remotes.Grappled, związaną z lotem.
		if shooter == localPlayer then return end
		startRope(shooter, anchor, goal, maxTime, nil)
	end)
end

return GrappleController
