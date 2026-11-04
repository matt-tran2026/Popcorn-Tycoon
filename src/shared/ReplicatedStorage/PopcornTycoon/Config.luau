--!strict
-- Prototype tuning, not final balance. Values are shared; rewards remain server-owned.
local Types = require(script.Parent.Types)
local crops: { [string]: Types.CropDefinition } = {
	-- maxYields: growth cycles a stalk stores before it stops; cornPerYield: raw corn per cycle.
	Normal = { displayName = "Normal Corn", growthSeconds = 10, popcornValue = 1, maxYields = 3, cornPerYield = 1 },
}
-- Farm upgrades bought with Cash from the Upgrades menu (creator request, Nov 4 2026).
-- effects[level + 1] is the value at that level; the last entry is the max level.
--   Backpack: bag capacity in raw corn (absolute; level 0 must equal Inventory.capacity).
--   Soil: growth time in percent of the crop's base duration (Normal: 10/9/8/7/6 s).
--   Yield: extra corn per cycle on top of the crop's cornPerYield (Normal: 1..5).
--   Storage: extra stored cycles on top of the crop's maxYields (Normal: 3/4/5/7/10).
-- Price of the next level = Pricing.nice(base * growth ^ current level). Backpack starts at
-- $200 like the Sickle and the first row (about two full-bag trips); the field upgrades are
-- bought again for every plot. Totals per plot: Soil $12K, Yield $42.5K, Storage $29.9K;
-- Backpack $51.6K once. See docs/design/FARM_UPGRADES.md for the pacing check.
local farmUpgrades: { [string]: Types.FarmUpgradeDefinition } = {
	Backpack = {
		displayName = "Backpack Capacity", description = "Carry more raw corn", scope = "Global",
		effects = { 50, 100, 200, 400, 800 }, base = 200, growth = 6, currency = "Cash",
	},
	Soil = {
		displayName = "Soil Quality", description = "Richer soil grows corn faster", scope = "Field",
		effects = { 100, 90, 80, 70, 60 }, base = 300, growth = 3, currency = "Cash",
	},
	Yield = {
		displayName = "Corn Yield", description = "More corn every growth cycle", scope = "Field",
		effects = { 0, 1, 2, 3, 4 }, base = 500, growth = 4, currency = "Cash",
	},
	Storage = {
		displayName = "Stalk Storage", description = "Stalks hold more grown cycles", scope = "Field",
		effects = { 0, 1, 2, 4, 7 }, base = 750, growth = 3, currency = "Cash",
	},
}
-- Swung harvest tools. Hand picking ("Manual", Config.Manual) uses prompts and is always available.
-- reach/arcDegrees describe a flat sweep in front of the character; the server picks
-- the nearest ripe stalks inside it (ToolRules.pickTargets), up to maxTargets.
local tools: { [string]: Types.ToolDefinition } = {
	Sickle = {
		displayName = "Sickle", description = "Sweep up to 3 ripe stalks per swing",
		-- 60 was the first hypothesis, but one 6x6 pass fills the 50-corn bag ($100), so
		-- 200 keeps the target of about two full harvest-and-sell passes.
		price = 200, currency = "Cash",
		reach = 9, arcDegrees = 140, maxTargets = 3, cooldownSeconds = 0.6, yieldMultiplier = 1,
		-- Presentation timing, shared so the swing, snips and kernels line up.
		swingSeconds = 0.32, snipStaggerSeconds = 0.07, kernelFlySeconds = 0.45,
	},
}
local Config = {
	-- 3 since Nov 4 2026: numeric upgrade levels (profile.upgrades, field.upgrades).
	SchemaVersion = 3,
	Crops = crops,
	FarmUpgrades = farmUpgrades,
	-- Menu order. Requests are throttled per player; a growth cycle never gets shorter than
	-- minGrowthSeconds whatever the soil (guards future crops and tuning).
	FarmUpgradeOrder = { "Backpack", "Soil", "Yield", "Storage" },
	UpgradeMenu = { requestCooldownSeconds = 0.3 },
	Growth = { minSeconds = 1 },
	-- One plot = one cornfield. Every plot starts with baseRows planted and its bed reserves room
	-- for maxExtraRows more, bought from the row pad. Row 1 faces the stations at the front;
	-- purchased rows extend toward the back of the plot.
	Plot = { cropId = "Normal", columns = 6, baseRows = 6, maxExtraRows = 6, spacing = 5 },
	-- Each island holds a 3x3 grid of plots (creator request, Nov 4 2026). order lists the cells
	-- in purchase order as { gx, gz }: gx -1/0/1 = left/center/right seen from the entrance,
	-- gz 0/1/2 = front/middle/back. Plot 1 is the starter; the rest unlock nearest first.
	Grid = {
		gap = 6,
		order = { { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { 1, 1 }, { 0, 2 }, { -1, 2 }, { 1, 2 } },
	},
	Manual = { range = 10, cooldownSeconds = 0.25 },
	-- The base bag (Backpack level 0); FarmUpgrades.bagCapacity gives a player's real limit.
	Inventory = { capacity = 50 },
	-- Pieces arc out, then fly magnet-style to the owner wherever they are (no range).
	Microwave = {
		cookSeconds = 5, range = 10, pieces = 8,
		landSeconds = 0.7, flySeconds = 0.9, staggerSeconds = 0.08,
	},
	-- Economy model (prototype, Nov 3 2026): popcorn is the product, sold at the farm's stand
	-- for Cash; Cash is the spendable balance for tools and land. Every price names its
	-- currency (docs/design/FIRST_LOOP_SLICE.md). The creator renamed Coins to Cash on
	-- Nov 3 2026 (shown as $, see Money).
	Economy = { currencies = { Cash = true, Popcorn = true } :: { [string]: boolean } },
	-- Land is bought on step-on pads (Nov 4 2026). Prices climb after every purchase:
	-- price = base * growth ^ (already bought), rounded to 2 significant figures (Pricing).
	-- Tuned to the creator's stage table: the starter's 6 rows and plots 2-3 are Beginner
	-- ($0-100K); plots 4-9 are Early game ($100K-10M), the last ($8.5M) just before Rebirth 1
	-- at $10M. Rows are counted across all plots (54 max, $200 -> ~$520K); plots 25K -> 8.5M.
	-- These assume the planned bag/machine upgrades; today's ~$100 per bag trip is far below.
	Upgrades = {
		ExtraRow = { displayName = "Extra Row", base = 200, growth = 1.16, currency = "Cash" :: Types.Currency },
		ExtraPlot = { displayName = "New Plot", base = 25000, growth = 2.3, max = 8, currency = "Cash" :: Types.Currency },
	},
	-- A pad buys once per step-on: it re-arms after the player steps off (reach studs past its
	-- edge) and at least rearmSeconds later.
	Pads = { reach = 2, rearmSeconds = 1 },
	-- Sell stand: every popcorn in the balance converts to Cash at once (playtest hypothesis).
	Sell = { cashPerPopcorn = 2, range = 10 },
	-- Tools are bought only from the Shop menu, from anywhere; requests (buy/equip) are throttled per player.
	Shop = { requestCooldownSeconds = 0.25 },
	Tools = tools,
	-- Farms are authored in this canonical frame (entrance on -Z at Z = 0, field toward +Z),
	-- then turned onto a map slot. origin is the center of plot 1 (the front-center cell);
	-- plotOffset leads from it to the island center. Stations stand in a strip across the
	-- front, the 3x3 plot grid fills the rest (Config.cellOffset).
	Farm = {
		origin = Vector3.new(0, 0, 58),
		plotSize = Vector3.new(122, 0.5, 234), plotOffset = Vector3.new(0, 0, 59),
	},
	-- A hexagonal hub island with one bridge per farm slot. Farm entrances sit on a ring
	-- around the hub and face its center; each farm grows outward from its bridge.
	Map = {
		center = Vector3.new(0, 0, 0), slots = 6, hubApothem = 55, entranceRadius = 120,
		bridgeWidth = 10, waterLevel = -2, oceanSize = 1200,
	},
	VisualUpdateSeconds = 0.25,
}

-- Rows per plot bed, planted or not.
function Config.layoutRows(): number
	return Config.Plot.baseRows + Config.Plot.maxExtraRows
end

-- Footprint of one plot cell (bed plus edging) in studs.
function Config.cellSize(): Vector2
	local p = Config.Plot
	return Vector2.new(p.columns * p.spacing + 4, Config.layoutRows() * p.spacing + 4)
end

-- Offset from Config.Farm.origin (plot 1's center) to plot `plot`'s center, canonical frame.
-- The visitor's left (entering toward +Z) is +X.
function Config.cellOffset(plot: number): Vector3
	local cell = Config.Grid.order[plot]
	local size = Config.cellSize()
	return Vector3.new(-cell[1] * (size.X + Config.Grid.gap), 0, cell[2] * (size.Y + Config.Grid.gap))
end

local function whole(value: number): boolean
	return value >= 0 and value % 1 == 0 and value < 2 ^ 52
end

function Config.validate()
	for _, crop in Config.Crops do
		assert(crop.growthSeconds > 0 and crop.growthSeconds < math.huge, "Invalid growth duration")
		assert(crop.maxYields >= 1 and crop.maxYields % 1 == 0, "Invalid storage capacity")
		assert(whole(crop.popcornValue), "Invalid crop value")
		assert(whole(crop.cornPerYield) and crop.cornPerYield >= 1, "Invalid corn per cycle")
	end
	assert(#Config.FarmUpgradeOrder == 4, "Every farm upgrade needs a menu slot")
	for _, id in Config.FarmUpgradeOrder do
		local upgrade = Config.FarmUpgrades[id]
		assert(upgrade, "Missing farm upgrade " .. id)
		assert(upgrade.scope == "Global" or upgrade.scope == "Field", "Invalid upgrade scope " .. id)
		assert(#upgrade.effects >= 2, "Farm upgrade needs a level above 0: " .. id)
		for level = 1, #upgrade.effects do
			local value = upgrade.effects[level]
			assert(whole(value), "Invalid effect " .. id)
			-- Soil gets faster (smaller percent), everything else grows; never a no-op level.
			if level > 1 then
				local previous = upgrade.effects[level - 1]
				assert(if id == "Soil" then value < previous else value > previous, "Effects must improve every level: " .. id)
			end
		end
		assert(whole(upgrade.base) and upgrade.base >= 1 and upgrade.growth >= 1, "Invalid upgrade price " .. id)
		assert(Config.Economy.currencies[upgrade.currency], "Invalid upgrade currency " .. id)
	end
	local up = Config.FarmUpgrades
	assert(up.Backpack.scope == "Global" and up.Soil.scope == "Field" and up.Yield.scope == "Field" and up.Storage.scope == "Field", "Upgrade scopes changed")
	assert(up.Backpack.effects[1] == Config.Inventory.capacity, "Backpack level 0 must be the base bag")
	assert(up.Soil.effects[1] == 100 and up.Soil.effects[#up.Soil.effects] >= 1, "Soil percents must start at 100")
	assert(up.Yield.effects[1] == 0 and up.Storage.effects[1] == 0, "Level 0 must not change a crop")
	assert(Config.Growth.minSeconds > 0 and Config.UpgradeMenu.requestCooldownSeconds > 0, "Invalid growth/menu tuning")
	local plot = Config.Plot
	assert(Config.Crops[plot.cropId], "Invalid plot crop")
	assert(whole(plot.baseRows) and plot.baseRows >= 1 and whole(plot.columns) and plot.columns >= 1, "Invalid plot size")
	assert(whole(plot.maxExtraRows) and plot.spacing > 0, "Invalid plot rows")
	assert(#Config.Grid.order == Config.Upgrades.ExtraPlot.max + 1, "Grid must hold the starter plus every buyable plot")
	assert(Config.Manual.range > 0 and Config.Manual.cooldownSeconds > 0)
	assert(whole(Config.Inventory.capacity) and Config.Inventory.capacity >= 1, "Invalid inventory capacity")
	local microwave = Config.Microwave
	assert(microwave.cookSeconds > 0 and microwave.range > 0, "Invalid microwave timing/range")
	assert(whole(microwave.pieces) and microwave.pieces >= 1, "Invalid popcorn piece count")
	assert(microwave.landSeconds > 0 and microwave.flySeconds > 0 and microwave.staggerSeconds >= 0, "Invalid popcorn flight timing")
	for id, upgrade in { ExtraRow = Config.Upgrades.ExtraRow, ExtraPlot = Config.Upgrades.ExtraPlot } :: { [string]: any } do
		assert(whole(upgrade.base) and upgrade.base >= 1 and upgrade.growth >= 1, "Invalid upgrade price " .. id)
		assert(Config.Economy.currencies[upgrade.currency], "Invalid upgrade currency " .. id)
	end
	assert(Config.Pads.reach >= 0 and Config.Pads.rearmSeconds > 0, "Invalid pad tuning")
	assert(whole(Config.Sell.cashPerPopcorn) and Config.Sell.cashPerPopcorn >= 1 and Config.Sell.range > 0, "Invalid sell rate")
	for id, tool in Config.Tools do
		assert(Config.Economy.currencies[tool.currency], "Invalid tool currency " .. id)
		assert(whole(tool.price) and tool.reach > 0 and tool.arcDegrees > 0 and tool.arcDegrees <= 360, "Invalid tool " .. id)
		assert(whole(tool.maxTargets) and tool.maxTargets >= 1 and tool.cooldownSeconds > 0, "Invalid tool " .. id)
		assert(whole(tool.yieldMultiplier) and tool.yieldMultiplier >= 1, "Invalid tool " .. id)
	end
	assert(Config.Tools.Sickle.cooldownSeconds >= (Config.Tools.Sickle.swingSeconds or 0), "Sickle swings must not overlap")
	local map, farm = Config.Map, Config.Farm
	assert(whole(map.slots) and map.slots >= 2, "Invalid farm slot count")
	assert(map.hubApothem + 20 <= map.entranceRadius, "Bridges need room between hub and farms")
	-- The widest side of a plot, measured from its entrance, must fit its share of the ring.
	local reach = farm.plotSize.X / 2 + math.abs(farm.plotOffset.X) + 4
	assert(reach <= map.entranceRadius * math.tan(math.pi / map.slots), "Neighboring farms would overlap")
	-- Every plot cell, plus room for the station strip in front, must fit inside the island.
	local half, size = farm.plotSize / 2, Config.cellSize()
	local center = farm.origin + farm.plotOffset
	for i = 1, #Config.Grid.order do
		local c = farm.origin + Config.cellOffset(i)
		assert(math.abs(c.X - center.X) + size.X / 2 <= half.X - 2, "Plot " .. i .. " leaves the island sideways")
		assert(c.Z + size.Y / 2 <= center.Z + half.Z - 2, "Plot " .. i .. " leaves the island at the back")
	end
	assert(farm.origin.Z - size.Y / 2 - (center.Z - half.Z) >= 24, "No room for the station strip")
end

return Config
