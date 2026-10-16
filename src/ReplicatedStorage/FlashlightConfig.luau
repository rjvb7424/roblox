-- FlashlightConfig (ModuleScript) - lives in ReplicatedStorage.
-- Every tweakable value for the flashlight. Shared by the server (hands out
-- flashlights and spare batteries, relays what everyone's flashlight is
-- doing) and the client (simulates the flashlight itself).
--
-- Ranges use NumberRange.new(min, max); a random value in that range is
-- picked each time.

local Config = {
	---------------------------------------------------------------------------
	-- Setup
	-- Your own scripts can change these Player attributes on the server at
	-- any time, e.g. to make players find the flashlight or pick up batteries.
	---------------------------------------------------------------------------

	-- Player attribute "HasFlashlight" (true/false): whether they're holding one.
	START_WITH_FLASHLIGHT = true,
	-- Player attribute "FlashlightBatteries" (number): spare batteries carried.
	START_SPARE_BATTERIES = 1,
	-- Player attribute "Fear" (0-1), if your game sets it: hands shake more.

	TOGGLE_KEYS = { Enum.KeyCode.F, Enum.KeyCode.DPadUp },
	SWAP_BATTERY_KEYS = { Enum.KeyCode.R, Enum.KeyCode.DPadDown },

	---------------------------------------------------------------------------
	-- The bulb
	---------------------------------------------------------------------------

	-- "Incandescent": an old warm-white bulb. Dims gradually and turns orange
	--   as the battery dies, takes a moment to warm up, glows as it cools.
	-- "LED": cold white. Stays at full brightness, then blinks a warning and
	--   drops to a dim low mode, then gives out.
	BULB = "Incandescent",

	-- Colour of the light on a fresh battery.
	INCANDESCENT_COLOR = Color3.fromRGB(255, 228, 188),
	LED_COLOR = Color3.fromRGB(228, 238, 255),
	-- Filament temperature on a fresh battery. The colour shifts from this
	-- towards orange and red as the voltage drops.
	INCANDESCENT_KELVIN = 2900,

	-- Seconds for the filament to heat up and to cool down.
	WARM_UP_TIME = 0.06,
	COOL_DOWN_TIME = 0.14,

	---------------------------------------------------------------------------
	-- The beam
	-- A real beam is a bright, tight hotspot inside a wide, dim spill.
	---------------------------------------------------------------------------

	HOTSPOT_ANGLE = 22,
	HOTSPOT_BRIGHTNESS = 3,
	HOTSPOT_RANGE = 60,

	SPILL_ANGLE = 75,
	SPILL_BRIGHTNESS = 0.6,
	SPILL_RANGE = 28,
	-- The spill is slightly warmer than the hotspot, like real reflectors.
	SPILL_TINT = Color3.fromRGB(255, 244, 228),

	-- Light leaking out around the head, which lights up the flashlight and
	-- your hand.
	GLOW_BRIGHTNESS = 0.35,
	GLOW_RANGE = 2.5,

	-- Light bouncing back off whatever the beam hits, softly lighting the
	-- room around it: point it at a white wall up close and the whole room
	-- lights up a little, at a dark floor far away and barely at all.
	-- Strength is a fraction of the hotspot's brightness; 0 = off.
	BOUNCE_STRENGTH = 0.4,
	BOUNCE_RANGE = 14,
	-- Studs off the surface the bounced light comes from.
	BOUNCE_OFFSET = 0.4,

	-- Floating dust that only shows up inside the beam. Turn off if it
	-- doesn't suit your map.
	DUST = true,
	DUST_RATE = 25,

	---------------------------------------------------------------------------
	-- Batteries
	---------------------------------------------------------------------------

	-- Seconds the flashlight can be on before the battery is flat.
	BATTERY_LIFE = 480,
	-- A tired battery droops further the longer it's on, and recovers some
	-- of it while it rests: switch a dying flashlight off for a bit and it
	-- comes back brighter for a while. 0 = no droop.
	BATTERY_SAG = 0.12,
	SAG_TIME = 20,
	RECOVER_TIME = 30,

	-- Battery level (as a fraction of fresh voltage) below which an
	-- incandescent bulb starts wavering and the contacts get unreliable.
	LOW_VOLTAGE = 0.6,
	-- How much a weak battery makes the brightness waver (0-1).
	LOW_BATTERY_WAVER = 0.3,

	-- LED only: voltage where it steps down to low mode, and where it dies.
	LED_STEP_DOWN_VOLTAGE = 0.5,
	LED_CUTOFF_VOLTAGE = 0.3,
	LED_LOW_LEVEL = 0.25,

	-- Seconds it takes to unscrew the cap and swap the batteries. The light
	-- is off the whole time.
	BATTERY_SWAP_TIME = 2.6,

	---------------------------------------------------------------------------
	-- Loose contacts
	---------------------------------------------------------------------------

	-- Random flickers per second with a good battery, plus extra as it dies.
	FLICKER_RATE = 1 / 150,
	LOW_BATTERY_FLICKER_RATE = 1 / 6,
	-- Chance that a flicker ends with the light cutting out completely, until
	-- you click it off and on again.
	CUT_OUT_CHANCE = 0.12,
	-- Chance that clicking it off and on again fixes a cut-out. If not, it
	-- blips and dies again; keep trying.
	CLICK_FIX_CHANCE = 0.55,

	-- Landing from a jump or fall jolts the contacts. Scaled by how hard you
	-- land.
	JOLT_FLICKER_CHANCE = 0.4,
	JOLT_CUT_OUT_CHANCE = 0.2,

	-- What a flicker looks like: this many quick cuts.
	FLICKER_COUNT = NumberRange.new(2, 7),
	FLICKER_OFF_TIME = NumberRange.new(0.02, 0.12),
	FLICKER_ON_TIME = NumberRange.new(0.03, 0.18),

	---------------------------------------------------------------------------
	-- Holding it
	---------------------------------------------------------------------------

	-- First person: where the lens sits relative to the camera
	-- (right, up, back). The flashlight is drawn there.
	HOLD_OFFSET = Vector3.new(0.6, -0.55, -1.25),
	SHOW_IN_FIRST_PERSON = true,

	-- How the hand follows where you look. Higher stiffness = snappier;
	-- lower damping = more overshoot when you stop turning.
	HAND_STIFFNESS = 170,
	HAND_DAMPING = 19,

	-- Multipliers for each kind of hand movement (0 = off, 1 = normal).
	WALK_BOB = 1,
	BREATHING = 1,
	TREMOR = 1,
	-- Studs per footstep at normal size, for timing the bob. Keep it the same
	-- as STRIDE_LENGTH in PlayerConfig so it matches your footsteps.
	STRIDE_LENGTH = 4.5,

	-- The beam aims at whatever you're looking at, up to this far away.
	AIM_DISTANCE = 120,
	MIN_AIM_DISTANCE = 4,

	---------------------------------------------------------------------------
	-- Sounds
	-- From Roblox's official sound library (ProSoundEffects), free in any
	-- game. Swap in your own if you prefer.
	---------------------------------------------------------------------------

	-- A random one plays on every click, so no two sound exactly alike.
	CLICK_SOUNDS = {
		"rbxassetid://9114479678",
		"rbxassetid://9114479665",
		"rbxassetid://9114479661",
		"rbxassetid://9114479852",
		"rbxassetid://9114479860",
		"rbxassetid://9114479857",
		"rbxassetid://9114479976",
		"rbxassetid://9114480094",
		"rbxassetid://9114480109",
		"rbxassetid://9114480110",
	},
	CLICK_VOLUME = 0.5,
	-- How far away other players can hear your clicks.
	CLICK_HEARING_DISTANCE = 40,

	-- Played during a battery swap. At = seconds after starting; MaxLength
	-- cuts the sound short (nil = play it all).
	BATTERY_SWAP_SOUNDS = {
		{ At = 0.1, Id = "rbxassetid://9126098644", Volume = 0.4, MaxLength = 1.1 }, -- cap off
		{ At = 1.0, Id = "rbxassetid://9113577259", Volume = 0.35, MaxLength = 0.7 }, -- old batteries out
		{ At = 1.6, Id = "rbxassetid://9113577259", Volume = 0.35, MaxLength = 0.6 }, -- new batteries in
		{ At = 2.0, Id = "rbxassetid://9126098651", Volume = 0.4, MaxLength = 0.6 }, -- cap on
	},

	---------------------------------------------------------------------------
	-- Other players' flashlights
	---------------------------------------------------------------------------

	-- Times a second your flashlight's state is sent to everyone else.
	SEND_RATE = 15,
	-- Other flashlights further away than this aren't drawn.
	OTHERS_MAX_DISTANCE = 250,
	-- Whether other players' flashlights cast shadows. Costs performance with
	-- many players.
	OTHERS_SHADOWS = true,

	---------------------------------------------------------------------------
	-- Misc
	---------------------------------------------------------------------------

	-- Print battery and flicker state once a second (client output).
	DEBUG = false,

	-- Internal names; only change these if they clash with something.
	HAS_FLASHLIGHT_ATTRIBUTE = "HasFlashlight",
	BATTERIES_ATTRIBUTE = "FlashlightBatteries",
	FEAR_ATTRIBUTE = "Fear",
	ON_ATTRIBUTE = "FlashlightOn",
	POWER_ATTRIBUTE = "FlashlightPower",
	COLOR_ATTRIBUTE = "FlashlightColor",
	AIM_ATTRIBUTE = "FlashlightAim",
	MODEL_NAME = "Flashlight",
	REMOTES_FOLDER_NAME = "FlashlightRemotes",
	BEAMS_FOLDER_NAME = "FlashlightBeams",
}

return Config
