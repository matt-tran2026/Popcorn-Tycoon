--!strict
-- Shared pieces of the studded brick menus (Shop, Upgrades): black outlines, top-lit shading,
-- outlined Fredoka One labels and chunky press-bouncing buttons. Moved out of ShopController
-- on Nov 4 2026 so both menus stay identical in style.
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local Brick = Theme.Brick
local MenuKit = {}

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

function MenuKit.corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius, c.Parent = UDim.new(0, radius), parent
end

function MenuKit.outline(parent: GuiObject, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.ApplyStrokeMode = BLACK, thickness, Enum.ApplyStrokeMode.Border
	s.LineJoinMode, s.Parent = Enum.LineJoinMode.Round, parent
	return s
end

-- Top-lit shading for brick faces.
function MenuKit.shade(parent: GuiObject)
	local g = Instance.new("UIGradient")
	g.Rotation, g.Color = 90, ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200))
	g.Parent = parent
end

-- White Fredoka One text with a black outline, like the HUD. Shrinks to fit, never grows past `size`.
function MenuKit.label(name: string, parent: Instance, text: string, size: number, position: UDim2, extent: UDim2): TextLabel
	local t = Instance.new("TextLabel")
	t.Name, t.BackgroundTransparency, t.Text = name, 1, text
	t.Font, t.TextColor3, t.TextScaled, t.TextWrapped = Theme.Font, WHITE, true, true
	t.Position, t.Size = position, extent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize, limit.Parent = size, t
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.LineJoinMode = BLACK, math.max(1.5, size / 11), Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = parent
	return t
end

export type Chunky = { button: TextButton, caption: TextLabel, paint: (color: Color3, caption: string) -> () }
-- A chunky brick button: coloured face, black outline, outlined caption, hover grow and a press bounce.
function MenuKit.chunky(name: string, parent: Instance, position: UDim2, extent: UDim2, textSize: number): Chunky
	local b = Instance.new("TextButton")
	b.Name, b.Text, b.AutoButtonColor = name, "", false
	b.Position, b.Size, b.BackgroundColor3 = position, extent, Brick.Green
	MenuKit.corner(b, 12)
	MenuKit.outline(b, 3)
	MenuKit.shade(b)
	local caption = MenuKit.label("Caption", b, "", textSize, UDim2.fromScale(0.06, 0.08), UDim2.fromScale(0.88, 0.84))
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1.06 }):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
	b.Activated:Connect(function()
		scale.Scale = 0.9
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	b.Parent = parent
	return {
		button = b,
		caption = caption,
		paint = function(color: Color3, text: string)
			b.BackgroundColor3, caption.Text = color, text
		end,
	}
end

return MenuKit
