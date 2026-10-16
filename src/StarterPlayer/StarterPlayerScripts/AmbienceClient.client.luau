-- AmbienceClient (LocalScript) - lives in StarterPlayer > StarterPlayerScripts.
--
-- Plays the background sound (AmbienceConfig) forever, heard the same
-- everywhere. Rather than looping the clip as it is, each pass starts at a
-- random point near the beginning and fades into the next one before it
-- reaches the end, so there's no gap or click where it would repeat, and
-- no two passes line up exactly.
--
-- It also makes room for the lights: it dips while a light hums near you,
-- and drops right down while one flickers near you.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("AmbienceConfig"))

local rng = Random.new()

local clip = Instance.new("Sound")
clip.Name = "Ambience"
clip.SoundId = Config.SOUND
clip.Parent = SoundService
ContentProvider:PreloadAsync({ clip })
if clip.TimeLength <= 0 then
	warn(`[Ambience] Couldn't load {Config.SOUND}.`)
	return
end

local voices = {} -- { sound, startedAt, endsAt, fade }
local nextPassAt = 0
local joinedAt = os.clock()
local duck = 0 -- 0 = full volume, 1 = silent

-- How much to turn down for the lights right now. MapLightsClient publishes
-- how audible the nearest hum and flicker are (0-1) on SoundService.
local function getDuckTarget()
	local hum = SoundService:GetAttribute("HumPresence")
	local flicker = SoundService:GetAttribute("FlickerPresence")
	hum = if type(hum) == "number" then hum else 0
	flicker = if type(flicker) == "number" then flicker else 0
	return math.clamp(math.max(hum * Config.DUCK_UNDER_HUM, flicker * Config.DUCK_UNDER_FLICKER), 0, 1)
end

local function startPass(now)
	local first, last = Config.TRIM, clip.TimeLength - Config.TRIM
	local usable = last - first
	local fade = math.min(Config.CROSSFADE, usable / 3)
	-- Somewhere in the first third, so passes don't repeat exactly.
	local start = first + rng:NextNumber(0, usable / 3)

	local sound = clip:Clone()
	sound.Volume = 0
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(start, last)
	sound.Parent = SoundService
	sound:Play()

	local duration = last - start
	table.insert(voices, { sound = sound, startedAt = now, endsAt = now + duration, fade = fade })
	-- The next pass fades in while this one fades out.
	nextPassAt = now + duration - fade
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	if now >= nextPassAt then
		startPass(now)
	end

	-- Duck quickly when a light starts making noise, recover gently.
	local target = getDuckTarget()
	local seconds = if target > duck then Config.DUCK_ATTACK else Config.DUCK_RELEASE
	duck += (target - duck) * (1 - math.exp(-dt / math.max(seconds, 1e-3)))

	local volume = Config.VOLUME * math.clamp((now - joinedAt) / Config.FADE_IN, 0, 1) * (1 - duck)
	for i = #voices, 1, -1 do
		local voice = voices[i]
		if now >= voice.endsAt then
			voice.sound:Destroy()
			table.remove(voices, i)
		else
			local fadeIn = math.clamp((now - voice.startedAt) / voice.fade, 0, 1)
			local fadeOut = math.clamp((voice.endsAt - now) / voice.fade, 0, 1)
			-- Equal-power fades, so the crossfade isn't louder or quieter.
			voice.sound.Volume = volume * math.sqrt(math.min(fadeIn, fadeOut))
		end
	end
end)
