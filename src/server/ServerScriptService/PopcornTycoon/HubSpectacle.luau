--!strict
-- Map spectacle (Nov 3 2026, "make the map 10000x cooler"): the hub's popcorn fountain with a
-- spinning giant bucket, a popcorn geyser, orbiting giant popcorn and chasing marquee bulbs; the
-- floating Blender-rendered logo; popcorn-bucket hot-air balloons, gulls and water glints.
-- Everything here is static server geometry. Motion is purely visual and runs on each client
-- (AmbientController reads the `Ambient`/`Bulb` attributes), so the server does no per-frame work.
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
local HubSpectacle = {}

-- Blender/PIL art uploaded Nov 3 2026; sources in Assets/UI/v2 of the Obsidian vault.
local ART = {
	Logo = "rbxassetid://121151235150792",
	Popcorn = "rbxassetid://112894460849000",
	Sparkle = "rbxassetid://96542276860825",
}
local RED, WHITE = Color3.fromRGB(226, 46, 52), Color3.fromRGB(255, 250, 238)
local GOLD, CREAM = Color3.fromRGB(255, 200, 52), Color3.fromRGB(255, 236, 190)
local STONE, TEAL = Color3.fromRGB(236, 214, 170), Color3.fromRGB(70, 196, 222)
local BROWN = Color3.fromRGB(120, 72, 40)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinders lie along X; this stands them up

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cframe, color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanTouch = true, false
	p.CanCollide, p.CanQuery = collide == true, collide == true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, name: string, diameter: number, height: number, base: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter), base * CFrame.new(0, height / 2, 0) * UPRIGHT, color, material, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.one * diameter, CFrame.new(at), color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Moving things never collide (they only move on clients) and stay out of the brick collision pass.
-- They also stream as one unit: with StreamingEnabled a Default model reaches the client before
-- its parts, which the client animator can't place. Sky movers that roam far from where the
-- server built them (balloons, gulls) are Persistent so they never stream out.
local function walkThrough(model: Model, mode: Enum.ModelStreamingMode?)
	model.ModelStreamingMode = mode or Enum.ModelStreamingMode.Atomic
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then d.CanCollide, d.CanQuery = false, false d:SetAttribute("WalkThrough", true) end
	end
end

-- A striped popcorn bucket heaped with popcorn, standing on `base` (bottom centre).
local function bucket(parent: Instance, name: string, base: CFrame, radius: number, height: number, stripes: number, heap: number, seed: number, collide: boolean): Model
	local m = Instance.new("Model")
	m.Name = name
	cylinder(m, "Body", radius * 2, height, base, RED, nil, collide)
	local width = math.pi * radius / stripes
	for i = 0, stripes - 1 do
		local a = i * 2 * math.pi / stripes
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = (base * CFrame.new(out * (radius + 0.05) + Vector3.new(0, height / 2, 0))).Position
		part(m, "Stripe", Vector3.new(width, height, 0.2), CFrame.lookAt(at, at + base:VectorToWorldSpace(out)), WHITE)
	end
	cylinder(m, "Rim", radius * 2 + 0.6, math.max(0.6, height * 0.07), base * CFrame.new(0, height - height * 0.035, 0), WHITE)
	local rng = Random.new(seed)
	for i = 1, heap do
		local r, theta = rng:NextNumber(0, radius * 0.85), rng:NextNumber(0, 2 * math.pi)
		local size = rng:NextNumber(0.32, 0.52) * radius
		local lift = height + (radius - r) * 0.45 + rng:NextNumber(0, radius * 0.12)
		local at = (base * CFrame.new(math.cos(theta) * r, lift, math.sin(theta) * r)).Position
		ball(m, "Popcorn", size, at, if i % 4 == 0 then CREAM else WHITE)
	end
	m.WorldPivot = base
	m.Parent = parent
	return m
end

-- A chunky popcorn piece: a few overlapping puffs, pivot at its centre.
local function popcornPiece(parent: Instance, at: Vector3, size: number, seed: number): Model
	local rng = Random.new(seed)
	local m = Instance.new("Model")
	m.Name = "GiantPopcorn"
	ball(m, "Puff", size, at, WHITE)
	for i = 1, 4 do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 1), rng:NextNumber(-1, 1)).Unit
		ball(m, "Puff", size * rng:NextNumber(0.55, 0.75), at + dir * size * 0.4, if i == 2 then CREAM else WHITE)
	end
	ball(m, "Hull", size * 0.35, at + Vector3.new(0, -size * 0.42, 0), Color3.fromRGB(214, 128, 30))
	m.WorldPivot = CFrame.new(at)
	m.Parent = parent
	return m
end

local function emitter(at: Vector3, parent: Instance, name: string): (Part, ParticleEmitter)
	local holder = part(parent, name, Vector3.new(1, 1, 1), CFrame.new(at), WHITE)
	holder.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Parent = holder
	return holder, e
end

