--!strict
-- Local sounds and particle bursts for harvesting tools. Effects are pooled: one leaf emitter
-- is moved and told to Emit for every burst, so a swing never creates Parts or emitters.
-- Bursts beyond FAR studs from the camera are skipped and halved past NEAR (distance LOD).
-- Presentation only: the server has already decided the harvest when these play.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local ToolPresentation = require(Shared:WaitForChild("ToolPresentation"))
local ToolEffects = {}

local NEAR, FAR = 60, 120
-- Global multiplier on every burst count; a future "reduced effects" setting can lower it.
ToolEffects.particleScale = 1
local rng = Random.new()

-- One-shot sound, 3D at a world position or 2D for the holder. Pitch varies a little so
-- repeats never sound identical. Missing ids (not yet uploaded, no fallback) play nothing.
function ToolEffects.sound(sound: ToolPresentation.Sound?, at: Vector3?)
	if not sound then return end
	local id = ToolPresentation.soundId(sound)
	if not id then return end
	local holder: Instance = workspace
	local anchor: Attachment? = nil
	if at then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = at
		attachment.Parent = workspace.Terrain
		anchor, holder = attachment, attachment
	end
	local s = Instance.new("Sound")
	s.SoundId, s.Volume = id, sound.volume
	s.PlaybackSpeed = rng:NextNumber(sound.pitch[1], sound.pitch[2])
	s.RollOffMinDistance, s.RollOffMaxDistance = 6, 60
	s.Parent = holder
	s:Play()
	local target: Instance = anchor or s
	s.Ended:Once(function() target:Destroy() end)
	task.delay(4, function() if target.Parent then target:Destroy() end end)
end

local leafEmitter: ParticleEmitter? = nil
local leafAnchor: Attachment? = nil
local function leaves(): (Attachment, ParticleEmitter)
	if leafAnchor and leafAnchor.Parent and leafEmitter then return leafAnchor, leafEmitter end
	local anchor = Instance.new("Attachment")
	anchor.Name = "PopcornToolLeaves"
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = ToolPresentation.Textures.LeafFleck
	emitter.Enabled = false
	emitter.Lifetime = NumberRange.new(0.45, 0.75)
	emitter.Speed = NumberRange.new(7, 12)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Acceleration = Vector3.new(0, -26, 0)
	emitter.Drag = 2.5
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-320, 320)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.35) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LightInfluence = 0.6
	emitter.Parent = anchor
	anchor.Parent = workspace.Terrain
	leafAnchor, leafEmitter = anchor, emitter
	return anchor, emitter
end

local flashEmitter: ParticleEmitter? = nil
local flashAnchor: Attachment? = nil
local function flashes(): (Attachment, ParticleEmitter)
	if flashAnchor and flashAnchor.Parent and flashEmitter then return flashAnchor, flashEmitter end
	local anchor = Instance.new("Attachment")
	anchor.Name = "PopcornToolFlash"
	local emitter = Instance.new("ParticleEmitter")
	-- Built-in Roblox sparkle texture (ships with the client; nothing to upload).
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Enabled = false
	emitter.Lifetime = NumberRange.new(0.12, 0.16)
	emitter.Speed = NumberRange.new(0)
	emitter.Rotation = NumberRange.new(0, 90)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.35, 1.3), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.LightEmission, emitter.LightInfluence = 1, 0
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Parent = anchor
	anchor.Parent = workspace.Terrain
	flashAnchor, flashEmitter = anchor, emitter
	return anchor, emitter
end

-- A tiny white sparkle where a blade snipped a stalk (one pooled emitter, like the leaves).
function ToolEffects.snipFlash(at: Vector3)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - at).Magnitude > NEAR then return end
	if ToolEffects.particleScale <= 0 then return end
	local anchor, emitter = flashes()
	anchor.WorldPosition = at
	emitter:Emit(1)
end

-- Hook Pull (Harvest Hook): pooled corn ears fly a curved path from the stalk back to the
-- holder. At most EAR_POOL ears exist; a pull with every ear busy is skipped. One Heartbeat
-- connection moves every ear with BulkMoveTo and disconnects when none are flying.
local RunService = game:GetService("RunService")
local EAR_POOL = 6
local PARKED = CFrame.new(0, -5000, 0)
type Ear = { parts: { BasePart }, offsets: { CFrame }, trail: Trail, busy: boolean }
type Flight = {
	ear: Ear, from: Vector3, bow: Vector3, target: () -> Vector3?, last: Vector3,
	started: number, seconds: number, spin: number, landed: (Vector3) -> (),
}
local ears: { Ear } = {}
local flights: { Flight } = {}
local mover: RBXScriptConnection? = nil
local fxFolder: Folder? = nil

