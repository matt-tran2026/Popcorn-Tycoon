--!strict
-- Temporary Server RunContext integration runner during Play (Owner Developer Panel, Nov 4 2026).
-- Install outside the synced PopcornTycoon folder: create it in Edit mode with the Studio MCP
-- multi_edit tool at ServerScriptService.PopcornTestRunners.Admin, start Play, read its
-- Results attribute, stop Play and delete the folder. Run it alone (one runner per Play).
-- Covers authorization (Owner allowlist, Studio test users, creator rule, environment policy,
-- an unauthorized caller at the same entry point the remote uses), request validation, replay
-- and rate limits, every command group (economy, farming, upgrades, tools, land, teleport,
-- movement), the replicated attributes the HUD/menus read, ordinary harvests and purchases
-- afterwards, and isolation from a second owner's profile. It leaves the player with every
-- plot and row (like Economy's land checks) but resets balances, upgrades and tools.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local FarmUpgrades = require(Shared.FarmUpgrades)
local Pricing = require(Shared.Pricing)
local Services = game:GetService("ServerScriptService"):WaitForChild("PopcornTycoon")
local State = require(Services.PlayerStateService)
local Farms = require(Services.FarmService)
local Harvest = require(Services.HarvestService)
local Upgrades = require(Services.UpgradeService)
local Map = require(Services.MapVisuals)
local AdminConfig = require(Services.AdminConfig)
local Admin = require(Services.AdminService)
local checks: { { name: string, passed: boolean } } = {}
local function check(name: string, condition: boolean)
	table.insert(checks, { name = name, passed = condition })
	assert(condition, name)
end
local deadline = os.clock() + 30
while os.clock() < deadline do
	local first = Players:GetPlayers()[1]
	if first and first.Character and State.get(first.UserId) and Farms.has(first.UserId) then break end
	task.wait(0.25)
end
task.wait(1)
local player = assert(Players:GetPlayers()[1], "Requires a live player")
local profile = assert(State.get(player.UserId))
local fixtureId = -9000005
local function now(): number return DateTime.now().UnixTimestampMillis / 1000 end
local function root(): BasePart return assert(assert(player.Character):FindFirstChild("HumanoidRootPart")) :: BasePart end
local requestId = 10 ^ 8
-- One admin request through AdminService.handle (what the remote's OnServerInvoke calls).
-- The pause keeps the sequence inside the token bucket's refill rate.
local function admin(command: string, args: { [string]: any }?): Admin.Response
	task.wait(1 / AdminConfig.rate.perSecond + 0.02)
	requestId += 1
	return Admin.handle(player, requestId, command, args)
end
local function yieldsOf(field: any, at: number): { number }
	local rules = FarmUpgrades.fieldRules(field)
	local list = {}
	for _, stalk in field.stalks do table.insert(list, Growth.yields(stalk.growthStartedAt, at, rules)) end
	return list
end
local function all(list: { number }, predicate: (number) -> boolean): boolean
	for _, v in list do if not predicate(v) then return false end end
	return #list > 0
end

local ok, err = pcall(function()
	-- 1. Authorization policy (pure) and environment.
	local owner = next(AdminConfig.Members) :: number
	local user = { creatorType = Enum.CreatorType.User, creatorId = 555 }
	local group = { creatorType = Enum.CreatorType.Group, creatorId = 555 }
	check("allowlisted UserId is Owner", AdminConfig.rankOf(owner, true, nil) == "Owner" and AdminConfig.rankOf(owner, false, nil) == "Owner")
	check("an unknown UserId has no rank", AdminConfig.rankOf(123456789, true, nil) == nil)
	check("Studio test Player1 (-1) is Owner only in Studio", AdminConfig.rankOf(-1, true, nil) == "Owner" and AdminConfig.rankOf(-1, false, nil) == nil)
	check("Studio test Player2 (-2) has no rank", AdminConfig.rankOf(-2, true, nil) == nil)
	check("the creator of a user-owned experience is Owner", AdminConfig.rankOf(555, false, user) == "Owner")
	check("a group-owned experience grants nothing to id 555", AdminConfig.rankOf(555, false, group) == nil)
	check("malformed ids have no rank", AdminConfig.rankOf(0 / 0, true, nil) == nil and AdminConfig.rankOf(1.5, true, nil) == nil)
	check("mutations are disabled outside Studio by default", AdminConfig.mutationsAllowed(false) == false and AdminConfig.mutationsAllowed(true) == true)
	check("rank comparison", AdminConfig.atLeast("Owner", "Owner") and not AdminConfig.atLeast(nil, "Owner") and not AdminConfig.atLeast("Nope", "Owner"))
	local remotes = Shared:FindFirstChild("Remotes")
	local remote = if remotes then remotes:FindFirstChild("AdminRequest") else nil
	check("the admin remote exists in Studio as a RemoteFunction", remote ~= nil and remote:IsA("RemoteFunction"))
	check("the Play Solo player is the Owner", Admin.rankOf(player) == "Owner")

	-- 2. An ordinary player at the remote's entry point gets nothing, whatever it sends.
	local cashBefore = profile.cash
	local intruder: any = { UserId = 123456789, Name = "Intruder" }
	local refusedAll = true
	for i, name in Admin.commandNames() do
		local r = Admin.handle(intruder, 10 ^ 9 + i, name, { amount = 1e6, fieldId = "Plot1", upgradeId = "Soil", toolId = "Sickle", level = 4 })
		if r.ok or r.state ~= nil or r.reason ~= "Not authorized" then refusedAll = false end
	end
	check("an unauthorized caller is refused every command with no state", refusedAll)
	local test2: any = { UserId = -2, Name = "Player2" }
	local r2 = Admin.handle(test2, 1, "cash.add", { amount = 1e6 })
	check("Studio test Player2 is refused", not r2.ok and r2.state == nil)
	check("refused requests changed nothing", profile.cash == cashBefore)

	-- A second owner (fixture) whose profile must never change.
	local fixture = State.load(fixtureId, now())
	Farms.create(fixtureId, fixture.fields)
	local fixtureStarts: { [string]: number } = {}
	for id, stalk in fixture.fields.Plot1.stalks do fixtureStarts[id] = stalk.growthStartedAt end

	-- 3. Request validation, replay and rate limits.
	local r = admin("hello")
	check("hello returns the caller's own snapshot", r.ok and r.state ~= nil and (r.state :: any).userId == player.UserId)
	requestId += 1
	local first = Admin.handle(player, requestId, "cash.set", { amount = 1000 })
	task.wait(0.25)
	local replay = Admin.handle(player, requestId, "cash.add", { amount = 1000 })
	check("a replayed request id is refused and grants nothing", first.ok and not replay.ok and profile.cash == 1000)
	task.wait(0.25)
	check("an older request id is refused", not Admin.handle(player, requestId - 5, "cash.add", { amount = 1 }).ok and profile.cash == 1000)
	check("an unknown command is refused", not admin("cash.steal", { amount = 1 }).ok)
	check("a non-number request id is refused", not Admin.handle(player, "x" :: any, "state", nil).ok)
	local big = {}
	for i = 1, 9 do big["k" .. i] = i end
	check("too many arguments are refused", not admin("cash.add", big).ok)
	check("nested tables are refused", not admin("cash.add", { amount = { 1 } }).ok)
	check("long strings are refused", not admin("tool.give", { toolId = string.rep("S", 40) }).ok)
	check("non-table arguments are refused", not admin("cash.add", "1000" :: any).ok)
	task.wait(2.5)
	local limited = 0
	for i = 1, AdminConfig.rate.burst + 6 do
		requestId += 1
		if Admin.handle(player, requestId, "state", nil).reason == "Too many requests · slow down" then limited += 1 end
	end
	check("bursts beyond the token bucket are refused", limited >= 5)
	task.wait(AdminConfig.rate.burst / AdminConfig.rate.perSecond + 0.5)

	-- 4. Economy: Cash, popcorn and raw corn on the real profile and attributes.
	check("give cash", admin("cash.add", { amount = 1e6 }).ok and profile.cash == 1001000 and player:GetAttribute("Cash") == 1001000)
	check("remove cash", admin("cash.remove", { amount = 1000 }).ok and profile.cash == 1e6)
	check("remove never goes below zero", admin("cash.remove", { amount = 5e6 }).ok and profile.cash == 0)
	check("set cash exactly", admin("cash.set", { amount = 123456 }).ok and profile.cash == 123456 and player:GetAttribute("Cash") == 123456)
	check("max cash is the testing max", admin("cash.max").ok and profile.cash == AdminConfig.maxBalance)
	check("adding past the max clamps", admin("cash.add", { amount = 5 }).ok and profile.cash == AdminConfig.maxBalance)
	check("zero cash", admin("cash.zero").ok and profile.cash == 0 and player:GetAttribute("Cash") == 0)
	local bad = { 0 / 0, math.huge, -math.huge, -5, 2.5, AdminConfig.maxBalance + 1, "100" :: any, true :: any }
	local allRefused = true
	for _, value in bad do if admin("cash.add", { amount = value }).ok then allRefused = false end end
	check("NaN, infinity, negative, fractional, too large and non-number amounts are refused", allRefused and profile.cash == 0)
	check("give 0 is refused but set 0 is allowed", not admin("cash.add", { amount = 0 }).ok and admin("cash.set", { amount = 0 }).ok)
	check("give popcorn", admin("popcorn.add", { amount = 500 }).ok and profile.popcorn == 500 and player:GetAttribute("Popcorn") == 500)
	task.wait(0.1)
	local stand = Farms.sellStand(player.UserId)
	local sell = if stand then stand:FindFirstChild("Sell") :: ProximityPrompt? else nil
	check("the sell stand's payout follows the popcorn grant", sell ~= nil and string.find(sell.ObjectText, "500 popcorn", 1, true) ~= nil)
	check("set/remove/clear popcorn", admin("popcorn.set", { amount = 900 }).ok and admin("popcorn.remove", { amount = 100 }).ok and profile.popcorn == 800
		and admin("popcorn.zero").ok and profile.popcorn == 0)
	check("empty the bag", admin("corn.empty").ok and State.carried(profile) == 0 and player:GetAttribute("RawCorn") == 0)
	check("add raw corn", admin("corn.add", { cropId = "Normal", amount = 10 }).ok and profile.rawCorn.Normal == 10 and player:GetAttribute("RawCorn") == 10)
	local fill = admin("corn.fill", { cropId = "Normal" })
	check("fill the bag to its capacity", fill.ok and State.carried(profile) == State.bagCapacity(profile) and player:GetAttribute("RawCorn") == State.bagCapacity(profile))
	check("adding to a full bag is refused", not admin("corn.add", { cropId = "Normal", amount = 1 }).ok and State.carried(profile) == State.bagCapacity(profile))
	check("an unknown corn type is refused", not admin("corn.add", { cropId = "Golden", amount = 1 }).ok)
	check("the snapshot shows corn and capacity", (fill.state :: any).carried == State.bagCapacity(profile) and (fill.state :: any).capacity == State.bagCapacity(profile))
	check("empty again", admin("corn.empty").ok and State.carried(profile) == 0)

	-- 5. Farming on Plot1: timestamps only, visuals follow on the same tick.
	local plot1 = profile.fields.Plot1
	local function stalkParts(): { Part }
		local list = {}
		for id, part in Farms.stalkParts(player.UserId) do
			if Farms.fieldOf(player.UserId, id) == "Plot1" then table.insert(list, part) end
		end
		return list
	end
	local function partsAll(predicate: (Part) -> boolean): boolean
		for _, part in stalkParts() do if not predicate(part) then return false end end
		return true
	end
	check("reset growth clears every ready cycle", admin("field.reset", { fieldId = "Plot1" }).ok and all(yieldsOf(plot1, now()), function(y) return y == 0 end))
	check("reset growth redraws stalks as seedlings with no corn", partsAll(function(p) return p:GetAttribute("AvailableYields") == 0 and p:GetAttribute("GrowthStage") == 0 end))
	check("instantly grow makes every stalk harvestable", admin("field.grow", { fieldId = "Plot1" }).ok and all(yieldsOf(plot1, now()), function(y) return y >= 1 end))
	check("grown stalks are drawn ripe", partsAll(function(p) return (p:GetAttribute("AvailableYields") :: number) >= 1 and p:GetAttribute("GrowthStage") == 3 end))
	local rules = FarmUpgrades.fieldRules(plot1)
	check("fill stalks reaches the plot's storage (3 cycles unupgraded)", admin("field.fill", { fieldId = "Plot1" }).ok
		and rules.maxYields == 3 and all(yieldsOf(plot1, now()), function(y) return y == rules.maxYields end))
	check("filled stalks are drawn full", partsAll(function(p) return p:GetAttribute("Full") == true and p:GetAttribute("AvailableYields") == 3 end))
	check("progress 50% is half a cycle and drawn at stage 1", admin("field.progress", { fieldId = "Plot1", percent = 50 }).ok
		and all(yieldsOf(plot1, now()), function(y) return y == 0 end) and partsAll(function(p) return p:GetAttribute("GrowthStage") == 1 end))
	check("invalid percents are refused", not admin("field.progress", { fieldId = "Plot1", percent = 101 }).ok
		and not admin("field.progress", { fieldId = "Plot1", percent = 0 / 0 }).ok and not admin("field.progress", { fieldId = "Plot1", percent = -1 }).ok)
	check("unowned or invalid plots are refused", not admin("field.grow", { fieldId = "Plot9" }).ok and not admin("field.grow", { fieldId = 1 }).ok
		and not admin("field.grow").ok)
	-- Timestamp consistency: 90% grown finishes its cycle in real time, once.
	admin("field.progress", { fieldId = "Plot1", percent = 90 })
	local cycle = FarmUpgrades.fieldRules(plot1).growthSeconds
	task.wait(cycle * 0.1 + 0.5)
	check("90% grown finishes the cycle on time and then grows normally", all(yieldsOf(plot1, now()), function(y) return y == 1 end))
	-- Ordinary harvesting afterwards: a full stalk with room for one cycle takes one and keeps the rest.
	admin("field.fill", { fieldId = "Plot1" })
	admin("corn.fill", { cropId = "Normal" })
	profile.rawCorn.Normal -= 1 -- room for exactly one cycle (direct test setup, like other runners)
	local stalkId, stalk = next(plot1.stalks)
	local target = assert(Farms.target(player.UserId, "Plot1", stalkId :: string))
	root().CFrame = CFrame.new(target.Position + Vector3.new(0, 1, 2))
	task.wait(0.35)
	local picked = Harvest.attempt(player, player.UserId, "Plot1", stalkId)
	check("a normal hand harvest still works after admin growth", picked.ok and picked.amount == 1)
	check("partial harvest keeps the rest on the stalk", Growth.yields((stalk :: any).growthStartedAt, now(), FarmUpgrades.fieldRules(plot1)) == 2)
	admin("corn.empty")

	-- 6. Upgrades: levels through the same commit as purchases, no Cash charged.
	admin("cash.set", { amount = 0 })
	check("set Backpack level", admin("upgrade.set", { upgradeId = "Backpack", level = 2 }).ok and profile.upgrades.Backpack == 2
		and player:GetAttribute("BagCapacity") == FarmUpgrades.effect("Backpack", 2) and profile.cash == 0)
	check("+1 Backpack", admin("upgrade.step", { upgradeId = "Backpack" }).ok and profile.upgrades.Backpack == 3)
	check("max Backpack", admin("upgrade.max", { upgradeId = "Backpack" }).ok and profile.upgrades.Backpack == FarmUpgrades.maxLevel("Backpack")
		and player:GetAttribute("Upgrade_Backpack") == FarmUpgrades.maxLevel("Backpack"))
	admin("corn.fill", { cropId = "Normal" })
	check("a bigger bag holds more corn", State.carried(profile) == FarmUpgrades.effect("Backpack", FarmUpgrades.maxLevel("Backpack")))
	check("reset Backpack trims the bag to the base size", admin("upgrade.reset", { upgradeId = "Backpack" }).ok and profile.upgrades.Backpack == 0
		and State.carried(profile) == Config.Inventory.capacity and player:GetAttribute("RawCorn") == Config.Inventory.capacity)
	admin("corn.empty")
	check("invalid levels are refused", not admin("upgrade.set", { upgradeId = "Soil", fieldId = "Plot1", level = 99 }).ok
		and not admin("upgrade.set", { upgradeId = "Soil", fieldId = "Plot1", level = -1 }).ok
		and not admin("upgrade.set", { upgradeId = "Soil", fieldId = "Plot1", level = 1.5 }).ok
		and not admin("upgrade.set", { upgradeId = "Rocket", level = 1 }).ok
		and not admin("upgrade.max", { upgradeId = "Soil" }).ok)
	-- Soil keeps full stalks full and speeds up growth.
	admin("field.fill", { fieldId = "Plot1" })
	check("Soil max shortens the growth time", admin("upgrade.max", { upgradeId = "Soil", fieldId = "Plot1" }).ok
		and FarmUpgrades.fieldRules(plot1).growthSeconds == FarmUpgrades.rules(Config.Crops.Normal, { Soil = FarmUpgrades.maxLevel("Soil"), Yield = 0, Storage = 0 }).growthSeconds
		and player:GetAttribute("Upgrade_Plot1_Soil") == FarmUpgrades.maxLevel("Soil"))
	check("a Soil change keeps full stalks full (rebase)", all(yieldsOf(plot1, now()), function(y) return y == 3 end))
	check("Yield 2 gives 3 corn per cycle on the stalks", admin("upgrade.set", { upgradeId = "Yield", fieldId = "Plot1", level = 2 }).ok
		and FarmUpgrades.fieldRules(plot1).cornPerYield == 3 and partsAll(function(p) return p:GetAttribute("CornPerYield") == 3 end))
	check("Storage max raises stored cycles", admin("upgrade.max", { upgradeId = "Storage", fieldId = "Plot1" }).ok
		and FarmUpgrades.fieldRules(plot1).maxYields == Config.Crops.Normal.maxYields + FarmUpgrades.effect("Storage", FarmUpgrades.maxLevel("Storage")))
	local maxed = FarmUpgrades.fieldRules(plot1)
	local filled = admin("field.fill", { fieldId = "Plot1" })
	check("fill respects the upgraded storage", filled.ok and all(yieldsOf(plot1, now()), function(y) return y == maxed.maxYields end))
	local shown = (filled.state :: any).fields[1]
	check("the snapshot reports the plot's effective values", shown.id == "Plot1" and shown.maxCorn == maxed.maxYields * maxed.cornPerYield
		and shown.growthSeconds == maxed.growthSeconds and shown.Storage == FarmUpgrades.maxLevel("Storage"))
	check("upgrade commands never charged Cash", profile.cash == 0)

	-- 7. Land: a second plot keeps its own levels; free rows and plots use the pad commits.
	local plots = Pricing.plotsBought(profile.fields) + 1
	local landed = admin("land.plot")
	check("unlock the next plot for free", landed.ok and Pricing.plotsBought(profile.fields) + 1 == plots + 1 and profile.cash == 0)
	local second = profile.fields["Plot" .. tostring(plots + 1)]
	check("a new plot starts unupgraded and ripe", second ~= nil and second.upgrades.Storage == 0 and all(yieldsOf(second, now()), function(y) return y == 1 end))
	check("different plots keep independent levels", plot1.upgrades.Storage == FarmUpgrades.maxLevel("Storage") and second.upgrades.Storage == 0)
	local rowsBefore = second.rows
	check("add a row for free", admin("land.row", { fieldId = second.id }).ok and second.rows == rowsBefore + 1 and profile.cash == 0)
	local count = 0
	for _ in second.stalks do count += 1 end
	check("the new row planted valid stalks", count == second.rows * Config.Plot.columns
		and Farms.target(player.UserId, second.id, State.stalkId(second.plot, second.rows, 1)) ~= nil)
	check("adding a row to an unowned plot is refused", not admin("land.row", { fieldId = "Plot42" }).ok)
	check("upgrades on All plots", admin("upgrade.set", { upgradeId = "Yield", fieldId = "*", level = 1 }).ok
		and plot1.upgrades.Yield == 1 and second.upgrades.Yield == 1)
	check("max all upgrades", admin("upgrades.maxAll").ok and profile.upgrades.Backpack == FarmUpgrades.maxLevel("Backpack")
		and second.upgrades.Soil == FarmUpgrades.maxLevel("Soil") and plot1.upgrades.Yield == FarmUpgrades.maxLevel("Yield"))
	check("reset all upgrades", admin("upgrades.resetAll").ok and profile.upgrades.Backpack == 0 and plot1.upgrades.Storage == 0
		and second.upgrades.Yield == 0 and player:GetAttribute("Upgrade_Plot1_Storage") == 0)
	-- The ordinary Upgrades menu still charges its price.
	admin("cash.set", { amount = 1000 })
	task.wait(Config.UpgradeMenu.requestCooldownSeconds + 0.05)
	local bought = Upgrades.buyUpgrade(player, "Soil", "Plot1")
	check("a normal upgrade purchase still charges Cash", bought.ok and profile.cash == 1000 - (FarmUpgrades.price("Soil", 0) :: number) and plot1.upgrades.Soil == 1)
	admin("upgrade.reset", { upgradeId = "Soil", fieldId = "Plot1" })

	-- 8. Tools.
	check("reset tools to the starter hands", admin("tool.reset").ok and profile.ownedTools.Manual == true and not profile.ownedTools.Sickle)
	check("give the Sickle", admin("tool.give", { toolId = "Sickle" }).ok and profile.ownedTools.Sickle == true and player:GetAttribute("Owned_Sickle") == true)
	task.wait(0.3)
	local backpack = player:FindFirstChildOfClass("Backpack")
	check("the Sickle Tool is in the backpack", backpack ~= nil and backpack:FindFirstChild("Sickle") ~= nil)
	check("giving it again is refused", not admin("tool.give", { toolId = "Sickle" }).ok)
	check("unknown and unfinished tools are refused", not admin("tool.give", { toolId = "Flamethrower" }).ok and not admin("tool.equip", { toolId = "Laser" }).ok)
	check("equip the Sickle", admin("tool.equip", { toolId = "Sickle" }).ok)
	task.wait(0.4)
	check("the Sickle is equipped", profile.equippedTool == "Sickle" and player:GetAttribute("EquippedTool") == "Sickle")
	-- A normal swing still harvests after admin changes.
	admin("field.grow", { fieldId = "Plot1" })
	admin("tp.plot", { fieldId = "Plot1" })
	task.wait(0.4)
	local swing = Harvest.swing(player, "Sickle")
	check("a normal Sickle swing still harvests", swing.ok and swing.amount >= 1)
	admin("corn.empty")
	check("remove the equipped Sickle falls back to hands", admin("tool.remove", { toolId = "Sickle" }).ok and profile.equippedTool == "Manual"
		and not profile.ownedTools.Sickle and player:GetAttribute("Owned_Sickle") == nil and player:GetAttribute("EquippedTool") == "Manual")
	task.wait(0.3)
	local character = assert(player.Character)
	local leftover = (backpack and backpack:FindFirstChild("Sickle")) or character:FindFirstChild("Sickle")
	check("no Sickle Tool is left behind", leftover == nil)
	check("hands can never be removed", not admin("tool.remove", { toolId = "Manual" }).ok and profile.ownedTools.Manual == true)
	check("unlock all tools", admin("tool.giveAll").ok and profile.ownedTools.Sickle == true)
	check("swinging a removed tool is refused", admin("tool.reset").ok and not Harvest.swing(player, "Sickle").ok)

	-- 9. Teleport and movement.
	local function near(frame: CFrame?): boolean
		task.wait(0.3)
		return frame ~= nil and (root().Position - frame.Position).Magnitude < 6
	end
	check("teleport to the farm entrance", admin("tp.farm").ok and near(Farms.spawnFrame(player.UserId)))
	check("teleport to the hub", admin("tp.hub").ok and near(Map.hubFrame()))
	check("teleport to a selected plot", admin("tp.plot", { fieldId = second.id }).ok and near(Farms.plotFrame(player.UserId, second.id)))
	check("teleport to an unowned plot is refused", not admin("tp.plot", { fieldId = "Plot77" }).ok)
	local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
	check("walk speed", admin("move.speed", { speed = 64 }).ok and humanoid.WalkSpeed == 64)
	check("out-of-range walk speed is refused", not admin("move.speed", { speed = 5000 }).ok and not admin("move.speed", { speed = 0 / 0 }).ok and humanoid.WalkSpeed == 64)
	check("normal walk speed", admin("move.reset").ok and humanoid.WalkSpeed == AdminConfig.walkSpeed.normal)

	-- 10. Bulk land last (heavy): one command at a time per player, limits respected.
	-- task.spawn runs the bulk command until its first yield (after one plot), so the next
	-- request deterministically arrives while it is still running.
	task.wait(1)
	local allPlots: Admin.Response? = nil
	requestId += 1
	local bulkId = requestId
	task.spawn(function() allPlots = Admin.handle(player, bulkId, "land.allPlots", nil) end)
	requestId += 1
	local busyReply = Admin.handle(player, requestId, "state", nil)
	local until_ = os.clock() + 20
	while allPlots == nil and os.clock() < until_ do task.wait(0.1) end
	check("unlock all plots stops at the configured maximum", allPlots ~= nil and (allPlots :: any).ok and Pricing.plotsBought(profile.fields) == Config.Upgrades.ExtraPlot.max)
	check("other commands wait while a bulk command runs", not busyReply.ok and busyReply.reason == "Still working on the last command")
	check("no plot pad remains once every plot is owned", Farms.plotPad(player.UserId) == nil and not admin("land.plot").ok)
	check("fill all rows", admin("land.allRows").ok)
	local full, stalksOk = true, true
	for _, field in profile.fields do
		if field.rows ~= Config.layoutRows() then full = false end
		local n = 0
		for _ in field.stalks do n += 1 end
		if n ~= field.rows * Config.Plot.columns then stalksOk = false end
		if Farms.rowPad(player.UserId, field.id) ~= nil then full = false end
	end
	check("every owned plot has every row and no row pad", full)
	check("every plot holds rows x columns stalks", stalksOk)
	check("adding a row to a full plot is refused", not admin("land.row", { fieldId = "Plot1" }).ok)

	-- 11. Isolation: the other owner's profile and farm never changed.
	local same = true
	for id, start in fixtureStarts do if fixture.fields.Plot1.stalks[id].growthStartedAt ~= start then same = false end end
	local fixtureFields = 0
	for _ in fixture.fields do fixtureFields += 1 end
	check("the second owner's profile is untouched", fixture.cash == 0 and fixture.popcorn == 0 and fixture.rawCorn.Normal == 0
		and fixture.upgrades.Backpack == 0 and fixture.fields.Plot1.upgrades.Storage == 0 and not fixture.ownedTools.Sickle and fixtureFields == 1 and same)
	check("a userId argument is ignored (commands target the caller)", admin("cash.add", { amount = 7, userId = fixtureId }).ok and fixture.cash == 0)

	-- 12. Leave the player with fresh balances, upgrades and tools (plots stay, like Economy).
	admin("upgrades.resetAll")
	admin("tool.reset")
	admin("corn.empty")
	admin("cash.set", { amount = 0 })
	admin("popcorn.set", { amount = 0 })
	check("cleanup leaves base values", profile.cash == 0 and profile.popcorn == 0 and State.carried(profile) == 0 and player:GetAttribute("BagCapacity") == Config.Inventory.capacity)
end)

pcall(function()
	Farms.remove(fixtureId)
	State.release(fixtureId)
end)
script:SetAttribute("Results", Http:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = checks }))
print("[Admin tests] " .. (if ok then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
