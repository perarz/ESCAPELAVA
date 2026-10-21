--!strict
-- BridgeController.luau
-- Client-side build mode dla bridge_builder. Pokazuje ghost preview podążający za myszą,
-- R obraca o snap (45° z ItemDefinitions), LMB wysyła BuildBridge do servera.
--
-- Build mode aktywowany przez server (Remotes.BridgeBuildMode(true)). Klient sam się NIE
-- aktywuje — chcemy żeby server potwierdził alive + count zanim klient zacznie pokazywać UI.
--
-- Mouse position: raycast z kamery przez mouse Position (Mouse.Hit może być nieprawidłowe
-- gdy klikasz na sufit; raycast filtruje character + ghost + ActiveCash). ActiveBridges
-- nie są wykluczone — kursor LĄDUJE na postawionych mostach (stacking + extending).
--
-- Kontrakt pozycji: kursor = ANCHOR = bliższa krawędź mostu (krótka). Centrum mostu liczone
-- jako anchor + length/2 wzdłuż +Z lokalnej osi (po rotacji Y). Dzięki temu most rozciąga
-- się OD kursora w kierunku gdzie obrócony, a kursor nigdy nie musi być nad przepaścią.
-- Klient wysyła do serwera anchorPos + rotationY; server liczy centrum tym samym wzorem.

local ItemEquipController = require(script.Parent.ItemEquipController)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local CooldownBarController = require(script.Parent.CooldownBarController)

local BridgeController = {}

local ITEM_ID = "bridge_builder"

local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

local active = false
local rotationY = 0
-- Ghost jest MODELEM (most Kacpra to 12 desek), więc trzymamy też płaską listę jego
-- partów i gotowy offset pivota: jedno i drugie liczone RAZ, bo używamy ich co klatkę.
local ghost: Instance? = nil
local ghostParts: { BasePart } = {}
local ghostPivotOffset = CFrame.identity
local ghostValid: boolean? = nil -- można tu budować (zasięg i nie na lawie)
-- Sylwetka rysowana poza kolejką przezroczystości — jedyne, czego lawa nie zamaluje.
local ghostHighlight: Highlight? = nil
local renderConn: RBXScriptConnection? = nil
local inputConn: RBXScriptConnection? = nil
local lastBuildAt = 0
local clickDebounce = false

local function getDef()
	return ItemDefinitions.get(ITEM_ID)
end

-- Wymiary mostu z tego samego miejsca, co serwer (ItemDefinitions.worldSize) — inaczej
-- podgląd kłamałby o tym, gdzie most stanie.
local function getDims(def: any): Vector3
	return ItemDefinitions.worldSize(ITEM_ID) or Vector3.new(def.width, def.thickness, def.length)
end

-- Ghost z modelu `def.worldModel`; brak modelu = prosty Part jak dawniej.
-- Ghost jest tylko sygnałem „tu i w tę stronę", więc kolorujemy go na jeden kolor stanu.
local function makeGhost(def: any): Instance
	local template = if def.worldModel then Utils.getAsset(def.worldModel) else nil
	local inst: Instance

	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		inst = template:Clone()
	else
		local dims = getDims(def)
		local part = Instance.new("Part")
		part.Size = dims
		part.Material = def.material or Config.Bridge.DefaultMaterial
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		inst = part
	end

	inst.Name = "BridgeGhost"
	table.clear(ghostParts)
	if inst:IsA("BasePart") then
		table.insert(ghostParts, inst)
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(ghostParts, d)
			end
		end
	end
	for _, p in ipairs(ghostParts) do
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Transparency = Config.Bridge.GhostTransparency
	end

	-- Offset pivot→środek bbox policzony RAZ: model się nie zmienia, a przeliczanie go
	-- w RenderStepped to `GetBoundingBox` na kilkunastu partach 60 razy na sekundę.
	if inst:IsA("Model") then
		local bbCF = inst:GetBoundingBox()
		ghostPivotOffset = inst:GetPivot():ToObjectSpace(bbCF):Inverse()
	else
		ghostPivotOffset = CFrame.identity
	end
	-- `Highlight` PO ustawieniu partów: bez niego ghost znika, gdy za nim jest lawa
	-- (obie rzeczy są przezroczyste, a wielka tafla sortuje się niestabilnie — pełny
	-- opis przy `Config.Bridge.GhostHighlight`).
	ghostHighlight = nil
	if Config.Bridge.GhostHighlight then
		local hl = Instance.new("Highlight")
		hl.Name = "GhostHighlight"
		hl.Adornee = inst :: any
		hl.FillTransparency = Config.Bridge.GhostFillTransparency
		hl.OutlineTransparency = Config.Bridge.GhostOutlineTransparency
		hl.DepthMode = Config.Bridge.GhostDepthMode
		hl.Parent = inst
		ghostHighlight = hl
	end

	ghostValid = nil
	return inst
end

