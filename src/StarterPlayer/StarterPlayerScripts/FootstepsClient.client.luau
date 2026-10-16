-- FootstepsClient (LocalScript) - lives in StarterPlayer > StarterPlayerScripts.
--
-- One footstep sound per step, for every character: yours, and everyone
-- else's from where they're walking. Steps are timed by distance walked, so
-- they keep pace with the character. Each character works through the
-- sounds in a shuffled cycle (every sound once in a random order, then a new
-- order, never the same one twice in a row).
--
-- Roblox's default running sound is muted.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("PlayerConfig"))

local rng = Random.new()

-- Slower than this (studs per second) counts as standing still.
local MIN_SPEED = 1
-- Speed of a normal walk; faster is louder, slower is quieter.
local WALK_SPEED = 16
-- When you start walking, the first step comes after this fraction of a
-- stride.
local FIRST_STEP = 0.3
-- Faster than this up or down (studs per second) is jumping or falling.
local MAX_VERTICAL_SPEED = 8
-- How tall a default character's HumanoidRootPart is; bigger characters
-- take longer strides.
local DEFAULT_ROOT_HEIGHT = 2
-- How far below the feet the ground can be and still count as standing.
local GROUND_TOLERANCE = 1.5

local templates = {}
for _, id in Config.FOOTSTEP_SOUNDS do
	local sound = Instance.new("Sound")
	sound.Name = "Footstep"
	sound.SoundId = id
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Config.FOOTSTEP_MIN_DISTANCE
	sound.RollOffMaxDistance = Config.FOOTSTEP_MAX_DISTANCE
	sound.Parent = SoundService
	table.insert(templates, sound)
end
task.spawn(ContentProvider.PreloadAsync, ContentProvider, templates)

local walkers = {} -- [Model] = { humanoid, root, travelled, order, index, last }

--------------------------------------------------------------------------------
-- Which sound next
--------------------------------------------------------------------------------

-- The next sound in this character's shuffled cycle.
local function nextTemplate(walker)
	if walker.index > #walker.order then
		local order = {}
		for i = 1, #templates do
			order[i] = i
		end
		for i = #order, 2, -1 do
			local j = rng:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
		-- Never the same sound twice in a row across two cycles.
		if #order > 1 and order[1] == walker.last then
			order[1], order[#order] = order[#order], order[1]
		end
		walker.order, walker.index = order, 1
	end
	local i = walker.order[walker.index]
	walker.index += 1
	walker.last = i
	return templates[i]
end

local function playStep(walker, speed)
	if #templates == 0 then
		return
	end
	local sound = nextTemplate(walker):Clone()
	sound.Volume = Config.FOOTSTEP_VOLUME * math.clamp(speed / WALK_SPEED, 0.4, 1.3)
	sound.PlaybackSpeed = 1 + rng:NextNumber(-Config.FOOTSTEP_PITCH_VARIATION, Config.FOOTSTEP_PITCH_VARIATION)
	sound.Parent = walker.root
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Characters
--------------------------------------------------------------------------------

-- Roblox's default footsteps ("Running", added by its character sound
-- script) would play over ours.
local function muteDefaultRunning(root)
	local function mute(child)
		if child:IsA("Sound") and child.Name == "Running" then
			child.Volume = 0
		end
	end
	root.ChildAdded:Connect(mute)
	for _, child in root:GetChildren() do
		mute(child)
	end
end

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and root) or not character.Parent then
		return
	end
	muteDefaultRunning(root)

	-- Other players' humanoid state isn't reliable on this client, so the
	-- ground under each character is checked directly.
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { character }
	groundParams.IgnoreWater = true

	walkers[character] = {
		humanoid = humanoid,
		root = root,
		groundParams = groundParams,
		travelled = 0,
		order = {},
		index = 1,
		last = nil,
	}
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			walkers[character] = nil
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

--------------------------------------------------------------------------------
-- Every frame
--------------------------------------------------------------------------------

local function isOnGround(walker)
	local root, humanoid = walker.root, walker.humanoid
	-- R6 characters stand on 2-stud legs rather than a hip height.
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6
		then 2 * root.Size.Y / DEFAULT_ROOT_HEIGHT
		else humanoid.HipHeight
	local depth = root.Size.Y / 2 + legs + GROUND_TOLERANCE
	return workspace:Raycast(root.Position, Vector3.new(0, -depth, 0), walker.groundParams) ~= nil
end

RunService.Heartbeat:Connect(function(dt)
	local cameraPosition = workspace.CurrentCamera.CFrame.Position
	for _, walker in walkers do
		local humanoid, root = walker.humanoid, walker.root
		local stride = Config.STRIDE_LENGTH * root.Size.Y / DEFAULT_ROOT_HEIGHT
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		local walking = speed > MIN_SPEED
			and math.abs(velocity.Y) < MAX_VERTICAL_SPEED
			and humanoid.Health > 0
			and not humanoid.Sit
			and (root.Position - cameraPosition).Magnitude < Config.FOOTSTEP_MAX_DISTANCE
			and isOnGround(walker)
		if not walking then
			-- Standing still: the first step comes soon after setting off.
			walker.travelled = stride * (1 - FIRST_STEP)
			continue
		end

		walker.travelled += speed * dt
		if walker.travelled >= stride then
			walker.travelled %= stride
			playStep(walker, speed)
		end
	end
end)
