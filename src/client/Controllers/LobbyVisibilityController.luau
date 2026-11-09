--!strict
-- LobbyVisibilityController.luau (09.11) — z mapy nie widać lobby. Kacper: „ustaw zasięg, żeby
-- nie było widać z mapy, albo przenieś lobby” → wybrał chowanie lokalne, a później tego samego dnia
-- kazał też oddalić wyspę (brzeg ~505 studów od barier, wcześniej ~110). Sama odległość nie
-- wystarcza: plac nie ma mgły, chmur ani Atmosphere, więc wyspę szeroką na 370 studów widać z mapy,
-- gdziekolwiek stoi. Dlatego chowanie zostaje. Liczby: `Config.LobbyHide`.
--
-- REGUŁA: kamera TEGO gracza nad obszarem gry (pudło barier w XZ + margines, na każdej
-- wysokości) → lobby (`Roots`) i postacie innych stojące w lobby znikają z jego obrazu.
-- Liczy się kamera, nie postać: obserwujący (SPECTATE) stoi w lobby, a patrzy na mapę —
-- też ma nie widzieć wyspy. Sceny sklepów stoją pod mapą, w tym samym pudle XZ, ale są
-- zamknięte — tam nie chowamy (`SceneFloorY`), żeby wejście do sklepu nie przełączało tysięcy
-- partów lobby.
--
-- WYŁĄCZNIE OBRAZ (lekcja 10): `LocalTransparencyModifier` partów i decali, `Enabled` efektów.
-- Kolizja, promienie i rodzic zostają — dlatego obserwujący dalej stoi na niewidocznej wyspie
-- (przepięcie lobby poza Workspace zrzuciłoby go w przepaść, bo fizykę postaci liczy klient),
-- a prompty i napisy, które inne kontrolery znajdują po nazwie pod Workspace.Lobby, są tam,
-- gdzie były. Serwer i inni gracze o niczym nie wiedzą.
--
-- Przełączamy po aktualizacji kamery, przed klatką (`BindToRenderStep` za `Camera`), więc
-- teleport z mapy do lobby nie pokazuje ani jednej klatki pustki pod nogami.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local CFG = Config.LobbyHide

local LobbyVisibilityController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local hidden = false
local lastCheck = -math.huge

-- Pudło obszaru gry w XZ (Vector2: X, Z). Bariery stoją w miejscu, liczymy raz; bez barier
-- nigdy nie chowamy — lepiej widoczne lobby niż niewidoczna mapa.
local areaMin: Vector2? = nil
local areaMax: Vector2? = nil

-- Wartości sprzed schowania. Słabe klucze: zniszczony obiekt nie trzyma się w pamięci.
local savedLTM: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local savedEnabled: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local roots: { [Instance]: { RBXScriptConnection } } = {}
local hiddenChars: { [Model]: { RBXScriptConnection } } = {}

local function isEffect(inst: Instance): boolean
	return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
		or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles")
end

local function hideOne(inst: Instance)
	if inst:IsA("BasePart") or inst:IsA("Decal") then -- Texture dziedziczy po Decal
		if savedLTM[inst] == nil then
			local target = inst :: any
			savedLTM[inst] = target.LocalTransparencyModifier
			target.LocalTransparencyModifier = 1
		end
	elseif isEffect(inst) then
		if savedEnabled[inst] == nil then
			local target = inst :: any
			savedEnabled[inst] = target.Enabled
			target.Enabled = false
		end
	end
end

-- Przywraca tylko to, czego nikt w międzyczasie nie ruszył (nasza wartość nadal stoi) — inaczej
-- nadpisalibyśmy zmianę innego kontrolera.
local function showOne(inst: Instance)
	local ltm = savedLTM[inst]
	if ltm ~= nil then
		savedLTM[inst] = nil
		local target = inst :: any
		if target.LocalTransparencyModifier == 1 then target.LocalTransparencyModifier = ltm end
	end
	local enabled = savedEnabled[inst]
	if enabled ~= nil then
		savedEnabled[inst] = nil
		local target = inst :: any
		if target.Enabled == false then target.Enabled = enabled end
	end
end

local function hideTree(root: Instance)
	hideOne(root)
	for _, d in ipairs(root:GetDescendants()) do hideOne(d) end
end

local function showTree(root: Instance)
	showOne(root)
	for _, d in ipairs(root:GetDescendants()) do showOne(d) end
