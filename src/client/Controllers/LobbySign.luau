--!strict
-- LobbySign.luau (03.11) — napis nad sprzedawcą w lobby (SHOP, COSMETICS): kolory płyną przez
-- litery w kółko, a napis chowa się za ścianami. Wyjęte z ShopController, kiedy COSMETICS
-- dostał to samo (Kacper 03.11). Helper bez `init` — wołają go właściciele straganów.
--
-- PŁYNIĘCIE: przesuwany tweenem gradient Robloxa na końcu przeskakuje (poza zakresem powtarza
-- skrajny kolor), więc gradient liczymy co klatkę z zapętlonej palety.
--
-- ZA ŚCIANAMI: `AlwaysOnTop = true` w placu zostaje. Samo `false` nie wystarcza: napis wisi
-- ~2 study nad dachem straganu i dach obcinał dół liter (zmierzone 03.11 w Edit: SHOP z 24–65
-- studów 12–13 z 15 punktów liter widocznych, z 16 studów 3 z 15). Zamiast tego promień
-- kamera → środek napisu; trafi coś nieprzezroczystego poza własnym straganem i postaciami →
-- napis znika. Przez szybę i niewidzialne ściany widać.
--
-- Daleko od napisu (poza MaxDistance) nic się nie liczy. Config: Config.UI.LobbySign.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local LobbySign = {}

local CFG = Config.UI.LobbySign
local KEYS = 7

local function blocked(from: Vector3, to: Vector3, own: Instance): boolean
	local skip: { Instance } = { own }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(skip, p.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 0, CFG.MaxSeeThroughHits do
		params.FilterDescendantsInstances = skip
		local hit = Workspace:Raycast(from, to - from, params)
		if not hit then return false end
		if hit.Instance.Transparency < CFG.SeeThroughTransparency then return true end
		table.insert(skip, hit.Instance)
	end
	return false
end

-- `own` = stragan, na którego dachu stoi napis (nie zasłania go). `palette` zapętlona: ostatni
-- kolor przechodzi w pierwszy; `speed` = cykli palety na sekundę, `span` = cykli na szerokość.
function LobbySign.start(sign: BillboardGui, grad: UIGradient, own: Instance, palette: { Color3 }, speed: number, span: number)
	local adornee = sign.Adornee or sign.Parent
	if not (adornee and adornee:IsA("BasePart")) then return end
	local n = #palette
	local function sample(u: number): Color3
		local x = (u % 1) * n
		local i = math.floor(x)
		local a, b = palette[i + 1], palette[(i + 1) % n + 1]
		return a:Lerp(b, x - i)
	end
	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local from = cam.CFrame.Position
		if (from - adornee.Position).Magnitude > sign.MaxDistance + 10 then return end
		local now = os.clock()
		if now >= nextCheck then
			nextCheck = now + CFG.CheckInterval
			-- StudsOffset jest w osiach kamery, StudsOffsetWorldSpace — świata.
			local at = adornee.Position + sign.StudsOffsetWorldSpace + cam.CFrame:VectorToWorldSpace(sign.StudsOffset)
			sign.Enabled = not blocked(from, at, own)
		end
		if not sign.Enabled then return end
		local phase = now * speed
		local keys = table.create(KEYS)
		for k = 0, KEYS - 1 do
			local x = k / (KEYS - 1)
			keys[k + 1] = ColorSequenceKeypoint.new(x, sample(x * span - phase))
		end
		grad.Color = ColorSequence.new(keys)
	end)
end

return LobbySign
