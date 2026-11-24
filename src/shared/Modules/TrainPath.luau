--!strict
-- TrainPath.luau (24.11) — tor pociągu i to, gdzie jest skład w danej chwili. Wspólne dla serwera
-- (trafienia, pasażerowie) i klienta (obraz, dach), bo obie strony liczą pozycję same z czasu
-- serwera: dwie kopie tego wzoru = pociąg, który uderza obok tego, co widać.
--
-- KONTRAKT STUDIO: `Workspace.Map.Locked.TrainTunnels.West.Mouth` i `.East.Mouth` — BasePart,
-- środek torów na wysokości wierzchu szyn, dokładnie w wylocie tunelu. Tor to prosta między nimi.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.Train

local TrainPath = {}

export type Run = {
	start: Vector3, -- wylot, z którego wyjeżdża
	dir: Vector3,   -- kierunek jazdy (poziomy)
	length: number, -- od wylotu do wylotu
}

local function mouth(side: string): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local locked = map and map:FindFirstChild("Locked")
	local tunnels = locked and locked:FindFirstChild(CFG.TunnelsFolder)
	local tunnel = tunnels and tunnels:FindFirstChild(side)
	local part = tunnel and tunnel:FindFirstChild("Mouth")
	return if part and part:IsA("BasePart") then part else nil
end

-- reverse = jazda East → West. nil = brak tuneli w placu.
function TrainPath.get(reverse: boolean): Run?
	local west, east = mouth("West"), mouth("East")
	if not (west and east) then return nil end
	local from = if reverse then east.Position else west.Position
	local to = if reverse then west.Position else east.Position
	local delta = to - from
	if delta.Magnitude < 1 then return nil end
	return { start = from, dir = delta.Unit, length = delta.Magnitude }
end

function TrainPath.trainLength(): number
	return (CFG.CarCount - 1) * CFG.CarPitch + CFG.CarLength
end

-- Droga czoła pociągu od wylotu (ujemna = jeszcze w tunelu).
function TrainPath.headDistance(departAt: number, now: number): number
	return CFG.Speed * (now - departAt)
end

-- Środek wagonu `index` (1 = lokomotywa) wzdłuż toru.
function TrainPath.carCenter(index: number, head: number): number
	return head - CFG.CarLength * 0.5 - (index - 1) * CFG.CarPitch
end

function TrainPath.finished(run: Run, head: number): boolean
	return head > run.length + TrainPath.trainLength()
end

return TrainPath
