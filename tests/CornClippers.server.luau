--!strict
-- Play runner for the Corn Clippers (Common, SingleTarget): config, targeting, the model and its
-- jaw joint, the purchase, single-stalk snips, the 0.12 s cadence with its jitter allowance,
-- reach, and a rate bound under spam. At the end it sets the player up for the client half
-- (CornClippersVisuals.client.luau): clippers owned, Plot 1 ripe, standing facing row 1.
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
	local clippers = Config.Tools.CornClippers
	check("config matches the catalog", clippers ~= nil and clippers.rarity == "Common" and clippers.behavior == "SingleTarget"
		and clippers.maxTargets == 1 and clippers.cooldownSeconds == 0.12 and clippers.reach == 8 and clippers.yieldMultiplier == 1)
	check("shorter reach than hands, faster than hands", clippers.reach < Config.Manual.range and clippers.cooldownSeconds < Config.Manual.cooldownSeconds)

	-- Targeting: the one nearest ripe stalk inside a 90 degree cone, within 8 studs.
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), {
		c("far", 0, 7.9), c("mid", 0.5, 4), c("near", 1, 2.5), c("tooFar", 0, 8.4), c("side", 3, 2.6), c("behind", 0, -1),
	}, clippers)
	check("one target: the nearest inside the cone", #picked == 1 and picked[1] == "near", table.concat(picked, ","))
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), { c("side", 3, 2.6), c("tooFar", 0, 8.4) }, clippers)
	check("nothing outside the 45 degree half-cone or past 8 studs", #picked == 0, table.concat(picked, ","))

	-- Model: built (Blender template if imported, else the part-built one) with the jaw joint.
	local look = assert(ToolPresentation.get("CornClippers"))
	local tool = ToolModels.build("CornClippers")
	-- lihfolk-ignore: findfirstchild-chain (nil-guarded below, inside pcall)
	local handle = tool:FindFirstChild("Handle") :: BasePart
	-- lihfolk-ignore: findfirstchild-chain (guarded by `and`)
	local jawMotor = handle and handle:FindFirstChild("Jaw") :: Motor6D?
	-- lihfolk-ignore: findfirstchild-chain (guarded by `and`)
	local springMotor = handle and handle:FindFirstChild("Spring") :: Motor6D?
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Common" and tool:GetAttribute("ModelSource") ~= nil, tostring(tool:GetAttribute("ModelSource")))
	check("jaw and spring are Motor6Ds from the handle", jawMotor ~= nil and jawMotor:IsA("Motor6D") and (jawMotor :: Motor6D).Part1 ~= nil
		and (jawMotor :: Motor6D).Part1.Name == "ClippersJaw" and springMotor ~= nil and (springMotor :: Motor6D).Part1.Name == "ClippersSpring")
	-- lihfolk-ignore: findfirstchild-chain (nil-guarded below, inside pcall)
	local jawGrip = tool:FindFirstChild("ClippersJawGrip") :: BasePart
	-- lihfolk-ignore: findfirstchild-chain (guarded by `and`)
	local gripWeld = jawGrip and jawGrip:FindFirstChildOfClass("WeldConstraint")
	check("upper handle rides on the jaw", gripWeld ~= nil and (gripWeld :: WeldConstraint).Part0 ~= nil and (gripWeld :: WeldConstraint).Part0.Name == "ClippersJaw")
	check("blade tip point exists", handle ~= nil and handle:FindFirstChild("BladeTip") ~= nil)
	-- Closing direction: the snip pose (Jaw = Swing key) must swing the hook toward the blade
	-- side (+Z of the tool frame) and the upper handle down toward the lower one (-Z).
	if jawMotor then
		local motor = jawMotor :: Motor6D
		local jaw = motor.Part1 :: BasePart
		-- The tool frame, recovered from the Grip (both builders set Grip = frameLocal * grip).
		local frame = handle.CFrame * tool.Grip * look.model.grip:Inverse()
		local closeDeg = look.clips.Swing.keys[2].pose.Jaw[2]
		local function placed(transform: CFrame): CFrame
			return handle.CFrame * motor.C0 * transform * motor.C1:Inverse()
		end
		local jawOpen = placed(CFrame.identity)
		local jawShut = placed(CFrame.Angles(0, math.rad(closeDeg), 0))
		local hookTip = frame:PointToObjectSpace(jaw.Position) -- hook body centre, in front of the pivot
		local pivot = look.model.joints and look.model.joints.ClippersJaw.pivot or Vector3.zero
		local tipShut = frame:PointToObjectSpace(jawShut:PointToWorldSpace(jawOpen:PointToObjectSpace(jaw.Position)))
		local gripPoint = frame:PointToObjectSpace(jawGrip.Position)
		local gripShut = frame:PointToObjectSpace(jawShut:PointToWorldSpace(jawOpen:PointToObjectSpace(jawGrip.Position)))
		check("snip closes: hook rises toward the blade", hookTip.X > pivot.X and tipShut.Z > hookTip.Z, string.format("hook z %.3f -> %.3f", hookTip.Z, tipShut.Z))
		check("snip closes: upper handle comes down", gripPoint.X < pivot.X and gripShut.Z < gripPoint.Z, string.format("grip z %.3f -> %.3f", gripPoint.Z, gripShut.Z))
	end
	tool:Destroy()

	-- Buying through the Shop path.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.CornClippers then Tools.revoke(player, "CornClippers") end
	profile.cash = clippers.price + 5
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "CornClippers"))
	check("shop buy charges the price once", bought.ok and profile.cash == 5 and profile.ownedTools.CornClippers == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "CornClippers")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "CornClippers" end, 2))
	local held = assert(player.Character):FindFirstChildOfClass("Tool")
	check("the held tool is the clippers with a Jaw motor", held ~= nil and held:GetAttribute("ToolId") == "CornClippers"
		and (held :: Tool):FindFirstChild("Jaw", true) ~= nil)

	-- Snipping from the cross path, facing row 1.
	local field = profile.fields.Plot1
	local crop = Config.Crops[field.cropId]
	local function ripen(cycles: number)
		local at = now()
		for _, stalk in field.stalks do stalk.growthStartedAt = at - cycles * crop.growthSeconds end
	end
	local function cutCount(): number
		local n = 0
		for id in field.stalks do if Growth.yields(field.stalks[id].growthStartedAt, now(), crop) < 1 then n += 1 end end
		return n
	end
	local a = assert(Farms.target(player.UserId, "Plot1", "1_3")).Position
	local b = assert(Farms.target(player.UserId, "Plot1", "1_4")).Position
	local inward = (assert(Farms.target(player.UserId, "Plot1", "1_9")).Position - a) * Vector3.new(1, 0, 1)
	local spot = (a + b) / 2 - inward.Unit * 2.5
	local y = root().Position.Y
	assert(player.Character):PivotTo(CFrame.lookAt(Vector3.new(spot.X, y, spot.Z), Vector3.new(spot.X, y, spot.Z) + inward))
	task.wait(0.3)
	ripen(1)
	profile.rawCorn.Normal = 0
	task.wait(0.2)
	local r1 = Harvest.swing(player, "CornClippers")
	check("a snip cuts exactly one stalk", r1.ok and r1.amount == 1 and #(r1.targets or {}) == 1 and cutCount() == 1 and profile.rawCorn.Normal == 1,
		r1.reason .. " " .. tostring(r1.amount))
	local r2 = Harvest.swing(player, "CornClippers")
	check("an immediate second snip is refused", not r2.ok and r2.reason == "Too fast" and profile.rawCorn.Normal == 1)
	task.wait(0.075) -- Early by ~0.045 s (network jitter): inside the half-cooldown allowance.
	local r3 = Harvest.swing(player, "CornClippers")
	check("a slightly early snip (jitter) is accepted", r3.ok and r3.amount == 1 and profile.rawCorn.Normal == 2, r3.reason)
	local r4 = Harvest.swing(player, "CornClippers")
	check("but the allowance is not a free extra snip", not r4.ok and r4.reason == "Too fast")

	-- Spam for 1.2 s: never more than one snip per cooldown (plus the allowance). Counts
	-- snips that passed the cadence gate, whether or not corn was left in reach.
	ripen(3)
	profile.rawCorn.Normal = 0
	task.wait(0.25)
	local accepted, startedAt = 0, os.clock()
	while os.clock() - startedAt < 1.2 do
		if Harvest.swing(player, "CornClippers").reason ~= "Too fast" then accepted += 1 end
		task.wait()
	end
	local bound = math.floor(1.2 / clippers.cooldownSeconds) + 2
	check("spamming is capped by the cadence", accepted >= 7 and accepted <= bound, string.format("%d accepted (bound %d)", accepted, bound))

	-- Out of reach: 9 studs back from the nearest stalk, nothing is cut.
	task.wait(0.3)
	local nearest = math.huge
	for _, part in Farms.stalkParts(player.UserId) do
		nearest = math.min(nearest, ((part.Position - root().Position) * Vector3.new(1, 0, 1)).Magnitude)
	end
	assert(player.Character):PivotTo(assert(player.Character):GetPivot() - inward.Unit * (clippers.reach + 1.5 - math.min(nearest, 2.5)))
	task.wait(0.3)
	local before = profile.rawCorn.Normal
	local far = Harvest.swing(player, "CornClippers")
	check("out of reach cuts nothing", not far.ok and profile.rawCorn.Normal == before, far.reason)

	-- Leave the player ready for the client half.
	assert(player.Character):PivotTo(CFrame.lookAt(Vector3.new(spot.X, y, spot.Z), Vector3.new(spot.X, y, spot.Z) + inward))
	ripen(1)
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	player:SetAttribute("RawCorn", 0)
	task.wait(Config.Shop.requestCooldownSeconds)
	Tools.request(player, "Equip", "Manual")
	-- Standing still, only ~4 stalks are in reach: keep Plot 1 ripe while the client snips.
	task.spawn(function()
		local untilAt = os.clock() + 25
		while os.clock() < untilAt do
			ripen(1)
			task.wait(0.05)
		end
	end)
end)

local passed = ok
for _, c in checks do if not c.passed then passed = false end end
script:SetAttribute("Results", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
player:SetAttribute("ClippersVisualsReady", ok)
print("[CornClippers tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
