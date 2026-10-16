-- MapLightsClient (LocalScript) - lives in StarterPlayer > StarterPlayerScripts.
--
-- Makes the lights in your map look and sound like real ones:
--
--   * Soft edges: wider, dimmer copies of each spot and surface light, so
--     its cone fades out instead of ending in a hard line.
--   * Bounced light: a dim light where each light's beam lands, tinted by
--     that surface's colour, softly lighting the walls and ceiling around it.
--   * Hum: every fixture hums from where it is.
--   * Flicker: a fixture buzzes and crackles for as long as it flickers.
--
-- All of it follows the original light: when BlackoutClient flickers, dims
-- or kills a light, its soft light and hum do the same. The added lights
-- cast shadows, so rooms with no light stay pitch black.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local BlackoutConfig = require(ReplicatedStorage:WaitForChild("BlackoutConfig"))
local Config = require(ReplicatedStorage:WaitForChild("MapLightsConfig"))
local LightUtil = require(ReplicatedStorage:WaitForChild("LightUtil"))

local rng = Random.new()

-- Set to false on a light (or an ancestor) to leave it alone. Our own added
-- lights are marked this way too.
local MAP_LIGHT_ATTRIBUTE = "MapLight"
-- Set to false on a light (or an ancestor) to keep it silent.
local HUM_ATTRIBUTE = "Hum"
local CHECK_INTERVAL = 0.5
-- How audible the nearest hum / flicker is right now (0-1), published on
-- SoundService for AmbienceClient.
local HUM_PRESENCE_ATTRIBUTE = "HumPresence"
local FLICKER_PRESENCE_ATTRIBUTE = "FlickerPresence"
local SUMMARY_DELAY = 8
-- If no surface was found under a light (e.g. the floor hasn't streamed in
-- yet), look again after this long.
local BOUNCE_RETRY_TIME = 3
-- Hits this close to a light are its own fixture, not where it lands.
local FIXTURE_RADIUS = 1
local DOWN = -Vector3.yAxis

local fixtures = {} -- [Light] = fixture
local soundParents = {} -- [Instance] = true where a fixture already makes sound (one per part)

local folder = Instance.new("Folder")
folder.Name = "BouncedLight"
folder:SetAttribute(MAP_LIGHT_ATTRIBUTE, false)
folder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { folder }

--------------------------------------------------------------------------------
-- Which lights
--------------------------------------------------------------------------------

-- True if no ancestor (or the light itself) sets `attribute` to false.
local function isAllowed(light, attribute)
	local node = light
	while node and node ~= workspace do
		if node:GetAttribute(attribute) == false then
			return false
		end
		node = node.Parent
	end
	return node == workspace
end

-- Exit signs and anything else that shouldn't hum or crackle.
local function isSilent(light)
	if not isAllowed(light, HUM_ATTRIBUTE) then
		return true
	end
	local node = light
	while node and node ~= workspace do
		local name = string.lower(node.Name)
		for _, word in Config.SILENT_NAMES do
			if string.find(name, string.lower(word), 1, true) then
				return true
			end
		end
		node = node.Parent
	end
	-- Exit signs glow green.
	local color = light.Color
	return Config.SILENT_GREEN_LIGHTS and color.G > 0.3 and color.G > color.R * 1.5 and color.G > color.B * 1.5
end

local function isInCharacter(light)
	local model = light:FindFirstAncestorOfClass("Model")
	while model do
		if Players:GetPlayerFromCharacter(model) then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

--------------------------------------------------------------------------------
-- Added lights and sounds
--------------------------------------------------------------------------------

local function createRing(source, spec)
	local ring = Instance.new(source.ClassName)
	ring.Name = "SoftEdge"
	ring:SetAttribute(MAP_LIGHT_ATTRIBUTE, false)
	ring.Shadows = Config.SHADOWS
	ring.Enabled = false
	ring.Parent = source.Parent
	return { light = ring, angle = spec.Angle, brightness = spec.Brightness }
