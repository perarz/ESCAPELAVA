--!strict
-- SparkleBurst.luau (01.11) — krótki błysk gwiazdek w kontenerze postawionym w Studio.
--
-- KONTRAKT: kontener (Frame) z ukrytym `StarTemplate` (ImageLabel, AnchorPoint 0,5/0,5).
-- Klony powstają tylko w tym kontenerze i każdy niszczy się sam po zgaśnięciu (UI_RULES:
-- jeden kontener na efekt). Brak kontenera albo szablonu = nic się nie dzieje.
-- Pomocnik bez `init` — wołają go WinMessageController i ShopController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.UIEffects

local SparkleBurst = {}

local rng = Random.new()

local function spawnStar(container: Instance, template: ImageLabel)
	if not container.Parent then return end
	local scale = rng:NextNumber(CFG.SparkleScaleMin, CFG.SparkleScaleMax)
	local full = UDim2.fromOffset(template.Size.X.Offset * scale, template.Size.Y.Offset * scale)
	local star = template:Clone()
	star.Name = "Star"
	star.Position = UDim2.fromScale(rng:NextNumber(0.05, 0.95), rng:NextNumber(0.1, 0.9))
	star.Rotation = rng:NextNumber(-20, 20)
	star.Size = UDim2.fromOffset(0, 0)
	star.Visible = true
	star.Parent = container

	local grow = TweenService:Create(star, TweenInfo.new(CFG.SparkleGrowTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = full,
	})
	grow.Completed:Connect(function()
		if not star.Parent then return end
		local fade = TweenService:Create(star, TweenInfo.new(CFG.SparkleFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(0, 0),
			Rotation = star.Rotation + 90,
		})
		fade.Completed:Connect(function() star:Destroy() end)
		fade:Play()
	end)
	grow:Play()
end

function SparkleBurst.play(container: Instance?)
	if not container then return end
	local template = container:FindFirstChild("StarTemplate")
	if not (template and template:IsA("ImageLabel")) then return end
	for i = 1, CFG.SparkleCount do
		task.delay((i - 1) * CFG.SparkleStagger, spawnStar, container, template)
	end
end

return SparkleBurst
