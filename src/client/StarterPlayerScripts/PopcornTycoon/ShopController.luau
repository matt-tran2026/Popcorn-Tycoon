--!strict
-- The Shop menu: a Tools tab (buy and equip) and a Seeds tab that previews crop varieties.
-- Buttons only send requests; the server decides every purchase and equip, and the panel
-- redraws from the replicated balance and Owned_/EquippedTool attributes.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local Money = require(Shared:WaitForChild("Money"))
local Theme = require(script.Parent.UITheme)
local player = Players.LocalPlayer
local Controller = {}

export type Ui = {
	frame: (name: string, parent: Instance, size: UDim2, position: UDim2) -> Frame,
	text: (name: string, parent: Instance, value: string, size: UDim2, position: UDim2, fontSize: number) -> TextLabel,
}

local function button(name: string, parent: Instance, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Name, b.Size, b.Position = name, size, position
	b.Font, b.TextSize, b.TextWrapped, b.AutoButtonColor = Enum.Font.GothamBold, 15, true, true
	b.BackgroundColor3, b.TextColor3 = Theme.Gold, Theme.Brown
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
	b.Parent = parent
	return b
end

-- Returns a function that toggles the panel (or forces it with `visible`).
function Controller.start(gui: ScreenGui, ui: Ui, request: RemoteEvent): (visible: boolean?) -> ()
	local panel = ui.frame("ShopPanel", gui, UDim2.new(0.92, 0, 0.8, 0), UDim2.fromScale(0.5, 0.52))
	panel.AnchorPoint, panel.Visible, panel.ZIndex = Vector2.new(0.5, 0.5), false, 10
	Instance.new("UISizeConstraint", panel).MaxSize = Vector2.new(540, 340)
	ui.text("Title", panel, "SHOP", UDim2.new(1, -80, 0, 40), UDim2.fromOffset(16, 8), 22)
	local close = button("Close", panel, UDim2.fromOffset(44, 44), UDim2.new(1, -54, 0, 8))
	close.Text, close.BackgroundColor3, close.TextColor3, close.TextSize = "X", Theme.Red, Theme.Cream, 22

	-- Tabs: Tools is live; Seeds previews the planned variety unlocks.
	local tabs: { [string]: { tab: TextButton, page: ScrollingFrame } } = {}
	local function page(name: string): ScrollingFrame
		local p = Instance.new("ScrollingFrame")
		p.Name, p.BackgroundTransparency, p.BorderSizePixel = name .. "Page", 1, 0
		p.Size, p.Position = UDim2.new(1, -24, 1, -104), UDim2.fromOffset(12, 98)
		p.CanvasSize, p.AutomaticCanvasSize, p.ScrollBarThickness = UDim2.new(), Enum.AutomaticSize.Y, 6
		local list = Instance.new("UIListLayout") list.Padding, list.SortOrder, list.Parent = UDim.new(0, 8), Enum.SortOrder.LayoutOrder, p
		p.Parent = panel
		return p
	end
	local function select(name: string)
		for id, entry in tabs do
			entry.page.Visible = id == name
			entry.tab.BackgroundColor3 = if id == name then Theme.Gold else Theme.Dark
			entry.tab.TextColor3 = if id == name then Theme.Brown else Theme.Cream
		end
	end
	for i, name in { "Tools", "Seeds" } do
		local tab = button(name .. "Tab", panel, UDim2.fromOffset(110, 38), UDim2.fromOffset(16 + (i - 1) * 118, 52))
		tab.Text = name
		tabs[name] = { tab = tab, page = page(name) }
		tab.Activated:Connect(function() select(name) end)
	end

	-- One row per item: name, effect, details, and a state button on the right.
	local function card(parent: Instance, order: number, title: string, effect: string, details: string): (Frame, TextButton)
		local c = Instance.new("Frame")
		c.Name, c.LayoutOrder, c.Size = title, order, UDim2.new(1, -8, 0, 78)
		c.BackgroundColor3, c.BackgroundTransparency = Theme.Dark, 0.15
		Instance.new("UICorner", c).CornerRadius = UDim.new(0, 12)
		c.Parent = parent
		local name = ui.text("Name", c, title, UDim2.new(1, -150, 0, 24), UDim2.fromOffset(12, 6), 18)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local line = ui.text("Effect", c, effect, UDim2.new(1, -150, 0, 20), UDim2.fromOffset(12, 30), 14)
		line.TextXAlignment = Enum.TextXAlignment.Left
		local more = ui.text("Details", c, details, UDim2.new(1, -150, 0, 18), UDim2.fromOffset(12, 52), 12)
		more.TextXAlignment, more.TextColor3 = Enum.TextXAlignment.Left, Theme.Muted
		for _, label in { line, more } do label.TextScaled = true Instance.new("UITextSizeConstraint", label).MaxTextSize = label.TextSize end
		local action = button("Action", c, UDim2.fromOffset(128, 52), UDim2.new(1, -138, 0, 13))
		return c, action
	end

	local toolsPage = tabs.Tools.page
	local _, handsButton = card(toolsPage, 1, "Hands", "Pick one ripe stalk at a time", "Always yours · E or tap a stalk")
	handsButton.Activated:Connect(function() request:FireServer("Equip", "Manual") end)
	local toolButtons: { [string]: TextButton } = {}
	local order = 2
	for toolId, tool in Config.Tools do
		local details = "Reach " .. tostring(tool.reach) .. " studs · " .. tostring(tool.cooldownSeconds) .. " s per swing"
			.. (if tool.yieldMultiplier > 1 then " · ×" .. tostring(tool.yieldMultiplier) .. " yield" else "")
		local _, action = card(toolsPage, order, tool.displayName, tool.description, details)
		order += 1
		toolButtons[toolId] = action
		action.Activated:Connect(function()
			if player:GetAttribute("Owned_" .. toolId) then
				request:FireServer("Equip", if player:GetAttribute("EquippedTool") == toolId then "Manual" else toolId)
			else
				request:FireServer("Buy", toolId)
			end
		end)
	end
	local soon = ui.text("ComingSoon", toolsPage, "More tools coming: Bigger Bag, Heavy Sickle", UDim2.new(1, -8, 0, 24), UDim2.new(), 13)
	soon.LayoutOrder, soon.TextColor3 = 99, Theme.Muted

	local seedsPage = tabs.Seeds.page
	for cropId, crop in Config.Crops do
		local details = "Grows " .. tostring(crop.growthSeconds) .. " s per yield · up to " .. tostring(crop.maxYields) .. " yields"
		local _, action = card(seedsPage, 1, crop.displayName, Money.cash(Config.Sell.cashPerPopcorn * crop.popcornValue) .. " per popcorn", details)
		action.Text, action.Active, action.AutoButtonColor, action.BackgroundColor3 = "Planted", false, false, Theme.Green
		action.TextColor3 = Theme.Cream
		action.Name = "Plant_" .. cropId
	end
	local seedsSoon = ui.text("ComingSoon", seedsPage, "New corn varieties unlock here soon. Choose what to plant in each field.", UDim2.new(1, -8, 0, 40), UDim2.new(), 13)
	seedsSoon.LayoutOrder, seedsSoon.TextColor3 = 99, Theme.Muted

	local function paint(b: TextButton, label: string, color: Color3, textColor: Color3)
		b.Text, b.BackgroundColor3, b.TextColor3 = label, color, textColor
	end
	local function render()
		local equipped = player:GetAttribute("EquippedTool")
		local holdingTool = typeof(equipped) == "string" and Config.Tools[equipped] ~= nil
		paint(handsButton, if holdingTool then "Use hands" else "In use", if holdingTool then Theme.Gold else Theme.Green, if holdingTool then Theme.Brown else Theme.Cream)
		for toolId, b in toolButtons do
			local tool = Config.Tools[toolId]
			local balance = (player:GetAttribute(tool.currency) or 0) :: number
			if equipped == toolId then
				paint(b, "Equipped\nput away", Theme.Green, Theme.Cream)
			elseif player:GetAttribute("Owned_" .. toolId) then
				paint(b, "Owned\nEquip", Theme.Gold, Theme.Brown)
			elseif balance >= tool.price then
				paint(b, "Buy\n" .. Money.price(tool.currency, tool.price), Theme.Gold, Theme.Brown)
			else
				paint(b, Money.price(tool.currency, tool.price) .. "\nneed " .. Money.price(tool.currency, tool.price - balance) .. " more", Theme.Brown, Theme.Muted)
			end
		end
	end
	player.AttributeChanged:Connect(function(name)
		if name == "Cash" or name == "Popcorn" or name == "EquippedTool" or string.sub(name, 1, 6) == "Owned_" then render() end
	end)
	select("Tools")
	render()

	local function toggle(visible: boolean?)
		panel.Visible = if visible == nil then not panel.Visible else visible
		if panel.Visible then render() end
	end
	close.Activated:Connect(function() toggle(false) end)
	return toggle
end

return Controller