local function folder(): Folder
	if fxFolder and fxFolder.Parent then return fxFolder end
	local f = Instance.new("Folder")
	f.Name = "PopcornToolFx"
	f.Parent = workspace
	fxFolder = f
	return f
end

-- A chunky toy ear: a gold cob with a rounded tip and two pale husk leaves, pointing along -Z.
-- Hook Pull and Corn Lasso ears share the pool; both looks carry the ear colours.
type EarLook = { earColor: Color3, huskColor: Color3, trailColors: { Color3 } }
local function newEar(pull: EarLook): Ear
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local function add(shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Shape, p.Size, p.Color, p.Material = shape, size, color, material
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.CFrame = PARKED * offset
		p.Parent = folder()
		table.insert(parts, p)
		table.insert(offsets, offset)
		return p
	end
	local cob = add(Enum.PartType.Cylinder, Vector3.new(0.85, 0.44, 0.44), CFrame.Angles(0, math.rad(90), 0), pull.earColor, Enum.Material.Pebble)
	add(Enum.PartType.Ball, Vector3.new(0.44, 0.44, 0.44), CFrame.new(0, 0, -0.42), pull.earColor, Enum.Material.Pebble)
	for _, side in { 1, -1 } do
		add(Enum.PartType.Block, Vector3.new(0.05, 0.3, 0.8), CFrame.new(0.16 * side, 0, 0.2) * CFrame.Angles(0, math.rad(-14 * side), 0),
			pull.huskColor, Enum.Material.SmoothPlastic)
	end
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 0.2, 0), Vector3.new(0, -0.2, 0)
	a0.Parent, a1.Parent = cob, cob
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime, trail.MinLength, trail.Enabled = 0.22, 0.05, false
	trail.Color = ColorSequence.new(pull.trailColors[1], pull.trailColors[#pull.trailColors])
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.LightEmission, trail.FaceCamera = 0.6, true
	trail.Parent = cob
	return { parts = parts, offsets = offsets, trail = trail, busy = false }
end

local function place(ear: Ear, frame: CFrame)
	local cframes = table.create(#ear.parts)
	for i, offset in ear.offsets do cframes[i] = frame * offset end
	workspace:BulkMoveTo(ear.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function park(ear: Ear)
	ear.trail.Enabled = false
	ear.trail:Clear()
	place(ear, PARKED)
	ear.busy = false
end

local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

local function step()
	local clock = os.clock()
	for i = #flights, 1, -1 do
		local f = flights[i]
		local to = f.target() or f.last
		f.last = to
		local t = math.clamp((clock - f.started) / f.seconds, 0, 1)
		-- Yanked: slow off the stalk, fastest as it comes in.
		local eased = t ^ 1.35
		-- The bow is fixed when the hook bites; the end follows the player as they move.
		local control = (f.from + to) / 2 + f.bow
		local at = bezier(f.from, control, to, eased)
		local ahead = bezier(f.from, control, to, math.min(1, eased + 0.05))
		local heading = if (ahead - at).Magnitude > 1e-3 then ahead else at + (to - f.from)
		place(f.ear, CFrame.lookAt(at, heading) * CFrame.Angles(0, 0, f.spin * t))
		if t >= 1 then
			table.remove(flights, i)
			park(f.ear)
			f.landed(to)
		end
	end
	if #flights == 0 and mover then
		mover:Disconnect()
		mover = nil
	end
end

-- Flies one ear from `from` to wherever `target()` is (the holder), bowing up and to one side
-- (side = 1 or -1, so two ears split left and right). `landed` runs when it arrives.
function ToolEffects.pullEar(from: Vector3, target: () -> Vector3?, pull: ToolPresentation.PullVfx, side: number, landed: (Vector3) -> ())
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - from).Magnitude > FAR then return end
	if ToolEffects.particleScale <= 0 then return end
	local to = target()
	if not to then return end
	local ear: Ear? = nil
	for _, candidate in ears do
		if not candidate.busy and candidate.parts[1].Parent then
			ear = candidate
			break
		end
	end
	if not ear and #ears < EAR_POOL then
		ear = newEar(pull)
		table.insert(ears, ear :: Ear)
	end
	if not ear then return end
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local across = if flat.Magnitude > 1e-3 then flat.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	local bow = Vector3.new(0, pull.rise, 0) + across * pull.sideways * side
	ear.busy = true
	place(ear, CFrame.lookAt(from, to))
	ear.trail:Clear()
	ear.trail.Enabled = true
	table.insert(flights, {
		ear = ear, from = from, bow = bow, target = target, last = to, started = os.clock(),
		seconds = pull.flySeconds, spin = math.rad(rng:NextNumber(300, 540) * side), landed = landed,
	})
	if not mover then mover = RunService.Heartbeat:Connect(step) end
end

-- A thin streak from the thrown hook to a stalk, so the long reach reads. Pooled beams (one per
-- simultaneous target); each fades after `seconds`.
local LINE_POOL = 3
type Line = { beam: Beam, far: Attachment, token: number }
local lines: { Line } = {}
local nextLine = 0
function ToolEffects.hookLine(from: Attachment, to: Vector3, seconds: number)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - to).Magnitude > NEAR then return end
	if ToolEffects.particleScale <= 0 or seconds <= 0 then return end
	nextLine = nextLine % LINE_POOL + 1
	local line = lines[nextLine]
	if not line or not line.far.Parent then
		local far = Instance.new("Attachment")
		far.Name = "PopcornHookLine"
		far.Parent = workspace.Terrain
		local beam = Instance.new("Beam")
		beam.Width0, beam.Width1 = 0.16, 0.05
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 250, 232), Color3.fromRGB(255, 214, 90))
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.55) })
		beam.LightEmission, beam.FaceCamera, beam.Segments = 0.5, true, 12
		beam.Enabled = false
		beam.Parent = far
		line = { beam = beam, far = far, token = 0 }
		lines[nextLine] = line
	end
	local l = line :: Line
	l.far.WorldPosition = to
	l.beam.Attachment0, l.beam.Attachment1 = from, l.far
	-- A slight upward sag, like a thrown line.
	l.beam.CurveSize0, l.beam.CurveSize1 = 1.2, -0.6
	l.beam.Enabled = true
	l.token += 1
	local token = l.token
	task.delay(seconds, function()
		if l.token == token then l.beam.Enabled = false end
	end)
