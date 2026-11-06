--!strict
-- How each harvesting tool looks, moves and sounds. Gameplay numbers (reach, targets, cooldown,
-- price) stay in Config.Tools; nothing in this module can change a harvest or a reward.
-- The server reads `model` to build the Tool; the client reads `clips`, `sounds` and `vfx`.
-- See docs/design/TOOL_COLLECTION.md for the conventions every tool follows.
local ToolPresentation = {}

-- Joint name -> { x, y, z } rotation in degrees, layered on top of whatever the Animator plays.
-- Names are R15 joints (ToolAnimator maps the arm/neck ones onto R6 rigs too). A tool joint may
-- add a translation in studs as entries 4-6 ({ 0, 0, 0, 1.2, 0, 0 } slides 1.2 along tool X).
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
	-- The Tool's Handle is a small invisible grip part at the grip point instead of the handle
	-- mesh, so `joints` may move the handle mesh itself (the Pitchfork's shaft slides through
	-- the hand on a thrust). Named points then ride on the handle mesh.
	holder: boolean?,
	-- Dual-wield tools (Twin Sickles): the server puts a copy of the model in the left hand while
	-- the tool is equipped (ToolModels). grip is that copy's hold in the left hand's grip frame,
	-- normally ToolPresentation.mirrorHold of the right hand's; trailColors tint its SwingTrail.
	offhand: { grip: CFrame, trailColors: { Color3 } }?,
}
-- Hook Pull (PullHarvest tools): each confirmed ear flies a curved path back to the holder.
-- flySeconds: the flight; rise/sideways: how far the curve bows up and out (studs); line: a
-- thin streak from the hook to each stalk at the Hit marker, shown for lineSeconds.
export type PullVfx = {
	flySeconds: number, rise: number, sideways: number, lineSeconds: number,
	earColor: Color3, huskColor: Color3, trailColors: { Color3 },
}
-- Combo Sweep (Twin Sickles): two glowing ribbons whirl once round the player during the spin.
-- radius/width: where the ribbon sits (studs from the player's centre); height above the root.
export type ComboVfx = { seconds: number, radius: number, width: number, height: number, colors: { Color3 } }
-- snipFlash: a tiny white sparkle where each confirmed stalk is cut (clippers and shears).
export type Vfx = {
	leafTexture: string, leavesPerStalk: number, leafColor: Color3, snipFlash: boolean?, pull: PullVfx?, combo: ComboVfx?,
}
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

-- The left hand's mirror image of hold(forward, face). Mirroring a hold is not a rotation, but
-- a head that is symmetric about its flat plane (Twin Sickles; see build_twin_sickles.py) looks
-- the same flipped over, so flipping its face too turns the mirror into a rotation of the same
-- mesh: the left copy then curls the other way, as a true mirror image would.
function ToolPresentation.mirrorHold(forward: Vector3, face: Vector3): CFrame
	return ToolPresentation.hold(Vector3.new(-forward.X, forward.Y, forward.Z), Vector3.new(face.X, -face.Y, -face.Z))
end

-- Twin Sickles hold: each hand's handle forward and a little up and out, its crescent tilted
-- 45 degrees and curling up and inward, so the pair frames the player like the reference render.
local TWIN_FORWARD, TWIN_FACE = Vector3.new(0.12, 0.3, -1), Vector3.new(-0.7, -0.7, 0)
-- The left arm has no default tool pose, so Twin Sickles clips hold it up in every key: the
-- mirror image of the R15 default tool hold measured on the right arm in Play (Nov 6 2026:
-- RightShoulder (79.2, 0, -6.3), RightElbow (9.8, 0.3, 5.4); a mirror flips Y and Z). `guard`
-- merges that base into a pose.
-- Pose angles are applied before the joint's base pose, so on an arm held straight forward
-- the shoulder's Z turns it sideways (+Z swings either arm toward the character's right) and
-- the wrist's Z flicks the hand left/right; X lifts it and Y rolls it.
local TWIN_GUARD: Pose = { LeftShoulder = { 79, 0, 6 }, LeftElbow = { 10, 0, -5 } }
local function guard(pose: Pose): Pose
	local merged: Pose = {}
	for name, value in TWIN_GUARD do merged[name] = value end
	for name, value in pose do
		local base = TWIN_GUARD[name]
		if base then
			-- Offsets on a guarded joint are added to the guard, not replacing it.
			merged[name] = { base[1] + value[1], base[2] + value[2], base[3] + value[3] }
		else
			merged[name] = value
		end
	end
	return merged
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
			-- Original synthesised clicks (assets/tools/Common/CornClippers/audio), uploaded Nov 5
			-- 2026 through the Asset Manager. Swing keeps the Creator Store scissors snip as fallback.
			Equip = { id = "rbxassetid://118510995750490", fallback = nil, volume = 0.3, pitch = { 0.96, 1.04 } },
			Swing = { id = "rbxassetid://72252775021618", fallback = "rbxassetid://9118831072", volume = 0.32, pitch = { 0.92, 1.1 } },
			Harvest = { id = "rbxassetid://125411384210572", fallback = "rbxassetid://9118831072", volume = 0.45, pitch = { 0.95, 1.15 } },
		},
		vfx = { leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 4, leafColor = Color3.new(1, 1, 1), snipFlash = true },
	},
	-- Long three-prong pitchfork (assets/tools/Common/Pitchfork, from the creator's reference
	-- render). Numbers come from build_pitchfork.py: shaft mesh from -1.565 to 2.56 along X
	-- (centre 0.498 ahead of the grip), prong tips at x 4.6-4.7. Design canvas: "Pitchfork Design".
	Pitchfork = {
		rarity = "Common",
		model = {
			template = "Pitchfork", handle = "PitchforkHandle", gripFromCentre = -0.498, head = "PitchforkHead",
			materials = { PitchforkHandle = Enum.Material.Wood, PitchforkHead = Enum.Material.Metal },
			-- The hand holds an invisible grip; the shaft hangs off it on the Thrust motor and the
			-- head is welded to the shaft, so the stab slides the whole fork forward.
			holder = true,
			joints = { PitchforkHandle = { motor = "Thrust", pivot = Vector3.zero } },
			welds = { PitchforkHead = "PitchforkHandle" },
			-- Right hand, shaft pointing straight ahead and a touch down, prongs lying flat so
			-- the camera behind the player sees the three tines spread over the row.
			grip = ToolPresentation.hold(Vector3.new(0, -0.08, -1), Vector3.new(0, 1, 0)),
			points = {
				MiddleTip = Vector3.new(4.72, 0.08, 0),
				OuterTipL = Vector3.new(4.58, 0.13, 0.43), OuterTipR = Vector3.new(4.58, 0.13, -0.43),
			},
			-- A flat streak across the prong tips, drawn while the fork drives forward.
			trail = { from = "OuterTipL", to = "OuterTipR", lifetime = 0.16,
				colors = { Color3.fromRGB(255, 252, 240), Color3.fromRGB(214, 236, 255) } },
		},
		clips = {
			-- Swung up from the hip into a ready port with a little twirl of the wrist.
			Equip = { seconds = 0.36, keys = {
				{ t = 0, pose = { RightShoulder = { -80, 0, 0 }, RightWrist = { 0, 0, 35 }, Thrust = { 0, 0, 0, -1.2, 0, 0 } } },
				{ t = 0.65, pose = { RightShoulder = { 8, 0, 0 }, RightWrist = { 0, 0, -10 }, Thrust = { 0, 0, 0, 0.25, 0, 0 } }, ease = "Back" },
				{ t = 1, pose = {} },
			}, markers = { Shing = 0.6 } },
			-- Slow breathing sway; the fork bobs a little in the hand.
			Idle = { seconds = 2.6, loop = true, keys = {
				{ t = 0, pose = { RightShoulder = { 0, 0, 0 }, Thrust = { 0, 0, 0, 0, 0, 0 } } },
				{ t = 0.5, pose = { RightShoulder = { 3, 1, 0 }, RightWrist = { 2, 0, 0 }, Thrust = { 0, 0, 0, 0.08, 0, 0 } } },
				{ t = 1, pose = { RightShoulder = { 0, 0, 0 }, Thrust = { 0, 0, 0, 0, 0, 0 } } },
			} },
			-- Piercing Harvest: pull back with a twist, then drive straight down the row. The
			-- shaft slides 1.9 studs forward through the hand at the jab, holds, and recovers.
			-- 0.42 s = Config.Tools.Pitchfork.swingSeconds; Hit times the snips down the line.
			Swing = { seconds = 0.42, keys = {
				{ t = 0, pose = {} },
				-- Little yaw: the head must travel along the lane, not sweep across it (a 20 degree
				-- waist twist moved the prongs ~4 studs sideways in the first playtest).
				{ t = 0.33, pose = { Waist = { 0, -8, 0 }, RightShoulder = { -4, -2, 0 }, LeftShoulder = { 0, 8, 0 },
					Neck = { 0, 4, 0 }, Thrust = { 0, 0, 0, -1.0, 0, 0 } }, ease = "Quad" },
				{ t = 0.5, pose = { Waist = { 0, 5, 0 }, RightShoulder = { -2, 3, 0 }, LeftShoulder = { 0, -8, 0 },
					Neck = { 0, -3, 0 }, Thrust = { 0, 0, 0, 1.9, 0, 0 } }, ease = "Quad" },
				{ t = 0.68, pose = { Waist = { 0, 4, 0 }, RightShoulder = { -2, 3, 0 }, LeftShoulder = { 0, -7, 0 },
					Neck = { 0, -3, 0 }, Thrust = { 0, 0, 0, 1.75, 0, 0 } } },
				{ t = 1, pose = {}, ease = "Sine" },
			}, markers = { Hit = 0.48 } },
		},
		sounds = {
			-- Original synthesised sounds (assets/tools/Common/Pitchfork/audio), uploaded Nov 5 2026
			-- through the Asset Manager. Fallbacks are the Sickle's equip, swoosh and stalk snap.
			Equip = { id = "rbxassetid://80005805168325", fallback = "rbxassetid://116936988986525", volume = 0.3, pitch = { 0.95, 1.05 } },
			Swing = { id = "rbxassetid://76327908959778", fallback = "rbxassetid://136321679774475", volume = 0.36, pitch = { 0.94, 1.06 } },
			Harvest = { id = "rbxassetid://118142725285059", fallback = "rbxassetid://125411384210572", volume = 0.48, pitch = { 0.9, 1.1 } },
		},
		vfx = { leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 5, leafColor = Color3.new(1, 1, 1), snipFlash = true },
	},
	-- Forged question-mark hook with a spiral leather grip (assets/tools/Common/HarvestHook, from
	-- the creator's reference render). Numbers come from build_harvest_hook.py: wrap from -0.92
	-- to 0.74 along X (centre 0.09 behind the grip), hook tip at (0.92, 0, 0.84), crown of the
	-- curl at (2.49, 0, 1.57). Design canvas: "Harvest Hook".
	HarvestHook = {
		rarity = "Common",
		model = {
			template = "HarvestHook", handle = "HookHandle", gripFromCentre = 0.09, head = "HookBlade",
			materials = { HookHandle = Enum.Material.Leather, HookBlade = Enum.Material.Metal, HookPommel = Enum.Material.Metal },
			-- The hand holds an invisible grip; the grip hangs off it on the Reach motor so the
			-- hook can lunge out of the hand on the throw and snap back on the pull.
			holder = true,
			joints = { HookHandle = { motor = "Reach", pivot = Vector3.zero } },
			welds = { HookBlade = "HookHandle", HookPommel = "HookHandle" },
			-- Right hand, handle forward and a little up, the curl hanging to the left and a bit
			-- down so the camera behind the player sees the question-mark shape.
			grip = ToolPresentation.hold(Vector3.new(0, 0.25, -1), Vector3.new(0.5, -0.87, 0)),
			points = {
				HookTip = Vector3.new(0.916, 0, 0.839), HookCrown = Vector3.new(2.486, 0, 1.574),
				CurlCentre = Vector3.new(1.78, 0, 0.877),
			},
			-- A short pale arc behind the curl while the hook is thrown.
			trail = { from = "HookTip", to = "HookCrown", lifetime = 0.16,
				colors = { Color3.fromRGB(255, 250, 232), Color3.fromRGB(255, 226, 140) } },
		},
		clips = {
			-- Drawn up from the hip, the hook sliding into the hand with a wrist flourish.
			Equip = { seconds = 0.34, keys = {
				{ t = 0, pose = { RightShoulder = { -75, 0, 0 }, RightWrist = { 0, 0, 35 }, Reach = { 0, 0, 0, -0.5, 0, 0 } } },
				{ t = 0.65, pose = { RightShoulder = { 8, 0, 0 }, RightWrist = { 0, 0, -10 }, Reach = { 0, 0, 0, 0.15, 0, 0 } }, ease = "Back" },
				{ t = 1, pose = {} },
			}, markers = { Shing = 0.6 } },
			-- Slow sway; the hook rocks a little on the wrist.
			Idle = { seconds = 2.5, loop = true, keys = {
				{ t = 0, pose = { RightShoulder = { 0, 0, 0 }, RightWrist = { 0, 0, 0 } } },
				{ t = 0.5, pose = { RightShoulder = { 3, 1, 0 }, RightWrist = { 3, 0, 3 } } },
				{ t = 1, pose = { RightShoulder = { 0, 0, 0 }, RightWrist = { 0, 0, 0 } } },
			} },
			-- Hook Pull, 0.42 s = Config.Tools.HarvestHook.swingSeconds. Reach: the arm lifts and
			-- the hook cocks back (0.08 s). Hook: a fast forward throw, the hook lunging 1.6 studs
			-- out of the hand (Hit at 0.19 s). Pull: a hard yank back past the start, then settle.
			Swing = { seconds = 0.42, keys = {
				{ t = 0, pose = {} },
				{ t = 0.19, pose = { RightShoulder = { 38, 0, 0 }, RightWrist = { -30, 0, 0 }, Waist = { 0, -6, 0 },
					LeftShoulder = { 0, 6, 0 }, Reach = { 0, 0, 0, -0.4, 0, 0 } }, ease = "Quad" },
				{ t = 0.45, pose = { RightShoulder = { -12, 0, 0 }, RightWrist = { 25, 0, 0 }, Waist = { 0, 6, 0 },
					LeftShoulder = { 0, -6, 0 }, Neck = { 0, -3, 0 }, Reach = { 0, 0, 0, 1.6, 0, 0 } }, ease = "Quad" },
				{ t = 0.64, pose = { RightShoulder = { 30, 0, 0 }, RightWrist = { -20, 0, 0 }, Waist = { 0, -4, 0 },
					LeftShoulder = { 0, 4, 0 }, Reach = { 0, 0, 0, -0.6, 0, 0 } }, ease = "Quad" },
				{ t = 1, pose = {}, ease = "Sine" },
			}, markers = { Hit = 0.45 } },
		},
		sounds = {
			-- Original synthesised sounds (assets/tools/Common/HarvestHook/audio), uploaded Nov 5 2026
			-- through the Import Queue. Fallbacks: the Pitchfork's equip, the Sickle's air swoosh
			-- and the shared stalk snap. Pull plays when an ear reaches the player.
			Equip = { id = "rbxassetid://134838537880385", fallback = "rbxassetid://80005805168325", volume = 0.3, pitch = { 0.95, 1.05 } },
			Swing = { id = "rbxassetid://75439704625894", fallback = "rbxassetid://136321679774475", volume = 0.35, pitch = { 0.9, 1.0 } },
			Harvest = { id = "rbxassetid://121639839244296", fallback = "rbxassetid://125411384210572", volume = 0.48, pitch = { 0.92, 1.1 } },
			Pull = { id = "rbxassetid://71365913156932", fallback = nil, volume = 0.32, pitch = { 0.95, 1.12 } },
		},
		vfx = {
			leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 4, leafColor = Color3.new(1, 1, 1), snipFlash = true,
			pull = {
				flySeconds = 0.36, rise = 3.2, sideways = 1.8, lineSeconds = 0.12,
				earColor = Color3.fromRGB(255, 204, 44), huskColor = Color3.fromRGB(200, 214, 122),
				trailColors = { Color3.fromRGB(255, 244, 186), Color3.fromRGB(255, 196, 40) },
			},
		},
	},
	-- A matched pair of polished crescents (assets/tools/Uncommon/TwinSickles, from the creator's
	-- reference render). One sickle is modelled; the server puts a copy in the left hand. Numbers
	-- come from build_twin_sickles.py: wrap from -0.86 to 0.68 along X (centre 0.09 behind the
	-- grip), tip at (0.13, 0, 0.557), front of the curve (2.03, 0, 0.919), top (1.008, 0, 1.799).
	TwinSickles = {
		rarity = "Uncommon",
		model = {
			template = "TwinSickles", handle = "TwinHandle", gripFromCentre = 0.09, head = "TwinBlade",
			materials = { TwinHandle = Enum.Material.Wood, TwinBlade = Enum.Material.Metal, TwinPommel = Enum.Material.Metal },
			grip = ToolPresentation.hold(TWIN_FORWARD, TWIN_FACE),
			-- Right trail cool blue, left trail green, like the two swirls in the reference.
			offhand = {
				grip = ToolPresentation.mirrorHold(TWIN_FORWARD, TWIN_FACE),
				trailColors = { Color3.fromRGB(240, 255, 236), Color3.fromRGB(120, 235, 140) },
			},
			points = {
				BladeTip = Vector3.new(0.13, 0, 0.557), BladeFront = Vector3.new(2.03, 0, 0.919),
				BladeCrown = Vector3.new(1.008, 0, 1.799),
			},
			-- The leading quarter of the crescent leaves the slash streak.
			trail = { from = "BladeFront", to = "BladeCrown", lifetime = 0.18,
				colors = { Color3.fromRGB(240, 250, 255), Color3.fromRGB(120, 190, 255) } },
		},
		clips = {
			-- Both blades drawn up from the hips together with a wrist flourish.
			Equip = { seconds = 0.34, keys = {
				{ t = 0, pose = guard({ RightShoulder = { -75, 0, 0 }, RightWrist = { 0, 0, 35 }, LeftShoulder = { -75, 0, 0 }, LeftWrist = { 0, 0, -35 } }) },
				{ t = 0.6, pose = guard({ RightShoulder = { 8, 0, 0 }, RightWrist = { 0, 0, -12 }, LeftShoulder = { 8, 0, 0 }, LeftWrist = { 0, 0, 12 } }), ease = "Back" },
				{ t = 1, pose = guard({}) },
			}, markers = { Shing = 0.55 } },
			-- A light, ready bounce: the two blades sway against each other.
			Idle = { seconds = 2.2, loop = true, keys = {
				{ t = 0, pose = guard({}) },
				{ t = 0.5, pose = guard({ RightShoulder = { 3, 0, 3 }, RightWrist = { 0, 0, 4 }, LeftShoulder = { 3, 0, -3 }, LeftWrist = { 0, 0, -4 } }) },
				{ t = 1, pose = guard({}) },
			} },
			-- Right-hand slash (0.3 s = Config.Tools.TwinSickles.swingSeconds): cock out to the
			-- right with a twist, whip across to the left; the left blade swings out of the way.
			Swing = { seconds = 0.3, keys = {
				{ t = 0, pose = guard({}) },
				{ t = 0.22, pose = guard({ Waist = { 0, -20, 0 }, RightShoulder = { 8, 0, 55 }, RightWrist = { 0, 0, 30 },
					LeftShoulder = { 0, 0, -12 } }), ease = "Quad" },
				{ t = 0.5, pose = guard({ Waist = { 0, 26, 0 }, RightShoulder = { -4, 0, -70 }, RightWrist = { 0, 0, -25 },
					LeftShoulder = { 0, 0, -20 } }), ease = "Quad" },
				{ t = 0.7, pose = guard({ Waist = { 0, 30, 0 }, RightShoulder = { -6, 0, -82 }, RightWrist = { 0, 0, -30 },
					LeftShoulder = { 0, 0, -22 } }) },
				{ t = 1, pose = guard({}), ease = "Sine" },
			}, markers = { Hit = 0.42 } },
			-- Left-hand slash: the mirror image (Y and Z flip sign on the other side).
			SwingAlt = { seconds = 0.3, keys = {
				{ t = 0, pose = guard({}) },
				{ t = 0.22, pose = guard({ Waist = { 0, 20, 0 }, LeftShoulder = { 8, 0, -55 }, LeftWrist = { 0, 0, -30 },
					RightShoulder = { 0, 0, 12 } }), ease = "Quad" },
				{ t = 0.5, pose = guard({ Waist = { 0, -26, 0 }, LeftShoulder = { -4, 0, 70 }, LeftWrist = { 0, 0, 25 },
					RightShoulder = { 0, 0, 20 } }), ease = "Quad" },
				{ t = 0.7, pose = guard({ Waist = { 0, -30, 0 }, LeftShoulder = { -6, 0, 82 }, LeftWrist = { 0, 0, 30 },
					RightShoulder = { 0, 0, 22 } }) },
				{ t = 1, pose = guard({}), ease = "Sine" },
			}, markers = { Hit = 0.42 } },
			-- Combo Sweep: wind up, then a full spin of the body with both blades flung out wide.
			-- 0.45 s, inside the 0.55 s cooldown. Root is the R15 root joint (R6 rigs skip the spin).
			-- Spin marks the ribbon effect, Hit the first snips (mid-spin).
			Combo = { seconds = 0.45, keys = {
				{ t = 0, pose = guard({ Root = { 0, 0, 0 } }) },
				{ t = 0.16, pose = guard({ Root = { 0, -20, 0 }, Waist = { 0, -18, 0 }, RightShoulder = { 0, 0, 35 },
					LeftShoulder = { 0, 0, -35 } }), ease = "Quad" },
				{ t = 0.72, pose = guard({ Root = { 0, 360, 0 }, Waist = { 0, 8, 0 }, RightShoulder = { 0, 0, 70 },
					LeftShoulder = { 0, 0, -70 } }), ease = "Linear" },
				{ t = 1, pose = guard({ Root = { 0, 360, 0 } }), ease = "Sine" },
			}, markers = { Spin = 0.16, Hit = 0.45 } },
		},
		sounds = {
			-- Original synthesised sounds (assets/tools/Uncommon/TwinSickles/audio), uploaded Nov 6 2026
			-- through the Import Queue. Fallbacks are the Sickle's equip and air swoosh. Harvest is
			-- the shared stalk snap.
			Equip = { id = "rbxassetid://87090173268579", fallback = "rbxassetid://116936988986525", volume = 0.3, pitch = { 0.96, 1.05 } },
			Swing = { id = "rbxassetid://85859553374268", fallback = "rbxassetid://136321679774475", volume = 0.32, pitch = { 0.95, 1.08 } },
			Harvest = { id = "rbxassetid://125411384210572", fallback = "rbxassetid://9118831072", volume = 0.45, pitch = { 0.95, 1.15 } },
			Combo = { id = "rbxassetid://92449086112694", fallback = "rbxassetid://136321679774475", volume = 0.4, pitch = { 0.96, 1.04 } },
		},
		vfx = {
			leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 4, leafColor = Color3.new(1, 1, 1), snipFlash = true,
			combo = {
				seconds = 0.3, radius = 3.4, width = 1.5, height = 0.3,
				colors = { Color3.fromRGB(130, 205, 255), Color3.fromRGB(130, 245, 150) },
			},
		},
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
			assert((model.holder or part ~= model.handle) and joint.motor ~= "",
				toolId .. " joint " .. part .. " must be a non-handle mesh (or use a holder) with a motor name")
		end
		for part, to in model.welds or {} do
			assert(part ~= model.handle and part ~= to, toolId .. " weld " .. part .. " is invalid")
		end
		local trail = look.model.trail
		if trail then
			assert(look.model.points[trail.from] and look.model.points[trail.to], toolId .. " trail names a missing point")
		end
		local pull = look.vfx.pull
		if pull then
			assert(pull.flySeconds > 0 and pull.flySeconds <= 1 and pull.lineSeconds >= 0 and #pull.trailColors >= 1,
				toolId .. " pull effect needs a flight under a second and trail colours")
		end
		local offhand = model.offhand
		if offhand then
			assert(not model.holder and #offhand.trailColors >= 1, toolId .. " offhand needs trail colours and a mesh handle (no holder)")
		end
		local combo = look.vfx.combo
		if combo then
			assert(combo.seconds > 0 and combo.radius > combo.width / 2 and #combo.colors >= 1, toolId .. " combo effect is invalid")
		end
	end
end

return ToolPresentation
