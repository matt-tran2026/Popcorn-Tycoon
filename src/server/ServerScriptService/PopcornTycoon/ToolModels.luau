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

-- Turns the tool's parts into one assembly: meshes named in look.model.joints get a Motor6D
-- from the Handle (named joint.motor) about the tool frame's Y axis through joint.pivot; the
-- rest are welded to the Handle, or to the part look.model.welds names. `frame` is the tool
-- frame in world space (grip point at its origin).
local function rig(handle: BasePart, parts: { BasePart }, frame: CFrame, look: ToolPresentation.Presentation)
	local byName: { [string]: BasePart } = {}
	for _, part in parts do byName[part.Name] = part end
	local joints, welds = look.model.joints or {}, look.model.welds or {}
	for _, part in parts do
		local joint = joints[part.Name]
		if part == handle then
			continue
		elseif joint then
			local pivot = frame * CFrame.new(joint.pivot)
			local motor = Instance.new("Motor6D")
			motor.Name, motor.Part0, motor.Part1 = joint.motor, handle, part
			motor.C0, motor.C1 = handle.CFrame:ToObjectSpace(pivot), part.CFrame:ToObjectSpace(pivot)
			motor.Parent = handle
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = byName[welds[part.Name] or ""] or handle, part
			weld.Parent = part
		end
	end
end

-- Part-built bypass clippers, used until the Blender template is imported. Built straight in
-- the tool frame (X along the handle toward the blades, Y the thin axis, Z toward the upper
-- handle; grip point at the origin) with the same mesh names, joints and points as the
-- Blender model, so the jaw animation works the same.
function ToolModels.cornClippers(): Tool
	local look = assert(ToolPresentation.get("CornClippers"))
	local tool = Instance.new("Tool")
	tool.Name = "CornClippers"
	tool:SetAttribute("ToolId", "CornClippers")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Snip 1 ripe stalk per click"
	local yellow, bolster, steel = Color3.fromRGB(255, 199, 28), Color3.fromRGB(246, 178, 22), Color3.fromRGB(196, 203, 212)
	local plastic, metal = Enum.Material.SmoothPlastic, Enum.Material.Metal
	local joints = look.model.joints or {}
	local pivot = if joints.ClippersJaw then joints.ClippersJaw.pivot else Vector3.new(0.95, 0, 0.165)
	-- A bar from a to b in the tool frame, `thick` along the thin axis (Y).
	local function bar(name: string, a: Vector3, b: Vector3, width: number, thick: number, color: Color3, material: Enum.Material, round: boolean?): Part
		local along = b - a
		local cf = CFrame.fromMatrix((a + b) / 2, along.Unit, Vector3.yAxis)
		local p = piece(tool, name, Vector3.new(along.Magnitude, thick, width), cf, color, material)
		if round then
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(along.Magnitude, width, width)
		end
		return p
	end
	-- Built butt-to-bolster so the handle's own X axis points toward the blades.
	local handle = bar("Handle", Vector3.new(-0.66, 0, 0), Vector3.new(0.72, 0, 0), 0.26, 0.26, yellow, plastic, true)
	bar("ClippersBolster", Vector3.new(0.78, 0, 0), Vector3.new(0.58, 0, 0), 0.31, 0.27, bolster, plastic)
	bar("ClippersBlade", pivot - Vector3.new(0.25, -0.05, 0.2), Vector3.new(2.0, 0.05, 0.16), 0.32, 0.06, steel, metal)
	bar("ClippersBladeTip", Vector3.new(1.95, 0.05, 0.17), Vector3.new(2.1, 0.05, 0.123), 0.1, 0.05, steel, metal)
	bar("ClippersEdge", Vector3.new(1.0, 0.05, -0.1), Vector3.new(2.0, 0.05, 0.07), 0.05, 0.065, Color3.fromRGB(246, 248, 251), metal)
	local bolt = piece(tool, "ClippersBolt", Vector3.new(0.24, 0.19, 0.19), CFrame.new(pivot) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(176, 184, 194), metal)
	bolt.Shape = Enum.PartType.Cylinder
	local jaw = bar("ClippersJaw", pivot + Vector3.new(0.05, -0.05, -0.05), Vector3.new(1.73, -0.05, -0.5), 0.23, 0.08, steel, metal)
	bar("ClippersJawTang", pivot + Vector3.new(0, -0.05, -0.1), pivot + Vector3.new(-0.02, -0.05, 0.33), 0.2, 0.08, steel, metal)
	local grip = bar("ClippersJawGrip", Vector3.new(0.93, 0, 0.465), Vector3.new(-0.23, 0, 1.115), 0.25, 0.25, yellow, plastic, true)
	bar("ClippersJawBolster", Vector3.new(0.95, 0, 0.44), Vector3.new(0.76, 0, 0.53), 0.3, 0.26, bolster, plastic)
	local spring = bar("ClippersSpring", Vector3.new(0.53, 0, 0.125), Vector3.new(0.61, 0, 0.48), 0.17, 0.17, Color3.fromRGB(150, 157, 167), metal, true)
	-- Extra pieces ride on the part they belong to (the jaw half or the fixed half).
	local rideOn: { [string]: BasePart } = { ClippersJawTang = jaw, ClippersJawBolster = grip }
	local main = { [handle] = true, [jaw] = true, [grip] = true, [spring] = true }
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and not main[child] then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = rideOn[child.Name] or handle, child, child
		end
	end
	rig(handle, { handle, jaw, grip, spring }, CFrame.identity, look)
	-- The tool frame is the world frame here; express points and grip in the handle's frame.
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, handle.CFrame:PointToObjectSpace(point), handle
	end
	tool.Grip = handle.CFrame:Inverse() * look.model.grip
	return tool
