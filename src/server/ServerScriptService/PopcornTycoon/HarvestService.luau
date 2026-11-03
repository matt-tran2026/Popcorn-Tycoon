--!strict
-- Every harvest path (hand prompts and swung tools) goes through take(), so maturity,
-- capacity, partial fits and regrowth follow one rule.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local ToolRules = require(Shared.ToolRules)
local Types = require(Shared.Types)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local lastAttempt: { [number]: number } = {}
local lastSwing: { [number]: number } = {}
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

-- Take the ready yields of one stalk that fit in the bag. Each yield is worth `multiplier`
-- corn; only whole yields are taken, and the stalk keeps the rest (its timer is backdated
-- so exactly the remainder stays ready). Returns corn granted and yields that were ready.
-- Must not yield: callers rely on validation and commit happening in one step.
local function take(profile: Types.Profile, field: Types.Field, stalk: Types.Stalk, at: number, multiplier: number): (number, number)
	local crop = Config.Crops[field.cropId]
	local available = Growth.yields(stalk.growthStartedAt, at, crop)
	local space = Config.Inventory.capacity - State.carried(profile)
	local taken = math.min(available, space // multiplier)
	if taken <= 0 then return 0, available end
	local corn = taken * multiplier
	profile.rawCorn[field.cropId] = (profile.rawCorn[field.cropId] or 0) + corn
	stalk.growthStartedAt = at - (available - taken) * crop.growthSeconds
	return corn, available
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
	local corn, available = take(profile, field, stalk, at, 1)
	if available == 0 then return result(false, "Corn is growing") end
	if corn == 0 then return result(false, "Bag full · pop it at the microwave") end
	player:SetAttribute("RawCorn", State.carried(profile))
	return result(true, if corn < available then "Bag full" else "Harvested", corn)
end

-- One swing of an owned, equipped tool. The server picks the targets from the character's
-- position and facing; the client never names stalks.
function HarvestService.swing(player: Player, toolId: string): Types.HarvestResult
	local tool = Config.Tools[toolId]
	if not tool then return result(false, "Unknown tool") end
	local clock = os.clock()
	local previous = lastSwing[player.UserId]
	-- A small allowance absorbs network jitter between two honest swings.
	if previous and clock - previous < tool.cooldownSeconds * 0.9 then return result(false, "Too fast") end
	lastSwing[player.UserId] = clock
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	if not profile.ownedTools[toolId] or profile.equippedTool ~= toolId then return result(false, tool.displayName .. " not equipped") end
	local root = livingRoot(player)
	if not root then return result(false, "Character unavailable") end
	local field = profile.fields.Starter
	if not field or field.ownerUserId ~= player.UserId or not Config.Crops[field.cropId] then return result(false, "No field") end
	local at = now()
	local crop = Config.Crops[field.cropId]
	-- Only ripe stalks are candidates, so growing corn never soaks up a swing's targets.
	local candidates: { Types.TargetCandidate } = {}
	for id, part in Farms.stalkParts(player.UserId) do
		local stalk = field.stalks[id]
		if stalk and Growth.yields(stalk.growthStartedAt, at, crop) > 0 then
			table.insert(candidates, { id = id, position = part.Position })
		end
	end
	local picked = ToolRules.pickTargets(root.Position, root.CFrame.LookVector, candidates, tool)
	if #picked == 0 then return result(false, "Swing closer to ripe corn") end
	if Config.Inventory.capacity - State.carried(profile) < tool.yieldMultiplier then
		return result(false, "Bag full · pop it at the microwave")
	end
	-- No yields between picking targets and committing every take.
	local total, full = 0, false
	local targets: { Vector3 } = {}
	for _, id in picked do
		local corn, available = take(profile, field, field.stalks[id], at, tool.yieldMultiplier)
		if corn > 0 then
			total += corn
			table.insert(targets, (Farms.target(player.UserId, field.id, id) :: Part).Position)
		end
		if corn < available * tool.yieldMultiplier then full = true end
	end
	if total == 0 then return result(false, "Bag full · pop it at the microwave") end
	player:SetAttribute("RawCorn", State.carried(profile))
	local response = result(true, if full then "Bag full" else "Harvested", total)
	response.tool, response.targets = toolId, targets
	return response
end

function HarvestService.release(userId: number)
	lastAttempt[userId] = nil
	lastSwing[userId] = nil
end

return HarvestService
