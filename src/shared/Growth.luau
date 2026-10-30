--!strict
local Types = require(script.Parent.Types)
local Growth = {}

-- Pure O(1) accrual per stalk, independent of online/offline time length.
-- No stored counter is also credited: the timestamp is the sole production source.
function Growth.yields(growthStartedAt: number, now: number, crop: Types.CropDefinition): number
	local elapsed = math.max(0, now - growthStartedAt)
	return math.min(crop.maxYields, math.floor(elapsed / crop.growthSeconds))
end

function Growth.progress(growthStartedAt: number, now: number, crop: Types.CropDefinition): number
	return math.clamp((now - growthStartedAt) / crop.growthSeconds, 0, 1)
end

return Growth
