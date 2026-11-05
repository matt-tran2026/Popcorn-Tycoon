--!strict
-- How each harvesting tool looks, moves and sounds. Gameplay numbers (reach, targets, cooldown,
-- price) stay in Config.Tools; nothing in this module can change a harvest or a reward.
-- The server reads `model` to build the Tool; the client reads `clips`, `sounds` and `vfx`.
-- See docs/design/TOOL_COLLECTION.md for the conventions every tool follows.
local ToolPresentation = {}

-- Joint name -> { x, y, z } rotation in degrees, layered on top of whatever the Animator plays.
-- Names are R15 joints (ToolAnimator maps the arm/neck ones onto R6 rigs too).
export type Pose = { [string]: { number } }
-- t is the fraction of the clip (0..1). ease shapes the move INTO this key.
export type Key = { t: number, pose: Pose, ease: ("Sine" | "Back" | "Quad" | "Linear")? }
-- markers: name -> fraction of the clip, for syncing sounds and effects (e.g. Hit).
export type Clip = { seconds: number, keys: { Key }, loop: boolean?, markers: { [string]: number }? }
-- id is the uploaded original sound (nil until uploaded); fallback keeps the old sound working.
export type Sound = { id: string?, fallback: string?, volume: number, pitch: { number } }
export type Model = {
	-- Model in ServerStorage.PopcornTemplates.Tools; without it the procedural builder is used.
	template: string,
	handle: string, -- the mesh that becomes the Tool's Handle (the one the hand grips)
	-- Distance from the handle mesh's bounding-box centre to the grip point, toward the head.
	gripFromCentre: number,
	materials: { [string]: Enum.Material },
	-- Tool frame used by `grip` and `points`: X along the handle toward the head, Y out of the
	-- blade's flat face, Z the side the head curls toward. Origin = the grip point.
	grip: CFrame,
	points: { [string]: Vector3 },
	trail: { from: string, to: string, lifetime: number, colors: { Color3 } }?,
	-- The mesh whose thinnest axis is the tool frame's Y (default: any non-handle mesh). Needed
	-- when the head has parts that are not flat (springs, bolts).
	head: string?,
	-- Moving parts: mesh name -> a Motor6D (named `motor`) from the Handle that turns the mesh
	-- about the tool frame's Y axis through `pivot` (tool frame). Pose clips drive it by that
	-- name, e.g. Jaw = { 0, -24, 0 } (ToolAnimator). Other meshes are welded.
	joints: { [string]: { motor: string, pivot: Vector3 } }?,
	-- Mesh name -> the mesh it is welded to instead of the Handle (parts that ride on a joint).
	welds: { [string]: string }?,
}
-- snipFlash: a tiny white sparkle where each confirmed stalk is cut (clippers and shears).
export type Vfx = { leafTexture: string, leavesPerStalk: number, leafColor: Color3, snipFlash: boolean? }
export type Presentation = {
	rarity: string,
	model: Model,
	clips: { [string]: Clip },
	sounds: { [string]: Sound },
	vfx: Vfx,
}

-- Tool.Grip from how the tool should sit in the right hand. The hand's grip frame matches the
-- character in the default hold (-Z forward, +Y up, +X right). `forward` is where the handle
-- points (tool-frame X) and `face` the side the head's flat face looks toward (tool-frame Y);
-- the head then curls toward X cross Y.
function ToolPresentation.hold(forward: Vector3, face: Vector3): CFrame
	local x = forward.Unit
	local y = (face - x * x:Dot(face)).Unit
	return CFrame.fromMatrix(Vector3.zero, x, y):Inverse()
end

-- Uploaded original art (assets/tools/_shared/textures).
ToolPresentation.Textures = { LeafFleck = "rbxassetid://107437834728710" }