end

-- Schowana gałąź pilnuje zmian: nowe dzieci (serwer, założony item) też chowamy, a to, co z niej
-- wychodzi (item schowany do plecaka), odkrywamy od razu — inaczej zostałoby niewidoczne na mapie.
local function watch(root: Instance): { RBXScriptConnection }
	return {
		root.DescendantAdded:Connect(function(d)
			if hidden then hideOne(d) end
		end),
		root.DescendantRemoving:Connect(showOne),
	}
end

local function disconnectAll(conns: { RBXScriptConnection })
	for _, c in ipairs(conns) do c:Disconnect() end
end

local function computeArea(): boolean
	local folder = Utils.barrierFolder()
	if not folder then return false end
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Obrys obróconego pudła w osiach świata.
			local cf, h = d.CFrame, d.Size * 0.5
			local ex = math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y + math.abs(cf.ZVector.X) * h.Z
			local ez = math.abs(cf.XVector.Z) * h.X + math.abs(cf.YVector.Z) * h.Y + math.abs(cf.ZVector.Z) * h.Z
			local p = cf.Position
			minX, maxX = math.min(minX, p.X - ex), math.max(maxX, p.X + ex)
			minZ, maxZ = math.min(minZ, p.Z - ez), math.max(maxZ, p.Z + ez)
		end
	end
	if minX == math.huge then return false end
	areaMin, areaMax = Vector2.new(minX, minZ), Vector2.new(maxX, maxZ)
	return true
end

local function insideArea(pos: Vector3, margin: number): boolean
	local mn, mx = areaMin, areaMax
	if not mn or not mx then return false end
	return pos.X >= mn.X - margin and pos.X <= mx.X + margin
		and pos.Z >= mn.Y - margin and pos.Z <= mx.Y + margin
end

-- Gałęzie lobby z placu; podpinamy te, które dojechały później (wejście w trakcie replikacji).
local function trackRoots()
	for root, conns in pairs(roots) do
		if root.Parent == nil then
			disconnectAll(conns)
			roots[root] = nil
		end
	end
	for _, name in ipairs(CFG.Roots) do
		local root = Workspace:FindFirstChild(name)
		if root and not roots[root] then
			roots[root] = watch(root)
			if hidden then hideTree(root) end
		end
	end
end

local function showCharacter(char: Model)
	local conns = hiddenChars[char]
	if not conns then return end
	hiddenChars[char] = nil
	disconnectAll(conns)
	showTree(char)
end

-- Postacie innych daleko za barierą (w lobby). Własnej nie ruszamy — jej przezroczystość
-- prowadzi kamera Robloxa (pierwsza osoba), a z mapy i tak jej nie widać pod kamerą.
local function refreshCharacters()
	local want: { [Model]: boolean } = {}
	if hidden then
		for _, player in ipairs(Players:GetPlayers()) do
			if player == localPlayer then continue end
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if char and root and root:IsA("BasePart") and not insideArea(root.Position, CFG.CharacterMargin) then
				want[char] = true
			end
		end
	end
	for char in pairs(hiddenChars) do
		if not want[char] then showCharacter(char) end
	end
	for char in pairs(want) do
		if not hiddenChars[char] then
			hideTree(char)
			hiddenChars[char] = watch(char)
		end
	end
end

local function setHidden(on: boolean)
	if on == hidden then return end
	hidden = on
	for root in pairs(roots) do
		if on then hideTree(root) else showTree(root) end
	end
	refreshCharacters()
end

local function step()
	local now = os.clock()
	local periodic = now - lastCheck >= CFG.CheckInterval
	if periodic then
		lastCheck = now
		trackRoots()
		if not areaMin then computeArea() end
	end
	local cam = Workspace.CurrentCamera
	if not cam or not areaMin then return end
	local at = cam.CFrame.Position
	setHidden(at.Y > CFG.SceneFloorY and insideArea(at, CFG.PlayAreaMargin))
	if periodic and hidden then refreshCharacters() end
end

function LobbyVisibilityController.init()
	if initialized then return end
	initialized = true
	-- +2: po `MovementCamera` (Camera+1), który jeszcze przestawia kamerę (widok po spawnie w lobby).
	RunService:BindToRenderStep("LobbyVisibility", Enum.RenderPriority.Camera.Value + 2, step)
end

return LobbyVisibilityController
