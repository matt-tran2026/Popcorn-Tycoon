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
		-- Collection identity (docs/design/TOOL_COLLECTION.md). behavior names the harvesting
		-- family HarvestService uses; ArcSweep is ToolRules.pickTargets.
		rarity = "Common", behavior = "ArcSweep",
		-- 60 was the first hypothesis, but one 6x6 pass fills the 50-corn bag ($100), so
		-- 200 keeps the target of about two full harvest-and-sell passes.
		price = 200, currency = "Cash",
		reach = 9, arcDegrees = 140, maxTargets = 3, cooldownSeconds = 0.6, yieldMultiplier = 1,
		-- Presentation timing, shared so the swing, snips and kernels line up.
		swingSeconds = 0.32, snipStaggerSeconds = 0.07, kernelFlySeconds = 0.45,
	},
	-- Catalog #2 (creator, Nov 5 2026): 1 stalk per snip, 0.12 s, 8 studs, 1x. Faster than
	-- hands (0.25 s) but shorter reach (hands 10); one stalk per action. SingleTarget picks
	-- the nearest ripe stalk inside a narrow cone, so aim matters. Price is a first guess
	-- under the Sickle's $200, as the first tool most players buy.
	CornClippers = {
		displayName = "Corn Clippers", description = "Snip 1 ripe stalk per click, super fast",
		rarity = "Common", behavior = "SingleTarget",
		price = 100, currency = "Cash",
		reach = 8, arcDegrees = 90, maxTargets = 1, cooldownSeconds = 0.12, yieldMultiplier = 1,
		swingSeconds = 0.12, snipStaggerSeconds = 0,
	},
	-- Catalog #3 (creator, Nov 5 2026): 3 stalks, 0.8 s, 11 studs, 1x, narrow forward thrust.
	-- LineHarvest (ToolRules.pickTargets) takes ripe stalks in a straight lane ahead, nearest
	-- first. Rows are Config.Plot.spacing (5) apart, so a 4-stud lane only ever covers one row
	-- and a full 3-stalk thrust needs the first stalk within 1 stud (positioning skill). Price
	-- is a first guess between the Clippers ($100) and the Sickle ($200).
	Pitchfork = {
		displayName = "Pitchfork", description = "Thrust through up to 3 ripe stalks in a line",
		rarity = "Common", behavior = "LineHarvest",
		price = 150, currency = "Cash",
		reach = 11, laneWidth = 4, maxTargets = 3, cooldownSeconds = 0.8, yieldMultiplier = 1,
		-- The stab reaches the corn at the Thrust clip's Hit marker; snips then run down the row.
		swingSeconds = 0.42, snipStaggerSeconds = 0.06,
	},
	-- Catalog #4 (creator, Nov 5 2026): 2 stalks, 0.45 s, 14 studs, 1x, forward hook and pull.
	-- PullHarvest takes the 2 nearest ripe stalks in a long, fairly narrow forward cone (the
	-- arc rule), so it reaches rows the other Common tools can't without walking up to them.
	-- Hook Pull is presentation: the client flies each confirmed ear back to the player.
	-- Price is a first guess between the Pitchfork ($150) and the Sickle ($200).
	HarvestHook = {
		displayName = "Harvest Hook", description = "Hook 2 ripe stalks from far away and pull them in",
		rarity = "Common", behavior = "PullHarvest",
		price = 175, currency = "Cash",
		reach = 14, arcDegrees = 60, maxTargets = 2, cooldownSeconds = 0.45, yieldMultiplier = 1,
		-- The hook bites at the Swing clip's Hit marker; the ears then fly back one after the other.
		swingSeconds = 0.42, snipStaggerSeconds = 0.06,
	},
	-- Catalog: Twin Sickles (Uncommon; creator, Nov 6 2026): 4 stalks, 0.55 s, 10 studs, 1x,
	-- raw corn, alternating left/right arcs. Each hand's 110 degree arc is centred 30 degrees
	-- toward that hand (right: from 85 degrees right of facing to 25 left), so the corn on the
	-- side you favour comes off on alternate swings. Combo Sweep: the 3rd successful swing in a row
	-- (each within 1.6 s of the last hit) spins through 360 degrees at the same reach. A miss
	-- or a pause ends the streak: that is the positioning weakness. Price is a first guess,
	-- 2.5x the Sickle ($200), as the first Uncommon.
	TwinSickles = {
		displayName = "Twin Sickles", description = "Slash 4 stalks, left then right; every 3rd hit in a row spins a full circle",
		rarity = "Uncommon", behavior = "ArcSweep",
		price = 500, currency = "Cash",
		reach = 10, arcDegrees = 110, sideDegrees = 30, maxTargets = 4, cooldownSeconds = 0.55, yieldMultiplier = 1,
		combo = { every = 3, arcDegrees = 360, windowSeconds = 1.6 },
		-- Each hand's slash; the Combo clip (the spin) has its own length within the cooldown.
		swingSeconds = 0.3, snipStaggerSeconds = 0.04,
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
		assert(whole(tool.price) and tool.reach > 0, "Invalid tool " .. id)
		-- Each family needs its own shape: an arc, or a lane narrower than a row gap.
		if tool.behavior == "LineHarvest" then
			local width = tool.laneWidth
			assert(width and width > 0 and width < Config.Plot.spacing * 2, "LineHarvest needs a laneWidth under two row gaps: " .. id)
		else
			local arc = tool.arcDegrees
			assert(arc and arc > 0 and arc <= 360, "Invalid tool arc " .. id)
		end
		assert(whole(tool.maxTargets) and tool.maxTargets >= 1 and tool.cooldownSeconds > 0, "Invalid tool " .. id)
		assert(whole(tool.yieldMultiplier) and tool.yieldMultiplier >= 1, "Invalid tool " .. id)
		assert(tool.behavior == "ArcSweep" or tool.behavior == "SingleTarget" or tool.behavior == "LineHarvest"
			or tool.behavior == "PullHarvest", "Unimplemented tool behavior " .. id)
		assert(tool.behavior ~= "SingleTarget" or tool.maxTargets == 1, "SingleTarget tools cut one stalk: " .. id)
		assert(tool.cooldownSeconds >= (tool.swingSeconds or 0), "Swings must not overlap: " .. id)
		-- Alternating tools: the side turn keeps each hand's arc in front, and a combo is a
		-- wider arc that can only be reached by swinging again before the window closes.
		if tool.sideDegrees ~= nil or tool.combo ~= nil then
			assert(tool.behavior == "ArcSweep", "Only ArcSweep tools alternate hands: " .. id)
			local side = tool.sideDegrees or 0
			assert(side >= 0 and side <= 90, "sideDegrees must be 0-90: " .. id)
		end
		local combo = tool.combo
		if combo then
			assert(whole(combo.every) and combo.every >= 2, "A combo needs at least 2 swings: " .. id)
			assert(combo.arcDegrees > (tool.arcDegrees or 0) and combo.arcDegrees <= 360, "A combo arc must be wider: " .. id)
			assert(combo.windowSeconds > tool.cooldownSeconds, "The combo window must outlast a cooldown: " .. id)
		end
	end
	-- Every tool has a presentation entry, and a swing clip lasts exactly as long as its swing.
	local ToolPresentation = require(script.Parent.ToolPresentation)
	local toolIds = {}
	for id in Config.Tools do table.insert(toolIds, id) end
	ToolPresentation.validate(toolIds)
	for id, tool in Config.Tools do
		local look = assert(ToolPresentation.get(id))
		assert(look.rarity == tool.rarity, "Rarity differs between Config and ToolPresentation: " .. id)
		-- Swing and its alternate (played on every other action) both last exactly one swing.
		for _, name in { "Swing", "SwingAlt" } do
			local clip = look.clips[name]
			assert(not clip or not tool.swingSeconds or math.abs(clip.seconds - tool.swingSeconds) < 1e-6, name .. " clip length must equal swingSeconds: " .. id)
		end
		-- An alternating tool swings each hand (Swing right, SwingAlt left); a combo spins.
		if tool.sideDegrees ~= nil or tool.combo ~= nil then
			assert(look.clips.Swing and look.clips.SwingAlt and look.model.offhand, "Alternating tools need both hands' clips and an offhand: " .. id)
		end
		if tool.combo then
			local spin = look.clips.Combo
			assert(spin and spin.seconds <= tool.cooldownSeconds, "Combo clip missing or longer than the cooldown: " .. id)
		end
	end
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
