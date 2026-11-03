--!strict
-- Prototype tuning, not final balance. Values are shared; rewards remain server-owned.
local Types = require(script.Parent.Types)
local crops: { [string]: Types.CropDefinition } = {
	Normal = { displayName = "Normal Corn", growthSeconds = 10, popcornValue = 1, maxYields = 3 },
}
local Config = {
	SchemaVersion = 1,
	Crops = crops,
	-- layoutRows reserves bed space for purchasable rows; only `rows` start planted.
	Starter = { cropId = "Normal", rows = 3, layoutRows = 4, columns = 4, spacing = 5 },
	Manual = { range = 10, cooldownSeconds = 0.25 },
	Inventory = { capacity = 50 },
	-- Pieces arc out, then fly magnet-style to the owner wherever they are (no range).
	Microwave = {
		cookSeconds = 5, range = 10, pieces = 8,
		landSeconds = 0.7, flySeconds = 0.9, staggerSeconds = 0.08,
	},
	Upgrades = { ExtraRow = { displayName = "Extra Row", price = 100, range = 10 } },
	Farm = {
		origin = Vector3.new(12, 0, 36), separation = 72, size = Vector3.new(22, 0.5, 23),
		plotSize = Vector3.new(60, 0.5, 54), plotOffset = Vector3.new(-12, 0, 0),
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
	assert(whole(Config.Upgrades.ExtraRow.price), "Invalid upgrade price")
	assert(Config.Farm.separation >= Config.Farm.plotSize.X + 8, "Plots need a clear expansion/service gap")
end

return Config
