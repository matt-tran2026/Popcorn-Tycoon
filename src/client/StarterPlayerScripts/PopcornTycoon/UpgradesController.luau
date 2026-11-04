--!strict
-- The Upgrades menu (Nov 4 2026), opened by the HUD's Upgrades button. A studded orange brick
-- panel like the button, styled like the Shop (MenuKit). Four cards: Backpack Capacity (for
-- every plot) and Soil Quality, Corn Yield and Stalk Storage for the plot picked in the plot row
-- (only plots you own are listed). Each card shows the level, the benefit now and next, and a
-- buy button with the price, or MAX LEVEL.
-- Buttons only send (upgradeId, fieldId); the server prices and applies every purchase. Levels
-- are read back from the server's Upgrade_* attributes, so the menu shows confirmed values only.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local Money = require(Shared:WaitForChild("Money"))
local FarmUpgrades = require(Shared:WaitForChild("FarmUpgrades"))
local Types = require(Shared:WaitForChild("Types"))
local Theme = require(script.Parent.UITheme)
local UIFx = require(script.Parent.UIFx)
local MenuKit = require(script.Parent.MenuKit)
local player = Players.LocalPlayer
local Brick = Theme.Brick
local Controller = {}

local WIDTH, HEIGHT = 640, 460 -- design size in pixels before UIScale
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local NEXT_GREEN = Color3.fromRGB(150, 255, 120)
local CARD_W, CARD_H = 290, 150

export type Menu = {
	toggle: (visible: boolean?) -> (),
	-- Purchase feedback for a server answer on ActionResult "FarmUpgrade".
	confirmed: (response: Types.ActionResult) -> (),
	refused: (response: Types.ActionResult) -> (),
	isOpen: () -> boolean,
}

type Card = {
	frame: Frame, scale: UIScale, buy: MenuKit.Chunky, level: TextLabel, tag: TextLabel,
	now: TextLabel, nextLine: TextLabel, pips: { Frame }, coin: ImageLabel,
}

local function levelOf(id: string, fieldId: string): number
	local name = if Config.FarmUpgrades[id].scope == "Global" then "Upgrade_" .. id else "Upgrade_" .. fieldId .. "_" .. id
	return FarmUpgrades.clampLevel(id, player:GetAttribute(name))
end

