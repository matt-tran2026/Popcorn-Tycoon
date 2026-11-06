--!strict
-- Play runner for the Long Scythe (Uncommon, ArcSweep with a 180 degree Great Harvest): config,
-- the half-circle targeting rule (sides in, behind out, 15-stud reach, 6 nearest), the model
-- (template or part-built, pack-style SmoothPlastic, blade welded, trail and points), the
-- presentation (two-handed hold joints, Sweep/Hit markers, wind trail), the purchase, a sweep
-- from the middle of the field that cuts 6 stalks across more than one row, and the slow
-- 1.1 s cadence with its jitter allowance. At the end it leaves the player holding the scythe in
-- the middle of Plot 1 with the corn kept ripe, for a visual check of the sweep.
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
	local scythe = Config.Tools.LongScythe
	check("config matches the catalog", scythe ~= nil and scythe.rarity == "Uncommon" and scythe.behavior == "ArcSweep"
		and scythe.maxTargets == 6 and scythe.cooldownSeconds == 1.1 and scythe.reach == 15 and scythe.arcDegrees == 180
		and scythe.yieldMultiplier == 1 and scythe.sideDegrees == nil and scythe.combo == nil)
	check("slowest swing of the shipped tools", (function()
		for id, tool in Config.Tools do
			if id ~= "LongScythe" and tool.cooldownSeconds >= scythe.cooldownSeconds then return false end
		end
		return true
	end)())

	-- Half-circle rule: everything in front and to both sides within 15 studs, nothing behind.
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), {
		c("left", -9, 0.2), c("right", 9, 0.2), c("ahead", 0, 14.5), c("far", 0, 15.3), c("behind", 0, -3),
		c("backLeft", -6, -1),
	}, scythe)
	table.sort(picked)
	check("sides and the far front are in, behind and past 15 are out", table.concat(picked, ",") == "ahead,left,right",
		table.concat(picked, ","))
	local many = {}
	for i = 1, 10 do table.insert(many, c("s" .. i, (i - 5.5) * 2, 3 + i * 0.1)) end
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), many, scythe)
	check("at most 6, nearest first", #picked == 6 and picked[1] == "s5", table.concat(picked, ","))

	-- Presentation: two hands, the heavy clip's markers, the wind trail.
	local look = assert(ToolPresentation.get("LongScythe"))
	local swingClip = look.clips.Swing
	check("swing clip is the full swing with Sweep before Hit", swingClip.seconds == scythe.swingSeconds
		and swingClip.markers ~= nil and (swingClip.markers :: any).Sweep < (swingClip.markers :: any).Hit)
	check("the left arm is held for two hands", look.holdJoints ~= nil and table.find(look.holdJoints :: { string }, "LeftShoulder") ~= nil)
	local wind = look.vfx.wind
	check("wind trail sweeps a half circle out toward the reach", wind ~= nil and (wind :: any).degrees == 180
		and (wind :: any).radii[#(wind :: any).radii] <= scythe.reach)

	-- Model: Blender template if imported, else the part-built one.
	local tool = ToolModels.build("LongScythe")
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local blade = tool:FindFirstChild("LongScytheBlade") :: BasePart?
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Uncommon" and tool:GetAttribute("ModelSource") ~= nil,
		tostring(tool:GetAttribute("ModelSource")))
	check("handle and blade present", handle ~= nil and blade ~= nil)
	local plastic = true
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 and part.Material ~= Enum.Material.SmoothPlastic then plastic = false end
	end
	check("pack style: every visible part is SmoothPlastic", plastic)
	check("trail and points on the handle", handle ~= nil and (handle :: BasePart):FindFirstChild("SwingTrail") ~= nil
		and (handle :: BasePart):FindFirstChild("BladeTip") ~= nil and (handle :: BasePart):FindFirstChild("BladeRoot") ~= nil)
	if handle and blade then
		local frame = (handle :: BasePart).CFrame * tool.Grip * look.model.grip:Inverse()
		local tipAttachment = (handle :: BasePart):FindFirstChild("BladeTip")
		local tip = if tipAttachment and tipAttachment:IsA("Attachment") then tipAttachment.WorldPosition else (handle :: BasePart).Position
		local tipAt = frame:PointToObjectSpace(tip)
		check("blade tip out to the side, well up the shaft", tipAt.X > 2.6 and tipAt.X < 4 and tipAt.Z > 3 and math.abs(tipAt.Y) < 0.4,
			string.format("%.2f, %.2f, %.2f", tipAt.X, tipAt.Y, tipAt.Z))
		local shaftAt = frame:PointToObjectSpace((handle :: BasePart).Position)
		check("grip sits on the shaft, 2 studs behind its centre", math.abs(shaftAt.X - 2.03) < 0.06 and math.abs(shaftAt.Y) < 0.06
			and math.abs(shaftAt.Z) < 0.06, string.format("%.3f, %.3f, %.3f", shaftAt.X, shaftAt.Y, shaftAt.Z))
		local bladeAt = frame:PointToObjectSpace((blade :: BasePart).Position)
		check("blade mesh sits at the shaft top on the blade side", bladeAt.X > 3.8 and bladeAt.X < 5 and bladeAt.Z > 1.4 and bladeAt.Z < 2.4
			and math.abs(bladeAt.Y) < 0.1, string.format("%.2f, %.2f, %.2f", bladeAt.X, bladeAt.Y, bladeAt.Z))
		check("blade welded to the shaft", (function()
			for _, item in (blade :: BasePart):GetChildren() do
				if item:IsA("WeldConstraint") and (item.Part0 == handle or item.Part1 == handle) then return true end
			end
			return false
		end)())
	end
	tool:Destroy()

	-- Buying through the Shop path.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.LongScythe then Tools.revoke(player, "LongScythe") end
	profile.cash = scythe.price + 9
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "LongScythe"))
	check("shop buy charges the price once", bought.ok and profile.cash == 9 and profile.ownedTools.LongScythe == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "LongScythe")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "LongScythe" end, 2))
	local held = assert(player.Character):FindFirstChildOfClass("Tool")
	check("the held tool is the long scythe", held ~= nil and held:GetAttribute("ToolId") == "LongScythe")

	-- Only swings harvest (creator's spam-click report, Nov 6 2026): a replicated Tool.Activated
	-- (every click, even inside the client's cooldown) cuts nothing, and hand picks are refused
	-- while a swung tool is held. Swings arrive on the ToolSwing remote (ToolService.swing).
	do
		local plot = profile.fields.Plot1
		local rules = Config.Crops[plot.cropId]
		local at = now()
		for _, stalk in plot.stalks do stalk.growthStartedAt = at - rules.growthSeconds end
		profile.rawCorn.Normal = 0
		-- Facing a ripe stalk 2 studs away, so the old Activated path would have cut it.
		local near = assert(Farms.target(player.UserId, "Plot1", "1_1")).Position
		local height = root().Position.Y
		local from = Vector3.new(near.X, height, near.Z - 2)
		assert(player.Character):PivotTo(CFrame.lookAt(from, Vector3.new(near.X, height, near.Z)))
		task.wait(1.2)
		-- (A server-side Tool:Activate() also activates the owner's client, which then plays a real
		-- swing and sends ToolSwing, so click timing is checked from the client instead: spam
		-- clicks every 0.1 s for 4 s gave 4 visible swings and 4 harvests, docs/testing.)
		Tools.swing(player, "Sickle")
		Tools.swing(player, 42)
		Tools.swing(player, nil)
		check("swing requests for a tool not in hand, or malformed, cut nothing", (profile.rawCorn.Normal or 0) == 0,
			tostring(profile.rawCorn.Normal))
		task.wait(Config.Manual.cooldownSeconds)
		local before = profile.rawCorn.Normal or 0
		local pick = Harvest.attempt(player, player.UserId, "Plot1", "1_1")
		check("no hand picking while a swung tool is held", not pick.ok and pick.reason == "Swing your tool to harvest"
			and (profile.rawCorn.Normal or 0) == before, pick.reason)
		local remote = Shared:FindFirstChild("Remotes") and (Shared :: any).Remotes:FindFirstChild("ToolSwing")
		check("the ToolSwing remote exists", remote ~= nil and remote:IsA("RemoteEvent"))
	end

	-- Great Harvest from the middle of Plot 1 (6 x 6, 5 studs apart), facing toward the back rows.
	local field = profile.fields.Plot1
	local crop = Config.Crops[field.cropId]
	local function ripen(cycles: number)
		local at = now()
		for _, stalk in field.stalks do stalk.growthStartedAt = at - cycles * crop.growthSeconds end
	end
	local function cutIds(): { string }
		local list = {}
		for id, stalk in field.stalks do if Growth.yields(stalk.growthStartedAt, now(), crop) < 1 then table.insert(list, id) end end
		return list
	end
	local a = assert(Farms.target(player.UserId, "Plot1", "1_15")).Position
	local b = assert(Farms.target(player.UserId, "Plot1", "1_22")).Position
	local back = ((assert(Farms.target(player.UserId, "Plot1", "1_33")).Position - assert(Farms.target(player.UserId, "Plot1", "1_3")).Position) * Vector3.new(1, 0, 1)).Unit
	local y = root().Position.Y
	local middle = Vector3.new((a.X + b.X) / 2, y, (a.Z + b.Z) / 2)
	local function stand()
		assert(player.Character):PivotTo(CFrame.lookAt(middle, middle + back))
		task.wait(0.3)
	end
	stand()
	ripen(1)
	profile.rawCorn.Normal = 0
	task.wait(1.2)
	local r1 = Harvest.swing(player, "LongScythe")
	local gone = cutIds()
	check("one sweep cuts 6 stalks", r1.ok and r1.amount == 6 and #(r1.targets or {}) == 6 and #gone == 6,
		r1.reason .. " " .. tostring(r1.amount) .. " gone " .. #gone)
	local rows: { [number]: boolean } = {}
	local rowCount = 0
	for _, id in gone do
		local index = tonumber(string.match(id, "_(%d+)$")) or 0
		local row = (index - 1) // Config.Plot.columns
		if not rows[row] then rows[row] = true; rowCount += 1 end
	end
	check("the sweep spans more than one row", rowCount >= 2, table.concat(gone, ","))
	local forward = 0
	for _, position in r1.targets or {} do
		if ((position - middle) * Vector3.new(1, 0, 1)):Dot(back) > -0.5 then forward += 1 end
	end
	check("nothing behind the player is cut", forward == #(r1.targets or {}))
	local r2 = Harvest.swing(player, "LongScythe")
	check("an immediate second sweep is refused", not r2.ok and r2.reason == "Too fast")
	ripen(1)
	task.wait(0.7) -- 0.4 s early: inside the half-cooldown (0.55 s) jitter allowance.
	local r3 = Harvest.swing(player, "LongScythe")
	check("a slightly early sweep (jitter) is accepted", r3.ok and r3.amount == 6, r3.reason)
	local r4 = Harvest.swing(player, "LongScythe")
	check("but the allowance is not a free extra sweep", not r4.ok and r4.reason == "Too fast")

	-- Leave the player ready for a visual check: holding the scythe in the middle of the field.
	stand()
	ripen(1)
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	player:SetAttribute("RawCorn", 0)
	task.spawn(function()
		local untilAt = os.clock() + 60
		while os.clock() < untilAt do
			ripen(1)
			profile.rawCorn.Normal = 0
			task.wait(0.5)
		end
	end)
end)

local passed = ok
for _, c in checks do if not c.passed then passed = false end end
script:SetAttribute("Results", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
print("[LongScythe tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
