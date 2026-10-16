-- PlayerConfig (ModuleScript) - lives in ReplicatedStorage.
-- Tweakable values for the player: camera, size and footsteps.

local Config = {
	---------------------------------------------------------------------------
	-- Camera and size (server)
	---------------------------------------------------------------------------

	-- Lock everyone into first person.
	FIRST_PERSON = true,

	-- How much bigger than a default character players are (1 = normal).
	-- Raises the camera too, so the map feels the right size around you.
	CHARACTER_SCALE = 1.25,

	---------------------------------------------------------------------------
	-- Footsteps (client)
	-- One sound per step, for every player. Sounds are played in a shuffled
	-- cycle: all of them once in a random order, then a new random order,
	-- never the same one twice in a row. Replaces Roblox's default running
	-- sound.
	---------------------------------------------------------------------------

	FOOTSTEP_SOUNDS = {
		"rbxassetid://5676510139", -- Concrete Footstep 1
		"rbxassetid://5676547800", -- Concrete Footstep 2
		"rbxassetid://5676568724", -- Concrete Footstep 3
		"rbxassetid://5676578760", -- Concrete Footstep 4
		"rbxassetid://5676583166", -- Concrete Footstep 5
	},
	FOOTSTEP_VOLUME = 0.6,
	-- Each step plays up to this much faster or slower, so it never sounds
	-- mechanical.
	FOOTSTEP_PITCH_VARIATION = 0.06,

	-- Studs travelled per step at normal size (scaled with the character).
	-- Keep this the same as STRIDE_LENGTH in FlashlightConfig so the
	-- flashlight bobs in time with your steps.
	STRIDE_LENGTH = 4.5,

	-- Other players' footsteps: full volume within MIN studs, silent beyond
	-- MAX.
	FOOTSTEP_MIN_DISTANCE = 5,
	FOOTSTEP_MAX_DISTANCE = 60,
}

return Config
