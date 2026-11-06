--!strict
-- Play runner for the Harvest Hook (Common, PullHarvest): config, the long forward cone (2
-- nearest, 14 studs, 60 degrees), the model (holder grip, Reach motor, hook and pommel on the
-- grip, trail, named points), the purchase, real swings from 10 studs away (out of the Sickle's
-- reach) and from 14.5 (out of the hook's), the 0.45 s cadence with its jitter allowance, and
-- the pull presentation data. At the end it leaves the player holding the hook 10 studs in front
-- of a ripe column, for a visual check of the Hook Pull.
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
	local hook = Config.Tools.HarvestHook
	check("config matches the catalog", hook ~= nil and hook.rarity == "Common" and hook.behavior == "PullHarvest"
		and hook.maxTargets == 2 and hook.cooldownSeconds == 0.45 and hook.reach == 14 and hook.yieldMultiplier == 1)
	check("swing fits inside the cooldown", (hook.swingSeconds or 0) <= hook.cooldownSeconds)

	-- Cone rule: 60 degrees, 14 studs, the 2 nearest.
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), {
		c("far", 0, 13.5), c("mid", 2, 8), c("near", -1, 4), c("wide", 6, 6), c("behind", 0, -3), c("past", 0, 14.3),
	}, hook)
	check("two nearest in the cone", #picked == 2 and picked[1] == "near" and picked[2] == "mid", table.concat(picked, ","))
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), { c("far", 0, 13.5), c("far2", 3, 12.5), c("wide", 6, 6), c("past", 0, 14.3) }, hook)
	check("reaches stalks 13+ studs away", #picked == 2 and picked[1] == "far2" and picked[2] == "far", table.concat(picked, ","))
	check("the Sickle cannot reach them", #ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), { c("far", 0, 13.5), c("far2", 3, 12.5) }, Config.Tools.Sickle) == 0)
	picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), { c("wide", 6, 6), c("behind", 0, -3), c("past", 0, 14.3) }, hook)
	check("nothing outside 30 degrees, behind or past 14 studs", #picked == 0, table.concat(picked, ","))

	-- Model: Blender template if imported, else the part-built one, both with the holder grip.
	local tool = ToolModels.build("HarvestHook")
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local holder = tool:FindFirstChild("Handle") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local grip = tool:FindFirstChild("HookHandle") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local blade = tool:FindFirstChild("HookBlade") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (optional cast, nil-guarded below)
	local pommel = tool:FindFirstChild("HookPommel") :: BasePart?
	-- lihfolk-ignore: findfirstchild-chain (guarded by `and`)
	local reach = holder and holder:FindFirstChild("Reach") :: Motor6D?
	check("model built with a source and rarity", tool:GetAttribute("Rarity") == "Common" and tool:GetAttribute("ModelSource") ~= nil,
		tostring(tool:GetAttribute("ModelSource")))
	check("hand holds an invisible grip", holder ~= nil and (holder :: BasePart).Transparency == 1)
	check("leather grip slides on the Reach motor", reach ~= nil and (reach :: Motor6D).Part1 == grip)
	local bladeWeld = blade and blade:FindFirstChildOfClass("WeldConstraint")
	local pommelWeld = pommel and pommel:FindFirstChildOfClass("WeldConstraint")
	check("hook and pommel ride on the grip", bladeWeld ~= nil and (bladeWeld :: WeldConstraint).Part0 == grip
		and pommelWeld ~= nil and (pommelWeld :: WeldConstraint).Part0 == grip)
	check("trail and hook points on the grip", grip ~= nil and (grip :: BasePart):FindFirstChild("SwingTrail") ~= nil
		and (grip :: BasePart):FindFirstChild("HookCrown") ~= nil and (grip :: BasePart):FindFirstChild("HookTip") ~= nil)
	if holder and grip and blade then
		local look = assert(ToolPresentation.get("HarvestHook"))
		local frame = (holder :: BasePart).CFrame * tool.Grip * look.model.grip:Inverse()
		-- The crown of the curl is ahead of the hand and off to the curl side (tool Z).
		local crown = (grip :: BasePart):FindFirstChild("HookCrown")
		local crownAt = if crown and crown:IsA("Attachment") then frame:PointToObjectSpace(crown.WorldPosition) else Vector3.zero
		check("curl ahead of the hand and to its side", math.abs(crownAt.X - 2.486) < 0.05 and math.abs(crownAt.Z - 1.574) < 0.05,
			string.format("%.2f, %.2f, %.2f", crownAt.X, crownAt.Y, crownAt.Z))
		local bladeAt = frame:PointToObjectSpace((blade :: BasePart).Position)
		-- (The part-built HookBlade is the straight shank; the Blender mesh's centre is inside the curl.)
		check("hook body ahead of the hand", bladeAt.X > 1 and bladeAt.X < 2.6 and bladeAt.Z > -0.2,
			string.format("%.2f, %.2f, %.2f", bladeAt.X, bladeAt.Y, bladeAt.Z))
		if tool:GetAttribute("ModelSource") == "Blender" then
			check("Blender materials", (grip :: BasePart).Material == Enum.Material.Leather and (blade :: BasePart).Material == Enum.Material.Metal)
		end
	end
	tool:Destroy()
	local look = assert(ToolPresentation.get("HarvestHook"))
	local pull = look.vfx.pull
	check("Hook Pull effect configured", pull ~= nil and pull.flySeconds > 0 and look.sounds.Pull ~= nil)

	-- Buying through the Shop path.
	local profile = assert(State.get(player.UserId))
	if profile.ownedTools.HarvestHook then Tools.revoke(player, "HarvestHook") end
	profile.cash = hook.price + 9
	State.publish(player.UserId)
	task.wait(Config.Shop.requestCooldownSeconds)
	local bought = assert(Tools.request(player, "Buy", "HarvestHook"))
	check("shop buy charges the price once", bought.ok and profile.cash == 9 and profile.ownedTools.HarvestHook == true, bought.reason)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("equip from the shop", assert(Tools.request(player, "Equip", "HarvestHook")).ok)
	check("equip tracked on the server", waitFor(function() return profile.equippedTool == "HarvestHook" end, 2))
	local held = assert(player.Character):FindFirstChildOfClass("Tool")
	check("the held tool is the hook with a Reach motor", held ~= nil and held:GetAttribute("ToolId") == "HarvestHook"
		and (held :: Tool):FindFirstChild("Reach", true) ~= nil)

	-- Standing in front of column 3 of Plot 1 (stalks 1_3, 1_9, 1_15 ... 5 studs apart).
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
	standBefore(10)
	ripen(1)
	profile.rawCorn.Normal = 0
	task.wait(0.6)
	local flat = (root().Position - first) * Vector3.new(1, 0, 1)
	local r1 = Harvest.swing(player, "HarvestHook")
	local gone = cut()
	local count = 0
	for _ in gone do count += 1 end
	check("hooks 2 stalks from 10 studs away", r1.ok and r1.amount == 2 and #(r1.targets or {}) == 2 and count == 2 and gone["1_3"] == true,
		string.format("%s %d (stood %.1f studs off)", r1.reason, r1.amount, flat.Magnitude))
	local targets = r1.targets or {}
	check("targets come nearest first", #targets == 2 and (targets[1] - first).Magnitude < 0.5)
	local r2 = Harvest.swing(player, "HarvestHook")
	check("an immediate second swing is refused", not r2.ok and r2.reason == "Too fast")
	ripen(1)
	task.wait(0.27) -- Early by 0.18 s: inside the half-cooldown (0.225 s) allowance.
	local r3 = Harvest.swing(player, "HarvestHook")
	check("a slightly early swing (jitter) is accepted", r3.ok and r3.amount == 2, r3.reason)
	local r4 = Harvest.swing(player, "HarvestHook")
	check("but the allowance is not a free extra swing", not r4.ok and r4.reason == "Too fast")

	-- Out of reach: 14.5 studs from the nearest stalk, the neighbours further still.
	standBefore(14.5)
	ripen(1)
	task.wait(0.6)
	local before = profile.rawCorn.Normal
	local r5 = Harvest.swing(player, "HarvestHook")
	check("nothing past 14 studs", not r5.ok and profile.rawCorn.Normal == before, r5.reason)
	-- Only alternating tools (Twin Sickles) carry hand/combo/streak in their replies.
	check("non-alternating tools report no hand", r1.hand == nil and r5.hand == nil)

	-- Leave the player ready for a visual check: holding the hook 10 studs before column 3.
	standBefore(10)
	ripen(1)
	profile.rawCorn.Normal = 0
	State.publish(player.UserId)
	player:SetAttribute("RawCorn", 0)
	task.spawn(function()
		local untilAt = os.clock() + 60
		while os.clock() < untilAt do
			ripen(1)
			task.wait(0.5)
		end
	end)
end)

local passed = ok
for _, c in checks do if not c.passed then passed = false end end
script:SetAttribute("Results", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
print("[HarvestHook tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
