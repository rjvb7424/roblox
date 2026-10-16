-- DarknessClient (LocalScript) - lives in StarterPlayer > StarterPlayerScripts.
--
-- Simulates the player's eyes. The server has already removed every source
-- of light that isn't a real light, so unlit areas are pure black. This
-- script decides how the LIT areas look:
--
--   * Eye adaptation: step from a bright room into a dim one and it's nearly
--     black at first, then slowly opens up. Step back into the light (or have
--     the power come back) and it's blinding for a moment.
--   * Night vision: once the eyes are dark-adapted, colour drains away and
--     shifts slightly blue, like it does in real life.
--   * Glare around bright lights, and a black floor so light falls off into
--     pure black rather than grey.
--
-- A script can't read how bright the screen is, so the light reaching the
-- eyes is estimated from nearby lights that have a clear line of sight.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("DarknessConfig"))
local LightUtil = require(ReplicatedStorage:WaitForChild("LightUtil"))

local player = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
-- What total darkness counts as when measuring (log2 of 0 is -infinity).
local MIN_LIGHT = 1e-3
-- Parts at least this transparent, or with CastShadow off, let light through.
local SEE_THROUGH_TRANSPARENCY = 0.5
-- Hits this close to a light are its own fixture (bulb, lampshade), not a
-- wall in the way.
local FIXTURE_RADIUS = 1
local MAX_RAY_HOPS = 4

local lights = {} -- [Light] = true

local function lerp(a, b, t)
	return a + (b - a) * t
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "DarknessEyes"
colorCorrection.Brightness = -Config.BLACK_CRUSH
colorCorrection.Contrast = Config.CONTRAST
colorCorrection.Saturation = Config.SATURATION
colorCorrection.Parent = Lighting

local bloom = Instance.new("BloomEffect")
bloom.Name = "DarknessGlare"
bloom.Intensity = Config.BLOOM_INTENSITY
bloom.Size = Config.BLOOM_SIZE
bloom.Threshold = Config.BLOOM_THRESHOLD
bloom.Parent = Lighting

--------------------------------------------------------------------------------
-- Measuring light
--------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function onCharacterAdded(character)
	-- Your own body shouldn't block the light reaching your eyes.
	rayParams.FilterDescendantsInstances = { character }
end

-- Whether light can travel from a light at `origin` to `target`.
local function canReach(origin, target, lightPart)
	local offset = target - origin
	if offset.Magnitude < 1e-3 then
		return true
	end
	local from = origin
	local direction = offset.Unit
	for _ = 1, MAX_RAY_HOPS do
		local remaining = (target - from):Dot(direction)
		if remaining <= 0 then
			return true
		end
		local result = workspace:Raycast(from, direction * remaining, rayParams)
		if not result then
			return true
		end
		local hit = result.Instance
		local blocks = hit ~= lightPart
			and hit.CastShadow
			and hit.Transparency < SEE_THROUGH_TRANSPARENCY
			and (result.Position - origin).Magnitude > FIXTURE_RADIUS
		if blocks then
			return false
		end
		from = result.Position + direction * 0.05
	end
	return true
end

-- Roughly how much light falls on `point`. 1 is about what a Brightness 1
-- white light gives right next to it.
local function lightAt(point)
	local total = 0
	for light in lights do
		if not light.Enabled or light.Brightness <= 0 then
			continue
		end
		local origin, direction, part = LightUtil.getLightSource(light)
		if not origin then
			continue
		end

		local offset = point - origin
		local distance = offset.Magnitude
		if distance >= light.Range then
			continue
		end
		if direction and distance > 0 and direction:Dot(offset / distance) < math.cos(math.rad(light.Angle / 2)) then
			continue
		end
		if not canReach(origin, point, part) then
			continue
		end

		local falloff = 1 - distance / light.Range
		total += light.Brightness * LightUtil.luminance(light.Color) * falloff * falloff
	end
	return total
end

-- Light at the eyes and on whatever they're looking at, averaged.
local function measureScene()
	local camera = workspace.CurrentCamera
	local eye = camera.CFrame.Position
	local atEye = lightAt(eye)

	local atView = 0
	local result = workspace:Raycast(eye, camera.CFrame.LookVector * Config.EYE_VIEW_DISTANCE, rayParams)
	if result then
		atView = lightAt(result.Position + result.Normal * 0.1)
	end

	return (atEye + atView) / 2, atEye, atView
end

--------------------------------------------------------------------------------
-- Adapting
--------------------------------------------------------------------------------

local referenceStops = math.log(Config.EYE_REFERENCE_LIGHT, 2)
local exposureRange = Config.EYE_EXPOSURE_RANGE

-- The exposure the eyes are heading towards for this much light.
local function targetExposure(light)
	local stops = math.log(math.max(light, MIN_LIGHT), 2)
	return math.clamp((referenceStops - stops) * Config.EYE_ADAPT_STRENGTH, exposureRange.Min, exposureRange.Max)
end

local exposure = nil -- set from the first measurement, so there's no flash on spawn
local target = 0
local sinceMeasure = math.huge
local sinceLog = 0

local function update(dt)
	sinceMeasure += dt
	if sinceMeasure >= 1 / Config.EYE_UPDATE_RATE then
		sinceMeasure = 0
		local light, atEye, atView = measureScene()
		target = targetExposure(light)

		if Config.DEBUG then
			sinceLog += 1 / Config.EYE_UPDATE_RATE
			if sinceLog >= 1 then
				sinceLog = 0
				print(
					string.format(
						"[Darkness] light eye %.3f view %.3f | exposure %+.2f -> %+.2f",
						atEye,
						atView,
						exposure or target,
						target
					)
				)
			end
		end
	end

	if exposure == nil then
		exposure = target
	end

	-- Opening up (getting used to the dark) is slow; closing down is fast.
	local seconds = if target > exposure then Config.DARK_ADAPT_TIME else Config.LIGHT_ADAPT_TIME
	-- 3 time constants = 95% of the way there.
	exposure += (target - exposure) * (1 - math.exp(-3 * dt / math.max(seconds, 1e-3)))
	Lighting.ExposureCompensation = exposure

	-- 0 in normal light, 1 once the eyes are fully dark-adapted.
	local nightVision = if exposureRange.Max > 0 then math.clamp(exposure / exposureRange.Max, 0, 1) else 0
	colorCorrection.Saturation = lerp(Config.SATURATION, Config.NIGHT_VISION_SATURATION, nightVision)
	colorCorrection.TintColor = WHITE:Lerp(Config.NIGHT_VISION_TINT, nightVision)
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

local function onDescendantAdded(inst)
	if inst:IsA("Light") then
		lights[inst] = true
	end
end

-- Also fires as lights stream in and out.
workspace.DescendantAdded:Connect(onDescendantAdded)
workspace.DescendantRemoving:Connect(function(inst)
	lights[inst] = nil
end)
for _, inst in workspace:GetDescendants() do
	onDescendantAdded(inst)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

RunService.RenderStepped:Connect(update)
