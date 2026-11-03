--!strict
-- The shared map: a hexagonal hub island, one bridge and island per farm slot, and
-- bridge-head signs naming each slot's owner. Static scenery generated once; the only
-- runtime change is setSlotOwner. Farms themselves are built by FarmService.
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
local Brick = require(script.Parent.BrickStyle)
local MapVisuals = {}
local colors = {
	grass = Color3.fromRGB(115, 174, 65), sand = Color3.fromRGB(222, 196, 140),
	dirt = Color3.fromRGB(186, 137, 85), wood = Color3.fromRGB(157, 99, 53),
	trim = Color3.fromRGB(101, 62, 37), stone = Color3.fromRGB(159, 153, 137),
	gold = Color3.fromRGB(255, 207, 83), red = Color3.fromRGB(214, 48, 49),
	white = Color3.fromRGB(255, 250, 238), metal = Color3.fromRGB(63, 70, 70),
}
local slotSigns: { [number]: TextLabel } = {}

local function angle(slot: number): number
	return slot * 2 * math.pi / Config.Map.slots
end

-- World frame of a slot's farm entrance: ZVector points from the hub out along the bridge.
local function entranceFrame(slot: number): CFrame
	return CFrame.new(Config.Map.center) * CFrame.Angles(0, angle(slot), 0) * CFrame.new(0, 0, Config.Map.entranceRadius)
end

-- Maps the canonical farm frame (Config.Farm, entrance on -Z) onto a slot.
function MapVisuals.farmFrame(slot: number): CFrame
	local farm = Config.Farm
	local plotCenter = farm.origin + farm.plotOffset
	local entrance = Vector3.new(farm.origin.X, 0, plotCenter.Z - farm.plotSize.Z / 2)
	return entranceFrame(slot) * CFrame.new(entrance):Inverse()
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame = name, size, cframe
	p.Color, p.Material = color, material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanTouch = true, false
	p.CanCollide, p.CanQuery = collide == true, collide == true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function lettering(board: Part, text: string): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.PixelsPerStud = "Lettering", Enum.NormalId.Front, 40
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local label = Instance.new("TextLabel")
	label.Name, label.Size = "Text", UDim2.fromScale(0.94, 0.85)
	label.Position, label.BackgroundTransparency = UDim2.fromScale(0.03, 0.075), 1
	label.Font, label.TextScaled, label.TextWrapped = Enum.Font.GothamBold, true, true
	label.TextColor3, label.Text = Color3.fromRGB(255, 239, 198), text
	label.Parent, gui.Parent = gui, board
	return label
end

-- A regular hexagon as three overlapping rectangles, flats facing the bridges.
local function hexagon(parent: Instance, name: string, apothem: number, top: number, height: number, color: Color3, material: Enum.Material)
	local side = 2 * apothem / math.sqrt(3)
	for i = 0, 2 do
		-- Tops step down by a hair so the overlapping stud textures never z-fight.
		local cframe = CFrame.new(Config.Map.center + Vector3.new(0, top - i * 0.03 - height / 2, 0)) * CFrame.Angles(0, angle(i), 0)
		part(parent, name, Vector3.new(side, height, apothem * 2), cframe, color, material, true)
	end
end

