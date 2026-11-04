--!strict
-- The always-on HUD (Nov 3 2026 art pass): the popcorn bucket at the top centre (up in the
-- free middle of Roblox's top bar when there is room), the cash bar bottom-left with the
-- corn-bag meter just above it, and two columns of menu buttons. The art is uploaded image
-- assets (assets/ui/hud, ids in UITheme.Hud); every number is a live Fredoka One label drawn
-- over the art and read from replicated attributes. All sizes come from one `unit` computed
-- from the safe screen area, so one layout scales from phones to desktops; the pixel layout
-- itself is the pure function HudController.placements, so it can be checked for any screen.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInput = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local Money = require(Shared:WaitForChild("Money"))
local Theme = require(script.Parent.UITheme)
local player = Players.LocalPlayer
local HudController = {}

export type Hud = {
	gui: ScreenGui,
	show: (message: string, seconds: number?) -> (),
	pulseCorn: () -> (),
	pulsePopcorn: () -> (),
	pulseCash: () -> (),
}
-- Button name -> what it opens. Buttons without an action say their feature is coming soon.
export type Actions = { [string]: () -> () }
-- A pixel rectangle: x, y is the top-left corner.
export type Box = { x: number, y: number, w: number, h: number }
export type Placements = {
	unit: number,
	gap: number,
	touch: boolean,
	left: Box, -- Index / Settings / Rebirth
	right: Box, -- Shop / Quests / Upgrades
	cash: Box,
	bag: Box, -- the bar itself; its corn icon pokes out by `bagOverhang` above and below
	bagOverhang: number,
	bagStroke: number, -- outline thickness, drawn outside the bar
	toast: Box,
	popcorn: Box, -- screen coordinates (the bucket has its own ScreenGui)
	popcornInHud: Box, -- the same box in HUD coordinates, for overlap checks
}

local LEFT = { "Index", "Settings", "Rebirth" }
local RIGHT = { "Shop", "Quests", "Upgrades" }
local POPCORN_ASPECT = 512 / 606 -- popcorn_counter.png
local CASH_ASPECT = 450 / 130 -- cash_bar.png
local CORN_ICON_SCALE = 1.7 -- corn icon height relative to the bag bar
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local function overlaps(a: Box, b: Box): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Where everything goes, in pixels. `screen` is the HUD's safe area (CoreUISafeInsets),
-- `viewport` the whole window and `topbar` GuiService.TopbarInset: the free part of
-- Roblox's top bar, in window coordinates. The HUD area is assumed to start at the bottom of
-- the top bar and to be centred horizontally in the window.
function HudController.placements(screen: Vector2, viewport: Vector2, touch: boolean, topbar: Rect): Placements
	local unit = math.floor(math.clamp(math.min(screen.X * 0.11, screen.Y * 0.15), 52, 118))
	local pad = math.floor(unit * 0.16)
	local gap = math.floor(unit * 0.1)
	local length = unit * 3 + gap * 2
	local cashH = math.floor(unit * 0.62)
	local cashW = math.floor(cashH * CASH_ASPECT)
	-- The bag bar spans the cash bar's width; its outline is drawn outside the bar, so the bar
	-- is inset by the outline to keep the outer edges flush with the cash bar.
	local bagStroke = math.max(1.5, unit * 0.03)
	local inset = math.ceil(bagStroke)
	local bagH = math.floor(unit * 0.32)
	local overhang = math.ceil(bagH * (CORN_ICON_SCALE - 1) / 2)
	local popH = math.max(math.floor(unit * 1.1), 64)
	local popW = math.floor(popH * POPCORN_ASPECT)

	-- Popcorn bucket: top centre of the window, inside the free middle of the top bar when it
	-- fits there, otherwise just under it.
	local originX = math.floor((viewport.X - screen.X) / 2)
	local originY = topbar.Max.Y
	local popX = math.floor((viewport.X - popW) / 2)
	local inTopbar = topbar.Height > 0 and popX >= topbar.Min.X + gap and popX + popW <= topbar.Max.X - gap
	local popY = if inTopbar then topbar.Min.Y + math.max(2, math.floor(gap / 2)) else originY + pad
	local popcorn = { x = popX, y = popY, w = popW, h = popH }
	local popcornInHud = { x = popX - originX, y = popY - originY, w = popW, h = popH }
	local belowPopcorn = popcornInHud.y + popH + gap

	local left, right, cash, bag
	local toastH = math.floor(unit * 0.36)
	local toastY
	if touch then
		-- Everything along the top, clear of the thumbstick and jump button: cash bar, corn bag
		-- and the left row stacked top-left, the right row top-right. A group drops below the
		-- bucket only if the bucket would otherwise touch it (very narrow screens).
		local leftColumn = { x = pad, y = pad, w = math.max(cashW, length), h = 1 }
		local rightRow = { x = screen.X - pad - length, y = pad, w = length, h = unit }
		local leftTop = if overlaps(leftColumn, popcornInHud) then belowPopcorn else pad
		local rightTop = if overlaps(rightRow, popcornInHud) then belowPopcorn else pad
		cash = { x = pad, y = leftTop, w = cashW, h = cashH }
		bag = { x = pad + inset, y = leftTop + cashH + gap + overhang, w = cashW - inset * 2, h = bagH }
		left = { x = pad, y = bag.y + bagH + overhang + pad, w = length, h = unit }
		right = { x = rightRow.x, y = rightTop, w = length, h = unit }
		toastY = math.max(left.y + unit + pad, right.y + unit + pad, belowPopcorn)
	else
		-- Mouse and keyboard: button columns down the screen edges, cash bar bottom-left with
		-- the corn bag above it; the left column moves up if a short window would squeeze them.
		cash = { x = pad, y = screen.Y - pad - cashH, w = cashW, h = cashH }
		bag = { x = pad + inset, y = cash.y - gap - overhang - bagH, w = cashW - inset * 2, h = bagH }
		local centred = math.floor((screen.Y - length) / 2)
		local highest = bag.y - overhang - gap - length
		left = { x = pad, y = math.max(pad, math.min(centred, highest)), w = unit, h = length }
		right = { x = screen.X - pad - unit, y = centred, w = unit, h = length }
		toastY = math.max(pad, belowPopcorn)
	end
	return {
		unit = unit,
		gap = gap,
		touch = touch,
		left = left,
		right = right,
		cash = cash,
		bag = bag,
		bagOverhang = overhang,
		bagStroke = bagStroke,
		toast = { x = math.floor(screen.X * 0.05), y = toastY, w = math.floor(screen.X * 0.9), h = toastH },
		popcorn = popcorn,
		popcornInHud = popcornInHud,
	}
end

-- Outlined text like the art: stroke thickness follows the label's on-screen height.
local function label(name: string, parent: Instance, color: Color3, strokeColor: Color3, weight: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.BackgroundTransparency, t.Text = name, 1, ""
	t.Font, t.TextScaled, t.TextColor3 = Theme.Font, true, color
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.LineJoinMode, stroke.Parent = strokeColor, Enum.LineJoinMode.Round, t
	t:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		stroke.Thickness = math.max(1, math.floor(t.AbsoluteSize.Y * weight + 0.5))
	end)
	t.Parent = parent
	return t
end

-- A quick bounce when a balance changes.
local function pulser(target: GuiObject): () -> ()
	local scale = Instance.new("UIScale")
	scale.Parent = target
	local current: Tween? = nil
	return function()
		if current then current:Cancel() end
		scale.Scale = 1.12
		local tween = TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 })
		current = tween
		tween:Play()
	end
