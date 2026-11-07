--!strict
-- Tool purchases, the Roblox Tool instances that carry them, and what is equipped.
-- The profile is the source of truth: Tool instances are rebuilt from ownedTools on spawn.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Money = require(Shared.Money)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local Harvest = require(script.Parent.HarvestService)
local ToolModels = require(script.Parent.ToolModels)
local ToolRules = require(Shared.ToolRules)
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
	if not backpack or not ToolModels.has(toolId) or owned(player, toolId) then return end
	local tool = ToolModels.build(toolId)
	-- Equip state comes from where the engine puts the Tool, read on the server.
	tool.Equipped:Connect(function() setEquipped(player, toolId) end)
	tool.Unequipped:Connect(function()
		local profile = State.get(player.UserId)
		if profile and profile.equippedTool == toolId then setEquipped(player, "Manual") end
		-- A held tool's engine stops when it is put away.
		if Config.Tools[toolId].behavior == "ContinuousHarvest" then ToolService.hold(player, toolId, false) end
	end)
	-- No harvest on Tool.Activated: it replicates every click, including the ones the client's
	-- cooldown ignores, so spam-clicking cut corn without a visible swing (Nov 6 2026). Swings
	-- arrive on the ToolSwing remote instead (ToolService.swing).
	tool.Parent = backpack
end

-- Held tools (ContinuousHarvest). The clock every cutter runs on: the server's synced clock,
-- which clients read too (workspace:GetServerTimeNow), so the heat they show from the Tool's
-- attributes matches the server's.
local function serverClock(): number
	return workspace:GetServerTimeNow()
end

-- Players whose held tool is running, and the last refusal each was told (refusals repeat every
-- tick while nothing is in reach, so each is sent once per press of the button).
local running: { [number]: boolean } = {}
local lastRefusal: { [number]: string } = {}
local lastHold: { [number]: number } = {}

-- Mirrors a held tool's heat onto its Tool so every client can show it (gauge tint, HUD meter):
-- Heat (0..1) at HeatAt, Running, OverheatUntil (all on the server clock).
local function publishHeat(player: Player, toolId: string, state: Types.HeatState)
	local tool = owned(player, toolId)
	if not tool then return end
	tool:SetAttribute("Heat", state.heat)
	tool:SetAttribute("HeatAt", state.at)
	tool:SetAttribute("Running", state.running)
	tool:SetAttribute("OverheatUntil", if state.overheatUntil > -math.huge then state.overheatUntil else 0)
end

-- One start/stop request from the ToolHold remote (the client sends it when the button goes
-- down and up). Starting needs the tool in the character's hand; HarvestService.hold checks
-- ownership, equip state, the character and the overheat lock. Requests are capped at 20 a
-- second per player; a stop is never dropped.
function ToolService.hold(player: Player, toolId: unknown, want: unknown)
	if typeof(toolId) ~= "string" or typeof(want) ~= "boolean" then return end
	local definition = Config.Tools[toolId]
	if not definition or definition.behavior ~= "ContinuousHarvest" then return end
	local clock = serverClock()
	if want then
		local previous = lastHold[player.UserId]
		if previous and clock - previous < 0.05 then return end
		lastHold[player.UserId] = clock
		local character = player.Character
		local held = character and character:FindFirstChildOfClass("Tool")
		if not held or held:GetAttribute("ToolId") ~= toolId then return end
	end
	local state = Harvest.hold(player, toolId, want, clock)
	if not state then return end
	running[player.UserId] = if state.running then true else nil
	lastRefusal[player.UserId] = nil
	publishHeat(player, toolId, state)
	-- Asked to start but locked: say so (the gauge shows it too).
	if want and not state.running and feedback then
		local _, locked = ToolRules.heatAt(definition, state, clock)
		if locked then feedback:FireClient(player, { ok = false, reason = "Overheated! Let it cool", amount = 0 }) end
	end
end

