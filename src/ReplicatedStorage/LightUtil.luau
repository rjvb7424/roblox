-- LightUtil (ModuleScript) - lives in ReplicatedStorage.
-- Small helpers shared by the lighting scripts.

local LightUtil = {}

local WHITE = Color3.new(1, 1, 1)
local GREY = Color3.new(0.5, 0.5, 0.5)
-- Parts at least this transparent don't count as a surface light lands on.
local SEE_THROUGH_TRANSPARENCY = 0.5
local MAX_RAY_HOPS = 4

-- A CFrame at `origin` looking along `direction` (works straight up/down).
function LightUtil.lookAlong(origin, direction)
	local up = if math.abs(direction.Y) > 0.99 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(origin, origin + direction, up)
end

-- The first solid surface along a ray, or nil. Skips see-through parts,
-- anything closer than `minDistance` (e.g. the light's own fixture) and, if
-- `staticOnly`, anything unanchored (players, props).
function LightUtil.findSurface(origin, direction, distance, params, minDistance, staticOnly)
	local travelled = 0
	for _ = 1, MAX_RAY_HOPS do
		local result = workspace:Raycast(origin + direction * travelled, direction * (distance - travelled), params)
		if not result then
			return nil
		end
		local hit = result.Instance
		local along = (result.Position - origin).Magnitude
		if hit.Transparency < SEE_THROUGH_TRANSPARENCY and along > minDistance and (hit.Anchored or not staticOnly) then
			return result
		end
		travelled = along + 0.05
		if travelled >= distance then
			return nil
		end
	end
	return nil
end

function LightUtil.luminance(color)
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

-- The same hue at full intensity (brightest channel = 1).
function LightUtil.normalize(color)
	local brightest = math.max(color.R, color.G, color.B)
	if brightest <= 0 then
		return WHITE
	end
	return Color3.new(color.R / brightest, color.G / brightest, color.B / brightest)
end

function LightUtil.multiply(a, b)
	return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B)
end

-- The colour of the surface a raycast hit.
function LightUtil.getSurfaceColor(result)
	local hit = result.Instance
	if hit:IsA("Terrain") then
		local ok, color = pcall(hit.GetMaterialColor, hit, result.Material)
		return if ok then color else GREY
	end
	return hit.Color
end

-- Where a light shines from, which way it points (nil for PointLights), and
-- the part it's in. Returns nil if it isn't in the world.
function LightUtil.getLightSource(light)
	local parent = light.Parent
	local cframe, part
	if parent and parent:IsA("BasePart") then
		cframe, part = parent.CFrame, parent
	elseif parent and parent:IsA("Attachment") then
		cframe, part = parent.WorldCFrame, parent.Parent
	else
		return nil
	end

	if light:IsA("PointLight") then
		return cframe.Position, nil, part
	end

	local normal = Vector3.FromNormalId(light.Face)
	local direction = cframe:VectorToWorldSpace(normal)
	local origin = cframe.Position
	if light:IsA("SurfaceLight") and parent:IsA("BasePart") then
		-- Shines from the face itself, not the middle of the part.
		origin += direction * math.abs(normal:Dot(parent.Size)) / 2
	end
	return origin, direction, part
end

return LightUtil