end

local function menuButton(name: string, parent: Instance, order: number, onActivated: () -> ()): ImageButton
	local b = Instance.new("ImageButton")
	b.Name, b.LayoutOrder, b.Image = name, order, Theme.Hud[name]
	b.BackgroundTransparency, b.ScaleType, b.AutoButtonColor = 1, Enum.ScaleType.Fit, false
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local function to(value: number, seconds: number, style: Enum.EasingStyle)
		TweenService:Create(scale, TweenInfo.new(seconds, style), { Scale = value }):Play()
	end
	b.MouseEnter:Connect(function() to(1.07, 0.12, Enum.EasingStyle.Quad) end)
	b.MouseLeave:Connect(function() to(1, 0.12, Enum.EasingStyle.Quad) end)
	b.Activated:Connect(function()
		scale.Scale = 0.88
		to(1, 0.25, Enum.EasingStyle.Back)
		onActivated()
	end)
	b.Parent = parent
	return b
end

local function column(name: string, parent: Instance, names: { string }, actions: Actions, show: (string, number?) -> ()): Frame
	local f = Instance.new("Frame")
	f.Name, f.BackgroundTransparency = name, 1
	local list = Instance.new("UIListLayout")
	list.FillDirection, list.SortOrder = Enum.FillDirection.Vertical, Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = f
	for i, id in names do
		menuButton(id, f, i, actions[id] or function() show(id .. " · coming soon!") end)
	end
	f.Parent = parent
	return f
