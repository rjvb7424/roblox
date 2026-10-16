-- FlashlightVisuals (ModuleScript) - lives in ReplicatedStorage.
--
-- The parts of a flashlight you can see or hear, shared by the server (the
-- flashlight in every player's hand) and the clients (your first-person
-- flashlight, and the beams of everyone's flashlights).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FlashlightConfig"))
local LightUtil = require(ReplicatedStorage:WaitForChild("LightUtil"))

local Visuals = {}

local rng = Random.new()

local BLACK = Color3.new(0, 0, 0)
local LENS_OFF_COLOR = Color3.fromRGB(190, 200, 210)
local LENS_OFF_TRANSPARENCY = 0.3
-- Power below this counts as off.
local OFF = 0.001
-- Cylinder parts run along X; this turns them to run front to back (Z).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)

local DARK_METAL = Color3.fromRGB(30, 30, 33)

-- A ~30cm two-cell metal flashlight, front to back. `z` is how far behind
-- the front of the lens each piece starts, in studs.
local PIECES = {
	{ name = "Lens", z = 0, length = 0.01, diameter = 0.172, material = Enum.Material.Glass, color = LENS_OFF_COLOR },
	{
		name = "Reflector",
		z = 0.01,
		length = 0.006,
		diameter = 0.17,
		material = Enum.Material.Foil,
		color = Color3.fromRGB(215, 215, 220),
	},
	{
		name = "Bezel",
		z = 0.016,
		length = 0.035,
		diameter = 0.2,
		material = Enum.Material.Metal,
		color = Color3.fromRGB(110, 110, 115),
	},
	{ name = "Head", z = 0.051, length = 0.14, diameter = 0.188, material = Enum.Material.Metal, color = DARK_METAL },
	{ name = "Neck", z = 0.191, length = 0.06, diameter = 0.15, material = Enum.Material.Metal, color = DARK_METAL },
	{ name = "Body", z = 0.251, length = 0.53, diameter = 0.13, material = Enum.Material.Metal, color = DARK_METAL },
	{
		name = "Grip",
		z = 0.36,
		length = 0.25,
		diameter = 0.136,
		material = Enum.Material.DiamondPlate,
		color = Color3.fromRGB(40, 40, 43),
	},
	{
		name = "TailCap",
		z = 0.781,
		length = 0.055,
		diameter = 0.14,
		material = Enum.Material.Metal,
		color = DARK_METAL,
	},
	{
		name = "Button",
		z = 0.836,
		length = 0.018,
		diameter = 0.075,
		material = Enum.Material.Rubber,
		color = Color3.fromRGB(18, 18, 18),
	},
}
-- Where the hand holds it (the middle of the grip).
local GRIP_Z = 0.485

--------------------------------------------------------------------------------
-- The flashlight itself
--------------------------------------------------------------------------------

-- Builds a flashlight pointing forward (-Z). Its pivot is the front of the
-- lens. The "Body" part holds two attachments: "LensPoint" (where the light
-- comes out) and "GripPoint" (where it's held).
function Visuals.buildModel()
	local model = Instance.new("Model")
	model.Name = Config.MODEL_NAME

	local parts = {}
	for _, piece in PIECES do
		local part = Instance.new("Part")
		part.Name = piece.name
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(piece.length, piece.diameter, piece.diameter)
		part.CFrame = CFrame.new(0, 0, piece.z + piece.length / 2) * ALONG_Z
		part.Material = piece.material
		part.Color = piece.color
		part.Transparency = if piece.name == "Lens" then LENS_OFF_TRANSPARENCY else 0
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		part.Parent = model
		parts[piece.name] = part
	end

	local body = parts.Body
	for _, part in parts do
		if part ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
		end
	end

	for name, z in { LensPoint = -0.005, GripPoint = GRIP_Z } do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.CFrame = body.CFrame:ToObjectSpace(CFrame.new(0, 0, z))
		attachment.Parent = body
	end

	model.PrimaryPart = body
	model.WorldPivot = CFrame.identity
	return model
end

-- Makes the lens glow with the light, or go back to clear glass.
function Visuals.setLens(model, power, color)
	local lens = model and model:FindFirstChild("Lens")
	if not lens then
		return
	end
	if power > OFF then
		lens.Material = Enum.Material.Neon
		lens.Transparency = 0
		-- A nearly dead bulb still glows visibly even when it lights nothing.
		lens.Color = BLACK:Lerp(color, math.clamp(power, 0, 1) ^ 0.35)
	elseif lens.Material ~= Enum.Material.Glass then
		lens.Material = Enum.Material.Glass
		lens.Transparency = LENS_OFF_TRANSPARENCY
		lens.Color = LENS_OFF_COLOR
	end
end

--------------------------------------------------------------------------------
-- The beam
--------------------------------------------------------------------------------

local function createCarrier(name, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.05, 0.05, 0.05)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	-- MapLightsClient leaves lights marked like this alone.
	part:SetAttribute("MapLight", false)
	part.Parent = parent
	return part
end

local function createSpotLight(part, angle, shadows)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = angle
	light.Shadows = shadows
	light.Enabled = false
	light.Parent = part
	return light
end

-- Invisible parts carrying the beam's lights, parented to `parent` (somewhere
-- in Workspace). Remove with destroyBeam.
function Visuals.createBeam(name, shadows, parent)
	local part = createCarrier(name, parent)
	local bouncePart = createCarrier(name .. "Bounce", parent)

	local glow = Instance.new("PointLight")
	glow.Range = Config.GLOW_RANGE
	glow.Shadows = false
	glow.Enabled = false
	glow.Parent = part

	return {
		part = part,
		hotspot = createSpotLight(part, Config.HOTSPOT_ANGLE, shadows),
		spill = createSpotLight(part, Config.SPILL_ANGLE, shadows),
		glow = glow,
		bouncePart = bouncePart,
		-- Light bouncing back off whatever the beam hits.
		bounce = createSpotLight(bouncePart, 180, shadows),
	}
