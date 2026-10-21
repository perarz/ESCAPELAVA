--!strict
-- Reconstruct the cosmetic gesture from replicated Tools on every client: no asset
-- publishing or per-frame network traffic, and mechanics never wait for the gesture.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CFG = require(ReplicatedStorage.Shared.Modules.Config).ItemEquip
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local RagdollState = require(script.Parent.RagdollState)
local ItemEquipController = {}

type Joint = { motor: Motor6D, base: CFrame?, written: CFrame? }
type Gesture = {
	character: Model, humanoid: Humanoid, tool: Tool, started: number,
	profile: string, joints: { [string]: Joint },
	drawCancelled: boolean, pausedUntil: number,
	actionTracks: { [AnimationTrack]: boolean }, animationConnection: RBXScriptConnection?,
}
type Watch = { character: Model?, characterConnections: { RBXScriptConnection }, connections: { RBXScriptConnection } }
local active: { [Player]: Gesture } = {}
local watches: { [Player]: Watch } = {}
local initialized = false

local function restore(gesture: Gesture)
	for _, joint in pairs(gesture.joints) do
		-- Animator may be throttled, so explicitly remove our previous pose before
		-- its next evaluation. Don't overwrite a transform changed by another owner.
		if joint.base and joint.written and joint.motor.Parent and joint.motor.Transform == joint.written then
			joint.motor.Transform = joint.base
		end
		joint.base, joint.written = nil, nil
	end
end

local function stop(player: Player)
	local gesture = active[player]
	if gesture then
		restore(gesture)
		if gesture.animationConnection then gesture.animationConnection:Disconnect() end
	end
	active[player] = nil
end

function ItemEquipController.cancel(pauseDuration: number?)
	local gesture = active[Players.LocalPlayer]
	if gesture and CFG.HoldPoses[gesture.profile] then
		-- Firing interrupts the draw, but spare rockets leave the launcher equipped.
		restore(gesture)
		gesture.drawCancelled = true
		gesture.pausedUntil = math.max(gesture.pausedUntil, os.clock() + (pauseDuration or 0))
	else
		stop(Players.LocalPlayer)
	end
end

local function begin(player: Player, character: Model, tool: Tool, skipDraw: boolean?)
	local profile = CFG.ToolProfiles[tool.Name]
	if not profile then return end
	stop(player)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or RagdollState.isRagdolled(hum) then return end
	local joints: { [string]: Joint } = {}
	local names = { RightShoulder = "Shoulder", RightElbow = "Elbow", RightWrist = "Wrist", Waist = "Waist" }
	if CFG.HoldPoses[profile] then
		names.LeftShoulder, names.LeftElbow, names.LeftWrist = "LeftShoulder", "LeftElbow", "LeftWrist"
	end
	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("Motor6D") then
			local name = names[instance.Name]
			if name then joints[name] = { motor = instance, base = nil, written = nil } end
		end
	end
	if not joints.Shoulder or not joints.Elbow or not joints.Wrist then return end
	local gesture: Gesture = { character = character, humanoid = hum, tool = tool,
		started = os.clock(), profile = profile, joints = joints,
		drawCancelled = skipDraw == true, pausedUntil = 0, actionTracks = {}, animationConnection = nil }
	if CFG.HoldPoses[profile] then
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			-- Yield to push/action animations on every observed character, including
			-- other players. A permanent Transform overlay would otherwise mask them.
			local function trackAction(track: AnimationTrack)
				-- Core is lowest in animation blending, but its enum value is 1000.
				-- Numeric ordering would treat Animate's idle/run tracks as actions
				-- and permanently suspend the grip while the player stands or moves.
				local priority = track.Priority
				if priority == Enum.AnimationPriority.Action or priority == Enum.AnimationPriority.Action2
					or priority == Enum.AnimationPriority.Action3 or priority == Enum.AnimationPriority.Action4 then
					gesture.actionTracks[track] = true
				end
			end
			gesture.animationConnection = animator.AnimationPlayed:Connect(trackAction)
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do trackAction(track) end
		end
	end
	active[player] = gesture
end

