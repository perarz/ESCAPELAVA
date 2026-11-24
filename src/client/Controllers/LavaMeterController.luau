--!strict
-- LavaMeterController.luau (15.11) — pionowy pasek po prawej w rundzie: jak wysoko jest lawa
-- i gdzie jesteś ty (głowa awatara). Decyzje Kacpra 15.11: tylko ty (bez innych graczy),
-- znacznik = okrągła miniatura głowy, blisko lawy znacznik pulsuje na czerwono.
--
-- Zakres paska: lawa na starcie rundy = 15%, ulica = 25%, lawa na końcu rundy (limit gry) = 90%
-- (skala nierówna, patrz `frac`). Lawa i głowa czytane lokalnie co klatkę
-- (`Utils.lavaSurfaceY` — ta sama tafla, której używa drabina i pływanie), bez remote'ów.
-- Widoczność = atrybut uczestnika rundy (jak pasek zdrowia): od teleportu na mapę do śmierci.
--
-- KONTRAKT UI (Studio): `HUD.LavaMeter` (Visible=false, pokazuje kod) → `Track.Lava` (Frame,
-- Size.Y.Scale = wysokość lawy), `Marker` (Frame, Position.Y.Scale = wysokość głowy) z `Ring`
-- (UIStroke), `Pop` (UIScale) i `Avatar` (ImageLabel — miniaturę wstawia kod).
-- `Track.LavaBase` (zaokrąglony spód, wysokość = 2× zaokrąglenie) — kolumna `Lava` stoi na nim,
-- góra kwadratowa (15.11).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local CFG = Config.LavaMeter
local PARTICIPANT = Config.Spectate.ParticipantAttribute

local LavaMeterController = {}

local localPlayer = Players.LocalPlayer

type Ui = { root: GuiObject, lava: GuiObject, marker: GuiObject, ring: UIStroke?, pop: UIScale? }
local ui: Ui? = nil
local shown = false
local bottomY = CFG.FallbackBottomY
local markerFrac = 0
local lavaFrac = 0
local lavaPeak = -math.huge
local lavaEndY = CFG.FallbackBottomY + 120
local baseInset = 0 -- px: wysokość zaokrąglonego spodu (`LavaBase`), na którym stoi kolumna lawy
local initialized = false

-- Skala nierówna (15.11, Kacper): start lawy = `LavaStartFrac` paska (wypełnienie nigdy nie
-- jest cieńsze niż zaokrąglenie ramki), ulica = `StreetFrac`, a poziom lawy na KOŃCU rundy
-- (limit gry, liczony z Config.Lava) = `LavaEndFrac`. Nad nim zostaje `AboveEndRange` studów
-- do samej góry paska — na wypadek, gdyby ktoś był wyżej niż koniec lawy (hak, skok).
local function frac(y: number): number
	local startF, streetF, endF = CFG.LavaStartFrac, CFG.StreetFrac, CFG.LavaEndFrac
	if y <= bottomY then return startF end
	if y <= CFG.StreetY then
		return startF + (streetF - startF) * (y - bottomY) / math.max(0.5, CFG.StreetY - bottomY)
	end
	if y <= lavaEndY then
		return streetF + (endF - streetF) * (y - CFG.StreetY) / math.max(1, lavaEndY - CFG.StreetY)
	end
	return math.min(1, endF + (1 - endF) * (y - lavaEndY) / CFG.AboveEndRange)
end

-- Wysokość STÓP, nie głowy (15.11, Kacper: „przy chodzeniu się lekko buja”): głowa kołysze się
-- z animacją chodu, korzeń postaci nie. Stopy = korzeń − połowa korzenia − HipHeight, więc
-- stojąc na ulicy znacznik jest dokładnie na `StreetFrac`.
local function feetY(): number?
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and hum) then return nil end
	return root.Position.Y - root.Size.Y * 0.5 - hum.HipHeight
end

local function refreshShown()
	local on = localPlayer:GetAttribute(PARTICIPANT) == true
	if on == shown then return end
	shown = on
	if on then
		-- Dół paska = lawa teraz (start rundy), żeby pasek zaczynał się pusty i lawa w nim rosła.
		bottomY = Utils.lavaSurfaceY() or CFG.FallbackBottomY
		-- Koniec rundy = start + cały przyrost (rośnie liniowo od SpeedStart do SpeedEnd).
		local L = Config.Lava
		lavaEndY = math.min(L.MaxY, bottomY + L.RoundDuration * (L.SpeedStart + L.SpeedEnd) / 2)
		markerFrac, lavaFrac = -1, CFG.LavaStartFrac -- -1 = ustaw od razu w pierwszej klatce
		lavaPeak = bottomY
	end
	if ui then (ui :: Ui).root.Visible = on end
