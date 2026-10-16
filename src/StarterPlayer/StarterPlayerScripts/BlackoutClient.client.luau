-- BlackoutClient (LocalScript) - lives in StarterPlayer > StarterPlayerScripts.
--
-- Renders the map's power (ReplicatedStorage.Power), single fixture faults
-- and jumpscares onto the lights the server tagged. Flicker patterns are generated
-- from the server's seed and timed against server time, so every player sees
-- the same flicker, including players who join or stream in partway through.
--
-- Also gives each Light a "NormalBrightness" attribute (on this client
-- only), so other scripts can tell how bright it's meant to be.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BlackoutConfig"))
local power = ReplicatedStorage:WaitForChild(Config.POWER_FOLDER_NAME)

local MIN_SEGMENT_TIME = 1 / 60
local BLACK = Color3.new(0, 0, 0)
-- The surge comes this many seconds before the power is due to go off.
local SURGE_LEAD = 0.3
-- Long enough to last until the server moves on to the next state.
local UNTIL_NEXT_STATE = 1e5

local lights = {} -- [inst] = { original, level, working, faultLevel, faultThread, connections }
local powerState = "On"
local powerLevel = 1
local powerThread = nil

--------------------------------------------------------------------------------
-- Applying a brightness level (0 = off, 1 = normal) to lights
--------------------------------------------------------------------------------

local function snapshot(inst)
	if inst:IsA("Light") then
		inst:SetAttribute("NormalBrightness", inst.Brightness)
		return { Enabled = inst.Enabled, Brightness = inst.Brightness }
	end
	return { Material = inst.Material, Color = inst.Color }
end

local function applyLevel(inst, original, level)
	if inst:IsA("Light") then
		inst.Enabled = original.Enabled and level > 0
		inst.Brightness = original.Brightness * level
	elseif level > 0 then
		-- Neon glows less the darker its colour, which reads as dimming.
		inst.Material = original.Material
		inst.Color = original.Color:Lerp(BLACK, 1 - math.min(level, 1))
	else
		inst.Material = Config.OFF_MATERIAL
		inst.Color = original.Color
	end
end

local function cancel(thread)
	if thread and coroutine.status(thread) ~= "dead" then
		task.cancel(thread)
	end
end

local function getLevel(light)
	if not light.working then
		return 0
	end
	-- Faults only show while the power is on.
	if light.faultLevel and powerState == "On" then
		return light.faultLevel
	end
	return powerLevel
end

local function refresh(inst, light)
	local level = getLevel(light)
	if level == light.level then
		return
	end
	-- Re-capture "normal" right before leaving it, in case another script
	-- changed this light since we last looked.
	if light.level == 1 then
		light.original = snapshot(inst)
	end
	light.level = level
	applyLevel(inst, light.original, level)
end

local function setPowerLevel(level)
	if powerLevel == level then
		return
	end
	powerLevel = level
	for inst, light in lights do
		refresh(inst, light)
	end
end

--------------------------------------------------------------------------------
-- Flicker patterns. Each step is { level, seconds }.
--------------------------------------------------------------------------------

local function randomIn(rng, range)
	return rng:NextNumber(range.Min, range.Max)
end

-- One glitch followed by a steady period. `progress` (0-1) is how far
-- through we are; steady periods shrink as it goes on.
local function queueGlitch(rng, queue, progress)
	local roll = rng:NextNumber()
	if roll < Config.DROPOUT_CHANCE then
		table.insert(queue, { 0, randomIn(rng, Config.DROPOUT_TIME) })
	elseif roll < Config.DROPOUT_CHANCE + Config.DIM_CHANCE then
		table.insert(queue, { randomIn(rng, Config.DIM_LEVEL), randomIn(rng, Config.DIM_TIME) })
	else
		local count = rng:NextInteger(Config.QUICK_FLICKER_COUNT.Min, Config.QUICK_FLICKER_COUNT.Max)
		for _ = 1, count do
			table.insert(queue, { 0, randomIn(rng, Config.QUICK_FLICKER_OFF) })
			table.insert(queue, { 1, randomIn(rng, Config.QUICK_FLICKER_ON) })
		end
	end
	table.insert(queue, { 1, randomIn(rng, Config.STEADY_TIME) * (1 - Config.FLICKER_BUILDUP * progress) })