local function disconnect(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
end

local function attach(player: Player, character: Model, watch: Watch)
	stop(player)
	disconnect(watch.characterConnections)
	watch.character = character
	table.insert(watch.characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then begin(player, character, child) end
	end))
	table.insert(watch.characterConnections, character.ChildRemoved:Connect(function(child)
		local gesture = active[player]
		if gesture and child == gesture.tool then stop(player) end
	end))
	-- Joining/streaming an already equipped character must not replay an old draw.
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and CFG.HoldPoses[CFG.ToolProfiles[child.Name]] then
			begin(player, character, child, true)
		end
	end
end

local function watchPlayer(player: Player)
	if watches[player] then return end
	local watch: Watch = { character = nil, characterConnections = {}, connections = {} }
	watches[player] = watch
	table.insert(watch.connections, player.CharacterAdded:Connect(function(character) attach(player, character, watch) end))
	table.insert(watch.connections, player.CharacterRemoving:Connect(function(character)
		if watch.character ~= character then return end
		stop(player)
		disconnect(watch.characterConnections)
		watch.character = nil
	end))
	if player.Character then attach(player, player.Character, watch) end
end

local function angles(v: Vector3): CFrame
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

local function update()
	local now = os.clock()
	for player, gesture in pairs(active) do
		local hum = gesture.humanoid
		local duration = CFG.ProfileDurations[gesture.profile] or CFG.Duration
		local t = if gesture.drawCancelled then 1 else math.min(1, (now - gesture.started) / duration)
		local hold = CFG.HoldPoses[gesture.profile]
		if (t >= 1 and not hold) or player.Character ~= gesture.character or not gesture.character.Parent
			or gesture.tool.Parent ~= gesture.character or hum.Health <= 0
		then
			stop(player)
			continue
		end
		local actionPlaying = false
		for track in pairs(gesture.actionTracks) do
			if track.IsPlaying then actionPlaying = true else gesture.actionTracks[track] = nil end
		end
		if RagdollState.isRagdolled(hum) or hum.Sit or now < gesture.pausedUntil or actionPlaying
			or hum:GetState() == Enum.HumanoidStateType.Climbing
			or hum:GetState() == Enum.HumanoidStateType.Swimming then
			if hold then gesture.drawCancelled = true else stop(player) end
			continue
		end
		local keys = CFG.Profiles[gesture.profile]
		local a, b = keys[1], keys[#keys]
		for index = 2, #keys do
			if t <= keys[index].Time then a, b = keys[index - 1], keys[index]; break end
		end
		local alpha = math.clamp((t - a.Time) / (b.Time - a.Time), 0, 1)
		alpha = alpha * alpha * (3 - 2 * alpha)
		local weight = a.Weight + (b.Weight - a.Weight) * alpha
		local holdWeight = math.clamp((t - CFG.HoldBlendStart) / (CFG.HoldBlendEnd - CFG.HoldBlendStart), 0, 1)
		holdWeight = holdWeight * holdWeight * (3 - 2 * holdWeight)
		for name, joint in pairs(gesture.joints) do
			local motor = joint.motor
			if not motor.Parent or not motor.Enabled then stop(player); break end
			local base = motor.Transform
			local result = base
			local holdAngles = hold and hold[name]
			if holdAngles then result = base:Lerp(angles(holdAngles), holdWeight) end
			if a[name] and b[name] then
				local pose = angles(a[name]):Lerp(angles(b[name]), alpha)
				result = if name == "Waist" then base * CFrame.identity:Lerp(pose, weight)
					else result:Lerp(pose, weight)
			end
			joint.base, joint.written = base, result
			motor.Transform = result
		end
	end
end

function ItemEquipController.init()
	if initialized then return end
	initialized = true
	if not CFG.Enabled then return end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		stop(player)
		local watch = watches[player]
		if watch then disconnect(watch.characterConnections); disconnect(watch.connections) end
		watches[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
	Remotes.RoundEnded.OnClientEvent:Connect(function()
		for player in pairs(active) do stop(player) end
	end)
	-- Animator writes between these phases. C0 belongs to head tracking; legs and
	-- the root remain entirely owned by the default Animate and movement systems.
	RunService.PreAnimation:Connect(function()
		for _, gesture in pairs(active) do restore(gesture) end
	end)
	RunService.PreSimulation:Connect(update)
end

return ItemEquipController
