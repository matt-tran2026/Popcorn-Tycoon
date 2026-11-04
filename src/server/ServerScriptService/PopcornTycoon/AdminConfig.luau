--!strict
-- Who may use the Owner-only Developer Panel (AdminService) and where. Server-only: this module
-- lives in ServerScriptService, which never replicates, so clients cannot read the allowlist.
-- Creator request (Nov 4 2026): one rank, Owner, identified by Roblox UserId (never by name),
-- and testing commands only while running in Roblox Studio. The rank table is shaped so more
-- ranks can be added later (give each a lower power and set a command's minRank); none exist yet.
local AdminConfig = {}

-- Rank name -> power. A command runs when the player's rank power >= the command's minRank power.
AdminConfig.Ranks = { Owner = 100 } :: { [string]: number }

-- Explicitly authorized accounts, by UserId. To authorize another account, add
-- `[<UserId>] = "Owner",` here (find a UserId in the profile URL roblox.com/users/<UserId>/profile,
-- or in Studio's command bar: print(game:GetService("StudioService"):GetUserId())).
AdminConfig.Members = {
	-- The account signed in to Studio on Nov 4 2026 (StudioService:GetUserId); the creator is asked to confirm it.
	[4648453584] = "Owner",
} :: { [number]: string }

-- Also treat the individual creator of a user-owned experience as Owner. Group-owned
-- experiences never grant this (group membership is not Owner access).
AdminConfig.trustUserCreator = true

-- Studio's local multi-client test (Test > Clients and Servers) uses simulated players with
-- UserIds -1, -2, ... instead of real accounts. Only these ids, and only inside Studio, get a
-- rank here: Player1 is Owner so the panel can be tested; Player2+ stay ordinary players.
-- Never honoured outside Studio, and negative ids are never real accounts.
AdminConfig.studioTestUsers = { [-1] = "Owner" } :: { [number]: string }

-- Testing commands mutate progression, so they run only in Studio. Keep this false: when false
-- the server never even creates the admin remote outside Studio.
AdminConfig.allowOutsideStudio = false

-- Limits for developer grants. maxBalance stays far below 2^53 so whole-number Cash, popcorn
-- and the sale payout (popcorn x Config.Sell.cashPerPopcorn) remain exact.
AdminConfig.maxBalance = 1e15
-- Token bucket per player: `burst` requests at once, refilled at `perSecond`.
AdminConfig.rate = { burst = 10, perSecond = 5 }
-- Owner walk-speed command range (16 is the Roblox default).
AdminConfig.walkSpeed = { normal = 16, min = 16, max = 120 }

export type Creator = { creatorType: Enum.CreatorType, creatorId: number }

-- The rank of `userId`, or nil for an ordinary player. Pure: the caller passes the environment.
function AdminConfig.rankOf(userId: number, isStudio: boolean, creator: Creator?): string?
	if typeof(userId) ~= "number" or userId ~= userId or userId % 1 ~= 0 then return nil end
	if userId <= 0 then
		return if isStudio then AdminConfig.studioTestUsers[userId] else nil
	end
	local rank = AdminConfig.Members[userId]
	if rank then return rank end
	if AdminConfig.trustUserCreator and creator and creator.creatorType == Enum.CreatorType.User
		and creator.creatorId > 0 and creator.creatorId == userId then
		return "Owner"
	end
	return nil
end

-- Whether testing mutations may run at all in this environment.
function AdminConfig.mutationsAllowed(isStudio: boolean): boolean
	return isStudio or AdminConfig.allowOutsideStudio == true
end

-- Whether `rank` meets `required` (both rank names).
function AdminConfig.atLeast(rank: string?, required: string): boolean
	local have = if rank then AdminConfig.Ranks[rank] else nil
	local need = AdminConfig.Ranks[required]
	return have ~= nil and need ~= nil and have >= need
end

function AdminConfig.validate()
	for userId, rank in AdminConfig.Members do
		assert(typeof(userId) == "number" and userId > 0 and userId % 1 == 0, "Admin members must be real UserIds")
		assert(AdminConfig.Ranks[rank], "Unknown admin rank " .. tostring(rank))
	end
	for userId, rank in AdminConfig.studioTestUsers do
		assert(typeof(userId) == "number" and userId < 0, "Studio test users must be simulated (negative) ids")
		assert(AdminConfig.Ranks[rank], "Unknown admin rank " .. tostring(rank))
	end
	assert(AdminConfig.maxBalance >= 1 and AdminConfig.maxBalance < 2 ^ 52 / 4, "maxBalance must leave room for sale payouts")
	assert(AdminConfig.rate.burst >= 1 and AdminConfig.rate.perSecond > 0, "Invalid admin rate limit")
	local speed = AdminConfig.walkSpeed
	assert(speed.min > 0 and speed.min <= speed.normal and speed.normal <= speed.max, "Invalid walk speed range")
end

return AdminConfig
