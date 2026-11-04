--!strict
-- UI juice shared by the HUD and menus (Nov 3 2026 "10000x cooler" pass): a spinning coin
-- sprite, rotating sunbursts, rolling number counters, icons that burst out and fly into a
-- counter, floating "+$24" text, popcorn confetti and the join splash. Art was rendered in
-- Blender (logo, coin sheet, popcorn piece) or drawn with PIL (sunburst, sparkle); sources are
-- in the vault's Assets/UI/v2. One Heartbeat drives every looping animation here.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local UIFx = {}

UIFx.Art = {
	CoinSheet = "rbxassetid://101301469414041", -- 4x4 grid of 160 px frames, one full turn
	Logo = "rbxassetid://121151235150792",
	Popcorn = "rbxassetid://112894460849000",
	Sparkle = "rbxassetid://96542276860825",
	Sunburst = "rbxassetid://90019751463359",
}
local COIN_FRAMES, COIN_COLUMNS, COIN_CELL, COIN_FPS = 16, 4, 160, 14
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
local rng = Random.new()

local coins: { ImageLabel } = {}
local spinners: { { gui: GuiObject, speed: number } } = {}
local clock = os.clock()
RunService.Heartbeat:Connect(function()
	local t = os.clock() - clock
	local frame = math.floor(t * COIN_FPS) % COIN_FRAMES
	local offset = Vector2.new((frame % COIN_COLUMNS) * COIN_CELL, math.floor(frame / COIN_COLUMNS) * COIN_CELL)
	for i = #coins, 1, -1 do
		local c = coins[i]
		if c.Parent then c.ImageRectOffset = offset else table.remove(coins, i) end
	end
	for i = #spinners, 1, -1 do
		local s = spinners[i]
		if s.gui.Parent then s.gui.Rotation = (t * s.speed) % 360 else table.remove(spinners, i) end
	end
end)

-- A spinning gold coin (sprite sheet).
function UIFx.coin(parent: Instance?): ImageLabel
	local c = Instance.new("ImageLabel")
	c.Name, c.BackgroundTransparency, c.Image = "Coin", 1, UIFx.Art.CoinSheet
	c.ImageRectSize, c.ScaleType = Vector2.new(COIN_CELL, COIN_CELL), Enum.ScaleType.Fit
	c.Parent = parent
	table.insert(coins, c)
	return c
end

-- A slowly turning sunburst (white art, tint with ImageColor3).
function UIFx.sunburst(parent: Instance?, color: Color3, speed: number): ImageLabel
	local s = Instance.new("ImageLabel")
	s.Name, s.BackgroundTransparency, s.Image = "Sunburst", 1, UIFx.Art.Sunburst
	s.ImageColor3, s.AnchorPoint = color, Vector2.new(0.5, 0.5)
	s.Parent = parent
	table.insert(spinners, { gui = s, speed = speed })
	return s
end

