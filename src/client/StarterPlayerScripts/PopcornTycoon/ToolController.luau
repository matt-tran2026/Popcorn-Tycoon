--!strict
-- Presentation for swung tools: the swing, the white glow on the stalks the next swing will
-- cut (HarvestHighlight; replaced the gold rings on the soil, Nov 3 2026) and staggered snips. (The yellow
-- kernels that used to arc out of cut stalks were removed on creator request, Nov 3 2026;
-- the HUD's flying corn icons show the reward instead.) Purely local; the server decides every harvest and reward.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Actions = game:GetService("ContextActionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local ToolRules = require(Shared:WaitForChild("ToolRules"))
local Types = require(Shared:WaitForChild("Types"))
local ToolPresentation = require(Shared:WaitForChild("ToolPresentation"))
local Prompts = require(script.Parent.PromptController)
local Highlight = require(script.Parent.HarvestHighlight)
local ToolAnimator = require(script.Parent.ToolAnimator)
local Effects = require(script.Parent.ToolEffects)
local player = Players.LocalPlayer
local Controller = {}

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

-- The layered pose player for the held tool (one per equip; stopped on unequip/respawn).
local animator: ToolAnimator.Player? = nil

local function stopAnimator()
	if animator then animator:stop() end
	animator = nil
end

-- Equip flourish, then the tool's idle sway. Falls back to nothing for tools without clips.
local function startAnimator(tool: Tool, look: ToolPresentation.Presentation?)
	stopAnimator()
	local character = tool.Parent
	if not look or not character or not character:IsA("Model") then return end
	local anim = ToolAnimator.attach(character)
	animator = anim
	anim:setIdle(look.clips.Idle)
	if look.clips.Equip then
		anim:play(look.clips.Equip, function(marker)
			if marker == "Shing" then Effects.sound(look.sounds.Equip) end
		end)
	end
end

-- Tools with a SwingAlt clip alternate it with Swing, so rapid repeats never look identical.
local useAlt = false

-- Alternating tools (Twin Sickles): a prediction of the server's hand/streak state
-- (HarvestService), so the right clip plays at once and the glow shows the next arc. It follows
-- the same rule (ToolRules.nextSwing) and is corrected by every server reply.
local prediction: { toolId: string, state: Types.ComboState }? = nil
local function predicted(toolId: string): Types.ComboState
	local current = prediction
	if current and current.toolId == toolId then return current.state end
	local fresh = { toolId = toolId, state = ToolRules.newCombo() }
	prediction = fresh
	return fresh.state
end

-- The swing trail under `holder`, skipping anything inside `skip` (the right blade's search must
-- not find the left copy's trail, which sits inside the same Tool).
local function trailOf(holder: Instance?, skip: Instance?): Trail?
	if not holder then return nil end
	for _, item in holder:GetDescendants() do
		if item:IsA("Trail") and item.Name == "SwingTrail" and not (skip and item:IsDescendantOf(skip)) then return item end
	end
	return nil
end

local function rootFrame(): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.CFrame else nil
end

-- The harvesting swing: pose clip, trail on for its duration, swish at the start. Alternating
-- tools play the hand whose turn it is (Swing right, SwingAlt left) or the Combo spin.
local function swing(tool: Tool, look: ToolPresentation.Presentation?, toolId: string, definition: Types.ToolDefinition)
	-- Trails sit on the Handle, or on the moving shaft for tools with a holder grip (Pitchfork);
	-- the Twin Sickles' left blade is the Offhand model inside the Tool.
	local trails: { Trail } = {}
	local clip = if look then look.clips.Swing else nil
	local sound = if look then look.sounds.Swing else nil
	local spin = false
	if look and ToolRules.alternates(definition) then
		local state = predicted(toolId)
		local shape = ToolRules.nextSwing(definition, state, os.clock())
		-- Only the hand is advanced here; the streak comes from the server's reply.
		state.hand = if shape.hand == "Right" then "Left" else "Right"
		if shape.combo then state.streak = 0 end
		local offhand = tool:FindFirstChild("Offhand")
		local right, left = trailOf(tool, offhand), trailOf(offhand)
		if shape.combo and look.clips.Combo then
			clip, spin = look.clips.Combo, true
			sound = look.sounds.Combo or sound
			if right then table.insert(trails, right) end
			if left then table.insert(trails, left) end
		elseif shape.hand == "Left" then
			clip = look.clips.SwingAlt or clip
			if left then table.insert(trails, left) end
		elseif right then
			table.insert(trails, right)
		end
	else
		local trail = trailOf(tool)
		if trail then table.insert(trails, trail) end
		if look and look.clips.SwingAlt then
			useAlt = not useAlt
			if useAlt then clip = look.clips.SwingAlt end
		end
	end
	for _, trail in trails do
		trail.Enabled = true
		task.delay(if clip then clip.seconds * 0.8 else 0.3, function() trail.Enabled = false end)
	end
	Effects.sound(sound)
	if animator and clip then
		local combo = if look and spin then look.vfx.combo else nil
		if combo then
			animator:play(clip, function(marker)
				if marker == "Spin" then Effects.comboSweep(rootFrame, combo) end
			end)
		else
			animator:play(clip)
		end
	end
end

-- When the blade reaches the corn: the played clip's Hit marker (the Combo spin for a combo).
local function hitLead(toolId: string, definition: Types.ToolDefinition, combo: boolean): number
	local look = ToolPresentation.get(toolId)
	local clip = if look then (if combo and look.clips.Combo then look.clips.Combo else look.clips.Swing) else nil
	local at = if clip and clip.markers and clip.markers.Hit then clip.markers.Hit else 0.35
	return (if clip then clip.seconds else definition.swingSeconds or 0.3) * at
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
		local look = ToolPresentation.get(toolId)
		tool.Equipped:Connect(function()
			held, heldId = tool, toolId
			startAnimator(tool, look)
			Prompts.setHarvestSuppressed(true)
			-- Mouse click and touch tap activate Tools natively; F gives keyboards a swing key.
			Actions:BindAction("PopcornSwing", function(_, state)
				if state == Enum.UserInputState.Begin and held == tool then tool:Activate() end
				return Enum.ContextActionResult.Sink
			end, false, Enum.KeyCode.F)
		end)
		tool.Unequipped:Connect(function()
			if held == tool then
				held, heldId = nil, nil
				stopAnimator()
			end
			Actions:UnbindAction("PopcornSwing")
			Prompts.setHarvestSuppressed(false)
			hideMarkers()
		end)
		tool.Activated:Connect(function()
			-- Same cadence as the server, so a refused swing never animates.
			if os.clock() - lastSwing < definition.cooldownSeconds then return end
			lastSwing = os.clock()
			swing(tool, look, toolId, definition)
		end)
	end
	local function watch(container: Instance)
		for _, child in container:GetChildren() do if child:IsA("Tool") then bind(child) end end
		container.ChildAdded:Connect(function(child) if child:IsA("Tool") then bind(child) end end)
	end
	watch(player:WaitForChild("Backpack"))
	player.CharacterAdded:Connect(function(character)
		held, heldId = nil, nil
		stopAnimator()
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
		-- Same targeting rule as the server, so the glow shows exactly what the swing will cut
		-- (for alternating tools: the next hand's arc, or the full combo circle when it is ready).
		local definition = Config.Tools[heldId]
		local shape = if ToolRules.alternates(definition) then ToolRules.nextSwing(definition, predicted(heldId), os.clock()) else nil
		Highlight.setToolTargets(ToolRules.pickTargets(root.Position, root.CFrame.LookVector, myStalks(), definition, shape))
	end)

	-- Where pulled ears land: the holder's chest, followed while they fly.
	local function pullTarget(): Vector3?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then return root.Position + Vector3.new(0, 0.8, 0) end
		return nil
	end

	-- Server-confirmed cuts: a snap and a leaf burst per stalk, staggered after the blade passes.
	-- Only stalks the server actually harvested get them; a refused swing shows nothing. Pull
	-- tools (Harvest Hook) also throw a streak to each stalk and fly its ear back to the player.
	feedback.OnClientEvent:Connect(function(response)
		-- Alternating tools: take the server's word for whose hand is next and the streak. (Refused
		-- swings carry no tool id; they belong to the tool in hand.)
		if typeof(response.hand) == "string" and typeof(response.streak) == "number" then
			local toolId = if typeof(response.tool) == "string" then response.tool else heldId
			if toolId and Config.Tools[toolId] and ToolRules.alternates(Config.Tools[toolId]) then
				local state = predicted(toolId)
				state.hand = if response.hand == "Right" then "Left" else "Right"
				state.streak = response.streak
				-- The server counted the hit about half a round trip before this arrived.
				if response.ok then state.lastHit = os.clock() - 0.1 end
			end
		end
		if not response.ok or typeof(response.tool) ~= "string" or typeof(response.targets) ~= "table" then return end
		local definition = Config.Tools[response.tool]
		local look = ToolPresentation.get(response.tool)
		if not definition or not look then return end
		local stagger = definition.snipStaggerSeconds or 0.07
		local lead = hitLead(response.tool, definition, response.combo == true)
		for i, position in response.targets do
			if typeof(position) == "Vector3" then
				task.delay(lead + (i - 1) * stagger, function()
					local at = position + Vector3.new(0, 2.5, 0)
					Effects.sound(look.sounds.Harvest, at)
					Effects.leafBurst(at, look.vfx.leavesPerStalk, look.vfx.leafColor)
					if look.vfx.snipFlash then Effects.snipFlash(at) end
					local pull = look.vfx.pull
					if pull then
						-- From the front of the curl, the part of the hook that leads the throw.
						local tip = held and held:FindFirstChild("HookCrown", true)
						if tip and tip:IsA("Attachment") then Effects.hookLine(tip, at, pull.lineSeconds) end
						Effects.pullEar(at, pullTarget, pull, if i % 2 == 1 then 1 else -1, function(landedAt)
							Effects.sound(look.sounds.Pull)
							Effects.snipFlash(landedAt)
						end)
					end
				end)
			end
		end
	end)
end

return Controller
