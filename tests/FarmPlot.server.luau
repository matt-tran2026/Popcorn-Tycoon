--!strict
-- Temporary Server RunContext integration runner during Play, after StarterField tests.
local Players = game:GetService("Players")
local Services = game.ServerScriptService.PopcornTycoon
local Farms = require(Services.FarmService)
local State = require(Services.PlayerStateService)
local Harvest = require(Services.HarvestService)
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
local checks = {}
local function check(name: string, passed: boolean)
	table.insert(checks, { name = name, passed = passed })
	assert(passed, name)
end
local player = assert(Players:GetPlayers()[1])
local character = assert(player.Character)
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local root = character:WaitForChild("HumanoidRootPart") :: BasePart
local pivot = character:GetPivot()
local function walkTo(position: Vector3)
	humanoid:MoveTo(position)
	local deadline = os.clock() + 7
	while (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude > 2 and os.clock() < deadline do task.wait(0.1) end
	assert((Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude <= 2, "Walking route blocked")
end
local ok, err = pcall(function()
	local farm = workspace.PopcornFarms:FindFirstChild("Farm_" .. player.UserId) :: Model
	local scenery = farm:FindFirstChild("Scenery") :: Model
	local parts, lights, prompts, scripts = 0, 0, 0, 0
	local obstacles = 0
	for _, object in farm:GetDescendants() do
		if object:IsA("BasePart") then
			parts += 1
			if object.CanCollide and object.Name ~= "GrassFoundation" then obstacles += 1 end
		elseif object:IsA("Light") then lights += 1
		elseif object:IsA("ProximityPrompt") then prompts += 1
		elseif object:IsA("LuaSourceContainer") then scripts += 1 end
	end
	check("bounded plot geometry and lights", parts <= 400 and lights == 2)
	check("no decorative scripts or new interactive placeholders", scripts == 0 and prompts == 12)
	check("no collision obstacles in decorative geometry", obstacles == 0)
	check("stations and expansion explicitly visual only", scenery.MicrowaveStation:GetAttribute("VisualOnly") and scenery.ToolShed:GetAttribute("VisualOnly") and scenery.FutureExpansion:GetAttribute("VisualOnly"))
	local center = scenery.GrassFoundation.Position
	check("neighbor footprint has expansion gap", Config.Farm.separation - Config.Farm.plotSize.X >= 8)
	walkTo(Vector3.new(center.X, root.Position.Y, center.Z - 27))
	walkTo(Vector3.new(center.X, root.Position.Y, center.Z - 12))
	check("spawn to entrance and cross path walkable", true)
	local profile = assert(State.get(player.UserId))
	local before, granted = profile.rawCorn.Normal, 0
	for row = 1, 3 do
		for step = 1, 4 do
			local col = if row % 2 == 1 then step else 5 - step
			local id = tostring((row - 1) * 4 + col)
			local target = assert(Farms.target(player.UserId, "Starter", id))
			walkTo(target.Position + Vector3.new(0, 0, -1.8))
			task.wait(Config.Manual.cooldownSeconds + 0.05)
			local owner, fieldId, stalkId = Farms.resolve(target.Harvest)
			check("registered prompt " .. id, owner == player.UserId and fieldId == "Starter" and stalkId == id)
			local result = Harvest.attempt(player, owner, fieldId, stalkId)
			check("walk to and harvest stalk " .. id, result.ok and result.amount >= 1)
			granted += result.amount
			Farms.update(DateTime.now().UnixTimestampMillis / 1000)
		end
	end
	check("all twelve harvests credited exactly once", profile.rawCorn.Normal == before + granted and player:GetAttribute("RawCorn") == before + granted)
end)
character:PivotTo(pivot)
script:SetAttribute("Results", game.HttpService:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = checks }))
print("[FarmPlot tests] " .. (if ok then "PASS " else "FAIL ") .. #checks .. " checks")
