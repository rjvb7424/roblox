-- MapLightsConfig (ModuleScript) - lives in ReplicatedStorage.
-- Tweakable values for MapLightsClient, which makes the lights in your map
-- look and sound like real ones.
--
-- Leave a light out by giving it (or any ancestor, e.g. its model) an
-- attribute "MapLight" set to false. Give it "Hum" = false to keep the light
-- but silence it (e.g. candles, fire); exit signs are silenced automatically
-- (see SILENT_NAMES).

local Config = {
	---------------------------------------------------------------------------
	-- Soft edges
	-- Roblox spot and surface lights stop dead at the edge of their cone,
	-- leaving a hard line. Real light fades out. Each ring is a wider, dimmer
	-- copy of the light: Angle = degrees wider than the light,
	-- Brightness = fraction of its brightness. More rings = smoother, but
	-- each costs about as much as a light.
	---------------------------------------------------------------------------

	SOFT_EDGE_RINGS = {
		{ Angle = 30, Brightness = 0.25 },
		{ Angle = 70, Brightness = 0.08 },
	},

	---------------------------------------------------------------------------
	-- Bounced light
	-- Real light bounces off whatever it hits and softly lights the room
	-- around it, so the walls and ceiling above a lit floor aren't pitch
	-- black. Each light gets a dim light where its beam lands, tinted by that
	-- surface's colour.
	---------------------------------------------------------------------------

	-- How much of the light bounces back, before the surface's colour and
	-- the distance the light travelled to it reduce it (a dark floor far
	-- below bounces maybe a tenth of this). 0 = off.
	BOUNCE_STRENGTH = 1,
	-- How far the bounced light spreads, as a fraction of the light's range.
	BOUNCE_RANGE = 1.2,
	-- Studs off the surface the bounced light comes from.
	BOUNCE_OFFSET = 0.5,

	-- Added lights cast shadows, so they can't leak through walls into rooms
	-- with no light. Only turn off if performance needs it.
	SHADOWS = true,
	-- Soft edges and bounced light are only drawn for lights within this many
	-- studs of the camera.
	DRAW_DISTANCE = 160,
	-- Lights with a shorter Range than this are left as they are.
	MIN_RANGE = 6,

	---------------------------------------------------------------------------
	-- Sounds
	---------------------------------------------------------------------------

	-- Lights that never hum or crackle: any whose name (or any ancestor's
	-- name) contains one of these words, ignoring case...
	SILENT_NAMES = { "exit" },
	-- ...and any clearly green light (exit signs).
	SILENT_GREEN_LIGHTS = true,

	-- Every fixture hums from where it is, and goes quiet when it's off.
	HUM_SOUND = "rbxassetid://80816978244858",
	HUM_VOLUME = 0.3,
	-- Full volume within MIN, silent beyond MAX (studs). MIN should cover
	-- standing anywhere under a light, or the hum is too faint to hear.
	HUM_MIN_DISTANCE = 10,
	HUM_MAX_DISTANCE = 45,
	-- Each fixture's hum is pitched slightly differently, like real ballasts.
	HUM_PITCH_VARIATION = 0.05,

	-- Buzzes and crackles from a fixture for as long as it flickers: while
	-- the power is failing, trying to come back or coming back, or while
	-- that one fixture faults. Fades out when the flickering stops, and cuts
	-- to silence when the power dies.
	-- The clips end abruptly, so they're never looped as they are: each one
	-- fades into the next (picked at random, started at a random point,
	-- pitched slightly differently) before it gets to its end.
	FLICKER_SOUNDS = {
		"rbxassetid://116266785932124", -- Fluorescent light flickering 1
		"rbxassetid://113596877653932", -- Fluorescent light flickering 2
	},
	FLICKER_VOLUME = 0.5,
	-- Louder for a jumpscare (the lights right by a player going haywire).
	JUMPSCARE_VOLUME = 0.9,
	FLICKER_MIN_DISTANCE = 12,
	FLICKER_MAX_DISTANCE = 60,
	-- When the whole map flickers, only this many of the nearest fixtures
	-- make the sound.
	MAX_FLICKER_SOUNDS = 3,
	-- Seconds each clip takes to fade into the next.
	FLICKER_CROSSFADE = 0.35,
	-- Seconds cut off the end of each clip, where it stops abruptly. Raise
	-- this if you can still hear the cut.
	FLICKER_END_TRIM = 0.15,
	-- Seconds to fade out when the flickering stops.
	FLICKER_FADE_OUT = 0.12,
	-- Each clip plays up to this much faster or slower than normal.
	FLICKER_PITCH_VARIATION = 0.05,

	-- Lights outside the power system play it for FLICKER_SOUND_HOLD
	-- seconds after their brightness drops below FLICKER_SOUND_LEVEL (a
	-- fraction of normal).
	FLICKER_SOUND_LEVEL = 0.6,
	FLICKER_SOUND_HOLD = 1.5,
}

return Config
