--!strict
-- Play runner for the Weed Whacker (Rare, ContinuousHarvest, Continuous Cutting + Overheat):
-- config, the pure heat rule (7 s to overheat, 3 s lock, cooling 1/3 per second after an early
-- release, restart refused while locked), the target rule (7-stud radius from the root, nearest
-- the head first, one at a time), the presentation (looping Cut clip, Spin/Engine joints, whacker
-- effects, the swirl trail riding the blade), the model (template or part-built: the Spin motor
-- turns the disc in its own plane about the hub, the gauge rides the engine, materials), the
-- purchase, real held cutting in the middle of Plot 1 through ToolService's shared loop (cadence,
-- 7-stud radius, the Tool's heat attributes), release, the overheat lock and restart, refusals
-- (not in hand, swing remote, bag full) and stopping on unequip. At the end it leaves the player
-- holding the whacker in the field with the corn kept ripe, for a visual check. Install at
-- ServerScriptService.PopcornTestRunners (never in the synced folder); start Play, read the
-- Results attribute after about 40 s, stop, delete the folder.
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
local function near(a: number, b: number, eps: number?): boolean return math.abs(a - b) < (eps or 1e-6) end
local function fmt(v: Vector3): string return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z) end
local scratch: { Instance } = {}

local ok, err = pcall(function()
	local whacker = Config.Tools.WeedWhacker
	local spec = assert(whacker.continuous)
	check("config matches the catalog", whacker.rarity == "Rare" and whacker.behavior == "ContinuousHarvest"
		and whacker.maxTargets == 1 and whacker.cooldownSeconds == 0.12 and whacker.reach == 7 and whacker.yieldMultiplier == 1
		and spec.runSeconds == 7 and spec.coolSeconds == 3 and whacker.swingSeconds == nil)

	-- The heat rule, on a made-up clock.
	local h = ToolRules.newHeat()
	check("starts cold and idle", h.heat == 0 and not h.running and select(2, ToolRules.heatAt(whacker, h, 0)) == false)
	check("starting runs the engine", ToolRules.setRunning(whacker, h, true, 100))
	check("half the run time is half the heat", near((ToolRules.heatAt(whacker, h, 103.5)), 0.5))
	check("no overheat before 7 s", not ToolRules.settleHeat(whacker, h, 106.9) and h.running)
	local heatAt7, lockedAt7 = ToolRules.heatAt(whacker, h, 107.2)
	check("past 7 s it reads as overheated", lockedAt7 and heatAt7 < 1 and heatAt7 > 0.9, tostring(heatAt7))
	check("settling stops it at the 7 s mark with a 3 s lock", ToolRules.settleHeat(whacker, h, 107.2) and not h.running
		and near(h.at, 107) and near(h.overheatUntil, 110))
	check("it cools to half in 1.5 s", near((ToolRules.heatAt(whacker, h, 108.5)), 0.5))
	check("restart refused while locked", not ToolRules.setRunning(whacker, h, true, 109.9))
	check("restart allowed once cooled", ToolRules.setRunning(whacker, h, true, 110.05) and near((ToolRules.heatAt(whacker, h, 110.05)), 0, 1e-3))
	local e = ToolRules.newHeat()
	ToolRules.setRunning(whacker, e, true, 0)
	ToolRules.setRunning(whacker, e, false, 3.5)
	check("letting go early cools at 1/3 per second", near((ToolRules.heatAt(whacker, e, 4.25)), 0.25) and near((ToolRules.heatAt(whacker, e, 6)), 0))
	-- Bursts of 2 s on, 1 s off for a minute: +2/7 heat, then -1/3, so it never builds up.
	local b = ToolRules.newHeat()
	local peak, everLocked = 0, false
	for k = 0, 19 do
		ToolRules.setRunning(whacker, b, true, k * 3)
		local hot, locked = ToolRules.heatAt(whacker, b, k * 3 + 2)
		peak, everLocked = math.max(peak, hot), everLocked or locked
		ToolRules.setRunning(whacker, b, false, k * 3 + 2)
	end
	check("2 s bursts with 1 s pauses never lock", not everLocked and peak < 0.5, string.format("%.3f", peak))

	-- The target rule, on a made-up grid 5 studs apart, the player at the origin facing +Z.
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local grid = { c("front", 0, 5), c("frontL", -5, 5), c("side", 5, 0), c("back", 0, -5), c("backFar", 0, -7.5), c("diag", 5, 5) }
	local facing = Vector3.new(0, 0, 1)
	local function pick(list: { any }, face: Vector3?): string
		return table.concat(ToolRules.pickTargets(Vector3.zero, face or facing, list, whacker), ",")
	end
	check("one stalk at a time, the one nearest the head", pick(grid) == "front", pick(grid))
	check("nothing ahead: the head takes the next nearest all round", pick({ c("side", 5, 0), c("back", 0, -5) }) == "side")
	check("behind still counts inside 7 studs", pick({ c("back", 0, -5) }) == "back")
	check("7.5 studs away is out of reach", pick({ c("backFar", 0, -7.5) }) == "" and pick({ c("edge", 0, 7) }) == "edge")
	check("facing picks which goes first", pick(grid, Vector3.new(1, 0, 0)) == "side", pick(grid, Vector3.new(1, 0, 0)))

	-- Presentation.
	local look = assert(ToolPresentation.get("WeedWhacker"))
	local fx = look.vfx.whacker
	check("Cut clip loops; Overheat, Equip and Idle exist", look.clips.Cut ~= nil and look.clips.Cut.loop == true
		and look.clips.Overheat ~= nil and look.clips.Equip ~= nil and look.clips.Idle ~= nil)
	local joints = look.model.joints or {}
	check("blade spins and engine shakes on their own motors", joints.WhackerBlade ~= nil and joints.WhackerBlade.motor == "Spin"
		and joints.WhackerEngine ~= nil and joints.WhackerEngine.motor == "Engine")
	check("whacker effects configured", fx ~= nil and (fx :: any).gaugeMesh == "WhackerHeat" and #(fx :: any).heatColors == 3)

	-- Model: Blender template if imported, else the part-built one.
	local tool = ToolModels.build("WeedWhacker")
	local built = tool:FindFirstChild("Handle")
	if built and built:IsA("BasePart") then built.Anchored = true end
	tool.Parent = workspace
	table.insert(scratch, tool)
	task.wait(0.1)
	local function part(name: string): BasePart?
		local found = tool:FindFirstChild(name)
		return if found and found:IsA("BasePart") then found else nil
	end
	local handle, blade, engine, heat = part("Handle"), part("WhackerBlade"), part("WhackerEngine"), part("WhackerHeat")
	local shaft, loop, guard = part("WhackerShaft"), part("WhackerLoop"), part("WhackerGuard")
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Rare" and tool:GetAttribute("ModelSource") ~= nil,
		tostring(tool:GetAttribute("ModelSource")))
	check("all seven meshes present", handle ~= nil and blade ~= nil and engine ~= nil and heat ~= nil and shaft ~= nil and loop ~= nil and guard ~= nil)
	check("materials: plastic grip, metal shaft and blade, neon gauge", handle ~= nil and shaft ~= nil and blade ~= nil and heat ~= nil
		and (handle :: BasePart).Material == Enum.Material.SmoothPlastic and (shaft :: BasePart).Material == Enum.Material.Metal
		and (blade :: BasePart).Material == Enum.Material.Metal and (heat :: BasePart).Material == Enum.Material.Neon)
	local swirl = tool:FindFirstChild("SwingTrail", true)
	check("swirl trail rides the blade", blade ~= nil and (blade :: BasePart):FindFirstChild("RimOuter") ~= nil
		and swirl ~= nil and swirl.Parent == blade)
	if handle and blade and engine and heat then
		local hp = handle :: BasePart
		local frame = hp.CFrame * tool.Grip * look.model.grip:Inverse()
		local function at(p: Vector3): Vector3 return frame:PointToObjectSpace(p) end
		local hub = at((blade :: BasePart).Position)
		check("disc hub ahead of the grip, under the shaft", (hub - Vector3.new(3.9, -0.44, 0)).Magnitude < 0.15, fmt(hub))
		check("engine behind the grip", at((engine :: BasePart).Position).X < -0.9, fmt(at((engine :: BasePart).Position)))
		check("gauge on the tool's +Z side", at((heat :: BasePart).Position).Z > 0.4, fmt(at((heat :: BasePart).Position)))
		local spin = tool:FindFirstChild("Spin", true)
		local rim = (blade :: BasePart):FindFirstChild("RimOuter")
		check("the Spin motor moves the blade from the handle", spin ~= nil and spin:IsA("Motor6D") and spin.Part0 == hp and spin.Part1 == blade)
		if spin and spin:IsA("Motor6D") and rim and rim:IsA("Attachment") then
			local before = at(rim.WorldPosition)
			spin.Transform = CFrame.Angles(0, math.rad(90), 0)
			task.wait(0.1)
			local after = at(rim.WorldPosition)
			local hubAfter = at((blade :: BasePart).Position)
			check("spinning turns the rim about the hub in the disc's plane", (after - before).Magnitude > 0.8
				and math.abs(after.Y - before.Y) < 0.02 and (hubAfter - hub).Magnitude < 0.02
				and math.abs((after - hub).Magnitude - (before - hub).Magnitude) < 0.02, fmt(before) .. " -> " .. fmt(after))
		end
		local shake = tool:FindFirstChild("Engine", true)
		local gaugeWeld = heat:FindFirstChildOfClass("WeldConstraint")
		check("the Engine motor holds the engine, and the gauge rides it", shake ~= nil and shake:IsA("Motor6D") and shake.Part1 == engine
			and gaugeWeld ~= nil and gaugeWeld.Part0 == engine)
	end
	tool:Destroy()

	-- Buying through the Shop path.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.WeedWhacker then Tools.revoke(player, "WeedWhacker") end
	profile.cash = whacker.price + 7
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "WeedWhacker"))
	check("shop buy charges the price once", bought.ok and profile.cash == 7 and profile.ownedTools.WeedWhacker == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "WeedWhacker")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "WeedWhacker" end, 2))
	local held = assert(assert(player.Character):FindFirstChildOfClass("Tool"), "no tool in hand")
	check("the held tool is the whacker", held ~= nil and held:GetAttribute("ToolId") == "WeedWhacker")
	check("a swing of a held tool is refused", not Harvest.swing(player, "WeedWhacker").ok)

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
	-- In the middle of the field, between four stalks, facing the back.
	local centre = (pos("1_9") + pos("1_10") + pos("1_15") + pos("1_16")) / 4
	stand(centre, back)
	ripen()
	profile.rawCorn.Normal = 0
	Tools.hold(player, "WeedWhacker", false)
	task.wait(0.2)

	-- Real held cutting through ToolService's loop.
	local started = os.clock()
	Tools.hold(player, "WeedWhacker", true)
	check("holding starts the engine (Tool attribute)", held:GetAttribute("Running") == true)
	task.wait(1.2)
	local cut = cutIds()
	local elapsed = os.clock() - started
	-- Between four stalks on the 5-stud grid only those four are within 7 studs (3.54 away; the
	-- next ring is 7.9 away), so a run cuts exactly those, one at a time.
	check("cuts every ripe stalk in reach, and only those", #cut == 4, tostring(#cut) .. " in " .. string.format("%.2f", elapsed) .. " s")
	local r = root().Position
	local farthest = 0
	for _, id in cut do
		local p = pos(id)
		farthest = math.max(farthest, Vector3.new(p.X - r.X, 0, p.Z - r.Z).Magnitude)
	end
	check("every cut stalk within 7 studs", farthest <= 7.01, string.format("%.2f", farthest))
	check("raw corn credited per stalk", (profile.rawCorn.Normal or 0) == #cutIds() * crop.cornPerYield, tostring(profile.rawCorn.Normal))
	Tools.hold(player, "WeedWhacker", false)
	local stoppedCount = #cutIds()
	task.wait(0.4)
	check("letting go stops cutting", #cutIds() == stoppedCount and held:GetAttribute("Running") == false)
	local heatNow = ToolRules.heatAt(whacker, {
		heat = held:GetAttribute("Heat") :: number, at = held:GetAttribute("HeatAt") :: number, running = false, overheatUntil = 0,
	}, workspace:GetServerTimeNow())
	check("the Tool shows the heat the run built up, cooling", heatNow >= 0 and heatNow < 0.2, string.format("%.3f", heatNow))

	-- Rate cap over a longer run, every stalk ripe again.
	task.wait(1)
	ripen()
	profile.rawCorn.Normal = 0
	local _, coolState = Harvest.cutterOf(player.UserId)
	check("cooled before the long run", coolState ~= nil and (ToolRules.heatAt(whacker, coolState :: any, workspace:GetServerTimeNow())) < 0.01)
	-- Keep everything ripe so the cadence, not the corn, limits the cuts; count them from the corn
	-- credited (each cut is one stalk's cycle).
	local t0 = os.clock()
	Tools.hold(player, "WeedWhacker", true)
	while os.clock() - t0 < 3 do
		ripen()
		task.wait(0.05)
	end
	local _, runState = Harvest.cutterOf(player.UserId)
	local stillRunning = runState ~= nil and (runState :: any).running == true
	Tools.hold(player, "WeedWhacker", false)
	local span = os.clock() - t0
	local cuts = (profile.rawCorn.Normal or 0) // crop.cornPerYield
	local cap = State.bagCapacity(profile) // crop.cornPerYield
	local expected = math.min(math.floor(span / whacker.cooldownSeconds), cap)
	check("about 8 cuts a second for 3 s and never more", cuts >= expected - 3 and cuts <= expected + 1,
		tostring(cuts) .. " cuts in " .. string.format("%.2f", span) .. " s (bag " .. tostring(cap) .. ")")
	check("still running after 3 s (under the 7 s limit)", stillRunning)
	profile.rawCorn.Normal = 0

	-- Overheat: run flat out for 7 s.
	task.wait(3.2)
	ripen()
	profile.rawCorn.Normal = 0
	local runFrom = workspace:GetServerTimeNow()
	Tools.hold(player, "WeedWhacker", true)
	task.wait(7.4)
	check("after 7 s of running it overheats and stops", held:GetAttribute("Running") == false
		and (held:GetAttribute("OverheatUntil") :: number) > workspace:GetServerTimeNow(), tostring(held:GetAttribute("OverheatUntil")))
	local lockEnd = held:GetAttribute("OverheatUntil") :: number
	check("the lock lasts 3 s from the 7 s mark", math.abs(lockEnd - (runFrom + 10)) < 0.25, string.format("%.2f", lockEnd - runFrom))
	local frozen = #cutIds()
	ripen()
	Tools.hold(player, "WeedWhacker", false)
	task.wait(0.1)
	Tools.hold(player, "WeedWhacker", true)
	task.wait(0.4)
	check("no restart and no cuts while locked", held:GetAttribute("Running") == false and #cutIds() == 0, tostring(frozen))
	task.wait(math.max(0, lockEnd - workspace:GetServerTimeNow()) + 0.15)
	Tools.hold(player, "WeedWhacker", true)
	check("restarts once cooled", held:GetAttribute("Running") == true)
	task.wait(0.3)
	check("and cuts again", #cutIds() >= 1)
	Tools.hold(player, "WeedWhacker", false)

	-- Bag full: the engine runs but cuts nothing.
	task.wait(0.3)
	ripen()
	profile.rawCorn.Normal = State.bagCapacity(profile)
	Tools.hold(player, "WeedWhacker", true)
	task.wait(0.5)
	check("a full bag cuts nothing", #cutIds() == 0)
	Tools.hold(player, "WeedWhacker", false)
	profile.rawCorn.Normal = 0

	-- Not in hand: unequipping stops a running engine, and a start without the tool is refused.
	task.wait(0.3)
	Tools.hold(player, "WeedWhacker", true)
	check("running before the unequip", held:GetAttribute("Running") == true)
	assert(Tools.request(player, "Equip", "Manual"))
	check("putting it away stops the engine", waitFor(function() return held:GetAttribute("Running") == false end, 1))
	task.wait(0.1)
	Tools.hold(player, "WeedWhacker", true)
	local _, offState = Harvest.cutterOf(player.UserId)
	check("a start without the tool in hand is refused", offState ~= nil and not (offState :: any).running)
	check("junk requests are ignored", pcall(function()
		Tools.hold(player, "WeedWhacker", "yes" :: any)
		Tools.hold(player, 42 :: any, true)
		Tools.hold(player, "Sickle", true)
	end))

	-- Leave the player ready for a visual check: holding the whacker in the field, corn kept ripe.
	task.wait(Config.Shop.requestCooldownSeconds)
	Tools.request(player, "Equip", "WeedWhacker")
	stand(centre, back)
	ripen()
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	task.spawn(function()
		local untilAt = os.clock() + 180
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
print("[WeedWhacker tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