local tools: { [string]: Presentation } = {
	Sickle = {
		rarity = "Common",
		model = {
			template = "Sickle", handle = "SickleHandle", gripFromCentre = 0.175,
			materials = { SickleHandle = Enum.Material.Wood, SickleBlade = Enum.Material.Metal },
			-- Right hand, handle pointing forward and a little up, blade lying flat and hooking
			-- to the left across the front, ready for the sideways sweep. (The old Grip, kept by
			-- the part-built fallback, stood the blade upright over the head.)
			grip = ToolPresentation.hold(Vector3.new(0, 0.3, -1), Vector3.new(0, -1, 0)),
			points = { BladeTip = Vector3.new(0.12, 0, 1.45), BladeBack = Vector3.new(2.3, 0, 1.0) },
			trail = { from = "BladeTip", to = "BladeBack", lifetime = 0.2,
				colors = { Color3.fromRGB(255, 252, 240), Color3.fromRGB(210, 230, 255) } },
		},
		clips = {
			-- Draw from the hip: arm comes up from the side with a little wrist flourish.
			Equip = { seconds = 0.32, keys = {
				{ t = 0, pose = { RightShoulder = { -75, 0, 0 }, RightWrist = { 0, 0, 40 } } },
				{ t = 0.7, pose = { RightShoulder = { 8, 0, 0 }, RightWrist = { 0, 0, -12 } }, ease = "Back" },
				{ t = 1, pose = {} },
			}, markers = { Shing = 0.55 } },
			-- Slow breathing sway while held; tiny, so it never fights walking.
			Idle = { seconds = 2.4, loop = true, keys = {
				{ t = 0, pose = { RightShoulder = { 0, 0, 0 }, RightWrist = { 0, 0, 0 } } },
				{ t = 0.5, pose = { RightShoulder = { 3, -2, 0 }, RightWrist = { 0, 0, 4 } } },
				{ t = 1, pose = { RightShoulder = { 0, 0, 0 }, RightWrist = { 0, 0, 0 } } },
			} },
			-- Fast sideways harvesting swing: cock out to the right, whip across, settle.
			-- seconds must match Config.Tools.Sickle.swingSeconds (the Hit marker times the snips).
			Swing = { seconds = 0.32, keys = {
				{ t = 0, pose = {} },
				{ t = 0.22, pose = { Waist = { 0, -22, 0 }, RightShoulder = { 18, -55, 0 }, RightElbow = { 0, 0, 0 },
					RightWrist = { 0, -25, 0 }, LeftShoulder = { 0, 15, 0 } }, ease = "Quad" },
				{ t = 0.5, pose = { Waist = { 0, 30, 0 }, RightShoulder = { 4, 95, 0 }, RightWrist = { 0, 22, 0 },
					LeftShoulder = { 0, -22, 0 } }, ease = "Quad" },
				{ t = 0.68, pose = { Waist = { 0, 36, 0 }, RightShoulder = { -4, 112, 0 }, RightWrist = { 0, 30, 0 },
					LeftShoulder = { 0, -26, 0 } } },
				{ t = 1, pose = {}, ease = "Sine" },
			}, markers = { Hit = 0.42 } },
		},
		sounds = {
			-- Original synthesised sounds (assets/tools/Common/Sickle/audio), uploaded Nov 5 2026
			-- through the Asset Manager. Fallbacks are the sounds the Sickle used before.
			Equip = { id = "rbxassetid://116936988986525", fallback = nil, volume = 0.3, pitch = { 0.96, 1.04 } },
			-- The plain air swoosh (the creator tried metal "shing" layers and chose this).
			Swing = { id = "rbxassetid://136321679774475", fallback = "rbxasset://sounds/swordslash.wav", volume = 0.35, pitch = { 0.95, 1.08 } },
			-- Fallback: Pro Sound Effects "Scissors Various Cuts Squeaky Snips 17", Creator Store.
			Harvest = { id = "rbxassetid://125411384210572", fallback = "rbxassetid://9118831072", volume = 0.5, pitch = { 0.92, 1.12 } },
		},
		vfx = { leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 4, leafColor = Color3.new(1, 1, 1) },
	},
	-- Bypass pruners (assets/tools/Common/CornClippers). Numbers come from the build script:
	-- handle mesh centre to grip 0.038 toward the butt, pivot bolt at (0.95, 0, 0.165).
	CornClippers = {
		rarity = "Common",
		model = {
			template = "CornClippers", handle = "ClippersHandle", gripFromCentre = -0.038, head = "ClippersBlade",
			materials = {
				ClippersHandle = Enum.Material.SmoothPlastic, ClippersJawGrip = Enum.Material.SmoothPlastic,
				ClippersBlade = Enum.Material.Metal, ClippersJaw = Enum.Material.Metal, ClippersSpring = Enum.Material.Metal,
			},
			-- The jaw half (hook and upper handle) turns about the bolt; the spring follows at half
			-- the angle so it stays between the handles.
			joints = {
				ClippersJaw = { motor = "Jaw", pivot = Vector3.new(0.95, 0, 0.165) },
				ClippersSpring = { motor = "Spring", pivot = Vector3.new(0.95, 0, 0.165) },
			},
			welds = { ClippersJawGrip = "ClippersJaw" },
			-- Right hand on the lower handle, blades pointing forward and a little up, upper
			-- handle on top: the side view shows the jaws opening and closing.
			grip = ToolPresentation.hold(Vector3.new(0, 0.12, -1), Vector3.new(-1, 0, 0)),
			points = { BladeTip = Vector3.new(2.1, 0, 0.123), SnipPoint = Vector3.new(1.37, 0, 0.005) },
		},
		clips = {
			-- Draw from the hip with a test click of the jaws (Shing marker = the click sound).
			Equip = { seconds = 0.3, keys = {
				{ t = 0, pose = { RightShoulder = { -70, 0, 0 }, RightWrist = { 0, 0, 30 } } },
				{ t = 0.55, pose = { RightShoulder = { 6, 0, 0 }, RightWrist = { 0, 0, -8 }, Jaw = { 0, -22, 0 }, Spring = { 0, -11, 0 } }, ease = "Back" },
				{ t = 0.8, pose = { RightShoulder = { 2, 0, 0 } } },
				{ t = 1, pose = {} },
			}, markers = { Shing = 0.5 } },
			Idle = { seconds = 2.4, loop = true, keys = {
				{ t = 0, pose = { RightShoulder = { 0, 0, 0 }, RightWrist = { 0, 0, 0 } } },
				{ t = 0.5, pose = { RightShoulder = { 3, 2, 0 }, RightWrist = { 2, 0, 3 } } },
				{ t = 1, pose = { RightShoulder = { 0, 0, 0 }, RightWrist = { 0, 0, 0 } } },
			} },
			-- Rapid Snip: a wrist flick forward with the jaws snapping shut and springing open.
			-- 0.12 s = Config.Tools.CornClippers.swingSeconds. Snips alternate between Swing
			-- (flick up) and SwingAlt (flick down) so fast repeats never look identical.
			Swing = { seconds = 0.12, keys = {
				{ t = 0, pose = {} },
				{ t = 0.45, pose = { RightShoulder = { 10, 4, 0 }, RightWrist = { -16, 0, 0 }, Jaw = { 0, -24, 0 }, Spring = { 0, -12, 0 } }, ease = "Quad" },
				{ t = 1, pose = {}, ease = "Sine" },
			}, markers = { Hit = 0.45 } },
			SwingAlt = { seconds = 0.12, keys = {
				{ t = 0, pose = {} },
				{ t = 0.45, pose = { RightShoulder = { 6, -5, 0 }, RightWrist = { 14, 0, 0 }, Jaw = { 0, -24, 0 }, Spring = { 0, -12, 0 } }, ease = "Quad" },
				{ t = 1, pose = {}, ease = "Sine" },
			}, markers = { Hit = 0.45 } },
		},
		sounds = {
			-- Original synthesised clicks (assets/tools/Common/CornClippers/audio), not uploaded
			-- yet: id stays nil until the creator uploads them. Swing falls back to the Creator
			-- Store scissors snip the Sickle already uses for its harvest.
			Equip = { id = nil, fallback = nil, volume = 0.3, pitch = { 0.96, 1.04 } },
			Swing = { id = nil, fallback = "rbxassetid://9118831072", volume = 0.32, pitch = { 0.92, 1.1 } },
			Harvest = { id = "rbxassetid://125411384210572", fallback = "rbxassetid://9118831072", volume = 0.45, pitch = { 0.95, 1.15 } },
		},
		vfx = { leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 4, leafColor = Color3.new(1, 1, 1), snipFlash = true },
	},
}

