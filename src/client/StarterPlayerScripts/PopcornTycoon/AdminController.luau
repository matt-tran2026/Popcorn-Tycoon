--!strict
-- The Owner-only Developer Panel (creator request, Nov 4 2026): F4 (or the DEV button on touch
-- screens) opens five tabs of testing commands for the Owner's own profile.
-- Nothing here is trusted: the client only names a command and its arguments. The server
-- (AdminService) authorizes every request by UserId, Studio-only, and validates and applies it.
-- Ordinary players never get this UI: it is built only after the server's handshake says the
-- player is an Owner, and outside Studio the admin remote does not exist at all.
-- Fly and noclip are local movement aids for the Owner's own character (the client already
-- owns its character's physics); they are offered only inside the authorized panel.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local Money = require(Shared:WaitForChild("Money"))
local FarmUpgrades = require(Shared:WaitForChild("FarmUpgrades"))
local Theme = require(script.Parent.UITheme)
local MenuKit = require(script.Parent.MenuKit)
local player = Players.LocalPlayer
local Brick = Theme.Brick
local Controller = {}

local WIDTH, HEIGHT = 800, 580 -- design size in pixels before UIScale
local CONTENT_W = WIDTH - 52
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local OK_GREEN = Color3.fromRGB(150, 255, 120)
local BAD_RED = Color3.fromRGB(255, 120, 110)
local TABS = { "Economy", "Farming", "Upgrades", "Tools", "Player" }
local ARM_SECONDS = 2.5 -- a destructive button runs only on a second press within this time
local REFRESH_SECONDS = 2

-- "1500", "1,500", "$1.5K", "2m", "1e6" -> a number; anything else -> nil. The server re-validates.
function Controller.parseAmount(text: string): number?
	local cleaned = string.gsub(string.gsub(text, "[%s,%$_]", ""), "^%+", "")
	local digits, suffix = string.match(cleaned, "^([%d%.]+)([kKmMbBtT]?)$")
	local scale = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }
	if digits then
		local value = tonumber(digits)
		if not value then return nil end
		local factor = if suffix ~= "" then scale[string.lower(suffix)] else 1
		return math.floor(value * factor + 0.5)
	end
	local plain = tonumber(cleaned)
	if plain and plain == plain and math.abs(plain) < math.huge then return plain end
	return nil
end

function Controller.start()
	task.spawn(function()
		local remotes = Shared:WaitForChild("Remotes")
		-- Outside Studio the server never creates this remote: no panel, nothing to fire.
		local remote = remotes:WaitForChild("AdminRequest", 15) :: RemoteFunction?
		if not remote then return end
		local nextId = 0
		local function call(command: string, args: { [string]: any }?): any
			nextId += 1
			local ok, response = pcall(function() return remote:InvokeServer(nextId, command, args) end)
			if not ok or typeof(response) ~= "table" then return { ok = false, reason = "No answer from the server" } end
			-- The server refused a stale request id without running it; skip ahead so the next
			-- press works (nothing is retried automatically).
			if typeof(response.lastId) == "number" and response.lastId >= nextId then
				nextId = response.lastId
				response.reason = "Panel resynced · press the button again"
			end
			return response
		end
		local hello = call("hello")
		if not hello.ok and hello.reason == "Panel resynced · press the button again" then hello = call("hello") end
		if not hello.ok or typeof(hello.state) ~= "table" then return end
		Controller.build(call, hello.state)
	end)
end

