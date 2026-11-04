--!strict
-- Temporary Server RunContext integration runner during Play (sell stand, Cash, Sickle).
-- Install outside the synced PopcornTycoon folder; destroy after reading Results.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local ToolRules = require(Shared.ToolRules)
local Services = game:GetService("ServerScriptService"):WaitForChild("PopcornTycoon")
local State = require(Services.PlayerStateService)
local Farms = require(Services.FarmService)
local Harvest = require(Services.HarvestService)
local Sell = require(Services.SellService)
local Tools = require(Services.ToolService)
local checks: { { name: string, passed: boolean } } = {}
local function check(name: string, condition: boolean)
	table.insert(checks, { name = name, passed = condition })
	assert(condition, name)
end
local player = assert(Players:GetPlayers()[1], "Requires a live player")
local function now(): number return DateTime.now().UnixTimestampMillis / 1000 end
local function root(): BasePart return (assert(player.Character):WaitForChild("HumanoidRootPart")) :: BasePart end
local function waitFor(condition: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not condition() and os.clock() < deadline do task.wait(0.1) end
	return condition()
end
local function heldTools(): { Tool }
	local list = {}
	for _, holder in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if holder then for _, child in holder:GetChildren() do if child:IsA("Tool") then table.insert(list, child) end end end
	end
	return list
end

local ok, err = pcall(function()
	-- Pure targeting rule.
	local sickle = Config.Tools.Sickle
	local c = function(id: string, x: number, z: number) return { id = id, position = Vector3.new(x, 7, z) } end
	local picked = ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 0, 1), {
		c("far", 0, 8.9), c("near", 0, 2), c("mid", 1, 4), c("behind", 0, -2), c("toofar", 0, 9.5),
		c("wide", 5, 0.5), c("next", -1, 5), c("near", 0, 2),
	}, sickle)
	check("targets: nearest first, in reach and arc, capped, deduplicated",
		#picked == 3 and picked[1] == "near" and picked[2] == "mid" and picked[3] == "next")
	check("targets: zero facing picks nothing", #ToolRules.pickTargets(Vector3.zero, Vector3.new(0, 1, 0), { c("a", 0, 1) }, sickle) == 0)

	local profile = assert(State.get(player.UserId))
	local field = profile.fields.Plot1
	local crop = Config.Crops[field.cropId]
	local farm = workspace.PopcornFarms:FindFirstChild("Farm_" .. player.UserId) :: Model
	local stand = assert(Farms.sellStand(player.UserId))
	check("stand has its owner prompt; no tool shed or in-world tool prompt", stand:FindFirstChild("Sell") ~= nil
		and farm.Scenery:FindFirstChild("ToolShed") == nil and farm:FindFirstChild("BuyTool", true) == nil)

	-- Selling.
	local function standAt(part: BasePart) assert(player.Character):PivotTo(CFrame.new(part.Position + part.CFrame.LookVector * 4)) end
	profile.popcorn, profile.cash = 0, 0
	State.publish(player.UserId)
	standAt(stand)
	local response = Sell.sell(player, player.UserId)
	check("sell with no popcorn is refused", not response.ok and profile.cash == 0)
	profile.popcorn = 35
	State.publish(player.UserId)
	check("stand shows expected payout", waitFor(function() return (stand:FindFirstChild("Sell") :: ProximityPrompt).ObjectText == "35 popcorn → $70" end, 1))
	assert(player.Character):PivotTo(CFrame.new(stand.Position + Vector3.new(0, 0, -40)))
	response = Sell.sell(player, player.UserId)
	check("sell out of range is refused without change", not response.ok and profile.popcorn == 35 and profile.cash == 0)
	response = Sell.sell(player, player.UserId + 1)
	check("selling at another owner's stand is refused", not response.ok and profile.popcorn == 35)
	standAt(stand)
	response = Sell.sell(player, player.UserId)
	check("sell converts all popcorn once", response.ok and response.amount == 70 and profile.popcorn == 0 and profile.cash == 70
		and player:GetAttribute("Cash") == 70 and player:GetAttribute("Popcorn") == 0)
	response = Sell.sell(player, player.UserId)
	check("repeat sell pays nothing", not response.ok and profile.cash == 70)

	-- Buying the sickle through the Shop menu, from anywhere.
	profile.cash = sickle.price - 1
	task.wait(Config.Shop.requestCooldownSeconds)
	response = assert(Tools.request(player, "Buy", "Sickle"))
	check("buy without enough cash is refused", not response.ok and profile.cash == sickle.price - 1 and not profile.ownedTools.Sickle)
	task.wait(Config.Shop.requestCooldownSeconds)
	response = assert(Tools.request(player, "Buy", "Flamethrower"))
	check("unknown tool is refused", not response.ok)
	-- Each price names its currency: popcorn cannot pay a Cash price.
	check("sickle is priced in cash", sickle.currency == "Cash")
	profile.popcorn = sickle.price * 10
	task.wait(Config.Shop.requestCooldownSeconds)
	response = assert(Tools.request(player, "Buy", "Sickle"))
	check("popcorn does not pay a cash price", not response.ok and profile.popcorn == sickle.price * 10 and not profile.ownedTools.Sickle)
	profile.popcorn = 0
	profile.cash = sickle.price + 10
	-- Far from every station: the Shop needs no walk.
	assert(player.Character):PivotTo(CFrame.new(stand.Position + Vector3.new(0, 0, -40)))
	task.wait(Config.Shop.requestCooldownSeconds)
	response = assert(Tools.request(player, "Buy", "Sickle"))
	check("shop buy charges once and grants the tool", response.ok and profile.cash == 10 and profile.ownedTools.Sickle == true
		and player:GetAttribute("Cash") == 10 and player:GetAttribute("Owned_Sickle") == true)
	check("rapid repeat shop request is dropped", Tools.request(player, "Buy", "Sickle") == nil and profile.cash == 10)
	task.wait(Config.Shop.requestCooldownSeconds)
	response = assert(Tools.request(player, "Buy", "Sickle"))
	check("repeat shop buy refused without charge", not response.ok and response.reason == "Already owned" and profile.cash == 10)
	task.wait(Config.Shop.requestCooldownSeconds)
	check("malformed shop requests are refused", not assert(Tools.request(player, "Steal", "Sickle")).ok and profile.cash == 10)
	check("one Sickle tool in the backpack", waitFor(function() return #heldTools() == 1 end, 2) and heldTools()[1]:GetAttribute("ToolId") == "Sickle")
	standAt(stand) -- Back onto the farm before the swing checks take their height from the avatar.
	task.wait(0.5)

	-- Swinging.
	local function ripen(count: number)
		local at = now()
		for _, stalk in field.stalks do stalk.growthStartedAt = at - count * crop.growthSeconds end
	end
	local function ready(id: string): number return Growth.yields(field.stalks[id].growthStartedAt, now(), crop) end
	ripen(1)
	profile.rawCorn.Normal = 0
	response = Harvest.swing(player, "Sickle")
	check("swing without equipping is refused", not response.ok and profile.rawCorn.Normal == 0)
	check("equipping an unknown tool is refused", not Tools.equip(player, "Flamethrower").ok)
	check("shop equip succeeds", Tools.equip(player, "Sickle").ok)
	check("equipping is tracked on the server", waitFor(function() return profile.equippedTool == "Sickle" and player:GetAttribute("EquippedTool") == "Sickle" end, 2))
	-- Face into row 1 from the cross path, between columns 3 and 4.
	local a = assert(Farms.target(player.UserId, "Plot1", "1_3")).Position
	local b = assert(Farms.target(player.UserId, "Plot1", "1_4")).Position
	local inward = (assert(Farms.target(player.UserId, "Plot1", "1_9")).Position - a) * Vector3.new(1, 0, 1)
	local spot = (a + b) / 2 - inward.Unit * 2.5
	assert(player.Character):PivotTo(CFrame.lookAt(Vector3.new(spot.X, root().Position.Y, spot.Z), Vector3.new(spot.X, root().Position.Y, spot.Z) + inward))
	task.wait(sickle.cooldownSeconds)
	response = Harvest.swing(player, "Sickle")
	local cut: { string } = {}
	for id in field.stalks do if ready(id) == 0 then table.insert(cut, id) end end
	table.sort(cut)
	check("one swing cuts the three nearest ripe stalks", response.ok and response.amount == 3 and #(response.targets or {}) == 3 and #cut == 3
		and table.find(cut, "1_3") ~= nil and table.find(cut, "1_4") ~= nil and profile.rawCorn.Normal == 3 and player:GetAttribute("RawCorn") == 3)
	response = Harvest.swing(player, "Sickle")
	check("swings faster than the cadence are refused", not response.ok and response.reason == "Too fast" and profile.rawCorn.Normal == 3)
	task.wait(sickle.cooldownSeconds)
	response = Harvest.swing(player, "Sickle")
	local second = 0
	for id in field.stalks do if ready(id) == 0 then second += 1 end end
	-- From the cross path only row 2's middle stalks are still inside the arc.
	check("next swing moves on to the next ripe stalks", response.ok and response.amount >= 1 and second == 3 + response.amount and profile.rawCorn.Normal == second)
	ripen(3)
	profile.rawCorn.Normal = Config.Inventory.capacity - 4
	task.wait(sickle.cooldownSeconds)
	response = Harvest.swing(player, "Sickle")
	local partial = 0
	for id in field.stalks do partial += crop.maxYields - ready(id) end
	check("a nearly full bag takes only what fits and the stalks keep the rest",
		response.ok and response.reason == "Bag full" and response.amount == 4 and profile.rawCorn.Normal == Config.Inventory.capacity and partial == 4)
	task.wait(sickle.cooldownSeconds)
	response = Harvest.swing(player, "Sickle")
	check("a full bag refuses the swing", not response.ok and profile.rawCorn.Normal == Config.Inventory.capacity)
	profile.rawCorn.Normal = 0
	assert(player.Character):PivotTo(assert(player.Character):GetPivot() * CFrame.Angles(0, math.pi, 0) + (-inward.Unit * 8))
	task.wait(sickle.cooldownSeconds)
	response = Harvest.swing(player, "Sickle")
	check("facing away from the corn cuts nothing", not response.ok and profile.rawCorn.Normal == 0)

	-- Hand picking still works while the sickle is held.
	local hand = assert(Farms.target(player.UserId, "Plot1", "1_1"))
	assert(player.Character):PivotTo(CFrame.new(hand.Position + Vector3.new(0, 0, -2)))
	task.wait(Config.Manual.cooldownSeconds)
	response = Harvest.attempt(player, player.UserId, "Plot1", "1_1")
	check("hand picking works with the sickle held", response.ok and response.amount >= 1)

	task.wait(Config.Shop.requestCooldownSeconds)
	check("shop can put the tool away", assert(Tools.request(player, "Equip", "Manual")).ok)
	check("unequipping returns to hands", waitFor(function() return profile.equippedTool == "Manual" end, 2))
	task.wait(sickle.cooldownSeconds)
	response = Harvest.swing(player, "Sickle")
	check("swing after unequipping is refused", not response.ok)

	-- Respawn rebuilds exactly one tool from the profile.
	player:LoadCharacter()
	check("respawn returns one sickle", waitFor(function() return #heldTools() == 1 end, 5) and profile.equippedTool == "Manual")
	task.wait(0.5)
	check("no duplicate after respawn settles", #heldTools() == 1)
end)

script:SetAttribute("Results", Http:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = checks }))
print("[Tools tests] " .. (if ok then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