end

-- The invisible part the hand holds for tools with model.holder (the Pitchfork): it sits at the
-- grip point in the tool frame, and the visible meshes hang off it on joints and welds.
local function holderPart(frame: CFrame): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Transparency = "Handle", Vector3.new(0.2, 0.2, 0.2), frame, 1
	p.CanCollide, p.CanTouch, p.CanQuery, p.Massless, p.CastShadow = false, false, false, true, false
	return p
end

-- Part-built pitchfork, used until the Blender template is imported. Built straight in the
-- tool frame (X along the shaft toward the prongs, Y the prongs' thin axis, Z across them; grip
-- point at the origin) with the Blender model's mesh names, holder grip, Thrust joint and points.
function ToolModels.pitchfork(): Tool
	local look = assert(ToolPresentation.get("Pitchfork"))
	local tool = Instance.new("Tool")
	tool.Name = "Pitchfork"
	tool:SetAttribute("ToolId", "Pitchfork")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Thrust through up to 3 ripe stalks in a line"
	local wood, iron, steel = Color3.fromRGB(150, 108, 70), Color3.fromRGB(92, 98, 106), Color3.fromRGB(196, 203, 212)
	local tip = Color3.fromRGB(240, 243, 246)
	local metal = Enum.Material.Metal
	local function bar(name: string, a: Vector3, b: Vector3, width: number, thick: number, color: Color3): Part
		local along = b - a
		return piece(tool, name, Vector3.new(along.Magnitude, thick, width), CFrame.fromMatrix((a + b) / 2, along.Unit, Vector3.yAxis), color, metal)
	end
	local holder = holderPart(CFrame.identity)
	holder.Parent = tool
	local shaft = cylinder(tool, "PitchforkHandle", 4.12, 0.32, 0.5, wood, Enum.Material.Wood)
	cylinder(tool, "PitchforkKnob", 0.16, 0.36, -1.5, Color3.fromRGB(110, 76, 46), Enum.Material.Wood)
	cylinder(tool, "PitchforkFerrule", 0.56, 0.4, 2.7, iron, metal)
	local head = bar("PitchforkHead", Vector3.new(2.9, 0, 0), Vector3.new(4.45, 0, 0), 0.17, 0.13, steel)
	bar("PitchforkTipM", Vector3.new(4.4, 0, 0), Vector3.new(4.7, 0, 0), 0.08, 0.08, tip)
	for _, side in { 1, -1 } do
		bar("PitchforkBow" .. side, Vector3.new(2.92, 0, 0.05 * side), Vector3.new(3.42, 0, 0.55 * side), 0.17, 0.13, steel)
		bar("PitchforkTine" .. side, Vector3.new(3.36, 0, 0.55 * side), Vector3.new(4.36, 0, 0.47 * side), 0.16, 0.12, steel)
		bar("PitchforkTip" .. side, Vector3.new(4.32, 0, 0.475 * side), Vector3.new(4.6, 0, 0.43 * side), 0.08, 0.08, tip)
	end
	-- Everything but the shaft rides on the shaft, which slides on the Thrust motor.
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= holder and child ~= shaft and child ~= head then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = shaft, child, child
		end
	end
	rig(holder, { holder :: BasePart, shaft, head }, CFrame.identity, look)
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, shaft.CFrame:PointToObjectSpace(point), shaft
	end
	tool.Grip = look.model.grip
	return tool
