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
-- frame in world space (grip point at its origin). A joint with `on` hangs from that mesh
-- instead of the Handle (it rides that mesh's own joint). Stretching meshes (look.model.stretch)
-- are marked with the part-space axis that runs along tool X and their rest size, which
-- ToolAnimator needs to resize them.
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
			local base = (if joint.on then byName[joint.on] else nil) or handle
			local motor = Instance.new("Motor6D")
			motor.Name, motor.Part0, motor.Part1 = joint.motor, base, part
			motor.C0, motor.C1 = base.CFrame:ToObjectSpace(pivot), part.CFrame:ToObjectSpace(pivot)
			motor.Parent = base
			local stretch = (look.model.stretch or {})[part.Name]
			if stretch then
				local along = part.CFrame:VectorToObjectSpace(frame.XVector)
				local ax, ay, az = math.abs(along.X), math.abs(along.Y), math.abs(along.Z)
				local axis = if ax >= ay and ax >= az then Vector3.xAxis elseif ay >= az then Vector3.yAxis else Vector3.zAxis
				part:SetAttribute("StretchAxis", axis)
				part:SetAttribute("StretchRest", part.Size)
			end
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

-- Part-built twin sickle (the right-hand one; the left is a copy, see attachOffhand), used until
-- the Blender template is imported. Built straight in the tool frame (X along the handle toward
-- the blade, Y the blade's thin axis, Z the side it curls to; grip point at the origin) with the
-- Blender model's mesh names and points. The crescent follows build_twin_sickles.py: a squashed
-- circle (0.98 x 0.9) tangent to the handle line at x 1.05, turning 282 degrees toward +Z.
function ToolModels.twinSickles(): Tool
	local look = assert(ToolPresentation.get("TwinSickles"))
	local tool = Instance.new("Tool")
	tool.Name = "TwinSickles"
	tool:SetAttribute("ToolId", "TwinSickles")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Slash left and right; every 3rd hit spins"
	local wood, silver, steel = Color3.fromRGB(110, 72, 44), Color3.fromRGB(196, 202, 210), Color3.fromRGB(204, 210, 218)
	local metal = Enum.Material.Metal
	local handle = cylinder(tool, "TwinHandle", 1.54, 0.33, -0.09, wood, Enum.Material.Wood)
	for i, x in { -0.6, -0.3, 0, 0.3 } do
		cylinder(tool, "TwinStrap_" .. i, 0.08, 0.37, x, Color3.fromRGB(70, 42, 25), Enum.Material.Leather)
	end
	local pommel = cylinder(tool, "TwinPommel", 0.17, 0.42, -0.93, silver, metal)
	cylinder(tool, "TwinCollar", 0.3, 0.43, 0.79, silver, metal)
	-- A blade bar from a to b along the spine; the blade's width runs inward (toward the centre).
	local function bar(name: string, a: Vector3, b: Vector3, width: number, thick: number, inward: Vector3): Part
		local along = b - a
		local mid = (a + b) / 2 + inward * (width / 2)
		return piece(tool, name, Vector3.new(along.Magnitude + 0.03, thick, width), CFrame.fromMatrix(mid, along.Unit, Vector3.yAxis), steel, metal)
	end
	local blade = bar("TwinBlade", Vector3.new(0.8, 0, 0), Vector3.new(1.05, 0, 0), 0.4, 0.13, Vector3.zAxis)
	local centre, segments = Vector3.new(1.05, 0, 0.9), 12
	local previous = Vector3.new(1.05, 0, 0)
	for i = 1, segments do
		local u = i / segments
		local angle = math.rad(-90 + 282 * u)
		local point = centre + Vector3.new(0.98 * math.cos(angle), 0, 0.9 * math.sin(angle))
		local mid = (previous + point) / 2
		local inward = ((centre - mid) * Vector3.new(1, 0, 1)).Unit
		bar("TwinArc_" .. i, previous, point, 0.45 * (1 - u) ^ 0.9 + 0.05, 0.13 * (1 - 0.7 * u) + 0.03, inward)
		previous = point
	end
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= handle and child ~= blade and child ~= pommel then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = handle, child, child
		end
	end
	rig(handle, { handle :: BasePart, blade, pommel }, CFrame.identity, look)
	-- The tool frame is the world frame here; express points and grip in the handle's frame.
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, handle.CFrame:PointToObjectSpace(point), handle
	end
	handle.Name = "Handle"
	tool.Grip = handle.CFrame:Inverse() * look.model.grip
	return tool
end

-- Part-built long scythe, used until the Blender template is imported. Built straight in the
-- tool frame (X along the shaft toward the blade, Y the blade's thin axis, Z the side it reaches
-- to; grip point at the origin) with the Blender model's mesh names and points, in the pack-style
-- flat colours. The blade follows build_long_scythe.py: a cubic Bezier spine from the shaft top
-- (4.95) bulging out and curling back toward the butt, the edge on the inside of the curve.
function ToolModels.longScythe(): Tool
	local look = assert(ToolPresentation.get("LongScythe"))
	local tool = Instance.new("Tool")
	tool.Name = "LongScythe"
	tool:SetAttribute("ToolId", "LongScythe")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Great Harvest: sweep 6 stalks in a wide half circle"
	local plastic = Enum.Material.SmoothPlastic
	local wood, iron, ironDark = Color3.fromRGB(150, 104, 64), Color3.fromRGB(128, 133, 141), Color3.fromRGB(84, 89, 98)
	local rim, steel, edge = Color3.fromRGB(86, 93, 106), Color3.fromRGB(200, 207, 216), Color3.fromRGB(246, 248, 252)
	local handle = cylinder(tool, "LongScytheHandle", 6.66, 0.29, 2.03, wood, plastic)
	cylinder(tool, "LongScytheFittings", 0.28, 0.36, -1.18, iron, plastic)
	for i, x in { 0.6, 2.7 } do
		cylinder(tool, "LongScytheNib_" .. i, 0.26, 0.4, x, ironDark, plastic)
		piece(tool, "LongScytheNibPeg_" .. i, Vector3.new(0.14, 0.14, 0.45), CFrame.new(x, 0, 0.37), iron, plastic)
	end
	cylinder(tool, "LongScytheCollar", 0.5, 0.46, 4.87, iron, plastic)
	-- Spine points of the crescent (tool frame x, z) and the width toward the inside of the curve.
	local p0, p1, p2, p3 = Vector3.new(4.95, 0, 0), Vector3.new(6.15, 0, 1.5), Vector3.new(5.35, 0, 3.55), Vector3.new(3.3, 0, 3.65)
	local function at(t: number): Vector3
		local u = 1 - t
		return p0 * u ^ 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ^ 3
	end
	local function plate(name: string, a: Vector3, b: Vector3, width: number, thick: number, color: Color3): Part
		local along = b - a
		local inward = along.Unit:Cross(Vector3.yAxis) -- toward the inside of the curve (-X at the root)
		local mid = (a + b) / 2 + inward * (width / 2)
		return piece(tool, name, Vector3.new(along.Magnitude + 0.04, thick, width), CFrame.fromMatrix(mid, along.Unit, Vector3.yAxis), color, plastic)
	end
	local segments = 10
	local blade: Part? = nil
	for i = 1, segments do
		local t0, t1 = (i - 1) / segments, i / segments
		local a, b = at(t0), at(t1)
		local tm = (t0 + t1) / 2
		local width = 0.98 * math.min(1, 0.55 + tm * 4.5) * (1 - tm) ^ 0.8 + 0.04
		-- Pack-style layers: a darker outline plate, the silver face, a bright edge band.
		local back = plate(if i == 1 then "LongScytheBlade" else "LongScytheRim_" .. i, a, b, width + 0.12, 0.2, rim)
		if i == 1 then blade = back end
		plate("LongScytheFace_" .. i, a, b, width * 0.75, 0.26, steel)
		local inward = (b - a).Unit:Cross(Vector3.yAxis)
		plate("LongScytheEdge_" .. i, a + inward * width * 0.75, b + inward * width * 0.75, width * 0.25, 0.24, edge)
	end
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= handle and child ~= blade then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = handle, child, child
		end
	end
	rig(handle, { handle :: BasePart, blade :: Part }, CFrame.identity, look)
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, handle.CFrame:PointToObjectSpace(point), handle
	end
	handle.Name = "Handle"
	tool.Grip = handle.CFrame:Inverse() * look.model.grip
	return tool
end

-- Part-built hedge trimmer, used until the Blender template is imported. Built straight in the
-- tool frame (X along the bar toward the tip, Y the blades' thin axis, Z from the housing toward
-- the bar; grip point on the rear loop at the origin) with the Blender model's mesh names,
-- blade joints and points, in the design page's flat colours. Blender (x, y, z) -> (x, z, -y).
function ToolModels.hedgeTrimmer(): Tool
	local look = assert(ToolPresentation.get("HedgeTrimmer"))
	local tool = Instance.new("Tool")
	tool.Name = "HedgeTrimmer"
	tool:SetAttribute("ToolId", "HedgeTrimmer")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Precision Cutting: trim 5 stalks in a narrow strip straight ahead"
	local plastic, metal = Enum.Material.SmoothPlastic, Enum.Material.Metal
	local green, greenDark = Color3.fromRGB(79, 174, 50), Color3.fromRGB(47, 122, 34)
	local orange, vent = Color3.fromRGB(242, 138, 26), Color3.fromRGB(43, 47, 51)
	local steel, steelLight, steelDark = Color3.fromRGB(169, 176, 184), Color3.fromRGB(227, 232, 237), Color3.fromRGB(107, 115, 124)
	local function box(name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material): Part
		return piece(tool, name, size, CFrame.new(at), color, material)
	end
	-- Rear loop: the grip bar (the Handle), the back post and the bottom bar; the trigger.
	local handle = box("TrimmerHandle", Vector3.new(1.07, 0.3, 0.3), Vector3.new(0.085, 0, 0), green, plastic)
	box("TrimmerLoopBack", Vector3.new(0.3, 0.3, 1.16), Vector3.new(-0.6, 0, 0.43), green, plastic)
	box("TrimmerLoopBottom", Vector3.new(1.22, 0.3, 0.3), Vector3.new(0.01, 0, 0.86), green, plastic)
	box("TrimmerTrigger", Vector3.new(0.33, 0.18, 0.3), Vector3.new(0.215, 0, 0.23), orange, plastic)
	-- Housing with its dark outline, orange side panel and vent window.
	local body = box("TrimmerBody", Vector3.new(1.5, 1.04, 1.46), Vector3.new(1.25, 0, 0.27), green, plastic)
	box("TrimmerOutline", Vector3.new(1.62, 0.92, 1.58), Vector3.new(1.25, 0, 0.27), greenDark, plastic)
	box("TrimmerPanel", Vector3.new(0.68, 1.26, 0.5), Vector3.new(1.56, 0, 0.35), orange, plastic)
	box("TrimmerVent", Vector3.new(0.44, 1.32, 0.3), Vector3.new(1.56, 0, 0.35), vent, plastic)
	box("TrimmerSwitch", Vector3.new(0.28, 0.36, 0.18), Vector3.new(1.42, 0, -0.49), orange, plastic)
	-- Front bow over the housing (two legs and the top bar) and the hand guard.
	for _, side in { 1, -1 } do
		box("TrimmerBowLeg" .. side, Vector3.new(0.26, 0.26, 1.22), Vector3.new(1.05, 0.66 * side, 0.31), green, plastic)
	end
	box("TrimmerBowTop", Vector3.new(0.26, 1.58, 0.26), Vector3.new(1.05, 0, -0.96), green, plastic)
	box("TrimmerGuard", Vector3.new(0.16, 1.28, 1.6), Vector3.new(2.07, 0, 0.5), green, plastic)
	-- Bar: gearbox neck and the spine rail.
	local bar = box("TrimmerBar", Vector3.new(2.32, 0.26, 0.18), Vector3.new(3.26, 0, 0.62), steelDark, metal)
	box("TrimmerNeck", Vector3.new(0.55, 0.4, 0.46), Vector3.new(2.175, 0, 0.63), steelDark, metal)
	-- Two toothed blades, half a tooth out of step; the teeth ride on their blade.
	local function blade(name: string, y: number, phase: number): Part
		local strip = box(name, Vector3.new(2.45, 0.07, 0.4), Vector3.new(3.375, y, 0.62), steel, metal)
		local x = 2.23 + phase
		local i = 0
		while x + 0.16 <= 4.42 do
			for _, side in { 1, -1 } do
				i += 1
				local tooth = box(name .. "Tooth" .. i, Vector3.new(0.13, 0.06, 0.2), Vector3.new(x + 0.08, y, 0.62 + side * 0.29), steelLight, metal)
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1, weld.Parent = strip, tooth, tooth
			end
			x += 0.3
		end
		return strip
	end
	local top = blade("TrimmerBladeTop", 0.035, 0.15)
	local bottom = blade("TrimmerBladeBottom", -0.035, 0)
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= handle and child ~= body and child ~= bar and child ~= top and child ~= bottom
			and not child:FindFirstChildOfClass("WeldConstraint") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = handle, child, child
		end
	end
	rig(handle, { handle :: BasePart, body, bar, top, bottom }, CFrame.identity, look)
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, handle.CFrame:PointToObjectSpace(point), handle
	end
	handle.Name = "Handle"
	tool.Grip = handle.CFrame:Inverse() * look.model.grip
	return tool
end

-- Part-built spring-loaded picker, used until the Blender template is imported. Built straight
-- in the tool frame (X along the barrel toward the claw, Y the thin axis, Z up from the grip to
-- the barrel; grip point on the D grip's rear bar at the origin) with the Blender model's mesh
-- names, joints (Plunger rod with the jaws on it, Latch, stretching Spring) and points, in the
-- design canvas's colours. Blender (x, y, z) -> (x, z, y).
function ToolModels.springLoadedPicker(): Tool
	local look = assert(ToolPresentation.get("SpringLoadedPicker"))
	local tool = Instance.new("Tool")
	tool.Name = "SpringLoadedPicker"
	tool:SetAttribute("ToolId", "SpringLoadedPicker")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Spring Dash: lunge 12 studs ahead and snatch 4 ripe stalks on the way"
	local plastic, metal = Enum.Material.SmoothPlastic, Enum.Material.Metal
	local red, dark = Color3.fromRGB(217, 52, 43), Color3.fromRGB(60, 65, 73)
	local steel, iron = Color3.fromRGB(180, 188, 198), Color3.fromRGB(125, 133, 143)
	local axisY = 0.6 -- barrel height above the grip (tool Z)
	local function box(name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material, tilt: number?): Part
		return piece(tool, name, size, CFrame.new(at) * CFrame.Angles(0, math.rad(tilt or 0), 0), color, material)
	end
	local function drum(name: string, x0: number, x1: number, diameter: number, color: Color3, material: Enum.Material): Part
		local p = piece(tool, name, Vector3.new(x1 - x0, diameter, diameter), CFrame.new((x0 + x1) / 2, 0, axisY), color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- D grip: top bar (the Handle), rear bar (the hand's grip), bottom bar, housing, rear collar.
	local handle = box("PickerHandle", Vector3.new(1.1, 0.4, 0.36), Vector3.new(0.42, 0, 0.71), red, plastic)
	box("PickerGripBar", Vector3.new(0.38, 0.4, 1.5), Vector3.new(0, 0, 0), red, plastic, -9)
	box("PickerLoopBottom", Vector3.new(0.75, 0.4, 0.36), Vector3.new(0.45, 0, -0.7), red, plastic)
	box("PickerHousing", Vector3.new(0.6, 0.6, 1.08), Vector3.new(1.0, 0, 0.52), red, plastic)
	drum("PickerRearCollar", 1.28, 1.5, 1.04, red, plastic)
	box("PickerTrigger", Vector3.new(0.18, 0.16, 0.3), Vector3.new(0.55, 0, 0.4), dark, plastic)
	box("PickerSlide", Vector3.new(1.3, 0.14, 0.14), Vector3.new(1.65, 0.19, 0.09), steel, metal)
	-- Moving parts, each one piece so the motors can move them.
	local spring = drum("PickerSpring", 1.5, 3.0, 0.84, steel, metal)
	local rod = drum("PickerRod", 1.3, 3.57, 0.2, iron, metal)
	box("PickerClevis", Vector3.new(0.3, 0.3, 0.52), Vector3.new(3.65, 0, axisY), steel, metal)
	local head = drum("PickerHead", 3.0, 3.22, 0.92, red, plastic)
	drum("PickerNose", 3.22, 3.54, 0.36, red, plastic)
	local jawTop = box("PickerJawTop", Vector3.new(0.9, 0.18, 0.18), Vector3.new(4.08, 0, axisY + 0.36), steel, metal, -22)
	local jawBottom = box("PickerJawBottom", Vector3.new(0.9, 0.18, 0.18), Vector3.new(4.08, 0, axisY - 0.36), steel, metal, 22)
	box("PickerPadTop", Vector3.new(0.2, 0.2, 0.15), Vector3.new(4.45, 0, axisY + 0.25), Color3.fromRGB(227, 154, 59), plastic)
	box("PickerPadBottom", Vector3.new(0.2, 0.2, 0.15), Vector3.new(4.45, 0, axisY - 0.25), Color3.fromRGB(227, 154, 59), plastic)
	local latch = box("PickerLatch", Vector3.new(0.12, 0.06, 0.36), Vector3.new(0.9, 0.37, 0.27), steel, metal, 25)
	-- Riders: the clevis, nose and head go with the rod, each pad with its jaw; the rest is the grip.
	local riders: { [string]: BasePart } = {
		PickerClevis = rod, PickerNose = head, PickerPadTop = jawTop, PickerPadBottom = jawBottom,
	}
	local moving = { [spring] = true, [rod] = true, [head] = true, [jawTop] = true, [jawBottom] = true, [latch] = true }
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= handle and not moving[child] then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = riders[child.Name] or handle, child, child
		end
	end
	rig(handle, { handle :: BasePart, spring, rod, head, jawTop, jawBottom, latch }, CFrame.identity, look)
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, handle.CFrame:PointToObjectSpace(point), handle
	end
	handle.Name = "Handle"
	tool.Grip = handle.CFrame:Inverse() * look.model.grip
	return tool
end

-- Part-built corn lasso, used until the Blender template is imported. Built straight in the
-- tool frame (X along the grip toward the rope, Y the rings' normal, Z the side the rope hangs;
-- grip point at the origin) with the Blender model's mesh names, the Loop joint and the points,
-- in the design canvas's colours. Rope rings are short cylinder segments. Every piece of the
-- loop rides the LassoLoop part and carries the LassoLoopPiece attribute, so the client can
-- hide the whole held loop while the thrown rope is out. Blender (x, y, z) -> (x, z, y).
function ToolModels.cornLasso(): Tool
	local look = assert(ToolPresentation.get("CornLasso"))
	local tool = Instance.new("Tool")
	tool.Name = "CornLasso"
	tool:SetAttribute("ToolId", "CornLasso")
	tool.CanBeDropped, tool.RequiresHandle = false, true
	tool.ToolTip = "Lasso the ripe stalk you aim at from up to 25 studs away"
	local leather, metal, fabric = Enum.Material.Leather, Enum.Material.Metal, Enum.Material.Fabric
	local brown, steel = Color3.fromRGB(142, 78, 40), Color3.fromRGB(143, 148, 154)
	local rope, ropeDark = Color3.fromRGB(200, 165, 119), Color3.fromRGB(156, 124, 82)
	local function drum(name: string, x0: number, x1: number, diameter: number, color: Color3, material: Enum.Material): Part
		local p = piece(tool, name, Vector3.new(x1 - x0, diameter, diameter), CFrame.new((x0 + x1) / 2, 0, 0), color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- A rope segment between two tool-frame points (a cylinder along its X).
	local function segment(name: string, a: Vector3, b: Vector3, color: Color3): Part
		local mid, length = (a + b) / 2, (b - a).Magnitude
		local p = piece(tool, name, Vector3.new(length * 1.08, 0.14, 0.14),
			CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0), color, fabric)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- A ring of rope in the X/Z plane (the rings' normal is tool Y).
	local function ring(name: string, centre: Vector3, radius: number, count: number): { Part }
		local list: { Part } = {}
		for i = 1, count do
			local a0, a1 = 2 * math.pi * (i - 1) / count, 2 * math.pi * i / count
			local p0 = centre + Vector3.new(math.cos(a0), 0, math.sin(a0)) * radius
			local p1 = centre + Vector3.new(math.cos(a1), 0, math.sin(a1)) * radius
			table.insert(list, segment(name, p0, p1, if i % 2 == 0 then ropeDark else rope))
		end
		return list
	end
	local handle = drum("LassoHandle", -0.85, 0.8, 0.37, brown, leather)
	drum("LassoFittings", 0.78, 1.12, 0.46, steel, metal)
	drum("LassoButtCap", -1.15, -0.83, 0.44, steel, metal)
	piece(tool, "LassoTassels", Vector3.new(0.09, 0.08, 0.7), CFrame.new(-1.28, 0, 0.42), Color3.fromRGB(160, 89, 44), leather)
	for _, part in ring("LassoCoilRing", Vector3.new(1.55, 0, 0.75), 0.5, 10) do part.Name = "LassoCoilRing" end
	local coil = segment("LassoCoil", Vector3.new(1.08, 0, 0.16), Vector3.new(1.5, 0, 0.26), rope)
	-- The loop: lead from the collar to the honda, the open ring, and a knot; all ride LassoLoop.
	local loop = segment("LassoLoop", Vector3.new(1.12, 0, 0.05), Vector3.new(2.3, 0, 0.4), rope)
	loop:SetAttribute("LassoLoopPiece", true)
	for _, part in ring("LassoLoopRing", Vector3.new(3.0, 0, 0.95), 0.85, 12) do part:SetAttribute("LassoLoopPiece", true) end
	local knot = piece(tool, "LassoHonda", Vector3.new(0.26, 0.22, 0.22), CFrame.new(2.3, 0, 0.4), ropeDark, fabric)
	knot:SetAttribute("LassoLoopPiece", true)
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= handle and child ~= loop and child ~= coil then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = if child:GetAttribute("LassoLoopPiece") then loop else handle, child, child
		end
	end
	rig(handle, { handle :: BasePart, loop, coil }, CFrame.identity, look)
	for name, point in look.model.points do
		local attachment = Instance.new("Attachment")
		attachment.Name, attachment.Position, attachment.Parent = name, handle.CFrame:PointToObjectSpace(point), handle
	end
	handle.Name = "Handle"
	tool.Grip = handle.CFrame:Inverse() * look.model.grip
	return tool
end

local procedural: { [string]: () -> Tool } = {
	Sickle = ToolModels.sickle, CornClippers = ToolModels.cornClippers, Pitchfork = ToolModels.pitchfork,
	HarvestHook = ToolModels.harvestHook, TwinSickles = ToolModels.twinSickles, LongScythe = ToolModels.longScythe,
	HedgeTrimmer = ToolModels.hedgeTrimmer, SpringLoadedPicker = ToolModels.springLoadedPicker, CornLasso = ToolModels.cornLasso,
}

-- Dual-wield tools (look.model.offhand): while the Tool is equipped, the server puts a copy of
-- its model inside the Tool, welded to the left hand ("LeftGrip"), so every client sees both
-- blades. It sits in the Tool, not loose in the character, because in first person Roblox's
-- camera hides every character part that is not inside a Tool (creator's report, Nov 6). The
-- copy is built once from the finished Tool (same meshes, trail and points; the trail
-- recoloured) and cloned on each equip; it is removed on unequip. The left hold is
-- look.model.offhand.grip in the same handle frame as the right one:
-- Tool.Grip = (handle -> tool frame) * grip.
local function attachOffhand(tool: Tool, look: ToolPresentation.Presentation)
	local spec = assert(look.model.offhand)
	local master = Instance.new("Model")
	master.Name = "Offhand"
	master:SetAttribute("ToolId", tool:GetAttribute("ToolId"))
	local copy = tool:Clone()
	for _, child in copy:GetChildren() do child.Parent = master end
	copy:Destroy()
	local handle = master:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		warn("[PopcornTycoon] " .. tool.Name .. " has no Handle to copy into the left hand")
		master:Destroy()
		return
	end
	handle.Name = "OffhandHandle"
	master.PrimaryPart = handle
	-- A WeldConstraint keeps whatever offset its parts have when it comes alive. In the copy the
	-- LeftGrip weld snaps the handle to the hand in that same moment, so the blade's constraint
	-- caught the wrong offset and the blade stayed ~110 studs away (Nov 6). Fixed Welds carry the
	-- offset measured here, where the copy's parts still sit as built.
	local constraints: { WeldConstraint } = {}
	for _, item in master:GetDescendants() do
		if item:IsA("WeldConstraint") then table.insert(constraints, item) end
	end
	for _, constraint in constraints do
		local a, b = constraint.Part0, constraint.Part1
		if a and b then
			local weld = Instance.new("Weld")
			weld.Name = "OffhandWeld"
			weld.Part0, weld.Part1 = a, b
			weld.C0, weld.C1 = a.CFrame:ToObjectSpace(b.CFrame), CFrame.identity
			weld.Parent = constraint.Parent
		end
		constraint:Destroy()
	end
	local trail = master:FindFirstChild("SwingTrail", true)
	if trail and trail:IsA("Trail") then
		trail.Color = ColorSequence.new(spec.trailColors[1], spec.trailColors[#spec.trailColors])
		trail.Enabled = false
	end
	local grip = tool.Grip * look.model.grip:Inverse() * spec.grip
	local held: Model? = nil
	local function detach()
		if held then held:Destroy() end
		held = nil
	end
	tool.Equipped:Connect(function()
		detach()
		local character = tool.Parent
		if not character or not character:IsA("Model") then return end
		local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
		if not hand or not hand:IsA("BasePart") then return end
		local attachment = hand:FindFirstChild("LeftGripAttachment")
		local weld = Instance.new("Weld")
		weld.Name = "LeftGrip"
		-- R6 arms without the attachment use the classic grip offset (as RightGrip does).
		weld.C0 = if attachment and attachment:IsA("Attachment") then attachment.CFrame
			else CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
		weld.C1 = grip
		local instance = master:Clone()
		weld.Part0, weld.Part1 = hand, instance.PrimaryPart
		weld.Parent = instance.PrimaryPart
		instance.Parent = tool
		held = instance
	end)
	tool.Unequipped:Connect(detach)
	tool.Destroying:Connect(function()
		detach()
		master:Destroy()
	end)
end

-- The tool frame (see ToolPresentation.Model) recovered from the imported meshes, so it does
-- not matter how the importer oriented or centred them: X runs along the handle mesh's long
-- axis toward the other meshes, Y is the head's thinnest axis, Z the side the head sits on.
local function toolFrame(handle: BasePart, others: { BasePart }, gripFromCentre: number, headName: string?, gripSide: number?): CFrame?
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
	-- gripSide: a grip bar off the handle mesh's centre (the Hedge Trimmer's rear loop).
	return CFrame.fromMatrix(handle.Position + x * gripFromCentre + z * (gripSide or 0), x, y, z)
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
	local frame = if handle then toolFrame(handle, others, look.model.gripFromCentre, look.model.head, look.model.gripSide) else nil
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
	if look and look.model.offhand then attachOffhand(built, look) end
	return built
end

return ToolModels
