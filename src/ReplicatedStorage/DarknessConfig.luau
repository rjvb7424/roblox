-- DarknessConfig (ModuleScript) - lives in ReplicatedStorage.
-- Every tweakable value for the darkness system. It's shared by the server
-- (removes every source of light that isn't a real light) and the client
-- (simulates how the player's eyes react to the light that's left).

local Config = {
	---------------------------------------------------------------------------
	-- The world (server)
	---------------------------------------------------------------------------

	-- Light that reaches everything, even where no light shines. Pure black
	-- means anywhere a light doesn't reach is pitch black. Only raise this
	-- (e.g. Color3.fromRGB(3, 3, 4)) if you want faint silhouettes in total
	-- darkness.
	AMBIENT = Color3.new(0, 0, 0),

	-- Make every PointLight / SpotLight / SurfaceLight in Workspace cast
	-- shadows. Without this, light shines straight through walls into rooms
	-- that should be dark.
	FORCE_LIGHT_SHADOWS = true,

	-- 0 = razor-sharp shadow edges, 1 = very soft.
	SHADOW_SOFTNESS = 0.4,

	-- How thick the air is. Higher = distant things sink into the dark
	-- sooner, even when they're lit. 0 = perfectly clear air.
	ATMOSPHERE_DENSITY = 0.3,

	-- Particles, beams and trails that aren't meant to glow (LightEmission 0)
	-- render at full brightness by default, even in total darkness. This
	-- makes them only visible where a light reaches them.
	FIX_UNLIT_EFFECTS = true,

	-- Turn off ColorCorrection / Bloom effects already in Lighting, since one
	-- with any Brightness above 0 turns black into grey. The client adds its
	-- own.
	DISABLE_EXISTING_EFFECTS = true,

	-- The midnight sky is black once stars and the moon are hidden. If yours
	-- still isn't (e.g. a custom sky), upload a plain black image and put its
	-- id here, like "rbxassetid://123456789".
	SKY_TEXTURE = nil :: string?,

	---------------------------------------------------------------------------
	-- The player's eyes (client)
	-- Real eyes adjust to the light: walk from a bright room into a dim one
	-- and it's black at first, then shapes slowly emerge. Walk back into the
	-- light (or have the power come back) and it's blinding for a moment.
	-- None of this can reveal anything in TOTAL darkness: with no light,
	-- there's nothing to adjust to.
	---------------------------------------------------------------------------

	-- Roughly how much light an ordinary lit spot gets, where the eyes need no
	-- adjusting. 0.5 is about halfway out from a Brightness 1 PointLight.
	-- Lower it if your rooms are dimly lit and look too bright.
	EYE_REFERENCE_LIGHT = 0.5,

	-- How strongly the eyes compensate (0 = not at all, 1 = fully). Real eyes
	-- only partly make up for low light.
	EYE_ADAPT_STRENGTH = 0.35,

	-- Exposure in stops. Max = how far fully dark-adapted eyes open up (+1
	-- means dim light looks twice as bright). Min = how far very bright light
	-- is toned down.
	EYE_EXPOSURE_RANGE = NumberRange.new(-1, 1),

	-- Seconds to (almost) fully adjust. Real eyes take much longer to get used
	-- to the dark than to the light.
	DARK_ADAPT_TIME = 10,
	LIGHT_ADAPT_TIME = 1,

	-- How far ahead the eyes look when judging how bright the scene is.
	EYE_VIEW_DISTANCE = 80,
	-- How many times a second the light reaching the eyes is measured.
	EYE_UPDATE_RATE = 20,

	---------------------------------------------------------------------------
	-- What the eyes see (client)
	---------------------------------------------------------------------------

	-- Colour grading in normal light. Slight desaturation keeps it grim.
	-- Extra contrast makes light fall off into black more abruptly.
	SATURATION = -0.1,
	CONTRAST = 0.05,

	-- Pushes the darkest shades all the way to black. Above 0 the edges of
	-- light end in a hard line instead of fading out. Unlit areas are pure
	-- black either way.
	BLACK_CRUSH = 0,

	-- Night vision: in dim light, the eye's colour sensors stop working, so
	-- colours drain away and shift slightly blue (the Purkinje effect). This
	-- is how things look once the eyes are fully dark-adapted.
	NIGHT_VISION_SATURATION = -0.75,
	NIGHT_VISION_TINT = Color3.fromRGB(200, 215, 255),

	-- Glow around bright lights. Dark-adapted eyes see more of it.
	BLOOM_INTENSITY = 0.7,
	BLOOM_SIZE = 36,
	BLOOM_THRESHOLD = 1,

	---------------------------------------------------------------------------
	-- Misc
	---------------------------------------------------------------------------

	-- Print what the eyes are measuring once a second (client output).
	DEBUG = false,
}

return Config
