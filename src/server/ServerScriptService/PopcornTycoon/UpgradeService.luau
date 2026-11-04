--!strict
-- Upgrade purchases. Price, ownership and balance are checked and committed in one
-- unyielding step; visuals follow the committed profile.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Money = require(Shared.Money)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local UpgradeService = {}

local function result(ok: boolean, reason: string, amount: number?): Types.ActionResult
	return { ok = ok, reason = reason, amount = amount or 0 }
end

function UpgradeService.buyExtraRow(player: Player, ownerUserId: unknown): Types.ActionResult
	if typeof(ownerUserId) ~= "number" or ownerUserId ~= player.UserId then return result(false, "Not your farm") end
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	local upgrade = Config.Upgrades.ExtraRow
	local field = profile.fields.Starter
	if profile.upgrades.ExtraRow or field.rows >= Config.Starter.layoutRows then return result(false, "Already owned") end
	local sign = Farms.rowSign(player.UserId)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not sign or not root or not root:IsA("BasePart") then return result(false, "Character unavailable") end
	local distance = (root.Position - sign.Position).Magnitude
	if distance ~= distance or distance > upgrade.range + 2 then return result(false, "Too far away") end
	-- Paid from the configured balance (Cash since Nov 3 2026).
	local short = upgrade.price - State.balance(profile, upgrade.currency)
	if short > 0 then
		local hint = if upgrade.currency == "Cash" then " · sell popcorn at the stand" else ""
		return result(false, "Need " .. Money.price(upgrade.currency, short) .. " more" .. hint)
	end
	-- No yields between the checks above and this commit.
	assert(State.spend(profile, upgrade.currency, upgrade.price))
	profile.upgrades.ExtraRow = true
	field.rows += 1
	State.plantRow(field, field.rows, DateTime.now().UnixTimestampMillis / 1000)
	State.publish(player.UserId)
	Farms.plantRow(player.UserId, field.rows)
	return result(true, upgrade.displayName .. " planted!", upgrade.price)
end

return UpgradeService
