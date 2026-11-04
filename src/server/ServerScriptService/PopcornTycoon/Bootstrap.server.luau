--!strict
local Players = game:GetService("Players")
-- Characters load only once the player's farm exists, then appear at their own farm entrance.
-- Auto-loading during the yielding startup below dropped early joiners at the hub before the
-- map existed, so they fell under it and were stuck. Set before anything can yield.
Players.CharacterAutoLoads = false
local RunService = game:GetService("RunService")
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
local Looks = require(script.Parent.UpgradeVisuals)
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
-- Upgrades menu: (upgradeId, fieldId?) only. Answered on ActionResult as "FarmUpgrade".
local upgradeRequest = Instance.new("RemoteEvent")
upgradeRequest.Name = "UpgradeRequest"
upgradeRequest.Parent = remotes
remotes.Parent = Shared
Tools.init(feedback)
-- Step-on land pads (Extra Row / New Plot). FarmService has already checked the toucher owns the farm.
Farms.setPadHandler(function(player: Player, kind: string, fieldId: string?, _pad: Part)
	local response = if kind == "Plot" then Upgrades.buyPlot(player) else Upgrades.buyRow(player, fieldId)
	if response.ok then Farms.update(DateTime.now().UnixTimestampMillis / 1000) end
	notice:FireClient(player, "Upgrade", response)
end)
-- Studio-only test hook: ServerStorage.DebugGrantCash:Invoke(userId, amount) from the command bar.
if RunService:IsStudio() then
	local grant = Instance.new("BindableFunction")
	grant.Name = "DebugGrantCash"
	grant.OnInvoke = function(userId: number, amount: number)
		local profile = State.get(userId)
		if not profile or typeof(amount) ~= "number" or amount % 1 ~= 0 then return false end
		profile.cash = math.max(0, profile.cash + amount)
		State.publish(userId)
		return profile.cash
	end
	grant.Parent = game:GetService("ServerStorage")
end
upgradeRequest.OnServerEvent:Connect(function(player: Player, upgradeId: unknown, fieldId: unknown)
	local response = Upgrades.buyUpgrade(player, upgradeId, fieldId)
	if response.ok then Farms.update(DateTime.now().UnixTimestampMillis / 1000) end
	-- Refusals name the upgrade too (only a known id), so the menu can shake the right card.
	if not response.upgradeId and typeof(upgradeId) == "string" and Config.FarmUpgrades[upgradeId] then response.upgradeId = upgradeId end
	notice:FireClient(player, "FarmUpgrade", response)
end)
shop.OnServerEvent:Connect(function(player: Player, action: unknown, toolId: unknown)
	local response = Tools.request(player, action, toolId)
	if response then notice:FireClient(player, if action == "Equip" then "Equip" else "Tool", response) end
end)

-- Moves a freshly loaded character to its owner's farm entrance (the engine first places it
-- at the hub SpawnLocation, which stays as the fallback when there is no free farm slot).
local function placeAtFarm(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local frame = Farms.spawnFrame(player.UserId)
	if not root or not frame then return end
	if not character:IsDescendantOf(workspace) then character.AncestryChanged:Wait() end
	RunService.Heartbeat:Wait()
	if character.Parent == nil then return end
	character:PivotTo(frame)
	root.AssemblyLinearVelocity = Vector3.zero
	-- The pack for the player's Backpack level rides on every new character.
	local profile = State.get(player.UserId)
	if profile then Looks.backpack(character, profile.upgrades.Backpack) end
end

-- With CharacterAutoLoads off, respawning after a death is ours to do.
local function trackCharacters(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(placeAtFarm, player, character)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then return end
		humanoid.Died:Once(function()
			task.wait(Players.RespawnTime)
			if player.Parent and player.Character == character then player:LoadCharacter() end
		end)
	end)
end

local function joined(player: Player)
	local profile = State.load(player.UserId, DateTime.now().UnixTimestampMillis / 1000)
	Farms.create(player.UserId, profile.fields, player.DisplayName)
	player:SetAttribute("RawCorn", 0)
	player:SetAttribute("BatchState", "Idle")
	State.publish(player.UserId)
	-- Every balance change (popcorn landing, purchases, sales) refreshes the stand's payout.
	player:GetAttributeChangedSignal("Popcorn"):Connect(function() Sell.refresh(player.UserId) end)
	Sell.refresh(player.UserId)
	Tools.track(player)
	Farms.update(DateTime.now().UnixTimestampMillis / 1000)
	trackCharacters(player)
	if player.Parent then player:LoadCharacter() end
end

Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
	Conversion.settle(player.UserId) -- Credit in-flight popcorn before the profile goes.
	Harvest.release(player.UserId)
	Upgrades.release(player.UserId)
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
	elseif prompt.Name == "Microwave" or prompt.Name == "Sell" then
		local owner = Farms.resolveOwner(prompt)
		if owner == nil then return end
		if prompt.Name == "Microwave" then
			notice:FireClient(player, "Microwave", Conversion.start(player, owner))
		else
			notice:FireClient(player, "Sell", Sell.sell(player, owner))
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
print("[PopcornTycoon] Farm ready with microwave, sell stand, sickle, land pads and farm upgrades (in-memory; progression resets on leave).")
