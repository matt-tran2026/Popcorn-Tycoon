--!strict
-- Land purchases from the farm's step-on pads (an Extra Row on one plot, or the next New Plot)
-- and farm upgrades from the Upgrades menu (Backpack for the player; Soil, Yield, Storage per plot).
-- Price, ownership, limits and balance are checked and committed in one unyielding step;
-- visuals follow the committed profile. Prices come from Pricing (they climb per purchase).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Money = require(Shared.Money)
local Pricing = require(Shared.Pricing)
local Growth = require(Shared.Growth)
local FarmUpgrades = require(Shared.FarmUpgrades)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local Looks = require(script.Parent.UpgradeVisuals)
local UpgradeService = {}
local lastRequest: { [number]: number } = {}

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

-- The land commits shared by pad purchases and the Studio-only Developer Panel (AdminService),
-- so both plant rows and plots through the same state and visual functions. Callers check
-- ownership, limits and (for purchases) payment first. Must not yield.
function UpgradeService.grantRow(player: Player, profile: Types.Profile, field: Types.Field)
	assert(field.rows < Config.layoutRows(), "Plot is full")
	field.rows += 1
	State.plantRow(field, field.rows, DateTime.now().UnixTimestampMillis / 1000)
	State.publish(player.UserId)
	Farms.plantRow(player.UserId, field.id, field.rows)
end

function UpgradeService.grantPlot(player: Player, profile: Types.Profile): Types.Field
	assert(Pricing.plotsBought(profile.fields) < Config.Upgrades.ExtraPlot.max, "Every plot is owned")
	local field = State.addPlot(profile, player.UserId, DateTime.now().UnixTimestampMillis / 1000)
	State.publish(player.UserId)
	Farms.addPlot(player.UserId, field.id)
	return field
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
	UpgradeService.grantRow(player, profile, field)
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
	UpgradeService.grantPlot(player, profile)
	return result(true, upgrade.displayName .. " ready to harvest!", price)
end

-- Sets a farm upgrade to `newLevel` and applies it: Soil/Storage changes settle every stalk of
-- the plot under the old rules and rebase it onto the new ones (Growth.rebase), then the state
-- is published and the looks follow. Shared by purchases (after the charge) and the Studio-only
-- Developer Panel; callers validate the id, scope, ownership and level. Must not yield.
function UpgradeService.applyLevel(player: Player, profile: Types.Profile, upgradeId: string, field: Types.Field?, newLevel: number)
	assert(newLevel == FarmUpgrades.clampLevel(upgradeId, newLevel), "Invalid upgrade level")
	local now = DateTime.now().UnixTimestampMillis / 1000
	if field then
		local oldRules = FarmUpgrades.fieldRules(field)
		local levels: any = field.upgrades
		levels[upgradeId] = newLevel
		local newRules = FarmUpgrades.fieldRules(field)
		if oldRules.growthSeconds ~= newRules.growthSeconds or oldRules.maxYields ~= newRules.maxYields then
			for _, stalk in field.stalks do
				stalk.growthStartedAt = Growth.rebase(stalk.growthStartedAt, now, oldRules, newRules)
			end
		end
	else
		local levels: any = profile.upgrades
		levels[upgradeId] = newLevel
	end
	State.publish(player.UserId)
	-- Visuals follow the committed state; they never change rewards.
	if field then Farms.applyFieldLook(player.UserId, field.id) else Looks.backpack(player.Character, newLevel) end
end

-- Buys the next level of a farm upgrade. The client names only the upgrade and, for field
-- upgrades, the plot; the server works out ownership, level, price and effect itself.
-- A repeated request is a separate purchase of the next level (each one is paid for), and
-- requests closer together than Config.UpgradeMenu.requestCooldownSeconds are refused.
-- Soil and Storage change a plot's growth rules, so every stalk on it is first settled under
-- the old rules and rebased onto the new ones (Growth.rebase) in the same unyielding step.
function UpgradeService.buyUpgrade(player: Player, upgradeId: unknown, fieldId: unknown): Types.ActionResult
	local clock = os.clock()
	local previous = lastRequest[player.UserId]
	if previous and clock - previous < Config.UpgradeMenu.requestCooldownSeconds then return result(false, "Too fast") end
	lastRequest[player.UserId] = clock
	if typeof(upgradeId) ~= "string" or not Config.FarmUpgrades[upgradeId] then return result(false, "Unknown upgrade") end
	local upgrade = Config.FarmUpgrades[upgradeId]
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	local field: Types.Field? = nil
	local level: number
	if upgrade.scope == "Global" then
		if fieldId ~= nil then return result(false, "Invalid plot") end
		level = FarmUpgrades.clampLevel(upgradeId, (profile.upgrades :: any)[upgradeId])
	else
		if typeof(fieldId) ~= "string" or #fieldId > 16 then return result(false, "Pick one of your plots") end
		field = profile.fields[fieldId]
		if not field or field.ownerUserId ~= player.UserId then return result(false, "Not your plot") end
		if not Config.Crops[field.cropId] then return result(false, "Invalid crop") end
		level = FarmUpgrades.clampLevel(upgradeId, (field.upgrades :: any)[upgradeId])
	end
	local price = FarmUpgrades.price(upgradeId, level)
	if not price then return result(false, upgrade.displayName .. " is maxed") end
	local short = shortfall(profile, upgrade.currency, price)
	if short then return short end
	-- No yields between the checks above and this commit.
	assert(State.spend(profile, upgrade.currency, price))
	local newLevel = level + 1
	UpgradeService.applyLevel(player, profile, upgradeId, field, newLevel)
	local response = result(true, upgrade.displayName .. " Lv " .. tostring(newLevel) .. "!", price)
	response.upgradeId, response.level = upgradeId, newLevel
	if field then response.fieldId = field.id end
	return response
end

function UpgradeService.release(userId: number)
	lastRequest[userId] = nil
end

return UpgradeService