local function buildHub(root: Model)
	local map = Config.Map
	local center, a, width = map.center, map.hubApothem, map.bridgeWidth
	local hub = Instance.new("Model")
	hub.Name, hub.Parent = "HubIsland", root
	hexagon(hub, "Shore", a + 1.5, -1, 9, colors.sand, Enum.Material.Sand)
	hexagon(hub, "Lawn", a, 0, 1, colors.grass, Enum.Material.Grass)
	local paths = Instance.new("Model")
	paths.Name, paths.Parent = "Paths", hub
	local ring = 30
	for slot = 0, map.slots - 1 do
		local yaw = CFrame.new(center) * CFrame.Angles(0, angle(slot), 0)
		part(paths, "RingPath", Vector3.new(2 * ring / math.sqrt(3) + 8 / math.sqrt(3), 0.12, 8), yaw * CFrame.new(0, 0.06, ring), colors.dirt, Enum.Material.Ground)
		part(paths, "Spoke", Vector3.new(width, 0.12, a - ring + 2), yaw * CFrame.new(0, 0.07, (a + ring) / 2), colors.dirt, Enum.Material.Ground)
		-- Lanterns mark each bridge head; lettering beside it names the farm across the water.
		for _, side in {-1, 1} do
			local post = yaw * CFrame.new(side * (width / 2 + 1), 0, a - 1.5)
			part(hub, "LanternPost", Vector3.new(0.8, 4, 0.8), post * CFrame.new(0, 2, 0), colors.trim, Enum.Material.Wood, true)
			part(hub, "LanternCap", Vector3.new(1.3, 0.3, 1.3), post * CFrame.new(0, 5.2, 0), colors.metal, Enum.Material.Metal)
			part(hub, "LanternGlass", Vector3.new(0.9, 1.1, 0.9), post * CFrame.new(0, 4.5, 0), colors.gold, Enum.Material.Neon)
		end
		local signAt = yaw * CFrame.new(width / 2 + 5, 0, a - 6)
		part(hub, "SlotSignPost", Vector3.new(0.4, 3, 0.4), signAt * CFrame.new(0, 1.5, 0), colors.trim, Enum.Material.Wood)
		local board = part(hub, "SlotSign_" .. slot, Vector3.new(9, 2.4, 0.4), CFrame.lookAt((signAt * CFrame.new(0, 3.4, 0)).Position, center + Vector3.new(0, 3.4, 0)), colors.trim, Enum.Material.Wood)
		slotSigns[slot] = lettering(board, "Open plot")
		-- Scenery between the spokes.
		local between = CFrame.new(center) * CFrame.Angles(0, angle(slot) + math.pi / map.slots, 0)
		Brick.tree(hub, (between * CFrame.new(0, 0, a - 11)).Position, 17 + (slot % 3) * 2, 900 + slot)
		local bale = between * CFrame.new(-6, 0.9, a - 20) * CFrame.Angles(0, math.rad(20), 0)
		part(hub, "HayBale", Vector3.new(4, 1.8, 2.7), bale, colors.gold, Enum.Material.Fabric)
		for _, x in {-1.2, 1.2} do part(hub, "BaleBinding", Vector3.new(0.18, 1.85, 2.75), bale * CFrame.new(x, 0, 0), colors.trim) end
		local rock = part(hub, "Rock", Vector3.new(2.6, 1.6, 2.2), between * CFrame.new(7, 0.5, a - 17), colors.stone, Enum.Material.Slate)
		rock.Shape = Enum.PartType.Ball
	end
	-- Centerpiece: a giant striped popcorn bucket on a stone plinth.
	local bucket = Instance.new("Model")
	bucket.Name, bucket.Parent = "PopcornBucket", hub
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	part(bucket, "Plinth", Vector3.new(0.6, 22, 22), CFrame.new(center + Vector3.new(0, 0.3, 0)) * upright, colors.stone, Enum.Material.Slate, true).Shape = Enum.PartType.Cylinder
	part(bucket, "Body", Vector3.new(14, 13, 13), CFrame.new(center + Vector3.new(0, 7.6, 0)) * upright, colors.red, Enum.Material.SmoothPlastic, true).Shape = Enum.PartType.Cylinder
	for i = 0, 7 do
		local out = Vector3.new(math.sin(i * math.pi / 4), 0, math.cos(i * math.pi / 4))
		local at = center + out * 6.55 + Vector3.new(0, 7.6, 0)
		part(bucket, "Stripe", Vector3.new(2.4, 14, 0.25), CFrame.lookAt(at, at + out), colors.white)
	end
	part(bucket, "Rim", Vector3.new(1.2, 14.2, 14.2), CFrame.new(center + Vector3.new(0, 14.6, 0)) * upright, colors.white).Shape = Enum.PartType.Cylinder
	local kernels = Random.new(2611)
	for i = 1, 16 do
		local r, theta = kernels:NextNumber(0, 5), kernels:NextNumber(0, 2 * math.pi)
		local lift = 15.4 + (5 - r) * 0.55 + kernels:NextNumber(0, 0.8)
		local size = kernels:NextNumber(2.6, 4.2)
		local piece = part(bucket, "Popcorn", Vector3.new(size, size * 0.85, size), CFrame.new(center + Vector3.new(math.cos(theta) * r, lift, math.sin(theta) * r)), if i % 3 == 0 then Color3.fromRGB(255, 232, 160) else colors.white)
		piece.Shape = Enum.PartType.Ball
	end
	local welcome = part(hub, "WelcomeSign", Vector3.new(12, 2.6, 0.5), CFrame.new(center + Vector3.new(0, 2.4, -13)), colors.trim, Enum.Material.Wood)
	lettering(welcome, "POPCORN TYCOON\nCross a bridge to your farm")
	for _, x in {-5, 5} do part(hub, "WelcomePost", Vector3.new(0.4, 2.4, 0.4), CFrame.new(center + Vector3.new(x, 1.2, -13)), colors.trim, Enum.Material.Wood) end
