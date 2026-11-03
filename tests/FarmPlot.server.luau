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
-- Follows a navmesh path so routes around the hub centerpiece and over bridges stay real walks.
local function walkPath(goal: Vector3)
	local path = game:GetService("PathfindingService"):CreatePath({ AgentRadius = 2, AgentCanJump = false, WaypointSpacing = 8 })
	path:ComputeAsync(root.Position, goal)
	assert(path.Status == Enum.PathStatus.Success, "No walkable path: " .. path.Status.Name)
	for _, waypoint in path:GetWaypoints() do
		humanoid:MoveTo(waypoint.Position)
		local deadline = os.clock() + 4
		while (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(waypoint.Position.X, 0, waypoint.Position.Z)).Magnitude > 2.5 and os.clock() < deadline do task.wait(0.05) end
	end
	assert((Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(goal.X, 0, goal.Z)).Magnitude <= 3, "Path walk fell short")
end
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
	-- 36 starter stalks (stem, ear, three-part mesh) plus a larger fence; measured 573 on Nov 3 2026,
	-- 628 after the sell stand, shed/stand anchors and the sickle display.
	check("bounded plot geometry and lights", parts <= 650 and lights == 2)
	local starterStalks = Config.Starter.rows * Config.Starter.columns
	check("no decorative scripts; only harvest, microwave, row, sell and tool prompts", scripts == 0 and prompts.Harvest == starterStalks and prompts.Microwave == 1 and prompts.BuyRow == 1 and prompts.Sell == 1 and prompts.BuyTool == 1)
	check("no collision obstacles in decorative geometry", obstacles == 0)
	check("microwave, shed and sell stand work; expansion stays visual only", scenery.MicrowaveStation:GetAttribute("VisualOnly") == false and scenery.ToolShed:GetAttribute("VisualOnly") == false and scenery.SellStand:GetAttribute("VisualOnly") == false and scenery.FutureExpansion:GetAttribute("VisualOnly"))
	local soil = farm:FindFirstChild("Soil") :: BasePart
	-- Layout in the farm's own frame (soil +Z points from the stations toward the back fence;
	-- +X is the visitor's left): stations face the field from the front, the lawn sits left.
	local function local_(position: Vector3): Vector3 return soil.CFrame:PointToObjectSpace(position) end
	local door = assert(Farms.microwave(player.UserId)).door
	local lawn = scenery.FutureExpansion.ReservedGrass :: BasePart
	check("stations stand in front of the field", local_(door.Position).Z < -soil.Size.Z / 2 and local_(scenery.ToolShed:GetPivot().Position).Z < -soil.Size.Z / 2)
	check("microwave faces the field", door.CFrame.LookVector:Dot(soil.CFrame.ZVector) > 0.99)
	check("expansion lawn is left of the field", local_(lawn.Position).X > (lawn.Size.X + soil.Size.X) / 2 - 1)
	-- Map: the entrance faces the hub and a bridge-head sign names the owner.
	local hubCenter = Config.Map.center
	local entranceOffset = Config.Farm.plotSize.Z / 2 - Config.Farm.plotOffset.Z
	local entrance = soil.Position - soil.CFrame.ZVector * entranceOffset
	check("farm entrance faces the hub", (hubCenter - entrance).Unit:Dot(-soil.CFrame.ZVector) > 0.99)
	local named = false
	for _, object in workspace.PopcornMap.HubIsland:GetChildren() do
		local text = object:FindFirstChild("Lettering") and object.Lettering:FindFirstChild("Text")
		if text and text.Text == player.DisplayName .. "'s Farm" then named = true end
	end
	check("hub sign names the farm owner", named)
	-- Every free slot shows starter-farm scenery with nothing to interact with.
	local openPlots = workspace.PopcornOpenPlots:GetChildren()
	local interactive = 0
	for _, plot in openPlots do
		for _, object in plot:GetDescendants() do
			if object:IsA("ProximityPrompt") or object:IsA("LuaSourceContainer") then interactive += 1 end
		end
	end
	check("open slots show starter farms without prompts", #openPlots + #workspace.PopcornFarms:GetChildren() == Config.Map.slots and interactive == 0)
	character:PivotTo(assert(workspace:FindFirstChildOfClass("SpawnLocation")).CFrame + Vector3.new(0, 4, 0))
	task.wait(0.5)
	walkPath(entrance - (entrance - hubCenter).Unit * 2 + Vector3.new(0, root.Position.Y - entrance.Y, 0))
	walkTo(soil.Position - soil.CFrame.ZVector * (soil.Size.Z / 2 + 4) + Vector3.new(0, root.Position.Y - soil.Position.Y, 0))
	check("spawn across the hub and bridge to the cross path walkable", true)
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
			walkTo(target.Position - soil.CFrame.ZVector * 1.8)
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
