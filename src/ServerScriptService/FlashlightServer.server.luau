-- FlashlightServer (Script) - lives in ServerScriptService.
--
-- 1. Puts a flashlight in the right hand of every player who has one, so
--    everyone can see it.
-- 2. Keeps track of spare batteries.
-- 3. Relays what each player's flashlight is doing (on/off, brightness,
--    colour, where it's pointing) to everyone else, as attributes on their
--    Player. Each client simulates its own flashlight; FlashlightOthers draws
--    everyone else's.
--
-- Your own scripts can set these Player attributes at any time:
--   HasFlashlight (bool)         - take it away / hand it back
--   FlashlightBatteries (number) - spare batteries carried
--   Fear (0-1)                   - makes their hands shake more

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FlashlightConfig"))
local Visuals = require(ReplicatedStorage:WaitForChild("FlashlightVisuals"))

local MIN_STATE_INTERVAL = 1 / 30
local APPEARANCE_TIMEOUT = 5

local remotes = Instance.new("Folder")
remotes.Name = Config.REMOTES_FOLDER_NAME
local stateRemote = Instance.new("UnreliableRemoteEvent")
stateRemote.Name = "State"
stateRemote.Parent = remotes
local batteryRemote = Instance.new("RemoteEvent")
batteryRemote.Name = "UseBattery"
batteryRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local lastStateAt = {} -- [Player] = os.clock()

--------------------------------------------------------------------------------
-- The flashlight in the hand
--------------------------------------------------------------------------------

local function getHand(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function equip(player, character)
	local old = character:FindFirstChild(Config.MODEL_NAME)
	if old then
		old:Destroy()
	end
	if player:GetAttribute(Config.HAS_FLASHLIGHT_ATTRIBUTE) ~= true then
		return
	end
	local hand = getHand(character)
	if not hand then
		return
	end

	local model = Visuals.buildModel()
	local body = model.PrimaryPart
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = body
	-- Gripped at the front of the hand, pointing forward.
	weld.C0 = CFrame.new(0, -hand.Size.Y * 0.3, -hand.Size.Z * 0.5)
	weld.C1 = body.GripPoint.CFrame
	weld.Parent = body
	model.Parent = character
end

local function onCharacterAdded(player, character)
	-- Avatar loading can swap the hand for a new part, so wait for it.
	local started = os.clock()
	while not player:HasAppearanceLoaded() and os.clock() - started < APPEARANCE_TIMEOUT do
		task.wait(0.1)
	end
	if player.Character ~= character then
		return
	end
	equip(player, character)

	-- Re-equip if the hand is ever replaced (e.g. a new body applied).
	character.ChildAdded:Connect(function(child)
		if child == getHand(character) then
			equip(player, character)
		end
	end)
end

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------

local function onPlayerAdded(player)
	if player:GetAttribute(Config.HAS_FLASHLIGHT_ATTRIBUTE) == nil then
		player:SetAttribute(Config.HAS_FLASHLIGHT_ATTRIBUTE, Config.START_WITH_FLASHLIGHT)
	end
	if player:GetAttribute(Config.BATTERIES_ATTRIBUTE) == nil then
		player:SetAttribute(Config.BATTERIES_ATTRIBUTE, Config.START_SPARE_BATTERIES)
	end
	player:SetAttribute(Config.ON_ATTRIBUTE, false)

	player:GetAttributeChangedSignal(Config.HAS_FLASHLIGHT_ATTRIBUTE):Connect(function()
		if player:GetAttribute(Config.HAS_FLASHLIGHT_ATTRIBUTE) ~= true then
			player:SetAttribute(Config.ON_ATTRIBUTE, false)
		end
		if player.Character then
			equip(player, player.Character)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	lastStateAt[player] = nil
end)

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------

local function isFinite(x)
	return type(x) == "number" and x == x and math.abs(x) ~= math.huge
end

stateRemote.OnServerEvent:Connect(function(player, on, power, color, aim)
	if
		type(on) ~= "boolean"
		or not isFinite(power)
		or typeof(color) ~= "Color3"
		or not (isFinite(color.R) and isFinite(color.G) and isFinite(color.B))
		or typeof(aim) ~= "Vector3"
		or not (isFinite(aim.X) and isFinite(aim.Y) and isFinite(aim.Z))
		or aim.Magnitude < 0.5
	then
		return
	end
	local now = os.clock()
	if now - (lastStateAt[player] or 0) < MIN_STATE_INTERVAL then
		return
	end
	lastStateAt[player] = now

	local holding = player:GetAttribute(Config.HAS_FLASHLIGHT_ATTRIBUTE) == true
	player:SetAttribute(Config.ON_ATTRIBUTE, on and holding)
	player:SetAttribute(Config.POWER_ATTRIBUTE, if holding then math.clamp(power, 0, 1) else 0)
	player:SetAttribute(
		Config.COLOR_ATTRIBUTE,
		Color3.new(math.clamp(color.R, 0, 1), math.clamp(color.G, 0, 1), math.clamp(color.B, 0, 1))
	)
	player:SetAttribute(Config.AIM_ATTRIBUTE, aim.Unit)
end)

-- The client only asks once it can see it has a spare.
batteryRemote.OnServerEvent:Connect(function(player)
	local spares = player:GetAttribute(Config.BATTERIES_ATTRIBUTE)
	if type(spares) == "number" and spares >= 1 then
		player:SetAttribute(Config.BATTERIES_ATTRIBUTE, spares - 1)
	end
end)
