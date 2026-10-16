-- BlackoutServer (Script) - lives in ServerScriptService.
--
-- The map's power supply. A "director" runs the whole map through a cycle
-- built for suspense: a long stretch of power, maybe a warning, the whole
-- map failing, a long blackout (sometimes with false hopes) and the power
-- coming back. See BlackoutConfig for the cycle and its timings.
--
-- 1. Finds every light fixture and tags its lights.
-- 2. Decides which fixtures work while the power is on (attribute "Working"
--    on each light) and makes single fixtures fault now and then.
-- 3. Publishes the power state to ReplicatedStorage.Power, so every client
--    renders the same flicker (and your own scripts can read it):
--      State      "On", "Failing", "Off", "FalseHope" or "Restoring"
--      StartedAt  server time it started
--      EndsAt     server time it's planned to end (not set while On)
--
-- The server never touches the lights itself: rapid flicker looks much
-- crisper when each client animates it locally from a shared random seed.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BlackoutConfig"))

local rng = Random.new()

local power = Instance.new("Folder")
power.Name = Config.POWER_FOLDER_NAME
power:SetAttribute("State", "On")
power.Parent = ReplicatedStorage

local fixtures = {} -- [root Instance] = { root, instances = { [Instance] = true }, working }
local fixtureOf = {} -- [Instance] = fixture

local function randomIn(range)
	return rng:NextNumber(range.Min, range.Max)
end

local function log(...)
	if Config.DEBUG then
		print("[Blackout]", ...)
	end
end

--------------------------------------------------------------------------------
-- Power state
--------------------------------------------------------------------------------

-- Clients listen for StartedAt, so it's written last.
local function setState(state, duration)
	local now = workspace:GetServerTimeNow()
	power:SetAttribute("State", state)
	power:SetAttribute("Seed", rng:NextInteger(1, 2 ^ 31 - 1))
	power:SetAttribute("EndsAt", if duration then now + duration else nil)
	power:SetAttribute("StartedAt", now)
	log(state, if duration then string.format("(%.1fs)", duration) else "")
end

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local function getWorldPosition(inst)
	if inst:IsA("BasePart") then
		return inst.Position
	end
	local parent = inst.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function getFixturePosition(fixture)
	for inst in fixture.instances do
		local position = getWorldPosition(inst)
		if position then
			return position
		end
	end
	return nil
end

local function setWorking(fixture, working)
	fixture.working = working
	for inst in fixture.instances do
		inst:SetAttribute(Config.WORKING_ATTRIBUTE, working)
	end
end

-- Some dead fixtures come back to life, some working ones die.
local function reroll()
	for _, fixture in fixtures do
		if rng:NextNumber() < Config.REROLL_FRACTION then
			setWorking(fixture, rng:NextNumber() < Config.WORKING_FRACTION)
		end
	end
end

local function getWorkingFixtures()
	local list = {}
	for _, fixture in fixtures do
		if fixture.working then
			table.insert(list, fixture)
		end
	end
	return list
end

