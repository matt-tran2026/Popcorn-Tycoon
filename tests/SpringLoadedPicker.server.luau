--!strict
-- Play runner for the Spring-Loaded Picker (Uncommon, DashHarvest, Spring Dash): config, the
-- lane rule (6 wide, 1 behind to 12 ahead, 4 nearest) and its cut-short reach, the dash's shape
-- cast (stops short of solid walls; walk-through parts and characters ignored), the model
-- (template or part-built: Plunger rod with the jaws hung on it, Latch, stretching Spring,
-- materials, frame), the presentation (Dash marker, stretch, dash effect), the purchase, a dash
-- down the gap between two columns of Plot 1 (both rows, capped at 4), a dash into a wall (cut
-- short), and the 1.5 s cadence with its jitter allowance. At the end it leaves the player
-- holding the picker in the gap with the corn kept ripe, for a visual check.
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
local scratch: { Instance } = {}
local function wall(cframe: CFrame, size: Vector3, solid: boolean): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.Size, p.CFrame = "PickerTestWall", true, solid, size, cframe
	p.Transparency = 0.5
	p.Parent = workspace
	table.insert(scratch, p)
	return p
end

local ok, err = pcall(function()
	local picker = Config.Tools.SpringLoadedPicker
	check("config matches the catalog", picker ~= nil and picker.rarity == "Uncommon" and picker.behavior == "DashHarvest"
		and picker.maxTargets == 4 and picker.cooldownSeconds == 1.5 and picker.reach == 12 and picker.yieldMultiplier == 1
		and picker.laneWidth == 6 and picker.arcDegrees == nil and picker.dash ~= nil)
	local dash = assert(picker.dash)
	check("the dash lands inside one cooldown", picker.reach / dash.speed + (picker.swingSeconds or 0) < picker.cooldownSeconds,
		string.format("%.2f s", picker.reach / dash.speed))
	check("a dash tool uses the lane rule", ToolRules.usesLane(picker) and ToolRules.usesLane(Config.Tools.Pitchfork)
		and not ToolRules.usesLane(Config.Tools.Sickle))

	-- Lane: 3 studs either side, 1 behind to 12 ahead; a shorter reach cuts it.
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local field = {
		c("a", -2.5, -0.5), c("b", 2.5, -0.5), c("c", -2.5, 4.5), c("d", 2.5, 4.5), c("e", -2.5, 9.5), c("f", 2.5, 9.5),
		c("past", 0, 12.4), c("wide", 3.3, 2), c("behind", 0, -1.3),
	}
	local picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), field, picker)
	check("lane: the 4 nearest of 6 inside, nothing wider, further or behind", table.concat(picked, ",") == "a,b,c,d", table.concat(picked, ","))
	local loose = table.clone(picker)
	loose.maxTargets = 10
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), field, loose)
	table.sort(picked)
	check("lane reaches 12 ahead (cap lifted)", table.concat(picked, ",") == "a,b,c,d,e,f", table.concat(picked, ","))
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), field, loose, nil, 5)
	table.sort(picked)
	check("a shorter dash reach cuts the lane", table.concat(picked, ",") == "a,b,c,d", table.concat(picked, ","))
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), field, loose, nil, 40)
	check("a reach past the tool's is capped at the tool's", #picked == 6, tostring(#picked))

	-- Shape cast, up in the sky away from the map: a solid wall 10 ahead stops the dash 1.5 short
	-- of the body box (half a stud deep) touching it; walk-through parts and ignored models don't.
	local origin = CFrame.lookAt(Vector3.new(0, 600, 0), Vector3.new(0, 600, 10))
	check("open air: the full 12 studs", math.abs(ToolRules.dashReach(origin, picker, {}) - 12) < 1e-3)
	local w = wall(CFrame.new(0, 600, 10.5), Vector3.new(8, 8, 1), true)
	local r = ToolRules.dashReach(origin, picker, {})
	check("a wall 10 ahead stops the dash about 8 out", r > 7.5 and r < 8.5, string.format("%.2f", r))
	w.CanCollide = false
	check("walk-through parts never stop it", math.abs(ToolRules.dashReach(origin, picker, {}) - 12) < 1e-3)
	w.CanCollide = true
	check("ignored models (characters) never stop it", math.abs(ToolRules.dashReach(origin, picker, { w }) - 12) < 1e-3)
	local low = wall(CFrame.new(0, 600 - 1.8, 6), Vector3.new(8, 0.6, 1), true)
	w:Destroy()
	r = ToolRules.dashReach(origin, picker, {})
	check("a knee-high fence stops it too", r > 3 and r < 4.5, string.format("%.2f", r))
	low:Destroy()
	check("a wall against the nose: no dash", (function()
		local close = wall(CFrame.new(0, 600, 1.2), Vector3.new(8, 8, 1), true)
		local d = ToolRules.dashReach(origin, picker, {})
		close:Destroy()
		return d == 0
	end)())

	-- Presentation: Dash marker, stretch rule, jaws on the rod, dash effect.
	local look = assert(ToolPresentation.get("SpringLoadedPicker"))
	local swingClip = look.clips.Swing
	check("swing clip is the full swing with Dash and Hit markers", swingClip.seconds == picker.swingSeconds
		and swingClip.markers ~= nil and (swingClip.markers :: any).Dash ~= nil and (swingClip.markers :: any).Hit ~= nil)
	local joints = look.model.joints or {}
	check("jaws hang on the plunger rod", joints.PickerJawTop ~= nil and joints.PickerJawTop.on == "PickerRod"
		and joints.PickerJawBottom ~= nil and joints.PickerJawBottom.on == "PickerRod" and joints.PickerRod.motor == "Plunger")
	local stretch = (look.model.stretch or {}).PickerSpring
	check("the coil stretches with the plunger", stretch ~= nil and stretch.motor == "Spring" and stretch.follow == "Plunger")
	check("dash effect configured", look.vfx.dash ~= nil and look.model.points[(look.vfx.dash :: any).sparkPoint] ~= nil)

	-- Model: Blender template if imported, else the part-built one.
	local tool = ToolModels.build("SpringLoadedPicker")
	local built = tool:FindFirstChild("Handle")
	if built and built:IsA("BasePart") then built.Anchored = true end -- Held still while the motors are moved.
	tool.Parent = workspace -- Motors only move parts in the world.
	table.insert(scratch, tool)
	task.wait(0.1)
	local function part(name: string): BasePart?
		local found = tool:FindFirstChild(name)
		return if found and found:IsA("BasePart") then found else nil
	end
	local handle, rod, spring = part("Handle"), part("PickerRod"), part("PickerSpring")
	local jawTop, jawBottom, head, latch = part("PickerJawTop"), part("PickerJawBottom"), part("PickerHead"), part("PickerLatch")
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Uncommon" and tool:GetAttribute("ModelSource") ~= nil,
		tostring(tool:GetAttribute("ModelSource")))
	check("all seven meshes present", handle ~= nil and rod ~= nil and spring ~= nil and jawTop ~= nil and jawBottom ~= nil
		and head ~= nil and latch ~= nil)
	check("materials: plastic grip and head, metal coil, rod and jaws", handle ~= nil and spring ~= nil and head ~= nil and jawTop ~= nil
		and (handle :: BasePart).Material == Enum.Material.SmoothPlastic and (head :: BasePart).Material == Enum.Material.SmoothPlastic
		and (spring :: BasePart).Material == Enum.Material.Metal and (jawTop :: BasePart).Material == Enum.Material.Metal)
	check("claw point on the handle", handle ~= nil and (handle :: BasePart):FindFirstChild("ClawTip") ~= nil)
	if handle and rod and spring and jawTop and jawBottom then
		local h = handle :: BasePart
		local frame = h.CFrame * tool.Grip * look.model.grip:Inverse()
		local function at(p: BasePart): Vector3 return frame:PointToObjectSpace(p.Position) end
		local springAt, rodAt, jawAt = at(spring :: BasePart), at(rod :: BasePart), at(jawTop :: BasePart)
		check("coil ahead of the grip on the barrel line", springAt.X > 2 and springAt.X < 2.5 and math.abs(springAt.Z - 0.6) < 0.15
			and math.abs(springAt.Y) < 0.15, fmt(springAt))
		check("claw out front, top jaw above the barrel", jawAt.X > 3.7 and jawAt.X < 4.4 and jawAt.Z > 0.65, fmt(jawAt))
		check("bottom jaw below the barrel", at(jawBottom :: BasePart).Z < 0.55, fmt(at(jawBottom :: BasePart)))
		check("rod on the barrel line", math.abs(rodAt.Z - 0.6) < 0.15, fmt(rodAt))
		local function motor(name: string): Motor6D?
			local m = tool:FindFirstChild(name, true)
			return if m and m:IsA("Motor6D") then m else nil
		end
		local plunger, jt, springMotor = motor("Plunger"), motor("JawTop"), motor("Spring")
		check("plunger moves the rod from the handle", plunger ~= nil and (plunger :: Motor6D).Part0 == h and (plunger :: Motor6D).Part1 == rod)
		check("jaw motors hang on the rod", jt ~= nil and (jt :: Motor6D).Part0 == rod and (jt :: Motor6D).Part1 == jawTop)
		if plunger then
			local axis = (h.CFrame * (plunger :: Motor6D).C0).RightVector
			check("the plunger slides along the barrel", axis:Dot(frame.RightVector) > 0.999, fmt(axis))
		end
		local axis, rest = (spring :: BasePart):GetAttribute("StretchAxis"), (spring :: BasePart):GetAttribute("StretchRest")
		check("coil marked for stretching along the barrel", springMotor ~= nil and typeof(axis) == "Vector3" and typeof(rest) == "Vector3"
			and math.abs((spring :: BasePart).CFrame:VectorToWorldSpace(axis :: Vector3):Dot(frame.RightVector)) > 0.99,
			tostring(axis))
		-- Firing: slide the plunger 0.6 and the jaw shut, as the clip does, and the coil stretch rule.
		if plunger and jt and springMotor and typeof(axis) == "Vector3" and typeof(rest) == "Vector3" then
			local tipBefore = at(jawTop :: BasePart)
			;(plunger :: Motor6D).Transform = CFrame.new(0.6, 0, 0)
			;(jt :: Motor6D).Transform = CFrame.Angles(0, math.rad(11), 0)
			local length = (stretch :: any).length
			local factor = (length + 0.6) / length
			;(spring :: BasePart).Size = rest + axis * rest:Dot(axis) * (factor - 1)
			;(springMotor :: Motor6D).Transform = CFrame.new(0.3, 0, 0)
			task.wait(0.1)
			local tipAfter = at(jawTop :: BasePart)
			check("firing carries the jaw forward", tipAfter.X - tipBefore.X > 0.45, fmt(tipAfter - tipBefore))
			check("closing turns the top jaw down", tipAfter.Z < tipBefore.Z, fmt(tipAfter - tipBefore))
			-- The coil's rear end stays seated at the rear collar (x 1.5 on the barrel).
			local s = spring :: BasePart
			local rear = frame:PointToObjectSpace(s.Position - s.CFrame:VectorToWorldSpace(axis) * s.Size:Dot(axis) / 2)
			local front = frame:PointToObjectSpace(s.Position + s.CFrame:VectorToWorldSpace(axis) * s.Size:Dot(axis) / 2)
			local lo, hi = math.min(rear.X, front.X), math.max(rear.X, front.X)
			check("stretched coil spans the rear collar to the fired head", math.abs(lo - 1.5) < 0.12 and math.abs(hi - 3.6) < 0.12,
				string.format("%.2f .. %.2f", lo, hi))
		end
	end
	tool:Destroy()

	-- Buying through the Shop path.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.SpringLoadedPicker then Tools.revoke(player, "SpringLoadedPicker") end
	profile.cash = picker.price + 9
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "SpringLoadedPicker"))
	check("shop buy charges the price once", bought.ok and profile.cash == 9 and profile.ownedTools.SpringLoadedPicker == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "SpringLoadedPicker")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "SpringLoadedPicker" end, 2))
	local held = assert(player.Character):FindFirstChildOfClass("Tool")
	check("the held tool is the picker", held ~= nil and held:GetAttribute("ToolId") == "SpringLoadedPicker")

	-- Plot 1 is 6 columns of stalks 5 studs apart; "back" runs from row 0 toward the back rows.
	local plot = profile.fields.Plot1
	local crop = Config.Crops[plot.cropId]
	local function ripen()
		local at = now()
		for _, stalk in plot.stalks do stalk.growthStartedAt = at - crop.growthSeconds end
	end
	local function cutIds(): { string }
		local list = {}
		for id, stalk in plot.stalks do if Growth.yields(stalk.growthStartedAt, now(), crop) < 1 then table.insert(list, id) end end
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

	-- Down the gap between columns 3 and 4: 3 stalks per column inside 12 studs, capped at 4.
	stand(gap)
	ripen()
	profile.rawCorn.Normal = 0
	task.wait(1.6)
	local r1 = Harvest.swing(player, "SpringLoadedPicker")
	local gone = cutIds()
	check("a dash down the gap takes the 4 nearest of both rows", r1.ok and r1.amount == 4 and #gone == 4
		and table.concat(gone, ",") == "1_10,1_3,1_4,1_9", r1.reason .. " " .. tostring(r1.amount) .. " gone " .. table.concat(gone, ","))
	check("the reply reports the full dash", r1.dashReach ~= nil and math.abs((r1.dashReach :: number) - 12) < 0.01, tostring(r1.dashReach))
	local r2 = Harvest.swing(player, "SpringLoadedPicker")
	check("an immediate second dash is refused", not r2.ok and r2.reason == "Too fast")
	ripen()
	task.wait(0.9) -- 0.6 s early: inside the half-cooldown (0.75 s) jitter allowance.
	local r3 = Harvest.swing(player, "SpringLoadedPicker")
	check("a slightly early dash (jitter) is accepted", r3.ok and r3.amount == 4, r3.reason)
	local r4 = Harvest.swing(player, "SpringLoadedPicker")
	check("but the allowance is not a free extra dash", not r4.ok and r4.reason == "Too fast")

	-- A wall 6 studs ahead in the gap: the dash (and the lane) stops at about 4, so only the first
	-- pair is in reach.
	stand(gap)
	local start = root().CFrame
	wall(start * CFrame.new(0, 0, -6.5), Vector3.new(6, 8, 1), true)
	ripen()
	task.wait(1.6)
	local r5 = Harvest.swing(player, "SpringLoadedPicker")
	gone = cutIds()
	check("a dash into a wall is cut short", r5.ok and r5.amount == 2 and table.concat(gone, ",") == "1_3,1_4"
		and r5.dashReach ~= nil and (r5.dashReach :: number) < 5, r5.reason .. " " .. table.concat(gone, ",") .. " reach " .. tostring(r5.dashReach))
	for _, item in scratch do if item.Parent then item:Destroy() end end

	-- Leave the player ready for a visual check: holding the picker in the gap, corn kept ripe.
	stand(gap)
	ripen()
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	task.spawn(function()
		local untilAt = os.clock() + 90
		while os.clock() < untilAt do
			ripen()
			profile.rawCorn.Normal = 0
			task.wait(0.5)
		end
	end)
end)

for _, item in scratch do if item.Parent then item:Destroy() end end
local passed = ok
for _, c in checks do if not c.passed then passed = false end end
script:SetAttribute("Results", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
print("[SpringLoadedPicker tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
