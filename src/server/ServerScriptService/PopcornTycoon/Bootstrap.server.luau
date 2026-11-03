--!strict
local Players = game:GetService("Players")
local Prompts = game:GetService("ProximityPromptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local Harvest = require(script.Parent.HarvestService)
local Conversion = require(script.Parent.ConversionService)
local Upgrades = require(script.Parent.UpgradeService)
Config.validate()
local Map = require(script.Parent.MapVisuals)
Map.placeSpawn() -- Before the yielding loads below, so early joiners spawn in the right place.
require(script.Parent.VisualTemplates).load()
require(script.Parent.EnvironmentVisuals).build()
Map.build()
Farms.init()

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local feedback = Instance.new("RemoteEvent")
feedback.Name = "HarvestResult"
feedback.Parent = remotes
-- Confirmed microwave, collection and purchase outcomes: (kind, ActionResult).
local notice = Instance.new("RemoteEvent")
notice.Name = "ActionResult"
notice.Parent = remotes
remotes.Parent = Shared

local function joined(player: Player)
	local profile = State.load(player.UserId, DateTime.now().UnixTimestampMillis / 1000)
	Farms.create(player.UserId, profile.fields.Starter, player.DisplayName)
	player:SetAttribute("RawCorn", 0)
	player:SetAttribute("Popcorn", profile.popcorn)
	Farms.update(DateTime.now().UnixTimestampMillis / 1000)
end

Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
	Conversion.settle(player.UserId) -- Credit in-flight popcorn before the profile goes.
	Harvest.release(player.UserId)
	Farms.remove(player.UserId)
	State.release(player.UserId)
end)
for _, player in Players:GetPlayers() do joined(player) end

Prompts.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
	if prompt.Name == "Harvest" then
		local owner, fieldId, stalkId = Farms.resolve(prompt)
		if owner == nil then return end
		local response = Harvest.attempt(player, owner, fieldId, stalkId)
		if response.ok then Farms.update(DateTime.now().UnixTimestampMillis / 1000) end
		feedback:FireClient(player, response)
	elseif prompt.Name == "Microwave" or prompt.Name == "BuyRow" then
		local owner = Farms.resolveOwner(prompt)
		if owner == nil then return end
		if prompt.Name == "Microwave" then
			notice:FireClient(player, "Microwave", Conversion.start(player, owner))
		else
			local response = Upgrades.buyExtraRow(player, owner)
			if response.ok then Farms.update(DateTime.now().UnixTimestampMillis / 1000) end
			notice:FireClient(player, "Upgrade", response)
		end
	end
end)

task.spawn(function()
	while script.Parent do
		task.wait(Config.VisualUpdateSeconds)
		local now = DateTime.now().UnixTimestampMillis / 1000
		Farms.update(now)
		for userId, amount in Conversion.update(now) do
			local player = Players:GetPlayerByUserId(userId)
			if player then notice:FireClient(player, "Collect", { ok = true, reason = "Collected", amount = amount }) end
		end
	end
end)
print("[PopcornTycoon] Farm ready with microwave (in-memory; progression resets on leave).")
