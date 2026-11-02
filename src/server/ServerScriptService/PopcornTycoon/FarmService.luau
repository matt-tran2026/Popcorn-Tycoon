--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local Types = require(Shared.Types)
local Visuals = require(script.Parent.FarmVisuals)
local Templates = require(script.Parent.VisualTemplates)

type StalkView = { part: Part, ear: Part, prompt: ProximityPrompt, leaves: { Part }, mesh: Model? }
type FarmView = { model: Model, field: Types.Field, slot: number, stalks: { [string]: StalkView } }
local farms: { [number]: FarmView } = {}
local occupied: { [number]: boolean } = {}
local root: Folder? = nil
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

function FarmService.init()
	assert(root == nil, "FarmService already initialized")
	assert(not workspace:FindFirstChild("PopcornFarms"), "Refusing to replace existing farms")
	local folder = Instance.new("Folder")
	folder.Name = "PopcornFarms"
	folder.Parent = workspace
	root = folder
end

function FarmService.create(userId: number, field: Types.Field, ownerName: string?)
	assert(root and not farms[userId], "Farm lifecycle error")
	local slot = 0
	while occupied[slot] do slot += 1 end
	occupied[slot] = true
	local origin = Config.Farm.origin + Vector3.new(slot * Config.Farm.separation, 0, 0)
	local model = Instance.new("Model")
	model.Name = "Farm_" .. tostring(userId)
	model:SetAttribute("OwnerUserId", userId)
	model:SetAttribute("FieldId", field.id)
	local soil = part("Soil", Config.Farm.size, origin, Color3.fromRGB(100, 66, 41), model)
	soil.Material = Enum.Material.Ground
	local ownerBoard = Visuals.build(model, origin, ownerName or tostring(userId))
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
	for row = 1, Config.Starter.rows do
		for col = 1, Config.Starter.columns do
			local id = tostring((row - 1) * Config.Starter.columns + col)
			local pos = origin + Vector3.new((col - (Config.Starter.columns + 1) / 2) * Config.Starter.spacing, 2.5, (row - (Config.Starter.rows + 1) / 2) * Config.Starter.spacing)
			local stem = part("Stalk_" .. id, Vector3.new(0.6, 4.5, 0.6), pos, Color3.fromRGB(68, 148, 56), model)
			stem:SetAttribute("StalkId", id)
			local ear = part("Ear_" .. id, Vector3.new(0.9, 1.5, 0.9), pos + Vector3.new(0.4, 0.6, 0), Color3.fromRGB(255, 211, 63), model)
			ear.Shape = Enum.PartType.Ball
			local leaves: { Part } = {}
			for i = 1, 4 do
				local leaf = part("Leaf_" .. i, Vector3.new(0.9, 0.18, 2.2), pos, Color3.fromRGB(86, 169, 49), stem)
				leaf.CanQuery = false
				table.insert(leaves, leaf)
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "Harvest"
			prompt.ActionText, prompt.ObjectText = "Pick corn", "Normal Corn"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.HoldDuration, prompt.MaxActivationDistance = 0, Config.Manual.range
			prompt.RequiresLineOfSight, prompt.ClickablePrompt = false, true
			prompt.Parent = stem
			local mesh = Templates.clone("Corn", model, Vector3.new(pos.X, origin.Y + 0.25, pos.Z), 4.5)
			if mesh then stem.Transparency = 1 for _, leaf in leaves do leaf:Destroy() end leaves = {} end
			views[id] = { part = stem, ear = ear, prompt = prompt, leaves = leaves, mesh = mesh }
		end
	end
	model.Parent = root
	farms[userId] = { model = model, field = field, slot = slot, stalks = views }
end

function FarmService.target(userId: number, fieldId: string, stalkId: string): Part?
	local farm = farms[userId]
	if not farm or farm.field.id ~= fieldId then return nil end
	local view = farm.stalks[stalkId]
	return if view then view.part else nil
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
	return userId, farm.field.id, stalkId
end

function FarmService.update(now: number)
	for _, farm in farms do
		local crop = Config.Crops[farm.field.cropId]
		for id, view in farm.stalks do
			local stalk = farm.field.stalks[id]
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
end

function FarmService.remove(userId: number)
	local farm = farms[userId]
	if farm then
		farm.model:Destroy()
		occupied[farm.slot], farms[userId] = nil, nil
	end
end

return FarmService
