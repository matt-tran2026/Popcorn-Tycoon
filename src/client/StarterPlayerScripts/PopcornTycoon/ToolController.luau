--!strict
-- Presentation for swung tools: the swing, the white glow on the stalks the next swing will
-- cut (HarvestHighlight; replaced the gold rings on the soil, Nov 3 2026) and staggered snips. (The yellow
-- kernels that used to arc out of cut stalks were removed on creator request, Nov 3 2026;
-- the HUD's flying corn icons show the reward instead.) Purely local; the server decides every harvest and reward.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Actions = game:GetService("ContextActionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local ToolRules = require(Shared:WaitForChild("ToolRules"))
local Types = require(Shared:WaitForChild("Types"))
local Prompts = require(script.Parent.PromptController)
local Highlight = require(script.Parent.HarvestHighlight)
local player = Players.LocalPlayer
local Controller = {}

local Sounds = {
	Swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.35 },
	-- Pro Sound Effects "Scissors Various Cuts Squeaky Snips 17" (1.1 s), Creator Store.
	Snip = { id = "rbxassetid://9118831072", volume = 0.5 },
}
local rng = Random.new()

-- One-shot 3D sound at a world position with a little pitch variation so repeats never match.
local function play(sound: { id: string, volume: number }, at: Vector3?, pitch: number?)
	local holder: Instance = workspace
	local anchor: Attachment? = nil
	if at then
		anchor = Instance.new("Attachment")
		;(anchor :: Attachment).WorldPosition = at
		;(anchor :: Attachment).Parent = workspace.Terrain
		holder = anchor :: Attachment
	end
	local s = Instance.new("Sound")
	s.SoundId, s.Volume = sound.id, sound.volume
	s.PlaybackSpeed = pitch or rng:NextNumber(0.92, 1.12)
	s.RollOffMinDistance, s.RollOffMaxDistance = 6, 60
	s.Parent = holder
	s:Play()
	s.Ended:Once(function() (anchor or s):Destroy() end)
	task.delay(4, function() if (anchor or s).Parent then (anchor or s):Destroy() end end)
end

local function myStalks(): { Types.TargetCandidate }
	local list: { Types.TargetCandidate } = {}
	local farms = workspace:FindFirstChild("PopcornFarms")
	local farm = farms and farms:FindFirstChild("Farm_" .. player.UserId)
	if not farm then return list end
	for _, child in farm:GetChildren() do
		local id = child:GetAttribute("StalkId")
		local ready = child:GetAttribute("AvailableYields")
		if child:IsA("BasePart") and typeof(id) == "string" and typeof(ready) == "number" and ready > 0 then
			table.insert(list, { id = id, position = child.Position })
		end
	end
	return list
end

-- With no swung tool held, the glow goes back to the hand-pick rule.
local function hideMarkers() Highlight.setToolTargets(nil) end

-- The swing layers a turn of the right shoulder over the animated hold pose, written after
-- the animator each frame. R15 shoulders are Motor6Ds on classic rigs and
-- AnimationConstraints on newer avatar rigs; both expose Transform.
local function shoulder(character: Model): Instance?
	local arm = character:FindFirstChild("RightUpperArm")
	local joint = if arm then arm:FindFirstChild("RightShoulder") else nil
	if not joint then
		local torso = character:FindFirstChild("Torso")
		joint = if torso then torso:FindFirstChild("Right Shoulder") else nil
	end
	return if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then joint else nil
end

