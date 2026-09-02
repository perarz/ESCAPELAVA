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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local CooldownBarController = require(script.Parent.CooldownBarController)

local BridgeController = {}

local ITEM_ID = "bridge_builder"
local TEMPLATE_NAME = "BridgeTemplate"

local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

local active = false
local rotationY = 0
local ghost: BasePart? = nil
local renderConn: RBXScriptConnection? = nil
local inputConn: RBXScriptConnection? = nil
local lastBuildAt = 0
local clickDebounce = false

local function getDef()
	return ItemDefinitions.get(ITEM_ID)
end

local function makeGhost(def: any): BasePart
	-- Preferuj Kacper template (ReplicatedStorage.BridgeTemplate), fallback default.
	local template = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
	local part: BasePart
	if template and template:IsA("BasePart") then
		part = template:Clone() :: BasePart
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(def.width, def.thickness, def.length)
		part.Material = def.material or Enum.Material.Wood
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	part.Name = "BridgeGhost"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Color = Config.Bridge.GhostColorOK
	part.Transparency = Config.Bridge.GhostTransparency
	return part
end

local function getHRP(): BasePart?
	local char = localPlayer.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return nil
end

local function computeAnchorPosition(def: any): (Vector3, boolean)
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
	if result then
		-- Anchor Y = powierzchnia trafienia + thickness/2 (most siada spodem na powierzchni).
		local anchorPos = result.Position + Vector3.new(0, def.thickness * 0.5, 0)
		return anchorPos, true
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

local function anchorToCenter(anchorPos: Vector3, rotY: number, def: any): Vector3
	-- Anchor = bliższa krawędź mostu (gdzie kursor). Centrum = anchor + length/2 wzdłuż +Z.
	return anchorPos + forwardFromRotY(rotY) * (def.length * 0.5)
end

local function isInRange(pos: Vector3, def: any): boolean
	local hrp = getHRP()
	if not hrp then return false end
	return (pos - hrp.Position).Magnitude <= def.maxBuildDistance
end

local function initialRotationFromCamera(): number
	-- Most domyślnie rozciąga się w stronę gdzie patrzy kamera (gracz nie musi obracać R
	-- żeby dostać sensowny początkowy kąt). Projekcja look na płaszczyznę XZ → atan2.
	local cam = Workspace.CurrentCamera
	if not cam then return 0 end
	local look = cam.CFrame.LookVector
	local hx, hz = look.X, look.Z
	if hx * hx + hz * hz < 1e-4 then return 0 end  -- kamera prawie pionowo
	return math.deg(math.atan2(hx, hz))
end

local function enterBuildMode()
	if active then return end
	active = true
	rotationY = initialRotationFromCamera()

	local def = getDef()
	if not def then
		warn("[Bridge] brak ItemDefinitions.bridge_builder — abort")
		active = false
		return
	end

	ghost = makeGhost(def)
	ghost.Parent = Workspace

	-- RenderStepped: follow mouse + rotation + range color
	renderConn = RunService.RenderStepped:Connect(function()
		if not ghost or not active then return end
		local anchorPos, _hit = computeAnchorPosition(def)
		local centerPos = anchorToCenter(anchorPos, rotationY, def)
		ghost.CFrame = CFrame.new(centerPos) * CFrame.Angles(0, math.rad(rotationY), 0)
		-- Visual feedback: distance check liczony od anchor (= miejsca gdzie gracz "kładzie"),
		-- nie od centrum mostu. Inaczej długi most byłby zawsze "za daleko".
		ghost.Color = isInRange(anchorPos, def)
			and Config.Bridge.GhostColorOK
			or Config.Bridge.GhostColorBad
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

			local anchorPos, _hit = computeAnchorPosition(def)
			if not isInRange(anchorPos, def) then
				-- Klient wie że za daleko — nie spammujemy server. Visual już czerwony.
				return
			end
			local now = os.clock()
			local cd = Config.RateLimits.BridgeBuild
			if now - lastBuildAt < cd then return end
			lastBuildAt = now
			-- Server dostaje ANCHOR (bliższa krawędź) + rotationY, sam wylicza centrum.
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
