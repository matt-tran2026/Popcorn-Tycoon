--!strict
-- Temporary Server RunContext integration runner during Play (farm upgrades, Nov 4 2026).
-- Install outside the synced PopcornTycoon folder (Nov 4 2026: the MCP Luau sandbox can no longer
-- parent scripts, so create it in Edit mode with the Studio MCP multi_edit tool at
-- ServerScriptService.PopcornTestRunners.<Name> and start Play); delete it after reading Results.
-- Covers the four upgrades' rules, purchases and server validation, growth rebasing, harvest
-- integration (hands and sickle), per-plot isolation, new plots/rows, a second owner, and the
-- replicated state the Upgrades menu reads. Run after Tools and before Economy: it resets the
-- player's upgrade levels at the end but leaves an extra plot (like Economy's land checks).
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local FarmUpgrades = require(Shared.FarmUpgrades)
local Types = require(Shared.Types)
local Money = require(Shared.Money)
local Services = game:GetService("ServerScriptService"):WaitForChild("PopcornTycoon")
local State = require(Services.PlayerStateService)
local Farms = require(Services.FarmService)
local Harvest = require(Services.HarvestService)
local Upgrades = require(Services.UpgradeService)
local Tools = require(Services.ToolService)
local checks: { { name: string, passed: boolean } } = {}
local function check(name: string, condition: boolean)
	table.insert(checks, { name = name, passed = condition })
	assert(condition, name)
end
-- Also works as a Play-start runner: wait for the first player's profile, farm and character.
local deadline = os.clock() + 30
while os.clock() < deadline do
	local first = Players:GetPlayers()[1]
	if first and first.Character and State.get(first.UserId) and Farms.has(first.UserId) then break end
	task.wait(0.25)
end
task.wait(1)
local player = assert(Players:GetPlayers()[1], "Requires a live player")
local fixtureId = -9000004
local function now(): number return DateTime.now().UnixTimestampMillis / 1000 end
local function root(): BasePart return assert(assert(player.Character):FindFirstChild("HumanoidRootPart")) :: BasePart end
local GAP = Config.UpgradeMenu.requestCooldownSeconds + 0.05
local function buy(id: unknown, fieldId: unknown): Types.ActionResult
	task.wait(GAP)
	return Upgrades.buyUpgrade(player, id, fieldId)
end
local crop = Config.Crops.Normal

