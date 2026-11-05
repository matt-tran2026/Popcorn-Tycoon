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
