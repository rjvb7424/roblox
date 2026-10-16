-- BlackoutConfig (ModuleScript) - lives in ReplicatedStorage.
-- Every tweakable value for the power system. It's shared by the server
-- (decides WHAT the power does and WHEN) and the client (decides how a
-- flicker LOOKS).
--
-- The whole map runs off one power supply, which goes round this cycle:
--
--   On ──► Failing ──► Off ──► Restoring ──► On ...
--                      │  ▲
--                      ▼  │
--                   FalseHope   (the lights stutter and nearly come back,
--                                then die again)
--
-- While the power is on, only some fixtures work; the rest are dead. Now and
-- then a single fixture flickers on its own, and sometimes one near a player
-- starts flickering just before the whole map goes.
--
-- Ranges use NumberRange.new(min, max); a random value in that range is
-- picked each time.

local Config = {
	-- Shortens every long wait (power on, power off, time between faults) to
	-- a quarter, with debug prints, so you can watch a whole cycle quickly.
	-- Set to false for the real game.
	TEST_MODE = false,

	---------------------------------------------------------------------------
	-- Setup
	---------------------------------------------------------------------------

	-- Name of the light fixtures in your map. Can be a Light (PointLight /
	-- SpotLight / SurfaceLight), a Part, or a Model/Folder containing them.
	-- Everything inside one object with this name counts as one fixture.
	LIGHT_NAME = "Light",

	-- Also switch off Neon parts inside "Light" (bulbs, light panels), plus
	-- a Neon part that directly contains a Light named "Light".
	CONTROL_NEON_PARTS = true,
	-- What a Neon part turns into while it's off.
	OFF_MATERIAL = Enum.Material.SmoothPlastic,

	---------------------------------------------------------------------------
	-- Power on (server)
	---------------------------------------------------------------------------

	-- Fraction of fixtures that work while the power is on. The rest are
	-- dead and stay dark.
	WORKING_FRACTION = 0.5,
	-- Each time the power comes back, this fraction of fixtures is re-rolled:
	-- some dead ones come back to life, some working ones don't come back.
	REROLL_FRACTION = 0.3,

	-- How long the power stays on.
	ON_TIME = NumberRange.new(90, 200),
	-- Chance it only stays on for a short while instead, just long enough
	-- to feel safe.
	SHORT_ON_CHANCE = 0.3,
	SHORT_ON_TIME = NumberRange.new(15, 35),

	-- While the power is on, a single random fixture flickers this often.
	FAULT_INTERVAL = NumberRange.new(40, 100),
	FAULT_TIME = NumberRange.new(0.8, 3),

	-- Chance that, just before the power fails, a working fixture near a
	-- player starts flickering first. OMEN_LEAD is how many seconds before.
	OMEN_CHANCE = 0.6,
	OMEN_LEAD = NumberRange.new(2.5, 5),

	---------------------------------------------------------------------------
	-- Jumpscares (server)
	-- While the power is on, the lights right next to a player suddenly snap
	-- off, strobe violently and flare, then carry on as if nothing happened.
	---------------------------------------------------------------------------

	-- Time between jumpscares (each one picks a random player who's near a
	-- working light).
	JUMPSCARE_INTERVAL = NumberRange.new(60, 150),
	-- Only lights within this many studs of the player.
	JUMPSCARE_RADIUS = 20,
	-- How many of the nearest working fixtures take part.
	JUMPSCARE_LIGHTS = 2,
	-- Seconds from the lights snapping off to them being back to normal.
	JUMPSCARE_TIME = 2.5,

	---------------------------------------------------------------------------
	-- Power failing, off and coming back (server)
	---------------------------------------------------------------------------

	-- The whole map flickering before it dies.
	FAILING_TIME = NumberRange.new(3, 7),

	-- How long the blackout lasts.
	OFF_TIME = NumberRange.new(35, 80),

	-- Chance (tried up to MAX_FALSE_HOPES times per blackout) that the power
	-- tries to come back and fails, then stays off a while longer.
	FALSE_HOPE_CHANCE = 0.5,
	MAX_FALSE_HOPES = 2,
	FALSE_HOPE_TIME = NumberRange.new(2, 4.5),
	OFF_AFTER_FALSE_HOPE_TIME = NumberRange.new(10, 30),

	-- The stutter as the power comes back for real.
	RESTORE_TIME = NumberRange.new(1.5, 3),

	---------------------------------------------------------------------------
	-- What flickering looks like (client)
	-- A flicker is a sequence of "glitches" separated by steady periods.
	-- Each glitch is a dropout, a dim, or a burst of quick flickers.
	---------------------------------------------------------------------------

	-- Steady (fully on) time between glitches.
	STEADY_TIME = NumberRange.new(0.15, 1.2),
	-- How much the steady gaps shrink by the end (0-1), so it gets worse as
	-- it goes on.
	FLICKER_BUILDUP = 0.7,

	-- Quick flicker burst: this many rapid off/on blinks.
	QUICK_FLICKER_COUNT = NumberRange.new(2, 6),
	QUICK_FLICKER_OFF = NumberRange.new(0.03, 0.12),
	QUICK_FLICKER_ON = NumberRange.new(0.03, 0.15),

	-- Dropout: light stays off for a moment, then comes back.
	DROPOUT_CHANCE = 0.2,
	DROPOUT_TIME = NumberRange.new(0.3, 1.2),

	-- Dim: brightness sags for a moment (level is a fraction of normal).
	DIM_CHANCE = 0.15,
	DIM_LEVEL = NumberRange.new(0.2, 0.5),
	DIM_TIME = NumberRange.new(0.15, 0.8),
	-- (Anything not a dropout or a dim is a quick flicker burst.)

	-- Right before the power dies, the lights surge this much brighter for a
	-- split second. 1 = no surge.
	SURGE_LEVEL = 1.6,

	---------------------------------------------------------------------------
	-- Misc
	---------------------------------------------------------------------------

	-- Print every power change in the server output.
	DEBUG = false,

	-- Internal names; only change these if they clash with something.
	POWER_FOLDER_NAME = "Power",
	LIGHT_TAG = "BlackoutLight",
	WORKING_ATTRIBUTE = "Working",
}

if Config.TEST_MODE then
	Config.DEBUG = true
	for _, key in
		{ "ON_TIME", "SHORT_ON_TIME", "FAULT_INTERVAL", "JUMPSCARE_INTERVAL", "OFF_TIME", "OFF_AFTER_FALSE_HOPE_TIME" }
	do
		local range = Config[key]
		Config[key] = NumberRange.new(range.Min / 4, range.Max / 4)
	end
end

return Config
