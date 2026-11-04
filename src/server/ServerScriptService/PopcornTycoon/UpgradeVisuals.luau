--!strict
-- How farm upgrades look. Pure presentation: nothing here reads or changes rewards.
-- * Backpack: one Blender pack per tier (ServerStorage.PopcornTemplates.Backpacks, MeshParts
--   Backpack_0..Backpack_4) welded to the character's back. Massless and non-colliding so it
--   never changes movement or animation. Without the template a small brick pack stands in.
-- * Soil: each upgraded plot's soil and tilled rows get richer colours, and from level 2 a few
--   Blender decor meshes (PopcornTemplates.SoilDecor: Pebbles, Sprouts, Blossoms) sit inside
--   the bed edging. At most 10 decor pieces per plot; no scripts, lights or particles.
-- * Corn Yield: ripe stalks show one cob per corn in a cycle (Corn_Cob1..Corn_Cob5 in the
--   CornStalk template) and grow a little taller at high levels. Unripe stalks show no cobs.
-- * Stalk Storage: a stalk holding its maximum cycles warms its cobs gold (FULL_TINT); the
--   client's pick badge also marks it FULL. Nothing floats over idle stalks.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local ServerStorage = game:GetService("ServerStorage")
local Brick = require(script.Parent.BrickStyle)
local UpgradeVisuals = {}

UpgradeVisuals.MAX_COBS = 5
UpgradeVisuals.FULL_TINT = Color3.fromRGB(255, 226, 140)

-- Soil and tilled-row colours by Soil level: basic brown, darker and richer each level.
local SOIL = {
	{ soil = Color3.fromRGB(100, 66, 41), rows = Color3.fromRGB(123, 78, 43) },
	{ soil = Color3.fromRGB(88, 56, 34), rows = Color3.fromRGB(106, 66, 36) },
	{ soil = Color3.fromRGB(76, 48, 30), rows = Color3.fromRGB(92, 56, 31) },
	{ soil = Color3.fromRGB(66, 42, 28), rows = Color3.fromRGB(80, 49, 28) },
	{ soil = Color3.fromRGB(58, 37, 25), rows = Color3.fromRGB(70, 42, 25) },
}
-- Ripe mesh height multiplier by Corn Yield level (a fuller, taller silhouette at the top).
local STALK_SCALE = { 1, 1, 1.04, 1.1, 1.18 }
-- Back-pack placeholder sizes (studs) by Backpack level when the Blender packs are missing.
local PACK_SIZE = { Vector3.new(1, 1, 0.6), Vector3.new(1.4, 1.4, 0.8), Vector3.new(1.7, 1.9, 0.9), Vector3.new(1.9, 2.2, 1), Vector3.new(2.1, 2.5, 1.1) }
local PACK_COLOR = { Color3.fromRGB(150, 96, 52), Color3.fromRGB(214, 168, 92), Color3.fromRGB(74, 132, 66), Color3.fromRGB(196, 84, 52), Color3.fromRGB(246, 193, 31) }

local function template(name: string): Instance?
	local folder = ServerStorage:FindFirstChild("PopcornTemplates")
	return if folder then folder:FindFirstChild(name) else nil
end

local function quiet(part: BasePart)
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
	part.CastShadow = false
end

