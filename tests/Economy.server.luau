--!strict
-- Temporary Server RunContext integration runner during Play (M3 economy, land pads).
-- Install outside the synced PopcornTycoon folder; destroy after reading Results.
-- Run it last in a Play session: it buys every row and plot, which changes the farm.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local Pricing = require(Shared.Pricing)
local Services = game:GetService("ServerScriptService"):WaitForChild("PopcornTycoon")
local State = require(Services.PlayerStateService)
local Farms = require(Services.FarmService)
local Harvest = require(Services.HarvestService)
local Conversion = require(Services.ConversionService)
local Upgrades = require(Services.UpgradeService)
local checks: { { name: string, passed: boolean } } = {}
local function check(name: string, condition: boolean)
	table.insert(checks, { name = name, passed = condition })
	assert(condition, name)
end
-- Also works as a Play-start runner: wait for the first player's profile, farm and character.
local readyBy = os.clock() + 30
while os.clock() < readyBy do
	local first = Players:GetPlayers()[1]
	if first and first.Character and State.get(first.UserId) and Farms.has(first.UserId) then break end
	task.wait(0.25)
end
task.wait(1)
local player = assert(Players:GetPlayers()[1], "Requires a live player")
local fixtureId = -9000002
local pivot = assert(player.Character):GetPivot()
local function now(): number return DateTime.now().UnixTimestampMillis / 1000 end
local function standAt(position: Vector3) assert(player.Character):PivotTo(CFrame.new(position + Vector3.new(0, 3, 0))) end
local function waitFor(condition: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not condition() and os.clock() < deadline do task.wait(0.1) end
	return condition()
end

local ok, err = pcall(function()
	local profile = assert(State.get(player.UserId))
	local field = profile.fields.Plot1
	local crop = Config.Crops[field.cropId]
	local microwave = assert(Farms.microwave(player.UserId))
	local away = microwave.door.Position + Vector3.new(0, 0, -40)
	local function inFront(door: BasePart): Vector3 return door.Position + door.CFrame.LookVector * 3 end
	-- Start from an empty bag and an idle microwave.
	Conversion.settle(player.UserId)
	profile.rawCorn.Normal = 0
	player:SetAttribute("RawCorn", 0)
	local popcorn0 = profile.popcorn

	-- Bag limit and partial harvest.
	local stalk1, stalk2 = field.stalks["1_1"], field.stalks["1_2"]
	local target1 = assert(Farms.target(player.UserId, "Plot1", "1_1"))
	standAt(target1.Position + Vector3.new(0, 0, -2))
	profile.rawCorn.Normal = Config.Inventory.capacity - 1
	stalk1.growthStartedAt = now() - crop.growthSeconds * 20
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	local response = Harvest.attempt(player, player.UserId, "Plot1", "1_1")
	check("partial harvest takes only what fits", response.ok and response.amount == 1 and response.reason == "Bag full" and profile.rawCorn.Normal == Config.Inventory.capacity)
	check("remainder stays ready on the stalk", Growth.yields(stalk1.growthStartedAt, now(), crop) == crop.maxYields - 1)
	check("bag attribute shows the cap", player:GetAttribute("RawCorn") == Config.Inventory.capacity)
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	stalk2.growthStartedAt = now() - crop.growthSeconds
	local before2 = stalk2.growthStartedAt
	standAt(assert(Farms.target(player.UserId, "Plot1", "1_2")).Position + Vector3.new(0, 0, -2))
	response = Harvest.attempt(player, player.UserId, "Plot1", "1_2")
	check("full bag refuses harvest without consuming the stalk", not response.ok and response.reason:find("Bag full") ~= nil and stalk2.growthStartedAt == before2 and profile.rawCorn.Normal == Config.Inventory.capacity)

	-- Microwave validation.
	local fixture = State.load(fixtureId, now())
	Farms.create(fixtureId, fixture.fields)
	local foreign = assert(Farms.microwave(fixtureId))
	check("farm prompts resolve to their owner", Farms.resolveOwner(foreign.prompt) == fixtureId and Farms.resolveOwner(microwave.prompt) == player.UserId)
	standAt(inFront(foreign.door))
	fixture.rawCorn.Normal = 5
	response = Conversion.start(player, fixtureId)
	check("foreign microwave rejected", not response.ok and response.reason == "Not your microwave" and fixture.rawCorn.Normal == 5 and profile.rawCorn.Normal == Config.Inventory.capacity)
	response = Conversion.start(player, "bad" :: any)
	check("malformed microwave owner rejected", not response.ok and profile.rawCorn.Normal == Config.Inventory.capacity)
	standAt(away)
	response = Conversion.start(player, player.UserId)
	check("out of range microwave rejected", not response.ok and response.reason == "Too far away" and profile.rawCorn.Normal == Config.Inventory.capacity)

	-- Load a full bag.
	standAt(inFront(microwave.door))
	response = Conversion.start(player, player.UserId)
	local reward = Config.Inventory.capacity * crop.popcornValue
	check("full bag loads as one batch", response.ok and response.amount == Config.Inventory.capacity and profile.rawCorn.Normal == 0 and player:GetAttribute("RawCorn") == 0)
	check("reward reserved, not yet paid", Conversion.pending(player.UserId) == reward and profile.popcorn == popcorn0)
	check("HUD batch state shows popping", player:GetAttribute("BatchState") == "Popping" and player:GetAttribute("BatchCorn") == Config.Inventory.capacity)
	response = Conversion.start(player, player.UserId)
	check("second press while cooking rejected", not response.ok and response.reason == "Already popping!" and Conversion.pending(player.UserId) == reward)
	check("cooking state shown on prompt", microwave.door:GetAttribute("Cooking") == true and microwave.prompt.ObjectText:find("Popping") ~= nil)
	-- Walk far away while it cooks: the popcorn must still reach the owner (no range).
	local far = microwave.door.Position + Vector3.new(150, 0, -40)
	standAt(far)
	check("batch bursts after the cook time", waitFor(function() return #microwave.popcorn:GetChildren() > 0 end, Config.Microwave.cookSeconds + 2))
	local total, towardField = 0, 0
	for _, piece in microwave.popcorn:GetChildren() do
		total += piece:GetAttribute("Value") :: number
		if (piece.Position - microwave.door.Position):Dot(microwave.door.CFrame.LookVector) > 1 then towardField += 1 end
	end
	check("bounded pieces carry the exact reward", #microwave.popcorn:GetChildren() == math.min(Config.Microwave.pieces, reward) and total == reward)
	check("burst lands on the field side", towardField == #microwave.popcorn:GetChildren())
	check("pieces carry staggered flight delays", (microwave.popcorn:GetChildren()[1]:GetAttribute("FlyDelay") :: number) >= 0)
	check("not paid before the pieces land", profile.popcorn == popcorn0)
	check("HUD batch state shows popcorn landing", player:GetAttribute("BatchState") == "Landing")
	check("microwave idle after burst", microwave.door:GetAttribute("Cooking") == false and microwave.prompt.ObjectText == "Microwave")
	local flight = Config.Microwave.landSeconds + Config.Microwave.staggerSeconds * Config.Microwave.pieces + Config.Microwave.flySeconds
	check("popcorn flies to the owner from far away", waitFor(function() return #microwave.popcorn:GetChildren() == 0 end, flight + 1))
	check("HUD batch state returns to idle", player:GetAttribute("BatchState") == "Idle")
	check("flight credits exactly the reward once", profile.popcorn == popcorn0 + reward and player:GetAttribute("Popcorn") == profile.popcorn and Conversion.pending(player.UserId) == 0)
	standAt(inFront(microwave.door))
	response = Conversion.start(player, player.UserId)
	check("empty bag rejected", not response.ok and response.reason:find("No corn") ~= nil)

	profile.rawCorn.Normal = 10
	check("second batch loads", Conversion.start(player, player.UserId).ok)
	check("second batch pays exactly once", waitFor(function() return profile.popcorn == popcorn0 + reward + 10 and Conversion.pending(player.UserId) == 0 end, Config.Microwave.cookSeconds + flight + 1))
	task.wait(0.5)
	check("no extra payout afterwards", profile.popcorn == popcorn0 + reward + 10)

	-- Leaving mid-cook credits everything once.
	profile.rawCorn.Normal = 7
	standAt(inFront(microwave.door))
	check("third batch loads", Conversion.start(player, player.UserId).ok)
	Conversion.settle(player.UserId)
	check("settle credits a cooking batch", profile.popcorn == popcorn0 + reward + 17 and Conversion.pending(player.UserId) == 0)
	Conversion.settle(player.UserId)
	check("settle is idempotent", profile.popcorn == popcorn0 + reward + 17)

	-- Land pads (Nov 4 2026): Extra Row on a plot's row pad, New Plot on the plot pad.
	-- Direct calls stand just beside a pad (inside the server's slack, outside its touch box) so the
	-- step-on path cannot race them; one check further down steps on for real.
	local farm = workspace.PopcornFarms:FindFirstChild("Farm_" .. player.UserId) :: Model
	local function beside(pad: BasePart) standAt((pad.CFrame * CFrame.new(0, 0, pad.Size.Z / 2 + 3)).Position) end
	local function count(): (number, number)
		local stalks, prompts = 0, 0
		for _, f in profile.fields do for _ in f.stalks do stalks += 1 end end
		for _, object in farm:GetDescendants() do if object:IsA("ProximityPrompt") and object.Name == "Harvest" then prompts += 1 end end
		return stalks, prompts
	end
	local rowUpgrade, plotUpgrade = Config.Upgrades.ExtraRow, Config.Upgrades.ExtraPlot
	check("land is priced in cash", rowUpgrade.currency == "Cash" and plotUpgrade.currency == "Cash")
	check("prices round to two significant figures", Pricing.nice(232) == 230 and Pricing.nice(57500) == 58000 and Pricing.nice(8512061) == 8500000)
	local price = Pricing.rowPrice(profile.fields)
	check("first row costs the configured base", price == rowUpgrade.base)
	local rowPad = assert(Farms.rowPad(player.UserId, field.id))
	check("row pad shows its price on the next row; no sign", rowPad:GetAttribute("Price") == price and rowPad:GetAttribute("Row") == Config.Plot.baseRows + 1 and farm:FindFirstChild("RowForSale") == nil)
	beside(rowPad)
	profile.cash, profile.popcorn = price - 1, price * 10
	response = Upgrades.buyRow(player, field.id)
	check("insufficient cash rejected even with popcorn", not response.ok and response.reason:find("Need $1 more", 1, true) ~= nil and profile.cash == price - 1 and profile.popcorn == price * 10 and field.rows == Config.Plot.baseRows)
	profile.cash, profile.popcorn = price + 5, 0
	response = Upgrades.buyRow(player, "Plot2")
	check("row on an unowned plot rejected", not response.ok and response.reason == "Not your plot" and profile.cash == price + 5)
	response = Upgrades.buyRow(player, 7 :: any)
	check("malformed plot id rejected", not response.ok and profile.cash == price + 5)
	standAt(away)
	response = Upgrades.buyRow(player, field.id)
	check("out of range purchase rejected", not response.ok and response.reason == "Too far away" and profile.cash == price + 5)
	beside(rowPad)
	local stalks0 = count()
	response = Upgrades.buyRow(player, field.id)
	local stalks, prompts = count()
	check("row purchase charges cash once and plants a row", response.ok and response.amount == price and profile.cash == 5 and player:GetAttribute("Cash") == 5 and field.rows == Config.Plot.baseRows + 1)
	check("extra row adds a row of stalks and harvest prompts", stalks == stalks0 + Config.Plot.columns and prompts == stalks)
	local movedPad = assert(Farms.rowPad(player.UserId, field.id))
	check("row pad moves back a row and its price rises", movedPad:GetAttribute("Row") == Config.Plot.baseRows + 2 and movedPad:GetAttribute("Price") == Pricing.nice(rowUpgrade.base * rowUpgrade.growth) and (movedPad:GetAttribute("Price") :: number) > price)
	local firstNew = State.stalkId(1, Config.Plot.baseRows + 1, 1)
	local newTarget = assert(Farms.target(player.UserId, field.id, firstNew))
	local lastOld = assert(Farms.target(player.UserId, field.id, State.stalkId(1, Config.Plot.baseRows, 1)))
	local soil = farm:FindFirstChild("Soil") :: BasePart
	local function depth(position: Vector3): number return soil.CFrame:PointToObjectSpace(position).Z end
	check("new row sits behind the old rows, away from the stations", depth(newTarget.Position) > depth(lastOld.Position) and depth(newTarget.Position) > depth(microwave.door.Position))
	standAt(newTarget.Position + Vector3.new(0, 0, -2))
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	profile.rawCorn.Normal = 0
	response = Harvest.attempt(player, player.UserId, field.id, firstNew)
	check("new stalks start harvestable", response.ok and response.amount == 1)
	check("purchased row is visible to tool targeting", Farms.stalkParts(player.UserId)[firstNew] ~= nil and Farms.fieldOf(player.UserId, firstNew) == field.id)

	-- Fill the plot: the pad walks back row by row and goes away at the end of the bed.
	profile.cash = 10 ^ 9
	while field.rows < Config.layoutRows() do
		beside(assert(Farms.rowPad(player.UserId, field.id)))
		assert(Upgrades.buyRow(player, field.id).ok, "row purchase failed")
	end
	check("a plot holds base plus extra rows, then its row pad is gone", field.rows == Config.Plot.baseRows + Config.Plot.maxExtraRows and Farms.rowPad(player.UserId, field.id) == nil)
	local cash = profile.cash
	response = Upgrades.buyRow(player, field.id)
	check("full plot rejects another row without charge", not response.ok and response.reason == "This plot is full" and profile.cash == cash)

	-- New Plot.
	local plotPad = assert(Farms.plotPad(player.UserId))
	local plotPrice = Pricing.plotPrice(profile.fields)
	check("first new plot costs the configured base, on cell 2", plotPrice == plotUpgrade.base and plotPad:GetAttribute("Plot") == 2 and plotPad:GetAttribute("Price") == plotPrice)
	beside(plotPad)
	profile.cash = plotPrice - 1
	response = Upgrades.buyPlot(player)
	check("insufficient cash rejects a plot", not response.ok and response.reason:find("Need $1 more", 1, true) ~= nil and profile.fields.Plot2 == nil)
	standAt(away)
	profile.cash = plotPrice
	response = Upgrades.buyPlot(player)
	check("out of range plot purchase rejected", not response.ok and response.reason == "Too far away" and profile.cash == plotPrice)
	beside(plotPad)
	local rowPriceBefore = Pricing.rowPrice(profile.fields)
	response = Upgrades.buyPlot(player)
	local plot2 = profile.fields.Plot2
	check("plot purchase charges once and plants the base rows", response.ok and response.amount == plotPrice and profile.cash == 0 and plot2 ~= nil and plot2.plot == 2 and plot2.rows == Config.Plot.baseRows and plot2.ownerUserId == player.UserId)
	check("the locked lawn becomes a bed with its own row pad", farm:FindFirstChild("LockedCell_2") == nil and farm:FindFirstChild("PlotBed_2") ~= nil and Farms.rowPad(player.UserId, "Plot2") ~= nil)
	local nextPad = assert(Farms.plotPad(player.UserId))
	check("plot pad moves to cell 3 at a higher price", nextPad:GetAttribute("Plot") == 3 and nextPad:GetAttribute("Price") == Pricing.nice(plotUpgrade.base * plotUpgrade.growth))
	check("a new plot does not change the row price", Pricing.rowPrice(profile.fields) == rowPriceBefore)
	local plot2Stalk = State.stalkId(2, 1, 1)
	local target2 = assert(Farms.target(player.UserId, "Plot2", plot2Stalk))
	check("a stalk only resolves under its own plot", Farms.target(player.UserId, field.id, plot2Stalk) == nil)
	standAt(target2.Position + Vector3.new(0, 0, -2))
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	profile.rawCorn.Normal = 0
	response = Harvest.attempt(player, player.UserId, "Plot2", plot2Stalk)
	check("new plot starts harvestable", response.ok and response.amount == 1)

	-- Stepping onto a pad buys through the real Touched path, once per step-on.
	local pad2 = assert(Farms.rowPad(player.UserId, "Plot2"))
	local stepPrice = pad2:GetAttribute("Price") :: number
	standAt(away)
	task.wait(0.6)
	profile.cash = 10 ^ 9
	local cashBefore = profile.cash
	assert(player.Character):PivotTo(CFrame.new(pad2.Position + Vector3.new(0, 3, 0)))
	check("stepping on a row pad buys a row", waitFor(function() return plot2.rows == Config.Plot.baseRows + 1 end, 3))
	task.wait(1.5)
	check("standing on it does not buy again", plot2.rows == Config.Plot.baseRows + 1 and profile.cash == cashBefore - stepPrice)

	-- Buy out the grid: the plot pad goes away after the last cell.
	while Pricing.plotsBought(profile.fields) < plotUpgrade.max do
		beside(assert(Farms.plotPad(player.UserId)))
		assert(Upgrades.buyPlot(player).ok, "plot purchase failed")
	end
	local owned, locked = 0, 0
	for _ in profile.fields do owned += 1 end
	for _, child in farm:GetChildren() do if child.Name:match("^LockedCell_") then locked += 1 end end
	check("nine plots at most; no locked cells or plot pad remain", owned == #Config.Grid.order and locked == 0 and Farms.plotPad(player.UserId) == nil)
	cash = profile.cash
	response = Upgrades.buyPlot(player)
	check("no plot left to buy, nothing charged", not response.ok and response.reason == "Every plot is yours" and profile.cash == cash)
end)

Conversion.settle(fixtureId)
Farms.remove(fixtureId)
State.release(fixtureId)
if player.Character then player.Character:PivotTo(pivot) end
script:SetAttribute("Results", Http:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = checks }))
print("[Economy tests] " .. (if ok then "PASS " else "FAIL ") .. tostring(#checks) .. " checks")
