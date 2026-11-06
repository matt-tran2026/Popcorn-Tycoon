--!strict
-- Play runner for the Pitchfork (Common, LineHarvest): config, the lane targeting rule, the model
-- (holder grip, Thrust motor, head on the shaft, trail), the purchase, a thrust down a column
-- of stalks (3 when standing close, 2 from further back), side rows ignored, the 0.8 s cadence
-- with its jitter allowance, and reach. At the end it leaves the player holding the Pitchfork,
-- facing a ripe column, for a visual check of the thrust.
-- Install at ServerScriptService.PopcornTestRunners (never in the synced folder); start Play,
-- read the Results attribute, stop, delete the folder.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local ToolRules = require(Shared.ToolRules)
local ToolPresentation = require(Shared.ToolPresentation)
local Services = game:GetService("ServerScriptService"):WaitForChild("PopcornTycoon")
local State = require(Services.PlayerStateService)
local Farms = require(Services.FarmService)
local Harvest = require(Services.HarvestService)
local Tools = require(Services.ToolService)
local ToolModels = require(Services.ToolModels)
local checks: { { name: string, passed: boolean, detail: string? } } = {}
local function check(name: string, condition: boolean, detail: string?)
	table.insert(checks, { name = name, passed = condition, detail = detail })
end
local readyBy = os.clock() + 30
while os.clock() < readyBy do
	local first = Players:GetPlayers()[1]
	if first and first.Character and State.get(first.UserId) and Farms.has(first.UserId) then break end
	task.wait(0.25)