-- Up to `count` fixtures from `list` within `maxDistance` of `position`,
-- nearest first.
local function getNearest(list, position, maxDistance, count)
	local found = {}
	for _, fixture in list do
		local fixturePosition = getFixturePosition(fixture)
		local distance = if fixturePosition then (fixturePosition - position).Magnitude else math.huge
		if distance <= maxDistance then
			table.insert(found, { fixture = fixture, distance = distance })
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local nearest = {}
	for i = 1, math.min(count, #found) do
		nearest[i] = found[i].fixture
	end
	return nearest
end

-- The working fixture closest to a random player, so someone sees it.
local function pickNearPlayer(list)
	local players = Players:GetPlayers()
	if #list == 0 or #players == 0 then
		return nil
	end
	local character = players[rng:NextInteger(1, #players)].Character
	local root = character and character.PrimaryPart
	if not root then
		return list[rng:NextInteger(1, #list)]
	end
	return getNearest(list, root.Position, math.huge, 1)[1]
end

-- One fixture flickers on its own for `duration` seconds. `kind` is
-- "Fault" (an ordinary bad contact) or "Scare" (a jumpscare). Fixtures given
-- the same seed flicker in sync.
local function startFault(fixture, duration, kind, seed)
	local now = workspace:GetServerTimeNow()
	for inst in fixture.instances do
		inst:SetAttribute("FaultKind", kind)
		inst:SetAttribute("FaultSeed", seed)
		inst:SetAttribute("FaultEndsAt", now + duration)
		-- Clients listen for FaultStartedAt, so it's written last.
		inst:SetAttribute("FaultStartedAt", now)
	end
	log(kind, "in", fixture.root:GetFullName(), string.format("(%.1fs)", duration))
end

local function newSeed()
	return rng:NextInteger(1, 2 ^ 31 - 1)
end

-- The lights right next to a random player (one who's near any) snap off,
-- strobe and flare. Returns false if nobody is near a working light.
local function startJumpscare()
	local working = getWorkingFixtures()
	local targets = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character.PrimaryPart
		local nearby = root and getNearest(working, root.Position, Config.JUMPSCARE_RADIUS, Config.JUMPSCARE_LIGHTS)
		if nearby and #nearby > 0 then
			table.insert(targets, nearby)
		end
	end
	if #targets == 0 then
		return false
	end
	local seed = newSeed()
	for _, fixture in targets[rng:NextInteger(1, #targets)] do
		startFault(fixture, Config.JUMPSCARE_TIME, "Scare", seed)
	end
	return true
end

--------------------------------------------------------------------------------
-- Light registration
--------------------------------------------------------------------------------

local function isNeonPart(inst)
	return Config.CONTROL_NEON_PARTS and inst:IsA("BasePart") and inst.Material == Enum.Material.Neon
end

-- Everything inside the outermost object named LIGHT_NAME is one fixture.
local function getFixtureRoot(inst)
	local root = inst
	local node = inst.Parent
	while node and node ~= workspace do
		if node.Name == Config.LIGHT_NAME then
			root = node
		end
		node = node.Parent
	end
	return root
end

-- Adds `inst` to the fixture at `root` (default: its own fixture) and
-- returns that root.
local function register(inst, root)
	root = root or getFixtureRoot(inst)
	if CollectionService:HasTag(inst, Config.LIGHT_TAG) then
		return root
	end
	local fixture = fixtures[root]
	if not fixture then
		fixture = { root = root, instances = {}, working = rng:NextNumber() < Config.WORKING_FRACTION }
		fixtures[root] = fixture
	end
	fixture.instances[inst] = true
	fixtureOf[inst] = fixture
	inst:SetAttribute(Config.WORKING_ATTRIBUTE, fixture.working)
	CollectionService:AddTag(inst, Config.LIGHT_TAG)
	return root
end

local function unregister(inst)
	local fixture = fixtureOf[inst]
	if not fixture then
		return
	end
	fixtureOf[inst] = nil
	fixture.instances[inst] = nil
	if next(fixture.instances) == nil then
		fixtures[fixture.root] = nil
	end
end

local function tryRegister(inst)
	if not (inst:IsA("Light") or isNeonPart(inst)) then
		return
	end
	if inst.Name ~= Config.LIGHT_NAME and not inst:FindFirstAncestor(Config.LIGHT_NAME) then
		return
	end

	local root = register(inst)

	-- A Light inside a glowing bulb part: the bulb is part of the same
	-- fixture, so it's dead or working along with it.
	local parent = inst.Parent
	if inst:IsA("Light") and parent and isNeonPart(parent) then
		register(parent, root)
	end
end

--------------------------------------------------------------------------------
-- Director
--------------------------------------------------------------------------------

-- If nobody is near a working light when a jumpscare is due, try again
-- after this many seconds.
local JUMPSCARE_RETRY_TIME = 5

-- The power stays on, with the odd fixture faulting and the odd jumpscare.
local function runPowerOn(duration)
	setState("On")
	local endsAt = os.clock() + duration
	local nextFault = os.clock() + randomIn(Config.FAULT_INTERVAL)
	local nextScare = os.clock() + randomIn(Config.JUMPSCARE_INTERVAL)
	while true do
		local now = os.clock()
		if now >= endsAt then
			return
		end
		if now >= nextFault then
			local list = getWorkingFixtures()
			if #list > 0 then
				startFault(list[rng:NextInteger(1, #list)], randomIn(Config.FAULT_TIME), "Fault", newSeed())
			end
			nextFault = now + randomIn(Config.FAULT_INTERVAL)
		end
		if now >= nextScare then
			-- Not in the last moments before the power fails anyway.
			local fits = endsAt - now > Config.JUMPSCARE_TIME + 3
			nextScare = now
				+ (if fits and startJumpscare() then randomIn(Config.JUMPSCARE_INTERVAL) else JUMPSCARE_RETRY_TIME)
		end
		task.wait(math.min(endsAt, nextFault, nextScare) - now)
	end
end

local function runState(state, range)
	local duration = randomIn(range)
	setState(state, duration)
	task.wait(duration)
end

local function runCycle(first)
	local short = not first and rng:NextNumber() < Config.SHORT_ON_CHANCE
	runPowerOn(randomIn(if short then Config.SHORT_ON_TIME else Config.ON_TIME))

	-- An omen: one light near someone starts flickering, then everything goes.
	if rng:NextNumber() < Config.OMEN_CHANCE then
		local fixture = pickNearPlayer(getWorkingFixtures())
		if fixture then
			local lead = randomIn(Config.OMEN_LEAD)
			startFault(fixture, lead, "Fault", newSeed())
			task.wait(lead)
		end
	end

	runState("Failing", Config.FAILING_TIME)
	runState("Off", Config.OFF_TIME)

	-- Which fixtures will work when it comes back (they also stutter during
	-- false hopes).
	reroll()
	for _ = 1, Config.MAX_FALSE_HOPES do
		if rng:NextNumber() >= Config.FALSE_HOPE_CHANCE then
			break
		end
		runState("FalseHope", Config.FALSE_HOPE_TIME)
		runState("Off", Config.OFF_AFTER_FALSE_HOPE_TIME)
	end

	runState("Restoring", Config.RESTORE_TIME)
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

for _, inst in workspace:GetDescendants() do
	tryRegister(inst)
end
workspace.DescendantAdded:Connect(tryRegister)
workspace.DescendantRemoving:Connect(unregister)

local totalLights, totalFixtures, working = 0, 0, 0
for _, fixture in fixtures do
	totalFixtures += 1
	working += if fixture.working then 1 else 0
	for _ in fixture.instances do
		totalLights += 1
	end
end
print(`[Blackout] {totalLights} light(s) in {totalFixtures} fixture(s), {working} working.`)
if totalLights == 0 then
	warn(
		`[Blackout] Found nothing to control. Check your lights are named "{Config.LIGHT_NAME}" `
			.. `and are (or contain) PointLight/SpotLight/SurfaceLight objects or Neon parts.`
	)
end

-- Lights that stay on through blackouts, in case that's not intended.
local uncontrolled = {}
for _, inst in workspace:GetDescendants() do
	if inst:IsA("Light") and not CollectionService:HasTag(inst, Config.LIGHT_TAG) then
		table.insert(uncontrolled, inst:GetFullName())
	end
end
if #uncontrolled > 0 then
	print(
		`[Blackout] {#uncontrolled} other light(s) aren't named "{Config.LIGHT_NAME}" and stay on through `
			.. `blackouts, e.g. {table.concat(uncontrolled, ", ", 1, math.min(#uncontrolled, 6))}`
	)
end

local first = true
while true do
	runCycle(first)
	first = false
end