local ok, err = pcall(function()
	-- 1. Pure rules: levels, effects, formulas, prices.
	local function rules(soil: number, yield: number, storage: number): Types.GrowthRules
		return FarmUpgrades.rules(crop, { Soil = soil, Yield = yield, Storage = storage })
	end
	local caps, times, corn, cycles = {}, {}, {}, {}
	for level = 0, 4 do
		table.insert(caps, FarmUpgrades.bagCapacity({ Backpack = level }))
		table.insert(times, rules(level, 0, 0).growthSeconds)
		table.insert(corn, rules(0, level, 0).cornPerYield)
		table.insert(cycles, rules(0, 0, level).maxYields)
	end
	check("backpack capacities 50/100/200/400/800", table.concat(caps, ",") == "50,100,200,400,800")
	check("soil growth times 10/9/8/7/6 s", table.concat(times, ",") == "10,9,8,7,6")
	check("corn per cycle 1..5", table.concat(corn, ",") == "1,2,3,4,5")
	check("stored cycles 3/4/5/7/10", table.concat(cycles, ",") == "3,4,5,7,10")
	local prices = {}
	for _, id in Config.FarmUpgradeOrder do
		local row = {}
		for level = 0, 4 do table.insert(row, tostring(FarmUpgrades.price(id, level) or "max")) end
		prices[id] = table.concat(row, ",")
	end
	check("backpack prices", prices.Backpack == "200,1200,7200,43000,max")
	check("soil prices", prices.Soil == "300,900,2700,8100,max")
	check("yield prices", prices.Yield == "500,2000,8000,32000,max")
	check("storage prices", prices.Storage == "750,2300,6800,20000,max")
	-- Display: whole prices never truncate down a cent-step (2.3 * 100 is 229.999 in floats).
	check("prices display exactly", Money.cash(2300) == "$2.3K" and Money.cash(4050) == "$4.05K" and Money.cash(6114) == "$6.11K"
		and Money.cash(61140) == "$61.1K" and Money.cash(2500000) == "$2.5M" and Money.cash(999) == "$999" and Money.cash(43000) == "$43K")
	local long = 1e9
	local function maxCorn(r: Types.GrowthRules): number return Growth.corn(0, long, r) end
	check("an unupgraded stalk holds at most 3 raw corn", maxCorn(rules(0, 0, 0)) == 3 and maxCorn(crop) == 3)
	check("yield 1 holds 6, yield 2 holds 9 (3 cycles)", maxCorn(rules(0, 1, 0)) == 6 and maxCorn(rules(0, 2, 0)) == 9)
	check("yield 1 + storage 1 holds 8", maxCorn(rules(0, 1, 1)) == 8)
	check("yield 2 + storage 2 holds 15", maxCorn(rules(0, 2, 2)) == 15)
	check("maxed yield and storage hold 50", maxCorn(rules(4, 4, 4)) == 50)
	check("levels are clamped and sanitised", FarmUpgrades.clampLevel("Soil", 0 / 0) == 0 and FarmUpgrades.clampLevel("Soil", -3) == 0
		and FarmUpgrades.clampLevel("Soil", 99) == 4 and FarmUpgrades.clampLevel("Soil", 2.7) == 2 and FarmUpgrades.clampLevel("Soil", "3") == 0
		and FarmUpgrades.clampLevel("Nope", 2) == 0)
	check("growth never drops below the minimum", FarmUpgrades.rules({ displayName = "T", growthSeconds = 1.2, popcornValue = 1, maxYields = 3, cornPerYield = 1 },
		{ Soil = 4, Yield = 0, Storage = 0 }).growthSeconds == Config.Growth.minSeconds)

	-- 2. Growth rebasing (Soil / Storage purchases), deterministic times.
	local t = 1730000000.123
	local base, soil1, storage1 = rules(0, 0, 0), rules(1, 0, 0), rules(0, 0, 1)
	local s = Growth.rebase(t - 25, t, base, soil1) -- 2.5 cycles at 10 s
	check("soil upgrade keeps ready cycles", Growth.yields(s, t, soil1) == 2)
	check("soil upgrade keeps the partial cycle as a fraction", Growth.yields(s, t + 4.49, soil1) == 2 and Growth.yields(s, t + 4.5, soil1) == 3)
	s = Growth.rebase(t - 29.5, t, base, soil1) -- 2.95 cycles: a naive re-read at 9 s would pay 3
	check("soil upgrade pays nothing retroactively", Growth.yields(s, t, soil1) == 2 and Growth.yields(s, t + 0.4, soil1) == 2 and Growth.yields(s, t + 0.46, soil1) == 3)
	s = Growth.rebase(t - 100, t, base, soil1)
	check("soil upgrade on a full stalk keeps it full with no extra progress", Growth.yields(s, t, soil1) == 3 and Growth.progress(s, t, soil1) == 1)
	s = Growth.rebase(t - 100, t, base, storage1)
	check("storage upgrade on a full stalk cannot reclaim discarded growth", Growth.yields(s, t, storage1) == 3
		and Growth.yields(s, t + 9.99, storage1) == 3 and Growth.yields(s, t + 10, storage1) == 4)
	check("storage upgrade leaves a growing stalk alone", Growth.rebase(t - 15, t, base, storage1) == t - 15)
	check("future timestamps are left alone", Growth.rebase(t + 5, t, base, soil1) == t + 5)
	check("rebasing twice at the same time changes nothing", Growth.rebase(Growth.rebase(t - 25, t, base, soil1), t, soil1, soil1) == Growth.rebase(t - 25, t, base, soil1))

	-- 3. Schema: a v2 profile migrates to numeric levels.
	local v2: any = { schemaVersion = 2, upgrades = {}, fields = { Plot1 = { id = "Plot1", stalks = {} }, Plot2 = { id = "Plot2", stalks = {}, upgrades = { Soil = 9, Yield = -1 } } } }
	local migrated = State.migrate(v2)
	check("v2 profile migrates to schema 3 with default levels", migrated.schemaVersion == Config.SchemaVersion and migrated.upgrades.Backpack == 0
		and migrated.fields.Plot1.upgrades.Soil == 0 and migrated.fields.Plot2.upgrades.Soil == 4 and migrated.fields.Plot2.upgrades.Yield == 0
		and migrated.fields.Plot2.upgrades.Storage == 0)

	-- 4. Purchases and validation on the live player.
	local profile = assert(State.get(player.UserId))
	local plot1 = profile.fields.Plot1
	check("new profile starts unupgraded", profile.upgrades.Backpack == 0 and plot1.upgrades.Soil == 0 and plot1.upgrades.Yield == 0 and plot1.upgrades.Storage == 0)
	profile.cash = 150
	local response = buy("Backpack", nil)
	check("insufficient funds refused with a clear message", not response.ok and response.reason:find("Need $50 more") ~= nil and profile.cash == 150 and profile.upgrades.Backpack == 0)
	profile.cash = 250
	response = buy("Backpack", nil)
	check("backpack purchase deducts exactly $200", response.ok and response.amount == 200 and profile.cash == 50 and profile.upgrades.Backpack == 1 and response.level == 1)
	check("bag capacity replicates", player:GetAttribute("BagCapacity") == 100 and player:GetAttribute("Upgrade_Backpack") == 1 and player:GetAttribute("Cash") == 50)
	local character = assert(player.Character)
	local pack = character:FindFirstChild("PopcornBackpack") :: BasePart?
	check("the pack on the character shows the new tier", pack ~= nil and pack:GetAttribute("Level") == 1 and pack.Massless and not pack.CanCollide and not pack.Anchored)
	profile.cash = 100000
	response = Upgrades.buyUpgrade(player, "Backpack", nil)
	check("a request inside the cooldown is refused without charge", not response.ok and response.reason == "Too fast" and profile.cash == 100000 and profile.upgrades.Backpack == 1)
	task.wait(GAP)
	local granted = 0
	for _ = 1, 5 do if Upgrades.buyUpgrade(player, "Backpack", nil).ok then granted += 1 end end
	check("a burst of duplicate requests buys one level and charges once", granted == 1 and profile.upgrades.Backpack == 2
		and profile.cash == 100000 - 1200 and player:GetAttribute("BagCapacity") == 200)
	profile.cash = 100000
	check("unknown upgrade refused", not buy("Rocket", "Plot1").ok and not buy(42, "Plot1").ok and not buy({}, nil).ok and profile.cash == 100000)
	check("field upgrade without a plot refused", not buy("Soil", nil).ok and profile.cash == 100000)
	check("plot you do not own refused", buy("Yield", "Plot9").reason == "Not your plot" and profile.cash == 100000)
	check("oversized plot id refused", not buy("Yield", string.rep("P", 400)).ok and profile.cash == 100000)
	check("global upgrade with a plot refused", buy("Backpack", "Plot1").reason == "Invalid plot" and profile.upgrades.Backpack == 2)

	-- A second owner's plot cannot be touched, and their levels never move.
	local fixture = State.load(fixtureId, now())
	Farms.create(fixtureId, fixture.fields)
	response = buy("Storage", "Plot1")
	check("a field purchase changes only the buyer's own plot", response.ok and plot1.upgrades.Storage == 1 and fixture.fields.Plot1.upgrades.Storage == 0)

	-- 5. Soil: growth time drops and in-progress growth is preserved.
	local s1 = plot1.stalks["1_1"]
	local before = now()
	s1.growthStartedAt = before - 15 -- 1.5 cycles at 10 s
	local oldRules = FarmUpgrades.fieldRules(plot1)
	response = buy("Soil", "Plot1")
	local after = now()
	local newRules = FarmUpgrades.fieldRules(plot1)
	check("soil purchase speeds the plot up", response.ok and response.amount == 300 and newRules.growthSeconds == 9 and oldRules.growthSeconds == 10)
	-- Same fraction of the unfinished cycle before (10 s cycles) and after (9 s cycles).
	local fractionBefore = (after - (before - 15)) / 10 - 1
	local fractionAfter = (after - s1.growthStartedAt) / newRules.growthSeconds - 1
	check("soil purchase keeps the ready cycle and partial progress", Growth.yields(s1.growthStartedAt, after, newRules) == 1
		and math.abs(fractionAfter - fractionBefore) < 0.02)

	-- 6. Storage after the old limit: no reclaimed growth.
	local s2 = plot1.stalks["1_2"]
	s2.growthStartedAt = now() - 500 -- full long ago
	response = buy("Storage", "Plot1")
	local r2 = FarmUpgrades.fieldRules(plot1)
	check("storage purchase on a full stalk keeps it at the old limit", response.ok and r2.maxYields == 5 and Growth.yields(s2.growthStartedAt, now(), r2) == 4)

	-- 7. Yield with hands: corn per cycle, bag space, partial cycles.
	response = buy("Yield", "Plot1")
	response = buy("Yield", "Plot1")
	local r3 = FarmUpgrades.fieldRules(plot1)
	check("yield level 2 makes 3 corn per cycle", plot1.upgrades.Yield == 2 and r3.cornPerYield == 3)
	local stalk = plot1.stalks["1_3"]
	local target = assert(Farms.target(player.UserId, "Plot1", "1_3"))
	assert(player.Character):PivotTo(CFrame.new(target.Position + Vector3.new(0, 1, -2)))
	task.wait(0.2)
	stalk.growthStartedAt = now() - r3.growthSeconds * 3 -- 3 ready cycles = 9 corn
	profile.rawCorn.Normal = State.bagCapacity(profile) - 7 -- room for 2 whole cycles (6 corn)
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	response = Harvest.attempt(player, player.UserId, "Plot1", "1_3")
	check("hand pick takes only whole cycles that fit", response.ok and response.amount == 6 and response.reason == "Bag full"
		and profile.rawCorn.Normal == State.bagCapacity(profile) - 1)
	check("the uncollected cycle stays on the stalk", Growth.yields(stalk.growthStartedAt, now(), r3) == 1)
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	local held = stalk.growthStartedAt
	response = Harvest.attempt(player, player.UserId, "Plot1", "1_3")
	check("a cycle that does not fit is refused, not consumed", not response.ok and response.reason:find("Bag full") ~= nil and stalk.growthStartedAt == held
		and profile.rawCorn.Normal == State.bagCapacity(profile) - 1)
	check("bag never exceeds capacity", profile.rawCorn.Normal <= State.bagCapacity(profile))
	profile.rawCorn.Normal = 0
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	response = Harvest.attempt(player, player.UserId, "Plot1", "1_3")
	check("an empty bag takes the rest", response.ok and response.amount == 3 and profile.rawCorn.Normal == 3)

	-- 8. Visuals follow state, never ripe without a ready cycle.
	Farms.update(now())
	local stem = target :: Part
	check("unripe stalk shows no cobs even with a yield upgrade", stem:GetAttribute("AvailableYields") == 0 and stem:GetAttribute("Cobs") == 0)
	plot1.stalks["1_4"].growthStartedAt = now() - 1e6
	Farms.update(now())
	local full = assert(Farms.target(player.UserId, "Plot1", "1_4"))
	check("full stalk publishes its storage, yield and FULL state", full:GetAttribute("AvailableYields") == 5 and full:GetAttribute("MaxYields") == 5
		and full:GetAttribute("CornPerYield") == 3 and full:GetAttribute("Full") == true and full:GetAttribute("Cobs") == 3)
	local prompt = assert(full:FindFirstChild("Harvest")) :: ProximityPrompt
	check("pick prompt counts corn, not cycles", prompt.ObjectText == "Normal Corn · 15/15 corn")
	local farms = assert(workspace:FindFirstChild("PopcornFarms"))
	local farm = assert(farms:FindFirstChild("Farm_" .. player.UserId)) :: Model
	local soil = assert(farm:FindFirstChild("Soil")) :: BasePart
	check("upgraded soil is richer than base soil", soil.Color ~= Color3.fromRGB(100, 66, 41))

	-- 9. Sickle with a yield multiplier on an upgraded plot.
	-- Bought through ToolService so the physical Tool exists; equipping is tracked from its Equipped event.
	if not profile.ownedTools.Sickle then
		profile.cash += Config.Tools.Sickle.price
		assert(Tools.purchase(player, "Sickle").ok)
	end
	check("sickle equips", Tools.equip(player, "Sickle").ok)
	local equipDeadline = os.clock() + 3
	while profile.equippedTool ~= "Sickle" and os.clock() < equipDeadline do task.wait(0.1) end
	local sickle = Config.Tools.Sickle
	local savedMultiplier = sickle.yieldMultiplier
	sickle.yieldMultiplier = 2
	local swingOk, swingErr = pcall(function()
		local a = assert(Farms.target(player.UserId, "Plot1", "1_3")).Position
		local b = assert(Farms.target(player.UserId, "Plot1", "1_4")).Position
		local inward = (assert(Farms.target(player.UserId, "Plot1", "1_9")).Position - a) * Vector3.new(1, 0, 1)
		local spot = (a + b) / 2 - inward.Unit * 2.5
		local y = root().Position.Y
		assert(player.Character):PivotTo(CFrame.lookAt(Vector3.new(spot.X, y, spot.Z), Vector3.new(spot.X, y, spot.Z) + inward))
		local at = now()
		for _, st in plot1.stalks do st.growthStartedAt = at - r3.growthSeconds * 2 end -- 2 cycles everywhere
		profile.rawCorn.Normal = 0
		task.wait(sickle.cooldownSeconds)
		response = Harvest.swing(player, "Sickle")
		-- 3 stalks x 2 cycles x 3 corn x 2 multiplier = 36.
		check("sickle multiplier combines with corn yield", response.ok and response.amount == 36 and profile.rawCorn.Normal == 36)
		for _, st in plot1.stalks do st.growthStartedAt = at - r3.growthSeconds * 2 end
		profile.rawCorn.Normal = State.bagCapacity(profile) - 13 -- room for 2 cycles of 6
		task.wait(sickle.cooldownSeconds)
		response = Harvest.swing(player, "Sickle")
		check("sickle respects the upgraded bag with whole cycles", response.ok and response.amount == 12 and response.reason == "Bag full"
			and profile.rawCorn.Normal == State.bagCapacity(profile) - 1)
		task.wait(sickle.cooldownSeconds)
		response = Harvest.swing(player, "Sickle")
		check("sickle with no room for a whole cycle takes nothing", not response.ok and profile.rawCorn.Normal == State.bagCapacity(profile) - 1)
	end)
	sickle.yieldMultiplier = savedMultiplier
	Tools.equip(player, "Manual")
	assert(swingOk, swingErr)

	-- 10. New plot and new rows.
	local plot2 = State.addPlot(profile, player.UserId, now())
	Farms.addPlot(player.UserId, plot2.id)
	State.publish(player.UserId)
	check("a new plot starts with default levels", plot2.upgrades.Soil == 0 and plot2.upgrades.Yield == 0 and plot2.upgrades.Storage == 0
		and FarmUpgrades.fieldRules(plot2).growthSeconds == 10 and player:GetAttribute("Plots") == 2 and player:GetAttribute("Upgrade_Plot2_Soil") == 0)
	response = buy("Yield", plot2.id)
	check("plots upgrade independently", response.ok and plot2.upgrades.Yield == 1 and plot1.upgrades.Yield == 2
		and FarmUpgrades.fieldRules(plot2).cornPerYield == 2 and FarmUpgrades.fieldRules(plot1).cornPerYield == 3)
	local soil2 = assert(farm:FindFirstChild("Soil_2")) :: BasePart
	check("plot 2's soil keeps the base look", soil2 ~= nil and soil2.Color == Color3.fromRGB(100, 66, 41))
	-- Backpack is global: a plot-2 pick obeys the same bag.
	local id2 = State.stalkId(2, 1, 1)
	local t2 = assert(Farms.target(player.UserId, plot2.id, id2))
	assert(player.Character):PivotTo(CFrame.new(t2.Position + Vector3.new(0, 1, -2)))
	task.wait(0.2)
	plot2.stalks[id2].growthStartedAt = now() - 1e6
	profile.rawCorn.Normal = State.bagCapacity(profile) - 3
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	response = Harvest.attempt(player, player.UserId, plot2.id, id2)
	check("backpack capacity applies on every plot", response.ok and response.amount == 2 and profile.rawCorn.Normal == State.bagCapacity(profile) - 1)
	-- A row planted on an upgraded plot inherits it (same path as a pad purchase).
	plot1.rows += 1
	local plantedAt = now()
	State.plantRow(plot1, plot1.rows, plantedAt)
	Farms.plantRow(player.UserId, plot1.id, plot1.rows)
	Farms.update(now())
	local rowId = State.stalkId(1, plot1.rows, 1)
	local rowPart = assert(Farms.target(player.UserId, plot1.id, rowId))
	check("a new row inherits its plot's upgrades", plot1.stalks[rowId].growthStartedAt == plantedAt - 9
		and rowPart:GetAttribute("MaxYields") == 5 and rowPart:GetAttribute("CornPerYield") == 3 and rowPart:GetAttribute("AvailableYields") == 1)

	-- 11. Max level.
	profile.cash = 1e6
	while profile.upgrades.Backpack < FarmUpgrades.maxLevel("Backpack") do assert(buy("Backpack", nil).ok) end
	local cash = profile.cash
	response = buy("Backpack", nil)
	check("max level refuses further purchases", not response.ok and response.reason:find("maxed") ~= nil and profile.cash == cash and profile.upgrades.Backpack == 4
		and player:GetAttribute("BagCapacity") == 800)
	check("no negative balances or inventory", profile.cash >= 0 and profile.rawCorn.Normal >= 0 and fixture.cash == 0)

	-- 12. Reset what this runner bought so later runners see a fresh player.
	profile.upgrades.Backpack = 0
	for _, field in profile.fields do
		local oldR = FarmUpgrades.fieldRules(field)
		field.upgrades = FarmUpgrades.defaultField()
		local newR = FarmUpgrades.fieldRules(field)
		for _, st in field.stalks do st.growthStartedAt = Growth.rebase(st.growthStartedAt, now(), oldR, newR) end
		Farms.applyFieldLook(player.UserId, field.id)
	end
	profile.rawCorn.Normal, profile.cash = 0, 0
	player:SetAttribute("RawCorn", 0)
	State.publish(player.UserId)
	require(Services.UpgradeVisuals).backpack(player.Character, 0)
	Farms.update(now())
	check("reset leaves base values", player:GetAttribute("BagCapacity") == 50 and player:GetAttribute("Upgrade_Plot1_Soil") == 0)
end)

pcall(function()
	Farms.remove(fixtureId)
	State.release(fixtureId)
end)
script:SetAttribute("Results", Http:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = checks }))
print("[FarmUpgrades tests] " .. (if ok then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