-- The shared loop for every running held tool: one Heartbeat connection, each player's due cut
-- at most once per frame. Successful cuts are sent like a swing's harvest (tool and target), an
-- overheat stops the engine and is announced, and farms refresh once per frame with any cut.
local function tickCutters()
	local clock = serverClock()
	local anyCut = false
	for userId in running do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			running[userId] = nil
			continue
		end
		local response, overheated = Harvest.cutTick(player, clock)
		local toolId, state = Harvest.cutterOf(userId)
		if overheated and toolId and state then
			running[userId] = nil
			publishHeat(player, toolId, state)
			local definition = Config.Tools[toolId]
			local cool = if definition.continuous then definition.continuous.coolSeconds else 0
			if feedback then
				feedback:FireClient(player, { ok = false, reason = "Overheated! Cooling for " .. tostring(cool) .. " s", amount = 0, tool = toolId })
			end
		elseif response then
			if response.ok then
				-- (lastRefusal is kept: walking between ripe patches would repeat "Walk into ripe
				-- corn" after every cut, so each refusal is said once per press.)
				anyCut = true
				if feedback then feedback:FireClient(player, response) end
			elseif lastRefusal[userId] ~= response.reason then
				lastRefusal[userId] = response.reason
				if feedback then feedback:FireClient(player, response) end
			end
			if state and not state.running and toolId then
				running[userId] = nil
				publishHeat(player, toolId, state)
			end
		end
	end
	if anyCut then Farms.update(DateTime.now().UnixTimestampMillis / 1000) end
end

function ToolService.init(harvestFeedback: RemoteEvent)
	feedback = harvestFeedback
	RunService.Heartbeat:Connect(tickCutters)
end

-- One swing request from the ToolSwing remote: the client sends it only when it plays the swing
-- animation. The tool must be the one in the character's hand; HarvestService.swing then checks
-- ownership, equip state and cadence and decides what the swing cut. `aim` is the targeted
-- tools' aim point (Corn Lasso); HarvestService checks it and ignores it for other tools.
function ToolService.swing(player: Player, toolId: unknown, aim: unknown?)
	if typeof(toolId) ~= "string" or not Config.Tools[toolId] then return end
	local character = player.Character
	local held = character and character:FindFirstChildOfClass("Tool")
	if not held or held:GetAttribute("ToolId") ~= toolId then return end
	local response = Harvest.swing(player, toolId, aim)
	if response.ok then Farms.update(DateTime.now().UnixTimestampMillis / 1000) end
	if feedback and response.reason ~= "Too fast" then feedback:FireClient(player, response) end
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
	if not tool or not ToolModels.has(toolId) then return result(false, "Unknown tool") end
	local profile = State.get(player.UserId)
	if not profile or not Farms.has(player.UserId) then return result(false, "Profile unavailable") end
	if profile.ownedTools[toolId] then return result(false, "Already owned") end
	local short = tool.price - State.balance(profile, tool.currency)
	if short > 0 then
		local hint = if tool.currency == "Cash" then " · sell popcorn at the stand" else ""
		return result(false, "Need " .. Money.price(tool.currency, short) .. " more" .. hint)
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

-- Whether a tool ID is defined in Config.Tools and has a model builder (so it can be held).
function ToolService.implemented(toolId: unknown): boolean
	return typeof(toolId) == "string" and Config.Tools[toolId] ~= nil and ToolModels.has(toolId)
end

-- Studio-only Developer Panel (AdminService): ownership without a charge, through the same
-- profile field and Tool instance as a purchase. Returns false if already owned.
function ToolService.grant(player: Player, toolId: string): boolean
	assert(ToolService.implemented(toolId), "Unknown tool")
	local profile = assert(State.get(player.UserId), "Profile unavailable")
	if profile.ownedTools[toolId] then return false end
	profile.ownedTools[toolId] = true
	State.publish(player.UserId)
	give(player, toolId)
	return true
end

-- Studio-only Developer Panel: takes an owned tool away. The live Tool is destroyed and, if it
-- was equipped, the player falls back to hands, so equippedTool never names an unowned tool.
-- Manual (hand picking) is not a Tool and always stays. Returns false if it was not owned.
function ToolService.revoke(player: Player, toolId: string): boolean
	assert(toolId ~= "Manual" and Config.Tools[toolId], "Unknown tool")
	local profile = assert(State.get(player.UserId), "Profile unavailable")
	if not profile.ownedTools[toolId] then return false end
	profile.ownedTools[toolId] = nil
	if profile.equippedTool == toolId then setEquipped(player, "Manual") end
	local tool = owned(player, toolId)
	while tool do
		tool:Destroy()
		tool = owned(player, toolId)
	end
	player:SetAttribute("Owned_" .. toolId, nil)
	State.publish(player.UserId)
	return true
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
	running[userId] = nil
	lastRefusal[userId] = nil
	lastHold[userId] = nil
end

return ToolService
