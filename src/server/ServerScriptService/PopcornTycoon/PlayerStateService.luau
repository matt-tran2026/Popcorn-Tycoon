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

function PlayerStateService.release(userId: number)
	profiles[userId] = nil
end

return PlayerStateService