end

-- Part-built harvest hook, used until the Blender template is imported. Built straight in the
-- tool frame (X along the grip toward the hook, Y the hook's thin axis, Z the side it curls to;
-- grip point at the origin) with the Blender model's mesh names, holder grip, Reach joint and
-- points. The curl follows build_harvest_hook.py: a tightening circle through 262 degrees.
function ToolModels.harvestHook(): Tool
	local look = assert(ToolPresentation.get("HarvestHook"))
	local tool = Instance.new("Tool")
	tool.Name = "HarvestHook"
	tool:SetAttribute("ToolId", "HarvestHook")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Hook 2 ripe stalks from far away and pull them in"
	local leather, iron, ironDark = Color3.fromRGB(107, 64, 38), Color3.fromRGB(72, 76, 82), Color3.fromRGB(58, 62, 68)
	local metal = Enum.Material.Metal
	local function bar(name: string, a: Vector3, b: Vector3, width: number, thick: number): Part
		local along = b - a
		return piece(tool, name, Vector3.new(along.Magnitude + 0.04, thick, width), CFrame.fromMatrix((a + b) / 2, along.Unit, Vector3.yAxis), ironDark, metal)
	end
	local holder = holderPart(CFrame.identity)
	holder.Parent = tool
	local grip = cylinder(tool, "HookHandle", 1.66, 0.34, -0.09, leather, Enum.Material.Leather)
	for i, x in { -0.7, -0.45, -0.2, 0.05, 0.3, 0.55 } do
		cylinder(tool, "HookWrap_" .. i, 0.07, 0.38, x, Color3.fromRGB(78, 46, 27), Enum.Material.Leather)
	end
	local pommel = cylinder(tool, "HookPommel", 0.24, 0.41, -1.02, iron, metal)
	cylinder(tool, "HookFerrule", 0.38, 0.4, 0.89, iron, metal)
	local curlStart, radius = Vector3.new(1.78, 0, -0.08), 1.04
	local blade = bar("HookBlade", Vector3.new(0.98, 0, 0), curlStart, 0.29, 0.24)
	local centre = curlStart + Vector3.new(0, 0, radius)
	local segments = 10
	local previous = curlStart
	for i = 1, segments do
		local u = i / segments
		local theta = math.rad(262 * u)
		local r = radius * (1 - 0.2 * u)
		local point = centre + Vector3.new(r * math.sin(theta), 0, -r * math.cos(theta))
		local width = 0.25 * (1 - u ^ 2.4) + 0.05
		bar("HookCurl_" .. i, previous, point, width, 0.2 * (1 - u ^ 2) + 0.05)
		previous = point
	end
	-- Everything but the grip and the hook bar rides on the grip, which slides on Reach.
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= holder and child ~= grip and child ~= blade and child ~= pommel then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = grip, child, child
		end
	end
	rig(holder, { holder :: BasePart, grip, blade, pommel }, CFrame.identity, look)
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, grip.CFrame:PointToObjectSpace(point), grip
	end
	tool.Grip = look.model.grip
	return tool
end

local procedural: { [string]: () -> Tool } = {
	Sickle = ToolModels.sickle, CornClippers = ToolModels.cornClippers, Pitchfork = ToolModels.pitchfork,
	HarvestHook = ToolModels.harvestHook,
}

