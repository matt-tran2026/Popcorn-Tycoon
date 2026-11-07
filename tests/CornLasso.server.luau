--!strict
-- Play runner for the Corn Lasso (Uncommon, TargetedPull, Long-Range Retrieval): config, the
-- aimed-stalk rule (snap within AimSnap, reach plus the server's slack, the loop's neighbour within
-- loopRadius, never more than 2, the cone fallback with no aim), the presentation (Throw marker,
-- Loop joint, lasso effect), the model (template or part-built: Loop motor turning the loop about
-- its pivot, the rope hanging on the tool's Z side, materials, rope point), the purchase, real
-- throws from in front of Plot 1 at a stalk 20 studs into the field, refusals (aim off any stalk,
-- unripe, out of range, junk aim) and the 0.4 s cadence with its jitter allowance. At the end it
-- leaves the player holding the lasso in front of the field with the corn kept ripe, for a
-- visual check. Install at ServerScriptService.PopcornTestRunners (never in the synced folder);
-- start Play, read the Results attribute, stop, delete the folder.
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

local ok, err = pcall(function()
	local lasso = Config.Tools.CornLasso
	check("config matches the catalog", lasso ~= nil and lasso.rarity == "Uncommon" and lasso.behavior == "TargetedPull"
		and lasso.maxTargets == 2 and lasso.cooldownSeconds == 0.4 and lasso.reach == 25 and lasso.yieldMultiplier == 1
		and lasso.loopRadius == 5.5 and lasso.arcDegrees == nil and lasso.laneWidth == nil)
	check("a targeted tool is not a lane tool", not ToolRules.usesLane(lasso))

	-- The rule, on a made-up grid 5 studs apart, the player at the origin facing +Z.
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local field = {
		c("aim", 0, 20), c("n1", 0, 15), c("n2", 5, 20), c("n3", -5, 20), c("n4", 0, 25.4),
		c("wideN", 6, 15), c("far", 0, 26), c("near", 0, 4), c("side", 3.6, 5),
	}
	local facing = Vector3.new(0, 0, 1)
	local function pick(aim: Vector3?, slack: number?): string
		return table.concat(ToolRules.pickTargets(Vector3.zero, facing, field, lasso, nil, nil, aim, slack), ",")
	end
	check("aimed stalk first, then its nearest neighbour inside the loop", pick(Vector3.new(0.3, 3, 20.2)) == "aim,n1", pick(Vector3.new(0.3, 3, 20.2)))
	check("an aim more than AimSnap from any stalk takes nothing", pick(Vector3.new(2.6, 7, 17.5)) == "", pick(Vector3.new(2.6, 7, 17.5)))
	check("a stalk past the reach cannot be aimed", pick(Vector3.new(0, 7, 26)) == "", pick(Vector3.new(0, 7, 26)))
	check("the server's lag slack lets it through", pick(Vector3.new(0, 7, 26), ToolRules.ReachSlack) == "far,n4",
		pick(Vector3.new(0, 7, 26), ToolRules.ReachSlack))
	local wide = table.clone(lasso)
	wide.maxTargets = 10
	local all = ToolRules.pickTargets(Vector3.zero, facing, field, wide, nil, nil, Vector3.new(0, 7, 20))
	table.sort(all)
	check("the loop only snags within loopRadius and reach", table.concat(all, ",") == "aim,n1,n2,n3", table.concat(all, ","))
	check("never more than 2 a throw", #ToolRules.pickTargets(Vector3.zero, facing, field, lasso, nil, nil, Vector3.new(0, 7, 20)) == 2)
	check("no aim: the nearest ripe stalk in the cone ahead", pick(nil) == "near,side", pick(nil))
	check("a broken aim is no aim", pick(Vector3.new(0 / 0, 0, 0)) == pick(nil) and pick(Vector3.new(math.huge, 0, 0)) == pick(nil))
	check("facing does not matter once aimed", table.concat(ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, -1), field, lasso,
		nil, nil, Vector3.new(0, 7, 20)), ",") == "aim,n1")

	-- Presentation: Throw marker, the Loop joint, the lasso effect.
	local look = assert(ToolPresentation.get("CornLasso"))
	local swingClip = look.clips.Swing
	check("swing clip is the full swing with a Throw marker", swingClip.seconds == lasso.swingSeconds
		and swingClip.markers ~= nil and (swingClip.markers :: any).Throw ~= nil)
	local joints = look.model.joints or {}
	check("the loop turns on its own motor", joints.LassoLoop ~= nil and joints.LassoLoop.motor == "Loop")
	local spec = look.vfx.lasso
	check("lasso effect configured", spec ~= nil and look.model.points[(spec :: any).ropePoint] ~= nil
		and (spec :: any).loopMesh == "LassoLoop")

	-- Model: Blender template if imported, else the part-built one.
	local tool = ToolModels.build("CornLasso")
	local built = tool:FindFirstChild("Handle")
	if built and built:IsA("BasePart") then built.Anchored = true end
	tool.Parent = workspace
	table.insert(scratch, tool)
	task.wait(0.1)
	local function part(name: string): BasePart?
		local found = tool:FindFirstChild(name)
		return if found and found:IsA("BasePart") then found else nil
	end
	local handle, loop, coil = part("Handle"), part("LassoLoop"), part("LassoCoil")
	local fittings, tassels = part("LassoFittings"), part("LassoTassels")
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Uncommon" and tool:GetAttribute("ModelSource") ~= nil,
		tostring(tool:GetAttribute("ModelSource")))
	check("all five meshes present", handle ~= nil and loop ~= nil and coil ~= nil and fittings ~= nil and tassels ~= nil)
	check("materials: leather grip, metal fittings, fabric rope", handle ~= nil and fittings ~= nil and loop ~= nil and coil ~= nil
		and (handle :: BasePart).Material == Enum.Material.Leather and (fittings :: BasePart).Material == Enum.Material.Metal
		and (loop :: BasePart).Material == Enum.Material.Fabric and (coil :: BasePart).Material == Enum.Material.Fabric)
	check("rope point on the handle", handle ~= nil and (handle :: BasePart):FindFirstChild("RopeOut") ~= nil)
	if handle and loop and coil then
		local h = handle :: BasePart
		local frame = h.CFrame * tool.Grip * look.model.grip:Inverse()
		local function at(p: BasePart): Vector3 return frame:PointToObjectSpace(p.Position) end
		check("coil hangs ahead of the grip on the tool's Z side", at(coil :: BasePart).X > 1 and at(coil :: BasePart).Z > 0.15, fmt(at(coil :: BasePart)))
		check("loop hangs further out on the same side", at(loop :: BasePart).X > 1.5 and at(loop :: BasePart).Z > 0.15, fmt(at(loop :: BasePart)))
		local rope = h:FindFirstChild("RopeOut")
		check("rope point at the collar", rope ~= nil and rope:IsA("Attachment")
			and (frame:PointToObjectSpace(rope.WorldPosition) - Vector3.new(1.12, 0, 0.05)).Magnitude < 0.05)
		local motor = tool:FindFirstChild("Loop", true)
		check("the Loop motor moves the loop from the handle", motor ~= nil and motor:IsA("Motor6D") and motor.Part0 == h and motor.Part1 == loop)
		if motor and motor:IsA("Motor6D") then
			local pivot = frame:PointToWorldSpace(Vector3.new(1.12, 0, 0.05))
			local before = (loop :: BasePart).Position
			motor.Transform = CFrame.Angles(0, math.rad(90), 0)
			task.wait(0.1)
			local after = (loop :: BasePart).Position
			check("twirling turns the loop about its pivot in its own plane", (after - before).Magnitude > 0.3
				and math.abs((after - pivot).Magnitude - (before - pivot).Magnitude) < 0.02
				and math.abs(frame:VectorToObjectSpace(after - before).Y) < 0.02, fmt(frame:VectorToObjectSpace(after - before)))
		end
	end
	tool:Destroy()

	-- Buying through the Shop path.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.CornLasso then Tools.revoke(player, "CornLasso") end
	profile.cash = lasso.price + 9
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "CornLasso"))
	check("shop buy charges the price once", bought.ok and profile.cash == 9 and profile.ownedTools.CornLasso == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "CornLasso")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "CornLasso" end, 2))
	local held = assert(player.Character):FindFirstChildOfClass("Tool")
	check("the held tool is the lasso", held ~= nil and held:GetAttribute("ToolId") == "CornLasso")

	-- Plot 1: 6 columns 5 studs apart; ids step 6 per row toward the back.
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
	local function stand(at: Vector3, facingDir: Vector3)
		local p = Vector3.new(at.X, y, at.Z)
		assert(player.Character):PivotTo(CFrame.lookAt(p, p + facingDir))
		task.wait(0.3)
	end
	-- 3 studs in front of the first row, facing away from the field: aim decides, not facing.
	local spot = pos("1_3") - back * 3
	stand(spot, -back)
	ripen()
	profile.rawCorn.Normal = 0
	local r1 = Harvest.swing(player, "CornLasso", pos("1_27"))
	local gone = cutIds()
	-- Its neighbours 1_21, 1_26 and 1_28 are all 5 studs away (1_33 is past reach); which one wins
	-- the tie depends on float noise in the turned plot, so any of the three counts.
	local second = if #gone == 2 then (if gone[1] == "1_27" then gone[2] else gone[1]) else ""
	check("a throw 23 studs into the field takes the aimed stalk and one neighbour", r1.ok and r1.amount == 2
		and table.find(gone, "1_27") ~= nil and (second == "1_21" or second == "1_26" or second == "1_28"),
		r1.reason .. " " .. tostring(r1.amount) .. " gone " .. table.concat(gone, ","))
	check("the reply lists the aimed stalk first", r1.targets ~= nil and #(r1.targets :: { Vector3 }) == 2
		and ((r1.targets :: { Vector3 })[1] - pos("1_27")).Magnitude < 0.01)
	local r2 = Harvest.swing(player, "CornLasso", pos("1_28"))
	check("an immediate second throw is refused", not r2.ok and r2.reason == "Too fast")
	ripen()
	task.wait(0.25) -- 0.15 s early: inside the half-cooldown (0.2 s) jitter allowance.
	local r3 = Harvest.swing(player, "CornLasso", pos("1_28"))
	check("a slightly early throw (jitter) is accepted", r3.ok and r3.amount == 2, r3.reason)
	local r4 = Harvest.swing(player, "CornLasso", pos("1_28"))
	check("but the allowance is not a free extra throw", not r4.ok and r4.reason == "Too fast")

	-- Refusals: nothing ripe under the aim, off any stalk, beyond reach plus slack.
	ripen()
	task.wait(0.45)
	plot.stalks["1_27"].growthStartedAt = now()
	local r5 = Harvest.swing(player, "CornLasso", pos("1_27"))
	check("an unripe aimed stalk takes nothing (not even its ripe neighbours)", not r5.ok and r5.reason == "Aim at ripe corn in range"
		and #cutIds() == 1, r5.reason)
	ripen()
	task.wait(0.45)
	local r6 = Harvest.swing(player, "CornLasso", pos("1_27") + (pos("1_28") - pos("1_27")).Unit * 1.5)
	check("an aim 1.5 studs off a stalk snaps to it", r6.ok and table.find(cutIds(), "1_27") ~= nil, r6.reason)
	ripen()
	task.wait(0.45)
	local r7 = Harvest.swing(player, "CornLasso", pos("1_27") + Vector3.new(0, 0, 0) + back * 2.6 + (pos("1_28") - pos("1_27")).Unit * 2.6)
	check("an aim well off every stalk takes nothing", not r7.ok and #cutIds() == 0, r7.reason)
	-- Step back so 1_33 (row 5, 25 studs behind row 0) is 25 + 3 = 28 away: past reach and slack.
	task.wait(0.45)
	local r8 = Harvest.swing(player, "CornLasso", pos("1_33"))
	check("a stalk 28 studs away is out of range", not r8.ok and #cutIds() == 0, r8.reason)
	stand(pos("1_3") - back * 1.5, -back)
	task.wait(0.45)
	local r9 = Harvest.swing(player, "CornLasso", pos("1_33"))
	check("26.5 studs is within the server's lag slack", r9.ok and table.find(cutIds(), "1_33") ~= nil, r9.reason)
	ripen()
	task.wait(0.45)
	stand(spot, back)
	local r10 = Harvest.swing(player, "CornLasso", "1_27")
	check("a junk aim is ignored: the nearest ripe stalk ahead instead", r10.ok and table.find(cutIds(), "1_3") ~= nil, r10.reason)

	-- Through the remote's server path (ToolService.swing): the held tool and the aim.
	ripen()
	task.wait(0.45)
	Tools.swing(player, "CornLasso", pos("1_16"))
	task.wait(0.1)
	check("the ToolSwing path harvests the aimed stalk", table.find(cutIds(), "1_16") ~= nil, table.concat(cutIds(), ","))

	-- Leave the player ready for a visual check: in front of the field facing it, corn kept ripe.
	stand(spot, back)
	ripen()
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	task.spawn(function()
		local untilAt = os.clock() + 120
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
print("[CornLasso tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
