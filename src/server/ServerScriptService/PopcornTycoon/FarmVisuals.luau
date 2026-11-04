--!strict
-- Stateless, bounded scenery generator. Coordinates are relative to the plot center.
-- No gameplay state, interactions, per-prop scripts, or background tasks belong here.
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
local Templates = require(script.Parent.VisualTemplates)
local FarmVisuals = {}
-- The Blender kiosk is 15.77 studs tall as authored; this is its height on the farm.
local KIOSK_HEIGHT, KIOSK_AUTHORED = 12.6, 15.7669
-- The Blender sell stand (Nov 4 2026) is 15.95 studs tall as authored; same scale as the kiosk.
local SELL_AUTHORED = 15.95
local SELL_HEIGHT = SELL_AUTHORED * KIOSK_HEIGHT / KIOSK_AUTHORED
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

-- Plain anchored part at a world position, for the per-plot pieces built in canonical coordinates.
local function plain(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.Position = name, size, position
	p.Color, p.Material = color, material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Edging and tilled strips for every layout row of an owned plot centred on `center`
-- (canonical frame, ground height). Empty strips show where bought rows will go.
function FarmVisuals.buildPlotBed(parent: Instance, center: Vector3)
	local s = Config.Plot
	local rows = Config.layoutRows()
	local halfWidth = (s.columns - 1) / 2 * s.spacing + 4.3
	local halfDepth = (rows - 1) / 2 * s.spacing + 4.3
	for _, x in { -halfWidth, halfWidth } do
		plain(parent, "Edging", Vector3.new(0.35, 0.4, halfDepth * 2 - 0.1), center + Vector3.new(x, 0.15, 0), colors.wood, Enum.Material.Wood)
	end
	for _, z in { -halfDepth, halfDepth } do
		plain(parent, "Edging", Vector3.new(halfWidth * 2 + 0.3, 0.4, 0.35), center + Vector3.new(0, 0.15, z), colors.wood, Enum.Material.Wood)
	end
	for row = 1, rows do
		plain(parent, "CultivatedRow_" .. row, Vector3.new(s.columns * s.spacing + 1, 0.15, 2.5), center + Vector3.new(0, 0.28, (row - (rows + 1) / 2) * s.spacing), Color3.fromRGB(123, 78, 43), Enum.Material.Ground)
	end
end

-- A plot cell not bought yet: lighter lawn with a thin gold border. Five parts per cell keeps
-- eight locked cells on every island (open plots included) cheap.
function FarmVisuals.buildLockedCell(parent: Instance, center: Vector3)
	local size = Config.cellSize()
	local halfX, halfZ = size.X / 2 - 1, size.Y / 2 - 1
	plain(parent, "ReservedGrass", Vector3.new(halfX * 2, 0.1, halfZ * 2), center + Vector3.new(0, 0.15, 0), Color3.fromRGB(140, 186, 76), Enum.Material.Grass)
	for _, z in { -halfZ, halfZ } do plain(parent, "BoundaryMarker", Vector3.new(halfX * 2, 0.12, 0.3), center + Vector3.new(0, 0.23, z), colors.gold) end
	for _, x in { -halfX, halfX } do plain(parent, "BoundaryMarker", Vector3.new(0.3, 0.12, halfZ * 2), center + Vector3.new(x, 0.23, 0), colors.gold) end
end

-- Layout, viewed from the entrance (-Z): stations across the front facing the field, the
-- 3x3 plot grid behind them with dirt walkways between the cells. Plot beds and locked
-- cells are built by FarmService (buildPlotBed / buildLockedCell) as plots change hands.
-- Returns the owner sign and the field-facing interaction frames of the microwave
-- and sell stand (FarmService puts the prompts there).
-- A nil ownerName builds an unclaimed plot's sign.
function FarmVisuals.build(farm: Model, origin: Vector3, ownerName: string?): (BasePart, CFrame, CFrame)
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

	-- Grid geometry in these mirrored, island-centred coordinates.
	local cell = Config.cellSize()
	local gap = Config.Grid.gap
	local starter = Vector3.new(Config.Farm.plotOffset.X, 0, -Config.Farm.plotOffset.Z) -- plot 1's center
	local gridFront = starter.Z - cell.Y / 2
	local gridBack = gridFront + 3 * cell.Y + 2 * gap
	local gridWidth = 3 * cell.X + 2 * gap
	local fenceX, fenceZ = Config.Farm.plotSize.X / 2 - 1, Config.Farm.plotSize.Z / 2 - 1
	local crossZ = gridFront - 4
	local stationZ = crossZ - 10
	local gateX = starter.X -- The entrance lines up with the starter plot and the gap between the stations.

	local ground = part(scenery, "GrassFoundation", Config.Farm.plotSize, Vector3.new(0, -0.15, 0), colors.grass, Enum.Material.Grass)
	ground.CanCollide, ground.CanQuery = true, true
	local paths = model("Paths", scenery)
	local entranceLength = crossZ - (-fenceZ - 1)
	part(paths, "EntranceDirt", Vector3.new(8, 0.12, entranceLength), Vector3.new(gateX, 0.12, crossZ - entranceLength / 2), colors.dirt, Enum.Material.Ground)
	part(paths, "CrossPath", Vector3.new(fenceX * 2 - 4, 0.12, 4), Vector3.new(0, 0.12, crossZ), colors.dirt, Enum.Material.Ground)
	-- Walkways between the plot cells: two running back from the cross path, two across.
	for _, side in { -1, 1 } do
		local x = starter.X + side * (cell.X + gap) / 2
		part(paths, "Walkway", Vector3.new(4, 0.12, gridBack - crossZ), Vector3.new(x, 0.12, (gridBack + crossZ) / 2), colors.dirt, Enum.Material.Ground)
	end
	for k = 1, 2 do
		local z = gridFront + k * (cell.Y + gap) - gap / 2
		part(paths, "Walkway", Vector3.new(gridWidth, 0.12, 4), Vector3.new(starter.X, 0.12, z), colors.dirt, Enum.Material.Ground)
	end
	for i = 1, 4 do
		local stone = part(paths, "SteppingStone_" .. i, Vector3.new(0.22, 3.1, 5.1), Vector3.new(gateX + (if i % 2 == 0 then 0.35 else -0.3), 0.2, -fenceZ + 1 + i * 4.6), colors.stone, Enum.Material.Slate)
		stone.Shape = Enum.PartType.Cylinder
		stone.Orientation = Vector3.new(0, if i % 2 == 0 then 9 else -8, 90)
	end

	local fence = model("PerimeterFence", scenery)
	local function fenceRun(a: Vector3, b: Vector3, segments: number)
		-- Spaced rails read as ladder rungs to Humanoids, which then climb them; an invisible
		-- wall along the run keeps the fence a barrier (a full jump still clears it).
		local barrier = part(fence, "FenceBarrier", Vector3.new((b - a).Magnitude, 4.2, 0.6), (a + b) / 2 + Vector3.new(0, 2.1, 0), colors.wood)
		barrier.Transparency, barrier.CanCollide = 1, true
		if math.abs(b.Z - a.Z) > 0 then barrier.Orientation = Vector3.new(0, 90, 0) end
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
	-- Runs of roughly 14 studs keep the 3x3 island's long perimeter within the part budget.
	fenceRun(Vector3.new(-fenceX, 0, -fenceZ), Vector3.new(-fenceX, 0, fenceZ), 16)
	fenceRun(Vector3.new(fenceX, 0, -fenceZ), Vector3.new(fenceX, 0, fenceZ), 16)
	fenceRun(Vector3.new(-fenceX, 0, fenceZ), Vector3.new(fenceX, 0, fenceZ), 8)
	fenceRun(Vector3.new(-fenceX, 0, -fenceZ), Vector3.new(gateX - 5, 0, -fenceZ), 4)
	fenceRun(Vector3.new(gateX + 5, 0, -fenceZ), Vector3.new(fenceX, 0, -fenceZ), 4)
	lantern(fence, Vector3.new(gateX - 5, 3, -fenceZ - 0.8), true)
	lantern(fence, Vector3.new(gateX + 5, 3, -fenceZ - 0.8), true)
	local ownerBoard = sign(fence, "OwnerSign", Vector3.new(gateX - 15, 3, -fenceZ - 0.5), Vector3.new(13, 2.6, 0.5), if ownerName then ownerName .. "'s Farm" else "Open Farm")

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

	-- Tools are bought from the Shop menu; no building sells them.
	local sellAnchor = Vector3.new(gateX - 28, 0, stationZ)

	-- The sell stand: a little theater-style popcorn cart left of the microwave, so selling
	-- is the next stop after popping. Interaction lives in FarmService/SellService.
	local stand = model("SellStand", scenery)
	stand:SetAttribute("VisualOnly", false)
	local function c(x: number, y: number, z: number): Vector3 return sellAnchor + Vector3.new(x, y, z) end
	local cream, red = Color3.fromRGB(255, 240, 209), Color3.fromRGB(217, 76, 58)
	wood(stand, "Counter", Vector3.new(8, 0.5, 3.6), c(0, 3, 0))
	part(stand, "CounterFront", Vector3.new(8, 2.7, 0.3), c(0, 1.5, -1.65), red, Enum.Material.Wood)
	for i = -3, 3, 2 do part(stand, "FrontStripe", Vector3.new(0.6, 2.7, 0.32), c(i, 1.5, -1.66), cream, Enum.Material.Wood) end
	for _, x in {-3.7, 3.7} do wood(stand, "AwningPost", Vector3.new(0.45, 6, 0.45), c(x, 3, 1.4), true) end
	for i = 0, 7 do
		local stripe = part(stand, "AwningStripe", Vector3.new(1, 0.25, 4.6), c(-3.5 + i, 6.15, -0.6), if i % 2 == 0 then red else cream, Enum.Material.Fabric)
		stripe.Orientation = Vector3.new(14, 0, 0)
	end
	sign(stand, "SellSign", c(0, 7.1, 1.3), Vector3.new(7, 1.5, 0.35), "SELL POPCORN", true)
	-- A striped popcorn bucket and a jar of coins on the counter.
	for i = 0, 5 do
		local angle = i * math.pi / 3
		part(stand, "BucketStripe", Vector3.new(0.45, 1.5, 0.2), c(-2 + math.cos(angle) * 0.6, 4, math.sin(angle) * 0.6), if i % 2 == 0 then red else cream)
	end
	for i = 1, 4 do
		local kernel = part(stand, "BucketPopcorn", Vector3.new(0.6, 0.6, 0.6), c(-2 + (i - 2.5) * 0.35, 4.85 + (i % 2) * 0.2, (i % 2 - 0.5) * 0.4), cream)
		kernel.Shape = Enum.PartType.Ball
	end
	local jar = part(stand, "CoinJar", Vector3.new(1.3, 1.1, 1.1), c(2, 3.8, 0), Color3.fromRGB(190, 225, 235), Enum.Material.Glass)
	jar.Shape, jar.Orientation, jar.Transparency = Enum.PartType.Cylinder, Vector3.new(0, 0, 90), 0.35
	local coins = part(stand, "Coins", Vector3.new(0.6, 0.95, 0.95), c(2, 3.55, 0), colors.gold, Enum.Material.Metal)
	coins.Shape, coins.Orientation = Enum.PartType.Cylinder, Vector3.new(0, 0, 90)

	local props = model("GardenDetails", scenery)
	for _, pos in {Vector3.new(sellAnchor.X - 8, 1.3, stationZ + 1), Vector3.new(sellAnchor.X - 11, 1.3, stationZ - 2)} do
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
	local brickKiosk = Templates.has("Microwave", "WindowCenter")
	local microwaveMesh = Templates.clone("Microwave", station, world(microwaveAnchor), if brickKiosk then KIOSK_HEIGHT else 12)
	if microwaveMesh and brickKiosk then
		-- The Blender brick kiosk (Nov 4 2026) carries its own sign, so every placeholder goes.
		for _, child in station:GetChildren() do
			if child ~= microwaveMesh then child:Destroy() end
		end
		FarmVisuals.dressMicrowave(station, microwaveMesh)
	elseif microwaveMesh then
		for _, child in station:GetChildren() do
			if child:IsA("BasePart") and not child:FindFirstChildOfClass("SurfaceGui") then child:Destroy() end
		end
		(station:FindFirstChild("StationSign") :: BasePart).Position = world(m(0, 9.2, -4.8))
	end
	-- The Blender sell stand and its vendor replace the part-built cart when the template is in the place.
	local sellMesh = if Templates.has("Sell", "SellBase") then Templates.clone("Sell", stand, world(sellAnchor), SELL_HEIGHT) else nil
	if sellMesh then
		for _, child in stand:GetChildren() do
			if child ~= sellMesh then child:Destroy() end
		end
		-- Centre the counter (the authored origin), not the bounds, which include the vendor's step.
		local origin = (sellMesh:FindFirstChild("SellBase", true) :: BasePart):GetPivot().Position
		local shift = world(sellAnchor) - origin
		sellMesh:PivotTo(sellMesh:GetPivot() + Vector3.new(shift.X, 0, shift.Z))
		FarmVisuals.dressSell(stand, sellMesh)
	end
	faceField(station, microwaveAnchor)
	faceField(stand, sellAnchor)
	-- The door stood 4.5 studs in front of the kiosk before the turn; it now faces the field (+Z).
	local function front(position: Vector3): CFrame
		local at = world(position)
		return CFrame.lookAt(at, at + Vector3.new(0, 0, 1))
	end
	return ownerBoard, front(m(0, 3.5, 4.5)), front(c(0, 3.5, 3.5))
end

-- Live pieces for the brick kiosk, placed from the anchor attachments authored in the template
-- (stand front toward -Z, before the station turns to face the field). The microwave body and
-- its window, glow and display go in a "MicrowaveUnit" model that clients shake while it cooks
-- (MicrowaveController); marquee bulbs on the sign chase like the hub arches.
local function piece(parent: Instance, name: string, sz: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color, p.Material = name, sz, cf, color, material
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p:SetAttribute("WalkThrough", true)
	p.Parent = parent
	return p
end

-- Marquee bulbs along the top and bottom of a sign frame (chased by AmbientController).
local function signBulbs(parent: Instance, signAt: CFrame, frame: Vector2, k: number)
	local count = 11
	for row, y in { frame.Y / 2 - 0.14 * k, -frame.Y / 2 + 0.14 * k } do
		for i = 0, count - 1 do
			local x = (i / (count - 1) - 0.5) * (frame.X - 0.9 * k)
			local b = piece(parent, "Bulb", Vector3.one * 0.42 * k, signAt * CFrame.new(x, y, -0.06 * k), colors.gold, Enum.Material.Neon)
			b.Shape = Enum.PartType.Ball
			b:SetAttribute("Bulb", i + (row - 1) * 2)
		end
	end
end

function FarmVisuals.dressMicrowave(station: Model, kiosk: Model)
	local _, size = kiosk:GetBoundingBox()
	local k = size.Y / KIOSK_AUTHORED -- authored studs -> placed studs
	local function anchor(name: string): (CFrame, Vector2)
		local a = kiosk:FindFirstChild(name, true) :: Attachment
		local s = a:GetAttribute("Size")
		return a.WorldCFrame, if typeof(s) == "Vector2" then s * k else Vector2.zero
	end
	local microwave = model("MicrowaveUnit", station)
	local body = kiosk:FindFirstChild("MicrowaveBody", true) :: BasePart
	body.Parent = microwave
	local windowAt, window = anchor("WindowCenter")
	-- Warm light behind tinted glass; dark until it cooks.
	local glow = piece(microwave, "WindowGlow", Vector3.new(window.X, window.Y, 0.05 * k), windowAt * CFrame.new(0, 0, 0.03 * k), Color3.fromRGB(255, 146, 40), Enum.Material.Neon)
	glow.Transparency = 1
	local light = Instance.new("PointLight")
	light.Name, light.Color, light.Range, light.Brightness, light.Shadows = "CookLight", Color3.fromRGB(255, 180, 80), 7, 0, false
	light.Parent = glow
	-- A faint tinted pane. Not Glass material: Roblox hides transparent parts (the glow) behind Glass.
	local glass = piece(microwave, "WindowGlass", Vector3.new(window.X, window.Y, 0.04 * k), windowAt * CFrame.new(0, 0, -0.05 * k), Color3.fromRGB(170, 215, 235), Enum.Material.SmoothPlastic)
	glass.Transparency, glass.Reflectance = 0.82, 0.2
	glass:SetAttribute("KeepFinish", true)
	local displayAt, display = anchor("DisplayCenter")
	local screen = piece(microwave, "Display", Vector3.new(display.X, display.Y, 0.04 * k), displayAt, Color3.fromRGB(20, 26, 30), Enum.Material.SmoothPlastic)
	screen.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.LightInfluence, gui.Brightness = "Readout", Enum.NormalId.Front, 0, 1.6
	gui.SizingMode, gui.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, 80
	local readout = Instance.new("TextLabel")
	readout.Name, readout.BackgroundTransparency, readout.Size = "Time", 1, UDim2.fromScale(1, 1)
	readout.Font, readout.TextScaled, readout.Text = Enum.Font.Arcade, true, "0:00"
	readout.TextColor3 = Color3.fromRGB(110, 255, 200)
	readout.Parent, gui.Parent = gui, screen
	-- Popcorn bursting out of the top while it cooks (client-toggled).
	local topAt = anchor("MicrowaveTop")
	local vent = piece(microwave, "PopVent", Vector3.new(2, 0.2, 1.5) * k, topAt, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	vent.Transparency = 1
	local burst = Instance.new("ParticleEmitter")
	burst.Name, burst.Enabled, burst.Rate = "PopBurst", false, 0
	burst.Texture = "rbxassetid://112894460849000" -- Blender popcorn piece (HubSpectacle.Art.Popcorn)
	burst.Speed, burst.SpreadAngle = NumberRange.new(9, 14), Vector2.new(30, 30)
	burst.Acceleration, burst.Lifetime = Vector3.new(0, -30, 0), NumberRange.new(0.7, 1)
	burst.Size = NumberSequence.new(0.7 * k, 0.5 * k)
	burst.Rotation, burst.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-300, 300)
	burst.EmissionDirection, burst.Parent = Enum.NormalId.Top, vent
	-- Marquee bulbs along the top and bottom of the sign frame, and a glowing globe on each post.
	local bulbs = Instance.new("Folder")
	bulbs.Name, bulbs.Parent = "Bulbs", station
	local signAt, frame = anchor("SignFront")
	signBulbs(bulbs, signAt, frame, k)
	for _, name in { "PostTopL", "PostTopR" } do
		local at = anchor(name)
		local globe = piece(bulbs, "Globe", Vector3.one * 0.9 * k, at, colors.gold, Enum.Material.Neon)
		globe.Shape = Enum.PartType.Ball
	end
	-- The kiosk meshes are solid (players bump the counter and posts), the awning and sign too.
	for _, d in kiosk:GetDescendants() do
		if d:IsA("MeshPart") then d.CanCollide, d.CanQuery = true, true end
	end
	body.CanCollide, body.CanQuery = true, true
end

-- Live pieces for the Blender sell stand (Assets/SellStand, anchors.json). Positions are the authored
-- Blender studs (x, y, z; front = -y) from the SellBase origin, mapped to Studio (-x, z, y) before the
-- stand turns to face the field. The vendor and coin meshes keep their authored pivots (shoulders,
-- coin centre); AmbientController animates them from the Ambient attributes set here.
function FarmVisuals.dressSell(stand: Model, kiosk: Model)
	local _, size = kiosk:GetBoundingBox()
	local k = size.Y / SELL_AUTHORED
	local origin = (kiosk:FindFirstChild("SellBase", true) :: BasePart):GetPivot().Position
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(origin + Vector3.new(-x, z, y) * k)
	end
	local function label(parent: BasePart, text: string, font: Enum.Font, color: Color3, background: Color3?): TextLabel
		local gui = Instance.new("SurfaceGui")
		gui.Name, gui.Face, gui.LightInfluence = "Lettering", Enum.NormalId.Front, 0.4
		gui.SizingMode, gui.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, 60
		local t = Instance.new("TextLabel")
		t.Name, t.Size, t.Position = "Text", UDim2.fromScale(0.92, 0.8), UDim2.fromScale(0.04, 0.1)
		t.BackgroundTransparency, t.Font, t.TextScaled, t.Text, t.TextColor3 = 1, font, true, text, color
		if background then
			t.Size, t.Position, t.BackgroundTransparency, t.BackgroundColor3 = UDim2.fromScale(1, 1), UDim2.new(), 0, background
			gui.LightInfluence, gui.Brightness = 0, 1.6 -- a lit screen
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color, stroke.Thickness = Color3.fromRGB(68, 49, 38), 2
		stroke.Parent, t.Parent, gui.Parent = t, gui, parent
		return t
	end
	-- No price on the stand: popcorn variants sell for different amounts (creator, Nov 4 2026).
	-- The prompt's ObjectText shows the actual payout. The register screen just shows cash.
	local screen = piece(stand, "RegisterScreen", Vector3.new(1.3 * k, 0.62 * k, 0.03 * k), at(3.2, -0.38, 6.89), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	screen.Transparency = 1
	label(screen, "$$$", Enum.Font.Arcade, Color3.fromRGB(124, 240, 122), Color3.fromRGB(35, 39, 44))
	-- Marquee bulbs on the sign and a glowing globe on each post, like the microwave kiosk.
	local bulbs = Instance.new("Folder")
	bulbs.Name, bulbs.Parent = "Bulbs", stand
	signBulbs(bulbs, at(0, 1.82, 11.95), Vector2.new(11.3, 2.8) * k, k)
	for _, x in { -5.95, 5.95 } do
		local globe = piece(bulbs, "Globe", Vector3.one * 0.9 * k, at(x, 2.2, 12.8), colors.gold, Enum.Material.Neon)
		globe.Shape = Enum.PartType.Ball
	end
	-- Movers get an upright axis part as PrimaryPart, so their pivot follows every later turn.
	local function mover(name: string, kind: string, axisAt: CFrame, parts: { string }): Model
		local m = Instance.new("Model")
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- arrives whole for the client animator
		m.Name, m.Parent = name, stand
		local axis = piece(m, "Axis", Vector3.one * 0.2, axisAt, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		axis.Transparency = 1
		m.PrimaryPart = axis
		for _, partName in parts do
			local p = kiosk:FindFirstChild(partName, true) :: BasePart
			p:SetAttribute("WalkThrough", true)
			p.CanCollide, p.CanQuery = false, false
			p.Parent = m
		end
		m:SetAttribute("Ambient", kind)
		return m
	end
	mover("SpinCoin", "Spin", at(0, 2.2, 14.75), { "SellCoin" }):SetAttribute("SpinSpeed", 1.6)
	-- The vendor: SellService stamps CheerAt on a sale and every client plays the wave and hop.
	local vendor = mover("SellVendor", "Vendor", at(-1, 3.75, 1.3), { "VendorBody", "VendorArmL", "VendorArmR" })
	vendor:SetAttribute("CheerAt", 0)
	-- The counter, posts, sign and awning are solid like the kiosk.
	for _, d in kiosk:GetDescendants() do
		if d:IsA("MeshPart") then d.CanCollide, d.CanQuery = true, true end
	end
end

return FarmVisuals
