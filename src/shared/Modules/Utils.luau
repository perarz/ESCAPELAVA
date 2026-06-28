--!strict
-- Utils.luau
-- Drobne helpery używane w serwisach i kontrolerach.

local Utils = {}

-- "M:SS" — np. 125 → "2:05"
function Utils.formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local m = math.floor(s / 60)
	local sec = s % 60
	return string.format("%d:%02d", m, sec)
end

-- Zwraca HumanoidRootPart jeśli postać istnieje i jest spawned, inaczej nil.
function Utils.getRoot(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Zwraca Humanoid jeśli żywy.
function Utils.getHumanoid(player: Player): Humanoid?
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

-- Punkty rozsiane równomiernie po obwodzie kwadratu o danym radiusie.
function Utils.getRingPositions(count: number, radius: number, y: number): { Vector3 }
	local positions = {}
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		table.insert(positions, Vector3.new(x, y, z))
	end
	return positions
end

-- Bezpieczny iterator po Players.
function Utils.eachPlayer(callback: (Player) -> ())
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		callback(p)
	end
end

return Utils
