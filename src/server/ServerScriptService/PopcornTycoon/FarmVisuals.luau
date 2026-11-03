--!strict
-- Stateless, bounded scenery generator. Coordinates are relative to the plot center.
-- No gameplay state, interactions, per-prop scripts, or background tasks belong here.
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
local Templates = require(script.Parent.VisualTemplates)
local FarmVisuals = {}
local colors = {
	grass = Color3.fromRGB(115, 174, 65), leaf = Color3.fromRGB(77, 143, 49),
	wood = Color3.fromRGB(157, 99, 53), trim = Color3.fromRGB(101, 62, 37),
	plank = Color3.fromRGB(188, 133, 73), roof = Color3.fromRGB(136, 70, 44),
	stone = Color3.fromRGB(159, 153, 137), dirt = Color3.fromRGB(186, 137, 85),
	gold = Color3.fromRGB(255, 207, 83), metal = Color3.fromRGB(63, 70, 70),
}

local function model(name: string, parent: Instance): Model
	local result = Instance.new("Model")
	result.Name, result.Parent = name, parent
	return result
end

-- Layout, viewed from the entrance (-Z): stations across the front facing the field,
-- the starter field behind them on the right, its expansion lawn on the left.
-- Purchased rows extend the field toward the back fence.
-- Returns the owner sign and the microwave's field-facing interaction frame.
function FarmVisuals.build(farm: Model, origin: Vector3, ownerName: string): (BasePart, CFrame)
	local center = origin + Config.Farm.plotOffset
	local scenery = model("Scenery", farm)
	-- Mirror X so +X in these coordinates is the visitor's right when entering from -Z.
	local function world(position: Vector3): Vector3
		return center + Vector3.new(-position.X, position.Y, position.Z)
	end
	local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name, p.Size, p.Position = name, size, world(position)
		p.Color, p.Material = color, material or Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end
	local function wood(parent: Instance, name: string, size: Vector3, position: Vector3, dark: boolean?): Part
		return part(parent, name, size, position, if dark then colors.trim else colors.wood, Enum.Material.Wood)
	end
	local function sign(parent: Instance, name: string, position: Vector3, size: Vector3, text: string, bothSides: boolean?): Part
		local board = wood(parent, name, size, position, true)
		for _, face in if bothSides then { Enum.NormalId.Front, Enum.NormalId.Back } else { Enum.NormalId.Front } do
			local gui = Instance.new("SurfaceGui")
			gui.Name, gui.Face, gui.PixelsPerStud = "Lettering", face, 40
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			local label = Instance.new("TextLabel")
			label.Name, label.Size = "Text", UDim2.fromScale(0.94, 0.85)
			label.Position, label.BackgroundTransparency = UDim2.fromScale(0.03, 0.075), 1
			label.Font, label.TextScaled, label.TextWrapped = Enum.Font.GothamBold, true, true
			label.TextColor3, label.Text = Color3.fromRGB(255, 239, 198), text
			label.Parent, gui.Parent = gui, board
		end
		return board
	end
	local function lantern(parent: Instance, position: Vector3, lit: boolean)
		local lamp = model("Lantern", parent)
		wood(lamp, "Bracket", Vector3.new(1.8, 0.25, 0.3), position + Vector3.new(0, 1, 0), true)
		for _, y in {-0.65, 0.65} do
			part(lamp, "Frame", Vector3.new(1.1, 0.18, 1.1), position + Vector3.new(0, y, 0), colors.metal)
		end
		local glow = part(lamp, "WarmGlass", Vector3.new(0.65, 1.15, 0.65), position, colors.gold, Enum.Material.Neon)
		for _, x in {-0.45, 0.45} do
			part(lamp, "Upright", Vector3.new(0.12, 1.3, 0.12), position + Vector3.new(x, 0, -0.45), colors.metal)
		end
		if lit then
			local light = Instance.new("PointLight")
			light.Color, light.Range, light.Brightness, light.Shadows = colors.gold, 12, 0.7, false
			light.Parent = glow
		end
	end
	-- Stations are authored with their fronts toward -Z around `anchor`, then turned to face the field.
	local function faceField(station: Model, anchor: Vector3)
		local pivot = CFrame.new(world(anchor))
		station.WorldPivot = pivot
		station:PivotTo(pivot * CFrame.Angles(0, math.pi, 0))
	end

	local s = Config.Starter
	local fieldCenter = Vector3.new(Config.Farm.plotOffset.X, 0, -Config.Farm.plotOffset.Z)
	local halfWidth = (s.columns - 1) / 2 * s.spacing + 4.3
	local halfDepth = (s.layoutRows - 1) / 2 * s.spacing + 4.3
	local fieldFront, fieldBack = fieldCenter.Z - halfDepth, fieldCenter.Z + halfDepth
	local fenceX, fenceZ = Config.Farm.plotSize.X / 2 - 1, Config.Farm.plotSize.Z / 2 - 1
	local crossZ = fieldFront - 4
	local stationZ = crossZ - 10
	local gateX = fieldCenter.X -- The entrance lines up with the field and the gap between the stations.
	local sideX = fieldCenter.X - halfWidth - 3
	local lawnCenter = Vector3.new(sideX - 3 - halfWidth, 0, fieldCenter.Z)

	local ground = part(scenery, "GrassFoundation", Config.Farm.plotSize, Vector3.new(0, -0.15, 0), colors.grass, Enum.Material.Grass)
	ground.CanCollide, ground.CanQuery = true, true
	local paths = model("Paths", scenery)
	local entranceLength = crossZ - (-fenceZ - 1)
	part(paths, "EntranceDirt", Vector3.new(8, 0.12, entranceLength), Vector3.new(gateX, 0.12, crossZ - entranceLength / 2), colors.dirt, Enum.Material.Ground)
	part(paths, "CrossPath", Vector3.new(fenceX * 2 - 4, 0.12, 4), Vector3.new(0, 0.12, crossZ), colors.dirt, Enum.Material.Ground)
	part(paths, "SidePath", Vector3.new(4, 0.12, fieldBack - crossZ), Vector3.new(sideX, 0.12, (fieldBack + crossZ) / 2), colors.dirt, Enum.Material.Ground)
	for i = 1, 4 do
		local stone = part(paths, "SteppingStone_" .. i, Vector3.new(0.22, 3.1, 5.1), Vector3.new(gateX + (if i % 2 == 0 then 0.35 else -0.3), 0.2, -fenceZ + 1 + i * 4.6), colors.stone, Enum.Material.Slate)
		stone.Shape = Enum.PartType.Cylinder
		stone.Orientation = Vector3.new(0, if i % 2 == 0 then 9 else -8, 90)
	end

	local field = model("FieldBorders", scenery)
	-- Beds cover every layout row, including the purchasable Extra Row at the back.
	for _, x in {-halfWidth, halfWidth} do
		wood(field, "Edging", Vector3.new(0.35, 0.4, halfDepth * 2 - 0.1), Vector3.new(fieldCenter.X + x, 0.15, fieldCenter.Z))
	end
	for _, z in {fieldFront, fieldBack} do
		wood(field, "Edging", Vector3.new(halfWidth * 2 + 0.3, 0.4, 0.35), Vector3.new(fieldCenter.X, 0.15, z))
	end
	for row = 1, s.layoutRows do
		part(field, "CultivatedRow_" .. row, Vector3.new(s.columns * s.spacing + 1, 0.15, 2.5), Vector3.new(fieldCenter.X, 0.28, fieldCenter.Z + (row - (s.layoutRows + 1) / 2) * s.spacing), Color3.fromRGB(123, 78, 43), Enum.Material.Ground)
	end

	local fence = model("PerimeterFence", scenery)
	local function fenceRun(a: Vector3, b: Vector3, segments: number)
		for i = 0, segments do
			local pos = a:Lerp(b, i / segments)
			wood(fence, "Post", Vector3.new(0.85, 4.2, 0.85), pos + Vector3.new(0, 2, 0))
			wood(fence, "PostCap", Vector3.new(1, 0.25, 1), pos + Vector3.new(0, 4.2, 0), true)
			part(fence, "StoneFooting", Vector3.new(1.2, 0.6, 1.2), pos + Vector3.new(0, 0.25, 0), colors.stone, Enum.Material.Slate)
			for _, y in {1.4, 3} do
				local bolt = part(fence, "IronPeg", Vector3.new(0.16, 0.16, 0.16), pos + Vector3.new(0, y, -0.48), colors.metal, Enum.Material.Metal)
				bolt.Shape = Enum.PartType.Ball
			end
			if i < segments then
				local nextPos = a:Lerp(b, (i + 1) / segments)
				for _, y in {1.4, 3} do
					local rail = wood(fence, "Rail", Vector3.new((nextPos - pos).Magnitude, 0.5, 0.3), (pos + nextPos) / 2 + Vector3.new(0, y, 0))
					if math.abs(b.Z - a.Z) > 0 then rail.Orientation = Vector3.new(0, 90, 0) end
				end
			end
		end
	end
	-- Runs of roughly nine studs keep the larger perimeter within the part budget.
	fenceRun(Vector3.new(-fenceX, 0, -fenceZ), Vector3.new(-fenceX, 0, fenceZ), 8)
	fenceRun(Vector3.new(fenceX, 0, -fenceZ), Vector3.new(fenceX, 0, fenceZ), 8)
	fenceRun(Vector3.new(-fenceX, 0, fenceZ), Vector3.new(fenceX, 0, fenceZ), 9)
	fenceRun(Vector3.new(-fenceX, 0, -fenceZ), Vector3.new(gateX - 5, 0, -fenceZ), 6)
	fenceRun(Vector3.new(gateX + 5, 0, -fenceZ), Vector3.new(fenceX, 0, -fenceZ), 2)
	lantern(fence, Vector3.new(gateX - 5, 3, -fenceZ - 0.8), true)
	lantern(fence, Vector3.new(gateX + 5, 3, -fenceZ - 0.8), true)
	local ownerBoard = sign(fence, "OwnerSign", Vector3.new(gateX - 15, 3, -fenceZ - 0.5), Vector3.new(13, 2.6, 0.5), ownerName .. "'s Farm")

	-- Every future expansion grows on the left of the starter field.
	local expansion = model("FutureExpansion", scenery)
	expansion:SetAttribute("VisualOnly", true)
	part(expansion, "ReservedGrass", Vector3.new(halfWidth * 2, 0.1, halfDepth * 2), lawnCenter + Vector3.new(0, 0.15, 0), Color3.fromRGB(140, 186, 76), Enum.Material.Grass)
	local lawnLeft, lawnRight = lawnCenter.X - halfWidth, lawnCenter.X + halfWidth
	for x = lawnLeft + 2, lawnRight - 1, 4 do
		for _, z in {fieldFront, fieldBack} do part(expansion, "BoundaryMarker", Vector3.new(2.2, 0.12, 0.2), Vector3.new(x, 0.23, z), colors.gold) end
	end
	for z = fieldFront + 2, fieldBack - 1, 4 do
		for _, x in {lawnLeft, lawnRight} do part(expansion, "BoundaryMarker", Vector3.new(0.2, 0.12, 2.2), Vector3.new(x, 0.23, z), colors.gold) end
	end
	wood(expansion, "SignPost", Vector3.new(0.4, 3, 0.4), Vector3.new(lawnCenter.X, 1.5, fieldFront + 2))
	sign(expansion, "ExpansionSign", Vector3.new(lawnCenter.X, 3, fieldFront + 2), Vector3.new(9, 2.5, 0.4), "ROOM TO GROW\nFuture expansion")

	-- The working microwave (interaction lives in FarmService) stands left of the entrance path.
	local microwaveAnchor = Vector3.new(gateX - 12, 0, stationZ)
	local station = model("MicrowaveStation", scenery)
	station:SetAttribute("VisualOnly", false)
	local function m(x: number, y: number, z: number): Vector3 return microwaveAnchor + Vector3.new(x, y, z) end
	for _, x in {-5, 5} do wood(station, "CanopyPost", Vector3.new(0.7, 8, 0.7), m(x, 4, 0)) end
	wood(station, "Counter", Vector3.new(11, 0.6, 5), m(0, 2.7, 0))
	for _, x in {-4, 4} do wood(station, "CounterLeg", Vector3.new(0.7, 2.5, 0.7), m(x, 1.25, -1)) end
	local canopy = part(station, "Canopy", Vector3.new(13, 0.5, 7), m(0, 8.5, 0), colors.roof, Enum.Material.Wood)
	canopy.Orientation = Vector3.new(-8, 0, 0)
	sign(station, "StationSign", m(0, 7, -3.2), Vector3.new(11, 1.7, 0.4), "MICROWAVE", true)
	sign(station, "HowTo", m(0, 1.7, -2.6), Vector3.new(8, 1.1, 0.3), "Press E to pop your corn")
	part(station, "MicrowaveBody", Vector3.new(6, 3, 3.5), m(0, 4.5, -0.5), Color3.fromRGB(220, 217, 186), Enum.Material.Metal)
	part(station, "DoorFrame", Vector3.new(4.3, 2.4, 0.15), m(-0.6, 4.5, -2.3), colors.metal)
	part(station, "AmberWindow", Vector3.new(3.6, 1.8, 0.16), m(-0.7, 4.5, -2.4), Color3.fromRGB(222, 132, 42), Enum.Material.Glass)
	part(station, "Handle", Vector3.new(0.2, 1.6, 0.25), m(1.35, 4.5, -2.55), colors.plank)
	for i = 1, 3 do part(station, "Button_" .. i, Vector3.new(0.35, 0.35, 0.2), m(2.3, 5.1 - i * 0.5, -2.4), colors.roof) end
	lantern(station, m(-5, 5.5, -2), false)
	lantern(station, m(5, 5.5, -2), false)

	-- The display-only tool shed stands right of the entrance path.
	local shedAnchor = Vector3.new(gateX + 12, 0, stationZ)
	local shed = model("ToolShed", scenery)
	shed:SetAttribute("VisualOnly", true)
	local function t(x: number, y: number, z: number): Vector3 return shedAnchor + Vector3.new(x, y, z) end
	wood(shed, "Floor", Vector3.new(13, 0.4, 9), t(0, 0.25, 0))
	for i = 0, 10 do wood(shed, "BackPlank_" .. i, Vector3.new(1.1, 7.6, 0.45), t(-6 + i * 1.2, 4, 4), i % 3 == 0) end
	for _, x in {-6.2, 6.2} do
		wood(shed, "SideWall", Vector3.new(0.5, 7.6, 8), t(x, 4, 0))
		wood(shed, "FrontPost", Vector3.new(0.8, 8, 0.8), t(x, 4, -4), true)
	end
	for _, side in {-1, 1} do
		local roof = part(shed, "PitchedRoof", Vector3.new(8, 0.55, 10.5), t(side * 3.5, 8.7, 0), colors.roof, Enum.Material.Wood)
		roof.Orientation = Vector3.new(0, 0, side * 23)
	end
	wood(shed, "RidgeBeam", Vector3.new(0.5, 0.5, 10.7), t(0, 10.25, 0), true)
	sign(shed, "ToolSign", t(0, 7.2, -4.4), Vector3.new(10, 1.7, 0.5), "TOOL SHED", true)
	sign(shed, "DisplayOnly", t(0, 1.4, -4.4), Vector3.new(9, 1, 0.4), "Future tools · display only")
	wood(shed, "DisplayBench", Vector3.new(10, 0.35, 2), t(0, 2.4, 1))
	for i = 1, 3 do
		local x = -7 + i * 3.5
		wood(shed, "ToolHandle_" .. i, Vector3.new(0.22, 3, 0.22), t(x, 4, 1))
		part(shed, "ToolHead_" .. i, Vector3.new(1.6, 0.35, 0.4), t(x, 5.4, 1), colors.metal, Enum.Material.Metal)
		if i == 2 then
			for tooth = -1, 1 do part(shed, "RakeTooth", Vector3.new(0.15, 0.8, 0.2), t(x + tooth * 0.55, 5.8, 1), colors.metal) end
		elseif i == 3 then part(shed, "Spade", Vector3.new(1.2, 1, 0.2), t(x, 5.6, 1), colors.metal) end
	end

	local props = model("GardenDetails", scenery)
	for _, pos in {Vector3.new(microwaveAnchor.X - 9, 1.3, stationZ + 1), Vector3.new(microwaveAnchor.X - 12, 1.3, stationZ - 2)} do
		local barrel = part(props, "Barrel", Vector3.new(2.6, 2.5, 2.5), pos, colors.wood, Enum.Material.Wood)
		barrel.Shape, barrel.Orientation = Enum.PartType.Cylinder, Vector3.new(0, 0, 90)
		for _, y in {-0.85, 0.85} do
			local band = part(props, "BarrelHoop", Vector3.new(0.18, 2.6, 2.6), pos + Vector3.new(0, y, 0), colors.metal, Enum.Material.Metal)
			band.Shape, band.Orientation = Enum.PartType.Cylinder, Vector3.new(0, 0, 90)
		end
	end
	for i = 1, 2 do
		local pos = Vector3.new(-fenceX + 6, 0.9 + (i - 1) * 1.7, stationZ - 3)
		part(props, "HayBale", Vector3.new(4, 1.8, 2.7), pos, colors.gold, Enum.Material.Fabric)
		for _, x in {-1.2, 1.2} do part(props, "BaleBinding", Vector3.new(0.18, 1.85, 2.75), pos + Vector3.new(x, 0, 0), colors.trim) end
	end
	local tufts = {
		Vector3.new(-fenceX + 3, 0, -fenceZ + 4), Vector3.new(-fenceX + 16, 0, -fenceZ + 4),
		Vector3.new(-fenceX + 3, 0, fenceZ - 4), Vector3.new(fenceX - 3, 0, fenceZ - 4),
		Vector3.new(gateX - 8, 0, -fenceZ + 2), Vector3.new(gateX + 8, 0, -fenceZ + 2),
	}
	for i, pos in tufts do
		for blade = 1, 3 do
			local leaf = part(props, "GrassTuft", Vector3.new(0.25, 1.2, 0.55), pos + Vector3.new((blade - 2) * 0.4, 0.5, 0), colors.leaf)
			leaf.Orientation = Vector3.new(0, i * 30, (blade - 2) * 25)
		end
		part(props, "FlowerStem", Vector3.new(0.12, 0.9, 0.12), pos + Vector3.new(0.8, 0.45, 0.3), colors.leaf)
		local flower = part(props, "Flower", Vector3.new(0.65, 0.25, 0.65), pos + Vector3.new(0.8, 1, 0.3), if i % 2 == 0 then Color3.fromRGB(244, 225, 174) else Color3.fromRGB(225, 147, 145))
		flower.Shape = Enum.PartType.Ball
	end

	-- Keep native signs readable while replacing structural placeholders with textured models.
	local microwaveMesh = Templates.clone("Microwave", station, world(microwaveAnchor), 12)
	local shedMesh = Templates.clone("Shed", shed, world(shedAnchor), 12.5)
	for _, entry in {{station, microwaveMesh}, {shed, shedMesh}} do
		local container, mesh = entry[1], entry[2]
		if mesh then
			for _, child in container:GetChildren() do
				if child:IsA("BasePart") and not child:FindFirstChildOfClass("SurfaceGui") then child:Destroy() end
			end
		end
	end
	if microwaveMesh then (station:FindFirstChild("StationSign") :: BasePart).Position = world(m(0, 9.2, -4.8)) end
	if shedMesh then (shed:FindFirstChild("ToolSign") :: BasePart).Position = world(t(0, 9, -5.8)) end
	faceField(station, microwaveAnchor)
	faceField(shed, shedAnchor)
	-- The door stood 4.5 studs in front of the kiosk before the turn; it now faces the field (+Z).
	local door = world(m(0, 3.5, 4.5))
	return ownerBoard, CFrame.lookAt(door, door + Vector3.new(0, 0, 1))
end

return FarmVisuals
