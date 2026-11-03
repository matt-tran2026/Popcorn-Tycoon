--!strict
-- Procedural tool models, kept in source so they sync and diff like code.
-- Built in the handle's own frame: the grip runs along +X, the blade hooks off its far end.
local ToolModels = {}

local colors = {
	wood = Color3.fromRGB(139, 90, 55), red = Color3.fromRGB(217, 76, 58),
	gold = Color3.fromRGB(244, 197, 66), steel = Color3.fromRGB(196, 203, 210),
	edge = Color3.fromRGB(243, 244, 240),
}

local function piece(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, cframe, color, material
	p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, name: string, length: number, diameter: number, x: number, color: Color3, material: Enum.Material): Part
	local p = piece(parent, name, Vector3.new(length, diameter, diameter), CFrame.new(x, 0, 0), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A toy-scaled sickle: red-wrapped wooden grip, gold ferrule, and a crescent steel blade
-- with a bright inner cutting edge. Returns a Tool whose Trail is off until a swing.
function ToolModels.sickle(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Sickle"
	tool:SetAttribute("ToolId", "Sickle")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Swing to cut up to 3 ripe stalks"
	local handle = cylinder(tool, "Handle", 2.2, 0.38, 0, colors.wood, Enum.Material.Wood)
	for i, x in { -0.55, 0.15 } do cylinder(tool, "GripWrap_" .. i, 0.32, 0.42, x, colors.red, Enum.Material.Fabric) end
	cylinder(tool, "Pommel", 0.22, 0.5, -1.15, colors.gold, Enum.Material.Metal)
	cylinder(tool, "Ferrule", 0.3, 0.46, 1.05, colors.gold, Enum.Material.Metal)
	-- Crescent: points on a circle that starts at the ferrule, hooks out to +Z and turns back.
	local radius, center = 1.05, Vector3.new(1.2 + 1.05, 0, 0)
	local first, last, segments = 180, -45, 9
	local points: { Vector3 } = {}
	for i = 0, segments do
		local angle = math.rad(first + (last - first) * i / segments)
		points[i + 1] = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
	end
	for i = 1, segments do
		local a, b = points[i], points[i + 1]
		local taper = 1 - (i - 1) / segments -- Broad at the heel, needle-thin at the tip.
		local width = 0.12 + 0.3 * taper
		local length = (b - a).Magnitude + 0.06
		local frame = CFrame.lookAt((a + b) / 2, b)
		-- The cutting edge sits on the inside of the curve, toward the circle's center.
		local inward = ((center - (a + b) / 2) * Vector3.new(1, 0, 1)).Unit
		piece(tool, "Blade_" .. i, Vector3.new(width, 0.1, length), frame, colors.steel, Enum.Material.Metal)
		local edgeAt = (a + b) / 2 + inward * (width / 2 - 0.03)
		piece(tool, "Edge_" .. i, Vector3.new(0.07, 0.11, length), CFrame.lookAt(edgeAt, edgeAt + (b - a)), colors.edge, Enum.Material.SmoothPlastic)
	end
	for _, object in tool:GetChildren() do
		if object:IsA("BasePart") and object ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = handle, object, object
		end
	end
	-- Swoosh ribbon between blade tip and heel; ToolController enables it during a swing.
	local tip, heel = Instance.new("Attachment"), Instance.new("Attachment")
	tip.Name, tip.Position, tip.Parent = "TrailTip", points[#points], handle
	heel.Name, heel.Position, heel.Parent = "TrailHeel", points[4], handle
	local trail = Instance.new("Trail")
	trail.Name, trail.Attachment0, trail.Attachment1 = "SwingTrail", tip, heel
	trail.Lifetime, trail.MinLength, trail.Enabled = 0.18, 0.05, false
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 209), colors.gold)
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.LightEmission, trail.FaceCamera = 0.4, true
	trail.Parent = handle
	-- Held in the right hand with the grip pointing forward and the blade curling left, flat.
	tool.Grip = CFrame.new(0, 0, 0.35) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(90), 0, 0)
	return tool
end

-- Anchored, script-free copy for the shed display.
function ToolModels.display(tool: Tool): Model
	local model = Instance.new("Model")
	model.Name = tool.Name .. "Display"
	for _, object in tool:GetChildren() do
		if object:IsA("BasePart") then
			object.Anchored = true
			for _, child in object:GetChildren() do
				if not child:IsA("Attachment") or child.Name:find("Trail") then child:Destroy() end
			end
			object.Parent = model
		end
	end
	model.PrimaryPart = model:FindFirstChild("Handle") :: BasePart
	tool:Destroy()
	return model
end

return ToolModels