end

-- Combo Sweep (Twin Sickles): two glowing ribbons whirl once round the player during the spin,
-- half a turn apart, like the two swirls in the reference render. Each is a Trail between two
-- attachments on a pooled invisible part (radius -/+ width/2 out from the centre); one
-- Heartbeat connection turns both and disconnects when the turn ends. A new combo restarts it.
type Spinner = { part: BasePart, inner: Attachment, outer: Attachment, trail: Trail }
local spinners: { Spinner } = {}
local spinner: RBXScriptConnection? = nil

local function newSpinner(): Spinner
	local part = Instance.new("Part")
	part.Name = "PopcornComboSweep"
	part.Size, part.Transparency = Vector3.new(0.2, 0.2, 0.2), 1
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.CFrame = PARKED
	part.Parent = folder()
	local inner, outer = Instance.new("Attachment"), Instance.new("Attachment")
	inner.Parent, outer.Parent = part, part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = inner, outer
	trail.Lifetime, trail.MinLength, trail.Enabled = 0.24, 0.05, false
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission, trail.FaceCamera = 0.8, false
	trail.Parent = part
	return { part = part, inner = inner, outer = outer, trail = trail }
end

-- `centre` gives the player's root frame each frame (nil once they are gone).
function ToolEffects.comboSweep(centre: () -> CFrame?, spec: ToolPresentation.ComboVfx)
	if ToolEffects.particleScale <= 0 then return end
	local start = centre()
	if not start then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - start.Position).Magnitude > FAR then return end
	for i = 1, 2 do
		if not spinners[i] or not spinners[i].part.Parent then spinners[i] = newSpinner() end
	end
	local look = start.LookVector
	local yaw0 = math.atan2(-look.X, -look.Z)
	local started = os.clock()
	local last = start
	local function place(turn: number)
		local at = centre() or last
		last = at
		for i, s in spinners do
			-- Increasing yaw turns counter-clockwise seen from above, the way the body spins.
			s.part.CFrame = CFrame.new(at.Position + Vector3.new(0, spec.height, 0)) * CFrame.Angles(0, yaw0 + turn + (i - 1) * math.pi, 0)
		end
	end
	place(0)
	for i, s in spinners do
		s.inner.Position = Vector3.new(spec.radius - spec.width / 2, 0, 0)
		s.outer.Position = Vector3.new(spec.radius + spec.width / 2, 0, 0)
		s.trail.Color = ColorSequence.new(spec.colors[math.min(i, #spec.colors)], Color3.new(1, 1, 1))
		s.trail:Clear()
		s.trail.Enabled = true
	end
	if spinner then spinner:Disconnect() end
	spinner = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - started) / spec.seconds, 0, 1)
		place(2 * math.pi * t)
		if t >= 1 then
			for _, s in spinners do s.trail.Enabled = false end
			if spinner then spinner:Disconnect() end
			spinner = nil
		end
	end)
end