end

-- The whole map failing: glitches getting worse, then one last surge and
-- darkness.
local function queueFailing(rng, queue, progress, remaining, memo)
	if memo.surged then
		table.insert(queue, { 0, UNTIL_NEXT_STATE })
		return
	end
	if remaining <= SURGE_LEAD then
		memo.surged = true
		table.insert(queue, { Config.SURGE_LEVEL, 0.12 })
		table.insert(queue, { 0, UNTIL_NEXT_STATE })
		return
	end

	queueGlitch(rng, queue, progress)
	-- Don't run past the moment of the surge.
	local budget = remaining - SURGE_LEAD
	local total = 0
	for i, step in queue do
		total += step[2]
		if total > budget then
			step[2] -= total - budget
			for j = #queue, i + 1, -1 do
				queue[j] = nil
			end
			break
		end
	end
end

-- Power coming back: short blips with long gaps at first, then the blips
-- get longer and the gaps shrink until the server switches the power on.
local function queueRestore(rng, queue, progress)
	table.insert(queue, { 1, randomIn(rng, Config.QUICK_FLICKER_ON) * (1 + 4 * progress) })
	table.insert(queue, { 0, randomIn(rng, Config.QUICK_FLICKER_OFF) * 3 * (1 - progress) })
end

-- The power trying to come back: it stutters, catches, seems to hold...
-- then gives out.
local function queueFalseHope(rng, queue, progress)
	if progress < 0.45 then
		queueRestore(rng, queue, progress / 0.45)
	elseif progress < 0.75 then
		table.insert(queue, { 1, rng:NextNumber(0.2, 0.6) })
		if rng:NextNumber() < 0.4 then
			table.insert(queue, { randomIn(rng, Config.DIM_LEVEL), rng:NextNumber(0.04, 0.1) })
		end
	else
		-- Dying: weaker blips, longer and longer gaps.
		local dying = (progress - 0.75) / 0.25
		table.insert(queue, { randomIn(rng, Config.DIM_LEVEL) * (1 - dying), randomIn(rng, Config.QUICK_FLICKER_ON) })
		table.insert(queue, { 0, randomIn(rng, Config.QUICK_FLICKER_OFF) * (1 + 10 * dying) })
	end
end

-- A jumpscare: the light snaps off, strobes violently, flares, goes dark
-- once more and then carries on as if nothing happened.
local function queueScare(rng, queue, _, _, memo)
	if memo.done then
		table.insert(queue, { 1, UNTIL_NEXT_STATE })
		return
	end
	memo.done = true
	table.insert(queue, { 0, rng:NextNumber(0.25, 0.6) })
	for _ = 1, rng:NextInteger(6, 12) do
		table.insert(queue, { rng:NextNumber(0.6, Config.SURGE_LEVEL), rng:NextNumber(0.02, 0.05) })
		table.insert(queue, { 0, rng:NextNumber(0.03, 0.08) })
	end
	table.insert(queue, { Config.SURGE_LEVEL, 0.08 })
	table.insert(queue, { 0, rng:NextNumber(0.2, 0.5) })
end

local PATTERNS = {
	Failing = queueFailing,
	FalseHope = queueFalseHope,
	Restoring = queueRestore,
}

local FAULT_PATTERNS = {
	Fault = queueGlitch,
	Scare = queueScare,
}

