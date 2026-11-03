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
	local parts, lights, scripts = 0, 0, 0
	local prompts: { [string]: number } = {}
	local obstacles = 0
	for _, object in farm:GetDescendants() do
		if object:IsA("BasePart") then
			parts += 1
			if object.CanCollide and object.Name ~= "GrassFoundation" then obstacles += 1 end
		elseif object:IsA("Light") then lights += 1
		elseif object:IsA("ProximityPrompt") then prompts[object.Name] = (prompts[object.Name] or 0) + 1
		elseif object:IsA("LuaSourceContainer") then scripts += 1 end
	end
	-- 36 starter stalks (stem, ear, three-part mesh) plus a larger fence; measured 573 on Nov 3 2026.
	check("bounded plot geometry and lights", parts <= 650 and lights == 2)
	local starterStalks = Config.Starter.rows * Config.Starter.columns
	check("no decorative scripts; only harvest, microwave and row prompts", scripts == 0 and prompts.Harvest == starterStalks and prompts.Microwave == 1 and prompts.BuyRow == 1)
	check("no collision obstacles in decorative geometry", obstacles == 0)
	check("microwave works; shed and expansion stay visual only", scenery.MicrowaveStation:GetAttribute("VisualOnly") == false and scenery.ToolShed:GetAttribute("VisualOnly") and scenery.FutureExpansion:GetAttribute("VisualOnly"))
	local center = scenery.GrassFoundation.Position
	local soil = farm:FindFirstChild("Soil") :: BasePart
	check("neighbor footprint has expansion gap", Config.Farm.separation - Config.Farm.plotSize.X >= 8)
	-- Layout: stations face the field from the front, the lawn sits left of the field.
	local door = assert(Farms.microwave(player.UserId)).door
	local lawn = scenery.FutureExpansion.ReservedGrass :: BasePart
	local rightVector = Vector3.new(-1, 0, 0) -- Visitor's right when walking in along +Z.
	check("stations stand in front of the field", door.Position.Z < soil.Position.Z - soil.Size.Z / 2 and scenery.ToolShed:GetPivot().Position.Z < soil.Position.Z - soil.Size.Z / 2)
	check("microwave faces the field", door.CFrame.LookVector:Dot(Vector3.new(0, 0, 1)) > 0.99)
	check("expansion lawn is left of the field", (lawn.Position - soil.Position):Dot(rightVector) < -(lawn.Size.X + soil.Size.X) / 2 + 1)
	local entrance = Vector3.new(soil.Position.X, root.Position.Y, center.Z - Config.Farm.plotSize.Z / 2 - 1)
	walkTo(entrance)
	walkTo(Vector3.new(soil.Position.X, root.Position.Y, center.Z - 15))
	check("spawn to entrance and cross path walkable", true)
	local profile = assert(State.get(player.UserId))
	local before, granted = profile.rawCorn.Normal, 0
	local columns = Config.Starter.columns
	-- A full 6x6 field can out-yield one bag; start empty and give each stalk exactly one yield.
	profile.rawCorn.Normal, before = 0, 0
	for row = 1, Config.Starter.rows do
		for step = 1, columns do
			local col = if row % 2 == 1 then step else columns + 1 - step
			local id = tostring((row - 1) * columns + col)
			local target = assert(Farms.target(player.UserId, "Starter", id))
			walkTo(target.Position + Vector3.new(0, 0, -1.8))
			task.wait(Config.Manual.cooldownSeconds + 0.05)
			local owner, fieldId, stalkId = Farms.resolve(target.Harvest)
			check("registered prompt " .. id, owner == player.UserId and fieldId == "Starter" and stalkId == id)
			profile.fields.Starter.stalks[id].growthStartedAt = DateTime.now().UnixTimestampMillis / 1000 - Config.Crops.Normal.growthSeconds
			local result = Harvest.attempt(player, owner, fieldId, stalkId)
			check("walk to and harvest stalk " .. id, result.ok and result.amount == 1)
			granted += result.amount
			Farms.update(DateTime.now().UnixTimestampMillis / 1000)
		end
	end
	check("every starter harvest credited exactly once", profile.rawCorn.Normal == before + granted and player:GetAttribute("RawCorn") == before + granted)
end)
character:PivotTo(pivot)
script:SetAttribute("Results", game.HttpService:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = checks }))
print("[FarmPlot tests] " .. (if ok then "PASS " else "FAIL ") .. #checks .. " checks")
