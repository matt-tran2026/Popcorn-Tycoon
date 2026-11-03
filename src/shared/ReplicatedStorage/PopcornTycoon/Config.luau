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
	-- Row 1 faces the stations at the front; purchased rows extend toward the back fence.
	Starter = { cropId = "Normal", rows = 6, layoutRows = 7, columns = 6, spacing = 5 },
	Manual = { range = 10, cooldownSeconds = 0.25 },
	Inventory = { capacity = 50 },
	-- Pieces arc out, then fly magnet-style to the owner wherever they are (no range).
	Microwave = {
		cookSeconds = 5, range = 10, pieces = 8,
		landSeconds = 0.7, flySeconds = 0.9, staggerSeconds = 0.08,
	},
	Upgrades = { ExtraRow = { displayName = "Extra Row", price = 100, range = 10 } },
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
	assert(whole(Config.Upgrades.ExtraRow.price), "Invalid upgrade price")
	local map, farm = Config.Map, Config.Farm
	assert(whole(map.slots) and map.slots >= 2, "Invalid farm slot count")
	assert(map.hubApothem + 20 <= map.entranceRadius, "Bridges need room between hub and farms")
	-- The widest side of a plot, measured from its entrance, must fit its share of the ring.
	local reach = farm.plotSize.X / 2 + math.abs(farm.plotOffset.X) + 4
	assert(reach <= map.entranceRadius * math.tan(math.pi / map.slots), "Neighboring farms would overlap")
end

return Config
