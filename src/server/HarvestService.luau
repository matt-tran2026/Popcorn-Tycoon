--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local Types = require(Shared.Types)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local lastAttempt: { [number]: number } = {}
local HarvestService = {}

local function result(ok: boolean, reason: string, amount: number?): Types.HarvestResult
	return { ok = ok, reason = reason, amount = amount or 0 }
end

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
	if profile.equippedTool ~= "Manual" or not profile.ownedTools.Manual then return result(false, "Manual tool required") end
	local field = profile.fields[fieldId]
	if not field or field.ownerUserId ~= player.UserId then return result(false, "Not your field") end
	local stalk = field.stalks[stalkId]
	local target = Farms.target(player.UserId, fieldId, stalkId)
	if not stalk or not target then return result(false, "Invalid target") end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return result(false, "Character unavailable") end
	local distance = (root.Position - target.Position).Magnitude
	if distance ~= distance or distance > Config.Manual.range then return result(false, "Too far away") end
	local crop = Config.Crops[field.cropId]
	if not crop then return result(false, "Invalid crop") end
	local now = DateTime.now().UnixTimestampMillis / 1000
	local amount = Growth.yields(stalk.growthStartedAt, now, crop)
	if amount == 0 then return result(false, "Corn is growing") end
	-- No yields between validation, inventory grant, and timer reset.
	profile.rawCorn[field.cropId] = (profile.rawCorn[field.cropId] or 0) + amount
	stalk.growthStartedAt = now
	player:SetAttribute("RawCorn", profile.rawCorn[field.cropId])
	return result(true, "Harvested", amount)
end

function HarvestService.release(userId: number)
	lastAttempt[userId] = nil
end

return HarvestService