end

local function buildBridgesAndIslands(root: Model)
	local map, farm = Config.Map, Config.Farm
	local plotCenter = farm.origin + farm.plotOffset
	local length = map.entranceRadius - map.hubApothem
	for slot = 0, map.slots - 1 do
		local yaw = CFrame.new(map.center) * CFrame.Angles(0, angle(slot), 0)
		local bridge = Instance.new("Model")
		bridge.Name, bridge.Parent = "Bridge_" .. slot, root
		local mid = yaw * CFrame.new(0, 0, map.hubApothem - 1 + length / 2)
		part(bridge, "Deck", Vector3.new(map.bridgeWidth, 0.6, length), mid * CFrame.new(0, -0.22, 0), colors.wood, Enum.Material.WoodPlanks, true)
		for _, side in {-1, 1} do
			local x = side * (map.bridgeWidth / 2 + 0.25)
			part(bridge, "Rail", Vector3.new(0.5, 0.5, length), mid * CFrame.new(x, 1.3, 0), colors.trim, Enum.Material.Wood, true)
			for i = 0, 4 do
				local z = -length / 2 + 1 + i * (length - 2) / 4
				part(bridge, "RailPost", Vector3.new(0.6, 1.8, 0.6), mid * CFrame.new(x, 0.6, z), colors.wood, Enum.Material.Wood, true)
				if i % 2 == 1 then part(bridge, "Pile", Vector3.new(1, 9, 1), mid * CFrame.new(x, -4.8, z), colors.trim, Enum.Material.Wood) end
			end
		end
		-- The island under each farm plot; it stays as open grass while the slot is free.
		local island = Instance.new("Model")
		island.Name, island.Parent = "FarmIsland_" .. slot, root
		local at = MapVisuals.farmFrame(slot) * CFrame.new(plotCenter)
		part(island, "Shore", Vector3.new(farm.plotSize.X + 6, 9, farm.plotSize.Z + 6), at * CFrame.new(0, -5.5, 0), colors.sand, Enum.Material.Sand, true)
		part(island, "Lawn", Vector3.new(farm.plotSize.X + 4, 1, farm.plotSize.Z + 4), at * CFrame.new(0, -0.55, 0), colors.grass, Enum.Material.Grass, true)
	end
end

function MapVisuals.build()
	if workspace:FindFirstChild("PopcornMap") then return end
	local root = Instance.new("Model")
	root.Name = "PopcornMap"
	buildHub(root)
	buildBridgesAndIslands(root)
	-- Studded brick finish; signs, lanterns, rocks, bales and the bucket become solid.
	Brick.finish(root, Config.Map.center.Y)
	root.Parent = workspace
end

-- The saved SpawnLocation sits where the bucket is built, so call this before any yielding
-- startup work: a player who joins meanwhile would otherwise load inside the centerpiece.
function MapVisuals.placeSpawn()
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawn then return end
	spawn.Transparency, spawn.CanCollide = 1, false
	for _, d in spawn:GetChildren() do if d:IsA("Decal") then d.Transparency = 1 end end
	-- In front of the bucket, behind the welcome sign, facing both; the client then turns toward the farm.
	spawn.CFrame = CFrame.new(Config.Map.center + Vector3.new(0, 0.05 - spawn.Size.Y / 2, -22)) * CFrame.Angles(0, math.pi, 0)
end

function MapVisuals.setSlotOwner(slot: number, ownerName: string?)
	local label = slotSigns[slot]
	if label then label.Text = if ownerName then ownerName .. "'s Farm" else "Open plot" end
end

return MapVisuals
