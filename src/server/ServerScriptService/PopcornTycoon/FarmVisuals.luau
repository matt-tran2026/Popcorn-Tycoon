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

function FarmVisuals.build(farm: Model, origin: Vector3, ownerName: string): BasePart
	local center = origin + Config.Farm.plotOffset
	local scenery = model("Scenery", farm)
	local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		-- Mirror X so the crop bed is on the visitor's left when entering from -Z.
		p.Name, p.Size, p.Position = name, size, center + Vector3.new(-position.X, position.Y, position.Z)
		p.Color, p.Material = color, material or Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end
	local function wood(parent: Instance, name: string, size: Vector3, position: Vector3, dark: boolean?): Part
		return part(parent, name, size, position, if dark then colors.trim else colors.wood, Enum.Material.Wood)
	end
	local function sign(parent: Instance, name: string, position: Vector3, size: Vector3, text: string): Part
		local board = wood(parent, name, size, position, true)
		local gui = Instance.new("SurfaceGui")
		gui.Name, gui.Face, gui.PixelsPerStud = "Lettering", Enum.NormalId.Front, 40
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		local label = Instance.new("TextLabel")
		label.Name, label.Size = "Text", UDim2.fromScale(0.94, 0.85)
		label.Position, label.BackgroundTransparency = UDim2.fromScale(0.03, 0.075), 1
		label.Font, label.TextScaled, label.TextWrapped = Enum.Font.GothamBold, true, true
		label.TextColor3, label.Text = Color3.fromRGB(255, 239, 198), text
		label.Parent, gui.Parent = gui, board
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
	local ground = part(scenery, "GrassFoundation", Config.Farm.plotSize, Vector3.new(0, -0.15, 0), colors.grass, Enum.Material.Grass)
	ground.CanCollide, ground.CanQuery = true, true
	local paths = model("Paths", scenery)
	part(paths, "EntranceDirt", Vector3.new(8, 0.12, 16), Vector3.new(0, 0.12, -20), colors.dirt, Enum.Material.Ground)
	part(paths, "CrossPath", Vector3.new(37, 0.12, 4), Vector3.new(0, 0.12, -12), colors.dirt, Enum.Material.Ground)
	for i = 1, 7 do
		local stone = part(paths, "SteppingStone_" .. i, Vector3.new(5.1, 0.2, 2.6), Vector3.new(if i % 2 == 0 then 0.35 else -0.3, 0.2, -19 + i * 4.6), colors.stone, Enum.Material.Slate)
		stone.Orientation = Vector3.new(0, if i % 2 == 0 then 9 else -8, 0)
		stone.Shape = Enum.PartType.Cylinder
		stone.Size = Vector3.new(0.22, 3.1, 5.1)
		stone.Orientation = Vector3.new(0, if i % 2 == 0 then 9 else -8, 90)
	end
	local field = model("FieldBorders", scenery)
	for _, x in {-23.3, -0.7} do wood(field, "Edging", Vector3.new(0.35, 0.4, 18.5), Vector3.new(x, 0.15, 0)) end
	for _, z in {-9.3, 9.3} do wood(field, "Edging", Vector3.new(23, 0.4, 0.35), Vector3.new(-12, 0.15, z)) end
	for row = 1, Config.Starter.rows do
		part(field, "CultivatedRow_" .. row, Vector3.new(21, 0.15, 2.5), Vector3.new(-12, 0.28, (row - 2) * Config.Starter.spacing), Color3.fromRGB(123, 78, 43), Enum.Material.Ground)
	end
	local fence = model("PerimeterFence", scenery)
	local function fenceRun(a: Vector3, b: Vector3, segments: number)
		for i = 0, segments do
			local pos = a:Lerp(b, i / segments)
			wood(fence, "Post", Vector3.new(0.85, 4.2, 0.85), pos + Vector3.new(0, 2, 0))
			wood(fence, "PostCap", Vector3.new(1, 0.25, 1), pos + Vector3.new(0, 4.2, 0), true)
			local foot = part(fence, "StoneFooting", Vector3.new(1.2, 0.6, 1.2), pos + Vector3.new(0, 0.25, 0), colors.stone, Enum.Material.Slate)
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
	fenceRun(Vector3.new(-29, 0, -26), Vector3.new(-29, 0, 26), 6)
	fenceRun(Vector3.new(29, 0, -26), Vector3.new(29, 0, 26), 6)
	fenceRun(Vector3.new(-29, 0, 26), Vector3.new(29, 0, 26), 7)
	fenceRun(Vector3.new(-29, 0, -26), Vector3.new(-5, 0, -26), 3)
	fenceRun(Vector3.new(5, 0, -26), Vector3.new(29, 0, -26), 3)
	lantern(fence, Vector3.new(-5, 3, -26.8), true)
	lantern(fence, Vector3.new(5, 3, -26.8), true)
	local ownerBoard = sign(fence, "OwnerSign", Vector3.new(-15, 3, -26.5), Vector3.new(13, 2.6, 0.5), ownerName .. "'s Farm")
	local expansion = model("FutureExpansion", scenery)
	expansion:SetAttribute("VisualOnly", true)
	part(expansion, "ReservedGrass", Vector3.new(20, 0.1, 18), Vector3.new(16, 0.15, 0), Color3.fromRGB(140, 186, 76), Enum.Material.Grass)
	for i = 0, 5 do
		for _, z in {-9, 9} do part(expansion, "BoundaryMarker", Vector3.new(2.2, 0.12, 0.2), Vector3.new(6 + i * 4, 0.23, z), colors.gold) end
	end
	for i = 0, 4 do
		for _, x in {6, 26} do part(expansion, "BoundaryMarker", Vector3.new(0.2, 0.12, 2.2), Vector3.new(x, 0.23, -8 + i * 4), colors.gold) end
	end
	wood(expansion, "SignPost", Vector3.new(0.4, 3, 0.4), Vector3.new(16, 1.5, -7))
	sign(expansion, "ExpansionSign", Vector3.new(16, 3, -7), Vector3.new(9, 2.5, 0.4), "ROOM TO GROW\nFuture expansion")
	local station = model("MicrowaveStation", scenery)
	station:SetAttribute("VisualOnly", true)
	for _, x in {-9, 1} do
		wood(station, "CanopyPost", Vector3.new(0.7, 8, 0.7), Vector3.new(x, 4, 18))
	end
	wood(station, "Counter", Vector3.new(11, 0.6, 5), Vector3.new(-4, 2.7, 18))
	for _, x in {-8, 0} do wood(station, "CounterLeg", Vector3.new(0.7, 2.5, 0.7), Vector3.new(x, 1.25, 17)) end
	local canopy = part(station, "Canopy", Vector3.new(13, 0.5, 7), Vector3.new(-4, 8.5, 18), colors.roof, Enum.Material.Wood)
	canopy.Orientation = Vector3.new(-8, 0, 0)
	sign(station, "StationSign", Vector3.new(-4, 7, 14.8), Vector3.new(11, 1.7, 0.4), "MICROWAVE")
	sign(station, "ComingSoon", Vector3.new(-4, 1.7, 15.4), Vector3.new(8, 1.1, 0.3), "Popping soon · display only")
	part(station, "MicrowaveBody", Vector3.new(6, 3, 3.5), Vector3.new(-4, 4.5, 17.5), Color3.fromRGB(220, 217, 186), Enum.Material.Metal)
	part(station, "DoorFrame", Vector3.new(4.3, 2.4, 0.15), Vector3.new(-4.6, 4.5, 15.7), colors.metal)
	part(station, "AmberWindow", Vector3.new(3.6, 1.8, 0.16), Vector3.new(-4.7, 4.5, 15.6), Color3.fromRGB(222, 132, 42), Enum.Material.Glass)
	part(station, "Handle", Vector3.new(0.2, 1.6, 0.25), Vector3.new(-2.65, 4.5, 15.45), colors.plank)
	for i = 1, 3 do part(station, "Button_" .. i, Vector3.new(0.35, 0.35, 0.2), Vector3.new(-1.7, 5.1 - i * 0.5, 15.6), colors.roof) end
	lantern(station, Vector3.new(-9, 5.5, 16), false)
	lantern(station, Vector3.new(1, 5.5, 16), false)
	local shed = model("ToolShed", scenery)
	shed:SetAttribute("VisualOnly", true)
	wood(shed, "Floor", Vector3.new(13, 0.4, 9), Vector3.new(17, 0.25, 19))
	for i = 0, 10 do wood(shed, "BackPlank_" .. i, Vector3.new(1.1, 7.6, 0.45), Vector3.new(11 + i * 1.2, 4, 23), i % 3 == 0) end
	for _, x in {10.8, 23.2} do
		wood(shed, "SideWall", Vector3.new(0.5, 7.6, 8), Vector3.new(x, 4, 19))
		wood(shed, "FrontPost", Vector3.new(0.8, 8, 0.8), Vector3.new(x, 4, 15), true)
	end
	for _, side in {-1, 1} do
		local roof = part(shed, "PitchedRoof", Vector3.new(8, 0.55, 10.5), Vector3.new(17 + side * 3.5, 8.7, 19), colors.roof, Enum.Material.Wood)
		roof.Orientation = Vector3.new(0, 0, side * 23)
	end
	wood(shed, "RidgeBeam", Vector3.new(0.5, 0.5, 10.7), Vector3.new(17, 10.25, 19), true)
	sign(shed, "ToolSign", Vector3.new(17, 7.2, 14.6), Vector3.new(10, 1.7, 0.5), "TOOL SHED")
	sign(shed, "DisplayOnly", Vector3.new(17, 1.4, 14.6), Vector3.new(9, 1, 0.4), "Future tools · display only")
	wood(shed, "DisplayBench", Vector3.new(10, 0.35, 2), Vector3.new(17, 2.4, 20))
	for i = 1, 3 do
		local x = 10 + i * 3.5
		wood(shed, "ToolHandle_" .. i, Vector3.new(0.22, 3, 0.22), Vector3.new(x, 4, 20))
		part(shed, "ToolHead_" .. i, Vector3.new(1.6, 0.35, 0.4), Vector3.new(x, 5.4, 20), colors.metal, Enum.Material.Metal)
		if i == 2 then
			for tooth = -1, 1 do part(shed, "RakeTooth", Vector3.new(0.15, 0.8, 0.2), Vector3.new(x + tooth * 0.55, 5.8, 20), colors.metal) end
		elseif i == 3 then part(shed, "Spade", Vector3.new(1.2, 1, 0.2), Vector3.new(x, 5.6, 20), colors.metal) end
	end
	local props = model("GardenDetails", scenery)
	for _, pos in {Vector3.new(-16, 1.3, 19), Vector3.new(6, 1.3, 20)} do
		local barrel = part(props, "Barrel", Vector3.new(2.6, 2.5, 2.5), pos, colors.wood, Enum.Material.Wood)
		barrel.Shape, barrel.Orientation = Enum.PartType.Cylinder, Vector3.new(0, 0, 90)
		for _, y in {-0.85, 0.85} do
			local band = part(props, "BarrelHoop", Vector3.new(0.18, 2.6, 2.6), pos + Vector3.new(0, y, 0), colors.metal, Enum.Material.Metal)
			band.Shape, band.Orientation = Enum.PartType.Cylinder, Vector3.new(0, 0, 90)
		end
	end
	for i = 1, 2 do
		local pos = Vector3.new(-24, 0.9 + (i - 1) * 1.7, 18)
		part(props, "HayBale", Vector3.new(4, 1.8, 2.7), pos, colors.gold, Enum.Material.Fabric)
		for _, x in {-1.2, 1.2} do part(props, "BaleBinding", Vector3.new(0.18, 1.85, 2.75), pos + Vector3.new(x, 0, 0), colors.trim) end
	end
	for i, pos in {Vector3.new(-25, 0, -20), Vector3.new(23, 0, -20), Vector3.new(-25, 0, 11), Vector3.new(26, 0, 12), Vector3.new(9, 0, -22), Vector3.new(-9, 0, -22)} do
		for blade = 1, 3 do
			local leaf = part(props, "GrassTuft", Vector3.new(0.25, 1.2, 0.55), pos + Vector3.new((blade - 2) * 0.4, 0.5, 0), colors.leaf)
			leaf.Orientation = Vector3.new(0, i * 30, (blade - 2) * 25)
		end
		part(props, "FlowerStem", Vector3.new(0.12, 0.9, 0.12), pos + Vector3.new(0.8, 0.45, 0.3), colors.leaf)
		local flower = part(props, "Flower", Vector3.new(0.65, 0.25, 0.65), pos + Vector3.new(0.8, 1, 0.3), if i % 2 == 0 then Color3.fromRGB(244, 225, 174) else Color3.fromRGB(225, 147, 145))
		flower.Shape = Enum.PartType.Ball
	end
	-- Keep native signs readable while replacing structural placeholders with textured models.
	local microwaveMesh = Templates.clone("Microwave", station, center + Vector3.new(4, 0, 18), 12)
	local shedMesh = Templates.clone("Shed", shed, center + Vector3.new(-17, 0, 19), 12.5)
	for _, entry in {{station, microwaveMesh}, {shed, shedMesh}} do
		local container, mesh = entry[1], entry[2]
		if mesh then
			for _, child in container:GetChildren() do
				if child:IsA("BasePart") and not child:FindFirstChildOfClass("SurfaceGui") then child:Destroy() end
			end
		end
	end
	if microwaveMesh then
		local board = station:FindFirstChild("StationSign") :: BasePart
		board.Position = center + Vector3.new(4, 9.2, 13.2)
	end
	if shedMesh then
		local board = shed:FindFirstChild("ToolSign") :: BasePart
		board.Position = center + Vector3.new(-17, 9, 13.2)
	end
	return ownerBoard
end

return FarmVisuals
