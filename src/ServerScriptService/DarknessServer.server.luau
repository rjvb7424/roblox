-- DarknessServer (Script) - lives in ServerScriptService.
--
-- Removes every bit of light that doesn't come from an actual light: sun,
-- moon, stars, sky glow and ambient light. Anywhere a light doesn't reach is
-- pitch black. Also makes every light cast shadows, so light can't leak
-- through walls into rooms that should be dark.
--
-- This only changes things while the game is running, so Studio's edit view
-- stays lit and you can still see what you're building.
--
-- Lighting.LightingStyle can't be set from a script. Set it to Realistic in
-- Studio yourself (this script warns if it isn't).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DarknessConfig"))

local BLACK = Color3.new(0, 0, 0)
local SKY_FACES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }

--------------------------------------------------------------------------------
-- Lighting
--------------------------------------------------------------------------------

Lighting.Ambient = Config.AMBIENT
Lighting.OutdoorAmbient = Config.AMBIENT
Lighting.Brightness = 0 -- no sunlight or moonlight
Lighting.ColorShift_Top = BLACK
Lighting.ColorShift_Bottom = BLACK
Lighting.EnvironmentDiffuseScale = 0 -- no light from the sky
Lighting.EnvironmentSpecularScale = 0 -- no reflections of the sky
Lighting.ClockTime = 0 -- midnight
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = Config.SHADOW_SOFTNESS
Lighting.ExposureCompensation = 0 -- each client drives this (eye adaptation)
Lighting.FogColor = BLACK

local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
sky.CelestialBodiesShown = false
sky.StarCount = 0
if Config.SKY_TEXTURE then
	for _, face in SKY_FACES do
		sky[face] = Config.SKY_TEXTURE
	end
end
sky.Parent = Lighting

-- Black air: distant things fade into darkness, and nothing glows on the
-- horizon.
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = Config.ATMOSPHERE_DENSITY
atmosphere.Offset = 0
atmosphere.Color = BLACK
atmosphere.Decay = BLACK
atmosphere.Glare = 0
atmosphere.Haze = 0
atmosphere.Parent = Lighting

local disabledEffects = 0
if Config.DISABLE_EXISTING_EFFECTS then
	for _, effect in Lighting:GetChildren() do
		if (effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect")) and effect.Enabled then
			effect.Enabled = false
			disabledEffects += 1
		end
	end
end

--------------------------------------------------------------------------------
-- Light leaks
--------------------------------------------------------------------------------

local shadowLights = 0

local function isUnlitEffect(inst)
	return (inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail")) and inst.LightEmission == 0
end

local function fixLightLeak(inst)
	if Config.FORCE_LIGHT_SHADOWS and inst:IsA("Light") then
		inst.Shadows = true
		shadowLights += 1
	elseif Config.FIX_UNLIT_EFFECTS and isUnlitEffect(inst) then
		inst.LightInfluence = 1
	end
end

for _, inst in workspace:GetDescendants() do
	fixLightLeak(inst)
end
workspace.DescendantAdded:Connect(fixLightLeak)

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

print(`[Darkness] World darkened. {shadowLights} light(s) cast shadows.`)
if disabledEffects > 0 then
	print(`[Darkness] Disabled {disabledEffects} ColorCorrection/Bloom effect(s) in Lighting.`)
end

-- These can be read but not written by scripts.
local ok, style = pcall(function()
	return Lighting.LightingStyle.Name
end)
if ok and style ~= "Realistic" then
	warn(
		`[Darkness] Lighting.LightingStyle is {style}. Select Lighting in the Explorer and set it to `
			.. `Realistic, or lights won't cast proper shadows and light will leak into dark rooms.`
	)
end

local ok2, prioritize = pcall(function()
	return Lighting.PrioritizeLightingQuality
end)
if ok2 and not prioritize then
	warn(`[Darkness] Turn on Lighting.PrioritizeLightingQuality in Studio so shadows stay sharp on more devices.`)
end
