--!strict
-- Temporary Workspace Server RunContext Script for StudioTestService only.
local TestService = game:GetService("StudioTestService")
local args = TestService:GetTestArgs()
if typeof(args) ~= "table" or args.test ~= "PopcornOwnership" then return end
local Players = game:GetService("Players")
local Services = game:GetService("ServerScriptService"):WaitForChild("PopcornTycoon")
local State = require(Services.PlayerStateService)
local Farms = require(Services.FarmService)
local Harvest = require(Services.HarvestService)
local Conversion = require(Services.ConversionService)
local Upgrades = require(Services.UpgradeService)
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
local checks: { { name: string, passed: boolean } } = {}
local function check(name: string, condition: boolean)
	table.insert(checks, { name = name, passed = condition })
	assert(condition, name)
end
-- True when two (possibly rotated) plot foundations share any ground.
local function footprintsOverlap(a: BasePart, b: BasePart): boolean
	local function cornerInside(from: BasePart, into: BasePart): boolean
		for _, x in {-0.5, 0.5} do
			for _, z in {-0.5, 0.5} do
				local p = into.CFrame:PointToObjectSpace(from.CFrame:PointToWorldSpace(Vector3.new(x * from.Size.X, 0, z * from.Size.Z)))
				if math.abs(p.X) < into.Size.X / 2 and math.abs(p.Z) < into.Size.Z / 2 then return true end
			end
		end
		return false
	end
	return cornerInside(a, b) or cornerInside(b, a)
end
local finished = false
task.delay(90, function()
	if not finished then TestService:EndTest({ passed = false, error = "Multiplayer test timed out", checks = checks }) end
end)
local ok, err = pcall(function()
	-- The second client took longer than 25 s to join once the islands grew to 3x3 (Nov 4 2026).
	local deadline = os.clock() + 45
	while #Players:GetPlayers() < 2 and os.clock() < deadline do task.wait(0.1) end
	local players = Players:GetPlayers()
	check("two real simulated clients joined (" .. #players .. ")", #players == 2)
	local first, second = players[1], players[2]
	while os.clock() < deadline + 10 and (not first.Character or not second.Character or not State.get(first.UserId) or not State.get(second.UserId)) do task.wait(0.1) end
	assert(first.Character and second.Character, "Characters missing")
	local a, b = assert(State.get(first.UserId)), assert(State.get(second.UserId))
	check("separate real player profiles", a ~= b and a.rawCorn ~= b.rawCorn)
	check("two owned fields assigned", a.fields.Plot1.ownerUserId == first.UserId and b.fields.Plot1.ownerUserId == second.UserId)
	local at = assert(Farms.target(first.UserId, "Plot1", "1_1"))
	local bt = assert(Farms.target(second.UserId, "Plot1", "1_1"))
	local am = at.Parent :: Model
	local bm = bt.Parent :: Model
	check("real player farms do not overlap", not footprintsOverlap(am.Scenery.GrassFoundation, bm.Scenery.GrassFoundation))
	local function promptCount(farm: Model): number
		local count = 0
		for _, object in farm:GetDescendants() do if object:IsA("ProximityPrompt") and object.Name == "Harvest" then count += 1 end end
		return count
	end
	local starterStalks = Config.Plot.baseRows * Config.Plot.columns
	check("both plots retain every starter harvest prompt", promptCount(am) == starterStalks and promptCount(bm) == starterStalks)
	local aMicrowave = assert(Farms.microwave(first.UserId))
	second.Character:PivotTo(CFrame.new(aMicrowave.door.Position + aMicrowave.door.CFrame.LookVector * 3))
	b.rawCorn.Normal = 4
	local converted = Conversion.start(second, first.UserId)
	check("second player cannot use first microwave", not converted.ok and b.rawCorn.Normal == 4 and Conversion.pending(first.UserId) == 0)
	-- Land pads (Nov 4 2026): standing on the first farm's pads buys nothing for anyone, whether
	-- by stepping on them or by asking for a row directly.
	b.cash = 10 ^ 6
	local aRowPad, aPlotPad = assert(Farms.rowPad(first.UserId, "Plot1")), assert(Farms.plotPad(first.UserId))
	second.Character:PivotTo(CFrame.new(aRowPad.Position + Vector3.new(0, 3, 0)))
	task.wait(1.5)
	second.Character:PivotTo(CFrame.new(aPlotPad.Position + Vector3.new(0, 3, 0)))
	task.wait(1.5)
	local bought = Upgrades.buyRow(second, "Plot1")
	local plotBought = Upgrades.buyPlot(second)
	check("second player cannot buy land on the first farm", not bought.ok and not plotBought.ok and b.cash == 10 ^ 6
		and a.fields.Plot1.rows == Config.Plot.baseRows and b.fields.Plot1.rows == Config.Plot.baseRows and a.fields.Plot2 == nil and b.fields.Plot2 == nil)
	b.rawCorn.Normal, b.popcorn, b.cash = 0, 0, 0
	first.Character:PivotTo(CFrame.new(bt.Position + Vector3.new(0, 2, -2)))
	local response = Harvest.attempt(first, second.UserId, "Plot1", "1_1")
	check("first player cannot harvest second field", not response.ok and response.reason == "Not your field" and b.rawCorn.Normal == 0)
	second.Character:PivotTo(CFrame.new(at.Position + Vector3.new(0, 2, -2)))
	response = Harvest.attempt(second, first.UserId, "Plot1", "1_1")
	check("second player cannot harvest first field", not response.ok and response.reason == "Not your field" and a.rawCorn.Normal == 0)
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	first.Character:PivotTo(CFrame.new(at.Position + Vector3.new(0, 2, -2)))
	second.Character:PivotTo(CFrame.new(bt.Position + Vector3.new(0, 2, -2)))
	local now = DateTime.now().UnixTimestampMillis / 1000
	a.fields.Plot1.stalks["1_1"].growthStartedAt = now - Config.Crops.Normal.growthSeconds
	b.fields.Plot1.stalks["1_1"].growthStartedAt = now - Config.Crops.Normal.growthSeconds
	response = Harvest.attempt(first, first.UserId, "Plot1", "1_1")
	check("first player harvest affects only first inventory", response.ok and a.rawCorn.Normal == 1 and b.rawCorn.Normal == 0)
	response = Harvest.attempt(second, second.UserId, "Plot1", "1_1")
	check("second player harvest affects only second inventory", response.ok and b.rawCorn.Normal == 1 and a.rawCorn.Normal == 1)
	check("both inventory attributes match", first:GetAttribute("RawCorn") == 1 and second:GetAttribute("RawCorn") == 1)
end)
finished = true
local result = { passed = ok, error = if ok then nil else tostring(err), checks = checks }
print("[PopcornTycoon multiplayer] " .. (if ok then "PASS " else "FAIL ") .. tostring(#checks) .. " checks")
TestService:EndTest(result)
