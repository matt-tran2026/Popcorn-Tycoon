--!strict
-- Land prices. Both counts are derived from a profile's fields (profile.fields), so whatever
-- resets the fields (a future rebirth) resets the prices with them. price = base * growth ^ bought.
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)
local Pricing = {}

-- Rounds to 2 significant figures: 232 -> 230, 57500 -> 58000, 8512061 -> 8500000.
function Pricing.nice(amount: number): number
	if amount < 100 then return math.max(1, math.floor(amount + 0.5)) end
	local step = 10 ^ (math.floor(math.log10(amount)) - 1)
	-- The epsilon keeps float noise (57499.9999 for 25000 * 2.3) rounding half up.
	return math.floor(amount / step + 0.5 + 1e-6) * step
end

type Fields = { [string]: Types.Field }

-- Extra rows bought across every plot.
function Pricing.rowsBought(fields: Fields): number
	local total = 0
	for _, field in fields do total += field.rows - Config.Plot.baseRows end
	return total
end

-- Plots bought beyond the starter.
function Pricing.plotsBought(fields: Fields): number
	local count = 0
	for _ in fields do count += 1 end
	return count - 1
end

function Pricing.rowPrice(fields: Fields): number
	local upgrade = Config.Upgrades.ExtraRow
	return Pricing.nice(upgrade.base * upgrade.growth ^ Pricing.rowsBought(fields))
end

function Pricing.plotPrice(fields: Fields): number
	local upgrade = Config.Upgrades.ExtraPlot
	return Pricing.nice(upgrade.base * upgrade.growth ^ Pricing.plotsBought(fields))
end

return Pricing