-- The hub centrepiece: fountain basin, spinning bucket, geyser, orbiting popcorn and bulbs.
local function fountain(root: Model, center: Vector3)
	local f = Instance.new("Model")
	f.Name, f.Parent = "PopcornFountain", root
	local ground = CFrame.new(center)
	cylinder(f, "Basin", 25, 2.2, ground, STONE, nil, true)
	cylinder(f, "BasinCap", 25.8, 0.5, ground * CFrame.new(0, 2.2, 0), GOLD, nil, true)
	local water = cylinder(f, "Water", 22.4, 0.3, ground * CFrame.new(0, 1.9, 0), TEAL, Enum.Material.Glass, true)
	water.Transparency, water.Reflectance = 0.2, 0.15
	cylinder(f, "Pedestal", 10, 4.2, ground * CFrame.new(0, 2, 0), GOLD, nil, true)
	cylinder(f, "PedestalBand", 10.6, 0.8, ground * CFrame.new(0, 5.2, 0), RED, nil, true)

	local spin = bucket(f, "GiantBucket", ground * CFrame.new(0, 6.2, 0), 7.2, 16, 12, 22, 2611, true)
	spin:SetAttribute("Ambient", "Spin")
	spin:SetAttribute("SpinSpeed", 0.25)
	spin.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Marquee bulbs around the basin cap; clients chase them.
	local bulbs = Instance.new("Folder")
	bulbs.Name, bulbs.Parent = "Bulbs", f
	local count = 32
	for i = 0, count - 1 do
		local a = i * 2 * math.pi / count
		local b = ball(bulbs, "Bulb", 0.9, center + Vector3.new(math.cos(a) * 12.4, 3.05, math.sin(a) * 12.4), GOLD, Enum.Material.Neon)
		b:SetAttribute("Bulb", i)
	end

	-- Popcorn geyser: pieces shoot out of the heap and rain back into the basin.
	local top = center + Vector3.new(0, 6.2 + 16 + 4, 0)
	local _, geyser = emitter(top, f, "PopcornGeyser")
	geyser.Texture = ART.Popcorn
	geyser.Rate, geyser.Lifetime = 9, NumberRange.new(1.9, 2.4)
	geyser.Speed, geyser.SpreadAngle = NumberRange.new(20, 27), Vector2.new(16, 16)
	geyser.Acceleration, geyser.Drag = Vector3.new(0, -34, 0), 0.4
	geyser.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.15, 2), NumberSequenceKeypoint.new(1, 1.6) })
	geyser.Rotation, geyser.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-220, 220)
	geyser.LightInfluence, geyser.Brightness = 0.6, 1.2
	local _, glitter = emitter(top - Vector3.new(0, 6, 0), f, "BucketSparkles")
	glitter.Texture, glitter.Rate = ART.Sparkle, 6
	glitter.Lifetime, glitter.Speed = NumberRange.new(0.6, 1.1), NumberRange.new(0)
	glitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 1.6), NumberSequenceKeypoint.new(1, 0) })
	glitter.LightEmission, glitter.Color = 1, ColorSequence.new(Color3.fromRGB(255, 236, 140))
	glitter.Shape, glitter.ShapeStyle = Enum.ParticleEmitterShape.Cylinder, Enum.ParticleEmitterShapeStyle.Surface
	;(glitter.Parent :: Part).Size = Vector3.new(16, 18, 16)

	-- Six giant popcorn pieces circling the bucket.
	for i = 0, 5 do
		local piece = popcornPiece(f, center + Vector3.new(0, 25, 0), 3.4, 77 + i)
		piece:SetAttribute("Ambient", "Orbit")
		piece:SetAttribute("OrbitCenter", center + Vector3.new(0, 24, 0))
		piece:SetAttribute("OrbitRadius", 13)
		piece:SetAttribute("OrbitSpeed", 0.45)
		piece:SetAttribute("OrbitPhase", i * math.pi / 3)
		piece:SetAttribute("Bob", 1.6)
		piece:SetAttribute("Tumble", 1.2)
		walkThrough(piece)
	end
end

-- The Blender logo floating high above the hub, readable from every farm.
local function floatingLogo(root: Model, center: Vector3)
	local anchor = part(root, "LogoAnchor", Vector3.one, CFrame.new(center + Vector3.new(0, 56, 0)), WHITE)
	anchor.Transparency = 1
	local board = Instance.new("BillboardGui")
	board.Name, board.Size = "Logo", UDim2.fromScale(62, 28)
	board.LightInfluence, board.MaxDistance, board.Brightness = 0, 2000, 1.15
	board:SetAttribute("Ambient", "Hover")
	local image = Instance.new("ImageLabel")
	image.Name, image.Image, image.BackgroundTransparency = "Art", ART.Logo, 1
	image.Size, image.ScaleType = UDim2.fromScale(1, 1), Enum.ScaleType.Fit
	image.Parent = board
	board.Parent = anchor
end

