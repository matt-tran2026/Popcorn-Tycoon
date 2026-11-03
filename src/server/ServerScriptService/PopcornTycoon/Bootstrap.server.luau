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
local Sell = require(script.Parent.SellService)
local Tools = require(script.Parent.ToolService)
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
-- Shop menu: (action "Buy" | "Equip", toolId). Answered on ActionResult as "Tool"/"Equip".
local shop = Instance.new("RemoteEvent")
shop.Name = "ShopRequest"
shop.Parent = remotes
remotes.Parent = Shared
Tools.init(feedback)
shop.OnServerEvent:Connect(function(player: Player, action: unknown, toolId: unknown)
	local response = Tools.request(player, action, toolId)
	if response then notice:FireClient(player, if action == "Equip" then "Equip" else "Tool", response) end
end)

local function joined(player: Player)
	local profile = State.load(player.UserId, DateTime.now().UnixTimestampMillis / 1000)
	Farms.create(player.UserId, profile.fields.Starter, player.DisplayName)
	player:SetAttribute("RawCorn", 0)
	player:SetAttribute("BatchState", "Idle")
	State.publish(player.UserId)
	-- Every balance change (popcorn landing, purchases, sales) refreshes the stand's payout.
	player:GetAttributeChangedSignal("Popcorn"):Connect(function() Sell.refresh(player.UserId) end)
	Sell.refresh(player.UserId)
	Tools.track(player)
	Farms.update(DateTime.now().UnixTimestampMillis / 1000)
end

Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
	Conversion.settle(player.UserId) -- Credit in-flight popcorn before the profile goes.
	Harvest.release(player.UserId)
	Tools.release(player.UserId)
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
	elseif prompt.Name == "Microwave" or prompt.Name == "BuyRow" or prompt.Name == "Sell" or prompt.Name == "BuyTool" then
		local owner = Farms.resolveOwner(prompt)
		if owner == nil then return end
		if prompt.Name == "Microwave" then
			notice:FireClient(player, "Microwave", Conversion.start(player, owner))
		elseif prompt.Name == "Sell" then
			notice:FireClient(player, "Sell", Sell.sell(player, owner))
		elseif prompt.Name == "BuyTool" then
			local holder = prompt.Parent
			notice:FireClient(player, "Tool", Tools.buy(player, owner, if holder then holder:GetAttribute("ToolId") else nil))
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
print("[PopcornTycoon] Farm ready with microwave, sell stand and sickle (in-memory; progression resets on leave).")