end

local function render(dt: number)
	local u = ui
	if not (u and shown) then return end
	local lavaY = Utils.lavaSurfaceY() or bottomY
	-- Tafla faluje w górę i w dół (`Lava.Wobble` z serwera), a w rundzie lawa tylko rośnie —
	-- pasek pokazuje najwyższy dotychczasowy poziom, więc nie skacze z każdą falą.
	lavaPeak = math.max(lavaPeak, lavaY)
	local footY = feetY() or lavaPeak

	local markerAlpha = math.min(1, dt / CFG.MarkerSmoothTime)
	local lavaAlpha = math.min(1, dt / CFG.LavaSmoothTime)
	local targetMarker = frac(footY)
	if markerFrac < 0 then
		markerFrac = targetMarker
	elseif math.abs(targetMarker - markerFrac) > CFG.MarkerDeadZone then
		markerFrac += (targetMarker - markerFrac) * markerAlpha
	end
	lavaFrac += (frac(lavaPeak) - lavaFrac) * lavaAlpha
	-- Kolumna lawy ma kwadratową górę i stoi na zaokrąglonym spodzie `LavaBase` (15.11) —
	-- jej wysokość to ułamek paska minus ten spód.
	u.lava.Size = UDim2.new(1, 0, lavaFrac, -baseInset)
	u.lava.Visible = true
	u.marker.Position = UDim2.fromScale(0.5, 1 - markerFrac)

	-- Blisko lawy: obwódka czerwona i znacznik pulsuje, mocniej im bliżej (stopy → tafla).
	local gap = footY - lavaY
	local danger = 1 - math.clamp(gap / CFG.WarnDistance, 0, 1)
	if danger > 0 then
		local wave = 0.5 + 0.5 * math.sin(os.clock() * CFG.PulseHz * math.pi * 2)
		if u.ring then u.ring.Color = Color3.new(0, 0, 0):Lerp(CFG.WarnColor, 0.4 + 0.6 * wave) end
		if u.pop then u.pop.Scale = 1 + CFG.PulseScale * danger * wave end
	else
		if u.ring then u.ring.Color = Color3.new(0, 0, 0) end
		if u.pop then u.pop.Scale = 1 end
	end
end

function LavaMeterController.init()
	if initialized then return end
	initialized = true

	-- Listenery najpierw (hard rule 9 / zasada init.client).
	localPlayer:GetAttributeChangedSignal(PARTICIPANT):Connect(refreshShown)
	RunService.RenderStepped:Connect(render)

	task.spawn(function()
		local hud = localPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD")
		local root = hud:WaitForChild("LavaMeter", 5)
		if not (root and root:IsA("GuiObject")) then
			warn("[LavaMeterController] HUD.LavaMeter nie istnieje — pasek lawy wyłączony")
			return
		end
		local lava = root:FindFirstChild("Lava", true)
		local marker = root:FindFirstChild("Marker")
		if not (lava and lava:IsA("GuiObject") and marker and marker:IsA("GuiObject")) then
			warn("[LavaMeterController] HUD.LavaMeter bez Track.Lava / Marker — pasek wyłączony")
			return
		end
		local base = root:FindFirstChild("LavaBase", true)
		baseInset = if base and base:IsA("GuiObject") then base.Size.Y.Offset / 2 else 0
		local ring = marker:FindFirstChild("Ring")
		local pop = marker:FindFirstChild("Pop")
		ui = {
			root = root,
			lava = lava,
			marker = marker,
			ring = if ring and ring:IsA("UIStroke") then ring else nil,
			pop = if pop and pop:IsA("UIScale") then pop else nil,
		}
		root.Visible = false
		shown = false
		refreshShown()

		-- Miniatura głowy: wywołanie sieciowe, może się nie udać — wtedy zostaje ciemne kółko.
		local avatar = marker:FindFirstChild("Avatar")
		if avatar and avatar:IsA("ImageLabel") then
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and type(image) == "string" then avatar.Image = image end
		end
	end)
end

return LavaMeterController
