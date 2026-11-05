--!strict
-- Every harvest path (hand prompts and swung tools) goes through take(), so maturity,
-- capacity, partial fits and regrowth follow one rule.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local ToolRules = require(Shared.ToolRules)
local Types = require(Shared.Types)
local FarmUpgrades = require(Shared.FarmUpgrades)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local lastAttempt: { [number]: number } = {}
-- When each player's next swing is due (os.clock). See HarvestService.swing.
local swingDue: { [number]: number } = {}
local HarvestService = {}

local function result(ok: boolean, reason: string, amount: number?): Types.HarvestResult
	return { ok = ok, reason = reason, amount = amount or 0 }
end

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return nil end
	return root
end

-- Take the ready cycles of one stalk that fit in the bag. One cycle is worth the field's corn
-- per cycle (Corn Yield upgrade) times the tool's multiplier; only whole cycles are taken and
-- the stalk keeps the rest (its timer is backdated so exactly the remainder stays ready, under
-- the field's own growth time). Returns corn granted, cycles that were ready, and whether
-- any ready cycle had to stay on the stalk because the bag ran out of room.
-- Must not yield: callers rely on validation and commit happening in one step.
local function take(profile: Types.Profile, field: Types.Field, stalk: Types.Stalk, at: number, multiplier: number): (number, number, boolean)
	local rules = FarmUpgrades.fieldRules(field)
	local available = Growth.yields(stalk.growthStartedAt, at, rules)
	local perCycle = rules.cornPerYield * multiplier
	local space = math.max(0, State.bagCapacity(profile) - State.carried(profile))
	local taken = math.min(available, space // perCycle)
	if taken <= 0 then return 0, available, available > 0 end
	local corn = taken * perCycle
	profile.rawCorn[field.cropId] = (profile.rawCorn[field.cropId] or 0) + corn
	stalk.growthStartedAt = at - (available - taken) * rules.growthSeconds
	return corn, available, taken < available
end

-- Hand picking through a stalk's prompt. Always available, whatever tool is held.
function HarvestService.attempt(player: Player, ownerUserId: unknown, fieldId: unknown, stalkId: unknown): Types.HarvestResult
	local clock = os.clock()
	local previous = lastAttempt[player.UserId]
	if previous and clock - previous < Config.Manual.cooldownSeconds then return result(false, "Too fast") end
	lastAttempt[player.UserId] = clock
	if typeof(ownerUserId) ~= "number" or typeof(fieldId) ~= "string" or typeof(stalkId) ~= "string" then
		return result(false, "Invalid target")
	end
	if ownerUserId ~= player.UserId then return result(false, "Not your field") end
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	if not profile.ownedTools.Manual then return result(false, "Manual tool required") end
	local field = profile.fields[fieldId]
	if not field or field.ownerUserId ~= player.UserId then return result(false, "Not your field") end
	local stalk = field.stalks[stalkId]
	local target = Farms.target(player.UserId, fieldId, stalkId)
	if not stalk or not target then return result(false, "Invalid target") end
	local root = livingRoot(player)
	if not root then return result(false, "Character unavailable") end
	local distance = (root.Position - target.Position).Magnitude
	if distance ~= distance or distance > Config.Manual.range then return result(false, "Too far away") end
	if not Config.Crops[field.cropId] then return result(false, "Invalid crop") end
	local at = now()
	local corn, available, leftOver = take(profile, field, stalk, at, 1)
	if available == 0 then return result(false, "Corn is growing") end
	if corn == 0 then return result(false, "Bag full · pop it at the microwave") end
	player:SetAttribute("RawCorn", State.carried(profile))
	return result(true, if leftOver then "Bag full" else "Harvested", corn)
end

-- One swing of an owned, equipped tool. The server picks the targets from the character's
-- position and facing; the client never names stalks.
function HarvestService.swing(player: Player, toolId: string): Types.HarvestResult
	local tool = Config.Tools[toolId]
	if not tool then return result(false, "Unknown tool") end
	if tool.behavior ~= "ArcSweep" and tool.behavior ~= "SingleTarget" then return result(false, "Unknown tool") end
	-- Cadence: each accepted swing moves the due time one cooldown on from the later of now and
	-- the previous due time, and a swing may arrive up to half a cooldown early. Network jitter
	-- between two honest swings (it matters at the clippers' 0.12 s) is absorbed, yet over any
	-- stretch no more than one swing per cooldown (plus one) is ever accepted.
	local clock = os.clock()
	local due = swingDue[player.UserId]
	if due and clock < due - tool.cooldownSeconds * 0.5 then return result(false, "Too fast") end
	swingDue[player.UserId] = math.max(clock, due or clock) + tool.cooldownSeconds
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	if not profile.ownedTools[toolId] or profile.equippedTool ~= toolId then return result(false, tool.displayName .. " not equipped") end
	local root = livingRoot(player)
	if not root then return result(false, "Character unavailable") end
	local at = now()
	-- Only ripe stalks are candidates, so growing corn never soaks up a swing's targets.
	-- Candidates come from every owned plot; each stalk remembers its plot (Farms.fieldOf).
	local candidates: { Types.TargetCandidate } = {}
	local fieldOf: { [string]: Types.Field } = {}
	local rulesOf: { [string]: Types.GrowthRules } = {}
	for fieldId, field in profile.fields do
		if Config.Crops[field.cropId] then rulesOf[fieldId] = FarmUpgrades.fieldRules(field) end
	end
	for id, part in Farms.stalkParts(player.UserId) do
		local fieldId = Farms.fieldOf(player.UserId, id)
		local field = if fieldId then profile.fields[fieldId] else nil
		local rules = if fieldId then rulesOf[fieldId] else nil
		local stalk = if field then field.stalks[id] else nil
		if field and rules and stalk and field.ownerUserId == player.UserId and Growth.yields(stalk.growthStartedAt, at, rules) > 0 then
			table.insert(candidates, { id = id, position = part.Position })
			fieldOf[id] = field
		end
	end
	-- ArcSweep and SingleTarget share the targeting rule; SingleTarget tools have maxTargets 1
	-- and a narrow arc (Config.validate), so they cut the one nearest ripe stalk in front.
	local picked = ToolRules.pickTargets(root.Position, root.CFrame.LookVector, candidates, tool)
	if #picked == 0 then return result(false, "Swing closer to ripe corn") end
	if State.carried(profile) >= State.bagCapacity(profile) then
		return result(false, "Bag full · pop it at the microwave")
	end
	-- No yields between picking targets and committing every take.
	local total, full = 0, false
	local targets: { Vector3 } = {}
	for _, id in picked do
		local field = fieldOf[id]
		local corn, _, leftOver = take(profile, field, field.stalks[id], at, tool.yieldMultiplier)
		if corn > 0 then
			total += corn
			table.insert(targets, (Farms.target(player.UserId, field.id, id) :: Part).Position)
		end
		if leftOver then full = true end
	end
	if total == 0 then return result(false, "Bag full · pop it at the microwave") end
	player:SetAttribute("RawCorn", State.carried(profile))
	local response = result(true, if full then "Bag full" else "Harvested", total)
	response.tool, response.targets = toolId, targets
	return response
end

function HarvestService.release(userId: number)
	lastAttempt[userId] = nil
	swingDue[userId] = nil
end

return HarvestService
