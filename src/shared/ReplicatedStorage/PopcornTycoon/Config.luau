--!strict
-- Prototype tuning, not final balance. Values are shared; rewards remain server-owned.
local Types = require(script.Parent.Types)
local crops: { [string]: Types.CropDefinition } = {
	Normal = { displayName = "Normal Corn", growthSeconds = 10, popcornValue = 1, maxYields = 3 },
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
	SchemaVersion = 1,
	Crops = crops,
	-- layoutRows reserves bed space for purchasable rows; only `rows` start planted.
	-- Row 1 faces the stations at the front; purchased rows extend toward the back fence.
	Starter = { cropId = "Normal", rows = 6, layoutRows = 7, columns = 6, spacing = 5 },
	Manual = { range = 10, cooldownSeconds = 0.25 },
	Inventory = { capacity = 50 },
	-- Pieces arc out, then fly magnet-style to the owner wherever they are (no range).
	Microwave = {
		cookSeconds = 5, range = 10, pieces = 8,
		landSeconds = 0.7, flySeconds = 0.9, staggerSeconds = 0.08,
	},
	-- Economy model (prototype, Nov 3 2026): popcorn is the product, sold at the farm's stand
	-- for Cash; Cash is the spendable balance for tools and land. Every price names its
	-- currency (docs/design/FIRST_LOOP_SLICE.md). Extra Row moved from 100 Popcorn to the
	-- spendable balance on the creator's request (Nov 3 2026); 200 keeps the same two full-bag
	-- passes. The creator renamed Coins to Cash the same day (shown as $, see Money).
	Economy = { currencies = { Cash = true, Popcorn = true } :: { [string]: boolean } },
	Upgrades = { ExtraRow = { displayName = "Extra Row", price = 200, currency = "Cash" :: Types.Currency, range = 10 } },
	-- Sell stand: every popcorn in the balance converts to Cash at once (playtest hypothesis).
	Sell = { cashPerPopcorn = 2, range = 10 },
	-- Tools are bought only from the Shop menu, from anywhere; requests (buy/equip) are throttled per player.
	Shop = { requestCooldownSeconds = 0.25 },
	Tools = tools,
	-- Farms are authored in this canonical frame (entrance on -Z, field toward +Z), then
	-- turned onto a map slot. origin is the starter field center; plotOffset leads from it
	-- to the plot center. The field sits back-right, its expansion lawn back-left, the stations up front.
	Farm = {
		origin = Vector3.new(0, 0, 53.5),
		plotSize = Vector3.new(82, 0.5, 72), plotOffset = Vector3.new(19, 0, -8.5),
	},
	-- A hexagonal hub island with one bridge per farm slot. Farm entrances sit on a ring
	-- around the hub and face its center; each farm grows outward from its bridge.
	Map = {
		center = Vector3.new(0, 0, 0), slots = 6, hubApothem = 55, entranceRadius = 115,
		bridgeWidth = 10, waterLevel = -2, oceanSize = 1200,
	},
	VisualUpdateSeconds = 0.25,
}

local function whole(value: number): boolean
	return value >= 0 and value % 1 == 0 and value < 2 ^ 52
end

function Config.validate()
	for _, crop in Config.Crops do
		assert(crop.growthSeconds > 0 and crop.growthSeconds < math.huge, "Invalid growth duration")
		assert(crop.maxYields >= 1 and crop.maxYields % 1 == 0, "Invalid storage capacity")
		assert(whole(crop.popcornValue), "Invalid crop value")
	end
	assert(Config.Starter.rows >= 1 and Config.Starter.columns >= 1)
	assert(Config.Starter.layoutRows == Config.Starter.rows + 1, "Layout must reserve exactly the Extra Row")
	assert(Config.Manual.range > 0 and Config.Manual.cooldownSeconds > 0)
	assert(whole(Config.Inventory.capacity) and Config.Inventory.capacity >= 1, "Invalid inventory capacity")
	local microwave = Config.Microwave
	assert(microwave.cookSeconds > 0 and microwave.range > 0, "Invalid microwave timing/range")
	assert(whole(microwave.pieces) and microwave.pieces >= 1, "Invalid popcorn piece count")
	assert(microwave.landSeconds > 0 and microwave.flySeconds > 0 and microwave.staggerSeconds >= 0, "Invalid popcorn flight timing")
	assert(whole(Config.Upgrades.ExtraRow.price) and Config.Economy.currencies[Config.Upgrades.ExtraRow.currency], "Invalid upgrade price")
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
end

return Config
