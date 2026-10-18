--!strict
-- PushController.luau
-- Dwie role:
--   1. F key → FireServer Push remote. Server jest authoritative (cooldown 2.5s, target
--      selection, alive check). Lokalny soft-cooldown żeby nie spamować RPC.
--   2. Odbiera Pushed (server → klient targetu) i aplikuje velocity na własnym HRP.
--      Server NIE może bezpośrednio ustawić velocity na character'ze gracza
--      (NetworkOwner=LocalPlayer → klient nadpisuje natychmiast).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local CooldownBarController = require(script.Parent.CooldownBarController)
local MovementController = require(script.Parent.MovementController)

local RunService = game:GetService("RunService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RagdollState = require(script.Parent.RagdollState)
local CFG = Config.Push
local PushController = {}
local initialized = false
local generation = 0
local pushTrack: AnimationTrack? = nil
local pushHumanoid: Humanoid? = nil
local previewId: string? = nil

local function cleanupAnimation()
	if pushTrack then pushTrack:Stop(0); pushTrack:Destroy() end
	pushTrack = nil
	pushHumanoid = nil
end

local function attachAnimation(character: Model)
	if character ~= Players.LocalPlayer.Character then return end
	generation += 1
	local ticket = generation
	cleanupAnimation()
	if not CFG.AnimationEnabled then return end
	local hum = character:WaitForChild("Humanoid", CFG.AnimationLoadTimeout)
	if ticket ~= generation or not hum or not hum:IsA("Humanoid") then return end
	local animator = hum:WaitForChild("Animator", CFG.AnimationLoadTimeout)
	if ticket ~= generation or not animator or not animator:IsA("Animator") then return end
	local loaded: AnimationTrack? = nil
	local ok, err = pcall(function()
		local id: string? = nil
		if CFG.AnimationId > 0 then
			id = "rbxassetid://" .. tostring(CFG.AnimationId)
		elseif RunService:IsStudio() and CFG.AnimationStudioPreview then
			if not previewId then
				local folder = ReplicatedStorage:FindFirstChild(CFG.AnimationFolder)
				local sequence = folder and folder:FindFirstChild(CFG.AnimationName)
				assert(sequence and sequence:IsA("KeyframeSequence"), "Missing push sequence")
				previewId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
			end
			id = previewId
		end
		if not id then return end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		animation:Destroy()
		loaded = track
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		local deadline = os.clock() + CFG.AnimationLoadTimeout
		while track.Length <= 0 and ticket == generation do
			assert(os.clock() < deadline, "Push animation load timeout")
			task.wait(CFG.AnimationLoadPoll)
		end
	end)
	if ticket ~= generation or not ok then
		if loaded then loaded:Destroy() end
		if not ok and ticket == generation then warn("[Push] Animation unavailable: " .. tostring(err)) end
		return
	end
	pushTrack, pushHumanoid = loaded, hum
end

local function playPushAnimation()
	local track, hum = pushTrack, pushHumanoid
	if not track or not hum or hum.Health <= 0 or RagdollState.isRagdolled(hum) then return end
	local speed = if CFG.Windup > 0 then CFG.AnimationImpactTime / CFG.Windup else 1
	track:Play(CFG.AnimationFadeIn, 1, speed)
end

local lastPushAt = 0

local localPlayer = Players.LocalPlayer

local function applyPushVelocity(velocity: Vector3)
	local char = localPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end
	hrp.AssemblyLinearVelocity = velocity
end

function PushController.init()
	if initialized then return end
	initialized = true
	localPlayer.CharacterAdded:Connect(function(character) task.spawn(attachAnimation, character) end)
	localPlayer.CharacterRemoving:Connect(function()
		generation += 1
		cleanupAnimation()
	end)
	if localPlayer.Character then task.spawn(attachAnimation, localPlayer.Character) end
	Remotes.RoundEnded.OnClientEvent:Connect(function()
		if pushTrack then pushTrack:Stop(CFG.AnimationFadeOut) end
	end)
	-- Monitor only an active gesture; the toolbox can change its flag before Humanoid state.
	RunService.Heartbeat:Connect(function()
		local track, hum = pushTrack, pushHumanoid
		if track and track.IsPlaying and hum and (hum.Health <= 0 or RagdollState.isRagdolled(hum)) then
			track:Stop(CFG.AnimationFadeOut)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode ~= Enum.KeyCode.F then return end

		local now = os.clock()
		local cd = Config.RateLimits.Push
		if now - lastPushAt < cd then return end
		lastPushAt = now

		playPushAnimation()
		Remotes.Push:FireServer()
		CooldownBarController.trigger("push", cd)
		-- Feedback popychającego (11.10): szarpnięcie kamery i mały zoom w chwili uderzenia.
		task.delay(CFG.Windup, function()
			MovementController.screenShake(CFG.PushShakeIntensity, CFG.PushShakeDuration)
			MovementController.fovKick(CFG.PushFOVKick)
		end)
	end)

	Remotes.Pushed.OnClientEvent:Connect(function(velocity)
		if typeof(velocity) ~= "Vector3" then return end
		applyPushVelocity(velocity)
		-- Feedback trafienia: krótki shake — czujesz że ktoś Cię pchnął, nie "samo się poleciało".
		MovementController.screenShake(Config.Push.HitShakeIntensity, Config.Push.HitShakeDuration)
	end)
end

return PushController
