-- FlashlightOthers (LocalScript) - lives in StarterPlayer > StarterPlayerScripts.
--
-- Draws everyone else's flashlight on this client: the beam coming out of
-- the flashlight in their hand and pointing where they're looking, the
-- glowing lens, and the click when they switch it on or off. What their
-- flashlight is doing comes from attributes FlashlightServer sets on their
-- Player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FlashlightConfig"))
local Visuals = require(ReplicatedStorage:WaitForChild("FlashlightVisuals"))

local localPlayer = Players.LocalPlayer

local WHITE = Color3.new(1, 1, 1)
-- How quickly a remote beam catches up with the latest aim (per second).
-- Updates arrive SEND_RATE times a second; this hides the steps.
local AIM_SMOOTHING = 14

local folder = Instance.new("Folder")
folder.Name = Config.BEAMS_FOLDER_NAME .. "Others"
folder.Parent = workspace

local others = {} -- [Player] = { beam, aim, connection }

local function getModel(player)
	local character = player.Character
	return character and character:FindFirstChild(Config.MODEL_NAME)
end

local function getLensPoint(model)
	local body = model and model.PrimaryPart
	return body and body:FindFirstChild("LensPoint")
end

local function track(player)
	if player == localPlayer or others[player] then
		return
	end
	local entry = {
		beam = Visuals.createBeam(player.Name, Config.OTHERS_SHADOWS, folder),
		aim = nil,
	}

	entry.connection = player:GetAttributeChangedSignal(Config.ON_ATTRIBUTE):Connect(function()
		local model = getModel(player)
		if model and model.PrimaryPart then
			Visuals.playClick(model.PrimaryPart, player:GetAttribute(Config.ON_ATTRIBUTE) == true)
		end
	end)
	others[player] = entry
end

local function untrack(player)
	local entry = others[player]
	if entry then
		entry.connection:Disconnect()
		Visuals.destroyBeam(entry.beam)
		others[player] = nil
	end
end

local function update(dt)
	local cameraPosition = workspace.CurrentCamera.CFrame.Position

	for player, entry in others do
		local model = getModel(player)
		local lensPoint = getLensPoint(model)
		local on = player:GetAttribute(Config.ON_ATTRIBUTE) == true
		local power = player:GetAttribute(Config.POWER_ATTRIBUTE)
		local color = player:GetAttribute(Config.COLOR_ATTRIBUTE)
		local aim = player:GetAttribute(Config.AIM_ATTRIBUTE)

		local visible = on
			and lensPoint
			and type(power) == "number"
			and typeof(aim) == "Vector3"
			and (lensPoint.WorldPosition - cameraPosition).Magnitude < Config.OTHERS_MAX_DISTANCE
		if not visible then
			entry.aim = nil
			Visuals.setBeam(entry.beam, cameraPosition, Vector3.zAxis, 0, WHITE)
			Visuals.setLens(model, 0, WHITE)
			continue
		end

		color = if typeof(color) == "Color3" then color else WHITE
		if entry.aim then
			local smoothed = entry.aim:Lerp(aim, 1 - math.exp(-AIM_SMOOTHING * dt))
			entry.aim = if smoothed.Magnitude > 1e-3 then smoothed.Unit else aim
		else
			entry.aim = aim
		end

		Visuals.setBeam(entry.beam, lensPoint.WorldPosition, entry.aim, power, color)
		Visuals.setLens(model, power, color)
	end
end

Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(untrack)
for _, player in Players:GetPlayers() do
	track(player)
end

RunService.RenderStepped:Connect(update)
