--!strict
-- Plays a tool's pose clips (ToolPresentation.clips) on the local character by layering joint
-- rotations over whatever the Animator is playing (walk, the default tool hold), so legs keep
-- walking while the arms swing. One PreSimulation connection per character; no assets to
-- publish. Presentation only: nothing here affects a harvest.
--
-- R15 joints are Motor6Ds on classic rigs and AnimationConstraints on newer avatar rigs; both
-- expose Transform. R6 rigs get the shoulders and neck only. Any other pose name is a Motor6D
-- inside the held Tool (ToolPresentation model.joints, e.g. the clippers' Jaw and Spring).
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local ToolPresentation = require(Shared:WaitForChild("ToolPresentation"))
type Clip = ToolPresentation.Clip
type Pose = ToolPresentation.Pose

local ToolAnimator = {}

local R15: { [string]: { string } } = {
	Waist = { "UpperTorso", "Waist" }, Neck = { "Head", "Neck" },
	RightShoulder = { "RightUpperArm", "RightShoulder" }, RightElbow = { "RightLowerArm", "RightElbow" },
	RightWrist = { "RightHand", "RightWrist" }, LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
	LeftElbow = { "LeftLowerArm", "LeftElbow" }, LeftWrist = { "LeftHand", "LeftWrist" },
	-- The whole body about the root (Y is up): the Twin Sickles' Combo spin. Not on R6.
	Root = { "LowerTorso", "Root" },
}
local R6: { [string]: string } = { RightShoulder = "Right Shoulder", LeftShoulder = "Left Shoulder", Neck = "Neck" }
local EASE: { [string]: Enum.EasingStyle } = {
	Sine = Enum.EasingStyle.Sine, Back = Enum.EasingStyle.Back, Quad = Enum.EasingStyle.Quad, Linear = Enum.EasingStyle.Linear,
}

local function findJoint(character: Model, name: string): Instance?
	local path = R15[name]
	local part = if path then character:FindFirstChild(path[1]) else nil
	local joint = if part and path then part:FindFirstChild(path[2]) else nil
	if not joint and R6[name] then
		local torso = character:FindFirstChild("Torso")
		joint = if torso then torso:FindFirstChild(R6[name]) else nil
	end
	if not joint and not path and not R6[name] then
		local tool = character:FindFirstChildOfClass("Tool")
		joint = if tool then tool:FindFirstChild(name, true) else nil
		if joint and not joint:IsA("Motor6D") then joint = nil end
	end
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then return joint end
	return nil
end

-- The clip's pose at fraction t (0..1): each joint blended between the keys around t.
function ToolAnimator.sample(clip: Clip, t: number): Pose
	local keys = clip.keys
	local i = 1
	while i < #keys - 1 and keys[i + 1].t <= t do i += 1 end
	local a, b = keys[i], keys[math.min(i + 1, #keys)]
	local span = math.max(b.t - a.t, 1e-6)
	local alpha = math.clamp((t - a.t) / span, 0, 1)
	alpha = TweenService:GetValue(alpha, EASE[b.ease or "Sine"], Enum.EasingDirection.InOut)
	local pose: Pose = {}
	-- Rotation (1-3) and the optional translation of tool joints (4-6); missing entries are 0.
	local function blend(name: string)
		if pose[name] then return end
		local from, to = a.pose[name] or {}, b.pose[name] or {}
		local value: { number } = {}
		for k = 1, math.max(3, #from, #to) do
			local x, y = from[k] or 0, to[k] or 0
			value[k] = x + (y - x) * alpha
		end
		pose[name] = value
	end
	for name in a.pose do blend(name) end
	for name in b.pose do blend(name) end
	return pose
end

export type Player = {
	play: (self: Player, clip: Clip, markers: ((string) -> ())?) -> (),
	setIdle: (self: Player, clip: Clip?) -> (),
	stop: (self: Player) -> (),
	playing: (self: Player) -> boolean,
}

-- Starts layering on a character. Call stop() when the tool is put away or the character goes.
function ToolAnimator.attach(character: Model): Player
	local joints: { [string]: any } = {} -- Untyped: Transform lives on two unrelated classes.
	local lastWritten: { [string]: CFrame } = {}
	local lastBase: { [string]: CFrame } = {}
	local idle: Clip? = nil
	local idleStarted = os.clock()
	local active: Clip? = nil
	local activeStarted = 0
	local onMarker: ((string) -> ())? = nil
	local firedMarkers: { [string]: boolean } = {}
	local connection: RBXScriptConnection? = nil

	local function joint(name: string): any
		local found = joints[name]
		if found == nil or not found.Parent then
			found = findJoint(character, name)
			joints[name] = found or false
		end
		return if found then found else nil
	end

	local function apply(pose: Pose, weight: number)
		for name, rotation in pose do
			local j = joint(name)
			if j then
				-- If nothing re-posed this joint since our last write, start from the base we
				-- used then, so rotations never pile up frame after frame.
				local base = if lastWritten[name] and j.Transform == lastWritten[name] then lastBase[name] else j.Transform
				local slide = CFrame.new((rotation[4] or 0) * weight, (rotation[5] or 0) * weight, (rotation[6] or 0) * weight)
				local value = base * slide * CFrame.Angles(math.rad(rotation[1] * weight), math.rad(rotation[2] * weight), math.rad(rotation[3] * weight))
				j.Transform = value
				lastWritten[name], lastBase[name] = value, base
			end
		end
	end

	local function step()
		local now = os.clock()
		local blendIdle = 1
		if active then
			local clip = active :: Clip
			local t = math.clamp((now - activeStarted) / clip.seconds, 0, 1)
			if clip.markers and onMarker then
				for name, at in clip.markers do
					if not firedMarkers[name] and t >= at then
						firedMarkers[name] = true
						task.spawn(onMarker :: (string) -> (), name)
					end
				end
			end
			apply(ToolAnimator.sample(clip, t), 1)
			blendIdle = 0
			if t >= 1 then
				active = nil
				idleStarted = now
			end
		end
		if idle and blendIdle > 0 then
			local clip = idle :: Clip
			local t = ((now - idleStarted) / clip.seconds) % 1
			-- Ease the idle back in over 0.2 s after a one-shot so it never snaps.
			apply(ToolAnimator.sample(clip, t), math.clamp((now - idleStarted) / 0.2, 0, 1))
		end
	end

	local player = {} :: any
	function player.play(_, clip: Clip, markers: ((string) -> ())?)
		active, activeStarted, onMarker, firedMarkers = clip, os.clock(), markers, {}
	end
	function player.setIdle(_, clip: Clip?)
		idle, idleStarted = clip, os.clock()
	end
	function player.playing(): boolean
		return active ~= nil
	end
	function player.stop()
		if connection then connection:Disconnect() end
		connection = nil
		active, idle = nil, nil
	end
	connection = RunService.PreSimulation:Connect(step)
	return player :: Player
end

return ToolAnimator