-- Popcorn-bucket hot-air balloons drifting in wide circles around the islands.
local function balloons(root: Model, center: Vector3)
	local colours = { RED, Color3.fromRGB(42, 132, 236), Color3.fromRGB(150, 84, 238) }
	for i = 1, 3 do
		local at = center + Vector3.new(0, 70, 0)
		local m = Instance.new("Model")
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		m.Name, m.Parent = "Balloon", root
		local envelope = bucket(m, "Envelope", CFrame.new(at), 6.5, 13, 10, 14, 300 + i, false)
		;(envelope:FindFirstChild("Body") :: Part).Color = colours[i]
		cylinder(m, "Skirt", 6, 2.4, CFrame.new(at - Vector3.new(0, 2.4, 0)), colours[i])
		local basket = at - Vector3.new(0, 9, 0)
		part(m, "Basket", Vector3.new(4, 3, 4), CFrame.new(basket), BROWN, Enum.Material.WoodPlanks)
		part(m, "BasketTrim", Vector3.new(4.4, 0.5, 4.4), CFrame.new(basket + Vector3.new(0, 1.6, 0)), GOLD)
		for _, corner in { Vector3.new(1.7, 0, 1.7), Vector3.new(-1.7, 0, 1.7), Vector3.new(1.7, 0, -1.7), Vector3.new(-1.7, 0, -1.7) } do
			local low, high = basket + corner + Vector3.new(0, 1.5, 0), at + corner * 1.3 - Vector3.new(0, 2.4, 0)
			part(m, "Rope", Vector3.new(0.2, 0.2, (high - low).Magnitude), CFrame.lookAt((low + high) / 2, high), Color3.fromRGB(70, 50, 34))
		end
		local flame = ball(m, "Flame", 1.4, at - Vector3.new(0, 3.2, 0), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
		flame.Transparency = 0.15
		m.WorldPivot = CFrame.new(at)
		m:SetAttribute("Ambient", "Orbit")
		m:SetAttribute("OrbitCenter", center + Vector3.new(0, 62 + i * 9, 0))
		m:SetAttribute("OrbitRadius", 150 + i * 32)
		m:SetAttribute("OrbitSpeed", (if i == 2 then -1 else 1) * (0.035 - i * 0.004))
		m:SetAttribute("OrbitPhase", i * 2.1)
		m:SetAttribute("Bob", 2.5)
		m:SetAttribute("SpinSpeed", 0.12)
		walkThrough(m, Enum.ModelStreamingMode.Persistent)
	end
end

-- A small flock of gulls gliding in circles over the water.
local function gulls(root: Model, center: Vector3)
	for i = 1, 7 do
		local at = center + Vector3.new(0, 40, 0)
		local m = Instance.new("Model")
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		m.Name, m.Parent = "Gull", root
		part(m, "Body", Vector3.new(0.7, 0.6, 2.2), CFrame.new(at), WHITE)
		part(m, "Beak", Vector3.new(0.25, 0.25, 0.5), CFrame.new(at + Vector3.new(0, 0, -1.3)), GOLD)
		for _, side in { -1, 1 } do
			local wing = part(m, "Wing", Vector3.new(2.6, 0.15, 1.1), CFrame.new(at + Vector3.new(side * 1.5, 0.35, 0.1)) * CFrame.Angles(0, 0, side * 0.35), WHITE)
			wing:SetAttribute("WingSide", side)
			part(m, "WingTip", Vector3.new(0.8, 0.16, 0.9), CFrame.new(at + Vector3.new(side * 2.85, 0.82, 0.1)) * CFrame.Angles(0, 0, side * 0.35), Color3.fromRGB(60, 60, 66))
		end
		m.WorldPivot = CFrame.new(at)
		m:SetAttribute("Ambient", "Fly")
		m:SetAttribute("OrbitCenter", center + Vector3.new((i % 3 - 1) * 60, 26 + (i % 4) * 7, (i % 2) * 50 - 25))
		m:SetAttribute("OrbitRadius", 45 + (i * 23) % 70)
		m:SetAttribute("OrbitSpeed", (if i % 2 == 0 then -1 else 1) * (0.22 + (i % 3) * 0.05))
		m:SetAttribute("OrbitPhase", i * 0.9)
		m:SetAttribute("Bob", 1.5)
		walkThrough(m, Enum.ModelStreamingMode.Persistent)
	end
end

-- Sunlight glints twinkling on the bay.
local function glints(root: Model, center: Vector3)
	local map = Config.Map
	local holder, e = emitter(center + Vector3.new(0, map.waterLevel + 0.4, 0), root, "WaterGlints")
	holder.Size = Vector3.new(420, 0.2, 420)
	e.Texture, e.Rate = ART.Sparkle, 40
	e.Lifetime, e.Speed = NumberRange.new(0.5, 1), NumberRange.new(0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.8), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission, e.Orientation = 1, Enum.ParticleOrientation.FacingCamera
	e.Shape, e.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
end

-- Builds the spectacle under the map root. Call before BrickStyle.finish so the fountain gets
-- the brick finish; the moving pieces are marked WalkThrough and stay passable.
function HubSpectacle.build(root: Model)
	local center = Config.Map.center
	local show = Instance.new("Model")
	show.Name, show.Parent = "Spectacle", root
	fountain(show, center)
	floatingLogo(show, center)
	balloons(show, center)
	gulls(show, center)
	glints(show, center)
end

HubSpectacle.Art = ART
return HubSpectacle
