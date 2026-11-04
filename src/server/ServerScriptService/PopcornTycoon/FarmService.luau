--!strict
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local Types = require(Shared.Types)
local Money = require(Shared.Money)
local Pricing = require(Shared.Pricing)
local Visuals = require(script.Parent.FarmVisuals)
local Map = require(script.Parent.MapVisuals)
local Templates = require(script.Parent.VisualTemplates)
local Brick = require(script.Parent.BrickStyle)
local State = require(script.Parent.PlayerStateService)

type StalkView = { part: Part, ear: Part, prompt: ProximityPrompt, leaves: { Part }, mesh: Model?, fieldId: string }
export type MicrowaveView = { door: Part, prompt: ProximityPrompt, popping: ParticleEmitter, popcorn: Folder }
-- Farms are built around the canonical origin (Config.Farm), then `placement` turns them onto their slot.
-- fields is the owner's profile.fields table (shared, not copied). Purchase pads: one row pad per
-- owned plot that still has bed room, and one plot pad on the next locked cell.
type FarmView = {
	model: Model, fields: { [string]: Types.Field }, slot: number, placement: CFrame, stalks: { [string]: StalkView },
	microwave: MicrowaveView, sellStand: Part, locked: { [number]: Model },
	rowPads: { [string]: Part }, plotPad: Part?,
}
-- What a pad step-on asks for: kind "Row" (with the plot's fieldId) or "Plot".
export type PadHandler = (player: Player, kind: string, fieldId: string?, pad: Part) -> ()
local farms: { [number]: FarmView } = {}
local occupied: { [number]: boolean } = {}
local root: Folder? = nil
-- Unclaimed slots show a fresh starter farm as scenery so the map always looks lived in.
local openPlots: { [number]: Model } = {}
local openRoot: Folder? = nil
local padHandler: PadHandler? = nil
-- The pad each player last stepped on; it re-arms once they step off (see FarmService.update).
local padVisits: { [number]: { pad: Part, at: number, left: boolean } } = {}
local FarmService = {}

local function part(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.Position, p.Color = name, size, position, color
	p.Anchored, p.CanCollide = true, false
	p.CanTouch = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function prompt(name: string, action: string, object: string, range: number, parent: Instance): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name, p.ActionText, p.ObjectText = name, action, object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration, p.MaxActivationDistance = 0, range
	p.RequiresLineOfSight, p.ClickablePrompt = false, true
	p.Parent = parent
	return p
end

-- Canonical center of a plot cell at ground height.
local function cellCenter(plot: number): Vector3
	return Config.Farm.origin + Config.cellOffset(plot)
end

-- Rows are laid out for the full purchasable bed so planting a row never moves existing stalks.
local function stalkPosition(plot: number, row: number, col: number): Vector3
	local s = Config.Plot
	local rows = Config.layoutRows()
	return cellCenter(plot) + Vector3.new((col - (s.columns + 1) / 2) * s.spacing, 2.5, (row - (rows + 1) / 2) * s.spacing)
end

local function buildStalk(farm: Model, field: Types.Field, row: number, col: number): (string, StalkView)
	local origin = Config.Farm.origin
	local id = State.stalkId(field.plot, row, col)
	local pos = stalkPosition(field.plot, row, col)
	local stem = part("Stalk_" .. id, Vector3.new(0.6, 4.5, 0.6), pos, Color3.fromRGB(68, 148, 56), farm)
	stem:SetAttribute("StalkId", id)
	stem:SetAttribute("FieldId", field.id)
	local ear = part("Ear_" .. id, Vector3.new(0.9, 1.5, 0.9), pos + Vector3.new(0.4, 0.6, 0), Color3.fromRGB(255, 211, 63), farm)
	ear.Shape = Enum.PartType.Ball
	local leaves: { Part } = {}
	for i = 1, 4 do
		local leaf = part("Leaf_" .. i, Vector3.new(0.9, 0.18, 2.2), pos, Color3.fromRGB(86, 169, 49), stem)
		leaf.CanQuery = false
		table.insert(leaves, leaf)
	end
	local harvest = prompt("Harvest", "Pick corn", "Normal Corn", Config.Manual.range, stem)
	local mesh = Templates.clone("Corn", farm, Vector3.new(pos.X, origin.Y + 0.25, pos.Z), 4.5)
	if mesh then stem.Transparency = 1 for _, leaf in leaves do leaf:Destroy() end leaves = {} end
	-- Lets clients find the visible stalk for a harvest target (HarvestHighlight).
	if mesh then mesh:SetAttribute("StalkId", id) end
	return id, { part = stem, ear = ear, prompt = harvest, leaves = leaves, mesh = mesh, fieldId = field.id }
end

-- Soil, edging and tilled strips of an owned plot. Plot 1's soil keeps the name "Soil"
-- (the client turns the first camera toward it).
local function buildPlotGround(model: Model, plot: number)
	local s = Config.Plot
	local center = cellCenter(plot)
	local soil = part(if plot == 1 then "Soil" else "Soil_" .. tostring(plot), Vector3.new(s.columns * s.spacing + 2, 0.5, Config.layoutRows() * s.spacing + 3), center, Color3.fromRGB(100, 66, 41), model)
	Brick.studs(soil)
	local bed = Instance.new("Model")
	bed.Name = "PlotBed_" .. tostring(plot)
	Visuals.buildPlotBed(bed, center)
	Brick.finish(bed, center.Y)
	bed.Parent = model
end

local function buildLocked(model: Model, plot: number): Model
	local cell = Instance.new("Model")
	cell.Name = "LockedCell_" .. tostring(plot)
	Visuals.buildLockedCell(cell, cellCenter(plot))
	Brick.finish(cell, Config.Farm.origin.Y)
	cell.Parent = model
	return cell
end

-- Builds into a scratch model in canonical coordinates, turns it onto the farm's slot, then
-- hands the pieces to the farm model.
local function buildPlaced(farm: FarmView, build: (Model) -> ())
	local batch = Instance.new("Model")
	build(batch)
	batch.WorldPivot = CFrame.identity
	batch:PivotTo(farm.placement)
	for _, child in batch:GetChildren() do child.Parent = farm.model end
	batch:Destroy()
end

-- Purchase pads: a dark slab with a neon top, walk-through, and a floating price tag.
-- Prices are attributes so the client can tint the pad by affordability (PadController).
local function buildPad(parent: Instance, name: string, size: Vector2, at: Vector3, kind: string, title: string, fieldId: string?): Part
	local pad = part(name, Vector3.new(size.X, 0.4, size.Y), at + Vector3.new(0, 0.3, 0), Color3.fromRGB(46, 52, 46), parent)
	pad.Material, pad.CanTouch, pad.CanQuery = Enum.Material.SmoothPlastic, true, false
	pad:SetAttribute("WalkThrough", true)
	local glow = part("Glow", Vector3.new(size.X - 1, 0.1, size.Y - 1), at + Vector3.new(0, 0.55, 0), Color3.fromRGB(80, 220, 100), pad)
	glow.Material, glow.CanQuery = Enum.Material.Neon, false
	glow.Transparency = 0.15
	pad:SetAttribute("PadKind", kind)
	if fieldId then pad:SetAttribute("FieldId", fieldId) end
	local tag = Instance.new("BillboardGui")
	tag.Name, tag.Size, tag.StudsOffsetWorldSpace = "PriceTag", UDim2.fromOffset(190, 74), Vector3.new(0, 4, 0)
	tag.MaxDistance, tag.LightInfluence, tag.ResetOnSpawn = 90, 0, false
	local function label(name: string, text: string, y: number, height: number, color: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.Name, t.Text, t.TextColor3 = name, text, color
		t.Size, t.Position = UDim2.new(1, 0, height, 0), UDim2.fromScale(0, y)
		t.BackgroundTransparency, t.Font, t.TextScaled = 1, Enum.Font.FredokaOne, true
		local stroke = Instance.new("UIStroke")
		stroke.Color, stroke.Thickness, stroke.Parent = Color3.fromRGB(40, 16, 8), 3, t
		t.Parent = tag
		return t
	end
	label("Title", title, 0, 0.45, Color3.fromRGB(255, 250, 238))
	label("Price", "", 0.45, 0.55, Color3.fromRGB(255, 226, 74))
	tag.Parent = pad
	return pad
end

local function setPadPrice(pad: Part, currency: Types.Currency, price: number)
	pad:SetAttribute("Price", price)
	pad:SetAttribute("Currency", currency)
	local tag = pad:FindFirstChild("PriceTag")
	local label = if tag then tag:FindFirstChild("Price") :: TextLabel? else nil
	if label then label.Text = Money.price(currency, price) end
end

local function connectPad(userId: number, pad: Part)
	pad.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		if character and character:IsA("Accessory") then character = character.Parent end
		local player = if character then Players:GetPlayerFromCharacter(character) else nil
		if not player or player.UserId ~= userId or not padHandler then return end
		local visit = padVisits[userId]
		local now = os.clock()
		if visit and visit.pad == pad and (not visit.left or now - visit.at < Config.Pads.rearmSeconds) then return end
		padVisits[userId] = { pad = pad, at = now, left = false }
		local kind = pad:GetAttribute("PadKind")
		local fieldId = pad:GetAttribute("FieldId")
		if typeof(kind) ~= "string" then return end
		padHandler(player, kind, if typeof(fieldId) == "string" then fieldId else nil, pad)
	end)
end

-- Is `position` over the pad (within Config.Pads.reach of its edge and a little above it)?
function FarmService.onPad(pad: Part, position: Vector3, slack: number?): boolean
	local reach = Config.Pads.reach + (slack or 0)
	local p = pad.CFrame:PointToObjectSpace(position)
	return math.abs(p.X) <= pad.Size.X / 2 + reach and math.abs(p.Z) <= pad.Size.Z / 2 + reach and p.Y > -2 and p.Y < 9
end

-- Puts every pad where the owner's land currently allows and refreshes their prices.
-- Row pads sit on the next empty row of their plot; the plot pad on the next locked cell.
local function refreshPads(userId: number, farm: FarmView)
	local rows = Config.layoutRows()
	local rowPrice, plotPrice = Pricing.rowPrice(farm.fields), Pricing.plotPrice(farm.fields)
	local rowUpgrade, plotUpgrade = Config.Upgrades.ExtraRow, Config.Upgrades.ExtraPlot
	for fieldId, pad in farm.rowPads do
		local field = farm.fields[fieldId]
		if not field or field.rows >= rows or pad:GetAttribute("Row") ~= field.rows + 1 then
			pad:Destroy()
			farm.rowPads[fieldId] = nil
		end
	end
	for fieldId, field in farm.fields do
		if field.rows < rows and not farm.rowPads[fieldId] then
			buildPlaced(farm, function(batch)
				local at = stalkPosition(field.plot, field.rows + 1, (Config.Plot.columns + 1) / 2)
				local pad = buildPad(batch, "RowPad_" .. fieldId, Vector2.new(8, 4), Vector3.new(at.X, Config.Farm.origin.Y, at.Z), "Row", "+1 Row", fieldId)
				pad:SetAttribute("Row", field.rows + 1)
				farm.rowPads[fieldId] = pad
				connectPad(userId, pad)
			end)
		end
		local pad = farm.rowPads[fieldId]
		if pad then setPadPrice(pad, rowUpgrade.currency, rowPrice) end
	end
	local nextPlot = Pricing.plotsBought(farm.fields) + 2
	local plotPad = farm.plotPad
	if plotPad and (plotPad:GetAttribute("Plot") ~= nextPlot or not Config.Grid.order[nextPlot]) then
		plotPad:Destroy()
		farm.plotPad = nil
	end
	if not farm.plotPad and Config.Grid.order[nextPlot] then
		buildPlaced(farm, function(batch)
			local at = cellCenter(nextPlot) - Vector3.new(0, 0, Config.cellSize().Y / 2 - 7)
			local pad = buildPad(batch, "PlotPad", Vector2.new(9, 9), at, "Plot", plotUpgrade.displayName)
			pad:SetAttribute("Plot", nextPlot)
			farm.plotPad = pad
			connectPad(userId, pad)
		end)
	end
	if farm.plotPad then setPadPrice(farm.plotPad, plotUpgrade.currency, plotPrice) end
end

local function buildMicrowave(model: Model, front: CFrame): MicrowaveView
	-- Invisible interaction anchor on the field-facing side of the kiosk; LookVector points at the field.
	local door = part("MicrowaveDoor", Vector3.new(4, 4, 1), front.Position, Color3.new(1, 1, 1), model)
	door.CFrame = front
	door.Transparency, door.CanQuery = 1, false
	local pop = prompt("Microwave", "Pop corn", "Microwave", Config.Microwave.range, door)
	local popping = Instance.new("ParticleEmitter")
	popping.Name, popping.Enabled, popping.Rate = "Popping", false, 18
	-- Tiny Blender popcorn pieces hop out while it cooks (Nov 3 2026).
	popping.Texture = require(script.Parent.HubSpectacle).Art.Popcorn
	popping.Rotation, popping.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-240, 240)
	popping.Size = NumberSequence.new(0.6, 0.35)
	popping.Lifetime, popping.Speed = NumberRange.new(0.4, 0.7), NumberRange.new(6, 10)
	popping.SpreadAngle, popping.Acceleration = Vector2.new(35, 35), Vector3.new(0, -25, 0)
	popping.EmissionDirection = Enum.NormalId.Top
	popping.Parent = door
	local popcorn = Instance.new("Folder")
	popcorn.Name, popcorn.Parent = "Popcorn", model
	return { door = door, prompt = pop, popping = popping, popcorn = popcorn }
end

-- Invisible field-facing anchor carrying one owner-only prompt.
local function station(model: Model, name: string, front: CFrame, promptName: string, action: string, object: string, range: number): Part
	local anchor = part(name, Vector3.new(4, 4, 1), front.Position, Color3.new(1, 1, 1), model)
	anchor.CFrame = front
	anchor.Transparency, anchor.CanQuery = 1, false
	prompt(promptName, action, object, range, anchor)
	return anchor
end

-- What a new player's farm looks like on arrival (ripe starter corn, stations, locked cells),
-- with no prompts, pads, player state or growth updates. Replaced when the slot is claimed.
local function buildOpenPlot(slot: number)
	local origin = Config.Farm.origin
	local model = Instance.new("Model")
	model.Name = "OpenPlot_" .. tostring(slot)
	model:SetAttribute("Slot", slot)
	buildPlotGround(model, 1)
	for plot = 2, #Config.Grid.order do buildLocked(model, plot) end
	Visuals.build(model, origin, nil)
	Brick.finish(model:FindFirstChild("Scenery") :: Model, origin.Y)
	for row = 1, Config.Plot.baseRows do
		for col = 1, Config.Plot.columns do
			local pos = stalkPosition(1, row, col)
			-- Same height FarmService.update gives a ripe stalk's mesh.
			if not Templates.clone("Corn", model, Vector3.new(pos.X, origin.Y + 0.25, pos.Z), 4.5 * 1.4) then
				part("Stalk", Vector3.new(0.6, 4.5, 0.6), pos, Color3.fromRGB(68, 148, 56), model)
				part("Ear", Vector3.new(0.9, 1.5, 0.9), pos + Vector3.new(0.4, 0.6, 0), Color3.fromRGB(255, 211, 63), model).Shape = Enum.PartType.Ball
			end
		end
	end
	model.WorldPivot = CFrame.identity
	model:PivotTo(Map.farmFrame(slot))
	model.Parent = openRoot
	openPlots[slot] = model
end

function FarmService.init()
	assert(root == nil, "FarmService already initialized")
	assert(not workspace:FindFirstChild("PopcornFarms"), "Refusing to replace existing farms")
	local folder = Instance.new("Folder")
	folder.Name = "PopcornFarms"
	folder.Parent = workspace
	root = folder
	local open = Instance.new("Folder")
	open.Name = "PopcornOpenPlots"
	open.Parent = workspace
	openRoot = open
	for slot = 0, Config.Map.slots - 1 do
		buildOpenPlot(slot)
		task.wait() -- Spread the six builds across frames; players already joined are created afterwards.
	end
end

-- Pad step-ons go to this handler (wired by Bootstrap to UpgradeService, which requires us).
function FarmService.setPadHandler(handler: PadHandler)
	padHandler = handler
end

function FarmService.create(userId: number, fields: { [string]: Types.Field }, ownerName: string?)
	assert(root and not farms[userId], "Farm lifecycle error")
	local slot = 0
	while occupied[slot] do slot += 1 end
	if slot >= Config.Map.slots then
		-- Set the place's Max Players to Config.Map.slots so this never happens.
		warn("[PopcornTycoon] No free farm slot for " .. tostring(userId))
		return
	end
	occupied[slot] = true
	if openPlots[slot] then
		openPlots[slot]:Destroy()
		openPlots[slot] = nil
	end
	local origin = Config.Farm.origin
	local model = Instance.new("Model")
	model.Name = "Farm_" .. tostring(userId)
	model:SetAttribute("OwnerUserId", userId)
	local owned: { [number]: Types.Field } = {}
	for _, field in fields do owned[field.plot] = field end
	local locked: { [number]: Model } = {}
	for plot = 1, #Config.Grid.order do
		if owned[plot] then buildPlotGround(model, plot) else locked[plot] = buildLocked(model, plot) end
	end
	local soil = model:FindFirstChild("Soil") :: BasePart
	local ownerBoard, microwaveFront, sellFront = Visuals.build(model, origin, ownerName or tostring(userId))
	-- Brick look and solid decorations; crops and prompts are built outside Scenery and stay passable.
	Brick.finish(model:FindFirstChild("Scenery") :: Model, origin.Y)
	local ownerLabel = Instance.new("BillboardGui")
	ownerLabel.Name, ownerLabel.Adornee = "OwnerLabel", ownerBoard
	ownerLabel.Size, ownerLabel.StudsOffset = UDim2.fromOffset(200, 36), Vector3.new(0, 3, 0)
	ownerLabel.MaxDistance = 60
	ownerLabel.Enabled = false -- The physical entrance sign already displays the owner.
	local title = Instance.new("TextLabel")
	title.Name = "OwnerName"
	title.Size, title.BackgroundTransparency = UDim2.fromScale(1, 1), 0.2
	title.BackgroundColor3, title.TextColor3 = Color3.fromRGB(47, 40, 29), Color3.fromRGB(255, 231, 155)
	title.Font, title.TextScaled = Enum.Font.GothamMedium, true
	title.Text = (ownerName or tostring(userId)) .. "'s cornfield"
	title.Parent = ownerLabel
	ownerLabel.Parent = soil
	local views: { [string]: StalkView } = {}
	for _, field in fields do
		for row = 1, field.rows do
			for col = 1, Config.Plot.columns do
				local id, view = buildStalk(model, field, row, col)
				views[id] = view
			end
		end
	end
	local microwave = buildMicrowave(model, microwaveFront)
	local sellStand = station(model, "SellCounter", sellFront, "Sell", "Sell popcorn", "No popcorn yet", Config.Sell.range)
	local placement = Map.farmFrame(slot)
	model.WorldPivot = CFrame.identity
	model:PivotTo(placement)
	model.Parent = root
	Map.setSlotOwner(slot, ownerName or tostring(userId))
	local farm: FarmView = {
		model = model, fields = fields, slot = slot, placement = placement, stalks = views,
		microwave = microwave, sellStand = sellStand, locked = locked, rowPads = {}, plotPad = nil,
	}
	farms[userId] = farm
	refreshPads(userId, farm)
end

-- Visual counterpart of a committed Extra Row purchase; the profile already holds the stalks.
function FarmService.plantRow(userId: number, fieldId: string, row: number)
	local farm = assert(farms[userId], "Farm missing")
	local field = assert(farm.fields[fieldId], "Field missing")
	buildPlaced(farm, function(batch)
		for col = 1, Config.Plot.columns do
			local id, view = buildStalk(batch, field, row, col)
			farm.stalks[id] = view
		end
	end)
	refreshPads(userId, farm)
end

-- Visual counterpart of a committed New Plot purchase: the lawn becomes a planted bed.
function FarmService.addPlot(userId: number, fieldId: string)
	local farm = assert(farms[userId], "Farm missing")
	local field = assert(farm.fields[fieldId], "Field missing")
	local cell = farm.locked[field.plot]
	if cell then cell:Destroy() end
	farm.locked[field.plot] = nil
	buildPlaced(farm, function(batch)
		buildPlotGround(batch, field.plot)
		for row = 1, field.rows do
			for col = 1, Config.Plot.columns do
				local id, view = buildStalk(batch, field, row, col)
				farm.stalks[id] = view
			end
		end
	end)
	refreshPads(userId, farm)
end

-- Re-prices every pad of a farm (after any purchase, prices of the other kind move too).
function FarmService.refreshPads(userId: number)
	local farm = farms[userId]
	if farm then refreshPads(userId, farm) end
end

function FarmService.target(userId: number, fieldId: string, stalkId: string): Part?
	local farm = farms[userId]
	if not farm then return nil end
	local view = farm.stalks[stalkId]
	return if view and view.fieldId == fieldId then view.part else nil
end

-- Stalk parts by ID, for server-side tool targeting.
function FarmService.stalkParts(userId: number): { [string]: Part }
	local list: { [string]: Part } = {}
	local farm = farms[userId]
	if farm then for id, view in farm.stalks do list[id] = view.part end end
	return list
end

-- The field (plot) a stalk belongs to.
function FarmService.fieldOf(userId: number, stalkId: string): string?
	local farm = farms[userId]
	local view = if farm then farm.stalks[stalkId] else nil
	return if view then view.fieldId else nil
end

-- Where the owner's character appears: on the bridge just outside the farm entrance,
-- facing into the farm. nil when the player has no farm (all slots taken).
function FarmService.spawnFrame(userId: number): CFrame?
	local farm = farms[userId]
	if not farm then return nil end
	local f = Config.Farm
	local plotCenter = f.origin + f.plotOffset
	local entrance = Vector3.new(f.origin.X, f.origin.Y, plotCenter.Z - f.plotSize.Z / 2)
	local at = entrance + Vector3.new(0, 3.5, -4)
	return farm.placement * CFrame.lookAt(at, at + Vector3.new(0, 0, 1))
end

function FarmService.has(userId: number): boolean
	return farms[userId] ~= nil
end

function FarmService.sellStand(userId: number): Part?
	local farm = farms[userId]
	return if farm then farm.sellStand else nil
end

function FarmService.microwave(userId: number): MicrowaveView?
	local farm = farms[userId]
	return if farm then farm.microwave else nil
end

-- The live row pad of a plot, if it still has bed room.
function FarmService.rowPad(userId: number, fieldId: string): Part?
	local farm = farms[userId]
	return if farm then farm.rowPads[fieldId] else nil
end

-- The live New Plot pad, while a cell is still locked.
function FarmService.plotPad(userId: number): Part?
	local farm = farms[userId]
	return if farm then farm.plotPad else nil
end

function FarmService.resolve(prompt: ProximityPrompt): (number?, string?, string?)
	local stem = prompt.Parent
	local model = if stem then stem.Parent else nil
	if not model or model.Parent ~= root then return nil, nil, nil end
	local userId = model:GetAttribute("OwnerUserId")
	local farm = farms[userId]
	local stalkId = if stem then stem:GetAttribute("StalkId") else nil
	local view = if farm then farm.stalks[stalkId] else nil
	if not view or view.prompt ~= prompt then return nil, nil, nil end
	return userId, view.fieldId, stalkId
end

-- Owner of a registered farm-level prompt (microwave or sell stand), else nil.
function FarmService.resolveOwner(target: ProximityPrompt): number?
	local holder = target.Parent
	local model = if holder then holder.Parent else nil
	if not model or model.Parent ~= root then return nil end
	local userId = model:GetAttribute("OwnerUserId")
	local farm = farms[userId]
	if not farm then return nil end
	if target == farm.microwave.prompt or holder == farm.sellStand then return userId end
	return nil
end

function FarmService.update(now: number)
	for _, farm in farms do
		for id, view in farm.stalks do
			local field = farm.fields[view.fieldId]
			local crop = Config.Crops[field.cropId]
			local stalk = field.stalks[id]
			local yields = Growth.yields(stalk.growthStartedAt, now, crop)
			local stage = if yields > 0 then 3 else math.floor(Growth.progress(stalk.growthStartedAt, now, crop) * 3)
			if view.part:GetAttribute("GrowthStage") ~= stage then
				local height = 0.75 + stage * 1.25
				view.part.Size = Vector3.new(0.6, height, 0.6)
				view.part.Position = Vector3.new(view.part.Position.X, Config.Farm.origin.Y + 0.25 + height / 2, view.part.Position.Z)
				view.ear.Transparency = if yields > 0 then 0 else 1
				if view.mesh then
					view.ear.Transparency = 1
					local _, size = view.mesh:GetBoundingBox()
					view.mesh:ScaleTo(view.mesh:GetScale() * (height * 1.4) / size.Y)
					local box, resized = view.mesh:GetBoundingBox()
					view.mesh:PivotTo(view.mesh:GetPivot() + Vector3.new(view.part.Position.X, Config.Farm.origin.Y + 0.25 + resized.Y / 2, view.part.Position.Z) - box.Position)
					for _, object in view.mesh:GetDescendants() do
						if object:IsA("BasePart") and object.Name:lower():find("corn") then object.Transparency = if stage == 3 then 0 else 1 end
					end
				end
				for i, leaf in view.leaves do
					local scale = 0.35 + stage * 0.21
					local angle = (i - 1) * math.pi / 2
					leaf.Size = Vector3.new(0.85 * scale, 0.18, 2.2 * scale)
					leaf.CFrame = CFrame.new(view.part.Position.X, Config.Farm.origin.Y + 0.25 + height * (0.35 + (i % 2) * 0.25), view.part.Position.Z)
						* CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.4 * scale, -0.85 * scale) * CFrame.Angles(math.rad(28), 0, 0)
				end
				view.part:SetAttribute("GrowthStage", stage)
			end
			if view.part:GetAttribute("AvailableYields") ~= yields then
				view.part:SetAttribute("AvailableYields", yields)
				view.prompt.ObjectText = crop.displayName .. " · " .. tostring(yields) .. "/" .. tostring(crop.maxYields)
				view.prompt.Enabled = yields > 0
			end
		end
	end
	-- Re-arm a pad once its player has stepped off it (or it is gone).
	for userId, visit in padVisits do
		if not visit.left then
			local player = Players:GetPlayerByUserId(userId)
			local character = if player then player.Character else nil
			local rootPart = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
			if not visit.pad.Parent or not rootPart or not FarmService.onPad(visit.pad, rootPart.Position) then visit.left = true end
		end
	end
end

function FarmService.remove(userId: number)
	local farm = farms[userId]
	padVisits[userId] = nil
	if farm then
		farm.model:Destroy()
		Map.setSlotOwner(farm.slot, nil)
		occupied[farm.slot], farms[userId] = nil, nil
		buildOpenPlot(farm.slot)
	end
end

return FarmService