end
task.wait(1)
local player = assert(Players:GetPlayers()[1], "Requires a live player")
local function now(): number return DateTime.now().UnixTimestampMillis / 1000 end
local function root(): BasePart return (assert(player.Character):WaitForChild("HumanoidRootPart")) :: BasePart end
local function waitFor(condition: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not condition() and os.clock() < deadline do task.wait(0.05) end
	return condition()
end

local ok, err = pcall(function()
	local fork = Config.Tools.Pitchfork
	check("config matches the catalog", fork ~= nil and fork.rarity == "Common" and fork.behavior == "LineHarvest"
		and fork.maxTargets == 3 and fork.cooldownSeconds == 0.8 and fork.reach == 11 and fork.yieldMultiplier == 1)
	check("lane narrower than the row gap", (fork.laneWidth or 0) / 2 < Config.Plot.spacing)

	-- Lane rule: straight ahead, nearest along the lane first, at most 3.
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), {
		c("a", 0, 0.8), c("b", 0.3, 5.8), c("c", -0.4, 10.8), c("d", 0, 10.95), c("side", 5, 1), c("side2", -2.5, 3),
		c("behind", 0, -2), c("underfoot", 0.2, -0.6), c("past", 0, 11.2),
	}, fork)
	check("three nearest along the lane, underfoot first", #picked == 3 and picked[1] == "underfoot" and picked[2] == "a" and picked[3] == "b",
		table.concat(picked, ","))
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), { c("side", 5, 1), c("side2", -2.5, 3), c("behind", 0, -2), c("past", 0, 11.2) }, fork)
	check("nothing beside the lane, behind it or past 11 studs", #picked == 0, table.concat(picked, ","))
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(1, 0, 0), { c("a", 0, 3), c("x", 6, 0), c("y", 9, 1.5) }, fork)
	check("the lane turns with the facing", #picked == 2 and picked[1] == "x" and picked[2] == "y", table.concat(picked, ","))
	-- The arc tools are unchanged by the new family.
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), { c("l", -3, 3), c("r", 3, 3), c("far", 0, 8.5) }, Config.Tools.Sickle)
	check("Sickle arc unchanged", #picked == 3, table.concat(picked, ","))

	-- Model: Blender template if imported, else the part-built one, both with the holder grip.
	local tool = ToolModels.build("Pitchfork")
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local holder = tool:FindFirstChild("Handle") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local shaft = tool:FindFirstChild("PitchforkHandle") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local head = tool:FindFirstChild("PitchforkHead") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (guarded by `and`)
	local thrust = holder and holder:FindFirstChild("Thrust") :: Motor6D?
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Common" and tool:GetAttribute("ModelSource") ~= nil,
		tostring(tool:GetAttribute("ModelSource")))
	check("hand holds an invisible grip", holder ~= nil and (holder :: BasePart).Transparency == 1)
	check("shaft slides on the Thrust motor", thrust ~= nil and (thrust :: Motor6D).Part1 == shaft)
	local headWeld = head and head:FindFirstChildOfClass("WeldConstraint")
	check("head rides on the shaft", headWeld ~= nil and (headWeld :: WeldConstraint).Part0 == shaft)
	check("trail across the prong tips", shaft ~= nil and (shaft :: BasePart):FindFirstChild("SwingTrail") ~= nil
		and (shaft :: BasePart):FindFirstChild("OuterTipL") ~= nil)
	if holder and shaft and head then
		-- The prongs point along the grip's forward: the head is ~3.5 studs ahead of the hand.
		local look = assert(ToolPresentation.get("Pitchfork"))
		local frame = (holder :: BasePart).CFrame * tool.Grip * look.model.grip:Inverse()
		local headAt = frame:PointToObjectSpace((head :: BasePart).Position)
		check("head ahead of the hand along tool X", headAt.X > 3 and headAt.X < 4.3 and math.abs(headAt.Z) < 0.3,
			string.format("%.2f, %.2f, %.2f", headAt.X, headAt.Y, headAt.Z))
		-- The grip point sits on the shaft axis, 0.498 behind the shaft mesh's centre.
		local shaftAt = frame:PointToObjectSpace((shaft :: BasePart).Position)
		check("grip sits on the shaft", math.abs(shaftAt.X - 0.498) < 0.05 and math.abs(shaftAt.Y) < 0.05 and math.abs(shaftAt.Z) < 0.05,
			string.format("%.3f, %.3f, %.3f", shaftAt.X, shaftAt.Y, shaftAt.Z))
	end
	tool:Destroy()

	-- Buying through the Shop path.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.Pitchfork then Tools.revoke(player, "Pitchfork") end
	profile.cash = fork.price + 7
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "Pitchfork"))
	check("shop buy charges the price once", bought.ok and profile.cash == 7 and profile.ownedTools.Pitchfork == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "Pitchfork")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "Pitchfork" end, 2))
	local held = assert(player.Character):FindFirstChildOfClass("Tool")
	check("the held tool is the pitchfork with a Thrust motor", held ~= nil and held:GetAttribute("ToolId") == "Pitchfork"
		and (held :: Tool):FindFirstChild("Thrust", true) ~= nil)

	-- Thrusting down column 3 of Plot 1 (stalks 1_3, 1_9, 1_15, 1_21 ... are 5 studs apart).
	local field = profile.fields.Plot1
	local crop = Config.Crops[field.cropId]
	local function ripen(cycles: number)
		local at = now()
		for _, stalk in field.stalks do stalk.growthStartedAt = at - cycles * crop.growthSeconds end
	end
	local function cut(): { [string]: boolean }
		local set = {}
		for id, stalk in field.stalks do if Growth.yields(stalk.growthStartedAt, now(), crop) < 1 then set[id] = true end end
		return set
	end
	local first = assert(Farms.target(player.UserId, "Plot1", "1_3")).Position
	local along = ((assert(Farms.target(player.UserId, "Plot1", "1_9")).Position - first) * Vector3.new(1, 0, 1)).Unit
	local y = root().Position.Y
	local function standBefore(distance: number)
		local spot = first - along * distance
		assert(player.Character):PivotTo(CFrame.lookAt(Vector3.new(spot.X, y, spot.Z), Vector3.new(spot.X, y, spot.Z) + along))
		task.wait(0.3)
	end
	standBefore(0.8)
	ripen(1)
	profile.rawCorn.Normal = 0
	task.wait(0.9)
	local r1 = Harvest.swing(player, "Pitchfork")
	local gone = cut()
	check("close thrust pierces 3 stalks in the column", r1.ok and r1.amount == 3 and #(r1.targets or {}) == 3
		and gone["1_3"] == true and gone["1_9"] == true and gone["1_15"] == true and gone["1_21"] == nil,
		r1.reason .. " " .. tostring(r1.amount))
	check("side columns untouched", gone["1_2"] == nil and gone["1_4"] == nil and gone["1_8"] == nil and gone["1_10"] == nil)
	local targets = r1.targets or {}
	check("targets come nearest first", #targets == 3 and (targets[1] - first).Magnitude < 0.5)
	local r2 = Harvest.swing(player, "Pitchfork")
	check("an immediate second thrust is refused", not r2.ok and r2.reason == "Too fast")
	ripen(1)
	task.wait(0.45) -- Early by 0.35 s: inside the half-cooldown (0.4 s) allowance.
	local r3 = Harvest.swing(player, "Pitchfork")
	check("a slightly early thrust (jitter) is accepted", r3.ok and r3.amount == 3, r3.reason)
	local r4 = Harvest.swing(player, "Pitchfork")
	check("but the allowance is not a free extra thrust", not r4.ok and r4.reason == "Too fast")

	-- Positioning: 3 studs back, the third stalk (13 studs) is out of reach.
	standBefore(3)
	ripen(1)
	task.wait(0.9)
	local r5 = Harvest.swing(player, "Pitchfork")
	check("from 3 studs back only 2 are in reach", r5.ok and r5.amount == 2, r5.reason .. " " .. tostring(r5.amount))

	-- Facing across the rows from the path beside the field: nothing in the lane.
	local side = first - along * 3 + along:Cross(Vector3.yAxis) * 2.5
	assert(player.Character):PivotTo(CFrame.lookAt(Vector3.new(side.X, y, side.Z), Vector3.new(side.X, y, side.Z) - along))
	task.wait(0.3)
	ripen(1)
	task.wait(0.9)
	local before = profile.rawCorn.Normal
	local r6 = Harvest.swing(player, "Pitchfork")
	check("facing away from the corn cuts nothing", not r6.ok and profile.rawCorn.Normal == before, r6.reason)

	-- Leave the player ready for a visual check: holding the fork at the head of column 3.
	standBefore(0.8)
	ripen(1)
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	player:SetAttribute("RawCorn", 0)
	task.spawn(function()
		local untilAt = os.clock() + 40
		while os.clock() < untilAt do
			ripen(1)
			task.wait(0.5)
		end
	end)
end)

local passed = ok
for _, c in checks do if not c.passed then passed = false end end
script:SetAttribute("Results", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
print("[Pitchfork tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
