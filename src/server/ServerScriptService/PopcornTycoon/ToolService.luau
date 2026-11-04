--!strict
-- Tool purchases, the Roblox Tool instances that carry them, and what is equipped.
-- The profile is the source of truth: Tool instances are rebuilt from ownedTools on spawn.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local Harvest = require(script.Parent.HarvestService)
local ToolModels = require(script.Parent.ToolModels)
local builders: { [string]: () -> Tool } = { Sickle = ToolModels.sickle }
local feedback: RemoteEvent? = nil
local spawnConnections: { [number]: RBXScriptConnection } = {}
local ToolService = {}

local function result(ok: boolean, reason: string, amount: number?): Types.ActionResult
	return { ok = ok, reason = reason, amount = amount or 0 }
end

local function setEquipped(player: Player, toolId: string)
	local profile = State.get(player.UserId)
	if not profile then return end
	profile.equippedTool = toolId
	player:SetAttribute("EquippedTool", toolId)
end

-- The player's live Tool for a tool ID, held or in the backpack.
local function owned(player: Player, toolId: string): Tool?
	for _, holder in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if holder then
			for _, child in holder:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("ToolId") == toolId then return child end
			end
		end
	end
	return nil
end

-- Gives the player a live Tool for an owned tool ID unless they already hold one.
local function give(player: Player, toolId: string)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local build = builders[toolId]
	if not backpack or not build or owned(player, toolId) then return end
	local tool = build()
	-- Equip state comes from where the engine puts the Tool, read on the server.
	tool.Equipped:Connect(function() setEquipped(player, toolId) end)
	tool.Unequipped:Connect(function()
		local profile = State.get(player.UserId)
		if profile and profile.equippedTool == toolId then setEquipped(player, "Manual") end
	end)
	-- Activated replicates from the owning client; the server decides what the swing cut.
	tool.Activated:Connect(function()
		local response = Harvest.swing(player, toolId)
		if response.ok then Farms.update(DateTime.now().UnixTimestampMillis / 1000) end
		if feedback and response.reason ~= "Too fast" then feedback:FireClient(player, response) end
	end)
	tool.Parent = backpack
end

function ToolService.init(harvestFeedback: RemoteEvent)
	feedback = harvestFeedback
end

function ToolService.track(player: Player)
	local function spawned()
		setEquipped(player, "Manual") -- A fresh character holds nothing.
		local profile = State.get(player.UserId)
		if not profile then return end
		player:WaitForChild("Backpack", 10)
		for toolId, owned in profile.ownedTools do
			if owned then give(player, toolId) end
		end
	end
	spawnConnections[player.UserId] = player.CharacterAdded:Connect(spawned)
	if player.Character then task.spawn(spawned) end
end

-- The one purchase transaction, reached through the Shop menu.
function ToolService.purchase(player: Player, toolId: unknown): Types.ActionResult
	if typeof(toolId) ~= "string" then return result(false, "Unknown tool") end
	local tool = Config.Tools[toolId]
	if not tool or not builders[toolId] then return result(false, "Unknown tool") end
	local profile = State.get(player.UserId)
	if not profile or not Farms.has(player.UserId) then return result(false, "Profile unavailable") end
	if profile.ownedTools[toolId] then return result(false, "Already owned") end
	local short = tool.price - State.balance(profile, tool.currency)
	if short > 0 then
		local hint = if tool.currency == "Coins" then " · sell popcorn at the stand" else ""
		return result(false, "Need " .. tostring(short) .. " more " .. string.lower(tool.currency) .. hint)
	end
	-- No yields between the checks above and this commit; ownership is set in the same step
	-- as the charge, so a repeated request finds "Already owned" and is never charged twice.
	assert(State.spend(profile, tool.currency, tool.price))
	profile.ownedTools[toolId] = true
	State.publish(player.UserId)
	give(player, toolId)
	return result(true, tool.displayName .. " bought! Equip it from the hotbar or the Shop", tool.price)
end

-- Equips an owned tool, or "Manual" for bare hands. The engine moves the Tool; the
-- Equipped/Unequipped connections above record the result in the profile.
function ToolService.equip(player: Player, toolId: unknown): Types.ActionResult
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then return result(false, "Character unavailable") end
	if toolId == "Manual" then
		humanoid:UnequipTools()
		return result(true, "Hands free · pick corn with E or tap")
	end
	if typeof(toolId) ~= "string" or not Config.Tools[toolId] then return result(false, "Unknown tool") end
	local profile = State.get(player.UserId)
	if not profile or not profile.ownedTools[toolId] then return result(false, "Buy it first") end
	local tool = owned(player, toolId)
	if not tool then return result(false, "Tool unavailable") end
	humanoid:EquipTool(tool)
	return result(true, Config.Tools[toolId].displayName .. " equipped · click, tap or F to swing")
end

local lastRequest: { [number]: number } = {}
-- Shop menu requests. Only the action and tool ID come from the client; everything else is
-- read from the server's own state, and requests faster than the cooldown are dropped.
function ToolService.request(player: Player, action: unknown, toolId: unknown): Types.ActionResult?
	local clock = os.clock()
	local previous = lastRequest[player.UserId]
	if previous and clock - previous < Config.Shop.requestCooldownSeconds then return nil end
	lastRequest[player.UserId] = clock
	if action == "Buy" then return ToolService.purchase(player, toolId) end
	if action == "Equip" then return ToolService.equip(player, toolId) end
	return result(false, "Unknown request")
end

function ToolService.release(userId: number)
	local connection = spawnConnections[userId]
	if connection then connection:Disconnect() end
	spawnConnections[userId] = nil
	lastRequest[userId] = nil
end

return ToolService