local function setGhostCFrame(cf: CFrame)
	local inst = ghost
	if not inst then return end
	if inst:IsA("BasePart") then
		inst.CFrame = cf
	else
		(inst :: Model):PivotTo(cf * ghostPivotOffset)
	end
end

-- Kolor przestawiamy TYLKO na zboczu stanu. Ustawianie go co klatkę to kilkanaście
-- zapisów property na klatkę za coś, co zmienia się raz na kilka sekund.
local function setGhostValid(valid: boolean)
	if ghostValid == valid then return end
	ghostValid = valid
	local color = if valid then Config.Bridge.GhostColorOK else Config.Bridge.GhostColorBad
	for _, p in ipairs(ghostParts) do
		p.Color = color
	end
	-- Sylwetka niesie ten sam sygnał co kolor partów — i to ona jest widoczna nad lawą.
	local hl = ghostHighlight
	if hl then
		hl.FillColor = color
		hl.OutlineColor = color
	end
end

local function getHRP(): BasePart?
	local char = localPlayer.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return nil
end

-- Wierzch stosu lawy, albo nil gdy lawy nie ma (wspólne z LavaSwimController — Utils).
local lavaTopY = Utils.lavaSurfaceY

local function computeAnchorPosition(dims: Vector3): (Vector3, boolean)
	-- Raycast z kamery przez mouse position. Filter: character, ghost, ActiveCash.
	-- ActiveBridges NIE wykluczane — chcemy żeby kursor lądował NA istniejących mostach
	-- (stacking + extending). Hit Y + thickness/2 = anchor (bliższa krawędź mostu).
	local cam = Workspace.CurrentCamera
	if not cam then return Vector3.new(0, 50, 0), false end

	local unitRay = cam:ScreenPointToRay(mouse.X, mouse.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList: { Instance } = {}
	if localPlayer.Character then table.insert(excludeList, localPlayer.Character) end
	if ghost then table.insert(excludeList, ghost) end
	local activeCash = Workspace:FindFirstChild("ActiveCash")
	if activeCash then table.insert(excludeList, activeCash) end
	rayParams.FilterDescendantsInstances = excludeList

	local maxDist = 300
	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * maxDist, rayParams)

	-- LAWA JAKO PODŁOGA: tafla ma `CanQuery = false`, więc promień przez nią PRZELATUJE
	-- i trafia w zatopiony grunt. Liczymy przecięcie z jej płaszczyzną osobno i bierzemy
	-- to, co bliżej kamery. Pełny opis przy `Config.Bridge.LavaAsFloor`.
	local lavaY = if Config.Bridge.LavaAsFloor then lavaTopY() else nil
	local lavaPoint: Vector3? = nil
	if lavaY and unitRay.Direction.Y < -1e-4 and unitRay.Origin.Y > lavaY then
		local dist = (lavaY - unitRay.Origin.Y) / unitRay.Direction.Y
		if dist > 0 and dist <= maxDist then
			lavaPoint = unitRay.Origin + unitRay.Direction * dist
		end
	end

	local hitPos: Vector3? = nil
	if result then
		-- Trafienie PONIŻEJ tafli znaczy, że gracz celował w lawę, a promień ją przeszył.
		if lavaPoint and lavaY and result.Position.Y < lavaY then
			hitPos = lavaPoint
		else
			hitPos = result.Position
		end
	elseif lavaPoint then
		-- Sama lawa po horyzont — bez tego byłby fallback „80 stud przed kamerą".
		hitPos = lavaPoint
	end

	if hitPos then
		-- Anchor Y = powierzchnia trafienia + grubość/2 (most siada spodem na powierzchni).
		return hitPos + Vector3.new(0, dims.Y * 0.5, 0), true
	end
	-- Brak hit → fallback 80 stud przed kamerą
	return unitRay.Origin + unitRay.Direction * 80, false
end

local function forwardFromRotY(rotY: number): Vector3
	-- Świat-space kierunek lokalnej osi +Z części po rotacji Y wokół (0,1,0).
	-- Zgodne z CFrame.Angles(0, rad(rotY), 0):VectorToWorldSpace(Vector3.new(0,0,1)).
	local rad = math.rad(rotY)
	return Vector3.new(math.sin(rad), 0, math.cos(rad))
end

local function anchorToCenter(anchorPos: Vector3, rotY: number, dims: Vector3): Vector3
	-- Anchor = bliższa krawędź mostu (gdzie kursor). Centrum = anchor + długość/2 wzdłuż +Z.
	-- Ten sam wzór liczy serwer w handleBuildBridge — muszą zostać zgodne.
	return anchorPos + forwardFromRotY(rotY) * (dims.Z * 0.5)
end

local function isInRange(pos: Vector3, def: any): boolean
	local hrp = getHRP()
	if not hrp then return false end
	return (pos - hrp.Position).Magnitude <= def.maxBuildDistance
end