end

-- A hemisphere of dim light coming off the surface the light lands on.
local function createBounce(source, result, distance)
	local albedo = LightUtil.getSurfaceColor(result)
	local position = result.Position + result.Normal * Config.BOUNCE_OFFSET

	local part = Instance.new("Part")
	part.Name = "Bounce"
	part.Size = Vector3.new(0.05, 0.05, 0.05)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = LightUtil.lookAlong(position, result.Normal)

	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 180
	light.Shadows = Config.SHADOWS
	light.Enabled = false
	light.Parent = part
	part.Parent = folder

	return {
		part = part,
		light = light,
		albedo = albedo,
		-- Darker surfaces and longer throws bounce back less.
		strength = Config.BOUNCE_STRENGTH * LightUtil.luminance(albedo) * (1 - distance / source.Range),
	}
end

local function createHum(parent)
	local sound = Instance.new("Sound")
	sound.Name = "Hum"
	sound.SoundId = Config.HUM_SOUND
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = 1 + rng:NextNumber(-Config.HUM_PITCH_VARIATION, Config.HUM_PITCH_VARIATION)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Config.HUM_MIN_DISTANCE
	sound.RollOffMaxDistance = Config.HUM_MAX_DISTANCE
	sound.Parent = parent
	sound:Play()

	-- Start each one at a different point so they don't drone in unison.
	task.spawn(function()
		if not sound.IsLoaded then
			sound.Loaded:Wait()
		end
		if sound.Parent and sound.TimeLength > 0 then
			sound.TimePosition = rng:NextNumber(0, sound.TimeLength)
		end
	end)
	return sound
end

--------------------------------------------------------------------------------
-- Flicker sound
-- The clips end abruptly, so they're never looped as they are. Each one is
-- played with its end trimmed off and faded into the next (picked at
-- random, started at a random point, pitched slightly differently), for as
-- long as the fixture flickers.
--------------------------------------------------------------------------------

local flickerClips = {} -- loaded copies to clone from
for _, id in Config.FLICKER_SOUNDS do
	local clip = Instance.new("Sound")
	clip.Name = "FlickerClip"
	clip.SoundId = id
	clip.RollOffMode = Enum.RollOffMode.InverseTapered
	clip.RollOffMinDistance = Config.FLICKER_MIN_DISTANCE
	clip.RollOffMaxDistance = Config.FLICKER_MAX_DISTANCE
	clip.Parent = SoundService
	table.insert(flickerClips, clip)
end
task.spawn(ContentProvider.PreloadAsync, ContentProvider, flickerClips)

-- Power states in which every working light flickers.
local FLICKERING_STATES = { Failing = true, FalseHope = true, Restoring = true }
-- Seconds the first clip of a flicker takes to fade in (just enough to
-- avoid a click).
local ONSET_TIME = 0.02

-- How loud the fixture's flicker sound should be right now, or nil if it
-- isn't flickering.
local function getFlickerVolume(fixture, now)
	local light = fixture.light
	local working = light:GetAttribute(BlackoutConfig.WORKING_ATTRIBUTE)
	if working == nil then
		-- Lights outside the power system: for a moment after each cut or dim.
		return if now - fixture.lastDrop < Config.FLICKER_SOUND_HOLD then Config.FLICKER_VOLUME else nil
	end
	if not working then
		return nil
	end

	local power = ReplicatedStorage:FindFirstChild(BlackoutConfig.POWER_FOLDER_NAME)
	local state = power and power:GetAttribute("State")
	if state == "On" then
		-- Just this fixture faulting (or a jumpscare).
		local serverNow = workspace:GetServerTimeNow()
		local startedAt, endsAt = light:GetAttribute("FaultStartedAt"), light:GetAttribute("FaultEndsAt")
		if
			type(startedAt) == "number"
			and type(endsAt) == "number"
			and startedAt <= serverNow
			and serverNow < endsAt
		then
			return if light:GetAttribute("FaultKind") == "Scare" then Config.JUMPSCARE_VOLUME else Config.FLICKER_VOLUME
		end
		return nil
	end
	return if FLICKERING_STATES[state] then Config.FLICKER_VOLUME else nil
