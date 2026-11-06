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
local function newEar(pull: ToolPresentation.PullVfx): Ear
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

return ToolEffects