-- Plays a pattern from `startedAt`, calling `apply` with each level. Runs
-- until cancelled, or until `endsAt` if `stopAtEnd`.
local function render(pattern, seed, startedAt, endsAt, apply, stopAtEnd)
	local rng = Random.new(seed)
	local span = if endsAt then math.max(endsAt - startedAt, MIN_SEGMENT_TIME) else nil
	local memo = {}
	local queue, index = {}, 1
	local t = startedAt

	while not (stopAtEnd and endsAt and t >= endsAt) do
		if index > #queue then
			table.clear(queue)
			index = 1
			local progress = if span then math.clamp((t - startedAt) / span, 0, 1) else 0
			local remaining = if endsAt then endsAt - t else math.huge
			pattern(rng, queue, progress, remaining, memo)
		end

		local level, duration = queue[index][1], queue[index][2]
		index += 1
		t += math.max(duration, MIN_SEGMENT_TIME)
		if stopAtEnd and endsAt then
			t = math.min(t, endsAt)
		end

		-- Steps that already ended (we joined late or hitched) are skipped,
		-- which keeps every client on the same timeline.
		local remaining = t - workspace:GetServerTimeNow()
		if remaining > 0 then
			apply(level)
			task.wait(remaining)
		end
	end
end

--------------------------------------------------------------------------------
-- Power state
--------------------------------------------------------------------------------

local function onPowerChanged()
	cancel(powerThread)
	powerThread = nil

	powerState = power:GetAttribute("State") or "On"
	local pattern = PATTERNS[powerState]
	local seed, startedAt = power:GetAttribute("Seed"), power:GetAttribute("StartedAt")
	if pattern and seed and startedAt then
		powerThread = task.spawn(render, pattern, seed, startedAt, power:GetAttribute("EndsAt"), setPowerLevel, false)
	else
		setPowerLevel(if powerState == "Off" then 0 else 1)
	end

	-- Faults stop or start counting.
	for inst, light in lights do
		refresh(inst, light)
	end
end

--------------------------------------------------------------------------------
-- Single fixture faults
--------------------------------------------------------------------------------

local function onFaultChanged(inst, light)
	cancel(light.faultThread)
	light.faultThread = nil
	light.faultLevel = nil

	local seed = inst:GetAttribute("FaultSeed")
	local startedAt = inst:GetAttribute("FaultStartedAt")
	local endsAt = inst:GetAttribute("FaultEndsAt")
	local pattern = FAULT_PATTERNS[inst:GetAttribute("FaultKind")] or queueGlitch
	if seed and startedAt and endsAt and endsAt > workspace:GetServerTimeNow() then
		light.faultThread = task.spawn(function()
			render(pattern, seed, startedAt, endsAt, function(level)
				light.faultLevel = level
				refresh(inst, light)
			end, true)
			light.faultThread = nil
			light.faultLevel = nil
			refresh(inst, light)
		end)
	end
	refresh(inst, light)
end

--------------------------------------------------------------------------------
-- Lights (tagged by the server; also fires as lights stream in and out)
--------------------------------------------------------------------------------

local function addLight(inst)
	if lights[inst] then
		return
	end
	local light = {
		original = snapshot(inst),
		level = 1,
		working = inst:GetAttribute(Config.WORKING_ATTRIBUTE) ~= false,
		faultLevel = nil,
		faultThread = nil,
		connections = {},
	}
	lights[inst] = light

	table.insert(
		light.connections,
		inst:GetAttributeChangedSignal(Config.WORKING_ATTRIBUTE):Connect(function()
			light.working = inst:GetAttribute(Config.WORKING_ATTRIBUTE) ~= false
			refresh(inst, light)
		end)
	)
	table.insert(
		light.connections,
		inst:GetAttributeChangedSignal("FaultStartedAt"):Connect(function()
			onFaultChanged(inst, light)
		end)
	)
	onFaultChanged(inst, light)
end

local function removeLight(inst)
	local light = lights[inst]
	if not light then
		return
	end
	lights[inst] = nil
	for _, connection in light.connections do
		connection:Disconnect()
	end
	cancel(light.faultThread)
	if light.level ~= 1 then
		applyLevel(inst, light.original, 1)
	end
end

CollectionService:GetInstanceAddedSignal(Config.LIGHT_TAG):Connect(addLight)
CollectionService:GetInstanceRemovedSignal(Config.LIGHT_TAG):Connect(removeLight)
for _, inst in CollectionService:GetTagged(Config.LIGHT_TAG) do
	addLight(inst)
end

power:GetAttributeChangedSignal("StartedAt"):Connect(onPowerChanged)
onPowerChanged()