-- Wind trail (Long Scythe's Great Harvest): pale ribbons, one per radius in spec.radii, sweep
-- spec.degrees round the player from their right, through the front, to their left in
-- spec.seconds. Same pooled-part-and-Trail build as the combo spinners, in a pool of its own
-- (at most 3), and one Heartbeat connection that disconnects when the sweep ends.
local gusts: { Spinner } = {}
local gust: RBXScriptConnection? = nil

function ToolEffects.windSweep(centre: () -> CFrame?, spec: ToolPresentation.WindVfx)
	if ToolEffects.particleScale <= 0 then return end
	local start = centre()
	if not start then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - start.Position).Magnitude > FAR then return end
	local count = math.min(#spec.radii, 3)
	for i = 1, count do
		if not gusts[i] or not gusts[i].part.Parent then
			gusts[i] = newSpinner()
			gusts[i].part.Name = "PopcornWindSweep"
			gusts[i].trail.Lifetime = 0.3
		end
	end
	-- The facing at the start of the sweep; the ribbons keep to it even if the player turns.
	local look = start.LookVector
	local yaw0 = math.atan2(-look.X, -look.Z)
	local sweep = math.rad(spec.degrees)
	local started = os.clock()
	local last = start
	local function place(turn: number)
		local at = centre() or last
		last = at
		for i = 1, count do
			-- Attachments sit on local +X: the player's right at turn 0. Increasing yaw turns
			-- counter-clockwise seen from above: right -> front -> left.
			gusts[i].part.CFrame = CFrame.new(at.Position + Vector3.new(0, spec.height, 0)) * CFrame.Angles(0, yaw0 + turn + (math.pi - sweep) / 2, 0)
		end
	end
	place(0)
	for i = 1, count do
		local g, radius = gusts[i], spec.radii[i]
		g.inner.Position = Vector3.new(radius - spec.width / 2, 0, 0)
		g.outer.Position = Vector3.new(radius + spec.width / 2, 0, 0)
		g.trail.Color = ColorSequence.new(spec.colors[math.min(i, #spec.colors)], Color3.new(1, 1, 1))
		g.trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25 + 0.15 * (i - 1)), NumberSequenceKeypoint.new(1, 1) })
		g.trail:Clear()
		g.trail.Enabled = true
	end
	for i = count + 1, #gusts do gusts[i].trail.Enabled = false end
	if gust then gust:Disconnect() end
	gust = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - started) / spec.seconds, 0, 1)
		-- Ease out: the blade is fastest as it leaves the wind-up.
		place(sweep * (1 - (1 - t) ^ 2))
		if t >= 1 then
			for _, g in gusts do g.trail.Enabled = false end
			if gust then gust:Disconnect() end
			gust = nil
		end
	end)
end

-- Trim strip (Hedge Trimmer's Precision Cutting): one pooled flat part on the ground in the
-- shape of the tool's lane (laneWidth wide, from `behind` studs behind the player to `reach`
-- ahead). It fills from the back edge outward in spec.seconds, then fades over
-- spec.fadeSeconds. It stays where it was laid down (a cut mark), even if the player turns.
-- One Heartbeat connection while it shows; a new trim restarts it.
local strip: BasePart? = nil
local stripMover: RBXScriptConnection? = nil

local function groundUnder(root: CFrame): number
	local params = RaycastParams.new()
	local ignore: { Instance } = { folder() }
	local character = game:GetService("Players").LocalPlayer.Character
	if character then table.insert(ignore, character) end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	return if hit then hit.Position.Y else root.Position.Y - 3
end

function ToolEffects.trimStrip(centre: () -> CFrame?, spec: ToolPresentation.TrimVfx, laneWidth: number, reach: number, behind: number)
	if ToolEffects.particleScale <= 0 then return end
	local start = centre()
	if not start then return end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - start.Position).Magnitude > FAR then return end
	local part = strip
	if not part or not part.Parent then
		local p = Instance.new("Part")
		p.Name = "PopcornTrimStrip"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Parent = folder()
		part = p
		strip = p
	end
	local s = part :: BasePart
	s.Color = spec.color
	local look = Vector3.new(start.LookVector.X, 0, start.LookVector.Z)
	if look.Magnitude < 1e-3 then return end
	look = look.Unit
	local y = groundUnder(start) + 0.08
	local back = Vector3.new(start.Position.X, y, start.Position.Z) - look * behind
	local length = behind + reach
	local frame = CFrame.lookAt(back, back + look)
	local started = os.clock()
	local function place(fill: number, transparency: number)
		local l = math.max(length * fill, 0.05)
		s.Size = Vector3.new(laneWidth, 0.1, l)
		s.CFrame = frame * CFrame.new(0, 0, -l / 2)
		s.Transparency = transparency
	end
	place(0, spec.transparency)
	if stripMover then stripMover:Disconnect() end
	stripMover = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - started
		if elapsed < spec.seconds then
			local t = elapsed / spec.seconds
			place(1 - (1 - t) ^ 2, spec.transparency)
		else
			local fadeT = math.clamp((elapsed - spec.seconds) / spec.fadeSeconds, 0, 1)
			place(1, spec.transparency + (1 - spec.transparency) * fadeT)
			if fadeT >= 1 then
				s.CFrame = PARKED
				if stripMover then stripMover:Disconnect() end
				stripMover = nil
			end
		end
	end)
