--!strict
-- Presentation for swung tools: the swing, the white glow on the stalks the next swing will
-- cut (HarvestHighlight; replaced the gold rings on the soil, Nov 3 2026) and staggered snips. (The yellow
-- kernels that used to arc out of cut stalks were removed on creator request, Nov 3 2026;
-- the HUD's flying corn icons show the reward instead.) Purely local; the server decides every harvest and reward.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Actions = game:GetService("ContextActionService")
local UserInput = game:GetService("UserInputService")
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
-- (toolId, aim?): one swing, sent only when the swing animation plays (Bootstrap.server,
-- ToolService.swing). aim is the Corn Lasso's aimed stalk; other tools send none.
local swingRequest = Shared:WaitForChild("Remotes"):WaitForChild("ToolSwing") :: RemoteEvent
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
	local anim = ToolAnimator.attach(character, look.holdJoints, look.model.stretch)
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

-- Every character, which the dash's shape cast ignores (the server ignores the same).
local function characters(): { Instance }
	local list: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(list, other.Character) end
	end
	return list
end

-- Corn Lasso (TargetedPull) aim: the camera ray through the mouse (the last touch on phones; the
-- screen centre in first person, where the mouse is locked there) picks the ripe stalk whose
-- middle passes closest to the ray, within AIM_RADIUS of it and the tool's reach of the player.
-- Its position is the aim the server checks (ToolRules.lassoTargets snaps it to the same stalk).
local AIM_RADIUS = 3.5
local function lassoAim(definition: Types.ToolDefinition): Vector3?
	local camera = workspace.CurrentCamera
	local frame = rootFrame()
	if not camera or not frame then return nil end
	local mouse = UserInput:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local best: Vector3? = nil
	local bestOff = AIM_RADIUS
	for _, candidate in myStalks() do
		local p = candidate.position
		local away = Vector3.new(p.X - frame.Position.X, 0, p.Z - frame.Position.Z).Magnitude
		local rel = (p + Vector3.new(0, 1.5, 0)) - ray.Origin
		local along = rel:Dot(ray.Direction)
		if along > 0 and away <= definition.reach then
			local off = (rel - ray.Direction * along).Magnitude
			if off < bestOff then best, bestOff = p, off end
		end
	end
	return best
end

-- Ropes still waiting for the server's answer, oldest first, with where each was aimed.
local pendingThrows: { { effect: Effects.LassoThrow?, aim: Vector3?, at: number } } = {}
-- How many ropes are out; the held loop hides while any is.
local ropesOut = 0

-- Hides (or shows) the loop the lasso holds: the Blender loop mesh, or the part-built loop pieces.
local function showHeldLoop(tool: Tool, look: ToolPresentation.Presentation, visible: boolean)
	local lasso = look.vfx.lasso
	if not lasso then return end
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") and (part.Name == lasso.loopMesh or part:GetAttribute("LassoLoopPiece")) then
			part.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

-- Long-Range Retrieval: at the Throw marker the request goes out with the aim and a rope flies
-- to the aimed ear (or, with nothing to aim at, to the ground ahead). The server's answer
-- (feedback below) decides whether it cinches and brings ears back or reels in empty.
local function lassoThrow(tool: Tool, look: ToolPresentation.Presentation?, aim: Vector3?)
	local frame = rootFrame()
	local lasso = if look then look.vfx.lasso else nil
	local entry = { effect = nil :: Effects.LassoThrow?, aim = aim, at = os.clock() }
	table.insert(pendingThrows, entry)
	if not look or not lasso or not frame then return end
	local anchor = tool:FindFirstChild(lasso.ropePoint, true)
	if not anchor or not anchor:IsA("Attachment") then return end
	local flat = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
	local to = if aim then aim + Vector3.new(0, 2.5, 0)
		else frame.Position + (if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis) * 12 - Vector3.new(0, 2.2, 0)
	ropesOut += 1
	showHeldLoop(tool, look, false)
	entry.effect = Effects.lassoThrow(anchor, to, lasso, function(at)
		Effects.sound(look.sounds.Harvest, at)
		Effects.leafBurst(at, look.vfx.leavesPerStalk, look.vfx.leafColor)
		if look.vfx.snipFlash then Effects.snipFlash(at) end
	end, function(hand)
		Effects.sound(look.sounds.Pull)
		Effects.snipFlash(hand)
	end, function()
		ropesOut = math.max(0, ropesOut - 1)
		if ropesOut == 0 then showHeldLoop(tool, look, true) end
	end)
end

-- The rope a server answer belongs to: for a harvest, the waiting rope aimed nearest its first
-- stalk; otherwise (a refusal carries no stalks) the oldest waiting rope.
local function takeThrow(first: Vector3?): Effects.LassoThrow?
	local clock = os.clock()
	for i = #pendingThrows, 1, -1 do
		if clock - pendingThrows[i].at > 2 then table.remove(pendingThrows, i) end
	end
	local pick = if #pendingThrows > 0 then 1 else nil
	if first then
		local best = math.huge
		for i, entry in pendingThrows do
			local aim = entry.aim
			local d = if aim then Vector3.new(aim.X - first.X, 0, aim.Z - first.Z).Magnitude else math.huge
			if d < best then pick, best = i, d end
		end
	end
	if not pick then return nil end
	return table.remove(pendingThrows, pick).effect
end

-- The latest Spring Dash (DashHarvest): where and when it started, so each confirmed stalk can
-- pop as the player passes it.
local lastDash: { started: number, origin: Vector3, direction: Vector3, speed: number }? = nil

-- Spring Dash: launches the local character straight along its flat facing for the lane the
-- server will harvest (ToolRules.dashReach: reach, or less where a wall would stop it), with a
-- small hop. A LinearVelocity holds the horizontal velocity on the facing line for the whole
-- dash (no steering: the tool's weakness) and leaves gravity alone; it is removed on landing and
-- most of the speed is bled off. Movement only: the server decides what the dash harvests.
local function springDash(tool: Tool, look: ToolPresentation.Presentation?, definition: Types.ToolDefinition)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local spec = definition.dash
	if not spec or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or humanoid.Sit then return end
	local frame = root.CFrame
	local direction = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
	if direction.Magnitude < 1e-3 then return end
	direction = direction.Unit
	local reach = ToolRules.dashReach(frame, definition, characters())
	local seconds = reach / spec.speed
	lastDash = { started = os.clock(), origin = frame.Position, direction = direction, speed = spec.speed }
	local vfx = if look then look.vfx.dash else nil
	if vfx then
		Effects.dashDust(frame, vfx)
		Effects.dashStreak(root, vfx, seconds)
		local tip = tool:FindFirstChild(vfx.sparkPoint, true)
		if tip and tip:IsA("Attachment") then Effects.snipFlash(tip.WorldPosition) end
	end
	if seconds <= 0.02 then return end -- Nose against a wall: the spring fires, nobody moves.
	local attachment = root:FindFirstChild("RootAttachment")
	if not attachment or not attachment:IsA("Attachment") then
		local made = Instance.new("Attachment")
		made.Name = "PopcornDashAttachment"
		made.Parent = root
		attachment = made
	end
	local mover = Instance.new("LinearVelocity")
	mover.Name = "PopcornDash"
	mover.Attachment0 = attachment :: Attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	local force = root.AssemblyMass * 4000
	mover.MaxAxesForce = Vector3.new(force, 0, force) -- Horizontal only: the hop and gravity stay free.
	mover.VectorVelocity = direction * spec.speed
	mover.Parent = root
	root.AssemblyLinearVelocity = direction * spec.speed + Vector3.new(0, spec.hop, 0)
	task.delay(seconds, function()
		mover:Destroy()
		if not root.Parent then return end
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X * 0.25, v.Y, v.Z * 0.25)
		if vfx then Effects.dashDust(root.CFrame, vfx) end
	end)
end

-- The harvesting swing: pose clip, trail on for its duration, swish at the start. Alternating
-- tools play the hand whose turn it is (Swing right, SwingAlt left) or the Combo spin. `send`
-- asks the server to harvest: at once, or for dash tools at the Dash marker, when the lunge
-- starts, so the server's lane starts where the character takes off (and for the lasso at the
-- Throw marker, with the aim taken when the player clicked).
local function swing(tool: Tool, look: ToolPresentation.Presentation?, toolId: string, definition: Types.ToolDefinition, send: (Vector3?) -> ())
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
	-- Corn Lasso: aim at the click (the stalk under the cursor, else the nearest in a cone ahead,
	-- by the server's own rule), turn to face it, twirl, and at the Throw marker send the aim and
	-- throw the rope.
	if definition.behavior == "TargetedPull" then
		local frame = rootFrame()
		local aim = lassoAim(definition)
		if not aim and frame then
			local picked = ToolRules.pickTargets(frame.Position, frame.LookVector, myStalks(), definition)
			for _, candidate in myStalks() do
				if candidate.id == picked[1] then aim = candidate.position break end
			end
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if aim and root and root:IsA("BasePart") and humanoid and not humanoid.Sit then
			local flat = Vector3.new(aim.X, root.Position.Y, aim.Z)
			if (flat - root.Position).Magnitude > 0.5 then root.CFrame = CFrame.lookAt(root.Position, flat) end
		end
		local function fire()
			send(aim)
			lassoThrow(tool, look, aim)
		end
		if animator and clip and clip.markers and clip.markers.Throw then
			animator:play(clip, function(marker)
				if marker == "Throw" and tool.Parent == player.Character then fire() end
			end)
		else
			if animator and clip then animator:play(clip) end
			fire()
		end
		return
	end
	-- Spring-Loaded Picker: the coil winds up, then at the Dash marker the request goes out and the
	-- character lunges. Without a clip or marker both happen at once.
	if definition.behavior == "DashHarvest" then
		local function fire()
			send()
			springDash(tool, look, definition)
		end
		if animator and clip and clip.markers and clip.markers.Dash then
			animator:play(clip, function(marker)
				if marker == "Dash" and tool.Parent == player.Character then fire() end
			end)
		else
			if animator and clip then animator:play(clip) end
			fire()
		end
		return
	end
	send()
	if animator and clip then
		local combo = if look and spin then look.vfx.combo else nil
		-- Long Scythe: the wind trail sweeps round the player as the blade leaves the wind-up.
		local wind = if look and not spin then look.vfx.wind else nil
		-- Hedge Trimmer: grass and sparks off the blade while it runs; at the Hit marker the
		-- trim strip fills the lane the server cuts (same laneWidth, reach and LaneBehind).
		local trim = if look and not spin then look.vfx.trim else nil
		if trim then Effects.bladeSpray(tool, trim) end
		if combo then
			animator:play(clip, function(marker)
				if marker == "Spin" then Effects.comboSweep(rootFrame, combo) end
			end)
		elseif wind then
			animator:play(clip, function(marker)
				if marker == "Sweep" then Effects.windSweep(rootFrame, wind) end
			end)
		elseif trim then
			animator:play(clip, function(marker)
				if marker == "Hit" then
					Effects.trimStrip(rootFrame, trim, definition.laneWidth or 0, definition.reach, ToolRules.LaneBehind)
				end
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
			if look and look.vfx.lasso then showHeldLoop(tool, look, true) end
			if held == tool then
				held, heldId = nil, nil
				stopAnimator()
			end
			Actions:UnbindAction("PopcornSwing")
			Prompts.setHarvestSuppressed(false)
			hideMarkers()
		end)
		tool.Activated:Connect(function()
			-- Clicks during the cooldown do nothing. Only a swing that plays here is sent to the
			-- server, so corn is only ever cut by a swing the player sees (Nov 6 2026; the server
			-- used to swing on every replicated click and accepted some the client never showed).
			if os.clock() - lastSwing < definition.cooldownSeconds then return end
			lastSwing = os.clock()
			swing(tool, look, toolId, definition, function(aim) swingRequest:FireServer(toolId, aim) end)
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
		-- Dash tools: the lane the dash would really cover from here (cut short at a wall).
		local reach = if definition.behavior == "DashHarvest" then ToolRules.dashReach(root.CFrame, definition, characters()) else nil
		-- Targeted tools (Corn Lasso): the stalk under the cursor and the loop's neighbour.
		local aim = if definition.behavior == "TargetedPull" then lassoAim(definition) else nil
		Highlight.setToolTargets(ToolRules.pickTargets(root.Position, root.CFrame.LookVector, myStalks(), definition, shape, reach, aim))
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
		-- Corn Lasso: every answer belongs to a rope in the air. A harvest cinches it round the
		-- confirmed ears; a refusal (no tool id, or nothing taken) reels it back empty.
		local lassoTool = if typeof(response.tool) == "string" then response.tool else heldId
		if lassoTool and Config.Tools[lassoTool] and Config.Tools[lassoTool].behavior == "TargetedPull" then
			local targets: { Vector3 } = {}
			if response.ok and typeof(response.targets) == "table" then
				for _, position in response.targets do
					if typeof(position) == "Vector3" then table.insert(targets, position + Vector3.new(0, 2.5, 0)) end
				end
			end
			local effect = takeThrow(if #targets > 0 then targets[1] - Vector3.new(0, 2.5, 0) else nil)
			if effect then Effects.lassoReply(effect, targets) end
			return
		end
		if not response.ok or typeof(response.tool) ~= "string" or typeof(response.targets) ~= "table" then return end
		local definition = Config.Tools[response.tool]
		local look = ToolPresentation.get(response.tool)
		if not definition or not look then return end
		local stagger = definition.snipStaggerSeconds or 0.07
		local lead = hitLead(response.tool, definition, response.combo == true)
		-- Spring Dash: the reply comes after take-off; each stalk pops when the player reaches it.
		local dash = if definition.behavior == "DashHarvest" then lastDash else nil
		for i, position in response.targets do
			if typeof(position) == "Vector3" then
				local delay = lead + (i - 1) * stagger
				if dash then
					local along = math.max(0, (position - dash.origin):Dot(dash.direction) - 1)
					delay = math.max(0, dash.started + along / dash.speed - os.clock())
				end
				task.delay(delay, function()
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
