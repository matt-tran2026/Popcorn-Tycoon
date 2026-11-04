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

-- Fredoka One lettering with a dark outline, matching the HUD.
local function lettering(board: Part, text: string, face: Enum.NormalId?, color: Color3?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.PixelsPerStud = "Lettering", face or Enum.NormalId.Front, 40
	gui.SizingMode, gui.LightInfluence = Enum.SurfaceGuiSizingMode.PixelsPerStud, 0.3
	local label = Instance.new("TextLabel")
	label.Name, label.Size = "Text", UDim2.fromScale(0.92, 0.8)
	label.Position, label.BackgroundTransparency = UDim2.fromScale(0.04, 0.1), 1
	label.Font, label.TextScaled, label.TextWrapped = Enum.Font.FredokaOne, true, true
	label.TextColor3, label.Text = color or Color3.fromRGB(255, 226, 74), text
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness, stroke.Parent = Color3.fromRGB(40, 16, 8), 4, label
	label.Parent, gui.Parent = gui, board
	return label
end

-- A theatre-marquee arch over a bridge head: candy-striped posts, a red sign with a gold frame
-- and chasing bulbs. The hub side names the farm, the bridge side welcomes players to the hub.
local function arch(parent: Instance, yaw: CFrame, width: number, apothem: number, slot: number): TextLabel
	local m = Instance.new("Model")
	m.Name, m.Parent = "Arch_" .. slot, parent
	local at = yaw * CFrame.new(0, 0, apothem - 1.2)
	local span = width / 2 + 1.7
	for _, side in { -1, 1 } do
		for i = 0, 4 do
			part(m, "Post", Vector3.new(1.8, 2.4, 1.8), at * CFrame.new(side * span, 1.2 + i * 2.4, 0), if i % 2 == 0 then colors.red else colors.white, Enum.Material.SmoothPlastic, true)
		end
		local cap = part(m, "PostCap", Vector3.new(2.3, 2.3, 2.3), at * CFrame.new(side * span, 16.1, 0), colors.gold, Enum.Material.Neon)
		cap.Shape = Enum.PartType.Ball
	end
	local center = (at * CFrame.new(0, 13.4, 0)).Position
	local facing = CFrame.lookAt(center, Vector3.new(Config.Map.center.X, center.Y, Config.Map.center.Z))
	part(m, "Frame", Vector3.new(span * 2 + 2.2, 4.6, 1.1), facing, colors.gold, Enum.Material.SmoothPlastic, true)
	local board = part(m, "Board", Vector3.new(span * 2 + 1, 3.6, 1.4), facing, colors.red, Enum.Material.SmoothPlastic, true)
	-- The bridge-side greeting gets its own name so "Lettering" stays the owner's sign.
	;(lettering(board, "POPCORN HUB", Enum.NormalId.Back, Color3.fromRGB(255, 250, 238)).Parent :: SurfaceGui).Name = "HubLettering"
	local label = lettering(board, "Open plot", Enum.NormalId.Front)
	local bulbs = Instance.new("Folder")
	bulbs.Name, bulbs.Parent = "Bulbs", m
	local count = 11
	for i = 0, count - 1 do
		local x = -span - 0.6 + i * (span * 2 + 1.2) / (count - 1)
		local bulb = part(bulbs, "Bulb", Vector3.new(0.8, 0.8, 0.8), facing * CFrame.new(x, 2.75, 0), colors.gold, Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
		bulb:SetAttribute("Bulb", i)
	end
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
		-- A marquee arch over each bridge head names the farm across the water.
		slotSigns[slot] = arch(hub, yaw, width, a, slot)
		-- Scenery between the spokes.
		local between = CFrame.new(center) * CFrame.Angles(0, angle(slot) + math.pi / map.slots, 0)
		Brick.tree(hub, (between * CFrame.new(0, 0, a - 11)).Position, 17 + (slot % 3) * 2, 900 + slot)
		local bale = between * CFrame.new(-6, 0.9, a - 20) * CFrame.Angles(0, math.rad(20), 0)
		part(hub, "HayBale", Vector3.new(4, 1.8, 2.7), bale, colors.gold, Enum.Material.Fabric)
		for _, x in {-1.2, 1.2} do part(hub, "BaleBinding", Vector3.new(0.18, 1.85, 2.75), bale * CFrame.new(x, 0, 0), colors.trim) end
		local rock = part(hub, "Rock", Vector3.new(2.6, 1.6, 2.2), between * CFrame.new(7, 0.5, a - 17), colors.stone, Enum.Material.Slate)
		rock.Shape = Enum.PartType.Ball
	end
	-- The centrepiece (popcorn fountain, spinning giant bucket, floating logo) is HubSpectacle.
	local welcome = part(hub, "WelcomeSign", Vector3.new(12, 2.6, 0.5), CFrame.new(center + Vector3.new(0, 2.4, -17)), colors.trim, Enum.Material.Wood)
	lettering(welcome, "Cross a bridge to your farm!")
	for _, x in {-5, 5} do part(hub, "WelcomePost", Vector3.new(0.4, 2.4, 0.4), CFrame.new(center + Vector3.new(x, 1.2, -17)), colors.trim, Enum.Material.Wood) end
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
	require(script.Parent.HubSpectacle).build(root)
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