end

-- Spring Dash dust (Spring-Loaded Picker): a low ring of dust puffs on the ground under the
-- player at take-off and landing. One pooled emitter (built-in smoke texture, nothing to upload),
-- moved and told to Emit, like the leaves.
local dustEmitter: ParticleEmitter? = nil
local dustAnchor: Attachment? = nil
function ToolEffects.dashDust(root: CFrame, spec: ToolPresentation.DashVfx)
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - root.Position).Magnitude else 0
	if distance > FAR or ToolEffects.particleScale <= 0 then return end
	if not (dustAnchor and dustAnchor.Parent and dustEmitter) then
		local anchor = Instance.new("Attachment")
		anchor.Name = "PopcornDashDust"
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Enabled = false
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(5, 9)
		-- Out sideways along the ground, a little up.
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(80, 80)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Drag = 5
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.LightInfluence = 0.8
		e.Parent = anchor
		anchor.Parent = workspace.Terrain
		dustAnchor, dustEmitter = anchor, e
	end
	local anchor, e = dustAnchor :: Attachment, dustEmitter :: ParticleEmitter
	e.Color = ColorSequence.new(spec.dustColor)
	anchor.WorldPosition = Vector3.new(root.Position.X, groundUnder(root) + 0.3, root.Position.Z)
	local n = math.floor(spec.dustCount * ToolEffects.particleScale * (if distance > NEAR then 0.5 else 1) + 0.5)
	if n > 0 then e:Emit(n) end
end

-- Spring Dash streak: a ribbon trailing the player's body for the length of the dash. One Trail
-- per character, made once (local only) between two attachments on the root part, spec.width
-- studs apart vertically, and switched on for `seconds` plus a little.
function ToolEffects.dashStreak(root: BasePart, spec: ToolPresentation.DashVfx, seconds: number)
	if ToolEffects.particleScale <= 0 or seconds <= 0 then return end
	local trail = root:FindFirstChild("PopcornDashStreak")
	if not (trail and trail:IsA("Trail")) then
		local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
		top.Name, top.Position, top.Parent = "PopcornDashTop", Vector3.new(0, spec.width / 2, 0.4), root
		bottom.Name, bottom.Position, bottom.Parent = "PopcornDashBottom", Vector3.new(0, -spec.width / 2, 0.4), root
		local made = Instance.new("Trail")
		made.Name = "PopcornDashStreak"
		made.Attachment0, made.Attachment1 = top, bottom
		made.MinLength, made.FaceCamera, made.LightEmission = 0.1, false, 0.5
		made.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		made.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.3) })
		made.Enabled = false
		made.Parent = root
		trail = made
	end
	local t = trail :: Trail
	t.Lifetime = spec.trailSeconds
	t.Color = ColorSequence.new(spec.trailColors[1], spec.trailColors[#spec.trailColors])
	t.Enabled = true
	local token = os.clock()
	t:SetAttribute("DashToken", token)
	task.delay(seconds + 0.05, function()
		if t.Parent and t:GetAttribute("DashToken") == token then t.Enabled = false end
	end)
end

-- Blade spray (Hedge Trimmer): grass flecks from spec.sprayPoint and small sparks from
-- spec.sparkPoint on the held tool for spec.spraySeconds. The two emitters are made once per
-- tool (local only, inside its attachments) and switched on and off; at most a few dozen
-- particles per trim.
local function sprayEmitter(attachment: Attachment, name: string, build: (ParticleEmitter) -> ()): ParticleEmitter
	local existing = attachment:FindFirstChild(name)
	if existing and existing:IsA("ParticleEmitter") then return existing end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name, emitter.Enabled = name, false
	build(emitter)
	emitter.Parent = attachment
	return emitter
end

function ToolEffects.bladeSpray(tool: Tool, spec: ToolPresentation.TrimVfx)
	if ToolEffects.particleScale <= 0 then return end
	local spray = tool:FindFirstChild(spec.sprayPoint, true)
	local spark = tool:FindFirstChild(spec.sparkPoint, true)
	local camera = workspace.CurrentCamera
	if not (spray and spray:IsA("Attachment")) then return end
	if camera and (camera.CFrame.Position - spray.WorldPosition).Magnitude > NEAR then return end
	local emitters: { ParticleEmitter } = {}
	table.insert(emitters, sprayEmitter(spray, "TrimSpray", function(e)
		e.Texture = ToolPresentation.Textures.LeafFleck
		e.Color = ColorSequence.new(spec.sprayColor)
		e.Rate = 45 * ToolEffects.particleScale
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(6, 10)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Acceleration = Vector3.new(0, -24, 0)
		e.Drag = 3
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-360, 360)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1) })
		e.EmissionDirection = Enum.NormalId.Top
		e.LightInfluence = 0.6
	end))
	if spark and spark:IsA("Attachment") then
		table.insert(emitters, sprayEmitter(spark, "TrimSparks", function(e)
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(spec.sparkColor)
			e.Rate = 30 * ToolEffects.particleScale
			e.Lifetime = NumberRange.new(0.12, 0.25)
			e.Speed = NumberRange.new(5, 9)
			e.SpreadAngle = Vector2.new(80, 80)
			e.Acceleration = Vector3.new(0, -30, 0)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
			e.LightEmission, e.LightInfluence = 1, 0
		end))
	end
	for _, e in emitters do e.Enabled = true end
	local token = os.clock()
	tool:SetAttribute("SprayToken", token)
	task.delay(spec.spraySeconds, function()
		if tool:GetAttribute("SprayToken") ~= token then return end
		for _, e in emitters do
			if e.Parent then e.Enabled = false end
		end
	end)