local function swing(tool: Tool, definition: Types.ToolDefinition)
	local character = tool.Parent
	if not character or not character:IsA("Model") then return end
	local joint: any = shoulder(character) -- Untyped: Transform lives on two unrelated classes.
	local duration = definition.swingSeconds or 0.3
	local handle = tool:FindFirstChild("Handle")
	local trail = if handle then handle:FindFirstChild("SwingTrail") :: Trail? else nil
	if trail then trail.Enabled = true end
	play(Sounds.Swing, nil, rng:NextNumber(1.05, 1.25))
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.PreSimulation:Connect(function()
		local t = math.clamp((os.clock() - started) / duration, 0, 1)
		-- Wind up out to the right, whip across the body, then ease back to the hold pose.
		local sweep = if t < 0.2 then -(t / 0.2) * 0.8 else -0.8 + TweenService:GetValue(math.min(1, (t - 0.2) / 0.5), Enum.EasingStyle.Back, Enum.EasingDirection.Out) * 2.2
		local settle = if t > 0.7 then (t - 0.7) / 0.3 else 0
		local lift = math.sin(math.min(t / 0.7, 1) * math.pi) * 0.45
		if joint and joint.Parent then
			joint.Transform = joint.Transform * CFrame.Angles(lift * (1 - settle), sweep * (1 - settle), 0)
		end
		if t >= 1 then
			connection:Disconnect()
			if trail then trail.Enabled = false end
		end
	end)
end

-- One snip sound per cut stalk, at the stalk.
local function snip(from: Vector3, delay: number)
	task.delay(delay, function() play(Sounds.Snip, from) end)
end

function Controller.start(feedback: RemoteEvent)
	local held: Tool? = nil
	local heldId: string? = nil
	local lastSwing = 0
	local lastScan = 0

	local function bind(tool: Tool)
		local toolId = tool:GetAttribute("ToolId")
		if typeof(toolId) ~= "string" or not Config.Tools[toolId] or tool:GetAttribute("Bound") then return end
		tool:SetAttribute("Bound", true)
		local definition = Config.Tools[toolId]
		tool.Equipped:Connect(function()
			held, heldId = tool, toolId
			Prompts.setHarvestSuppressed(true)
			-- Mouse click and touch tap activate Tools natively; F gives keyboards a swing key.
			Actions:BindAction("PopcornSwing", function(_, state)
				if state == Enum.UserInputState.Begin and held == tool then tool:Activate() end
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.F)
		end)
		tool.Unequipped:Connect(function()
			if held == tool then held, heldId = nil, nil end
			Actions:UnbindAction("PopcornSwing")
			Prompts.setHarvestSuppressed(false)
			hideMarkers()
		end)
		tool.Activated:Connect(function()
			-- Same cadence as the server, so a refused swing never animates.
			if os.clock() - lastSwing < definition.cooldownSeconds then return end
			lastSwing = os.clock()
			swing(tool, definition)
		end)
	end
	local function watch(container: Instance)
		for _, child in container:GetChildren() do if child:IsA("Tool") then bind(child) end end
		container.ChildAdded:Connect(function(child) if child:IsA("Tool") then bind(child) end end)
	end
	watch(player:WaitForChild("Backpack"))
	player.CharacterAdded:Connect(function(character)
		held, heldId = nil, nil
		Prompts.setHarvestSuppressed(false)
		hideMarkers()
		watch(character)
		player:WaitForChild("Backpack")
		watch(player:FindFirstChildOfClass("Backpack") :: Backpack)
	end)
	if player.Character then watch(player.Character) end

	-- Preview what the next swing would cut, using the server's own targeting rule.
	RunService.RenderStepped:Connect(function()
		if not held or not heldId then return end
		if os.clock() - lastScan < 0.1 then return end
		lastScan = os.clock()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then Highlight.setToolTargets({}) return end
		-- Same targeting rule as the server, so the glow shows exactly what the swing will cut.
		Highlight.setToolTargets(ToolRules.pickTargets(root.Position, root.CFrame.LookVector, myStalks(), Config.Tools[heldId]))
	end)

	-- Server-confirmed cuts: one snip per stalk, staggered after the blade passes.
	feedback.OnClientEvent:Connect(function(response)
		if not response.ok or typeof(response.tool) ~= "string" or typeof(response.targets) ~= "table" then return end
		local definition = Config.Tools[response.tool]
		if not definition then return end
		local stagger = definition.snipStaggerSeconds or 0.07
		local lead = (definition.swingSeconds or 0.3) * 0.35
		for i, position in response.targets do
			if typeof(position) == "Vector3" then
				snip(position + Vector3.new(0, 2.5, 0), lead + (i - 1) * stagger)
			end
		end
	end)
end

return Controller
