--!strict
-- Display formatting for balances and prices. Cash is the only spendable currency (it replaced
-- Coins on Nov 3 2026); Popcorn is the product balance. Formatting never changes an amount.
local Types = require(script.Parent.Types)
local Money = {}
local suffixes = { "K", "M", "B", "T", "Qd" }

-- 999 -> "999", 6114 -> "6.11K", 61140 -> "61.1K", 2500000 -> "2.5M". Truncated, never rounded
-- up, so a balance is never shown as more than the player has.
function Money.short(amount: number): string
	local value = math.floor(amount)
	if value < 1000 then return tostring(value) end
	local scaled, tier = value, 0
	while scaled >= 1000 and tier < #suffixes do
		scaled /= 1000
		tier += 1
	end
	local digits = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	local factor = 10 ^ digits
	-- Truncate from the whole amount: 2300 * 100 / 1000 = 230 exactly, where 2.3 * 100 would be
	-- 229.99999 in floating point and show $2.29K (fixed Nov 4 2026).
	local kept = math.floor(value * factor / 1000 ^ tier + 1e-9)
	local text = string.format("%." .. tostring(digits) .. "f", kept / factor)
	if digits > 0 then
		text = (string.gsub(text, "0+$", ""))
		text = (string.gsub(text, "%.$", ""))
	end
	return text .. suffixes[tier]
end

function Money.cash(amount: number): string
	return "$" .. Money.short(amount)
end

-- A price in the balance it is paid from: "$200" or "40 popcorn".
function Money.price(currency: Types.Currency, amount: number): string
	return if currency == "Cash" then Money.cash(amount) else Money.short(amount) .. " popcorn"
end

return Money
