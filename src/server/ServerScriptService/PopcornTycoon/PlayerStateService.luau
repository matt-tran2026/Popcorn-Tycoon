--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

-- The only profile lifecycle boundary. Replace this adapter with validated,
-- session-protected persistence later; callers must not manufacture fallback saves.
local profiles: { [number]: Types.Profile } = {}
local PlayerStateService = {}

-- Stalk IDs are row-major, so a purchased row continues the numbering.
function PlayerStateService.plantRow(field: Types.Field, row: number, now: number)
	local crop = Config.Crops[field.cropId]
	for col = 1, Config.Starter.columns do
		local id = tostring((row - 1) * Config.Starter.columns + col)
		field.stalks[id] = { id = id, growthStartedAt = now - crop.growthSeconds }
	end
end

function PlayerStateService.load(userId: number, now: number): Types.Profile
	assert(profiles[userId] == nil, "Profile is already loaded")
	local field: Types.Field = { id = "Starter", ownerUserId = userId, cropId = Config.Starter.cropId, rows = Config.Starter.rows, stalks = {} }
	for row = 1, field.rows do PlayerStateService.plantRow(field, row, now) end
	local profile: Types.Profile = {
		schemaVersion = Config.SchemaVersion,
		popcorn = 0,
		coins = 0,
		rawCorn = { Normal = 0 },
		ownedTools = { Manual = true },
		equippedTool = "Manual",
		unlockedCrops = { Normal = true },
		upgrades = {},
		fields = { Starter = field },
	}
	profiles[userId] = profile
	return profile
end

function PlayerStateService.get(userId: number): Types.Profile?
	return profiles[userId]
end

function PlayerStateService.carried(profile: Types.Profile): number
	local total = 0
	for _, count in profile.rawCorn do total += count end
	return total
end

-- Every popcorn grant goes through here so the replicated balance never drifts.
function PlayerStateService.creditPopcorn(userId: number, amount: number)
	local profile = profiles[userId]
	assert(profile and amount >= 0 and amount % 1 == 0, "Invalid popcorn credit")
	profile.popcorn += amount
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player then player:SetAttribute("Popcorn", profile.popcorn) end
end

-- Balances replicate as player attributes; call after any committed balance change.
function PlayerStateService.publish(userId: number)
	local profile = profiles[userId]
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not profile or not player then return end
	player:SetAttribute("Popcorn", profile.popcorn)
	player:SetAttribute("Coins", profile.coins)
	player:SetAttribute("EquippedTool", profile.equippedTool)
	-- Owned_<toolId> lets the Shop show owned state; the profile stays the authority.
	for toolId, owned in profile.ownedTools do player:SetAttribute("Owned_" .. toolId, owned) end
end

function PlayerStateService.balance(profile: Types.Profile, currency: Types.Currency): number
	return if currency == "Coins" then profile.coins else profile.popcorn
end

-- Deducts a price from the named balance if it is covered. Must not yield: callers check
-- eligibility, then spend and grant in the same step. Returns false without changing anything.
function PlayerStateService.spend(profile: Types.Profile, currency: Types.Currency, amount: number): boolean
	assert(amount >= 0 and amount % 1 == 0, "Invalid price")
	if PlayerStateService.balance(profile, currency) < amount then return false end
	if currency == "Coins" then profile.coins -= amount else profile.popcorn -= amount end
	return true
end

function PlayerStateService.release(userId: number)
	profiles[userId] = nil
end

return PlayerStateService
