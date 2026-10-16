-- PlayerServer (Script) - lives in ServerScriptService.
--
-- Locks everyone into first person and makes their characters bigger.
-- See PlayerConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("PlayerConfig"))

local APPEARANCE_TIMEOUT = 5

local function onCharacterAdded(player, character)
	-- Scale once the avatar is on, or it would be applied over the top at the
	-- old size.
	local started = os.clock()
	while not player:HasAppearanceLoaded() and os.clock() - started < APPEARANCE_TIMEOUT do
		task.wait(0.1)
	end
	if player.Character == character and character.Parent and Config.CHARACTER_SCALE ~= 1 then
		character:ScaleTo(Config.CHARACTER_SCALE)
	end
end

local function onPlayerAdded(player)
	if Config.FIRST_PERSON then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
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
