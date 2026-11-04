--!strict
-- Temporary Server RunContext integration runner during Play (M3 economy).
-- Install outside the synced PopcornTycoon folder; destroy after reading Results.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
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
	local field = profile.fields.Starter
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
	local stalk1, stalk2 = field.stalks["1"], field.stalks["2"]
	local target1 = assert(Farms.target(player.UserId, "Starter", "1"))
	standAt(target1.Position + Vector3.new(0, 0, -2))
	profile.rawCorn.Normal = Config.Inventory.capacity - 1
	stalk1.growthStartedAt = now() - crop.growthSeconds * 20
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	local response = Harvest.attempt(player, player.UserId, "Starter", "1")
	check("partial harvest takes only what fits", response.ok and response.amount == 1 and response.reason == "Bag full" and profile.rawCorn.Normal == Config.Inventory.capacity)
	check("remainder stays ready on the stalk", Growth.yields(stalk1.growthStartedAt, now(), crop) == crop.maxYields - 1)
	check("bag attribute shows the cap", player:GetAttribute("RawCorn") == Config.Inventory.capacity)
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	stalk2.growthStartedAt = now() - crop.growthSeconds
	local before2 = stalk2.growthStartedAt
	standAt(assert(Farms.target(player.UserId, "Starter", "2")).Position + Vector3.new(0, 0, -2))
	response = Harvest.attempt(player, player.UserId, "Starter", "2")
	check("full bag refuses harvest without consuming the stalk", not response.ok and response.reason:find("Bag full") ~= nil and stalk2.growthStartedAt == before2 and profile.rawCorn.Normal == Config.Inventory.capacity)

	-- Microwave validation.
	local fixture = State.load(fixtureId, now())
	Farms.create(fixtureId, fixture.fields.Starter)
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

	-- Extra Row purchase.
	local price = Config.Upgrades.ExtraRow.price
	local sign = assert(Farms.rowSign(player.UserId))
	standAt(sign.Position + Vector3.new(0, -3, 3))
	-- Extra Row is paid in Cash (called Coins until the Nov 3 2026 rename); popcorn alone cannot buy it.
	check("extra row is priced in cash", Config.Upgrades.ExtraRow.currency == "Cash")
	profile.cash, profile.popcorn = price - 1, price * 10
	response = Upgrades.buyExtraRow(player, player.UserId)
	check("insufficient cash rejected even with popcorn", not response.ok and response.reason:find("Need $1 more", 1, true) ~= nil and profile.cash == price - 1 and profile.popcorn == price * 10 and field.rows == Config.Starter.rows)
	profile.cash, profile.popcorn = price + 5, 0
	response = Upgrades.buyExtraRow(player, fixtureId)
	check("foreign row purchase rejected", not response.ok and profile.cash == price + 5 and fixture.fields.Starter.rows == Config.Starter.rows)
	standAt(away)
	response = Upgrades.buyExtraRow(player, player.UserId)
	check("out of range purchase rejected", not response.ok and response.reason == "Too far away" and profile.cash == price + 5)
	standAt(sign.Position + Vector3.new(0, -3, 3))
	response = Upgrades.buyExtraRow(player, player.UserId)
	local stalks, prompts = 0, 0
	for _ in field.stalks do stalks += 1 end
	local farm = workspace.PopcornFarms:FindFirstChild("Farm_" .. player.UserId) :: Model
	for _, object in farm:GetDescendants() do if object:IsA("ProximityPrompt") and object.Name == "Harvest" then prompts += 1 end end
	check("purchase charges cash once and plants a row", response.ok and profile.cash == 5 and player:GetAttribute("Cash") == 5 and profile.popcorn == 0 and profile.upgrades.ExtraRow == true and field.rows == Config.Starter.layoutRows)
	local planted = Config.Starter.layoutRows * Config.Starter.columns
	check("extra row adds a row of stalks and harvest prompts", stalks == planted and prompts == planted)
	check("for-sale sign removed", Farms.rowSign(player.UserId) == nil and farm:FindFirstChild("RowForSale") == nil)
	local firstNew = tostring(Config.Starter.rows * Config.Starter.columns + 1)
	local newTarget = assert(Farms.target(player.UserId, "Starter", firstNew))
	local lastOld = assert(Farms.target(player.UserId, "Starter", tostring((Config.Starter.rows - 1) * Config.Starter.columns + 1)))
	local soil = farm:FindFirstChild("Soil") :: BasePart
	local function depth(position: Vector3): number return soil.CFrame:PointToObjectSpace(position).Z end
	check("new row sits behind the old rows, away from the stations", depth(newTarget.Position) > depth(lastOld.Position) and depth(newTarget.Position) > depth(microwave.door.Position))
	response = Upgrades.buyExtraRow(player, player.UserId)
	check("second purchase rejected without charge", not response.ok and response.reason == "Already owned" and profile.cash == 5)
	standAt(newTarget.Position + Vector3.new(0, 0, -2))
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	profile.rawCorn.Normal = 0
	response = Harvest.attempt(player, player.UserId, "Starter", firstNew)
	check("new stalks start harvestable", response.ok and response.amount == 1)
	check("purchased row is visible to tool targeting", Farms.stalkParts(player.UserId)[firstNew] ~= nil)
end)

Conversion.settle(fixtureId)
Farms.remove(fixtureId)
State.release(fixtureId)
if player.Character then player.Character:PivotTo(pivot) end
script:SetAttribute("Results", Http:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = checks }))
print("[Economy tests] " .. (if ok then "PASS " else "FAIL ") .. tostring(#checks) .. " checks")