end

-- A small burst of leaf flecks where a stalk was cut.
function ToolEffects.leafBurst(at: Vector3, count: number, color: Color3?)
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - at).Magnitude else 0
	if distance > FAR then return end
	local n = math.floor(count * ToolEffects.particleScale * (if distance > NEAR then 0.5 else 1) + 0.5)
	if n <= 0 then return end
	local anchor, emitter = leaves()
	emitter.Color = ColorSequence.new(color or Color3.new(1, 1, 1))
	anchor.WorldPosition = at
	emitter:Emit(n)
end


-- Long-Range Retrieval (Corn Lasso): a rope loop flies from the lasso to the aimed ear, waits for
-- the server, cinches round each confirmed ear, and the ears ride the rope back to the hand. At
-- most ROPE_POOL ropes exist (throws overlap: the cycle outlasts the 0.4 s cooldown); a throw
-- with every rope busy is skipped. Each rope is LOOP_PARTS short cylinder segments laid round a
-- ring (resized as the loop opens and cinches), a knot and a Beam from the lasso's rope point
-- to the knot. Ears come from the Hook Pull's pool. One Heartbeat connection moves every rope
-- with BulkMoveTo and disconnects when none are out. Presentation only: the server has
-- already decided what the throw took; a refused throw reels back an empty loop.
local ROPE_POOL = 3
local LOOP_PARTS = 10
type Rope = { parts: { BasePart }, knot: BasePart, beam: Beam, far: Attachment, busy: boolean, radius: number }
type Phase = "out" | "wait" | "cinch" | "back"
export type LassoThrow = {
	rope: Rope, spec: ToolPresentation.LassoVfx, anchor: Attachment, start: Vector3, to: Vector3,
	started: number, flight: number, phase: Phase, phaseAt: number, targets: { Vector3 }?,
	ears: { Ear }, hand: Vector3, spin: number, done: () -> (), cinched: (Vector3) -> (), caught: (Vector3) -> (),
}
local ropes: { Rope } = {}
local throws: { LassoThrow } = {}
local lassoMover: RBXScriptConnection? = nil

local function newRope(spec: ToolPresentation.LassoVfx): Rope
	local parts: { BasePart } = {}
	for i = 1, LOOP_PARTS do
		local p = Instance.new("Part")
		p.Name = "PopcornLassoLoop"
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.4, spec.ropeWidth, spec.ropeWidth)
		p.Color = if i % 2 == 0 then spec.ropeShade else spec.ropeColor
		p.Material = Enum.Material.Fabric
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.CFrame = PARKED
		p.Parent = folder()
		table.insert(parts, p)
	end
	local knot = Instance.new("Part")
	knot.Name = "PopcornLassoKnot"
	knot.Size = Vector3.new(0.24, 0.24, 0.3)
	knot.Color, knot.Material = spec.ropeShade, Enum.Material.Fabric
	knot.Anchored, knot.CanCollide, knot.CanQuery, knot.CanTouch, knot.CastShadow = true, false, false, false, false
	knot.CFrame = PARKED
	knot.Parent = folder()
	local far = Instance.new("Attachment")
	far.Name = "PopcornLassoEnd"
	far.Parent = workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Width0, beam.Width1 = spec.ropeWidth, spec.ropeWidth
	beam.Color = ColorSequence.new(spec.ropeColor, spec.ropeShade)
	beam.Transparency = NumberSequence.new(0)
	beam.LightEmission, beam.LightInfluence, beam.FaceCamera, beam.Segments = 0, 1, true, 16
	beam.Enabled = false
	beam.Attachment1 = far
	beam.Parent = far
	return { parts = parts, knot = knot, beam = beam, far = far, busy = false, radius = -1 }
