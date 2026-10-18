--!strict
-- TextShadowController.luau (10.10) — cień tekstu w UI.
--
-- Zasada Kacpra dla całego UI: pod każdym tekstem leży ten sam tekst, cały czarny, lekko
-- przesunięty w lewo i w dół. Cień to ZWYKŁA etykieta postawiona w Studio obok tekstu
-- (UI jest obiektami, nie kodem) — tu tylko pilnujemy, żeby pokazywała to samo co tekst,
-- który zmienia kod (kasa, nazwa itemu, liczba sztuk…).
--
-- KONTRAKT: etykieta `<Nazwa>Shadow` (TextLabel/TextButton) obok etykiety `<Nazwa>` w tym
-- samym rodzicu → `Text` i `Visible` kopiowane z `<Nazwa>` (z RichText — bez znaczników, gdy cień
-- ma RichText wyłączony). Wygląd cienia (kolor, przesunięcie,
-- ZIndex niżej niż tekst) ustawia się w Studio. Działa dla wszystkiego w PlayerGui, także
-- dla UI dodanego później (sklep, panele).

local Players = game:GetService("Players")

local TextShadowController = {}

local SUFFIX = "Shadow"
local linked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local initialized = false

local function isText(inst: Instance): boolean
	return inst:IsA("TextLabel") or inst:IsA("TextButton")
end

local function link(shadow: Instance)
	if linked[shadow] or not isText(shadow) then return end
	local name = shadow.Name
	if #name <= #SUFFIX or name:sub(-#SUFFIX) ~= SUFFIX then return end
	local parent = shadow.Parent
	local base = parent and parent:FindFirstChild(name:sub(1, -#SUFFIX - 1))
	if not (base and isText(base)) then return end
	linked[shadow] = true
	local s = shadow :: any
	local b = base :: any
	local function sync()
		-- Tekst z RichText (np. czerwone „KILLED”): cień jest jednokolorowy, więc dostaje sam
		-- tekst bez znaczników — inaczej kolor ze znacznika przebiłby czerń cienia.
		if b.RichText and not s.RichText then
			s.Text = (b.Text:gsub("<[^>]->", ""):gsub("&lt;", "<"):gsub("&gt;", ">")
				:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
		else
			s.Text = b.Text
		end
		s.Visible = b.Visible
	end
	sync()
	-- Połączenia giną razem z etykietami (Destroy rozłącza), więc nie trzeba ich sprzątać.
	b:GetPropertyChangedSignal("Text"):Connect(sync)
	b:GetPropertyChangedSignal("Visible"):Connect(sync)
end

function TextShadowController.init()
	if initialized then return end
	initialized = true
	-- task.spawn: WaitForChild yielduje, a kolejne kontrolery nie mogą na to czekać (hard rule 9).
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		-- Cień albo tekst może dojechać w dowolnej kolejności — przy każdym nowym obiekcie
		-- sprawdzamy jego i, jeśli to tekst, jego ewentualny cień.
		playerGui.DescendantAdded:Connect(function(inst)
			link(inst)
			local parent = inst.Parent
			local shadow = parent and parent:FindFirstChild(inst.Name .. SUFFIX)
			if shadow then
				link(shadow)
			end
		end)
		for _, inst in ipairs(playerGui:GetDescendants()) do
			link(inst)
		end
	end)
end

return TextShadowController
