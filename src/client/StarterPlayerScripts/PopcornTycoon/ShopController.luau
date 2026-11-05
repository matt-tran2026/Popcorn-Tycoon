--!strict
-- The Shop menu, styled like the HUD's Shop button (Nov 3 2026): a studded green brick panel with
-- a black outline, the striped shop bag in the corner, Fredoka One outlined text and chunky brick
-- buttons. A Tools tab (buy and equip) and a Seeds tab that previews crop varieties.
-- Buttons only send requests; the server decides every purchase and equip, and the panel
-- redraws from the replicated Cash balance and Owned_/EquippedTool attributes.
-- The panel is laid out at one design size and scaled with UIScale to fit any screen.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local Money = require(Shared:WaitForChild("Money"))
local Theme = require(script.Parent.UITheme)
local UIFx = require(script.Parent.UIFx)
local MenuKit = require(script.Parent.MenuKit)
local player = Players.LocalPlayer
local Brick = Theme.Brick
local Controller = {}

local WIDTH, HEIGHT = 600, 400 -- design size in pixels before UIScale
local BLACK = Color3.new(0, 0, 0)

local corner, outline, label, chunky = MenuKit.corner, MenuKit.outline, MenuKit.label, MenuKit.chunky
type Chunky = MenuKit.Chunky