-- Spód mostu na poziomie lawy (01.10): most ma fizykę od postawienia, a lawa nie ma kolizji,
-- więc utonąłby od razu. Ten sam próg sprawdza serwer przed zabraniem itemu.
local function isOnLava(anchorPos: Vector3, dims: Vector3): boolean
	local top = lavaTopY()
	return top ~= nil and anchorPos.Y - dims.Y * 0.5 <= top + Config.Bridge.LavaMargin
end

local function canBuildAt(anchorPos: Vector3, dims: Vector3, def: any): boolean
	return isInRange(anchorPos, def) and not isOnLava(anchorPos, dims)
end

local function initialRotationFromCamera(snap: number): number
	-- Most domyślnie rozciąga się w stronę gdzie patrzy kamera (gracz nie musi obracać R
	-- żeby dostać sensowny początkowy kąt). Projekcja look na płaszczyznę XZ → atan2.
	-- ZAOKRĄGLONE do kroku R (zgłoszenie Kacpra 08.10: „zależnie od kierunku patrzenia most
	-- jest obrócony o kilka stopni”) — kąt prosto z kamery dawał np. 37° albo 93°, więc most
	-- stał krzywo względem ulic i dachów, a R obracało od tego krzywego kąta.
	local cam = Workspace.CurrentCamera
	if not cam then return 0 end
	local look = cam.CFrame.LookVector
	local hx, hz = look.X, look.Z
	if hx * hx + hz * hz < 1e-4 then return 0 end  -- kamera prawie pionowo
	local deg = math.deg(math.atan2(hx, hz))
	if snap > 0 then
		deg = math.floor(deg / snap + 0.5) * snap
	end
	return deg % 360
end

local function enterBuildMode()
	if active then return end
	active = true

	local def = getDef()
	if not def then
		warn("[Bridge] brak ItemDefinitions.bridge_builder — abort")
		active = false
		return
	end
	rotationY = initialRotationFromCamera(def.rotateSnapDegrees or 0)

	local dims = getDims(def)

	ghost = makeGhost(def)
	ghost.Parent = Workspace

	-- RenderStepped: follow mouse + rotation + range color
	renderConn = RunService.RenderStepped:Connect(function()
		if not ghost or not active then return end
		local anchorPos, _hit = computeAnchorPosition(dims)
		local centerPos = anchorToCenter(anchorPos, rotationY, dims)
		setGhostCFrame(CFrame.new(centerPos) * CFrame.Angles(0, math.rad(rotationY), 0))
		-- Visual feedback: distance check liczony od anchor (= miejsca gdzie gracz "kładzie"),
		-- nie od centrum mostu. Inaczej długi most byłby zawsze "za daleko". Do tego lawa.
		setGhostValid(canBuildAt(anchorPos, dims, def))
	end)

	-- InputBegan: R rotate, LMB confirm. Filter gameProcessed (HUD klikalny przez Roblox).
	inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not active then return end
		if input.KeyCode == Enum.KeyCode.R and not gameProcessed then
			rotationY = (rotationY + def.rotateSnapDegrees) % 360
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not gameProcessed then
			if clickDebounce then return end
			clickDebounce = true
			task.delay(0.15, function() clickDebounce = false end)

			local anchorPos, _hit = computeAnchorPosition(dims)
			if not canBuildAt(anchorPos, dims, def) then
				-- Za daleko albo na lawie — nie spammujemy serwera. Ghost już czerwony.
				return
			end
			local now = os.clock()
			local cd = Config.RateLimits.BridgeBuild
			if now - lastBuildAt < cd then return end
			lastBuildAt = now
			-- Server dostaje ANCHOR (bliższa krawędź) + rotationY, sam wylicza centrum.
			ItemEquipController.cancel()
			Remotes.BuildBridge:FireServer(anchorPos, rotationY)
			CooldownBarController.trigger("bridge", cd)
		end
	end)
end

local function exitBuildMode()
	if not active then return end
	active = false
	if renderConn then renderConn:Disconnect() renderConn = nil end
	if inputConn then inputConn:Disconnect() inputConn = nil end
	if ghost then ghost:Destroy() ghost = nil end
	-- Highlight jest dzieckiem ghosta, więc zginął razem z nim — zerujemy tylko referencję.
	ghostHighlight = nil
	table.clear(ghostParts)
	ghostValid = nil
end

function BridgeController.init()
	Remotes.BridgeBuildMode.OnClientEvent:Connect(function(isActive: boolean)
		if isActive then
			enterBuildMode()
		else
			exitBuildMode()
		end
	end)

	Remotes.BridgeResult.OnClientEvent:Connect(function(success: boolean, reason: string?)
		if not success then
			print(("[Bridge] build FAIL — %s"):format(tostring(reason)))
		end
	end)

	-- Character cleanup — śmierć / respawn wychodzi z build mode (server fires
	-- BridgeBuildMode(false) na PlayerRemoving, ale nie na death; dlatego klient sam tu).
	localPlayer.CharacterRemoving:Connect(exitBuildMode)
end

return BridgeController
