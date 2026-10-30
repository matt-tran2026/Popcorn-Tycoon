--!strict
local Players = game:GetService("Players")
local Prompts = game:GetService("ProximityPromptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local Harvest = require(script.Parent.HarvestService)
Config.validate()
Farms.init()

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local feedback = Instance.new("RemoteEvent")
feedback.Name = "HarvestResult"
feedback.Parent = remotes
remotes.Parent = Shared

local function joined(player: Player)
	local profile = State.load(player.UserId, DateTime.now().UnixTimestampMillis / 1000)
	Farms.create(player.UserId, profile.fields.Starter)
	player:SetAttribute("RawCorn", 0)
	player:SetAttribute("Popcorn", profile.popcorn)
	Farms.update(DateTime.now().UnixTimestampMillis / 1000)
end

Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
	Harvest.release(player.UserId)
	Farms.remove(player.UserId)
	State.release(player.UserId)
end)
for _, player in Players:GetPlayers() do joined(player) end

Prompts.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
	local owner, fieldId, stalkId = Farms.resolve(prompt)
	if owner == nil then return end
	local response = Harvest.attempt(player, owner, fieldId, stalkId)
	if response.ok then Farms.update(DateTime.now().UnixTimestampMillis / 1000) end
	feedback:FireClient(player, response)
end)

task.spawn(function()
	while script.Parent do
		task.wait(Config.VisualUpdateSeconds)
		Farms.update(DateTime.now().UnixTimestampMillis / 1000)
	end
end)
print("[PopcornTycoon] Starter field ready (in-memory; progression resets on leave).")