end

local function startVoice(fixture, now, volume)
	-- The first clip of a flicker starts abruptly, like the flicker itself;
	-- the rest crossfade into each other.
	local continuing = false
	for _, voice in fixture.voices do
		continuing = continuing or not voice.stopAt
	end

	local loaded = {}
	for _, clip in flickerClips do
		if clip.TimeLength > 0 then
			table.insert(loaded, clip)
		end
	end
	if #loaded == 0 then
		return
	end

	local clip = loaded[rng:NextInteger(1, #loaded)]
	local stop = clip.TimeLength - Config.FLICKER_END_TRIM
	local fade = math.min(Config.FLICKER_CROSSFADE, stop / 4)
	-- Somewhere in the first half, leaving room for both fades.
	local start = rng:NextNumber(0, math.max(stop / 2 - fade, 0))
	local speed = 1 + rng:NextNumber(-Config.FLICKER_PITCH_VARIATION, Config.FLICKER_PITCH_VARIATION)

	local sound = clip:Clone()
	sound.Volume = 0
	sound.PlaybackSpeed = speed
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(start, stop)
	sound.Parent = fixture.soundParent
	sound:Play()

	local duration = (stop - start) / speed
	table.insert(fixture.voices, {
		sound = sound,
		volume = volume,
		startedAt = now,
		endsAt = now + duration,
		fadeIn = if continuing then fade else ONSET_TIME,
		fade = fade,
		stopAt = nil,
	})
	-- The next clip fades in while this one fades out.
	fixture.nextVoiceAt = now + duration - fade
end

-- `volume` is nil when the fixture isn't flickering.
local function updateFlickerSound(fixture, volume, now)
	local flickering = volume ~= nil
	if flickering then
		if now >= fixture.nextVoiceAt then
			startVoice(fixture, now, volume)
		end
	else
		fixture.nextVoiceAt = 0
	end

	for i = #fixture.voices, 1, -1 do
		local voice = fixture.voices[i]
		if not flickering and not voice.stopAt then
			voice.stopAt = now
		end
		local fadeIn = math.clamp((now - voice.startedAt) / voice.fadeIn, 0, 1)
		local fadeOut = math.clamp((voice.endsAt - now) / voice.fade, 0, 1)
		local stopping = if voice.stopAt
			then math.clamp(1 - (now - voice.stopAt) / Config.FLICKER_FADE_OUT, 0, 1)
			else 1
		local level = math.min(fadeIn, fadeOut, stopping)
		if level <= 0 and now > voice.startedAt then
			voice.sound:Destroy()
			table.remove(fixture.voices, i)
		else
			-- Equal-power fades, so two overlapping clips aren't louder or
			-- quieter than one.
			voice.sound.Volume = voice.volume * math.sqrt(level)
		end
	end
end

--------------------------------------------------------------------------------
-- Following the original light
--------------------------------------------------------------------------------

local function sync(fixture)
	local light = fixture.light
	local brightness = light.Brightness
	local on = light.Enabled and brightness > 0
	-- BlackoutClient dims lights by lowering Brightness and says what's
	-- normal. Other lights: the brightest it's been.
	local normal = light:GetAttribute("NormalBrightness")
	fixture.normal = if type(normal) == "number" then normal else math.max(fixture.normal, brightness)
	local level = if on and fixture.normal > 0 then math.min(brightness / fixture.normal, 1) else 0
	local drawn = on and fixture.near

	for _, ring in fixture.rings do
		local copy = ring.light
		copy.Enabled = drawn
		if drawn then
			copy.Face = light.Face
			copy.Angle = math.min(light.Angle + ring.angle, 180)
			copy.Range = light.Range
			copy.Color = light.Color
			copy.Brightness = brightness * ring.brightness
		end
	end

	local bounce = fixture.bounce
	if bounce then
		bounce.light.Enabled = drawn
		if drawn then
			bounce.light.Range = light.Range * Config.BOUNCE_RANGE
			bounce.light.Color = LightUtil.normalize(LightUtil.multiply(light.Color, bounce.albedo))
			bounce.light.Brightness = brightness * bounce.strength
		end
	end

	if fixture.hum then
		fixture.hum.Volume = Config.HUM_VOLUME * level
	end
	if fixture.level > Config.FLICKER_SOUND_LEVEL and level <= Config.FLICKER_SOUND_LEVEL then
		fixture.lastDrop = os.clock()
	end
	fixture.level = level
end

local function tryAddBounce(fixture, now)
	local light = fixture.light
	if fixture.bounce or now < fixture.nextBounceTry or light.Range < Config.MIN_RANGE then
		return
	end
	if Config.BOUNCE_STRENGTH <= 0 then
		return
	end
	fixture.nextBounceTry = now + BOUNCE_RETRY_TIME

	local origin, direction = LightUtil.getLightSource(light)
	if not origin then
		return
	end
	-- Where the middle of the beam lands; for PointLights, the floor below.
	local result = LightUtil.findSurface(origin, direction or DOWN, light.Range, rayParams, FIXTURE_RADIUS, true)
	if result then
		fixture.bounce = createBounce(light, result, (result.Position - origin).Magnitude)
		sync(fixture)
	end
end

--------------------------------------------------------------------------------
-- Lights coming and going (also as they stream in and out)
--------------------------------------------------------------------------------

local function register(light)
	if fixtures[light] or not light:IsA("Light") then
		return
	end
	if not isAllowed(light, MAP_LIGHT_ATTRIBUTE) or isInCharacter(light) then
		return
	end
	if not LightUtil.getLightSource(light) then
		return
	end

	local fixture = {
		light = light,
		rings = {},
		bounce = nil,
		hum = nil,
		-- Where this fixture's sounds play from (nil if another light in
		-- the same part already makes them, or it's silenced).
		soundParent = nil,
		voices = {},
		nextVoiceAt = 0,
		normal = 0,
		level = 0,
		lastDrop = -math.huge,
		near = false,
		nextBounceTry = 0,
		connection = nil,
	}

	local cone = light:IsA("SpotLight") or light:IsA("SurfaceLight")
	if cone and light.Range >= Config.MIN_RANGE and light.Angle < 179 then
		for _, spec in Config.SOFT_EDGE_RINGS do
			table.insert(fixture.rings, createRing(light, spec))
		end
	end

	local parent = light.Parent
	fixture.silent = isSilent(light)
	if not soundParents[parent] and not fixture.silent then
		soundParents[parent] = true
		fixture.soundParent = parent
		if Config.HUM_SOUND ~= "" then
			fixture.hum = createHum(parent)
		end
	end

	fixture.connection = light.Changed:Connect(function()
		sync(fixture)
	end)
	fixtures[light] = fixture
	sync(fixture)
end

local function unregister(light)
	local fixture = fixtures[light]
	if not fixture then
		return
	end
	fixtures[light] = nil
	fixture.connection:Disconnect()
	for _, ring in fixture.rings do
		ring.light:Destroy()
	end
	if fixture.bounce then
		fixture.bounce.part:Destroy()
	end
	if fixture.hum then
		fixture.hum:Destroy()
	end
	for _, voice in fixture.voices do
		voice.sound:Destroy()
	end
	if fixture.soundParent then
		soundParents[fixture.soundParent] = nil
	end
end

-- 1 within `near` studs, fading to 0 at `far`: roughly how much of a sound
-- reaches the listener.
local function audibility(distance, near, far)
	return math.clamp((far - distance) / math.max(far - near, 1e-3), 0, 1)
end

local function updateSounds()
	local now = os.clock()
	local cameraPosition = workspace.CurrentCamera.CFrame.Position

	local distances = {} -- [fixture] = studs from the camera
	local flickering = {}
	local humPresence = 0
	for light, fixture in fixtures do
		if fixture.soundParent then
			local origin = LightUtil.getLightSource(light)
			local distance = if origin then (origin - cameraPosition).Magnitude else math.huge
			distances[fixture] = distance

			local volume = if distance < Config.FLICKER_MAX_DISTANCE then getFlickerVolume(fixture, now) else nil
			if volume then
				table.insert(flickering, { fixture = fixture, distance = distance, volume = volume })
			end
			if fixture.hum and Config.HUM_VOLUME > 0 then
				local heard = fixture.hum.Volume
					/ Config.HUM_VOLUME
					* audibility(distance, Config.HUM_MIN_DISTANCE, Config.HUM_MAX_DISTANCE)
				humPresence = math.max(humPresence, heard)
			end
		end
	end

	-- Only the nearest few play, so the whole map flickering at once doesn't
	-- turn into a wall of noise.
	table.sort(flickering, function(a, b)
		return a.distance < b.distance
	end)
	local playing = {} -- [fixture] = volume
	for i = 1, math.min(#flickering, Config.MAX_FLICKER_SOUNDS) do
		playing[flickering[i].fixture] = flickering[i].volume
	end

	local flickerPresence = 0
	for fixture, distance in distances do
		updateFlickerSound(fixture, playing[fixture], now)
		local loudest = 0
		for _, voice in fixture.voices do
			loudest = math.max(loudest, voice.sound.Volume / Config.FLICKER_VOLUME)
		end
		local heard = loudest * audibility(distance, Config.FLICKER_MIN_DISTANCE, Config.FLICKER_MAX_DISTANCE)
		flickerPresence = math.max(flickerPresence, math.min(heard, 1))
	end

	-- AmbienceClient turns the background down to make room for these.
	SoundService:SetAttribute(HUM_PRESENCE_ATTRIBUTE, humPresence)
	SoundService:SetAttribute(FLICKER_PRESENCE_ATTRIBUTE, flickerPresence)
end

-- Draws soft light only near the camera, and finds where lights land.
local function check()
	local now = os.clock()
	local cameraPosition = workspace.CurrentCamera.CFrame.Position
	for light, fixture in fixtures do
		local origin = LightUtil.getLightSource(light)
		local near = origin ~= nil and (origin - cameraPosition).Magnitude < Config.DRAW_DISTANCE
		if near then
			tryAddBounce(fixture, now)
		end
		if near ~= fixture.near then
			fixture.near = near
			sync(fixture)
		end
	end
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

workspace.DescendantAdded:Connect(register)
workspace.DescendantRemoving:Connect(unregister)
for _, inst in workspace:GetDescendants() do
	register(inst)
end
RunService.Heartbeat:Connect(updateSounds)

check()

-- Reported after a few seconds, once the map has streamed in around you.
task.delay(SUMMARY_DELAY, function()
	local count, rings, bounces, hums, silent = 0, 0, 0, 0, {}
	for light, fixture in fixtures do
		count += 1
		rings += #fixture.rings
		bounces += if fixture.bounce then 1 else 0
		hums += if fixture.hum then 1 else 0
		if fixture.silent then
			table.insert(silent, light:GetFullName())
		end
	end
	print(
		`[MapLights] {count} light(s): {rings} soft edge(s), {bounces} bounce light(s), {hums} humming, `
			.. `{#silent} silent{if #silent > 0
				then " (e.g. " .. table.concat(silent, ", ", 1, math.min(#silent, 4)) .. ")"
				else ""}.`
	)
end)

while true do
	task.wait(CHECK_INTERVAL)
	check()
end
