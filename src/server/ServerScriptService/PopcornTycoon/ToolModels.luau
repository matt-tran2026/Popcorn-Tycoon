--!strict
-- Builds the Roblox Tool for a tool ID. The Blender model (imported into
-- ServerStorage.PopcornTemplates.Tools.<template>, place file only) is preferred; the procedural
-- part-built model below is the fallback, kept in source so it syncs and diffs like code.
-- Procedural models are built in the handle's own frame: the grip runs along +X, the blade
-- hooks off its far end.
local ServerStorage = game:GetService("ServerStorage")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local ToolPresentation = require(Shared.ToolPresentation)
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

local procedural: { [string]: () -> Tool } = { Sickle = ToolModels.sickle }

-- The tool frame (see ToolPresentation.Model) recovered from the imported meshes, so it does
-- not matter how the importer oriented or centred them: X runs along the handle mesh's long
-- axis toward the other meshes, Y is the head's thinnest axis, Z the side the head sits on.
local function toolFrame(handle: BasePart, others: { BasePart }, gripFromCentre: number): CFrame?
	if #others == 0 then return nil end
	local function axes(part: BasePart): { { axis: Vector3, size: number } }
		local cf, size = part.CFrame, part.Size
		return { { axis = cf.RightVector, size = size.X }, { axis = cf.UpVector, size = size.Y }, { axis = cf.LookVector, size = size.Z } }
	end
	local list = axes(handle)
	table.sort(list, function(a, b) return a.size > b.size end)
	local headCentre = Vector3.zero
	for _, part in others do headCentre += part.Position end
	headCentre /= #others
	local x = list[1].axis
	if (headCentre - handle.Position):Dot(x) < 0 then x = -x end
	local head = axes(others[1])
	table.sort(head, function(a, b) return a.size < b.size end)
	local y = head[1].axis
	local side = (headCentre - handle.Position)
	side -= x * side:Dot(x) + y * side:Dot(y)
	if side.Magnitude < 1e-3 then return nil end
	local z = side.Unit
	if x:Cross(y):Dot(z) < 0 then y = -y end -- Keep the frame right-handed with Z toward the head.
	return CFrame.fromMatrix(handle.Position + x * gripFromCentre, x, y, z)
end

-- Builds the Tool from ServerStorage.PopcornTemplates.Tools.<template>, or nil if it is missing
-- or does not have the expected meshes (the caller then uses the procedural model).
local function fromTemplate(toolId: string, look: ToolPresentation.Presentation): Tool?
	local folder = ServerStorage:FindFirstChild("PopcornTemplates")
	local tools = folder and folder:FindFirstChild("Tools")
	local source = tools and tools:FindFirstChild(look.model.template)
	if not source then return nil end
	local copy = source:Clone()
	local handle: BasePart? = nil
	local others: { BasePart } = {}
	for _, part in copy:GetDescendants() do
		if part:IsA("LuaSourceContainer") then
			part:Destroy()
		elseif part:IsA("BasePart") then
			if part.Name == look.model.handle then handle = part else table.insert(others, part) end
		end
	end
	local frame = if handle then toolFrame(handle, others, look.model.gripFromCentre) else nil
	if not handle or not frame then
		warn("[PopcornTycoon] Tool template " .. look.model.template .. " is missing its meshes; using the part-built model")
		copy:Destroy()
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = toolId
	tool:SetAttribute("ToolId", toolId)
	tool:SetAttribute("ModelSource", "Blender")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	for _, part in { handle :: BasePart, table.unpack(others) } do
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.Massless = false, false, false, false, true
		part.CastShadow = true
		-- Colours are vertex colours; a white part shows them as painted.
		part.Color = Color3.new(1, 1, 1)
		local material = look.model.materials[part.Name]
		if material then part.Material = material end
		part.Parent = tool
		if part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = handle, part, part
		end
	end
	handle.Name = "Handle"
	copy:Destroy()
	-- Named points in the tool frame become attachments on the handle.
	local local_ = handle.CFrame:ToObjectSpace(frame)
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, local_:PointToWorldSpace(point), handle
	end
	tool.Grip = local_ * look.model.grip
	return tool
end

-- The swing ribbon between two named points; ToolController enables it during a swing.
local function addTrail(tool: Tool, look: ToolPresentation.Presentation)
	local spec = look.model.trail
	local handle = tool:FindFirstChild("Handle")
	if not spec or not handle or handle:FindFirstChild("SwingTrail") then return end
	local a0, a1 = handle:FindFirstChild(spec.from), handle:FindFirstChild(spec.to)
	if not (a0 and a0:IsA("Attachment") and a1 and a1:IsA("Attachment")) then return end
	local trail = Instance.new("Trail")
	trail.Name, trail.Attachment0, trail.Attachment1 = "SwingTrail", a0, a1
	trail.Lifetime, trail.MinLength, trail.Enabled = spec.lifetime, 0.05, false
	trail.Color = ColorSequence.new(spec.colors[1], spec.colors[#spec.colors])
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.LightEmission, trail.FaceCamera = 0.35, true
	trail.Parent = handle
end

-- Whether a tool ID can be built: it has a procedural builder, or a presentation entry whose
-- Blender template is in the place.
function ToolModels.has(toolId: string): boolean
	if procedural[toolId] then return true end
	local look = ToolPresentation.get(toolId)
	local folder = ServerStorage:FindFirstChild("PopcornTemplates")
	local tools = folder and folder:FindFirstChild("Tools")
	return look ~= nil and tools ~= nil and tools:FindFirstChild(look.model.template) ~= nil
end

function ToolModels.build(toolId: string): Tool
	local look = ToolPresentation.get(toolId)
	local tool = if look then fromTemplate(toolId, look) else nil
	if not tool then
		local builder = assert(procedural[toolId], "No model for tool " .. toolId)
		tool = builder()
		tool:SetAttribute("ModelSource", "Procedural")
	end
	local built = tool :: Tool
	if look then addTrail(built, look) end
	built:SetAttribute("Rarity", if look then look.rarity else nil)
	return built
end

return ToolModels
