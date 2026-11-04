--!strict
-- The Owner-only Developer Panel's server side (creator request, Nov 4 2026): testing commands
-- that change the Owner's own live profile instantly, without grinding or waiting.
-- Security model, enforced here on every request (the client UI is only a convenience):
--   * the admin remote exists only where AdminConfig.mutationsAllowed (Roblox Studio by default);
--     every request re-checks the environment and the caller's rank (AdminConfig.rankOf, UserId);
--   * identity comes from the connection; commands always target the caller's own profile,
--     never another player, and every field ID must be one of the caller's own plots;
--   * request shape, command names, IDs and numbers are validated (finite whole numbers in range);
--   * each request carries an increasing request id, so a replayed request is refused and never
--     grants twice; a token bucket limits the rate; one command runs at a time per player.
-- Commands reuse the gameplay services' own state functions (PlayerStateService,
-- UpgradeService.applyLevel/grantRow/grantPlot, ToolService.grant/revoke/equip, FarmService),
-- never charge Cash, and are named developer actions rather than fake purchases or harvests.
-- Profiles are in memory only (no DataStore), so nothing here can touch saved progression.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Growth = require(Shared.Growth)
local Money = require(Shared.Money)
local Pricing = require(Shared.Pricing)
local FarmUpgrades = require(Shared.FarmUpgrades)
local AdminConfig = require(script.Parent.AdminConfig)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local Upgrades = require(script.Parent.UpgradeService)
local Tools = require(script.Parent.ToolService)
local Map = require(script.Parent.MapVisuals)
local AdminService = {}

export type Response = { ok: boolean, reason: string, state: { [string]: any }?, lastId: number? }
type Args = { [string]: any }
type Context = { player: Player, profile: Types.Profile, args: Args, now: number }
type Command = { minRank: string, run: (Context) -> (boolean, string) }

type Session = { tokens: number, refilledAt: number, lastId: number, busy: boolean, refusedLogAt: number }
local sessions: { [number]: Session } = {}
local MAX_ARGS, MAX_STRING, MAX_COMMAND = 8, 32, 32

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function isStudio(): boolean
	return RunService:IsStudio()
end

-- The caller's rank in this environment, or nil.
function AdminService.rankOf(player: Player): string?
	return AdminConfig.rankOf(player.UserId, isStudio(), { creatorType = game.CreatorType, creatorId = game.CreatorId })
end

local function log(player: Player, command: string, ok: boolean, reason: string)
	print(string.format("[Admin] %s %s -> %s: %s", player.Name, command, if ok then "ok" else "refused", reason))
end

---------------------------------------------------------------------------------------------
-- Validation helpers. Everything from the client is `unknown` until checked here.

