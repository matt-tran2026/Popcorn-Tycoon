--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

-- The only profile lifecycle boundary. Replace this adapter with validated,
-- session-protected persistence later; callers must not manufacture fallback saves.
local profiles: { [number]: Types.Profile } = {}
local PlayerStateService = {}

-- Stalk IDs are "<plot>_<n>" with n row-major, so a purchased row continues the numbering
-- and every id is unique across the farm.
function PlayerStateService.stalkId(plot: number, row: number, col: number): string
	return tostring(plot) .. "_" .. tostring((row - 1) * Config.Plot.columns + col)
end

function PlayerStateService.plantRow(field: Types.Field, row: number, now: number)
	local crop = Config.Crops[field.cropId]
	for col = 1, Config.Plot.columns do
		local id = PlayerStateService.stalkId(field.plot, row, col)
		field.stalks[id] = { id = id, growthStartedAt = now - crop.growthSeconds }
	end
end

-- A new plot (grid index `plot`) with its base rows planted and ripe.
local function newField(userId: number, plot: number, now: number): Types.Field
	local field: Types.Field = {
		id = "Plot" .. tostring(plot), plot = plot, ownerUserId = userId,
		cropId = Config.Plot.cropId, rows = Config.Plot.baseRows, stalks = {},
	}
	for row = 1, field.rows do PlayerStateService.plantRow(field, row, now) end
	return field
end

-- Adds the next plot in grid order. Must not yield (purchases commit in one step).
function PlayerStateService.addPlot(profile: Types.Profile, userId: number, now: number): Types.Field
	local plot = 1
	while profile.fields["Plot" .. tostring(plot)] do plot += 1 end
	assert(Config.Grid.order[plot], "No plot cell left")
	local field = newField(userId, plot, now)
	profile.fields[field.id] = field
	return field
end

function PlayerStateService.load(userId: number, now: number): Types.Profile
	assert(profiles[userId] == nil, "Profile is already loaded")
	local field = newField(userId, 1, now)
	local profile: Types.Profile = {
		schemaVersion = Config.SchemaVersion,
		popcorn = 0,
		cash = 0,
		rawCorn = { Normal = 0 },
		ownedTools = { Manual = true },
		equippedTool = "Manual",
		unlockedCrops = { Normal = true },
		upgrades = {},
		fields = { [field.id] = field },
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
	player:SetAttribute("Cash", profile.cash)
	player:SetAttribute("EquippedTool", profile.equippedTool)
	-- Owned_<toolId> lets the Shop show owned state; the profile stays the authority.
	for toolId, owned in profile.ownedTools do player:SetAttribute("Owned_" .. toolId, owned) end
end

function PlayerStateService.balance(profile: Types.Profile, currency: Types.Currency): number
	return if currency == "Cash" then profile.cash else profile.popcorn
end

-- Deducts a price from the named balance if it is covered. Must not yield: callers check
-- eligibility, then spend and grant in the same step. Returns false without changing anything.
function PlayerStateService.spend(profile: Types.Profile, currency: Types.Currency, amount: number): boolean
	assert(amount >= 0 and amount % 1 == 0, "Invalid price")
	if PlayerStateService.balance(profile, currency) < amount then return false end
	if currency == "Cash" then profile.cash -= amount else profile.popcorn -= amount end
	return true
end

function PlayerStateService.release(userId: number)
	profiles[userId] = nil
end

return PlayerStateService