-- The tool frame (see ToolPresentation.Model) recovered from the imported meshes, so it does
-- not matter how the importer oriented or centred them: X runs along the handle mesh's long
-- axis toward the other meshes, Y is the head's thinnest axis, Z the side the head sits on.
local function toolFrame(handle: BasePart, others: { BasePart }, gripFromCentre: number, headName: string?): CFrame?
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
	local headPart = others[1]
	for _, part in others do if part.Name == headName then headPart = part end end
	local head = axes(headPart)
	table.sort(head, function(a, b) return a.size < b.size end)
	local y = head[1].axis
	local side = (headCentre - handle.Position)
	side -= x * side:Dot(x) + y * side:Dot(y)
	local z: Vector3
	if side.Magnitude < 1e-3 then
		-- A head centred on the handle (the Pitchfork's three prongs): no side to point Z at,
		-- and the head is symmetric, so any right-handed Z across it works.
		if math.abs(x:Dot(y)) > 0.99 then return nil end
		y = (y - x * x:Dot(y)).Unit
		z = x:Cross(y)
	else
		z = side.Unit
		if x:Cross(y):Dot(z) < 0 then y = -y end -- Keep the frame right-handed with Z toward the head.
	end
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
	local frame = if handle then toolFrame(handle, others, look.model.gripFromCentre, look.model.head) else nil
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
	local mesh = handle :: BasePart
	local parts = { mesh, table.unpack(others) }
	for _, part in parts do
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.Massless = false, false, false, false, true
		part.CastShadow = true
		-- Colours are vertex colours; a white part shows them as painted.
		part.Color = Color3.new(1, 1, 1)
		local material = look.model.materials[part.Name]
		if material then part.Material = material end
		part.Parent = tool
	end
	local toolFrameCf = frame :: CFrame
	if look.model.holder then
		-- The hand holds an invisible grip at the grip point; the handle mesh hangs off it on
		-- its joint (the Pitchfork's Thrust), and named points ride on the handle mesh.
		local holder = holderPart(toolFrameCf)
		holder.Parent = tool
		rig(holder, { holder :: BasePart, table.unpack(parts) }, toolFrameCf, look)
		copy:Destroy()
		for name, point in look.model.points do
			local attachment = Instance.new("Attachment")
			attachment.Name, attachment.Position, attachment.Parent = name, mesh.CFrame:PointToObjectSpace(toolFrameCf:PointToWorldSpace(point)), mesh
		end
		tool.Grip = look.model.grip
		return tool
	end
	-- Welds, or Motor6Ds for moving parts (before the handle is renamed to "Handle").
	rig(mesh, parts, toolFrameCf, look)
	mesh.Name = "Handle"
	copy:Destroy()
	-- Named points in the tool frame become attachments on the handle.
	local local_ = mesh.CFrame:ToObjectSpace(toolFrameCf)
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, local_:PointToWorldSpace(point), mesh
	end
	tool.Grip = local_ * look.model.grip
	return tool
end

-- The swing ribbon between two named points; ToolController enables it during a swing.
local function addTrail(tool: Tool, look: ToolPresentation.Presentation)
	local spec = look.model.trail
	if not spec or tool:FindFirstChild("SwingTrail", true) then return end
	-- Points sit on the Handle, or on the moving handle mesh for tools with a holder grip.
	local a0, a1 = tool:FindFirstChild(spec.from, true), tool:FindFirstChild(spec.to, true)
	if not (a0 and a0:IsA("Attachment") and a1 and a1:IsA("Attachment")) then return end
	local carrier = a0.Parent :: Instance
	local trail = Instance.new("Trail")
	trail.Name, trail.Attachment0, trail.Attachment1 = "SwingTrail", a0, a1
	trail.Lifetime, trail.MinLength, trail.Enabled = spec.lifetime, 0.05, false
	trail.Color = ColorSequence.new(spec.colors[1], spec.colors[#spec.colors])
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.LightEmission, trail.FaceCamera = 0.35, true
	trail.Parent = carrier
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
