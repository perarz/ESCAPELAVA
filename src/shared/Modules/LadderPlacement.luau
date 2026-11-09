--!strict
-- LadderPlacement.luau (09.11) — gdzie staje postawiona drabina. Od 09.11 item `bridge_builder`
-- stawia drabinę zamiast mostu (Kacper: „zamiast mostu drabinę, pochyloną i nie anchored —
-- możesz użyć jako drabinę, ale też most, bo stawiasz i spadnie w dół jako most”).
-- Jedno miejsce dla ducha (BridgeController) i serwera (BridgeService): gdyby liczyły osobno,
-- duch pokazywałby co innego, niż potem staje.
--
-- Model drabiny leży w assecie PŁASKO, wzdłuż lokalnej osi Z, ze szczeblami na wierzchu (+Y) —
-- jak most. Stawiamy go pochylonego o `Config.Bridge.LeanDegrees` od poziomu, dolnym końcem
-- w `foot` (punkt pod kursorem), w stronę `rotationY`; szczeble patrzą na wspinającego się.
--   * Ściana przed drabiną bliżej niż jej zasięg → stopa cofa się, aż wierzch oprze się o ścianę.
--     Bez tego drabina stawałaby wbita w mur, a fizyka wystrzeliłaby ją albo (przez
--     NoCollisionConstraint ze spawnu) puściła przez ścianę.
--   * Nic przed nią → po postawieniu przewraca się do przodu (środek ciężkości leży przed
--     stopą). Postawiona przy krawędzi nad przepaścią kładzie się na drugą stronę jak most.
-- Promienie idą wzdłuż drabiny (spód szyn i wierzch szczebli): środkiem i pod obiema szynami — pomiar
-- 09.11 na mapie: sam środkowy przegapiał słup/gzyms, w który wchodziła boczna szyna, a spawn
-- dawał jej wtedy NoCollisionConstraint z tą częścią (drabina przelatywała przez nią). Po
-- cofnięciu sprawdzamy jeszcze raz (`Passes`), bo cofnięta drabina może trafić w coś innego.
-- Niski murek pod drabiną też cofa stopę: wierzch staje wtedy nad murkiem, a fizyka kładzie
-- go na krawędzi — lepiej niż drabina wbita w murek.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local CFG = Config.Bridge

local LadderPlacement = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
-- Przez rzeczy bez kolizji postawiona drabina i tak przeleci — nie mogą jej odsuwać.
params.RespectCanCollide = true
local exclude: { Instance } = {}

-- Postacie (wszystkich, bo serwer nie ma „swojej”) i leżąca gotówka nie są ścianą: gracz
-- stojący przed drabiną nie może jej odpychać, a pojawiłby się u ducha i nie u serwera w tej
-- samej chwili. `extra` = to, czego nie ma u drugiej strony (duch, własna postać klienta).
local function buildExclude(extra: { Instance })
	table.clear(exclude)
	for _, inst in ipairs(extra) do
		table.insert(exclude, inst)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclude, player.Character) end
	end
	local cash = Workspace:FindFirstChild("ActiveCash")
	if cash then table.insert(exclude, cash) end
	params.FilterDescendantsInstances = exclude
end

-- CFrame środka obrysu drabiny (pod `Utils.setModelCenter` / pivot ducha) i stopa po
-- ewentualnym cofnięciu od ściany. `dims` = wymiary płasko leżącego modelu (X szerokość,
-- Y grubość, Z długość) — te same, co `ItemDefinitions.worldSize`.
function LadderPlacement.cframe(foot: Vector3, rotationY: number, dims: Vector3, extra: { Instance }): (CFrame, Vector3)
	local lean = math.rad(CFG.LeanDegrees)
	local rot = CFrame.Angles(0, math.rad(rotationY), 0) * CFrame.Angles(-lean, 0, 0)
	local axis = rot:VectorToWorldSpace(Vector3.zAxis) -- od stopy do wierzchu, wzdłuż spodu szyn
	local normal = rot:VectorToWorldSpace(Vector3.yAxis) -- strona szczebli: w górę i do tyłu
	local length = dims.Z

	buildExclude(extra)
	local right = rot:VectorToWorldSpace(Vector3.xAxis)
	local side = math.max(dims.X * 0.5 - CFG.RailInset, 0)
	local flatForward = Vector3.new(axis.X, 0, axis.Z).Unit
	local reach = length - CFG.FootLift
	for _ = 1, CFG.Passes do
		-- Najbliższe trafienie z trzech linii; start kawałek nad stopą, żeby nie trafić
		-- w podłogę, na której stoi.
		local nearest = math.huge
		-- Spód szyn i wierzch szczebli: gzyms wystający nad ścianą łapał tylko wierzch
		-- (pomiar 09.11: 2 z 50 ustawień przy ścianach, oba pod gzymsem).
		for _, lift in ipairs({ 0, dims.Y }) do
			for _, offset in ipairs({ 0, side, -side }) do
				local origin = foot + axis * CFG.FootLift + right * offset + normal * lift
				local hit = Workspace:Raycast(origin, axis * reach, params)
				if hit then
					nearest = math.min(nearest, CFG.FootLift + (hit.Position - origin):Dot(axis))
				end
			end
		end
		if nearest == math.huge then break end
		foot -= flatForward * ((length - nearest) * math.cos(lean) + CFG.WallGap)
		-- Cofnięta stopa siada na tym, co pod nią (krawężnik, stopień) — pomiar 09.11: bez tego
		-- dolny koniec wchodził w chodnik. Nic w zasięgu (za krawędzią dachu) → zostaje w miejscu
		-- i fizyka zrobi swoje.
		local ground = Workspace:Raycast(foot + Vector3.yAxis * CFG.FootSnap, Vector3.yAxis * (-2 * CFG.FootSnap), params)
		if ground then
			foot = Vector3.new(foot.X, ground.Position.Y, foot.Z)
		end
	end

	-- Dolna przednia krawędź modelu (z = −L/2, y = −h/2) ląduje dokładnie w stopie.
	local center = foot + axis * (length * 0.5) + normal * (dims.Y * 0.5)
	return CFrame.new(center) * rot, foot
end

return LadderPlacement
