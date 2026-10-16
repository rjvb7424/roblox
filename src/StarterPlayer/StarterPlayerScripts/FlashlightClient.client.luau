-- FlashlightClient (LocalScript) - lives in StarterPlayer > StarterPlayerScripts.
--
-- Your own flashlight, simulated like a real one:
--
--   * Beam: a tight, bright hotspot inside a wide, dim spill. It comes from
--     your hand, not your eyes, so you can see the shadows it throws.
--   * Hand: it's held, not glued to the camera. It lags behind when you turn
--     and overshoots a little, bobs with your steps, sways as you breathe,
--     jolts when you land and trembles slightly (more with the "Fear"
--     attribute).
--   * Battery: it drains while on. An incandescent bulb dims and goes orange
--     as it dies; an LED stays bright, blinks a warning, drops to a dim low
--     mode, then dies. A dying battery left off for a while comes back a
--     little brighter, for a little while.
--   * Bulb: an incandescent filament takes a moment to light up and glows
--     orange as it cools after switching off.
--   * Loose contacts: it flickers now and then, more on a dying battery and
--     when you land hard, and can cut out until you click it off and on
--     again. That doesn't always work the first time.
--   * Spare batteries (Player attribute "FlashlightBatteries") are swapped by
--     hand, in the dark.
--
-- Other players see and hear your flashlight through FlashlightOthers.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("FlashlightConfig"))
local LightUtil = require(ReplicatedStorage:WaitForChild("LightUtil"))
local Visuals = require(ReplicatedStorage:WaitForChild("FlashlightVisuals"))

local remotes = ReplicatedStorage:WaitForChild(Config.REMOTES_FOLDER_NAME)
local stateRemote = remotes:WaitForChild("State")
local batteryRemote = remotes:WaitForChild("UseBattery")

local player = Players.LocalPlayer
local rng = Random.new()

local IS_LED = Config.BULB == "LED"
-- What a flat battery still gives at rest, as a fraction of a fresh one.
local DEAD_VOLTAGE = 0.2
-- A filament's light output goes with voltage^3.4, its temperature with
-- voltage^0.42.
local LIGHT_EXPONENT = 3.4
local HEAT_EXPONENT = 0.42
-- Camera closer than this to the head = first person.
local FIRST_PERSON_DISTANCE = 2
local MAX_SPRING_STEP = 1 / 120
-- How far the flashlight is lowered while swapping batteries.
local SWAP_OFFSET = Vector3.new(-0.15, -0.6, 0.3)
-- Seconds to lower / raise it at the start / end of a swap.
local SWAP_MOVE_TIME = 0.35
-- Resend the state at least this often, in case an update was lost.
local RESEND_INTERVAL = 0.5

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function randomIn(range)
	return rng:NextNumber(range.Min, range.Max)
end

local function hasFlashlight()
	return player:GetAttribute(Config.HAS_FLASHLIGHT_ATTRIBUTE) == true
end

local function getFear()
	local fear = player:GetAttribute(Config.FEAR_ATTRIBUTE)
	return if type(fear) == "number" then math.clamp(fear, 0, 1) else 0
end