function Controller.build(call: (string, { [string]: any }?) -> any, initial: any)
	local snapshot: any = initial
	local selectedField = "Plot1"
	local selectedCrop = Config.Plot.cropId
	local pending = false
	local renderers: { () -> () } = {}
	local userScale = 1

	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.ZIndexBehavior = "PopcornAdmin", false, 50, Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name, panel.AnchorPoint, panel.Position = "AdminPanel", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	panel.Size, panel.BackgroundColor3, panel.Visible, panel.Active = UDim2.fromOffset(WIDTH, HEIGHT), Theme.Dark, false, true
	MenuKit.corner(panel, 24)
	MenuKit.outline(panel, 5)
	local fit = Instance.new("UIScale")
	fit.Parent = panel
	local face = Instance.new("ImageLabel")
	face.Name, face.Image, face.ScaleType = "Face", Theme.Hud.Studs, Enum.ScaleType.Tile
	face.TileSize, face.BackgroundColor3 = UDim2.fromOffset(44, 44), Theme.Brown
	face.Position, face.Size = UDim2.fromOffset(9, 9), UDim2.new(1, -18, 1, -18)
	MenuKit.corner(face, 17)
	face.Parent = panel
	panel.Parent = gui

	-- Header: title, an "Owner · Studio only" chip, size buttons and the close button.
	local title = MenuKit.label("Title", panel, "Developer Panel", 40, UDim2.fromOffset(26, 14), UDim2.fromOffset(330, 46))
	title.TextXAlignment, title.TextColor3 = Enum.TextXAlignment.Left, Theme.Gold
	local chip = Instance.new("Frame")
	chip.Name, chip.BackgroundColor3, chip.Position, chip.Size = "OwnerChip", Brick.Red, UDim2.fromOffset(362, 22), UDim2.fromOffset(196, 32)
	MenuKit.corner(chip, 10)
	MenuKit.outline(chip, 2.5)
	chip.Parent = panel
	MenuKit.label("Caption", chip, "OWNER · STUDIO ONLY", 18, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8))
	local smaller = MenuKit.chunky("Smaller", panel, UDim2.new(1, -196, 0, 18), UDim2.fromOffset(52, 40), 20)
	smaller.paint(Brick.Grey, "A−")
	local bigger = MenuKit.chunky("Bigger", panel, UDim2.new(1, -138, 0, 18), UDim2.fromOffset(52, 40), 20)
	bigger.paint(Brick.Grey, "A+")
	local close = MenuKit.chunky("Close", panel, UDim2.new(1, -40, 0, -16), UDim2.fromOffset(56, 56), 34)
	close.paint(Brick.Red, "X")
	close.button.ZIndex = 3

	-- Status line: every action's server answer, green or red.
	local statusBar = Instance.new("Frame")
	statusBar.Name, statusBar.BackgroundColor3, statusBar.BackgroundTransparency = "Status", BLACK, 0.45
	statusBar.Position, statusBar.Size = UDim2.new(0, 26, 1, -60), UDim2.new(1, -52, 0, 40)
	MenuKit.corner(statusBar, 10)
	statusBar.Parent = panel
	local status = MenuKit.label("Text", statusBar, "Owner tools ready · commands change only your own test profile", 20, UDim2.fromScale(0.02, 0.1), UDim2.fromScale(0.96, 0.8))
	status.TextXAlignment = Enum.TextXAlignment.Left
	local function setStatus(text: string, color: Color3)
		status.Text, status.TextColor3 = text, color
	end

	-- Tabs and their pages.
	local pages: { [string]: ScrollingFrame } = {}
	local tabButtons: { [string]: MenuKit.Chunky } = {}
	local current = "Economy"
	local function selectTab(name: string)
		current = name
		for tab, page in pages do page.Visible = tab == name end
		for tab, chunky in tabButtons do chunky.paint(if tab == name then Brick.Yellow else Brick.Grey, tab) end
	end
	for i, name in TABS do
		local tab = MenuKit.chunky("Tab_" .. name, panel, UDim2.fromOffset(26 + (i - 1) * 150, 70), UDim2.fromOffset(142, 44), 22)
		tabButtons[name] = tab
		tab.button.Activated:Connect(function() selectTab(name) end)
		local page = Instance.new("ScrollingFrame")
		page.Name, page.BackgroundColor3, page.BackgroundTransparency = name .. "Page", BLACK, 0.55
		page.Position, page.Size = UDim2.fromOffset(26, 124), UDim2.new(1, -52, 1, -194)
		page.BorderSizePixel, page.ScrollBarThickness, page.ScrollBarImageColor3 = 0, 8, Theme.Cream
		page.AutomaticCanvasSize, page.CanvasSize, page.Visible = Enum.AutomaticSize.Y, UDim2.new(), false
		MenuKit.corner(page, 14)
		local list = Instance.new("UIListLayout")
		list.Padding, list.SortOrder, list.Parent = UDim.new(0, 8), Enum.SortOrder.LayoutOrder, page
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 18), UDim.new(0, 10), UDim.new(0, 12)
		pad.Parent = page
		page.Parent = panel
		pages[name] = page
	end

	-- Building blocks -------------------------------------------------------------------------
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function heading(page: Instance, text: string)
		local label = MenuKit.label("Heading", page, text, 24, UDim2.new(), UDim2.new(1, 0, 0, 30))
		label.TextXAlignment, label.TextColor3, label.LayoutOrder = Enum.TextXAlignment.Left, Theme.Gold, nextOrder()
	end

	-- A multi-line info block re-rendered from the snapshot and the replicated attributes.
	local function info(page: Instance, render: () -> string): TextLabel
		local label = Instance.new("TextLabel")
		label.Name, label.BackgroundColor3, label.BackgroundTransparency = "Info", Color3.fromRGB(14, 26, 60), 0.3
		label.Size, label.AutomaticSize, label.LayoutOrder = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y, nextOrder()
		label.Font, label.TextSize, label.TextColor3, label.TextWrapped = Theme.Font, 19, Theme.Cream, true
		label.TextXAlignment, label.TextYAlignment, label.RichText = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top, true
		MenuKit.corner(label, 10)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 8), UDim.new(0, 8)
		pad.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color, stroke.Thickness, stroke.ApplyStrokeMode, stroke.Parent = BLACK, 2, Enum.ApplyStrokeMode.Border, label
		label.Parent = page
		table.insert(renderers, function() label.Text = render() end)
		return label
	end

	local function row(page: Instance, height: number?): Frame
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Size, frame.LayoutOrder = UDim2.new(1, 0, 0, height or 44), nextOrder()
		-- Unique names (Row7, B_Give) give every button a stable path for Studio automation.
		frame.Name = "Row" .. tostring(frame.LayoutOrder)
		local list = Instance.new("UIListLayout")
		list.FillDirection, list.Padding, list.SortOrder = Enum.FillDirection.Horizontal, UDim.new(0, 8), Enum.SortOrder.LayoutOrder
		list.VerticalAlignment, list.Parent = Enum.VerticalAlignment.Center, frame
		frame.Parent = page
		return frame
	end

	local function caption(parent: Instance, text: string, width: number): TextLabel
		local label = MenuKit.label("Caption", parent, text, 20, UDim2.new(), UDim2.fromOffset(width, 40))
		label.TextXAlignment = Enum.TextXAlignment.Left
		return label
	end

	local function box(parent: Instance, placeholder: string, width: number): TextBox
		local b = Instance.new("TextBox")
		b.Name, b.PlaceholderText, b.Text, b.ClearTextOnFocus = "Input", placeholder, "", false
		b.Size, b.BackgroundColor3, b.TextColor3, b.PlaceholderColor3 = UDim2.fromOffset(width, 40), Color3.fromRGB(24, 18, 14), Theme.Cream, Theme.Muted
		b.Font, b.TextSize = Theme.Font, 20
		MenuKit.corner(b, 10)
		MenuKit.outline(b, 2.5)
		b.Parent = parent
		return b
	end

	-- Sends one command; refuses while another is in flight, so a double click never repeats it.
	local function send(command: string, args: { [string]: any }?, label: string?)
		if pending then setStatus("Still working on the last command…", Theme.Gold) return end
		pending = true
		setStatus((label or command) .. "…", Theme.Cream)
		task.spawn(function()
			local response = call(command, args)
			pending = false
			if typeof(response.state) == "table" then snapshot = response.state end
			setStatus(tostring(response.reason), if response.ok then OK_GREEN else BAD_RED)
			for _, render in renderers do render() end
		end)
	end

	-- A chunky button. Destructive ones arm on the first press ("Sure?") and run on the second.
	local function button(parent: Instance, text: string, width: number, color: Color3, action: () -> (), destructive: boolean?): MenuKit.Chunky
		local chunky = MenuKit.chunky("B_" .. (string.gsub(text, "[^%w]", "")), parent, UDim2.new(), UDim2.fromOffset(width, 40), 20)
		chunky.paint(color, text)
		local armed = false
		chunky.button.Activated:Connect(function()
			if destructive and not armed then
				armed = true
				chunky.paint(Brick.Red, "Sure?")
				setStatus("Press again to confirm: " .. text, Theme.Gold)
				task.delay(ARM_SECONDS, function()
					if armed then
						armed = false
						chunky.paint(color, text)
					end
				end)
				return
			end
			if armed then
				armed = false
				chunky.paint(color, text)
			end
			action()
		end)
		return chunky
	end

	local function amountFrom(input: TextBox): number?
		local value = Controller.parseAmount(input.Text)
		if not value then setStatus("Enter an amount such as 5000, 2.5K or 1M", BAD_RED) end
		return value
	end

	local function field(id: string?): any
		for _, f in snapshot.fields do if f.id == id then return f end end
		return nil
	end

	local function singleField(): string?
		if selectedField == "*" then setStatus("Pick a single plot for this command", BAD_RED) return nil end
		return selectedField
	end

	-- A plot picker row (shared selection across tabs); `all` adds an "All plots" choice.
	local pickers: { () -> () } = {}
	local function fieldPicker(page: Instance, all: boolean)
		local frame = row(page, 44)
		local function render()
			for _, child in frame:GetChildren() do if child:IsA("GuiButton") or child:IsA("TextLabel") then child:Destroy() end end
			caption(frame, "Plot:", 52)
			for _, f in snapshot.fields do
				local id = f.id
				local b = button(frame, tostring(f.plot), 44, if selectedField == id then Brick.Yellow else Brick.Grey, function()
					selectedField = id
					for _, other in pickers do other() end
					for _, r in renderers do r() end
				end)
				b.button.LayoutOrder = f.plot
			end
			if all then
				local b = button(frame, "All", 64, if selectedField == "*" then Brick.Yellow else Brick.Grey, function()
					selectedField = "*"
					for _, other in pickers do other() end
					for _, r in renderers do r() end
				end)
				b.button.LayoutOrder = 100
			end
		end
		table.insert(pickers, render)
	end

	local function plotLine(f: any): string
		return string.format("<b>%s</b> · %s · %d stalks (%d/%d rows)\nSoil Lv %d · Yield Lv %d · Storage Lv %d\nGrowth %s per cycle · %d corn per cycle · stores %d cycles = <b>%d max corn per stalk</b>\nReady now: %d corn on %d stalks (%d full)",
			f.id, f.crop, f.stalks, f.rows, f.maxRows, f.Soil, f.Yield, f.Storage,
			(string.gsub(string.format("%.1f", f.growthSeconds), "%.0$", "")) .. " s", f.cornPerYield, f.maxYields, f.maxCorn,
			f.readyCorn, f.readyStalks, f.fullStalks)
	end

	local function attr(name: string): number
		local value = player:GetAttribute(name)
		return if typeof(value) == "number" then value else 0
	end

	-- Economy -------------------------------------------------------------------------------
	local economy = pages.Economy
	info(economy, function()
		return string.format("Cash <b>%s</b> · Popcorn <b>%s</b> · Raw corn <b>%d / %d</b>", Money.cash(attr("Cash")), Money.short(attr("Popcorn")), attr("RawCorn"), attr("BagCapacity"))
	end)
	for _, spec in { { "Cash", "cash", Brick.Green }, { "Popcorn", "popcorn", Brick.Yellow } } do
		local name, prefix, color = spec[1] :: string, spec[2] :: string, spec[3] :: Color3
		heading(economy, name)
		local r = row(economy)
		local input = box(r, if name == "Cash" then "amount, e.g. 2.5M" else "amount, e.g. 500", 190)
		button(r, "Give", 92, color, function() local v = amountFrom(input) if v then send(prefix .. ".add", { amount = v }, "Give " .. name) end end)
		button(r, "Set", 80, Brick.Blue, function() local v = amountFrom(input) if v then send(prefix .. ".set", { amount = v }, "Set " .. name) end end)
		button(r, "Remove", 104, Brick.Orange, function() local v = amountFrom(input) if v then send(prefix .. ".remove", { amount = v }, "Remove " .. name) end end)
		button(r, if name == "Cash" then "Zero" else "Clear", 92, Brick.Red, function() send(prefix .. ".zero", nil, "Clear " .. name) end, true)
		local presets = row(economy)
		local amounts = if name == "Cash" then { 1e3, 1e5, 1e6, 1e9 } else { 100, 1e3, 1e4, 1e6 }
		for _, amount in amounts do
			local text = "+" .. (if name == "Cash" then Money.cash(amount) else Money.short(amount))
			button(presets, text, 112, color, function() send(prefix .. ".add", { amount = amount }, text .. " " .. name) end)
		end
		button(presets, "Max", 92, Brick.Blue, function() send(prefix .. ".max", nil, "Max " .. name) end)
	end
	heading(economy, "Raw corn (backpack)")
	local cornRow = row(economy)
	local cropIds = {}
	for id in Config.Crops do table.insert(cropIds, id) end
	table.sort(cropIds)
	local cropButton = button(cornRow, Config.Crops[selectedCrop].displayName, 170, Brick.Grey, function() end)
	cropButton.button.Activated:Connect(function()
		-- Cycles through every corn variety in Config.Crops (only Normal Corn exists today).
		local index = table.find(cropIds, selectedCrop) or 0
		selectedCrop = cropIds[index % #cropIds + 1]
		cropButton.paint(Brick.Grey, Config.Crops[selectedCrop].displayName)
	end)
	local cornInput = box(cornRow, "amount", 110)
	button(cornRow, "Add", 80, Brick.Green, function() local v = amountFrom(cornInput) if v then send("corn.add", { cropId = selectedCrop, amount = v }, "Add corn") end end)
	button(cornRow, "Fill bag", 112, Brick.Yellow, function() send("corn.fill", { cropId = selectedCrop }, "Fill bag") end)
	button(cornRow, "Empty", 92, Brick.Red, function() send("corn.empty", nil, "Empty bag") end, true)

	-- Farming -------------------------------------------------------------------------------
	local farming = pages.Farming
	fieldPicker(farming, true)
	info(farming, function()
		if selectedField == "*" then
			local lines = {}
			for _, f in snapshot.fields do table.insert(lines, plotLine(f)) end
			return table.concat(lines, "\n\n")
		end
		local f = field(selectedField)
		return if f then plotLine(f) else "Pick one of your plots"
	end)
	heading(farming, "Growth (selected plot)")
	local growRow = row(farming)
	button(growRow, "Instantly Grow All Corn", 250, Brick.Green, function() send("field.grow", { fieldId = selectedField }, "Grow") end)
	button(growRow, "Fill All Stalks to Maximum", 270, Brick.Yellow, function() send("field.fill", { fieldId = selectedField }, "Fill stalks") end)
	button(growRow, "Reset Growth", 160, Brick.Red, function() send("field.reset", { fieldId = selectedField }, "Reset growth") end, true)
	local progressRow = row(farming)
	caption(progressRow, "Progress:", 96)
	for _, percent in { 0, 25, 50, 75, 100 } do
		button(progressRow, tostring(percent) .. "%", 72, Brick.Blue, function() send("field.progress", { fieldId = selectedField, percent = percent }, tostring(percent) .. "% grown") end)
	end
	local percentInput = box(progressRow, "%", 64)
	button(progressRow, "Set", 64, Brick.Blue, function()
		local v = tonumber((string.gsub(percentInput.Text, "[%s%%]", "")))
		if not v then setStatus("Enter a percent from 0 to 100", BAD_RED) return end
		send("field.progress", { fieldId = selectedField, percent = v }, "Set growth")
	end)
	heading(farming, "Land (free, same pads rules)")
	info(farming, function()
		local f = field(selectedField)
		return string.format("Plots owned <b>%d / %d</b> · Rows bought across plots <b>%d</b>%s", snapshot.plots, snapshot.maxPlots, snapshot.rowsBought,
			if f then string.format(" · %s has %d / %d rows", f.id, f.rows, f.maxRows) else "")
	end)
	local landRow = row(farming)
	button(landRow, "Unlock Next Plot", 180, Brick.Green, function() send("land.plot", nil, "Unlock plot") end)
	button(landRow, "Add Row", 112, Brick.Green, function() local id = singleField() if id then send("land.row", { fieldId = id }, "Add row") end end)
	button(landRow, "Unlock All Plots", 180, Brick.Yellow, function() send("land.allPlots", nil, "Unlock all plots") end)
	button(landRow, "Fill All Rows", 156, Brick.Yellow, function() send("land.allRows", nil, "Fill all rows") end)

	-- Upgrades ------------------------------------------------------------------------------
	local upgrades = pages.Upgrades
	fieldPicker(upgrades, true)
	heading(upgrades, "Levels (field upgrades use the selected plot)")
	for _, upgradeId in Config.FarmUpgradeOrder do
		local definition = Config.FarmUpgrades[upgradeId]
		local max = FarmUpgrades.maxLevel(upgradeId)
		local r = row(upgrades)
		local label = caption(r, definition.displayName, 262)
		local function args(extra: { [string]: any }?): { [string]: any }
			local a: { [string]: any } = { upgradeId = upgradeId }
			if definition.scope == "Field" then a.fieldId = selectedField end
			for k, v in extra or {} do a[k] = v end
			return a
		end
		table.insert(renderers, function()
			local level: number? = nil
			if definition.scope == "Global" then
				level = snapshot.Backpack
			elseif selectedField == "*" then
				for _, f in snapshot.fields do
					if level == nil then level = f[upgradeId] elseif level ~= f[upgradeId] then level = -1 end
				end
			else
				local f = field(selectedField)
				level = if f then f[upgradeId] else nil
			end
			local where = if definition.scope == "Global" then "player" elseif selectedField == "*" then "all plots" else selectedField
			local shown = if level == nil then "?" elseif level < 0 then "mixed" else tostring(level)
			local effect = if level and level >= 0 then " · " .. FarmUpgrades.describe(upgradeId, level) else ""
			label.Text = string.format("%s Lv %s/%d (%s)%s", definition.displayName, shown, max, where, effect)
		end)
		local levelInput = box(r, "0-" .. tostring(max), 62)
		button(r, "Set", 64, Brick.Blue, function()
			local v = tonumber(levelInput.Text)
			if not v then setStatus("Enter a level from 0 to " .. tostring(max), BAD_RED) return end
			send("upgrade.set", args({ level = v }), "Set " .. definition.displayName)
		end)
		button(r, "+1", 56, Brick.Green, function() send("upgrade.step", args(), definition.displayName .. " +1") end)
		button(r, "Max", 70, Brick.Yellow, function() send("upgrade.max", args(), "Max " .. definition.displayName) end)
		button(r, "Reset", 80, Brick.Red, function() send("upgrade.reset", args(), "Reset " .. definition.displayName) end, true)
	end
	heading(upgrades, "Everything (Backpack and every owned plot)")
	local allRow = row(upgrades)
	button(allRow, "Max All Upgrades", 210, Brick.Yellow, function() send("upgrades.maxAll", nil, "Max all upgrades") end)
	button(allRow, "Reset All Upgrades", 220, Brick.Red, function() send("upgrades.resetAll", nil, "Reset all upgrades") end, true)

	-- Tools ---------------------------------------------------------------------------------
	local tools = pages.Tools
	heading(tools, "Harvesting tools (from Config.Tools)")
	local handsRow = row(tools)
	local handsLabel = caption(handsRow, "Hands (Manual)", 380)
	button(handsRow, "Equip", 92, Brick.Blue, function() send("tool.equip", { toolId = "Manual" }, "Equip hands") end)
	table.insert(renderers, function()
		handsLabel.Text = "Hands (Manual) · always owned" .. (if snapshot.equippedTool == "Manual" then " · equipped" else "")
	end)
	for _, tool in snapshot.tools do
		local toolId = tool.id
		local r = row(tools)
		local label = caption(r, tool.name, 380)
		button(r, "Give", 80, Brick.Green, function() send("tool.give", { toolId = toolId }, "Give " .. tool.name) end)
		button(r, "Equip", 92, Brick.Blue, function() send("tool.equip", { toolId = toolId }, "Equip " .. tool.name) end)
		button(r, "Remove", 104, Brick.Red, function() send("tool.remove", { toolId = toolId }, "Remove " .. tool.name) end, true)
		table.insert(renderers, function()
			local now: any = nil
			for _, t in snapshot.tools do if t.id == toolId then now = t end end
			local owned = now and now.owned
			label.Text = tool.name .. " · " .. (if owned then "owned" else "not owned") .. (if snapshot.equippedTool == toolId then " · equipped" else "")
		end)
	end
	local toolRow = row(tools)
	button(toolRow, "Unlock All Tools", 200, Brick.Yellow, function() send("tool.giveAll", nil, "Unlock all tools") end)
	button(toolRow, "Reset to Starter Tools", 250, Brick.Red, function() send("tool.reset", nil, "Reset tools") end, true)

	-- Player / Testing ----------------------------------------------------------------------
	local testing = pages.Player
	info(testing, function()
		local f = field(selectedField)
		local levels = {}
		for _, plot in snapshot.fields do table.insert(levels, string.format("%s %d/%d/%d", plot.id, plot.Soil, plot.Yield, plot.Storage)) end
		local equipped = snapshot.equippedTool
		local toolName = if equipped == "Manual" then "Hands" elseif Config.Tools[equipped] then Config.Tools[equipped].displayName else tostring(equipped)
		return string.format("<b>%s</b> (@%s) · UserId %d\nCash %s · Popcorn %s · Raw corn %d / %d · Holding %s\nPlots %d / %d · Backpack Lv %d · Plot Soil/Yield/Storage: %s\nSelected plot: %s · Walk speed %s",
			snapshot.displayName, snapshot.name, snapshot.userId, Money.cash(attr("Cash")), Money.short(attr("Popcorn")), attr("RawCorn"), attr("BagCapacity"), toolName,
			snapshot.plots, snapshot.maxPlots, snapshot.Backpack, table.concat(levels, " · "),
			if selectedField == "*" then "all plots" elseif f then f.id else "none", tostring(snapshot.walkSpeed or "?"))
	end)
	fieldPicker(testing, false)
	heading(testing, "Teleport")
	local tpRow = row(testing)
	button(tpRow, "Farm Entrance", 170, Brick.Green, function() send("tp.farm", nil, "Teleport") end)
	button(tpRow, "Central Hub", 150, Brick.Blue, function() send("tp.hub", nil, "Teleport") end)
	button(tpRow, "Selected Plot", 160, Brick.Yellow, function() local id = singleField() if id then send("tp.plot", { fieldId = id }, "Teleport") end end)
	heading(testing, "Movement (your character only; a respawn restores normal)")
	local speedRow = row(testing)
	for _, speed in { 32, 64, 100 } do
		button(speedRow, "Speed " .. tostring(speed), 120, Brick.Green, function() send("move.speed", { speed = speed }, "Walk speed") end)
	end
	local speedInput = box(speedRow, "speed", 80)
	button(speedRow, "Set", 64, Brick.Blue, function()
		local v = tonumber(speedInput.Text)
		if not v then setStatus("Enter a walk speed", BAD_RED) return end
		send("move.speed", { speed = v }, "Walk speed")
	end)
	button(speedRow, "Normal", 100, Brick.Grey, function() send("move.reset", nil, "Walk speed") end)

	-- Fly and noclip: local aids on the Owner's own character, undone when switched off or on respawn.
	local flyState: { conn: RBXScriptConnection?, velocity: LinearVelocity?, align: AlignOrientation?, attachment: Attachment?, humanoid: Humanoid? } = {}
	local noclip: { conn: RBXScriptConnection?, saved: { [BasePart]: boolean } } = { saved = {} }
	local moveRow = row(testing)
	local flyButton: MenuKit.Chunky
	local noclipButton: MenuKit.Chunky
	local function stopFly()
		if flyState.conn then flyState.conn:Disconnect() end
		for _, item in { flyState.velocity, flyState.align, flyState.attachment } :: { Instance? } do if item then item:Destroy() end end
		if flyState.humanoid then flyState.humanoid.PlatformStand = false end
		flyState = {}
		flyButton.paint(Brick.Grey, "Fly: Off")
	end
	local function startFly(): boolean
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		-- lihfolk-ignore: findfirstchild-chain (nil-checked on the next line)
		local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if not humanoid or not root then return false end
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Parent = "AdminFly", root
		local velocity = Instance.new("LinearVelocity")
		velocity.Name, velocity.Attachment0, velocity.MaxForce = "AdminFly", attachment, math.huge
		velocity.VelocityConstraintMode, velocity.RelativeTo = Enum.VelocityConstraintMode.Vector, Enum.ActuatorRelativeTo.World
		velocity.VectorVelocity, velocity.Parent = Vector3.zero, root
		local align = Instance.new("AlignOrientation")
		align.Name, align.Mode, align.Attachment0, align.RigidityEnabled = "AdminFly", Enum.OrientationAlignmentMode.OneAttachment, attachment, true
		align.Parent = root
		humanoid.PlatformStand = true
		flyState = { velocity = velocity, align = align, attachment = attachment, humanoid = humanoid }
		flyState.conn = RunService.RenderStepped:Connect(function()
			local camera = workspace.CurrentCamera
			if not camera or not root.Parent then stopFly() return end
			local look = camera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 1e-3 then align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) end
			local vertical = (if Input:IsKeyDown(Enum.KeyCode.Space) then 1 else 0) - (if Input:IsKeyDown(Enum.KeyCode.LeftControl) then 1 else 0)
			velocity.VectorVelocity = (humanoid.MoveDirection + Vector3.new(0, vertical, 0)) * 60
		end)
		flyButton.paint(Brick.Green, "Fly: On")
		return true
	end
	local function stopNoclip()
		if noclip.conn then noclip.conn:Disconnect() end
		for part, collide in noclip.saved do if part.Parent then part.CanCollide = collide end end
		noclip = { saved = {} }
		noclipButton.paint(Brick.Grey, "Noclip: Off")
	end
	local function startNoclip()
		noclip.conn = RunService.Stepped:Connect(function()
			local character = player.Character
			if not character then return end
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") and part.CanCollide then
					if noclip.saved[part] == nil then noclip.saved[part] = true end
					part.CanCollide = false
				end
			end
		end)
		noclipButton.paint(Brick.Green, "Noclip: On")
	end
	flyButton = button(moveRow, "Fly: Off", 140, Brick.Grey, function()
		if flyState.conn then stopFly() setStatus("Fly off", OK_GREEN)
		elseif startFly() then setStatus("Fly on · move to steer, Space up, Ctrl down", OK_GREEN)
		else setStatus("Character unavailable", BAD_RED) end
	end)
	noclipButton = button(moveRow, "Noclip: Off", 160, Brick.Grey, function()
		if noclip.conn then stopNoclip() setStatus("Noclip off", OK_GREEN) else startNoclip() setStatus("Noclip on · walk through walls", OK_GREEN) end
	end)
	player.CharacterAdded:Connect(function()
		if flyState.conn then stopFly() end
		if noclip.conn then stopNoclip() end
	end)

	-- Opening, closing, scaling and refreshing ------------------------------------------------
	local function layout()
		local screen = gui.AbsoluteSize
		local target = math.clamp(math.min(screen.X * 0.96 / (WIDTH + 30), screen.Y * 0.92 / (HEIGHT + 30)), 0.4, 1.25)
		fit.Scale = target * userScale
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	smaller.button.Activated:Connect(function() userScale = math.max(0.6, userScale - 0.1) layout() end)
	bigger.button.Activated:Connect(function() userScale = math.min(1.4, userScale + 0.1) layout() end)

	local refreshing = false
	local function toggle(visible: boolean?)
		local open = if visible == nil then not panel.Visible else visible
		if open == panel.Visible then return end
		panel.Visible = open
		if not open then return end
		layout()
		local target = fit.Scale
		fit.Scale = target * 0.6
		TweenService:Create(fit, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = target }):Play()
		send("state", nil, "Refreshing")
		if refreshing then return end
		refreshing = true
		-- Ready-corn counts change with time; refresh quietly while the panel is open.
		task.spawn(function()
			while panel.Visible do
				task.wait(REFRESH_SECONDS)
				if panel.Visible and not pending then
					pending = true
					local response = call("state")
					pending = false
					if typeof(response.state) == "table" then snapshot = response.state end
					for _, render in renderers do render() end
				end
			end
			refreshing = false
		end)
	end
	close.button.Activated:Connect(function() toggle(false) end)

	-- The DEV button for touch screens (Owner only, since this whole UI exists only for Owners).
	local devButton = MenuKit.chunky("DevButton", gui, UDim2.new(1, -66, 0.42, 0), UDim2.fromOffset(58, 46), 20)
	devButton.paint(Brick.Red, "DEV")
	devButton.button.Visible = Input.TouchEnabled
	devButton.button.Activated:Connect(function() toggle() end)

	Input.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.F4 then toggle() end
		if input.KeyCode == Enum.KeyCode.Escape then toggle(false) end
	end)
	-- Balances in the info blocks follow the replicated attributes immediately.
	player.AttributeChanged:Connect(function(name)
		if panel.Visible and (name == "Cash" or name == "Popcorn" or name == "RawCorn" or name == "BagCapacity") then
			for _, render in renderers do render() end
		end
	end)
	for _, render in pickers do render() end
	for _, render in renderers do render() end
	selectTab(current)
	print("[PopcornTycoon] Developer Panel available (F4).")
end

return Controller
