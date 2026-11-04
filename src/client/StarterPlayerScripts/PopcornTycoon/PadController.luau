--!strict
-- Land purchase pads (built by FarmService, bought by stepping on them). Your own pads glow
-- green while you can afford them and red while you can't; other players' pads are hidden.
-- Purely local presentation; the server prices and validates every purchase.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local PadController = {}
local AFFORD, SHORT = Color3.fromRGB(80, 220, 100), Color3.fromRGB(230, 72, 60)
local GOLD, DIM = Color3.fromRGB(255, 226, 74), Color3.fromRGB(255, 150, 140)

local function isPad(object: Instance): boolean
	return object:IsA("BasePart") and typeof(object:GetAttribute("PadKind")) == "string"
end

function PadController.start()
	local mine: { [BasePart]: boolean } = {}
	local function paint(pad: BasePart)
		local price = pad:GetAttribute("Price")
		if typeof(price) ~= "number" then return end
		local balance = player:GetAttribute(if pad:GetAttribute("Currency") == "Popcorn" then "Popcorn" else "Cash")
		local affordable = typeof(balance) == "number" and balance >= price
		local glow = pad:FindFirstChild("Glow") :: BasePart?
		if glow then glow.Color = if affordable then AFFORD else SHORT end
		local tag = pad:FindFirstChild("PriceTag")
		local label = if tag then tag:FindFirstChild("Price") :: TextLabel? else nil
		if label then label.TextColor3 = if affordable then GOLD else DIM end
	end
	local function hide(pad: BasePart)
		pad.LocalTransparencyModifier = 1
		for _, child in pad:GetChildren() do
			if child:IsA("BasePart") then child.LocalTransparencyModifier = 1 end
			if child:IsA("BillboardGui") then child.Enabled = false end
		end
	end
	local function track(object: Instance)
		if not isPad(object) then
			-- A pad's glow or price tag can stream in after the pad itself.
			local parent = object.Parent
			if parent and isPad(parent) then
				if mine[parent :: BasePart] then paint(parent :: BasePart) else hide(parent :: BasePart) end
			end
			return
		end
		local pad = object :: BasePart
		local farm = pad.Parent
		if not farm or farm:GetAttribute("OwnerUserId") ~= player.UserId then hide(pad) return end
		mine[pad] = true
		paint(pad)
		pad:GetAttributeChangedSignal("Price"):Connect(function() paint(pad) end)
		pad.Destroying:Connect(function() mine[pad] = nil end)
		pad.AncestryChanged:Connect(function() if not pad:IsDescendantOf(workspace) then mine[pad] = nil end end)
	end
	local function repaintAll()
		for pad in mine do paint(pad) end
	end
	player:GetAttributeChangedSignal("Cash"):Connect(repaintAll)
	player:GetAttributeChangedSignal("Popcorn"):Connect(repaintAll)
	task.spawn(function()
		local farms = workspace:WaitForChild("PopcornFarms", 30)
		if not farms then return end
		farms.DescendantAdded:Connect(track)
		for _, object in farms:GetDescendants() do track(object) end
	end)
end

return PadController
