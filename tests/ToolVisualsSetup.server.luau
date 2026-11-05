--!strict
-- Server half of the ToolVisuals Play runner: gives the first player the Sickle (Developer Panel
-- path, no charge), ripens Plot 1 and stands them on the cross path facing row 1, then reports
-- the corn they carry so the client half can confirm a real server harvest.
-- Install at ServerScriptService.PopcornTestRunners (never in the synced folder); delete after.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Services = game:GetService("ServerScriptService"):WaitForChild("PopcornTycoon")
local State = require(Services.PlayerStateService)
local Farms = require(Services.FarmService)
local Tools = require(Services.ToolService)

local readyBy = os.clock() + 30
while os.clock() < readyBy do
	local first = Players:GetPlayers()[1]
	if first and first.Character and State.get(first.UserId) and Farms.has(first.UserId) then break end
	task.wait(0.25)
end
task.wait(1)
local player = assert(Players:GetPlayers()[1], "Requires a live player")
local profile = assert(State.get(player.UserId))
local ok, err = pcall(function()
	if not profile.ownedTools.Sickle then Tools.grant(player, "Sickle") end
	local field = profile.fields.Plot1
	local crop = Config.Crops[field.cropId]
	local at = DateTime.now().UnixTimestampMillis / 1000
	for _, stalk in field.stalks do stalk.growthStartedAt = at - crop.growthSeconds end
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	local a = assert(Farms.target(player.UserId, "Plot1", "1_3")).Position
	local b = assert(Farms.target(player.UserId, "Plot1", "1_4")).Position
	local inward = (assert(Farms.target(player.UserId, "Plot1", "1_9")).Position - a) * Vector3.new(1, 0, 1)
	local spot = (a + b) / 2 - inward.Unit * 2.5
	local root = (assert(player.Character):WaitForChild("HumanoidRootPart")) :: BasePart
	local y = root.Position.Y
	assert(player.Character):PivotTo(CFrame.lookAt(Vector3.new(spot.X, y, spot.Z), Vector3.new(spot.X, y, spot.Z) + inward))
end)
script:SetAttribute("SetupOk", ok)
script:SetAttribute("SetupError", if ok then nil else tostring(err))
-- Ready flag the client half waits for.
player:SetAttribute("ToolVisualsReady", ok)
print("[ToolVisuals setup] " .. (if ok then "ready" else "FAILED: " .. tostring(err)))