-- Returns a function that toggles the panel (or forces it with `visible`).
function Controller.start(gui: ScreenGui, request: RemoteEvent): (visible: boolean?) -> ()
	local panel = Instance.new("Frame")
	panel.Name, panel.AnchorPoint, panel.Position = "ShopPanel", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	panel.Size, panel.BackgroundColor3 = UDim2.fromOffset(WIDTH, HEIGHT), Brick.GreenRim
	panel.Visible, panel.ZIndex, panel.Active = false, 10, true
	corner(panel, 24)
	outline(panel, 5)
	local fit = Instance.new("UIScale")
	fit.Parent = panel
	-- Studded green face inside the darker rim, like the button tile.
	local face = Instance.new("ImageLabel")
	face.Name, face.Image, face.ScaleType = "Face", Theme.Hud.Studs, Enum.ScaleType.Tile
	face.TileSize, face.BackgroundColor3 = UDim2.fromOffset(44, 44), Brick.Green
	face.Position, face.Size = UDim2.fromOffset(9, 9), UDim2.new(1, -18, 1, -18)
	corner(face, 17)
	face.Parent = panel

	-- Header: the shop bag breaking out of the top-left corner, title, and a red close brick.
	-- A golden sunburst turns behind the bag.
	local glow = UIFx.sunburst(panel, Color3.fromRGB(255, 226, 90), 30)
	glow.Position, glow.Size, glow.ZIndex, glow.ImageTransparency = UDim2.fromOffset(28, 14), UDim2.fromOffset(230, 230), 2, 0.25
	local bag = Instance.new("ImageLabel")
	bag.Name, bag.Image, bag.BackgroundTransparency, bag.ScaleType = "Bag", Theme.Hud.ShopBag, 1, Enum.ScaleType.Fit
	bag.Position, bag.Size, bag.Rotation, bag.ZIndex = UDim2.fromOffset(-36, -50), UDim2.fromOffset(128, 128), -8, 3
	bag.Parent = panel
	local title = label("Title", panel, "Shop", 54, UDim2.fromOffset(0, 10), UDim2.new(1, 0, 0, 58))
	title.ZIndex = 2
	local close = chunky("Close", panel, UDim2.new(1, -40, 0, -16), UDim2.fromOffset(56, 56), 34)
	close.paint(Brick.Red, "X")
	close.button.ZIndex = 3

	-- Tabs: Tools is live; Seeds previews the planned variety unlocks.
	local tabs: { [string]: { tab: Chunky, page: ScrollingFrame } } = {}
	local function page(name: string): ScrollingFrame
		local p = Instance.new("ScrollingFrame")
		p.Name, p.BackgroundTransparency, p.BorderSizePixel = name .. "Page", 1, 0
		p.Position, p.Size = UDim2.fromOffset(22, 130), UDim2.new(1, -44, 1, -148)
		p.CanvasSize, p.AutomaticCanvasSize, p.ScrollBarThickness = UDim2.new(), Enum.AutomaticSize.Y, 8
		p.ScrollBarImageColor3, p.ScrollingDirection = BLACK, Enum.ScrollingDirection.Y
		local list = Instance.new("UIListLayout")
		list.Padding, list.SortOrder = UDim.new(0, 10), Enum.SortOrder.LayoutOrder
		list.HorizontalAlignment, list.Parent = Enum.HorizontalAlignment.Center, p
		local padding = Instance.new("UIPadding")
		padding.PaddingTop, padding.PaddingBottom, padding.Parent = UDim.new(0, 4), UDim.new(0, 6), p
		p.Parent = panel
		return p
	end
	local function select(name: string)
		for id, entry in tabs do
			entry.page.Visible = id == name
			entry.tab.paint(if id == name then Brick.Yellow else Brick.GreenRim, id)
		end
	end
	for i, name in { "Tools", "Seeds" } do
		local tab = chunky(name .. "Tab", panel, UDim2.new(0.5, (i - 1) * 150 - 140, 0, 74), UDim2.fromOffset(130, 44), 24)
		tabs[name] = { tab = tab, page = page(name) }
		tab.button.Activated:Connect(function() select(name) end)
	end

	-- One row per item: name, effect, details, and a state button on the right.
	local function card(parent: Instance, order: number, heading: string, effect: string, details: string): Chunky
		local c = Instance.new("Frame")
		c.Name, c.LayoutOrder, c.Size = heading, order, UDim2.new(1, -14, 0, 88)
		c.BackgroundColor3, c.BackgroundTransparency = Color3.fromRGB(20, 24, 30), 0.35
		corner(c, 14)
		local edge = Instance.new("UIStroke")
		edge.Color, edge.Thickness, edge.Parent = BLACK, 2.5, c
		c.Parent = parent
		local name = label("Name", c, heading, 28, UDim2.fromOffset(14, 6), UDim2.new(1, -190, 0, 32))
		local line = label("Effect", c, effect, 18, UDim2.fromOffset(14, 39), UDim2.new(1, -190, 0, 22))
		local more = label("Details", c, details, 15, UDim2.fromOffset(14, 62), UDim2.new(1, -190, 0, 18))
		more.TextColor3 = Color3.fromRGB(205, 240, 190)
		for _, t in { name, line, more } do t.TextXAlignment = Enum.TextXAlignment.Left end
		return chunky("Action", c, UDim2.new(1, -166, 0.5, -29), UDim2.fromOffset(152, 58), 21)
	end

	local toolsPage = tabs.Tools.page
	local hands = card(toolsPage, 1, "Hands", "Pick one ripe stalk at a time", "Always yours · E or tap a stalk")
	hands.button.Activated:Connect(function() request:FireServer("Equip", "Manual") end)
	local toolButtons: { [string]: Chunky } = {}
	local order = 2
	-- Cheapest first, so the catalog reads as a progression (Clippers, then Sickle, ...).
	local toolIds: { string } = {}
	for toolId in Config.Tools do table.insert(toolIds, toolId) end
	table.sort(toolIds, function(a, b)
		local pa, pb = Config.Tools[a].price, Config.Tools[b].price
		if pa ~= pb then return pa < pb end
		return a < b
	end)
	for _, toolId in toolIds do
		local tool = Config.Tools[toolId]
		local details = "Reach " .. tostring(tool.reach) .. " studs · " .. tostring(tool.cooldownSeconds) .. " s per swing"
			.. (if tool.yieldMultiplier > 1 then " · ×" .. tostring(tool.yieldMultiplier) .. " yield" else "")
		local action = card(toolsPage, order, tool.displayName, tool.description, details)
		order += 1
		toolButtons[toolId] = action
		action.button.Activated:Connect(function()
			if player:GetAttribute("Owned_" .. toolId) then
				request:FireServer("Equip", if player:GetAttribute("EquippedTool") == toolId then "Manual" else toolId)
			else
				request:FireServer("Buy", toolId)
			end
		end)
	end
	local soon = label("ComingSoon", toolsPage, "Bigger bags are in Upgrades · More tools coming: Heavy Sickle", 18, UDim2.new(), UDim2.new(1, -14, 0, 26))
	soon.LayoutOrder = 99

	local seedsPage = tabs.Seeds.page
	for cropId, crop in Config.Crops do
		local details = "Grows " .. tostring(crop.growthSeconds) .. " s per yield · up to " .. tostring(crop.maxYields) .. " yields"
		local action = card(seedsPage, 1, crop.displayName, Money.cash(Config.Sell.cashPerPopcorn * crop.popcornValue) .. " per popcorn", details)
		action.paint(Brick.Blue, "Planted")
		action.button.Name = "Plant_" .. cropId
	end
	local seedsSoon = label("ComingSoon", seedsPage, "New corn varieties unlock here soon.\nChoose what to plant in each field.", 18, UDim2.new(), UDim2.new(1, -14, 0, 46))
	seedsSoon.LayoutOrder = 99

	local function render()
		local equipped = player:GetAttribute("EquippedTool")
		local holdingTool = typeof(equipped) == "string" and Config.Tools[equipped] ~= nil
		if holdingTool then hands.paint(Brick.Yellow, "Use hands") else hands.paint(Brick.Blue, "In use") end
		for toolId, action in toolButtons do
			local tool = Config.Tools[toolId]
			local balance = (player:GetAttribute(tool.currency) or 0) :: number
			if equipped == toolId then
				action.paint(Brick.Blue, "Equipped\nPut away")
			elseif player:GetAttribute("Owned_" .. toolId) then
				action.paint(Brick.Yellow, "Owned\nEquip")
			elseif balance >= tool.price then
				action.paint(Brick.Green, "Buy\n" .. Money.price(tool.currency, tool.price))
			else
				action.paint(Brick.Grey, Money.price(tool.currency, tool.price) .. "\nNeed " .. Money.price(tool.currency, tool.price - balance))
			end
		end
	end
	player.AttributeChanged:Connect(function(name)
		if name == "Cash" or name == "Popcorn" or name == "EquippedTool" or string.sub(name, 1, 6) == "Owned_" then render() end
	end)

	-- Whole panel (plus the bag and close button that break out of it) fits the safe screen area.
	local function fitToScreen()
		local screen = gui.AbsoluteSize
		if screen.X <= 0 or screen.Y <= 0 then return end
		fit.Scale = math.clamp(math.min(screen.X * 0.92 / (WIDTH + 60), screen.Y * 0.94 / (HEIGHT + 50)), 0.4, 1.25)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)

	-- Opening blurs and dims the world behind the panel (local camera effect only).
	local blur = Instance.new("BlurEffect")
	blur.Name, blur.Size, blur.Enabled = "ShopBlur", 0, false
	local dim = Instance.new("Frame")
	dim.Name, dim.BackgroundColor3, dim.BackgroundTransparency = "ShopDim", BLACK, 1
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
			render()
			-- Pops in from small with an overshoot, cards sliding up after it.
			local target = fit.Scale
			fit.Scale = target * 0.55
			panel.Position, panel.Rotation = UDim2.fromScale(0.5, 0.5), -4
			panel.Visible = true
			backdrop(true)
			TweenService:Create(fit, TweenInfo.new(0.38, Enum.EasingStyle.Back), { Scale = target }):Play()
			TweenService:Create(panel, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
			for _, entry in tabs do
				for index, child in entry.page:GetChildren() do
					if child:IsA("Frame") then
						local slide = child:FindFirstChild("Slide") :: UIScale? or Instance.new("UIScale")
						;(slide :: UIScale).Name, (slide :: UIScale).Parent = "Slide", child
						;(slide :: UIScale).Scale = 0.6
						TweenService:Create(slide :: UIScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.08 + index * 0.05), { Scale = 1 }):Play()
					end
				end
			end
		elseif not open then
			panel.Visible = false
			backdrop(false)
		end
	end
	close.button.Activated:Connect(function() toggle(false) end)
	panel.Parent = gui
	select("Tools")
	render()
	fitToScreen()
	return toggle
end

return Controller
