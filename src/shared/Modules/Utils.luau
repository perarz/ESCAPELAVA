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

return Utils
