--!strict
-- Play runner for the Twin Sickles (Uncommon, alternating ArcSweep with Combo Sweep): config,
-- the side-turned arcs and the 360 degree combo arc, the hand/streak state machine (hits, a
-- miss, the window running out), the mirrored left hold, the model (handle, welded blade and
-- pommel, trail, points), the Shop purchase, the left-hand copy appearing on equip and going on
-- unequip, and real swings in the field: right, left, then a combo that cuts corn behind the
-- player. At the end it leaves the player holding the sickles among ripe corn for a visual check.
-- Install at ServerScriptService.PopcornTestRunners (never in the synced folder); start Play,
-- read the Results attribute, stop, delete the folder.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local ToolRules = require(Shared.ToolRules)
local ToolPresentation = require(Shared.ToolPresentation)
local Types = require(Shared.Types)
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
local function near(a: Vector3, b: Vector3): boolean return (a - b).Magnitude < 1e-3 end

local ok, err = pcall(function()
	local twin = Config.Tools.TwinSickles
	check("config matches the catalog", twin ~= nil and twin.rarity == "Uncommon" and twin.behavior == "ArcSweep"
		and twin.maxTargets == 4 and twin.cooldownSeconds == 0.55 and twin.reach == 10 and twin.yieldMultiplier == 1
		and twin.combo ~= nil and (twin.combo :: Types.ToolCombo).every == 3)
	check("config validates", (pcall(Config.validate)))

	-- Arcs. Facing +Z: the character's right is -X (Roblox right = look x up).
	local facing = Vector3.new(0, 0, 1)
	local rightSide = facing:Cross(Vector3.yAxis)
	local function at(deg: number, dist: number): Vector3
		-- deg > 0 is toward the character's right.
		local a = math.rad(deg)
		return facing * math.cos(a) * dist + rightSide * math.sin(a) * dist + Vector3.new(0, 7, 0)
	end
	local c = function(id: string, deg: number, dist: number) return { id = id, position = at(deg, dist) } end
	local ring = { c("r80", 80, 6), c("r40", 40, 6), c("ahead", 0, 6), c("l20", -20, 6.5), c("l40", -40, 6), c("l80", -80, 6),
		c("back", 180, 5), c("far", 0, 10.5) }
	local function set(list: { string }): { [string]: boolean }
		local s = {}
		for _, id in list do s[id] = true end
		return s
	end
	local right = set(ToolRules.pickTargets(Vector3.zero, facing, ring, twin, { hand = "Right", combo = false }))
	check("right hand's arc leans right", right.r80 and right.r40 and right.ahead and right.l20 and not right.l40 and not right.l80 and not right.back,
		Http:JSONEncode(right))
	local left = set(ToolRules.pickTargets(Vector3.zero, facing, ring, twin, { hand = "Left", combo = false }))
	check("left hand's arc leans left", left.l80 and left.l40 and left.ahead and left.l20 and not left.r80 and not left.back,
		Http:JSONEncode(left))
	local comboPick = ToolRules.pickTargets(Vector3.zero, facing, ring, twin, { hand = "Right", combo = true })
	local combo = set(comboPick)
	check("combo arc is a full circle, 4 nearest, same reach", #comboPick == 4 and combo.back and not combo.far, table.concat(comboPick, ","))

	-- State machine: hands alternate every swing; every 3rd successful swing in a row is a combo.
	local s = ToolRules.newCombo()
	local seen: { string } = {}
	local clock = 100
	for i = 1, 7 do
		local shape = ToolRules.nextSwing(twin, s, clock)
		table.insert(seen, shape.hand:sub(1, 1) .. (if shape.combo then "*" else ""))
		ToolRules.afterSwing(twin, s, shape, true, clock)
		clock += 0.6
	end
	check("R, L, combo, then again", table.concat(seen, " ") == "R L R* L R L* R", table.concat(seen, " "))
	s = ToolRules.newCombo()
	ToolRules.afterSwing(twin, s, ToolRules.nextSwing(twin, s, 0), true, 0)
	ToolRules.afterSwing(twin, s, ToolRules.nextSwing(twin, s, 0.6), false, 0.6)
	ToolRules.afterSwing(twin, s, ToolRules.nextSwing(twin, s, 1.2), true, 1.2)
	check("a miss ends the streak", not ToolRules.nextSwing(twin, s, 1.8).combo and s.streak == 1)
	s = ToolRules.newCombo()
	ToolRules.afterSwing(twin, s, ToolRules.nextSwing(twin, s, 0), true, 0)
	ToolRules.afterSwing(twin, s, ToolRules.nextSwing(twin, s, 0.6), true, 0.6)
	check("combo is ready inside the window", ToolRules.nextSwing(twin, s, 2.1).combo)
	check("but not after a pause", not ToolRules.nextSwing(twin, s, 2.3).combo)

	-- Holds: the left one is the right one mirrored, with the face flipped (same mesh turned).
	local look = assert(ToolPresentation.get("TwinSickles"))
	local offhand = assert(look.model.offhand)
	local r, l = look.model.grip:Inverse(), offhand.grip:Inverse()
	local function mirror(v: Vector3): Vector3 return Vector3.new(-v.X, v.Y, v.Z) end
	check("left hold mirrors the right", near(l.XVector, mirror(r.XVector)) and near(l.ZVector, mirror(r.ZVector))
		and near(l.YVector, -mirror(r.YVector)))
	check("combo clip fits the cooldown", look.clips.Combo ~= nil and look.clips.Combo.seconds <= twin.cooldownSeconds
		and look.clips.SwingAlt ~= nil and look.vfx.combo ~= nil)

	-- Model: Blender template if imported, else the part-built one.
	local tool = ToolModels.build("TwinSickles")
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local blade = tool:FindFirstChild("TwinBlade") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local pommel = tool:FindFirstChild("TwinPommel") :: BasePart?
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Uncommon" and tool:GetAttribute("ModelSource") ~= nil,
		tostring(tool:GetAttribute("ModelSource")))
	local bladeWeld = blade and blade:FindFirstChildOfClass("WeldConstraint")
	local pommelWeld = pommel and pommel:FindFirstChildOfClass("WeldConstraint")
	check("blade and pommel welded to the handle", handle ~= nil and bladeWeld ~= nil and (bladeWeld :: WeldConstraint).Part0 == handle
		and pommelWeld ~= nil and (pommelWeld :: WeldConstraint).Part0 == handle)
	check("trail and points on the handle", handle ~= nil and (handle :: BasePart):FindFirstChild("SwingTrail") ~= nil
		and (handle :: BasePart):FindFirstChild("BladeCrown") ~= nil and (handle :: BasePart):FindFirstChild("BladeTip") ~= nil)
	if handle then
		local frame = (handle :: BasePart).CFrame * tool.Grip * look.model.grip:Inverse()
		local crown = (handle :: BasePart):FindFirstChild("BladeCrown")
		local crownAt = if crown and crown:IsA("Attachment") then frame:PointToObjectSpace(crown.WorldPosition) else Vector3.zero
		check("crescent top ahead of the hand and to its side", math.abs(crownAt.X - 1.008) < 0.05 and math.abs(crownAt.Z - 1.799) < 0.05,
			string.format("%.2f, %.2f, %.2f", crownAt.X, crownAt.Y, crownAt.Z))
		if tool:GetAttribute("ModelSource") == "Blender" then
			check("Blender materials", (handle :: BasePart).Material == Enum.Material.Wood and blade ~= nil
				and (blade :: BasePart).Material == Enum.Material.Metal)
			-- The real blade mesh must sit where the build put it: its centre inside the crescent.
			local bladeAt = frame:PointToObjectSpace((blade :: BasePart).Position)
			check("blade mesh centre inside the crescent", math.abs(bladeAt.X - 1.05) < 0.1 and math.abs(bladeAt.Z - 0.79) < 0.1 and math.abs(bladeAt.Y) < 0.05,
				string.format("%.2f, %.2f, %.2f", bladeAt.X, bladeAt.Y, bladeAt.Z))
		end
	end
	tool:Destroy()

	-- Buying through the Shop path, and the left-hand copy.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.TwinSickles then Tools.revoke(player, "TwinSickles") end
	profile.cash = twin.price + 9
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "TwinSickles"))
	check("shop buy charges the price once", bought.ok and profile.cash == 9 and profile.ownedTools.TwinSickles == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "TwinSickles")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "TwinSickles" end, 2))
	local character = assert(player.Character)
	check("a left-hand copy appears", waitFor(function() return character:FindFirstChild("Offhand") ~= nil end, 2))
	local copy = character:FindFirstChild("Offhand")
	-- lihfolk-ignore: findfirstchild-chain (guarded by `and`)
	local grip = copy and copy:FindFirstChild("LeftGrip", true) :: Weld?
	check("welded to the left hand", grip ~= nil and grip:IsA("Weld") and (grip :: Weld).Part0 == character:FindFirstChild("LeftHand"))
	local copyTrail = copy and copy:FindFirstChild("SwingTrail", true)
	check("left trail is green", copyTrail ~= nil and copyTrail:IsA("Trail")
		and (copyTrail :: Trail).Color.Keypoints[1].Value == offhand.trailColors[1])
	task.wait(Config.Shop.requestCooldownSeconds)
	Tools.request(player, "Equip", "Manual")
	check("unequip removes the copy", waitFor(function() return character:FindFirstChild("Offhand") == nil end, 2))
	task.wait(Config.Shop.requestCooldownSeconds)
	Tools.request(player, "Equip", "TwinSickles")
	check("re-equip brings exactly one copy back", waitFor(function() return character:FindFirstChild("Offhand") ~= nil end, 2)
		and #(function() local n = {} for _, ch in character:GetChildren() do if ch.Name == "Offhand" then table.insert(n, ch) end end return n end)() == 1)

	-- In the field: stand on column 3 of Plot 1 between rows 2 and 3, facing down the column.
	local field = profile.fields.Plot1
	local crop = Config.Crops[field.cropId]
	local function ripenWhere(filter: (Vector3) -> boolean)
		local t = now()
		for id, stalk in field.stalks do
			local part = Farms.target(player.UserId, "Plot1", id)
			stalk.growthStartedAt = if part and filter(part.Position) then t - crop.growthSeconds else t
		end
	end
	local a = assert(Farms.target(player.UserId, "Plot1", "1_9")).Position
	local b = assert(Farms.target(player.UserId, "Plot1", "1_15")).Position
	local along = ((b - a) * Vector3.new(1, 0, 1)).Unit
	local spot = (a + b) / 2
	local y = root().Position.Y
	local stand = CFrame.lookAt(Vector3.new(spot.X, y, spot.Z), Vector3.new(spot.X, y, spot.Z) + along)
	character:PivotTo(stand)
	task.wait(0.4)
	local function side(position: Vector3): number
		-- Degrees from facing, positive toward the character's right.
		local flat = (position - root().Position) * Vector3.new(1, 0, 1)
		local cf = root().CFrame
		return math.deg(math.atan2(flat:Dot(cf.RightVector), flat:Dot(cf.LookVector)))
	end
	local function angles(response: Types.HarvestResult): string
		local list = {}
		for _, p in response.targets or {} do table.insert(list, string.format("%.0f", side(p))) end
		return table.concat(list, ",")
	end
	local function within(response: Types.HarvestResult, lo: number, hi: number): boolean
		for _, p in response.targets or {} do
			local deg = side(p)
			if deg < lo - 1 or deg > hi + 1 then return false end
		end
		return true
	end
	profile.rawCorn.Normal = 0
	ripenWhere(function() return true end)
	task.wait(0.6)
	local r1 = Harvest.swing(player, "TwinSickles")
	check("1st swing: right hand, 4 stalks in the right arc", r1.ok and r1.hand == "Right" and r1.combo == false and #(r1.targets or {}) == 4
		and within(r1, -25, 85) and r1.streak == 1, r1.reason .. " " .. angles(r1))
	local tooSoon = Harvest.swing(player, "TwinSickles")
	check("an immediate repeat is refused", not tooSoon.ok and tooSoon.reason == "Too fast" and tooSoon.hand == nil)
	ripenWhere(function() return true end)
	task.wait(0.6)
	local r2 = Harvest.swing(player, "TwinSickles")
	check("2nd swing: left hand, 4 stalks in the left arc", r2.ok and r2.hand == "Left" and r2.combo == false and #(r2.targets or {}) == 4
		and within(r2, -85, 25) and r2.streak == 2, r2.reason .. " " .. angles(r2))
	-- Only corn behind the player is ripe: the combo's full circle must still find it.
	ripenWhere(function(p) return (p - root().Position):Dot(root().CFrame.LookVector) < -1 end)
	task.wait(0.6)
	local r3 = Harvest.swing(player, "TwinSickles")
	local behind = true
	for _, p in r3.targets or {} do if math.abs(side(p)) < 100 then behind = false end end
	check("3rd swing: Combo Sweep cuts corn behind", r3.ok and r3.combo == true and #(r3.targets or {}) >= 2 and behind and r3.streak == 0,
		r3.reason .. " " .. angles(r3))
	ripenWhere(function() return true end)
	task.wait(0.6)
	local r4 = Harvest.swing(player, "TwinSickles")
	check("then the count starts again", r4.ok and r4.combo == false and r4.hand == "Left" and r4.streak == 1, r4.reason)
	-- A miss (nothing ripe) ends the streak, so the next hit is not a combo.
	ripenWhere(function() return false end)
	task.wait(0.6)
	local miss = Harvest.swing(player, "TwinSickles")
	check("a miss reports and resets the streak", not miss.ok and miss.hand == "Right" and miss.streak == 0, miss.reason)
	ripenWhere(function() return true end)
	task.wait(0.6)
	local r5 = Harvest.swing(player, "TwinSickles")
	check("no combo straight after a miss", r5.ok and r5.combo == false and r5.streak == 1)

	-- Leave the player holding the sickles among ripe corn for a visual check.
	character:PivotTo(stand)
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	player:SetAttribute("RawCorn", 0)
	task.spawn(function()
		local untilAt = os.clock() + 90
		while os.clock() < untilAt do
			ripenWhere(function() return true end)
			task.wait(0.5)
		end
	end)
end)

local passed = ok
for _, c in checks do if not c.passed then passed = false end end
script:SetAttribute("Results", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
print("[TwinSickles tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