-- A finite whole number in [low, high], else nil.
local function whole(value: unknown, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
	if value % 1 ~= 0 or value < low or value > high then return nil end
	return value
end

-- A finite number in [low, high] (fractions allowed), else nil.
local function finite(value: unknown, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value or value < low or value > high then return nil end
	return value
end

local function amountArg(ctx: Context, allowZero: boolean): number?
	return whole(ctx.args.amount, if allowZero then 0 else 1, AdminConfig.maxBalance)
end

-- One of the caller's own plots (by field ID). Ownership is checked against the profile.
local function ownField(ctx: Context, fieldId: unknown): Types.Field?
	if typeof(fieldId) ~= "string" then return nil end
	local field = ctx.profile.fields[fieldId]
	if not field or field.ownerUserId ~= ctx.player.UserId or not Config.Crops[field.cropId] then return nil end
	return field
end

-- The plots a field command applies to: one owned plot, or "*" for every owned plot.
local function targetFields(ctx: Context): { Types.Field }?
	local fieldId = ctx.args.fieldId
	if fieldId == "*" then
		local list = {}
		for _, field in ctx.profile.fields do
			if field.ownerUserId == ctx.player.UserId and Config.Crops[field.cropId] then table.insert(list, field) end
		end
		table.sort(list, function(a, b) return a.plot < b.plot end)
		return list
	end
	local field = ownField(ctx, fieldId)
	return if field then { field } else nil
end

local function fieldsLabel(list: { Types.Field }): string
	return if #list == 1 then list[1].id else tostring(#list) .. " plots"
end

---------------------------------------------------------------------------------------------
-- Economy. Balances only change through the profile; publish() replicates them (HUD, Shop,
-- Upgrades menu and the sell stand's payout all follow the attributes).

local function setBalance(ctx: Context, currency: Types.Currency, value: number): number
	local clamped = math.clamp(value, 0, AdminConfig.maxBalance)
	if currency == "Cash" then ctx.profile.cash = clamped else ctx.profile.popcorn = clamped end
	State.publish(ctx.player.UserId)
	return clamped
end

local function show(currency: Types.Currency, amount: number): string
	return if currency == "Cash" then Money.cash(amount) else Money.short(amount) .. " popcorn"
end

local function balanceCommands(commands: { [string]: Command }, prefix: string, currency: Types.Currency)
	commands[prefix .. ".add"] = { minRank = "Owner", run = function(ctx)
		local amount = amountArg(ctx, false)
		if not amount then return false, "Enter a whole amount from 1 to " .. Money.short(AdminConfig.maxBalance) end
		local before = State.balance(ctx.profile, currency)
		local after = setBalance(ctx, currency, before + amount)
		return true, "+" .. show(currency, after - before) .. " · now " .. show(currency, after)
	end }
	commands[prefix .. ".set"] = { minRank = "Owner", run = function(ctx)
		local amount = amountArg(ctx, true)
		if not amount then return false, "Enter a whole amount from 0 to " .. Money.short(AdminConfig.maxBalance) end
		return true, "Set to " .. show(currency, setBalance(ctx, currency, amount))
	end }
	commands[prefix .. ".remove"] = { minRank = "Owner", run = function(ctx)
		local amount = amountArg(ctx, false)
		if not amount then return false, "Enter a whole amount from 1 to " .. Money.short(AdminConfig.maxBalance) end
		local before = State.balance(ctx.profile, currency)
		local after = setBalance(ctx, currency, before - amount)
		return true, "−" .. show(currency, before - after) .. " · now " .. show(currency, after)
	end }
	commands[prefix .. ".zero"] = { minRank = "Owner", run = function(ctx)
		setBalance(ctx, currency, 0)
		return true, show(currency, 0) .. " left"
	end }
	commands[prefix .. ".max"] = { minRank = "Owner", run = function(ctx)
		return true, "Set to the testing max " .. show(currency, setBalance(ctx, currency, AdminConfig.maxBalance))
	end }
end

-- Raw corn: never above the bag (PlayerStateService.bagCapacity), so the harvest, HUD and
-- microwave rules keep their usual invariant (carried <= capacity).
local function cropArg(ctx: Context): string?
	local cropId = ctx.args.cropId
	return if typeof(cropId) == "string" and Config.Crops[cropId] then cropId else nil
end

local function addCorn(ctx: Context, cropId: string, wanted: number): number
	local space = math.max(0, State.bagCapacity(ctx.profile) - State.carried(ctx.profile))
	local added = math.min(wanted, space)
	ctx.profile.rawCorn[cropId] = (ctx.profile.rawCorn[cropId] or 0) + added
	State.publish(ctx.player.UserId)
	return added
end

-- Drops raw corn above the bag size (after a lower Backpack level), newest crop IDs first.
local function trimBag(profile: Types.Profile): number
	local excess = State.carried(profile) - State.bagCapacity(profile)
	if excess <= 0 then return 0 end
	local ids = {}
	for cropId in profile.rawCorn do table.insert(ids, cropId) end
	table.sort(ids, function(a, b) return a > b end)
	local removed = 0
	for _, cropId in ids do
		local take = math.min(profile.rawCorn[cropId], excess - removed)
		profile.rawCorn[cropId] -= take
		removed += take
	end
	return removed
end

---------------------------------------------------------------------------------------------
-- Farming. Growth is only ever a stalk's growthStartedAt (Growth.yields); these commands move
-- that one server timestamp, so harvesting, partial harvests and regrowth keep their rules.

local function setGrowth(ctx: Context, list: { Types.Field }, cycles: (rules: Types.GrowthRules, ready: number) -> number?): number
	local changed = 0
	for _, field in list do
		local rules = FarmUpgrades.fieldRules(field)
		for _, stalk in field.stalks do
			local wanted = cycles(rules, Growth.yields(stalk.growthStartedAt, ctx.now, rules))
			if wanted then
				stalk.growthStartedAt = ctx.now - wanted * rules.growthSeconds
				changed += 1
			end
		end
	end
	-- Visual stages, cobs, prompts and pick badges follow on the same server tick.
	Farms.update(ctx.now)
	return changed
end

---------------------------------------------------------------------------------------------
-- Upgrades. Levels go through UpgradeService.applyLevel, the same commit as a purchase minus
-- the charge, so Soil/Storage rebase stalks and the Upgrades menu and visuals refresh.

local function upgradeArg(ctx: Context): (string?, string?)
	local upgradeId = ctx.args.upgradeId
	if typeof(upgradeId) ~= "string" or not Config.FarmUpgrades[upgradeId] then return nil, "Unknown upgrade" end
	return upgradeId, nil
end

-- Applies `level(current, max)` to an upgrade on the player or on the targeted plots.
local function changeUpgrade(ctx: Context, upgradeId: string, level: (current: number, max: number) -> number?): (boolean, string)
	local upgrade = Config.FarmUpgrades[upgradeId]
	local max = FarmUpgrades.maxLevel(upgradeId)
	if upgrade.scope == "Global" then
		local current = FarmUpgrades.clampLevel(upgradeId, (ctx.profile.upgrades :: any)[upgradeId])
		local target = level(current, max)
		if not target then return false, "Pick a level from 0 to " .. tostring(max) end
		Upgrades.applyLevel(ctx.player, ctx.profile, upgradeId, nil, target)
		local trimmed = if upgradeId == "Backpack" then trimBag(ctx.profile) else 0
		if trimmed > 0 then State.publish(ctx.player.UserId) end
		return true, upgrade.displayName .. " Lv " .. tostring(target) .. "/" .. tostring(max)
			.. (if trimmed > 0 then " · " .. tostring(trimmed) .. " corn over the new bag size dropped" else "")
	end
	local list = targetFields(ctx)
	if not list or #list == 0 then return false, "Pick one of your plots" end
	local shown: number? = nil
	for _, field in list do
		local current = FarmUpgrades.clampLevel(upgradeId, (field.upgrades :: any)[upgradeId])
		local target = level(current, max)
		if not target then return false, "Pick a level from 0 to " .. tostring(max) end
		Upgrades.applyLevel(ctx.player, ctx.profile, upgradeId, field, target)
		shown = target
	end
	Farms.update(ctx.now)
	return true, upgrade.displayName .. " Lv " .. tostring(shown) .. "/" .. tostring(max) .. " on " .. fieldsLabel(list)
end

local function everyUpgrade(ctx: Context, toMax: boolean): (boolean, string)
	for _, upgradeId in Config.FarmUpgradeOrder do
		local upgrade = Config.FarmUpgrades[upgradeId]
		local target = if toMax then FarmUpgrades.maxLevel(upgradeId) else 0
		if upgrade.scope == "Global" then
			Upgrades.applyLevel(ctx.player, ctx.profile, upgradeId, nil, target)
		else
			for _, field in ctx.profile.fields do Upgrades.applyLevel(ctx.player, ctx.profile, upgradeId, field, target) end
		end
	end
	if trimBag(ctx.profile) > 0 then State.publish(ctx.player.UserId) end
	Farms.update(ctx.now)
	return true, (if toMax then "Every upgrade maxed" else "Every upgrade reset to Lv 0") .. " (Backpack and all plots)"
end

---------------------------------------------------------------------------------------------
-- Tools: ToolService owns ownership, Tool instances and equipping.

local function toolArg(ctx: Context): string?
	local toolId = ctx.args.toolId
	return if Tools.implemented(toolId) then toolId :: string else nil
end

local function sortedTools(): { string }
	local ids = {}
	for toolId in Config.Tools do if Tools.implemented(toolId) then table.insert(ids, toolId) end end
	table.sort(ids)
	return ids
end

---------------------------------------------------------------------------------------------
-- Player and movement (the caller's own character only).

local function character(player: Player): (Model?, Humanoid?, BasePart?)
	local model = player.Character
	local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	if not model or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil, nil, nil end
	return model, humanoid, root
end

local function teleport(player: Player, frame: CFrame?, label: string): (boolean, string)
	local model, _, root = character(player)
	if not model or not root then return false, "Character unavailable" end
	if not frame then return false, label .. " unavailable" end
	model:PivotTo(frame)
	root.AssemblyLinearVelocity = Vector3.zero
	return true, "Teleported to " .. label
end

---------------------------------------------------------------------------------------------
-- The command registry. Each entry names its minimum rank (only Owner exists today).

local commands: { [string]: Command } = {}
balanceCommands(commands, "cash", "Cash")
balanceCommands(commands, "popcorn", "Popcorn")

commands["corn.add"] = { minRank = "Owner", run = function(ctx)
	local cropId = cropArg(ctx)
	if not cropId then return false, "Unknown corn type" end
	local amount = whole(ctx.args.amount, 1, AdminConfig.maxBalance)
	if not amount then return false, "Enter a whole amount of corn" end
	local added = addCorn(ctx, cropId, amount)
	if added == 0 then return false, "Bag is already full" end
	return true, "+" .. tostring(added) .. " " .. Config.Crops[cropId].displayName .. (if added < amount then " (bag full)" else "")
end }
commands["corn.fill"] = { minRank = "Owner", run = function(ctx)
	local cropId = cropArg(ctx)
	if not cropId then return false, "Unknown corn type" end
	local added = addCorn(ctx, cropId, AdminConfig.maxBalance)
	return true, "Bag filled · +" .. tostring(added) .. " " .. Config.Crops[cropId].displayName
		.. " · " .. tostring(State.carried(ctx.profile)) .. "/" .. tostring(State.bagCapacity(ctx.profile))
end }
commands["corn.empty"] = { minRank = "Owner", run = function(ctx)
	local removed = State.carried(ctx.profile)
	for cropId in ctx.profile.rawCorn do ctx.profile.rawCorn[cropId] = 0 end
	State.publish(ctx.player.UserId)
	return true, "Bag emptied (" .. tostring(removed) .. " corn removed)"
end }

-- Grow: every stalk on the plot gets at least one ready cycle; stalks already holding more keep them.
commands["field.grow"] = { minRank = "Owner", run = function(ctx)
	local list = targetFields(ctx)
	if not list then return false, "Pick one of your plots" end
	local changed = setGrowth(ctx, list, function(_, ready) return if ready >= 1 then nil else 1 end)
	return true, "Grew " .. tostring(changed) .. " stalks on " .. fieldsLabel(list)
end }
-- Fill: every stalk holds its plot's full storage (crop maxYields + Stalk Storage level).
commands["field.fill"] = { minRank = "Owner", run = function(ctx)
	local list = targetFields(ctx)
	if not list then return false, "Pick one of your plots" end
	setGrowth(ctx, list, function(rules) return rules.maxYields end)
	local rules = FarmUpgrades.fieldRules(list[1])
	return true, "Filled " .. fieldsLabel(list) .. " · " .. tostring(rules.maxYields * rules.cornPerYield) .. " corn per stalk"
end }
-- Reset: every stalk starts a fresh cycle now (no ready corn).
commands["field.reset"] = { minRank = "Owner", run = function(ctx)
	local list = targetFields(ctx)
	if not list then return false, "Pick one of your plots" end
	setGrowth(ctx, list, function() return 0 end)
	return true, "Growth reset on " .. fieldsLabel(list)
end }
-- Progress: every stalk is `percent` of the way through its first cycle (100 = one ready cycle).
commands["field.progress"] = { minRank = "Owner", run = function(ctx)
	local list = targetFields(ctx)
	if not list then return false, "Pick one of your plots" end
	local percent = finite(ctx.args.percent, 0, 100)
	if not percent then return false, "Enter a growth percent from 0 to 100" end
	setGrowth(ctx, list, function() return percent / 100 end)
	return true, "Growth set to " .. tostring(math.floor(percent * 10 + 0.5) / 10) .. "% on " .. fieldsLabel(list)
end }

commands["upgrade.set"] = { minRank = "Owner", run = function(ctx)
	local upgradeId, problem = upgradeArg(ctx)
	if not upgradeId then return false, problem :: string end
	local wanted = ctx.args.level
	return changeUpgrade(ctx, upgradeId, function(_, max) return whole(wanted, 0, max) end)
end }
commands["upgrade.step"] = { minRank = "Owner", run = function(ctx)
	local upgradeId, problem = upgradeArg(ctx)
	if not upgradeId then return false, problem :: string end
	return changeUpgrade(ctx, upgradeId, function(current, max) return math.min(current + 1, max) end)
end }
commands["upgrade.max"] = { minRank = "Owner", run = function(ctx)
	local upgradeId, problem = upgradeArg(ctx)
	if not upgradeId then return false, problem :: string end
	return changeUpgrade(ctx, upgradeId, function(_, max) return max end)
end }
commands["upgrade.reset"] = { minRank = "Owner", run = function(ctx)
	local upgradeId, problem = upgradeArg(ctx)
	if not upgradeId then return false, problem :: string end
	return changeUpgrade(ctx, upgradeId, function() return 0 end)
end }
commands["upgrades.maxAll"] = { minRank = "Owner", run = function(ctx) return everyUpgrade(ctx, true) end }
commands["upgrades.resetAll"] = { minRank = "Owner", run = function(ctx) return everyUpgrade(ctx, false) end }

commands["tool.give"] = { minRank = "Owner", run = function(ctx)
	local toolId = toolArg(ctx)
	if not toolId then return false, "Unknown tool" end
	if not Tools.grant(ctx.player, toolId) then return false, Config.Tools[toolId].displayName .. " is already owned" end
	return true, Config.Tools[toolId].displayName .. " given"
end }
commands["tool.giveAll"] = { minRank = "Owner", run = function(ctx)
	local given = 0
	for _, toolId in sortedTools() do if Tools.grant(ctx.player, toolId) then given += 1 end end
	return true, "Unlocked every tool (" .. tostring(given) .. " new)"
end }
commands["tool.equip"] = { minRank = "Owner", run = function(ctx)
	local toolId = ctx.args.toolId
	if toolId ~= "Manual" and not toolArg(ctx) then return false, "Unknown tool" end
	local response = Tools.equip(ctx.player, toolId)
	return response.ok, response.reason
end }
commands["tool.remove"] = { minRank = "Owner", run = function(ctx)
	if ctx.args.toolId == "Manual" then return false, "Hand picking always stays" end
	local toolId = toolArg(ctx)
	if not toolId then return false, "Unknown tool" end
	if not Tools.revoke(ctx.player, toolId) then return false, Config.Tools[toolId].displayName .. " is not owned" end
	return true, Config.Tools[toolId].displayName .. " removed"
end }
commands["tool.reset"] = { minRank = "Owner", run = function(ctx)
	local removed = 0
	for toolId, owned in table.clone(ctx.profile.ownedTools) do
		if owned and toolId ~= "Manual" and Config.Tools[toolId] and Tools.revoke(ctx.player, toolId) then removed += 1 end
	end
	ctx.profile.ownedTools.Manual = true
	State.publish(ctx.player.UserId)
	return true, "Tools reset to the starter hands (" .. tostring(removed) .. " removed)"
end }

-- Land: the same limits and commits as the pads (UpgradeService.grantRow/grantPlot), free.
local function nextPlot(ctx: Context): (boolean, string)
	if Pricing.plotsBought(ctx.profile.fields) >= Config.Upgrades.ExtraPlot.max then return false, "Every plot is already yours" end
	local field = Upgrades.grantPlot(ctx.player, ctx.profile)
	Farms.update(now())
	return true, field.id .. " unlocked"
end
commands["land.plot"] = { minRank = "Owner", run = nextPlot }
commands["land.row"] = { minRank = "Owner", run = function(ctx)
	local field = ownField(ctx, ctx.args.fieldId)
	if not field then return false, "Pick one of your plots" end
	if field.rows >= Config.layoutRows() then return false, field.id .. " already has every row" end
	Upgrades.grantRow(ctx.player, ctx.profile, field)
	Farms.update(now())
	return true, "Row " .. tostring(field.rows) .. " planted on " .. field.id
end }
-- The bulk land commands build one plot or row at a time and yield between them, so a full
-- farm (up to 648 stalks) never builds in a single frame. Each step re-checks its limits and
-- commits on its own; the per-player busy flag keeps other admin commands out meanwhile.
commands["land.allPlots"] = { minRank = "Owner", run = function(ctx)
	local added = 0
	while Pricing.plotsBought(ctx.profile.fields) < Config.Upgrades.ExtraPlot.max do
		if State.get(ctx.player.UserId) ~= ctx.profile or not Farms.has(ctx.player.UserId) then return false, "Profile unavailable" end
		Upgrades.grantPlot(ctx.player, ctx.profile)
		added += 1
		task.wait()
	end
	Farms.update(now())
	return true, if added > 0 then "Unlocked " .. tostring(added) .. " plots" else "Every plot is already yours"
end }
commands["land.allRows"] = { minRank = "Owner", run = function(ctx)
	local added = 0
	local ids = {}
	for id in ctx.profile.fields do table.insert(ids, id) end
	table.sort(ids)
	for _, fieldId in ids do
		local field = ctx.profile.fields[fieldId]
		while field and field.rows < Config.layoutRows() do
			if State.get(ctx.player.UserId) ~= ctx.profile or not Farms.has(ctx.player.UserId) then return false, "Profile unavailable" end
			Upgrades.grantRow(ctx.player, ctx.profile, field)
			added += 1
			if added % 3 == 0 then task.wait() end
		end
	end
	Farms.update(now())
	return true, if added > 0 then "Planted " .. tostring(added) .. " rows" else "Every owned plot already has every row"
end }

commands["tp.farm"] = { minRank = "Owner", run = function(ctx)
	return teleport(ctx.player, Farms.spawnFrame(ctx.player.UserId), "your farm entrance")
end }
commands["tp.hub"] = { minRank = "Owner", run = function(ctx)
	return teleport(ctx.player, Map.hubFrame(), "the hub")
end }
commands["tp.plot"] = { minRank = "Owner", run = function(ctx)
	local field = ownField(ctx, ctx.args.fieldId)
	if not field then return false, "Pick one of your plots" end
	return teleport(ctx.player, Farms.plotFrame(ctx.player.UserId, field.id), field.id)
end }
-- Walk speed lives on the Owner's current Humanoid only, so a respawn restores normal speed.
commands["move.speed"] = { minRank = "Owner", run = function(ctx)
	local limits = AdminConfig.walkSpeed
	local speed = whole(ctx.args.speed, limits.min, limits.max)
	if not speed then return false, "Pick a walk speed from " .. tostring(limits.min) .. " to " .. tostring(limits.max) end
	local _, humanoid = character(ctx.player)
	if not humanoid then return false, "Character unavailable" end
	humanoid.WalkSpeed = speed
	return true, "Walk speed " .. tostring(speed)
end }
commands["move.reset"] = { minRank = "Owner", run = function(ctx)
	local _, humanoid = character(ctx.player)
	if not humanoid then return false, "Character unavailable" end
	humanoid.WalkSpeed = AdminConfig.walkSpeed.normal
	return true, "Walk speed back to normal"
end }

-- Read-only commands: the panel's opening handshake and refreshes.
commands["hello"] = { minRank = "Owner", run = function() return true, "Developer Panel ready (Studio only)" end }
commands["state"] = { minRank = "Owner", run = function() return true, "Refreshed" end }

---------------------------------------------------------------------------------------------
-- What the panel shows: the caller's own profile only (never other players' data).

function AdminService.snapshot(player: Player): { [string]: any }?
	local profile = State.get(player.UserId)
	if not profile then return nil end
	local at = now()
	local fields = {}
	for _, field in profile.fields do
		local crop = Config.Crops[field.cropId]
		local rules = FarmUpgrades.fieldRules(field)
		local stalks, readyCorn, readyStalks, fullStalks = 0, 0, 0, 0
		for _, stalk in field.stalks do
			stalks += 1
			local ready = Growth.yields(stalk.growthStartedAt, at, rules)
			readyCorn += ready * rules.cornPerYield
			if ready > 0 then readyStalks += 1 end
			if ready >= rules.maxYields then fullStalks += 1 end
		end
		table.insert(fields, {
			id = field.id, plot = field.plot, cropId = field.cropId, crop = if crop then crop.displayName else field.cropId,
			stalks = stalks, rows = field.rows, maxRows = Config.layoutRows(),
			Soil = field.upgrades.Soil, Yield = field.upgrades.Yield, Storage = field.upgrades.Storage,
			growthSeconds = rules.growthSeconds, maxYields = rules.maxYields, cornPerYield = rules.cornPerYield,
			maxCorn = rules.maxYields * rules.cornPerYield, readyCorn = readyCorn, readyStalks = readyStalks, fullStalks = fullStalks,
		})
	end
	table.sort(fields, function(a, b) return a.plot < b.plot end)
	local tools = {}
	for _, toolId in sortedTools() do
		table.insert(tools, { id = toolId, name = Config.Tools[toolId].displayName, owned = profile.ownedTools[toolId] == true })
	end
	local _, humanoid = character(player)
	return {
		name = player.Name, displayName = player.DisplayName, userId = player.UserId,
		cash = profile.cash, popcorn = profile.popcorn, rawCorn = table.clone(profile.rawCorn),
		carried = State.carried(profile), capacity = State.bagCapacity(profile),
		equippedTool = profile.equippedTool, tools = tools,
		Backpack = profile.upgrades.Backpack, fields = fields,
		plots = #fields, maxPlots = Config.Upgrades.ExtraPlot.max + 1, rowsBought = Pricing.rowsBought(profile.fields),
		walkSpeed = if humanoid then humanoid.WalkSpeed else nil, maxBalance = AdminConfig.maxBalance,
		walkLimits = { min = AdminConfig.walkSpeed.min, max = AdminConfig.walkSpeed.max, normal = AdminConfig.walkSpeed.normal },
	}
end

---------------------------------------------------------------------------------------------
-- The one request entry point (also what the remote calls). Order: environment, rank, rate,
-- request id, shape, command; then the command runs against the caller's own profile.

local function session(userId: number): Session
	local s = sessions[userId]
	if not s then
		s = { tokens = AdminConfig.rate.burst, refilledAt = os.clock(), lastId = 0, busy = false, refusedLogAt = -math.huge }
		sessions[userId] = s
	end
	return s
end

local function refuse(player: Player, reason: string): Response
	-- Unauthorized callers get no state and at most one log line every 10 seconds.
	local s = session(player.UserId)
	if os.clock() - s.refusedLogAt > 10 then
		s.refusedLogAt = os.clock()
		warn("[Admin] refused " .. player.Name .. ": " .. reason)
	end
	return { ok = false, reason = reason }
end

local function validArgs(args: unknown): Args?
	if args == nil then return {} end
	if typeof(args) ~= "table" then return nil end
	local count = 0
	for key, value in args :: { [any]: any } do
		count += 1
		if count > MAX_ARGS or typeof(key) ~= "string" or #key > MAX_STRING then return nil end
		local kind = typeof(value)
		if kind == "string" then
			if #value > MAX_STRING then return nil end
		elseif kind ~= "number" and kind ~= "boolean" then
			return nil
		end
	end
	return args :: Args
end

function AdminService.handle(player: Player, requestId: unknown, command: unknown, args: unknown): Response
	if not AdminConfig.mutationsAllowed(isStudio()) then return refuse(player, "Developer Panel is disabled outside Studio") end
	local rank = AdminService.rankOf(player)
	if not rank then return refuse(player, "Not authorized") end
	local s = session(player.UserId)
	local clock = os.clock()
	s.tokens = math.min(AdminConfig.rate.burst, s.tokens + (clock - s.refilledAt) * AdminConfig.rate.perSecond)
	s.refilledAt = clock
	if s.tokens < 1 then return { ok = false, reason = "Too many requests · slow down" } end
	s.tokens -= 1
	local id = whole(requestId, 1, 2 ^ 31)
	if not id then return { ok = false, reason = "Invalid request" } end
	-- A stale id never runs. lastId lets an honest panel resync its counter (it does not retry).
	if id <= s.lastId then return { ok = false, reason = "Duplicate request ignored", lastId = s.lastId } end
	if typeof(command) ~= "string" or #command > MAX_COMMAND or not commands[command] then return { ok = false, reason = "Unknown command" } end
	local entry = commands[command]
	if not AdminConfig.atLeast(rank, entry.minRank) then return refuse(player, "Rank too low for " .. command) end
	local checked = validArgs(args)
	if not checked then return { ok = false, reason = "Invalid arguments" } end
	if s.busy then return { ok = false, reason = "Still working on the last command" } end
	local profile = State.get(player.UserId)
	if not profile or not Farms.has(player.UserId) then return { ok = false, reason = "Profile unavailable" } end
	s.lastId = id
	s.busy = true
	local ran, okOrError, reason = pcall(entry.run, { player = player, profile = profile, args = checked, now = now() })
	s.busy = false
	local ok = ran and okOrError == true
	local message = if ran then tostring(reason) else "Command failed (see Output)"
	if not ran then warn("[Admin] " .. command .. " error: " .. tostring(okOrError)) end
	if command ~= "state" and command ~= "hello" then log(player, command, ok, message) end
	return { ok = ok, reason = message, state = AdminService.snapshot(player) }
end

-- Creates the admin remote under `remotes`, only where testing mutations are allowed.
-- Returns the remote, or nil (production: nothing is created, so there is nothing to fire).
function AdminService.init(remotes: Folder): RemoteFunction?
	AdminConfig.validate()
	if not AdminConfig.mutationsAllowed(isStudio()) then return nil end
	local remote = Instance.new("RemoteFunction")
	remote.Name = "AdminRequest"
	remote.OnServerInvoke = function(player: Player, requestId: unknown, command: unknown, args: unknown)
		return AdminService.handle(player, requestId, command, args)
	end
	remote.Parent = remotes
	return remote
end

function AdminService.release(userId: number)
	sessions[userId] = nil
end

-- The command names, for tests and docs.
function AdminService.commandNames(): { string }
	local names = {}
	for name in commands do table.insert(names, name) end
	table.sort(names)
	return names
end

return AdminService
