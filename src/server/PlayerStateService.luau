--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

-- The only profile lifecycle boundary. Replace this adapter with validated,
-- session-protected persistence later; callers must not manufacture fallback saves.
local profiles: { [number]: Types.Profile } = {}
local PlayerStateService = {}

function PlayerStateService.load(userId: number, now: number): Types.Profile
	assert(profiles[userId] == nil, "Profile is already loaded")
	local stalks: { [string]: Types.Stalk } = {}
	local crop = Config.Crops[Config.Starter.cropId]
	for i = 1, Config.Starter.rows * Config.Starter.columns do
		local id = tostring(i)
		stalks[id] = { id = id, growthStartedAt = now - crop.growthSeconds }
	end
	local profile: Types.Profile = {
		schemaVersion = Config.SchemaVersion,
		popcorn = 0,
		rawCorn = { Normal = 0 },
		ownedTools = { Manual = true },
		equippedTool = "Manual",
		unlockedCrops = { Normal = true },
		fields = {
			Starter = { id = "Starter", ownerUserId = userId, cropId = Config.Starter.cropId, stalks = stalks },
		},
	}
	profiles[userId] = profile
	return profile
end

function PlayerStateService.get(userId: number): Types.Profile?
	return profiles[userId]
end

function PlayerStateService.release(userId: number)
	profiles[userId] = nil
end

return PlayerStateService
