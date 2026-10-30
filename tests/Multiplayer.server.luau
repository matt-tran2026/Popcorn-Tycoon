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
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
local checks: { { name: string, passed: boolean } } = {}
local function check(name: string, condition: boolean)
	table.insert(checks, { name = name, passed = condition })
	assert(condition, name)
end
local finished = false
task.delay(40, function()
	if not finished then TestService:EndTest({ passed = false, error = "Multiplayer test timed out", checks = checks }) end
end)
local ok, err = pcall(function()
	local deadline = os.clock() + 25
	while #Players:GetPlayers() < 2 and os.clock() < deadline do task.wait(0.1) end
	local players = Players:GetPlayers()
	check("two real simulated clients joined", #players == 2)
	local first, second = players[1], players[2]
	while os.clock() < deadline and (not first.Character or not second.Character or not State.get(first.UserId) or not State.get(second.UserId)) do task.wait(0.1) end
	assert(first.Character and second.Character, "Characters missing")
	local a, b = assert(State.get(first.UserId)), assert(State.get(second.UserId))
	check("separate real player profiles", a ~= b and a.rawCorn ~= b.rawCorn)
	check("two owned fields assigned", a.fields.Starter.ownerUserId == first.UserId and b.fields.Starter.ownerUserId == second.UserId)
	local at = assert(Farms.target(first.UserId, "Starter", "1"))
	local bt = assert(Farms.target(second.UserId, "Starter", "1"))
	check("real player farms do not overlap", math.abs(at.Position.X - bt.Position.X) >= Config.Farm.separation)
	first.Character:PivotTo(CFrame.new(bt.Position + Vector3.new(0, 2, -2)))
	local response = Harvest.attempt(first, second.UserId, "Starter", "1")
	check("first player cannot harvest second field", not response.ok and response.reason == "Not your field" and b.rawCorn.Normal == 0)
	second.Character:PivotTo(CFrame.new(at.Position + Vector3.new(0, 2, -2)))
	response = Harvest.attempt(second, first.UserId, "Starter", "1")
	check("second player cannot harvest first field", not response.ok and response.reason == "Not your field" and a.rawCorn.Normal == 0)
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	first.Character:PivotTo(CFrame.new(at.Position + Vector3.new(0, 2, -2)))
	second.Character:PivotTo(CFrame.new(bt.Position + Vector3.new(0, 2, -2)))
	local now = DateTime.now().UnixTimestampMillis / 1000
	a.fields.Starter.stalks["1"].growthStartedAt = now - Config.Crops.Normal.growthSeconds
	b.fields.Starter.stalks["1"].growthStartedAt = now - Config.Crops.Normal.growthSeconds
	response = Harvest.attempt(first, first.UserId, "Starter", "1")
	check("first player harvest affects only first inventory", response.ok and a.rawCorn.Normal == 1 and b.rawCorn.Normal == 0)
	response = Harvest.attempt(second, second.UserId, "Starter", "1")
	check("second player harvest affects only second inventory", response.ok and b.rawCorn.Normal == 1 and a.rawCorn.Normal == 1)
	check("both inventory attributes match", first:GetAttribute("RawCorn") == 1 and second:GetAttribute("RawCorn") == 1)
end)
finished = true
local result = { passed = ok, error = if ok then nil else tostring(err), checks = checks }
print("[PopcornTycoon multiplayer] " .. (if ok then "PASS " else "FAIL ") .. tostring(#checks) .. " checks")
TestService:EndTest(result)