-- Fredoka One text with a black outline that follows the label's height.
function UIFx.label(name: string, parent: Instance?, color: Color3, weight: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.BackgroundTransparency, t.Text = name, 1, ""
	t.Font, t.TextScaled, t.TextColor3 = Theme.Font, true, color
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.LineJoinMode, stroke.Parent = BLACK, Enum.LineJoinMode.Round, t
	local function fit() stroke.Thickness = math.max(1, math.floor(t.AbsoluteSize.Y * weight + 0.5)) end
	t:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	t.Parent = parent
	return t
end

-- Rolls a label from its shown value to each new value (eased, longer for bigger jumps).
function UIFx.counter(label: TextLabel, format: (number) -> string): (value: number) -> ()
	local shown: number? = nil
	local target = 0
	local connection: RBXScriptConnection? = nil
	return function(value: number)
		target = value
		if shown == nil or shown == value then
			shown = value
			label.Text = format(value)
			return
		end
		local from = shown :: number
		local started = os.clock()
		local duration = math.clamp(0.3 + math.log10(math.abs(value - from) + 1) * 0.14, 0.3, 1)
		if connection then connection:Disconnect() end
		connection = RunService.Heartbeat:Connect(function()
			local a = math.clamp((os.clock() - started) / duration, 0, 1)
			local eased = 1 - (1 - a) ^ 3
			local now = from + (target - from) * eased
			shown = now
			label.Text = format(if a >= 1 then target else math.floor(now + 0.5))
			if a >= 1 and connection then
				shown = target
				connection:Disconnect()
				connection = nil
			end
		end)
	end
end

-- The full-window effects layer every burst and flight is drawn in.
function UIFx.layer(playerGui: Instance): ScreenGui
	local fx = Instance.new("ScreenGui")
	fx.Name, fx.ResetOnSpawn, fx.DisplayOrder = "PopcornFx", false, 20
	fx.ScreenInsets, fx.ZIndexBehavior = Enum.ScreenInsets.None, Enum.ZIndexBehavior.Sibling
	fx.Parent = playerGui
	return fx
end

-- Centre of a GuiObject in `fx` coordinates (both AbsolutePositions share one origin).
function UIFx.centerOf(fx: ScreenGui, target: GuiObject): Vector2
	return target.AbsolutePosition + target.AbsoluteSize / 2 - fx.AbsolutePosition
end

-- A point in the 3D world, in `fx` coordinates.
function UIFx.worldPoint(fx: ScreenGui, position: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local point, visible = camera:WorldToScreenPoint(position)
	if not visible then return nil end
	return Vector2.new(point.X, point.Y) - fx.AbsolutePosition
end

local function icon(fx: ScreenGui, image: string, size: number, at: Vector2): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency, i.Image, i.ScaleType = 1, image, Enum.ScaleType.Fit
	i.AnchorPoint, i.Position, i.Size = Vector2.new(0.5, 0.5), UDim2.fromOffset(at.X, at.Y), UDim2.fromOffset(0, 0)
	i.ZIndex, i.Parent = 10, fx
	return i
end

-- `count` icons burst out around `from`, then fly into `target`; `arrive` runs as the first lands.
-- image "Coin" uses the spinning coin sprite.
function UIFx.fly(fx: ScreenGui, image: string, from: Vector2, target: GuiObject, count: number, size: number, arrive: (() -> ())?)
	local landed = false
	for n = 1, count do
		local i = if image == "Coin" then UIFx.coin(fx) else icon(fx, image, size, from)
		i.AnchorPoint, i.Position, i.Size, i.ZIndex = Vector2.new(0.5, 0.5), UDim2.fromOffset(from.X, from.Y), UDim2.fromOffset(0, 0), 10
		i.Rotation = rng:NextNumber(-25, 25)
		local angle = rng:NextNumber(0, 2 * math.pi)
		local spread = from + Vector2.new(math.cos(angle), math.sin(angle)) * rng:NextNumber(size * 0.8, size * 2.2)
		TweenService:Create(i, TweenInfo.new(0.28, Enum.EasingStyle.Back), {
			Position = UDim2.fromOffset(spread.X, spread.Y), Size = UDim2.fromOffset(size, size),
		}):Play()
		task.delay(0.3 + n * 0.05, function()
			if not i.Parent then return end
			local goal = if target.Parent then UIFx.centerOf(fx, target) else spread
			local tween = TweenService:Create(i, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(goal.X, goal.Y), Size = UDim2.fromOffset(size * 0.55, size * 0.55), Rotation = 0,
			})
			tween.Completed:Once(function()
				i:Destroy()
				if not landed then
					landed = true
					if arrive then arrive() end
				end
			end)
			tween:Play()
		end)
	end
end

-- Outlined text that pops in at `at`, rises and fades.
function UIFx.floatText(fx: ScreenGui, text: string, color: Color3, at: Vector2, height: number)
	local t = UIFx.label("FloatText", nil, color, 0.12)
	t.Text, t.AnchorPoint, t.ZIndex = text, Vector2.new(0.5, 0.5), 11
	t.Size, t.Position = UDim2.fromOffset(height * 6, height), UDim2.fromOffset(at.X, at.Y)
	t.Rotation = rng:NextNumber(-8, 8)
	local scale = Instance.new("UIScale")
	scale.Scale, scale.Parent = 0.3, t
	t.Parent = fx
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(t, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(at.X, at.Y - height * 2.2), Rotation = 0,
	}):Play()
	task.delay(0.7, function()
		TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local stroke = t:FindFirstChildOfClass("UIStroke")
		if stroke then TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play() end
	end)
	task.delay(1.15, function() t:Destroy() end)
