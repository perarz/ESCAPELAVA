--!strict
-- LobbySign.luau (03.11) — napis nad sprzedawcą w lobby (SHOP, COSMETICS): kolory płyną przez
-- litery w kółko. Wyjęte z ShopController, kiedy COSMETICS dostał to samo (Kacper 03.11).
-- Helper bez `init` — wołają go właściciele straganów.
--
-- PŁYNIĘCIE: przesuwany tweenem gradient Robloxa na końcu przeskakuje (poza zakresem powtarza
-- skrajny kolor), więc gradient liczymy co klatkę z zapętlonej palety.
--
-- WIDOCZNOŚĆ = tylko stały `MaxDistance` w placu (09.11, Kacper). Do 09.11 napis chował się też
-- za ścianami (promień kamera → napis co 0,1 s), ale przy szybkim ruchu kamery promień łapał słupy
-- i krawędzie, a napis migał. `AlwaysOnTop = true` zostaje (inaczej dach straganu obcina litery),
-- więc w lobby napis widać też przez budynki. Nie wracać do promienia bez wygładzania.
--
-- Daleko od napisu (poza MaxDistance) nic się nie liczy.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LobbySign = {}

local KEYS = 7

-- `palette` zapętlona: ostatni kolor przechodzi w pierwszy; `speed` = cykli palety na sekundę,
-- `span` = cykli na szerokość.
function LobbySign.start(sign: BillboardGui, grad: UIGradient, palette: { Color3 }, speed: number, span: number)
	local adornee = sign.Adornee or sign.Parent
	if not (adornee and adornee:IsA("BasePart")) then return end
	local n = #palette
	local function sample(u: number): Color3
		local x = (u % 1) * n
		local i = math.floor(x)
		local a, b = palette[i + 1], palette[(i + 1) % n + 1]
		return a:Lerp(b, x - i)
	end
	RunService.Heartbeat:Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam or not sign.Enabled then return end
		if (cam.CFrame.Position - adornee.Position).Magnitude > sign.MaxDistance + 10 then return end
		local phase = os.clock() * speed
		local keys = table.create(KEYS)
		for k = 0, KEYS - 1 do
			local x = k / (KEYS - 1)
			keys[k + 1] = ColorSequenceKeypoint.new(x, sample(x * span - phase))
		end
		grad.Color = ColorSequence.new(keys)
	end)
end

return LobbySign