-- Approximate colour of a glowing body at `kelvin` (Tanner Helland's fit).
local function kelvinToColor(kelvin)
	local t = math.max(kelvin, 100) / 100
	local r, g, b
	if t <= 66 then
		r = 255
		g = 99.4708025861 * math.log(t) - 161.1195681661
	else
		r = 329.698727446 * (t - 60) ^ -0.1332047592
		g = 288.1221695283 * (t - 60) ^ -0.0755148492
	end
	if t >= 66 then
		b = 255
	elseif t <= 19 then
		b = 0
	else
		b = 138.5177312231 * math.log(t - 10) - 305.0447927307
	end
	return math.clamp(r, 0, 255) / 255, math.clamp(g, 0, 255) / 255, math.clamp(b, 0, 255) / 255
end

local freshR, freshG, freshB = kelvinToColor(Config.INCANDESCENT_KELVIN)

-- Light colour of a filament heated by `voltage` (1 = fresh battery). Shifts
-- INCANDESCENT_COLOR the way a real filament shifts as it cools.
local function filamentColor(voltage)
	local r, g, b = kelvinToColor(Config.INCANDESCENT_KELVIN * math.max(voltage, 0) ^ HEAT_EXPONENT)
	local base = Config.INCANDESCENT_COLOR
	return Color3.new(
		math.min(base.R * r / freshR, 1),
		math.min(base.G * g / freshG, 1),
		math.min(base.B * b / math.max(freshB, 1e-3), 1)
	)
end

--------------------------------------------------------------------------------
-- Battery and bulb
--------------------------------------------------------------------------------

local switchOn = false
local charge = 1 -- 1 = fresh, 0 = flat. Kept across respawns.
local sag = 0 -- extra voltage drop from being on a while
local filament = 0 -- incandescent: filament heat; LED: output
local contactLost = false
local burst = nil -- current flicker: { steps = {{level, seconds}}, index, stepEnds, cutsOut }
local swapStartedAt = nil
local warnedLowBattery = false

local function restingVoltage()
	local used = 1 - charge
	return DEAD_VOLTAGE + (1 - DEAD_VOLTAGE) * (1 - used * used * used)
end

local function getVoltage()
	return math.max(restingVoltage() - sag, 0)
end

-- 0 with a healthy battery, 1 when it's nearly flat.
local function getLowness(voltage)
	return math.clamp((Config.LOW_VOLTAGE - voltage) / (Config.LOW_VOLTAGE - DEAD_VOLTAGE), 0, 1)
end

local function startBurst(steps, cutsOut)
	burst = { steps = steps, index = 0, stepEnds = 0, cutsOut = cutsOut }
end

-- The contact cutting in and out a few times. Sometimes it doesn't come back.
local function startFlicker(cutOutChance)
	if burst then
		return
	end
	local steps = {}
	for _ = 1, rng:NextInteger(Config.FLICKER_COUNT.Min, Config.FLICKER_COUNT.Max) do
		-- Rarely a clean cut: usually the contact half-connects.
		table.insert(steps, { rng:NextNumber(0, 0.35), randomIn(Config.FLICKER_OFF_TIME) })
		table.insert(steps, { 1, randomIn(Config.FLICKER_ON_TIME) })
	end
	startBurst(steps, rng:NextNumber() < cutOutChance)
end

-- How much current the contact lets through right now (1 = solid).
local function getContact(now)
	if contactLost then
		return 0
	end
	if not burst then
		return 1
	end
	while now >= burst.stepEnds do
		burst.index += 1
		local step = burst.steps[burst.index]
		if not step then
			contactLost = burst.cutsOut
			burst = nil
			return if contactLost then 0 else 1
		end
		burst.stepEnds = now + step[2]
	end
	return burst.steps[burst.index][1]
end

local function getLedOutput(voltage)
	if voltage >= Config.LED_STEP_DOWN_VOLTAGE then
		return 1
	elseif voltage >= Config.LED_CUTOFF_VOLTAGE then
		return Config.LED_LOW_LEVEL
	end
	return 0
end

-- Advances the battery and bulb. Returns light output (0-1) and colour.
local function updateBulb(dt, now)
	local drawing = switchOn and not swapStartedAt and not contactLost
	if drawing then
		charge = math.max(charge - dt / Config.BATTERY_LIFE, 0)
		local sagTarget = Config.BATTERY_SAG * (1 - charge)
		sag += (sagTarget - sag) * (1 - math.exp(-dt / Config.SAG_TIME))
	else
		sag -= sag * (1 - math.exp(-dt / Config.RECOVER_TIME))
	end

	local voltage = getVoltage()
	local lowness = getLowness(voltage)

	local drive = 0
	if switchOn and not swapStartedAt then
		if rng:NextNumber() < (Config.FLICKER_RATE + Config.LOW_BATTERY_FLICKER_RATE * lowness) * dt then
			startFlicker(Config.CUT_OUT_CHANCE * (0.5 + lowness))
		end

		if IS_LED then
			if voltage < Config.LED_STEP_DOWN_VOLTAGE and not warnedLowBattery then
				-- LED drivers blink a warning before dropping to low mode.
				warnedLowBattery = true
				burst = nil
				startBurst({ { 0, 0.1 }, { 1, 0.15 }, { 0, 0.1 }, { 1, 0.15 }, { 0, 0.1 } }, false)
			end
			drive = getLedOutput(voltage)
		else
			-- A weak battery makes the brightness wander.
			local waver = Config.LOW_BATTERY_WAVER * lowness * (0.5 + 0.5 * math.noise(now * 1.7, 0.37))
			drive = voltage * math.clamp(1 - waver, 0, 1)
		end
		drive *= getContact(now)
	end

	if IS_LED then
		filament = drive
		return filament, Config.LED_COLOR
	end

	-- The filament heats up fast and cools a bit slower, glowing orange.
	local seconds = if drive > filament then Config.WARM_UP_TIME else Config.COOL_DOWN_TIME
	filament += (drive - filament) * (1 - math.exp(-dt / math.max(seconds, 1e-3)))
	return filament ^ LIGHT_EXPONENT, filamentColor(filament)
end

--------------------------------------------------------------------------------
-- Switching and batteries
--------------------------------------------------------------------------------

local function setSwitch(on)
	if switchOn == on then
		return
	end
	switchOn = on
	Visuals.playClick(SoundService, on)

	if on and contactLost then
		contactLost = false
		if rng:NextNumber() >= Config.CLICK_FIX_CHANCE then
			-- It catches for a moment, then dies again.
			startBurst({ { rng:NextNumber(0.3, 0.8), rng:NextNumber(0.03, 0.08) } }, true)
		end
	end
end

local function toggle()
	if swapStartedAt or not hasFlashlight() then
		return
	end
	setSwitch(not switchOn)
end

local function swapBattery()
	if swapStartedAt or not hasFlashlight() then
		return
	end
	local spares = player:GetAttribute(Config.BATTERIES_ATTRIBUTE)
	if type(spares) ~= "number" or spares < 1 then
		return
	end
	batteryRemote:FireServer()

	local wasOn = switchOn
	setSwitch(false)
	local startedAt = os.clock()
	swapStartedAt = startedAt

	for _, cue in Config.BATTERY_SWAP_SOUNDS do
		task.delay(cue.At, function()
			if swapStartedAt == startedAt then
				Visuals.playSound(cue.Id, SoundService, cue.Volume, 1, cue.MaxLength)
			end
		end)
	end

	task.delay(Config.BATTERY_SWAP_TIME, function()
		if swapStartedAt ~= startedAt then
			return
		end
		charge, sag = 1, 0
		contactLost, burst, warnedLowBattery = false, nil, false
		swapStartedAt = nil
		if wasOn and hasFlashlight() then
			setSwitch(true)
		end
	end)
end

-- 0 = held up, 1 = fully lowered for a battery swap.
local function getSwapLowered(now)
	if not swapStartedAt then
		return 0
	end
	local t = now - swapStartedAt
	local amount = math.clamp(math.min(t, Config.BATTERY_SWAP_TIME - t) / SWAP_MOVE_TIME, 0, 1)
	return amount * amount * (3 - 2 * amount)
end

--------------------------------------------------------------------------------
-- The hand
--------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local aimDirection = nil -- where the hand points (lags behind the camera)
local aimVelocity = Vector3.zero
local stepPhase = 0
local walkAmount = 0
local fallSpeed = 0
local lensPosition = nil

-- The point you're looking at, never closer than MIN_AIM_DISTANCE in front
-- of the flashlight (in third person it's well ahead of the camera). The
-- beam converges on it.
local function getAimPoint(cameraCFrame, from)
	local look = cameraCFrame.LookVector
	local minDistance = Config.MIN_AIM_DISTANCE + math.max((from - cameraCFrame.Position):Dot(look), 0)
	local result = workspace:Raycast(cameraCFrame.Position, look * Config.AIM_DISTANCE, rayParams)
	local distance = if result
		then math.max((result.Position - cameraCFrame.Position).Magnitude, minDistance)
		else math.max(Config.AIM_DISTANCE, minDistance)
	return cameraCFrame.Position + look * distance
end

-- Moves the hand for this frame. Returns the beam direction (with tremor)
-- and how far the flashlight is bobbing (for the first-person model).
local function updateHand(dt, now, cameraCFrame, humanoid, root)
	local right, up = cameraCFrame.RightVector, cameraCFrame.UpVector
	local from = lensPosition or cameraCFrame.Position
	local target = (getAimPoint(cameraCFrame, from) - from).Unit

	-- Walking: the beam swings side to side with each step and dips as
	-- each foot lands.
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local walkTarget = if grounded then math.min(speed / 16, 1.5) else 0
	walkAmount += (walkTarget - walkAmount) * (1 - math.exp(-6 * dt))
	-- Bigger characters take longer strides (a default root part is 2 studs tall).
	local stride = Config.STRIDE_LENGTH * root.Size.Y / 2
	stepPhase += dt * speed / stride * math.pi
	local bob = Config.WALK_BOB * walkAmount
	local yaw = math.sin(stepPhase) * 0.016 * bob
	local pitch = math.cos(2 * stepPhase) * 0.012 * bob

	-- Breathing.
	yaw += math.sin(now * 0.8) * 0.003 * Config.BREATHING
	pitch += math.sin(now * 1.3 + 1.7) * 0.004 * Config.BREATHING

	target = (target + right * yaw + up * pitch).Unit

	-- The hand follows on a spring: it lags when you turn and overshoots a
	-- little when you stop.
	if not aimDirection or aimDirection:Dot(target) < 0.3 then
		aimDirection, aimVelocity = target, Vector3.zero
	end
	local steps = math.max(math.ceil(dt / MAX_SPRING_STEP), 1)
	local h = dt / steps
	for _ = 1, steps do
		aimVelocity += ((target - aimDirection) * Config.HAND_STIFFNESS - aimVelocity * Config.HAND_DAMPING) * h
		aimDirection = (aimDirection + aimVelocity * h).Unit
	end

	-- Tremor is too quick for the spring to smooth out.
	local shake = 0.0025 * Config.TREMOR * (1 + 3 * getFear())
	local tremor = right * math.noise(now * 9, 0.31) * shake + up * math.noise(now * 9, 4.7) * shake
	local bobOffset = Vector3.new(math.sin(stepPhase) * 0.03, math.cos(2 * stepPhase) * 0.025, 0) * bob

	return (aimDirection + tremor).Unit, bobOffset
end

-- A hard landing jolts the hand down and rattles the contacts.
local function onStateChanged(_, state)
	if state == Enum.HumanoidStateType.Freefall then
		return
	end
	if state == Enum.HumanoidStateType.Landed then
		local strength = math.clamp(fallSpeed / 80, 0, 1)
		local camera = workspace.CurrentCamera
		aimVelocity -= camera.CFrame.UpVector * strength * 1.5
		if switchOn and rng:NextNumber() < Config.JOLT_FLICKER_CHANCE * strength then
			startFlicker(Config.JOLT_CUT_OUT_CHANCE * strength)
		end
	end
	fallSpeed = 0
end

--------------------------------------------------------------------------------
-- Everything you see
--------------------------------------------------------------------------------

local folder = Instance.new("Folder")
folder.Name = Config.BEAMS_FOLDER_NAME
folder.Parent = workspace

local beam = Visuals.createBeam("Local", true, folder)

-- The flashlight drawn in first person (the one in your character's hand is
-- hidden in first person).
local viewModel = Visuals.buildModel()
for _, part in viewModel:GetDescendants() do
	if part:IsA("BasePart") then
		part.Anchored = true
	end
end

local dustVolume, dust
if Config.DUST then
	-- Spawns slowly drifting specks in front of the lens. With no ambient
	-- light they're only visible where the beam lights them.
	dustVolume = Instance.new("Part")
	dustVolume.Name = "Dust"
	dustVolume.Size = Vector3.new(3, 3, 12)
	dustVolume.Transparency = 1
	dustVolume.Anchored = true
	dustVolume.CanCollide = false
	dustVolume.CanQuery = false
	dustVolume.CanTouch = false
	dustVolume.CastShadow = false

	dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Rate = Config.DUST_RATE
	dust.Lifetime = NumberRange.new(4, 8)
	dust.Speed = NumberRange.new(0.02, 0.12)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Drag = 1
	dust.Acceleration = Vector3.new(0, -0.01, 0)
	dust.Size = NumberSequence.new(0.03)
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(0.8, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	dust.LightInfluence = 1
	dust.LightEmission = 0
	dust.Enabled = false
	dust.Parent = dustVolume
	dustVolume.Parent = folder
end

local function getHandModel(character)
	return character and character:FindFirstChild(Config.MODEL_NAME)
end

local function hideAll(character)
	Visuals.setBeam(beam, Vector3.zero, Vector3.zAxis, 0, Color3.new())
	Visuals.setLens(getHandModel(character), 0, Color3.new())
	viewModel.Parent = nil
	if dust then
		dust.Enabled = false
	end
	aimDirection, lensPosition = nil, nil
end

--------------------------------------------------------------------------------
-- Telling everyone else
--------------------------------------------------------------------------------

local lastSent = { at = -math.huge, on = nil, power = -1, color = nil, aim = nil }

local function send(now, on, power, color, aim)
	if now - lastSent.at < 1 / Config.SEND_RATE then
		return
	end
	-- Rounded so tiny changes don't count as new colours.
	color = Color3.new(math.round(color.R * 50) / 50, math.round(color.G * 50) / 50, math.round(color.B * 50) / 50)
	-- While it's off, nobody can see where it points.
	local changed = on ~= lastSent.on
		or math.abs(power - lastSent.power) > 0.02
		or (power > 0 and (color ~= lastSent.color or not lastSent.aim or aim:Dot(lastSent.aim) < 0.9999))
	if not changed and now - lastSent.at < RESEND_INTERVAL then
		return
	end
	stateRemote:FireServer(on, power, color, aim)
	lastSent.at, lastSent.on, lastSent.power, lastSent.color, lastSent.aim = now, on, power, color, aim
end

--------------------------------------------------------------------------------
-- Every frame
--------------------------------------------------------------------------------

local sinceLog = 0

local function update(dt)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local cameraCFrame = camera.CFrame
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local head = character and character:FindFirstChild("Head")
	local holding = hasFlashlight() and humanoid and humanoid.Health > 0 and root and head

	if not holding then
		-- Dropped it, or died: it goes out with no click.
		switchOn = false
	end

	local power, color = updateBulb(dt, now)

	if Config.DEBUG then
		sinceLog += dt
		if sinceLog >= 1 then
			sinceLog = 0
			print(
				string.format(
					"[Flashlight] on %s | charge %.2f volts %.2f sag %.2f | power %.3f | %s",
					tostring(switchOn),
					charge,
					getVoltage(),
					sag,
					power,
					if contactLost then "CUT OUT" elseif burst then "flickering" else "steady"
				)
			)
		end
	end

	if not holding then
		hideAll(character)
		send(now, false, 0, color, cameraCFrame.LookVector)
		return
	end

	if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		fallSpeed = math.max(fallSpeed, -root.AssemblyLinearVelocity.Y)
	end

	local direction, bobOffset = updateHand(dt, now, cameraCFrame, humanoid, root)
	local handModel = getHandModel(character)
	local firstPerson = (cameraCFrame.Position - head.Position).Magnitude < FIRST_PERSON_DISTANCE

	local lens
	if firstPerson then
		local lowered = getSwapLowered(now)
		-- Held in a frame that turns with the (lagging) hand, so the
		-- flashlight swings across the view when you turn quickly.
		local hold = CFrame.lookAt(cameraCFrame.Position, cameraCFrame.Position + aimDirection, cameraCFrame.UpVector)
		lens = hold:PointToWorldSpace(Config.HOLD_OFFSET + bobOffset + SWAP_OFFSET * lowered)
		viewModel:PivotTo(
			CFrame.lookAt(lens, lens + direction, cameraCFrame.UpVector)
				* CFrame.Angles(lowered * 0.9, 0, lowered * 0.4)
		)
		viewModel.Parent = if Config.SHOW_IN_FIRST_PERSON then camera else nil
	else
		local lensPoint = handModel and handModel.PrimaryPart and handModel.PrimaryPart:FindFirstChild("LensPoint")
		-- Until the server has put it in your hand, light from just in front
		-- of your head (not inside it, or the head would block it).
		lens = if lensPoint then lensPoint.WorldPosition else head.Position + direction * 1.5
		viewModel.Parent = nil
	end
	lensPosition = lens

	Visuals.setBeam(beam, lens, direction, power, color)
	Visuals.setLens(viewModel, power, color)
	Visuals.setLens(handModel, power, color)

	if dust then
		dust.Enabled = power > 0.05
		dustVolume.CFrame = LightUtil.lookAlong(lens + direction * 7, direction)
	end

	send(now, switchOn, power, color, direction)
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

local function onCharacterAdded(character)
	switchOn = false
	aimDirection, lensPosition, fallSpeed = nil, nil, 0
	rayParams.FilterDescendantsInstances = { character, folder }
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.StateChanged:Connect(onStateChanged)
	end
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

local function bind(name, title, keys, callback)
	ContextActionService:BindAction(name, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			callback()
		end
		return Enum.ContextActionResult.Pass
	end, true, table.unpack(keys))
	ContextActionService:SetTitle(name, title)
end

bind("FlashlightToggle", "Light", Config.TOGGLE_KEYS, toggle)
bind("FlashlightBattery", "Battery", Config.SWAP_BATTERY_KEYS, swapBattery)

RunService.RenderStepped:Connect(update)