end

-- Popcorn confetti: pieces pop up from `at` and fall with gravity, spinning.
function UIFx.popcornBurst(fx: ScreenGui, at: Vector2, count: number, size: number, power: number?)
	local strength = power or 1
	local pieces = {}
	for _ = 1, count do
		local p = icon(fx, UIFx.Art.Popcorn, size, at)
		local s = size * rng:NextNumber(0.7, 1.2)
		p.Size = UDim2.fromOffset(s, s)
		table.insert(pieces, {
			gui = p, pos = at, vel = Vector2.new(rng:NextNumber(-260, 260), rng:NextNumber(-620, -340)) * strength,
			spin = rng:NextNumber(-400, 400),
		})
	end
	local started, last = os.clock(), os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 0.05)
		last = now
		local age = now - started
		for _, p in pieces do
			p.vel += Vector2.new(0, 1500 * strength * dt)
			p.pos += p.vel * dt
			p.gui.Position = UDim2.fromOffset(p.pos.X, p.pos.Y)
			p.gui.Rotation += p.spin * dt
			if age > 0.8 then p.gui.ImageTransparency = math.clamp((age - 0.8) / 0.5, 0, 1) end
		end
		if age > 1.3 then
			connection:Disconnect()
			for _, p in pieces do p.gui:Destroy() end
		end
	end)
end

-- Join splash: the Blender logo bounces in over a turning golden sunburst with a popcorn
-- shower, holds, then zooms away. Purely decorative and never blocks input.
function UIFx.splash(fx: ScreenGui)
	local root = Instance.new("Frame")
	root.Name, root.BackgroundTransparency, root.Size = "Splash", 1, UDim2.fromScale(1, 1)
	root.ZIndex, root.Parent = 20, fx
	local view = fx.AbsoluteSize
	local short = math.min(view.X, view.Y)
	local burst = UIFx.sunburst(root, Color3.fromRGB(255, 214, 90), 25)
	burst.Position, burst.Size = UDim2.fromScale(0.5, 0.42), UDim2.fromOffset(short * 1.3, short * 1.3)
	burst.ImageTransparency, burst.ZIndex = 1, 20
	local logo = Instance.new("ImageLabel")
	logo.Name, logo.Image, logo.BackgroundTransparency = "Logo", UIFx.Art.Logo, 1
	logo.ScaleType, logo.AnchorPoint = Enum.ScaleType.Fit, Vector2.new(0.5, 0.5)
	logo.Position, logo.ZIndex = UDim2.fromScale(0.5, 0.42), 21
	local width = math.min(view.X * 0.82, short * 1.6)
	logo.Size = UDim2.fromOffset(width, width * 664 / 1424)
	local scale = Instance.new("UIScale")
	scale.Scale, scale.Parent = 0, logo
	logo.Rotation = -12
	logo.Parent = root
	TweenService:Create(burst, TweenInfo.new(0.5), { ImageTransparency = 0.35 }):Play()
	TweenService:Create(scale, TweenInfo.new(0.7, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(logo, TweenInfo.new(0.9, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
	task.delay(0.35, function()
		local center = Vector2.new(view.X * 0.5, view.Y * 0.42)
		UIFx.popcornBurst(fx, center, 18, short * 0.07, 1.25)
	end)
	task.delay(2.8, function()
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		TweenService:Create(burst, TweenInfo.new(0.45), { ImageTransparency = 1 }):Play()
		task.delay(0.5, function() root:Destroy() end)
	end)
end

return UIFx
