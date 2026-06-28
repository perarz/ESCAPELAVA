--!strict
-- BridgeController.luau
-- Client-side build mode dla bridge_builder. Pokazuje ghost preview podążający za myszą,
-- R obraca o snap (45° z ItemDefinitions), LMB wysyła BuildBridge do servera.
--
-- Build mode aktywowany przez server (Remotes.BridgeBuildMode(true)). Klient sam się NIE
-- aktywuje — chcemy żeby server potwierdził alive + count zanim klient zacznie pokazywać UI.
--
-- Mouse position: raycast z kamery przez mouse Position (Mouse.Hit może być nieprawidłowe
-- gdy klikasz na sufit; raycast filtruje character + ActiveBridges + ActiveCash).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

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

local function computeTargetPosition(def: any): (Vector3, boolean)
	-- Raycast z kamery przez mouse position. Filter: character, ghost, ActiveCash, ActiveBridges.
	-- Hit found → mouse pozycja na powierzchni, hit Y. Nie znalezione → 100 stud przed kamerą.
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
	local activeBridges = Workspace:FindFirstChild("ActiveBridges")
	if activeBridges then table.insert(excludeList, activeBridges) end
	rayParams.FilterDescendantsInstances = excludeList

	local maxDist = 300
	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * maxDist, rayParams)
	if result then
		-- Most środkiem pivota Y, więc unosi się o thickness/2 nad uderzonej powierzchni.
		local hitPos = result.Position + Vector3.new(0, def.thickness * 0.5, 0)
		return hitPos, true
	end
	-- Brak hit → fallback 80 stud przed kamerą
	return unitRay.Origin + unitRay.Direction * 80, false
end

local function isInRange(pos: Vector3, def: any): boolean
	local hrp = getHRP()
	if not hrp then return false end
	return (pos - hrp.Position).Magnitude <= def.maxBuildDistance
end

local function enterBuildMode()
	if active then return end
	active = true
	rotationY = 0

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
		local pos, _hit = computeTargetPosition(def)
		ghost.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(rotationY), 0)
		-- Visual feedback: zielony in range, czerwony out of range
		ghost.Color = isInRange(pos, def)
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

			local pos, _hit = computeTargetPosition(def)
			if not isInRange(pos, def) then
				-- Klient wie że za daleko — nie spammujemy server. Visual już czerwony.
				return
			end
			Remotes.BuildBridge:FireServer(pos, rotationY)
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
