--!strict
-- Prototype tuning, not final balance. Values are shared; rewards remain server-owned.
local Types = require(script.Parent.Types)
local crops: { [string]: Types.CropDefinition } = {
	Normal = { displayName = "Normal Corn", growthSeconds = 10, popcornValue = 1, maxYields = 3 },
}
local Config = {
	SchemaVersion = 1,
	Crops = crops,
	Starter = { cropId = "Normal", rows = 3, columns = 4, spacing = 5 },
	Manual = { range = 10, cooldownSeconds = 0.25 },
	Farm = { origin = Vector3.new(0, 0, 24), separation = 32, size = Vector3.new(20, 0.5, 20) },
	VisualUpdateSeconds = 0.25,
}

function Config.validate()
	for _, crop in Config.Crops do
		assert(crop.growthSeconds > 0 and crop.growthSeconds < math.huge, "Invalid growth duration")
		assert(crop.maxYields >= 1 and crop.maxYields % 1 == 0, "Invalid storage capacity")
		assert(crop.popcornValue >= 0 and crop.popcornValue % 1 == 0, "Invalid crop value")
	end
	assert(Config.Starter.rows >= 1 and Config.Starter.columns >= 1)
	assert(Config.Manual.range > 0 and Config.Manual.cooldownSeconds > 0)
end

return Config