end

-- Lays the rope's loop round `centre` (normal `up`, turned by `spin`) at `radius`, with the knot
-- on the side facing `toward`, and puts the rope's far end on the knot.
local function layLoop(rope: Rope, centre: Vector3, up: Vector3, radius: number, spin: number, toward: Vector3, width: number)
	local flat = toward - centre
	flat -= up * flat:Dot(up)
	local u = if flat.Magnitude > 1e-3 then flat.Unit else up:Cross(Vector3.xAxis).Unit
	local w = up:Cross(u)
	if math.abs(radius - rope.radius) > 0.005 then
		local length = 2 * math.pi * radius / LOOP_PARTS * 1.12
		for _, p in rope.parts do p.Size = Vector3.new(length, width, width) end
		rope.radius = radius
	end
	local cframes = table.create(LOOP_PARTS + 1)
	for i = 1, LOOP_PARTS do
		local a0 = spin + 2 * math.pi * (i - 1) / LOOP_PARTS
		local a1 = spin + 2 * math.pi * i / LOOP_PARTS
		local p0 = centre + (u * math.cos(a0) + w * math.sin(a0)) * radius
		local p1 = centre + (u * math.cos(a1) + w * math.sin(a1)) * radius
		cframes[i] = CFrame.lookAt((p0 + p1) / 2, p1, up) * CFrame.Angles(0, math.rad(90), 0)
	end
	local knotAt = centre + u * radius
	cframes[LOOP_PARTS + 1] = CFrame.lookAt(knotAt, knotAt + u, up)
	local all = table.clone(rope.parts)
	table.insert(all, rope.knot)
	workspace:BulkMoveTo(all, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	-- The far end's axis points up, so a positive CurveSize1 sags the rope just short of the knot.
	local side = u:Cross(Vector3.yAxis)
	rope.far.WorldCFrame = CFrame.fromMatrix(knotAt, Vector3.yAxis, if side.Magnitude > 1e-3 then side.Unit else Vector3.zAxis)
end

local function parkRope(rope: Rope)
	rope.beam.Enabled = false
	local all = table.clone(rope.parts)
	table.insert(all, rope.knot)
	workspace:BulkMoveTo(all, table.create(#all, PARKED), Enum.BulkMoveMode.FireCFrameChanged)
	rope.busy = false
end

local function freeEar(look: ToolPresentation.LassoVfx): Ear?
	for _, candidate in ears do
		if not candidate.busy and candidate.parts[1].Parent then return candidate end
	end
	if #ears < EAR_POOL then
		local ear = newEar(look)
		table.insert(ears, ear)
		return ear
	end
	return nil
end

local function lassoStep()
	local clock = os.clock()
	for i = #throws, 1, -1 do
		local th = throws[i]
		local spec = th.spec
		if th.anchor.Parent then th.hand = th.anchor.WorldPosition end
		local radius, centre, finished = spec.openRadius, th.to, false
		local sag = 0
		if th.phase == "out" then
			local t = math.clamp((clock - th.started) / th.flight, 0, 1)
			local lift = Vector3.new(0, spec.rise * (th.to - th.start).Magnitude / 10, 0)
			centre = bezier(th.start, (th.start + th.to) / 2 + lift, th.to, t)
			radius = spec.cinchRadius + (spec.openRadius - spec.cinchRadius) * math.min(1, t * 1.8)
			th.spin = spec.spinTurns * 2 * math.pi * t
			sag = 0.35
			if t >= 1 then th.phase, th.phaseAt = "wait", clock end
		elseif th.phase == "wait" then
			-- Hovering over the ear, settling a little, until the server answers.
			centre = th.to - Vector3.new(0, 0.25 * math.clamp((clock - th.phaseAt) / 0.25, 0, 1), 0)
			sag = 0.5
			local targets = th.targets
			if targets then
				th.phase, th.phaseAt = if #targets > 0 then "cinch" else "back", clock
				for k, at in targets do
					th.cinched(at)
					local ear = freeEar(spec)
					if ear then
						ear.busy = true
						place(ear, CFrame.new(at))
						ear.trail:Clear()
						ear.trail.Enabled = true
						th.ears[k] = ear
					end
				end
				if #targets == 0 then th.to = centre end
			elseif clock - th.phaseAt > spec.waitSeconds then
				th.targets = {}
				th.phase, th.phaseAt = "back", clock
				th.to = centre
			end
		elseif th.phase == "cinch" then
			local t = math.clamp((clock - th.phaseAt) / spec.cinchSeconds, 0, 1)
			centre = th.to - Vector3.new(0, 0.25, 0)
			radius = spec.openRadius + (spec.cinchRadius - spec.openRadius) * (t ^ 0.6)
			sag = 0.5 * (1 - t)
			local back = (th.hand - centre)
			back = if back.Magnitude > 1e-3 then back.Unit else Vector3.zAxis
			for k, ear in th.ears do
				-- Snagged neighbours hop into the loop behind the aimed ear, which is already in it.
				local from = (th.targets :: { Vector3 })[k]
				local at = if k == 1 then centre else from:Lerp(centre - back * 0.6 * (k - 1), t)
				place(ear, CFrame.lookAt(at, at + back))
			end
			if t >= 1 then
				th.phase, th.phaseAt = "back", clock
				th.to = centre
			end
		else
			-- Back along the tightened rope to the hand (followed as the player moves).
			local t = math.clamp((clock - th.phaseAt) / spec.backSeconds, 0, 1)
			local eased = t ^ 1.25
			local from = th.to
			centre = from:Lerp(th.hand, eased) + Vector3.new(0, math.sin(math.pi * eased) * 0.6, 0)
			radius = if #th.ears > 0 then spec.cinchRadius else spec.openRadius * (1 - 0.5 * t)
			th.spin += 0.05
			local dir = th.hand - from
			for k, ear in th.ears do
				local u = math.clamp(eased - 0.12 * (k - 1), 0, 1)
				local at = from:Lerp(th.hand, u) + Vector3.new(0, math.sin(math.pi * u) * 0.6, 0)
				place(ear, CFrame.lookAt(at, at + dir) * CFrame.Angles(0, 0, 6 * t))
			end
			if t >= 1 then finished = true end
		end
		if finished then
			table.remove(throws, i)
			for _, ear in th.ears do park(ear) end
			if #th.ears > 0 then th.caught(th.hand) end
			parkRope(th.rope)
			th.done()
		else
			layLoop(th.rope, centre, Vector3.yAxis, radius, th.spin, th.hand, spec.ropeWidth)
			local span = (centre - th.hand).Magnitude
			th.rope.beam.CurveSize0 = span * 0.18
			th.rope.beam.CurveSize1 = span * sag * 0.12
		end
	end
	if #throws == 0 and lassoMover then
		lassoMover:Disconnect()
		lassoMover = nil
	end
end

-- Throws a rope from `anchor` (the lasso's rope point) to `to` (the aimed ear, or a spot on the
-- ground for a throw at nothing). `cinched(at)` runs for each confirmed stalk as the loop
-- tightens, `caught(hand)` once when the ears reach the hand, `done()` when the rope is back
-- (always, even for a skipped throw, so the held loop reappears). Returns nil when skipped.
function ToolEffects.lassoThrow(anchor: Attachment, to: Vector3, spec: ToolPresentation.LassoVfx,
	cinched: (Vector3) -> (), caught: (Vector3) -> (), done: () -> ()): LassoThrow?
	local camera = workspace.CurrentCamera
	local start = anchor.WorldPosition
	if (camera and (camera.CFrame.Position - start).Magnitude > FAR) or ToolEffects.particleScale <= 0 then
		done()
		return nil
	end
	local rope: Rope? = nil
	for _, candidate in ropes do
		if not candidate.busy and candidate.knot.Parent then
			rope = candidate
			break
		end
	end
	if not rope and #ropes < ROPE_POOL then
		rope = newRope(spec)
		table.insert(ropes, rope :: Rope)
	end
	if not rope then
		done()
		return nil
	end
	local r = rope :: Rope
	r.busy = true
	r.beam.Attachment0 = anchor
	r.beam.Enabled = true
	local th: LassoThrow = {
		rope = r, spec = spec, anchor = anchor, start = start, to = to, started = os.clock(),
		flight = math.max(0.06, (to - start).Magnitude / spec.speed), phase = "out", phaseAt = os.clock(),
		targets = nil, ears = {}, hand = start, spin = 0, done = done, cinched = cinched, caught = caught,
	}
	table.insert(throws, th)
	if not lassoMover then lassoMover = RunService.Heartbeat:Connect(lassoStep) end
	return th
end

-- The server's answer for a throw: the confirmed stalks' ear positions (aimed one first), or an
-- empty list for a refused throw. A throw still in flight uses it when it lands.
function ToolEffects.lassoReply(th: LassoThrow, targets: { Vector3 })
	if th.targets == nil then th.targets = targets end
end

return ToolEffects
