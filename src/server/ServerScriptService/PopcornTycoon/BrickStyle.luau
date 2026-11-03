--!strict
-- Classic Roblox brick look for generated scenery (creator request, Nov 3 2026): plastic
-- with Roblox's classic stud surfaces, and decorations players bump into instead of walking
-- through. Applied once to a finished scenery model before it is placed.
-- Crops, prompts, popcorn and other gameplay parts are never passed here.
local BrickStyle = {}

-- Glowing and see-through parts keep their material; everything else becomes plastic brick.
local keepMaterial: { [Enum.Material]: boolean } = {
	[Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true,
}
-- Walk-through rules: thin pieces lying on the ground (paths, beds, edging, markers) and tiny
-- details (pegs, flowers, buttons) stay passable so they never snag a walking player.
local FLAT_HEIGHT, FLAT_BOTTOM, TINY_SIZE = 0.8, 0.6, 1.5

local function isMesh(part: BasePart): boolean
	return part:IsA("MeshPart") or part:FindFirstChildWhichIsA("DataModelMesh") ~= nil
end

-- Raised classic studs on every face, inlets underneath, like a real brick. Surfaces are
-- drawn by the engine (no extra instances) and show on Plastic.
function BrickStyle.studs(part: BasePart)
	part.Material = Enum.Material.Plastic
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Studs, Enum.SurfaceType.Inlet
	part.FrontSurface, part.BackSurface = Enum.SurfaceType.Studs, Enum.SurfaceType.Studs
	part.LeftSurface, part.RightSurface = Enum.SurfaceType.Studs, Enum.SurfaceType.Studs
end

-- Brick finish and collision for every visible part under `root`. groundY is the walking
-- surface the model stands on. Parts already marked collidable stay that way; a part with the
-- WalkThrough attribute is left passable on purpose.
function BrickStyle.finish(root: Instance, groundY: number)
	for _, object in root:GetDescendants() do
		if object:IsA("BasePart") and object.Transparency < 1 then
			local mesh = isMesh(object)
			if not mesh and not keepMaterial[object.Material] then BrickStyle.studs(object) end
			if not object.CanCollide and not object:GetAttribute("WalkThrough") then
				local extents = object.ExtentsSize
				local bottom = object.Position.Y - extents.Y / 2 - groundY
				local flat = extents.Y < FLAT_HEIGHT and bottom < FLAT_BOTTOM
				local tiny = math.max(extents.X, extents.Y, extents.Z) < TINY_SIZE
				object.CanCollide = not flat and not tiny
			end
		end
	end
end

-- A blocky brick tree like a classic Roblox map: a flared trunk, two stubby branches and
-- stacked, slightly offset leaf slabs. `bottom` is the ground point; parts are solid.
function BrickStyle.tree(parent: Instance, bottom: Vector3, height: number, seed: number): Model
	local rng = Random.new(seed)
	local tree = Instance.new("Model")
	tree.Name = "BrickTree"
	local s = height / 18
	local bark, barkDark = Color3.fromRGB(105, 64, 40), Color3.fromRGB(86, 52, 34)
	local leaves = { Color3.fromRGB(39, 112, 45), Color3.fromRGB(46, 125, 50), Color3.fromRGB(34, 99, 40) }
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local function block(name: string, size: Vector3, offset: CFrame, color: Color3): Part
		local p = Instance.new("Part")
		p.Name, p.Size, p.Color = name, size, color
		p.CFrame = CFrame.new(bottom) * yaw * offset
		p.Anchored, p.CanCollide, p.CanTouch = true, true, false
		p.Parent = tree
		BrickStyle.studs(p)
		return p
	end
	block("TrunkBase", Vector3.new(3.2, 1.6, 3.2) * s, CFrame.new(0, 0.8 * s, 0), barkDark)
	block("Trunk", Vector3.new(2, 10, 2) * s, CFrame.new(0, 6 * s, 0), bark)
	for _, side in { -1, 1 } do
		block("Branch", Vector3.new(1.2, 4.5, 1.2) * s, CFrame.new(side * 1.6 * s, 10 * s, 0) * CFrame.Angles(0, 0, side * -0.65), bark)
	end
	local slabs = {
		{ size = Vector3.new(11, 3.2, 9), y = 11.8 },
		{ size = Vector3.new(8.5, 3, 10), y = 14.2 },
		{ size = Vector3.new(6, 2.6, 6), y = 16.6 },
	}
	for i, slab in slabs do
		local shift = Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
		block("Leaves", slab.size * s, CFrame.new((shift + Vector3.new(0, slab.y, 0)) * s), leaves[i])
	end
	tree.Parent = parent
	return tree
end

return BrickStyle
