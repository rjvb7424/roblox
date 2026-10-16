-- AmbienceConfig (ModuleScript) - lives in ReplicatedStorage.
-- The constant background sound, heard the same everywhere.

local Config = {
	SOUND = "rbxassetid://8992983748", -- Cave Wind
	VOLUME = 0.2,

	-- The background makes room for the lights: it's turned down by up to
	-- this fraction while a light hums near you...
	DUCK_UNDER_HUM = 0.5,
	-- ...and by up to this much while a light flickers near you.
	DUCK_UNDER_FLICKER = 0.85,
	-- Seconds to duck down, and to come back up afterwards.
	DUCK_ATTACK = 0.25,
	DUCK_RELEASE = 1.5,

	-- It's looped by fading each pass into the next, so the very start and
	-- end of the clip (MP3s often have a short silence or click there) are
	-- never heard. Seconds each pass fades into the next:
	CROSSFADE = 2,
	-- Seconds skipped at the start and end of the clip.
	TRIM = 0.2,

	-- Seconds to fade in when you join.
	FADE_IN = 4,
}

return Config