function UpgradeVisuals.stalkScale(yieldLevel: number): number
	return STALK_SCALE[math.clamp(yieldLevel, 0, #STALK_SCALE - 1) + 1]
end

-- The cob MeshParts of a corn mesh by number (Corn_Cob1..), plus any unnumbered "corn" parts
-- (an older three-cob template), which then show whenever the stalk is ripe.
export type CobSet = { numbered: { [number]: BasePart }, other: { BasePart } }
function UpgradeVisuals.cobs(mesh: Model): CobSet
	local set: CobSet = { numbered = {}, other = {} }
	for _, object in mesh:GetDescendants() do
		if object:IsA("BasePart") and object.Name:lower():find("corn") then
			local n = tonumber(string.match(object.Name, "^Corn_Cob(%d+)$"))
			if n then set.numbered[n] = object else table.insert(set.other, object) end
		end
	end
	return set
end

-- Shows `count` cobs (0 = none) and tints them gold when the stalk is full.
function UpgradeVisuals.showCobs(set: CobSet, count: number, full: boolean)
	local tint = if full then UpgradeVisuals.FULL_TINT else Color3.new(1, 1, 1)
	for n, part in set.numbered do
		part.Transparency = if n <= count then 0 else 1
		part.Color = tint
	end
	for _, part in set.other do
		part.Transparency = if count > 0 then 0 else 1
		part.Color = tint
	end
end

-- Canonical (unplaced) spots for soil decor inside a plot bed, around its edging.
local function decorSpots(center: Vector3): { { at: Vector3, minLevel: number, kind: string } }
	local s = Config.Plot
	local halfWidth = (s.columns - 1) / 2 * s.spacing + 3
	local halfDepth = (Config.layoutRows() - 1) / 2 * s.spacing + 3
	local spots = {}
	for _, x in { -halfWidth, halfWidth } do
		for _, z in { -halfDepth, halfDepth } do
			table.insert(spots, { at = center + Vector3.new(x, 0.35, z), minLevel = 2, kind = "Pebbles" })
		end
		for _, z in { -halfDepth / 2, halfDepth / 2 } do
			table.insert(spots, { at = center + Vector3.new(x, 0.35, z), minLevel = 3, kind = "Sprouts" })
		end
		table.insert(spots, { at = center + Vector3.new(x, 0.35, 0), minLevel = 4, kind = "Blossoms" })
	end
	return spots
end

-- Restyles one owned plot for its Soil level. `farm` is the placed farm model, `placement`
-- its slot frame, `center` the plot's canonical centre. Rebuilt from scratch each call.
function UpgradeVisuals.applySoil(farm: Model, plot: number, level: number, placement: CFrame, center: Vector3)
	local look = SOIL[math.clamp(level, 0, #SOIL - 1) + 1]
	local soil = farm:FindFirstChild(if plot == 1 then "Soil" else "Soil_" .. tostring(plot))
	if soil and soil:IsA("BasePart") then soil.Color = look.soil end
	local bed = farm:FindFirstChild("PlotBed_" .. tostring(plot))
	if bed then
		for _, part in bed:GetChildren() do
			if part:IsA("BasePart") and string.sub(part.Name, 1, 14) == "CultivatedRow_" then
				part.Color = look.rows
				part.Material = if level >= 3 then Enum.Material.Mud else Enum.Material.Ground
			end
		end
	end
	local old = farm:FindFirstChild("SoilLook_" .. tostring(plot))
	if old then old:Destroy() end
	if level < 2 then return end
	local decor = template("SoilDecor")
	local group = Instance.new("Model")
	group.Name = "SoilLook_" .. tostring(plot)
	for i, spot in decorSpots(center) do
		if level >= spot.minLevel then
			local source = if decor then decor:FindFirstChild(spot.kind) else nil
			local piece: BasePart
			if source and source:IsA("BasePart") then
				piece = source:Clone()
				piece.Color = Color3.new(1, 1, 1) -- Vertex colours carry the look.
			else
				-- Placeholder: a small studded clump in the decor's colour.
				local p = Instance.new("Part")
				p.Size = Vector3.new(1.2, 0.4, 1.2)
				p.Color = if spot.kind == "Pebbles" then Color3.fromRGB(150, 146, 140) elseif spot.kind == "Sprouts" then Color3.fromRGB(86, 186, 64) else Color3.fromRGB(246, 193, 31)
				p.Material = Enum.Material.Plastic
				Brick.studs(p)
				piece = p
			end
			piece.Name = spot.kind
			piece.Anchored = true
			quiet(piece)
			piece:SetAttribute("WalkThrough", true)
			-- Bottom on the soil, a fixed turn per spot so neighbouring clumps differ.
			piece.CFrame = placement * CFrame.new(spot.at + Vector3.new(0, piece.Size.Y / 2 - 0.15, 0)) * CFrame.Angles(0, i * 1.7, 0)
			piece.Parent = group
		end
	end
	group.Parent = farm
end

-- Puts the pack for `level` on a character's back, replacing any older one.
function UpgradeVisuals.backpack(character: Model?, level: number)
	if not character then return end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then return end
	local old = character:FindFirstChild("PopcornBackpack")
	if old then old:Destroy() end
	local tier = math.clamp(level, 0, #PACK_SIZE - 1)
	local packs = template("Backpacks")
	local source = if packs then packs:FindFirstChild("Backpack_" .. tostring(tier)) else nil
	local pack: BasePart
	if source and source:IsA("BasePart") then
		pack = source:Clone()
		pack.Color = Color3.new(1, 1, 1)
	else
		local p = Instance.new("Part")
		p.Size, p.Color, p.Material = PACK_SIZE[tier + 1], PACK_COLOR[tier + 1], Enum.Material.Plastic
		Brick.studs(p)
		pack = p
	end
	pack.Name = "PopcornBackpack"
	pack.Anchored, pack.Massless = false, true
	quiet(pack)
	pack:SetAttribute("Level", tier)
	-- Hung on the back (torso +Z), top just under the shoulders; the weld follows animations.
	local weld = Instance.new("Weld")
	weld.Name = "BackpackWeld"
	weld.Part0, weld.Part1 = torso, pack
	weld.C0 = CFrame.new(0, torso.Size.Y / 2 - pack.Size.Y / 2 + 0.1, torso.Size.Z / 2 + pack.Size.Z / 2 - 0.05)
	weld.Parent = pack
	pack.CFrame = torso.CFrame * weld.C0
	pack.Parent = character
end

return UpgradeVisuals
