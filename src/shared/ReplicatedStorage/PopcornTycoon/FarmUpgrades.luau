--!strict
-- Pure rules for the four farm upgrades (Config.FarmUpgrades), shared so the Upgrades menu
-- shows exactly what the server applies. The server alone owns levels and purchases.
--   bag capacity  = Backpack effect at the player's level
--   growth time   = max(Config.Growth.minSeconds, crop.growthSeconds * Soil% / 100)
--   stored cycles = crop.maxYields + Storage bonus
--   corn / cycle  = crop.cornPerYield + Yield bonus
--   max corn on a stalk = corn per cycle x stored cycles (before tool multipliers)
-- The current Yield level applies to every stored cycle, including cycles grown before it
-- was bought (prototype rule, Nov 4 2026).
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)
local Pricing = require(script.Parent.Pricing)
local FarmUpgrades = {}

-- A stored or replicated level as a whole number in range; anything malformed counts as 0.
function FarmUpgrades.clampLevel(id: string, level: unknown): number
	local upgrade = Config.FarmUpgrades[id]
	if not upgrade or typeof(level) ~= "number" or level ~= level then return 0 end
	return math.clamp(math.floor(level), 0, #upgrade.effects - 1)
end

function FarmUpgrades.maxLevel(id: string): number
	return #Config.FarmUpgrades[id].effects - 1
end

function FarmUpgrades.effect(id: string, level: number): number
	return Config.FarmUpgrades[id].effects[FarmUpgrades.clampLevel(id, level) + 1]
end

-- Price of the level after `level`, or nil when maxed.
function FarmUpgrades.price(id: string, level: number): number?
	return Pricing.upgradePrice(Config.FarmUpgrades[id], level)
end

function FarmUpgrades.defaultField(): Types.FieldUpgradeLevels
	return { Soil = 0, Yield = 0, Storage = 0 }
end

function FarmUpgrades.defaultGlobal(): Types.GlobalUpgradeLevels
	return { Backpack = 0 }
end

function FarmUpgrades.bagCapacity(levels: Types.GlobalUpgradeLevels): number
	return FarmUpgrades.effect("Backpack", levels.Backpack)
end

-- A crop's growth rules with a field's upgrade levels applied.
function FarmUpgrades.rules(crop: Types.CropDefinition, levels: Types.FieldUpgradeLevels): Types.GrowthRules
	return {
		growthSeconds = math.max(Config.Growth.minSeconds, crop.growthSeconds * FarmUpgrades.effect("Soil", levels.Soil) / 100),
		maxYields = crop.maxYields + FarmUpgrades.effect("Storage", levels.Storage),
		cornPerYield = crop.cornPerYield + FarmUpgrades.effect("Yield", levels.Yield),
	}
end

function FarmUpgrades.fieldRules(field: Types.Field): Types.GrowthRules
	return FarmUpgrades.rules(Config.Crops[field.cropId], field.upgrades)
end

local function seconds(value: number): string
	local text = string.format("%.1f", value)
	return (string.gsub(text, "%.0$", "")) .. " s"
end

-- What an upgrade gives at `level`, in words, for `crop` (field upgrades). Display only.
function FarmUpgrades.describe(id: string, level: number, crop: Types.CropDefinition?): string
	local base = crop or Config.Crops[Config.Plot.cropId]
	if id == "Backpack" then
		return tostring(FarmUpgrades.effect(id, level)) .. " corn"
	elseif id == "Soil" then
		local rules = FarmUpgrades.rules(base, { Soil = level, Yield = 0, Storage = 0 })
		return seconds(rules.growthSeconds) .. " per cycle"
	elseif id == "Yield" then
		local corn = base.cornPerYield + FarmUpgrades.effect(id, level)
		return tostring(corn) .. " corn per cycle"
	else
		local cycles = base.maxYields + FarmUpgrades.effect(id, level)
		return tostring(cycles) .. " cycles stored"
	end
end

return FarmUpgrades
