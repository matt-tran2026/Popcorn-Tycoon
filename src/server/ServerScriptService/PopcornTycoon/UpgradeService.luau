--!strict
-- Land purchases from the farm's step-on pads: an Extra Row on one plot, or the next New Plot.
-- Price, ownership, limits and balance are checked and committed in one unyielding step;
-- visuals follow the committed profile. Prices come from Pricing (they climb per purchase).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Money = require(Shared.Money)
local Pricing = require(Shared.Pricing)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local UpgradeService = {}

local function result(ok: boolean, reason: string, amount: number?): Types.ActionResult
	return { ok = ok, reason = reason, amount = amount or 0 }
end

-- The player must be standing on (or right beside) the pad they bought from.
local function standingOn(player: Player, pad: Part?): string?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not pad or not root or not root:IsA("BasePart") then return "Character unavailable" end
	local position = root.Position
	if position ~= position or not Farms.onPad(pad, position, 2) then return "Too far away" end
	return nil
end

local function shortfall(profile: Types.Profile, currency: Types.Currency, price: number): Types.ActionResult?
	local short = price - State.balance(profile, currency)
	if short <= 0 then return nil end
	local hint = if currency == "Cash" then " · sell popcorn at the stand" else ""
	return result(false, "Need " .. Money.price(currency, short) .. " more" .. hint)
end

function UpgradeService.buyRow(player: Player, fieldId: unknown): Types.ActionResult
	if typeof(fieldId) ~= "string" then return result(false, "Invalid plot") end
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	local field = profile.fields[fieldId]
	if not field or field.ownerUserId ~= player.UserId then return result(false, "Not your plot") end
	if field.rows >= Config.layoutRows() then return result(false, "This plot is full") end
	local problem = standingOn(player, Farms.rowPad(player.UserId, fieldId))
	if problem then return result(false, problem) end
	local upgrade = Config.Upgrades.ExtraRow
	local price = Pricing.rowPrice(profile.fields)
	local short = shortfall(profile, upgrade.currency, price)
	if short then return short end
	-- No yields between the checks above and this commit.
	assert(State.spend(profile, upgrade.currency, price))
	field.rows += 1
	State.plantRow(field, field.rows, DateTime.now().UnixTimestampMillis / 1000)
	State.publish(player.UserId)
	Farms.plantRow(player.UserId, fieldId, field.rows)
	return result(true, upgrade.displayName .. " planted!", price)
end

function UpgradeService.buyPlot(player: Player): Types.ActionResult
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	local upgrade = Config.Upgrades.ExtraPlot
	if Pricing.plotsBought(profile.fields) >= upgrade.max then return result(false, "Every plot is yours") end
	local problem = standingOn(player, Farms.plotPad(player.UserId))
	if problem then return result(false, problem) end
	local price = Pricing.plotPrice(profile.fields)
	local short = shortfall(profile, upgrade.currency, price)
	if short then return short end
	-- No yields between the checks above and this commit.
	assert(State.spend(profile, upgrade.currency, price))
	local field = State.addPlot(profile, player.UserId, DateTime.now().UnixTimestampMillis / 1000)
	State.publish(player.UserId)
	Farms.addPlot(player.UserId, field.id)
	return result(true, upgrade.displayName .. " ready to harvest!", price)
end

return UpgradeService
