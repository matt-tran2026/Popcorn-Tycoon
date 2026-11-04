--!strict
local Types = require(script.Parent.Types)
local Growth = {}

-- Absorbs float error when a timestamp is set to exactly n cycles ago (now - n * seconds can
-- come back a hair short with Unix-second timestamps). Far below one frame of growth.
local EPSILON = 1e-6

-- Pure O(1) accrual per stalk, independent of online/offline time length.
-- No stored counter is also credited: the timestamp is the sole production source.
-- `rules` are the field's effective rules (FarmUpgrades.rules); a bare crop definition is
-- the unupgraded case. Returns completed growth cycles ("yields"), capped by storage.
function Growth.yields(growthStartedAt: number, now: number, rules: Types.GrowthRules): number
	local elapsed = math.max(0, now - growthStartedAt)
	return math.min(rules.maxYields, math.floor(elapsed / rules.growthSeconds + EPSILON))
end

-- Raw corn ready on a stalk before tool multipliers: cycles x corn per cycle.
function Growth.corn(growthStartedAt: number, now: number, rules: Types.GrowthRules): number
	return Growth.yields(growthStartedAt, now, rules) * rules.cornPerYield
end

function Growth.progress(growthStartedAt: number, now: number, rules: Types.GrowthRules): number
	return math.clamp((now - growthStartedAt) / rules.growthSeconds, 0, 1)
end

-- Re-expresses a stalk's timestamp when its field's rules change (Soil or Storage upgrade),
-- settled at `now` under the old rules first:
-- * completed cycles carry over unchanged (capped by the new storage, never raised);
-- * the unfinished cycle carries over as the same fraction of a cycle, so faster soil neither
--   loses progress nor pays out time already spent at the old rate;
-- * a stalk that was full had stopped growing, so it keeps no partial progress and a bigger
--   storage starts its next cycle now (growth discarded while full is never reclaimed).
-- A timestamp in the future (clock skew) is left alone.
function Growth.rebase(growthStartedAt: number, now: number, old: Types.GrowthRules, new: Types.GrowthRules): number
	if now <= growthStartedAt then return growthStartedAt end
	local ready = Growth.yields(growthStartedAt, now, old)
	local fraction = 0
	if ready < old.maxYields then
		-- Capped below 1 so the carried fraction can never round up into a whole cycle.
		fraction = math.clamp((now - growthStartedAt) / old.growthSeconds - ready, 0, 0.999)
	end
	local kept = math.min(ready, new.maxYields)
	if kept < ready then fraction = 0 end
	return now - (kept + fraction) * new.growthSeconds
end

return Growth
