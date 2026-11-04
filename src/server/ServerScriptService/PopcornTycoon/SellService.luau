--!strict
-- The sell stand turns the whole popcorn balance into Cash in one unyielding step.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Money = require(Shared.Money)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local SellService = {}

local function result(ok: boolean, reason: string, amount: number?): Types.ActionResult
	return { ok = ok, reason = reason, amount = amount or 0 }
end

-- Shows the expected payout on the stand's prompt before the player commits.
function SellService.refresh(userId: number)
	local profile = State.get(userId)
	local stand = Farms.sellStand(userId)
	local sell = if stand then stand:FindFirstChild("Sell") :: ProximityPrompt? else nil
	if not profile or not sell then return end
	sell.ObjectText = if profile.popcorn > 0
		then tostring(profile.popcorn) .. " popcorn → " .. Money.cash(profile.popcorn * Config.Sell.cashPerPopcorn)
		else "No popcorn yet"
end

function SellService.sell(player: Player, ownerUserId: unknown): Types.ActionResult
	if typeof(ownerUserId) ~= "number" or ownerUserId ~= player.UserId then return result(false, "Not your stand") end
	local profile = State.get(player.UserId)
	local stand = Farms.sellStand(player.UserId)
	if not profile or not stand then return result(false, "Profile unavailable") end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then return result(false, "Character unavailable") end
	local distance = (root.Position - stand.Position).Magnitude
	if distance ~= distance or distance > Config.Sell.range + 2 then return result(false, "Too far away") end
	local sold = profile.popcorn
	if sold <= 0 then return result(false, "No popcorn to sell · pop some corn first") end
	local earned = sold * Config.Sell.cashPerPopcorn
	-- No yields between the checks above and this commit.
	profile.popcorn = 0
	profile.cash += earned
	State.publish(player.UserId)
	SellService.refresh(player.UserId)
	return result(true, "Sold " .. tostring(sold) .. " popcorn", earned)
end

return SellService
