--!strict
-- Studio-only integration runner. Install temporarily as a Server RunContext Script
-- in ServerScriptService during Play; never include in normal bootstrapping.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local Services = game:GetService("ServerScriptService"):WaitForChild("PopcornTycoon")
local State = require(Services.PlayerStateService)
local Farms = require(Services.FarmService)
local Harvest = require(Services.HarvestService)
local results: { { name: string, passed: boolean } } = {}
local function check(name: string, condition: boolean)
	table.insert(results, { name = name, passed = condition })
	assert(condition, name)
end
local player = Players:GetPlayers()[1]
local fixtureId = -9000001
local originalPivot: CFrame? = nil

local ok, err = pcall(function()
	assert(player and player.Character, "Requires a live player")
	originalPivot = player.Character:GetPivot()
	local crop = Config.Crops.Normal
	local start = 1000
	check("zero elapsed", Growth.yields(start, start, crop) == 0)
	check("negative elapsed clamped", Growth.yields(start, start - 1, crop) == 0)
	check("before maturity", Growth.yields(start, start + crop.growthSeconds - 0.01, crop) == 0)
	check("exact maturity", Growth.yields(start, start + crop.growthSeconds, crop) == 1)
	check("two cycles plus remainder", Growth.yields(start, start + crop.growthSeconds * 2.5, crop) == 2)
	check("capacity after long absence", Growth.yields(start, start + 1e9, crop) == 3)
	check("same timestamp calculation is stable", Growth.yields(start, start + crop.growthSeconds * 2.5, crop) == 2)
	local profile = assert(State.get(player.UserId), "Profile not available in server script context")
	check("profile version and contract", profile.schemaVersion == 1 and profile.popcorn == 0 and profile.ownedTools.Manual and profile.equippedTool == "Manual" and profile.unlockedCrops.Normal)
	local field = profile.fields.Starter
	local count = 0
	for _ in field.stalks do count += 1 end
	check("nine individually timed stalks", count == 9)
	local fixture = State.load(fixtureId, DateTime.now().UnixTimestampMillis / 1000)
	Farms.create(fixtureId, fixture.fields.Starter)
	check("second profile starts harvestable", Growth.yields(fixture.fields.Starter.stalks["1"].growthStartedAt, DateTime.now().UnixTimestampMillis / 1000, crop) >= 1)
	fixture.rawCorn.Normal = 7
	local before = profile.rawCorn.Normal
	check("profiles do not alias", profile.rawCorn.Normal == before and profile.rawCorn ~= fixture.rawCorn)
	local ownTarget = assert(Farms.target(player.UserId, "Starter", "1"))
	local foreignTarget = assert(Farms.target(fixtureId, "Starter", "1"))
	player.Character:PivotTo(CFrame.new(foreignTarget.Position + Vector3.new(0, 2, -2)))
	local response = Harvest.attempt(player, fixtureId, "Starter", "1")
	check("foreign field rejected even in reach", not response.ok and response.reason == "Not your field" and fixture.rawCorn.Normal == 7)
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	response = Harvest.attempt(player, player.UserId, {}, "1")
	check("malformed target rejected", not response.ok and response.reason == "Invalid target")
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	player.Character:PivotTo(CFrame.new(ownTarget.Position + Vector3.new(100, 0, 0)))
	response = Harvest.attempt(player, player.UserId, "Starter", "1")
	check("out of range rejected", not response.ok and response.reason == "Too far away")
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	player.Character:PivotTo(CFrame.new(ownTarget.Position + Vector3.new(0, 2, -2)))
	profile.equippedTool = "Unowned"
	response = Harvest.attempt(player, player.UserId, "Starter", "1")
	profile.equippedTool = "Manual"
	check("invalid equipped tool rejected", not response.ok and response.reason == "Manual tool required")
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	field.stalks["1"].growthStartedAt = DateTime.now().UnixTimestampMillis / 1000 - crop.growthSeconds * 20
	Farms.update(DateTime.now().UnixTimestampMillis / 1000)
	response = Harvest.attempt(player, player.UserId, "Starter", "1")
	check("capped harvest grants exactly three", response.ok and response.amount == 3 and profile.rawCorn.Normal == before + 3)
	local harvestedAt = field.stalks["1"].growthStartedAt
	response = Harvest.attempt(player, player.UserId, "Starter", "1")
	check("immediate replay rate limited", not response.ok and response.reason == "Too fast" and profile.rawCorn.Normal == before + 3)
	task.wait(Config.Manual.cooldownSeconds + 0.05)
	response = Harvest.attempt(player, player.UserId, "Starter", "1")
	check("unavailable stalk cannot grant twice", not response.ok and response.reason == "Corn is growing" and field.stalks["1"].growthStartedAt == harvestedAt and profile.rawCorn.Normal == before + 3)
	Farms.update(DateTime.now().UnixTimestampMillis / 1000)
	check("harvest resets visible growth", ownTarget:GetAttribute("AvailableYields") == 0 and ownTarget:GetAttribute("GrowthStage") == 0)
	check("remainder discarded on harvest", Growth.yields(harvestedAt, harvestedAt + crop.growthSeconds - 0.01, crop) == 0)
	task.wait(crop.growthSeconds + Config.VisualUpdateSeconds)
	Farms.update(DateTime.now().UnixTimestampMillis / 1000)
	check("real time regrowth becomes available", ownTarget:GetAttribute("AvailableYields") == 1 and ownTarget:GetAttribute("GrowthStage") == 3)
	response = Harvest.attempt(player, player.UserId, "Starter", "1")
	check("regrown harvest adds one", response.ok and response.amount == 1 and profile.rawCorn.Normal == before + 4)
	check("harvesting does not grant popcorn", profile.popcorn == 0)
end)

Farms.remove(fixtureId)
State.release(fixtureId)
Harvest.release(fixtureId)
if player and player.Character and originalPivot then player.Character:PivotTo(originalPivot) end
check("fixture cleanup", State.get(fixtureId) == nil and workspace.PopcornFarms:FindFirstChild("Farm_" .. tostring(fixtureId)) == nil)
script:SetAttribute("Results", Http:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = results }))
print("[PopcornTycoon tests] " .. (if ok then "PASS " else "FAIL ") .. tostring(#results) .. " checks")
