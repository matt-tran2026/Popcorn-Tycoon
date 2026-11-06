--!strict
-- Play runner for the Hedge Trimmer (Uncommon, LineHarvest, Precision Cutting): config, the
-- narrow-rectangle rule (6 wide, 1 behind to 8 ahead, 5 nearest), the model (template or
-- part-built: blades on BladeA/BladeB motors, materials, frame, points), the presentation (two
-- hands, Hit marker, blade buzz on the real motors, trim strip), the purchase, a trim down the
-- gap between two columns of Plot 1 (both rows, 4 stalks on the 5-stud grid), a trim standing on
-- a column (one row only), and the 0.75 s cadence with its jitter allowance. At the end it
-- leaves the player holding the trimmer in the gap with the corn kept ripe, for a visual check.
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
local function fmt(v: Vector3): string return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z) end

local ok, err = pcall(function()
	local trimmer = Config.Tools.HedgeTrimmer
	check("config matches the catalog", trimmer ~= nil and trimmer.rarity == "Uncommon" and trimmer.behavior == "LineHarvest"
		and trimmer.maxTargets == 5 and trimmer.cooldownSeconds == 0.75 and trimmer.reach == 8 and trimmer.yieldMultiplier == 1
		and trimmer.laneWidth == 6 and trimmer.arcDegrees == nil)
	check("the lane fits two rows but never three", (trimmer.laneWidth or 0) > Config.Plot.spacing
		and (trimmer.laneWidth or 0) < Config.Plot.spacing * 2)

	-- Narrow rectangle: 3 studs either side, 1 behind to 8 ahead. Nothing wider, nothing further.
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), {
		c("leftNear", -2.5, 3), c("rightNear", 2.5, 3), c("leftFar", -2.5, 7.9), c("rightPast", 2.5, 8.2),
		c("wide", -3.2, 2), c("behind", 0, -1.2), c("underfoot", -2.5, -0.9), c("side", 6, 0),
	}, trimmer)
	table.sort(picked)
	check("inside the strip in; wider, further or behind out", table.concat(picked, ",") == "leftFar,leftNear,rightNear,underfoot",
		table.concat(picked, ","))
	local many = {}
	for i = 1, 8 do table.insert(many, c("s" .. i, if i % 2 == 0 then 1 else -1, i)) end
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), many, trimmer)
	check("at most 5, nearest first", #picked == 5 and picked[1] == "s1" and picked[5] == "s5", table.concat(picked, ","))

	-- Presentation: two hands, Hit marker, blade buzz on the model's motors, trim strip.
	local look = assert(ToolPresentation.get("HedgeTrimmer"))
	local swingClip = look.clips.Swing
	check("swing clip is the full swing with a Hit marker", swingClip.seconds == trimmer.swingSeconds
		and swingClip.markers ~= nil and (swingClip.markers :: any).Hit ~= nil)
	check("the left arm is held for two hands", look.holdJoints ~= nil and table.find(look.holdJoints :: { string }, "LeftShoulder") ~= nil)
	local motors: { [string]: boolean } = {}
	for _, joint in look.model.joints or {} do motors[joint.motor] = true end
	local buzz = swingClip.buzz
	check("buzz slides both blades on their motors", buzz ~= nil and motors.BladeA == true and motors.BladeB == true
		and (buzz :: any).joints.BladeA ~= nil and (buzz :: any).joints.BladeB ~= nil
		and (buzz :: any).joints.BladeA[4] == -(buzz :: any).joints.BladeB[4])
	check("trim strip effect configured", look.vfx.trim ~= nil and look.model.trail == nil)

	-- Model: Blender template if imported, else the part-built one.
	local tool = ToolModels.build("HedgeTrimmer")
	-- lihfolk-ignore: findfirstchild-chain (optional casts, nil-guarded below)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local top = tool:FindFirstChild("TrimmerBladeTop") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local bottom = tool:FindFirstChild("TrimmerBladeBottom") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local body = tool:FindFirstChild("TrimmerBody") :: BasePart?
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Uncommon" and tool:GetAttribute("ModelSource") ~= nil,
		tostring(tool:GetAttribute("ModelSource")))
	check("handle, body and both blades present", handle ~= nil and top ~= nil and bottom ~= nil and body ~= nil)
	check("materials: plastic housing, metal blades", handle ~= nil and top ~= nil and body ~= nil
		and (handle :: BasePart).Material == Enum.Material.SmoothPlastic and (body :: BasePart).Material == Enum.Material.SmoothPlastic
		and (top :: BasePart).Material == Enum.Material.Metal)
	check("points on the handle", handle ~= nil and (handle :: BasePart):FindFirstChild("BladeMid") ~= nil
		and (handle :: BasePart):FindFirstChild("BladeRoot") ~= nil and (handle :: BasePart):FindFirstChild("LeftHand") ~= nil)
	if handle and top and bottom and body then
		local h = handle :: BasePart
		local frame = h.CFrame * tool.Grip * look.model.grip:Inverse()
		local bladeAt = frame:PointToObjectSpace((top :: BasePart).Position)
		check("blade ahead of the housing, below the grip line", bladeAt.X > 3 and bladeAt.X < 3.8 and bladeAt.Z > 0.4 and bladeAt.Z < 0.85
			and math.abs(bladeAt.Y) < 0.15, fmt(bladeAt))
		local bodyAt = frame:PointToObjectSpace((body :: BasePart).Position)
		check("housing just ahead of the grip", bodyAt.X > 1 and bodyAt.X < 1.6 and bodyAt.Z > -0.1 and bodyAt.Z < 0.45
			and math.abs(bodyAt.Y) < 0.15, fmt(bodyAt))
		local function motorFor(part: BasePart, name: string): Motor6D?
			local m = h:FindFirstChild(name)
			if m and m:IsA("Motor6D") and m.Part1 == part then return m end
			return nil
		end
		local ma, mb = motorFor(top :: BasePart, "BladeA"), motorFor(bottom :: BasePart, "BladeB")
		check("each blade hangs on its own motor from the handle", ma ~= nil and mb ~= nil)
		if ma then
			-- A slide in the motor's frame (what the buzz writes) runs along the bar.
			local axis = (h.CFrame * (ma :: Motor6D).C0).RightVector
			check("the blade motor slides along the bar", axis:Dot(frame.RightVector) > 0.999, fmt(axis))
		end
	end
	tool:Destroy()

	-- Buying through the Shop path.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.HedgeTrimmer then Tools.revoke(player, "HedgeTrimmer") end
	profile.cash = trimmer.price + 9
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "HedgeTrimmer"))
	check("shop buy charges the price once", bought.ok and profile.cash == 9 and profile.ownedTools.HedgeTrimmer == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "HedgeTrimmer")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "HedgeTrimmer" end, 2))
	local held = assert(player.Character):FindFirstChildOfClass("Tool")
	check("the held tool is the hedge trimmer", held ~= nil and held:GetAttribute("ToolId") == "HedgeTrimmer")

	-- Plot 1 is 6 columns of stalks 5 studs apart; "back" runs from row 0 toward the back rows.
	local field = profile.fields.Plot1
	local crop = Config.Crops[field.cropId]
	local function ripen()
		local at = now()
		for _, stalk in field.stalks do stalk.growthStartedAt = at - crop.growthSeconds end
	end
	local function cutIds(): { string }
		local list = {}
		for id, stalk in field.stalks do if Growth.yields(stalk.growthStartedAt, now(), crop) < 1 then table.insert(list, id) end end
		table.sort(list)
		return list
	end
	local function pos(id: string): Vector3 return assert(Farms.target(player.UserId, "Plot1", id)).Position end
	local back = ((pos("1_33") - pos("1_3")) * Vector3.new(1, 0, 1)).Unit
	local y = root().Position.Y
	local function stand(at: Vector3)
		local p = Vector3.new(at.X, y, at.Z) + back * 0.5 -- the first row 0.5 behind: inside the lane
		assert(player.Character):PivotTo(CFrame.lookAt(p, p + back))
		task.wait(0.3)
	end
	local gap = (pos("1_3") + pos("1_4")) / 2

	-- Down the gap between columns 3 and 4: both columns, 2 stalks each (4.5 ahead; 9.5 is out).
	stand(gap)
	ripen()
	profile.rawCorn.Normal = 0
	task.wait(1.2)
	local r1 = Harvest.swing(player, "HedgeTrimmer")
	local gone = cutIds()
	check("a trim down the gap cuts both rows: 4 stalks", r1.ok and r1.amount == 4 and #gone == 4
		and table.concat(gone, ",") == "1_10,1_3,1_4,1_9", r1.reason .. " " .. tostring(r1.amount) .. " gone " .. table.concat(gone, ","))
	local r2 = Harvest.swing(player, "HedgeTrimmer")
	check("an immediate second trim is refused", not r2.ok and r2.reason == "Too fast")
	ripen()
	task.wait(0.45) -- 0.3 s early: inside the half-cooldown (0.375 s) jitter allowance.
	local r3 = Harvest.swing(player, "HedgeTrimmer")
	check("a slightly early trim (jitter) is accepted", r3.ok and r3.amount == 4, r3.reason)
	local r4 = Harvest.swing(player, "HedgeTrimmer")
	check("but the allowance is not a free extra trim", not r4.ok and r4.reason == "Too fast")

	-- Standing on column 3: the strip covers only that column (the side-coverage weakness).
	stand(pos("1_3"))
	ripen()
	task.wait(0.8)
	local r5 = Harvest.swing(player, "HedgeTrimmer")
	gone = cutIds()
	check("standing on a row covers that row only", r5.ok and r5.amount == 2 and table.concat(gone, ",") == "1_3,1_9",
		r5.reason .. " " .. table.concat(gone, ","))

	-- Leave the player ready for a visual check: holding the trimmer in the gap, corn kept ripe.
	stand(gap)
	ripen()
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	task.spawn(function()
		local untilAt = os.clock() + 60
		while os.clock() < untilAt do
			ripen()
			profile.rawCorn.Normal = 0
			task.wait(0.5)
		end
	end)
end)

local passed = ok
for _, c in checks do if not c.passed then passed = false end end
script:SetAttribute("Results", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
print("[HedgeTrimmer tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