end

function Visuals.destroyBeam(beam)
	beam.part:Destroy()
	beam.bouncePart:Destroy()
end

-- Light bounced back off whatever the hotspot lands on, softly lighting the
-- room around it (a white wall close up lights a lot, a dark floor far away
-- barely any).
local function updateBounce(beam, origin, direction, power, color)
	local range = beam.hotspot.Range
	local result = LightUtil.findSurface(origin, direction, range, nil, 0, false)
	if not result or Config.BOUNCE_STRENGTH <= 0 then
		beam.bounce.Enabled = false
		return
	end
	local albedo = LightUtil.getSurfaceColor(result)
	local falloff = 1 - (result.Position - origin).Magnitude / range
	beam.bouncePart.CFrame = LightUtil.lookAlong(result.Position + result.Normal * Config.BOUNCE_OFFSET, result.Normal)
	beam.bounce.Brightness = Config.HOTSPOT_BRIGHTNESS
		* power
		* Config.BOUNCE_STRENGTH
		* LightUtil.luminance(albedo)
		* falloff
	beam.bounce.Range = Config.BOUNCE_RANGE
	beam.bounce.Color = LightUtil.normalize(LightUtil.multiply(color, albedo))
	beam.bounce.Enabled = true
end

-- `power` is light output (0 = off, 1 = a fresh battery).
function Visuals.setBeam(beam, origin, direction, power, color)
	local on = power > OFF
	if beam.hotspot.Enabled ~= on then
		beam.hotspot.Enabled = on
		beam.spill.Enabled = on
		beam.glow.Enabled = on
	end
	if not on then
		beam.bounce.Enabled = false
		return
	end

	beam.part.CFrame = LightUtil.lookAlong(origin, direction)

	-- How far you can see by a light goes with the square root of its power.
	local reach = 0.35 + 0.65 * math.sqrt(power)
	local tint = Config.SPILL_TINT

	beam.hotspot.Brightness = Config.HOTSPOT_BRIGHTNESS * power
	beam.hotspot.Range = Config.HOTSPOT_RANGE * reach
	beam.hotspot.Color = color

	beam.spill.Brightness = Config.SPILL_BRIGHTNESS * power
	beam.spill.Range = Config.SPILL_RANGE * reach
	beam.spill.Color = Color3.new(color.R * tint.R, color.G * tint.G, color.B * tint.B)

	beam.glow.Brightness = Config.GLOW_BRIGHTNESS * power
	beam.glow.Color = color

	updateBounce(beam, origin, direction, power, color)
end

--------------------------------------------------------------------------------
-- Sounds
--------------------------------------------------------------------------------

-- Plays a one-off sound. Parented to a part it's heard from there; parented
-- to SoundService it's heard by this client only, everywhere.
function Visuals.playSound(soundId, parent, volume, speed, maxLength)
	speed = speed or 1
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 2
	sound.RollOffMaxDistance = Config.CLICK_HEARING_DISTANCE
	if maxLength then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(0, maxLength)
	end
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- In case it never loads.
	Debris:AddItem(sound, (maxLength or 4) / speed + 1)
end

function Visuals.playClick(parent, on)
	local sounds = Config.CLICK_SOUNDS
	if #sounds == 0 then
		return
	end
	-- Clicking on is a touch sharper than clicking off.
	local speed = if on then rng:NextNumber(1, 1.06) else rng:NextNumber(0.9, 0.96)
	Visuals.playSound(sounds[rng:NextInteger(1, #sounds)], parent, Config.CLICK_VOLUME, speed)
end

return Visuals