function ToolPresentation.get(toolId: string): Presentation?
	return tools[toolId]
end

-- The sound to play: the uploaded original if there is one, else the old fallback (or nil).
function ToolPresentation.soundId(sound: Sound): string?
	return sound.id or sound.fallback
end

-- Startup check: every clip has ordered keys spanning 0..1 and every trail names real points.
function ToolPresentation.validate(toolIds: { string })
	for _, toolId in toolIds do
		local look = tools[toolId]
		assert(look, "ToolPresentation missing for " .. toolId)
		for name, clip in look.clips do
			assert(clip.seconds > 0 and #clip.keys >= 2, toolId .. "." .. name .. " needs a duration and two keys")
			assert(clip.keys[1].t == 0 and clip.keys[#clip.keys].t == 1, toolId .. "." .. name .. " keys must span 0..1")
			for i = 2, #clip.keys do
				assert(clip.keys[i].t > clip.keys[i - 1].t, toolId .. "." .. name .. " keys out of order")
			end
		end
		local model = look.model
		for part, joint in model.joints or {} do
			assert(part ~= model.handle and joint.motor ~= "", toolId .. " joint " .. part .. " must be a non-handle mesh with a motor name")
		end
		for part, to in model.welds or {} do
			assert(part ~= model.handle and part ~= to, toolId .. " weld " .. part .. " is invalid")
		end
		local trail = look.model.trail
		if trail then
			assert(look.model.points[trail.from] and look.model.points[trail.to], toolId .. " trail names a missing point")
		end
	end
end

return ToolPresentation
