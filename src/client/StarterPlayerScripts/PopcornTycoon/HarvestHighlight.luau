--!strict
-- A glowing white outline on the corn you can harvest right now (creator request, Nov 3 2026).
-- One rule for every way of harvesting:
--   * holding a swung tool (Sickle, and any tool added to Config.Tools later): the stalks the
--     next swing would cut, as ToolController reports them with setToolTargets;
--   * hands: the ripe stalks whose pick prompt is showing (in reach), the ones E or a tap picks.
-- Above every glowing stalk floats a small row of corn pips, one per yield the stalk can hold:
-- bright cobs are ready to pick, dark ones are still growing (replaced the brown
-- "E · Pick corn / Normal Corn · 2/3" button, Nov 3 2026). For hand picking the row carries
-- a small key chip (E, or the gamepad button) and is itself the tap target on touch screens.
-- Farm upgrades (Nov 4 2026): the row has one pip per cycle the stalk's plot stores (Stalk
-- Storage, up to 10; pips shrink past 5), a "+n" count of ready corn when a cycle is worth more
-- than one (Corn Yield), and gold pips with a FULL tag once the stalk has stopped growing.
-- Purely local presentation; the server still decides every harvest.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local PromptService = game:GetService("ProximityPromptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(script.Parent.UITheme)
local player = Players.LocalPlayer
local HarvestHighlight = {}

-- Roblox draws at most 31 Highlights at once; prompts show at most 16 by default.
local POOL_SIZE = 16
local WHITE = Color3.new(1, 1, 1)

local BLACK = Color3.new(0, 0, 0)
local PIP = 34 -- pip size in screen pixels (the row keeps its size at any distance)
local PIP_GAP = 2
local KEY = 26
local PAD = 6 -- inner padding of the dark pill behind the row
local READY_TINT, GROWING_TINT = Color3.new(1, 1, 1), Color3.fromRGB(46, 40, 30)
local FULL_TINT = Color3.fromRGB(255, 214, 70)
local SMALL_PIP = 22 -- pip size once a stalk stores more than 5 cycles
local COUNT_W = 58

local toolTargets: { string }? = nil
-- Showing hand-pick prompts and the input that showed them (keyboard, gamepad or touch).
local shown: { [ProximityPrompt]: Enum.ProximityPromptInputType } = {}

-- Called by ToolController while a swung tool is held (nil when it is put away).
function HarvestHighlight.setToolTargets(ids: { string }?)
	toolTargets = ids
end

local function myFarm(): Instance?
	local farms = workspace:FindFirstChild("PopcornFarms")
	return farms and farms:FindFirstChild("Farm_" .. player.UserId)
end

-- The visible corn for a stalk id: the mesh model FarmService tags with StalkId, else the
-- stalk part itself (plain-part fallback farms).
local cornById: { [string]: Instance } = {}
local indexedFarm: Instance? = nil
local function corn(farm: Instance, id: string): Instance?
	if indexedFarm ~= farm then
		indexedFarm, cornById = farm, {}
		local function index(child: Instance)
			local stalkId = child:GetAttribute("StalkId")
			if typeof(stalkId) ~= "string" then return end
			if child:IsA("Model") or not cornById[stalkId] then cornById[stalkId] = child end
		end
		for _, child in farm:GetChildren() do index(child) end
		farm.ChildAdded:Connect(function(child)
			task.defer(function() if indexedFarm == farm then index(child) end end)
		end)
	end
	local found = cornById[id]
	return if found and found.Parent then found else nil
end

type Target = { corn: Instance, stalk: BasePart, prompt: ProximityPrompt?, input: Enum.ProximityPromptInputType? }
type Badge = {
	gui: BillboardGui, pips: { ImageLabel }, key: Frame, keyText: TextLabel, pop: UIScale, count: TextLabel,
	stalk: BasePart?, prompt: ProximityPrompt?, last: number,
}

local function keyLabel(input: Enum.ProximityPromptInputType?, prompt: ProximityPrompt): string?
	if input == Enum.ProximityPromptInputType.Touch then return nil end
	if input == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

-- One floating pip row; pooled and re-pointed at whichever stalk needs it.
local function newBadge(parent: Instance, maxYields: number): Badge
	local gui = Instance.new("BillboardGui")
	gui.Name, gui.AlwaysOnTop, gui.Active, gui.Enabled = "CornPips", true, true, false
	gui.LightInfluence, gui.ResetOnSpawn = 0, false
	local row = Instance.new("TextButton") -- The whole row is the tap target on touch screens.
	row.Name, row.Text, row.AutoButtonColor = "Pick", "", false
	-- A soft dark pill keeps the cobs readable over corn, soil or sky.
	row.BackgroundColor3, row.BackgroundTransparency = Color3.fromRGB(16, 20, 26), 0.5
	row.Size = UDim2.fromScale(1, 1)
	Instance.new("UICorner", row).CornerRadius = UDim.new(1, 0)
	local list = Instance.new("UIListLayout")
	list.FillDirection, list.SortOrder = Enum.FillDirection.Horizontal, Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment, list.VerticalAlignment = Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center
	list.Padding, list.Parent = UDim.new(0, PIP_GAP), row
	local pop = Instance.new("UIScale")
	pop.Parent = row
	-- Key chip: a small white keycap with the pick key.
	local key = Instance.new("Frame")
	key.Name, key.LayoutOrder, key.Size = "Key", 0, UDim2.fromOffset(KEY, KEY)
	key.BackgroundColor3 = Color3.new(1, 1, 1)
	Instance.new("UICorner", key).CornerRadius = UDim.new(0, 6)
	local keyEdge = Instance.new("UIStroke")
	keyEdge.Color, keyEdge.Thickness, keyEdge.ApplyStrokeMode, keyEdge.Parent = BLACK, 2, Enum.ApplyStrokeMode.Border, key
	local keyText = Instance.new("TextLabel")
	keyText.Name, keyText.BackgroundTransparency, keyText.Size = "Text", 1, UDim2.fromScale(1, 1)
	keyText.Font, keyText.TextScaled, keyText.TextColor3 = Theme.Font, true, BLACK
	local keyPad = Instance.new("UIPadding")
	keyPad.PaddingTop, keyPad.PaddingBottom, keyPad.Parent = UDim.new(0, 3), UDim.new(0, 3), keyText
	keyText.Parent, key.Parent = key, row
	local count = Instance.new("TextLabel")
	count.Name, count.LayoutOrder, count.BackgroundTransparency = "Count", 1000, 1
	count.Size, count.Font, count.TextScaled = UDim2.fromOffset(COUNT_W, PIP - 6), Theme.Font, true
	count.TextColor3 = Color3.fromRGB(255, 226, 74)
	local countStroke = Instance.new("UIStroke")
	countStroke.Color, countStroke.Thickness, countStroke.Parent = BLACK, 2, count
	count.Parent = row
	local pips = {}
	for i = 1, maxYields do
		local pip = Instance.new("ImageLabel")
		pip.Name, pip.LayoutOrder, pip.Image = "Pip" .. i, i, Theme.CornIcon
		pip.BackgroundTransparency, pip.ScaleType, pip.Size = 1, Enum.ScaleType.Fit, UDim2.fromOffset(PIP, PIP)
		pip.Parent = row
		table.insert(pips, pip)
	end
	row.Parent = gui
	local badge: Badge = { gui = gui, pips = pips, key = key, keyText = keyText, pop = pop, count = count, stalk = nil, prompt = nil, last = -1 }
	row.Activated:Connect(function()
		local prompt = badge.prompt
		if prompt and prompt.Enabled then prompt:InputHoldBegin() prompt:InputHoldEnd() end
	end)
	gui.Parent = parent
	return badge
end

-- Points a badge at a stalk and redraws its pips; a pick makes the row hop.
local function showBadge(badge: Badge, target: Target, limit: number)
	local stalk = target.stalk
	local ready = stalk:GetAttribute("AvailableYields")
	-- The plot's own storage and corn per cycle, replicated by FarmService.
	local stored, perCycle = stalk:GetAttribute("MaxYields"), stalk:GetAttribute("CornPerYield")
	local maxYields = if typeof(stored) == "number" then math.clamp(stored, 1, limit) else limit
	local corn = if typeof(perCycle) == "number" then perCycle else 1
	local count = if typeof(ready) == "number" then math.clamp(ready, 0, maxYields) else 0
	local full = count >= maxYields
	if badge.stalk ~= stalk then
		badge.stalk, badge.last = stalk, count
		badge.gui.Adornee = stalk
		badge.pop.Scale = 0.4
		TweenService:Create(badge.pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	elseif count ~= badge.last then
		badge.pop.Scale = if count < badge.last then 1.3 else 1.15
		TweenService:Create(badge.pop, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		badge.last = count
	end
	badge.prompt = target.prompt
	-- Just above the visible corn (the mesh stands about 1.4 times the stalk part's height).
	badge.gui.StudsOffsetWorldSpace = Vector3.new(0, stalk.Size.Y * 0.85 + 0.3, 0)
	local key = if target.prompt then keyLabel(target.input, target.prompt) else nil
	badge.key.Visible = key ~= nil
	badge.keyText.Text = key or ""
	local pip = if maxYields > 5 then SMALL_PIP else PIP
	local label = if full then "FULL" elseif corn > 1 then "+" .. tostring(count * corn) else ""
	badge.count.Visible = label ~= ""
	badge.count.Text = label
	badge.count.TextColor3 = if full then FULL_TINT else Color3.fromRGB(255, 255, 255)
	local width = maxYields * pip + (maxYields - 1) * PIP_GAP + (if key then KEY + PIP_GAP + 4 else 0)
		+ (if label ~= "" then COUNT_W + PIP_GAP else 0)
	badge.gui.Size = UDim2.fromOffset(width + PAD * 2 + 8, PIP + PAD)
	for i, image in badge.pips do
		local on = i <= count
		image.Visible = i <= maxYields
		image.Size = UDim2.fromOffset(pip, pip)
		image.ImageColor3 = if full then FULL_TINT elseif on then READY_TINT else GROWING_TINT
		image.ImageTransparency = if on then 0 else 0.35
	end
	badge.gui.Enabled = true
end

function HarvestHighlight.start(gui: ScreenGui)
	-- Enough pips for the most a stalk can store (base storage plus the top Storage level).
	local storage = Config.FarmUpgrades.Storage.effects
	local maxYields = Config.Crops[Config.Plot.cropId].maxYields + storage[#storage]
	local badges: { Badge } = {}
	local pool: { Highlight } = {}
	local function highlight(i: number): Highlight
		local h = pool[i]
		if h then return h end
		h = Instance.new("Highlight")
		h.Name = "HarvestGlow"
		h.FillColor, h.OutlineColor = WHITE, WHITE
		-- Drawn through neighbouring stalks so a target in the middle of the field still shows.
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Enabled = false
		h.Parent = workspace.CurrentCamera
		pool[i] = h
		return h
	end

	PromptService.PromptShown:Connect(function(prompt, input)
		if prompt.Name ~= "Harvest" then return end
		local farm = prompt.Parent and prompt.Parent.Parent
		if farm and farm:GetAttribute("OwnerUserId") == player.UserId then shown[prompt] = input end
	end)
	PromptService.PromptHidden:Connect(function(prompt) shown[prompt] = nil end)

	RunService.Heartbeat:Connect(function()
		local farm = myFarm()
		local targets: { Target } = {}
		if farm then
			if toolTargets then
				for _, id in toolTargets do
					local c = corn(farm, id)
					local stalk = farm:FindFirstChild("Stalk_" .. id)
					if c and stalk and stalk:IsA("BasePart") then table.insert(targets, { corn = c, stalk = stalk }) end
				end
			else
				for prompt, input in shown do
					local stalk = prompt.Parent
					local id = stalk and stalk:GetAttribute("StalkId")
					if not prompt.Enabled or not stalk or stalk.Parent ~= farm then
						if not prompt.Parent then shown[prompt] = nil end
					elseif typeof(id) == "string" and stalk:IsA("BasePart") then
						local c = corn(farm, id)
						if c then table.insert(targets, { corn = c, stalk = stalk, prompt = prompt, input = input }) end
					end
				end
			end
		end
		-- A soft breathing glow: the outline pulses, with a faint white wash over the stalk.
		local pulse = (math.sin(os.clock() * 5) + 1) / 2
		for i = 1, math.max(#targets, #pool) do
			if i > POOL_SIZE then break end
			local target = targets[i]
			if target then
				local h = highlight(i)
				h.Adornee = target.corn
				h.OutlineTransparency = pulse * 0.25
				h.FillTransparency = 0.6 + pulse * 0.2
				h.Enabled = true
				badges[i] = badges[i] or newBadge(gui, maxYields)
				showBadge(badges[i], target, maxYields)
			else
				if pool[i] then
					pool[i].Enabled = false
					pool[i].Adornee = nil
				end
				local badge = badges[i]
				if badge then
					badge.gui.Enabled, badge.gui.Adornee = false, nil
					badge.stalk, badge.prompt = nil, nil
				end
			end
		end
	end)
end

return HarvestHighlight
