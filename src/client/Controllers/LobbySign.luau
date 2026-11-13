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

-- Gradient z zapętlonej palety w chwili `phase` (cykle palety). `palette`: ostatni kolor przechodzi
-- w pierwszy; `span` = cykli na szerokość; `dim` (domyślnie 1) przyciemnia — tło COSMETICS (09.11)
-- płynie tą samą paletą co napis nad sprzedawcą, tylko ciemniej.
function LobbySign.sequence(palette: { Color3 }, span: number, phase: number, dim: number?): ColorSequence
	local n = #palette
	local d = dim or 1
	local keys = table.create(KEYS)
	for k = 0, KEYS - 1 do
		local x = k / (KEYS - 1)
		local u = ((x * span - phase) % 1) * n
		local i = math.floor(u)
		local c = palette[i + 1]:Lerp(palette[(i + 1) % n + 1], u - i)
		keys[k + 1] = ColorSequenceKeypoint.new(x, Color3.new(c.R * d, c.G * d, c.B * d))
	end
	return ColorSequence.new(keys)
end

-- `speed` = cykli palety na sekundę, `span` = cykli na szerokość.
function LobbySign.start(sign: BillboardGui, grad: UIGradient, palette: { Color3 }, speed: number, span: number)
	local adornee = sign.Adornee or sign.Parent
	if not (adornee and adornee:IsA("BasePart")) then return end
	RunService.Heartbeat:Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam or not sign.Enabled then return end
		if (cam.CFrame.Position - adornee.Position).Magnitude > sign.MaxDistance + 10 then return end
		grad.Color = LobbySign.sequence(palette, span, os.clock() * speed)
	end)
end

return LobbySign