function Controller.start(gui: ScreenGui, request: RemoteEvent, show: (string, number?) -> ()): Menu
	local panel = Instance.new("Frame")
	panel.Name, panel.AnchorPoint, panel.Position = "UpgradesPanel", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	panel.Size, panel.BackgroundColor3 = UDim2.fromOffset(WIDTH, HEIGHT), Brick.OrangeRim
	panel.Visible, panel.ZIndex, panel.Active = false, 10, true
	MenuKit.corner(panel, 24)
	MenuKit.outline(panel, 5)
	local fit = Instance.new("UIScale")
	fit.Parent = panel
	local face = Instance.new("ImageLabel")
	face.Name, face.Image, face.ScaleType = "Face", Theme.Hud.Studs, Enum.ScaleType.Tile
	face.TileSize, face.BackgroundColor3 = UDim2.fromOffset(44, 44), Brick.Orange
	face.Position, face.Size = UDim2.fromOffset(9, 9), UDim2.new(1, -18, 1, -18)
	MenuKit.corner(face, 17)
	face.Parent = panel

	-- Header: the Upgrades arrows breaking out of the top-left corner over a turning sunburst.
	local glow = UIFx.sunburst(panel, Color3.fromRGB(255, 236, 120), 30)
	glow.Position, glow.Size, glow.ZIndex, glow.ImageTransparency = UDim2.fromOffset(20, 10), UDim2.fromOffset(220, 220), 2, 0.3
	local badge = Instance.new("ImageLabel")
	badge.Name, badge.Image, badge.BackgroundTransparency, badge.ScaleType = "Arrows", Theme.Hud.Upgrades, 1, Enum.ScaleType.Fit
	badge.Position, badge.Size, badge.Rotation, badge.ZIndex = UDim2.fromOffset(-34, -48), UDim2.fromOffset(124, 124), -8, 3
	badge.Parent = panel
	local title = MenuKit.label("Title", panel, "Upgrades", 52, UDim2.fromOffset(0, 8), UDim2.new(1, 0, 0, 56))
	title.ZIndex = 2
	local close = MenuKit.chunky("Close", panel, UDim2.new(1, -40, 0, -16), UDim2.fromOffset(56, 56), 34)
	close.paint(Brick.Red, "X")
	close.button.ZIndex = 3

	-- Plot picker: one brick per owned plot; the picked one is yellow and raised.
	local selected = "Plot1"
	local plotRow = Instance.new("Frame")
	plotRow.Name, plotRow.BackgroundTransparency = "PlotPicker", 1
	plotRow.Position, plotRow.Size = UDim2.fromOffset(22, 70), UDim2.new(1, -44, 0, 46)
	plotRow.Parent = panel
	local plotCaption = MenuKit.label("Caption", plotRow, "Plot", 24, UDim2.fromOffset(0, 6), UDim2.fromOffset(62, 34))
	plotCaption.TextXAlignment = Enum.TextXAlignment.Left
	local chips = Instance.new("Frame")
	chips.Name, chips.BackgroundTransparency = "Chips", 1
	chips.Position, chips.Size = UDim2.fromOffset(62, 0), UDim2.new(1, -62, 1, 0)
	chips.Parent = plotRow
	local chipList = Instance.new("UIListLayout")
	chipList.FillDirection, chipList.Padding, chipList.SortOrder = Enum.FillDirection.Horizontal, UDim.new(0, 8), Enum.SortOrder.LayoutOrder
	chipList.VerticalAlignment, chipList.Parent = Enum.VerticalAlignment.Center, chips
	local chipButtons: { [string]: MenuKit.Chunky } = {}

	local cards: { [string]: Card } = {}
	local render: () -> ()

	local function card(order: number, id: string): Card
		local upgrade = Config.FarmUpgrades[id]
		local column, row = (order - 1) % 2, (order - 1) // 2
		local c = Instance.new("Frame")
		c.Name, c.Size = id, UDim2.fromOffset(CARD_W, CARD_H)
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromOffset(22 + column * (CARD_W + 16) + CARD_W / 2, 126 + row * (CARD_H + 12) + CARD_H / 2)
		c.BackgroundColor3, c.BackgroundTransparency = Color3.fromRGB(24, 18, 14), 0.3
		MenuKit.corner(c, 14)
		local edge = Instance.new("UIStroke")
		edge.Color, edge.Thickness, edge.Parent = BLACK, 2.5, c
		local scale = Instance.new("UIScale")
		scale.Parent = c
		c.Parent = panel
		local icon = Instance.new("ImageLabel")
		icon.Name, icon.BackgroundTransparency, icon.ScaleType = "Icon", 1, Enum.ScaleType.Fit
		icon.Image = if Theme.Upgrades[id] ~= "" then Theme.Upgrades[id] else Theme.CornIcon
		icon.Position, icon.Size, icon.ZIndex = UDim2.fromOffset(4, 2), UDim2.fromOffset(62, 62), 2
		icon.Parent = c
		local name = MenuKit.label("Name", c, upgrade.displayName, 24, UDim2.fromOffset(70, 6), UDim2.new(1, -78, 0, 28))
		name.TextXAlignment = Enum.TextXAlignment.Left
		local tag = MenuKit.label("Scope", c, "", 15, UDim2.fromOffset(70, 34), UDim2.new(0.5, -40, 0, 20))
		tag.TextXAlignment, tag.TextColor3 = Enum.TextXAlignment.Left, Color3.fromRGB(255, 214, 160)
		local level = MenuKit.label("Level", c, "", 17, UDim2.new(0.5, 30, 0, 34), UDim2.new(0.5, -38, 0, 20))
		level.TextXAlignment, level.TextColor3 = Enum.TextXAlignment.Right, Color3.fromRGB(255, 226, 74)
		local now = MenuKit.label("Now", c, "", 18, UDim2.fromOffset(12, 62), UDim2.new(1, -24, 0, 20))
		now.TextXAlignment = Enum.TextXAlignment.Left
		local nextLine = MenuKit.label("Next", c, "", 18, UDim2.fromOffset(12, 83), UDim2.new(1, -24, 0, 20))
		nextLine.TextXAlignment, nextLine.TextColor3 = Enum.TextXAlignment.Left, NEXT_GREEN
		-- Level bars: one per level above 0, lit up to the current level.
		local pips: { Frame } = {}
		for i = 1, FarmUpgrades.maxLevel(id) do
			local pip = Instance.new("Frame")
			pip.Name, pip.Size = "Pip" .. i, UDim2.fromOffset(22, 12)
			pip.Position = UDim2.fromOffset(12 + (i - 1) * 27, 122)
			MenuKit.corner(pip, 4)
			MenuKit.outline(pip, 2)
			pip.Parent = c
			table.insert(pips, pip)
		end
		local buy = MenuKit.chunky("Buy", c, UDim2.new(1, -146, 1, -44), UDim2.fromOffset(136, 38), 19)
		buy.caption.Position, buy.caption.Size = UDim2.fromScale(0.3, 0.1), UDim2.fromScale(0.66, 0.8)
		local coin = UIFx.coin(buy.button)
		coin.AnchorPoint, coin.Position, coin.Size, coin.ZIndex = Vector2.new(0.5, 0.5), UDim2.fromScale(0.17, 0.5), UDim2.fromOffset(32, 32), 3
		buy.button.Activated:Connect(function()
			if buy.button:GetAttribute("Maxed") then return end
			request:FireServer(id, if upgrade.scope == "Field" then selected else nil)
		end)
		return { frame = c, scale = scale, buy = buy, level = level, tag = tag, now = now, nextLine = nextLine, pips = pips, coin = coin }
	end
	for i, id in Config.FarmUpgradeOrder do cards[id] = card(i, id) end

	local function plots(): number
		local count = player:GetAttribute("Plots")
		return if typeof(count) == "number" then math.clamp(math.floor(count), 1, #Config.Grid.order) else 1
	end
	local function rebuildChips()
		local count = plots()
		for i = 1, #Config.Grid.order do
			local fieldId = "Plot" .. tostring(i)
			local chip = chipButtons[fieldId]
			if i <= count and not chip then
				chip = MenuKit.chunky(fieldId, chips, UDim2.new(), UDim2.fromOffset(52, 40), 22)
				chip.button.LayoutOrder = i
				chip.button.Activated:Connect(function()
					selected = fieldId
					render()
				end)
				chipButtons[fieldId] = chip
			elseif i > count and chip then
				chip.button:Destroy()
				chipButtons[fieldId] = nil
			end
		end
		if not chipButtons[selected] then selected = "Plot1" end
	end

	render = function()
		for fieldId, chip in chipButtons do
			chip.paint(if fieldId == selected then Brick.Yellow else Brick.OrangeRim, string.sub(fieldId, 5))
		end
		local cash = (player:GetAttribute("Cash") or 0) :: number
		for id, entry in cards do
			local upgrade = Config.FarmUpgrades[id]
			local level = levelOf(id, selected)
			local maxLevel = FarmUpgrades.maxLevel(id)
			local price = FarmUpgrades.price(id, level)
			entry.tag.Text = if upgrade.scope == "Global" then "All plots" else "Plot " .. string.sub(selected, 5)
			entry.level.Text = "Lv " .. tostring(level) .. "/" .. tostring(maxLevel)
			entry.now.Text = "Now: " .. FarmUpgrades.describe(id, level)
			entry.nextLine.Text = if price then "Next: " .. FarmUpgrades.describe(id, level + 1) else "Fully upgraded!"
			for i, pip in entry.pips do pip.BackgroundColor3 = if i <= level then Brick.Yellow else Color3.fromRGB(70, 56, 44) end
			entry.buy.button:SetAttribute("Maxed", price == nil)
			entry.coin.Visible = price ~= nil
			if not price then
				entry.buy.paint(Brick.Grey, "MAX LEVEL")
				entry.buy.caption.Position, entry.buy.caption.Size = UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.88, 0.8)
			else
				entry.buy.caption.Position, entry.buy.caption.Size = UDim2.fromScale(0.3, 0.1), UDim2.fromScale(0.66, 0.8)
				local affordable = cash >= price
				entry.buy.paint(if affordable then Brick.Green else Brick.Grey,
					Money.price(upgrade.currency, price) .. (if affordable then "" else "\nNeed " .. Money.price(upgrade.currency, price - cash)))
			end
		end
	end
	player.AttributeChanged:Connect(function(name)
		if name == "Plots" then rebuildChips() end
		if name == "Cash" or name == "Plots" or string.sub(name, 1, 8) == "Upgrade_" then render() end
	end)

	-- Whole panel (plus the badge and close button that break out of it) fits the safe screen area.
	local function fitToScreen()
		local screen = gui.AbsoluteSize
		if screen.X <= 0 or screen.Y <= 0 then return end
		fit.Scale = math.clamp(math.min(screen.X * 0.92 / (WIDTH + 60), screen.Y * 0.94 / (HEIGHT + 50)), 0.35, 1.2)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)

	local blur = Instance.new("BlurEffect")
	blur.Name, blur.Size, blur.Enabled = "UpgradesBlur", 0, false
	local dim = Instance.new("Frame")
	dim.Name, dim.BackgroundColor3, dim.BackgroundTransparency = "UpgradesDim", BLACK, 1
	dim.Size, dim.Position, dim.ZIndex, dim.Visible = UDim2.new(1, 400, 1, 400), UDim2.fromOffset(-200, -200), 9, false
	dim.Parent = gui
	local function backdrop(on: boolean)
		blur.Parent = workspace.CurrentCamera
		if on then
			blur.Enabled, dim.Visible = true, true
			TweenService:Create(blur, TweenInfo.new(0.25), { Size = 14 }):Play()
			TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.55 }):Play()
		else
			blur.Size, blur.Enabled = 0, false
			dim.BackgroundTransparency, dim.Visible = 1, false
		end
	end

	local function toggle(visible: boolean?)
		local open = if visible == nil then not panel.Visible else visible
		if open and not panel.Visible then
			fitToScreen()
			rebuildChips()
			render()
			local target = fit.Scale
			fit.Scale = target * 0.55
			panel.Rotation = -4
			panel.Visible = true
			backdrop(true)
			TweenService:Create(fit, TweenInfo.new(0.38, Enum.EasingStyle.Back), { Scale = target }):Play()
			TweenService:Create(panel, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
			for i, id in Config.FarmUpgradeOrder do
				local entry = cards[id]
				entry.scale.Scale = 0.6
				TweenService:Create(entry.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.08 + i * 0.05), { Scale = 1 }):Play()
			end
		elseif not open then
			panel.Visible = false
			backdrop(false)
		end
	end
	close.button.Activated:Connect(function() toggle(false) end)

	-- A bought card jumps, flashes gold and floats its new stat above itself.
	local function confirmed(response: Types.ActionResult)
		local id = response.upgradeId
		local entry = if typeof(id) == "string" then cards[id] else nil
		if not entry or not panel.Visible then return end
		if response.fieldId and response.fieldId ~= selected then return end
		entry.scale.Scale = 1.12
		TweenService:Create(entry.scale, TweenInfo.new(0.45, Enum.EasingStyle.Elastic), { Scale = 1 }):Play()
		local flash = UIFx.sunburst(entry.frame, Color3.fromRGB(255, 230, 90), 120)
		flash.AnchorPoint, flash.Position, flash.Size, flash.ZIndex = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(60, 60), 0
		TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(340, 340), ImageTransparency = 1 }):Play()
		task.delay(0.65, function() flash:Destroy() end)
		local stat = MenuKit.label("NewStat", entry.frame, FarmUpgrades.describe(id :: string, response.level or 0) .. "!", 24,
			UDim2.fromOffset(0, 58), UDim2.new(1, 0, 0, 30))
		stat.TextColor3, stat.ZIndex = NEXT_GREEN, 5
		-- Rises inside its own card so it never covers the plot picker.
		TweenService:Create(stat, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { Position = UDim2.fromOffset(0, 18), TextTransparency = 1 }):Play()
		task.delay(1.15, function() stat:Destroy() end)
	end

	-- A refused purchase shakes its card; the reason (e.g. "Need $40 more") shows as a toast.
	local function refused(response: Types.ActionResult)
		show(response.reason)
		local id = response.upgradeId
		local entry = if typeof(id) == "string" then cards[id] else nil
		local target = if entry then entry.frame else nil
		if not target or not panel.Visible then return end
		task.spawn(function()
			for i = 1, 6 do
				target.Rotation = (if i % 2 == 0 then 1 else -1) * (7 - i) * 0.8
				task.wait(0.04)
			end
			target.Rotation = 0
		end)
	end

	panel.Parent = gui
	rebuildChips()
	render()
	fitToScreen()
	return {
		toggle = toggle,
		confirmed = confirmed,
		refused = refused,
		isOpen = function(): boolean return panel.Visible end,
	}
end

return Controller