end

-- Anchored at the centre so the UIScale bounces grow from the middle. Sizes are rounded down
-- to even numbers so the centre, and with it every edge, lands on a whole pixel.
local function place(target: GuiObject, box: Box)
	local w, h = box.w - box.w % 2, box.h - box.h % 2
	target.AnchorPoint = Vector2.new(0.5, 0.5)
	target.Position = UDim2.fromOffset(box.x + w / 2, box.y + h / 2)
	target.Size = UDim2.fromOffset(w, h)
end

function HudController.start(actions: Actions): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "PopcornHUD", false, 1
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The bucket gets its own full-window ScreenGui so it can sit up in the top bar. It draws
	-- below the main HUD (lower DisplayOrder) so open panels cover it.
	local topGui = Instance.new("ScreenGui")
	topGui.Name, topGui.ResetOnSpawn, topGui.DisplayOrder = "PopcornHUDTop", false, 0
	topGui.ScreenInsets = Enum.ScreenInsets.None
	topGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Feedback: outlined text below the bucket, no panel, matching the rest of the HUD.
	local toast = label("Feedback", gui, WHITE, BLACK, 0.09)
	toast.Visible, toast.ZIndex = false, 5
	local toastRevision = 0
	local function show(message: string, seconds: number?)
		toastRevision += 1
		local revision = toastRevision
		toast.Text, toast.Visible = message, true
		task.delay(seconds or 2.5, function()
			if revision == toastRevision then toast.Visible = false end
		end)
	end

	local left = column("LeftButtons", gui, LEFT, actions, show)
	local right = column("RightButtons", gui, RIGHT, actions, show)

	local popcorn = Instance.new("ImageLabel")
	popcorn.Name, popcorn.Image, popcorn.BackgroundTransparency = "PopcornCounter", Theme.Hud.Popcorn, 1
	popcorn.ScaleType, popcorn.Parent = Enum.ScaleType.Fit, topGui
	local popcornCount = label("Count", popcorn, Color3.fromRGB(255, 226, 74), BLACK, 0.1)
	popcornCount.AnchorPoint, popcornCount.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.665)
	popcornCount.Size = UDim2.fromScale(0.62, 0.22)

	-- Corn bag meter: carried raw corn against the bag capacity, above the cash bar. The corn
	-- icon's left edge lines up with the bar's (and so with the cash bar's) left edge.
	local bag = Instance.new("Frame")
	bag.Name = "BagMeter"
	bag.BackgroundColor3, bag.BackgroundTransparency = Color3.fromRGB(20, 24, 30), 0.4
	Instance.new("UICorner", bag).CornerRadius = UDim.new(1, 0)
	local bagStroke = Instance.new("UIStroke")
	bagStroke.Color, bagStroke.ApplyStrokeMode, bagStroke.Parent = BLACK, Enum.ApplyStrokeMode.Border, bag
	local fill = Instance.new("Frame")
	fill.Name, fill.BackgroundColor3, fill.BorderSizePixel = "Fill", WHITE, 0
	fill.Size = UDim2.fromScale(0, 1)
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation, gradient.Parent = 90, fill
	fill.Parent = bag
	local bagText = label("Amount", bag, WHITE, BLACK, 0.12)
	bagText.AnchorPoint, bagText.Position, bagText.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.6, 0.5), UDim2.fromScale(0.64, 0.86)
	bagText.ZIndex = 2
	local corn = Instance.new("ImageLabel")
	corn.Name, corn.Image, corn.BackgroundTransparency, corn.ScaleType = "CornIcon", Theme.CornIcon, 1, Enum.ScaleType.Fit
	corn.SizeConstraint, corn.AnchorPoint = Enum.SizeConstraint.RelativeYY, Vector2.new(0, 0.5)
	corn.Position, corn.Size, corn.ZIndex = UDim2.fromScale(0, 0.5), UDim2.fromScale(CORN_ICON_SCALE, CORN_ICON_SCALE), 3
	corn.Parent = bag
	bag.Parent = gui

	local cash = Instance.new("ImageLabel")
	cash.Name, cash.Image, cash.BackgroundTransparency = "CashBar", Theme.Hud.Cash, 1
	cash.ScaleType, cash.Parent = Enum.ScaleType.Stretch, gui
	local cashText = label("Amount", cash, Color3.fromRGB(124, 240, 74), Color3.fromRGB(16, 58, 14), 0.1)
	cashText.AnchorPoint, cashText.Position, cashText.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.84, 0.72)

	local capacity = Config.Inventory.capacity
	local function render()
		local carried = (player:GetAttribute("RawCorn") or 0) :: number
		popcornCount.Text = Money.short((player:GetAttribute("Popcorn") or 0) :: number)
		cashText.Text = Money.cash((player:GetAttribute("Cash") or 0) :: number)
		bagText.Text = tostring(carried) .. "/" .. tostring(capacity)
		fill.Size = UDim2.fromScale(math.clamp(carried / capacity, 0, 1), 1)
		gradient.Color = if carried >= capacity
			then ColorSequence.new(Color3.fromRGB(255, 122, 110), Color3.fromRGB(214, 48, 58))
			else ColorSequence.new(Color3.fromRGB(255, 234, 112), Color3.fromRGB(245, 176, 40))
	end
	player.AttributeChanged:Connect(function(name)
		if name == "RawCorn" or name == "Popcorn" or name == "Cash" then render() end
	end)

	-- Touch players keep the lower corners for the thumbstick and jump button. PreferredInput
	-- follows the device the player is actually using (and the Studio emulator); older
	-- clients fall back to "touch screen without a mouse". Setting the boolean attribute
	-- TouchLayout on PopcornHUD forces either layout, for checking it in Studio.
	local function touchOnly(): boolean
		local forced = gui:GetAttribute("TouchLayout")
		if typeof(forced) == "boolean" then return forced end
		local ok, preferred = pcall(function() return (UserInput :: any).PreferredInput end)
		if ok and preferred ~= nil then return preferred == (Enum :: any).PreferredInput.Touch end
		return UserInput.TouchEnabled and not UserInput.MouseEnabled
	end
	local function layout()
		local screen, viewport = gui.AbsoluteSize, topGui.AbsoluteSize
		if screen.X <= 0 or screen.Y <= 0 or viewport.X <= 0 then return end
		local p = HudController.placements(screen, viewport, touchOnly(), GuiService.TopbarInset)
		for _, group in { left, right } do
			local list = group:FindFirstChildOfClass("UIListLayout") :: UIListLayout
			list.Padding = UDim.new(0, p.gap)
			list.FillDirection = if p.touch then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
			list.HorizontalAlignment = Enum.HorizontalAlignment.Left
			for _, child in group:GetChildren() do
				if child:IsA("ImageButton") then child.Size = UDim2.fromOffset(p.unit, p.unit) end
			end
		end
		place(left, p.left)
		place(right, p.right)
		place(cash, p.cash)
		place(bag, p.bag)
		place(toast, p.toast)
		place(popcorn, p.popcorn)
		bagStroke.Thickness = p.bagStroke
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	topGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout)
	gui:GetAttributeChangedSignal("TouchLayout"):Connect(layout)
	UserInput.LastInputTypeChanged:Connect(layout)
	pcall(function() UserInput:GetPropertyChangedSignal("PreferredInput" :: any):Connect(layout) end)

	render()
	local playerGui = player:WaitForChild("PlayerGui")
	topGui.Parent = playerGui
	gui.Parent = playerGui
	layout()
	return {
		gui = gui,
		show = show,
		pulseCorn = pulser(bag),
		pulsePopcorn = pulser(popcorn),
		pulseCash = pulser(cash),
	}
end

return HudController
