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
-- buzz: a fast vibration layered on the clip between fractions `from` and `to`: each joint in
-- `joints` gets its value times sin(2 pi hz t) added (fading out over the last 15% of the span),
-- e.g. the Hedge Trimmer's blades sliding past each other and the wrist jittering.
export type Buzz = { from: number, to: number, hz: number, joints: Pose }
export type Clip = { seconds: number, keys: { Key }, loop: boolean?, markers: { [string]: number }?, buzz: Buzz? }
-- id is the uploaded original sound (nil until uploaded); fallback keeps the old sound working.
export type Sound = { id: string?, fallback: string?, volume: number, pitch: { number } }
export type Model = {
	-- Model in ServerStorage.PopcornTemplates.Tools; without it the procedural builder is used.
	template: string,
	handle: string, -- the mesh that becomes the Tool's Handle (the one the hand grips)
	-- Distance from the handle mesh's bounding-box centre to the grip point, toward the head.
	gripFromCentre: number,
	-- Distance along the tool frame's Z from the handle mesh's bounding-box centre to the grip
	-- point, for handles whose grip bar is off-centre (the Hedge Trimmer's rear loop). Default 0.
	gripSide: number?,
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
	-- name, e.g. Jaw = { 0, -24, 0 } (ToolAnimator). Other meshes are welded. `on` hangs the
	-- motor from another mesh instead of the Handle, so the part rides that mesh's own joint
	-- (the Spring-Loaded Picker's jaws ride the sliding plunger rod).
	joints: { [string]: { motor: string, pivot: Vector3, on: string? } }?,
	-- Stretching parts (the Spring-Loaded Picker's coil): mesh name -> its own joint's motor, the
	-- joint it follows and its rest length along tool X. Its rear end stays at its motor's pivot
	-- and its front end follows the `follow` motor's slide: each frame ToolAnimator resizes it
	-- along tool X to length + slide and moves it half the slide forward. Client-only, like every
	-- pose. ToolModels marks the mesh with the axis and rest size it needs.
	stretch: { [string]: { motor: string, follow: string, length: number } }?,
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
-- Wind trail (Long Scythe's Great Harvest): ribbons, one per radius, sweep `degrees` round the
-- player from their right to their left at the clip's Sweep marker, showing the swing's reach.
export type WindVfx = { seconds: number, degrees: number, radii: { number }, width: number, height: number, colors: { Color3 } }
-- Trim strip (Hedge Trimmer's Precision Cutting): at the Hit marker a flat translucent rectangle
-- the size of the tool's lane (Config laneWidth, LaneBehind to reach) fills along the ground
-- from the player outward in `seconds`, then fades over `fadeSeconds`. While the blades run
-- (`spraySeconds` from the start of the swing) grass flecks spray from `sprayPoint` and small
-- sparks fly from `sparkPoint` (named points on the tool).
export type TrimVfx = {
	seconds: number, fadeSeconds: number, color: Color3, transparency: number,
	spraySeconds: number, sprayPoint: string, sprayColor: Color3, sparkPoint: string, sparkColor: Color3,
}
-- Spring Dash (Spring-Loaded Picker): while the character lunges, a speed streak (a Trail between
-- two attachments on the root part, `width` studs tall, fading over `trailSeconds`) follows it;
-- a ring of dust puffs (`dustCount` particles, `dustColor`) kicks up at take-off and landing,
-- and a spring sparkle pops at the claw (`sparkPoint`) when it fires.
export type DashVfx = {
	trailColors: { Color3 }, trailSeconds: number, width: number, dustColor: Color3, dustCount: number, sparkPoint: string,
}
-- Long-Range Retrieval (Corn Lasso): at the Swing clip's Throw marker a rope loop flies from the
-- tool's `ropePoint` to the aimed ear at `speed` studs/s, bowing `rise` studs up per 10 studs
-- of throw, opening to `openRadius` and spinning `spinTurns` times. It waits up to `waitSeconds`
-- for the server; for each confirmed stalk it cinches to `cinchRadius` in `cinchSeconds` and the
-- ears ride the rope back to the hand in `backSeconds` (a refused throw reels back empty). The
-- held loop mesh (`loopMesh`) hides while a rope is out. `ropeColor`/`ropeWidth` style the rope
-- (a Beam) and the loop (pooled rope segments); ears use the Hook Pull's ear colours.
export type LassoVfx = {
	speed: number, rise: number, openRadius: number, cinchRadius: number, spinTurns: number,
	waitSeconds: number, cinchSeconds: number, backSeconds: number, ropePoint: string, loopMesh: string,
	ropeColor: Color3, ropeShade: Color3, ropeWidth: number,
	earColor: Color3, huskColor: Color3, trailColors: { Color3 },
}
-- snipFlash: a tiny white sparkle where each confirmed stalk is cut (clippers and shears).
export type Vfx = {
	leafTexture: string, leavesPerStalk: number, leafColor: Color3, snipFlash: boolean?, pull: PullVfx?, combo: ComboVfx?,
	wind: WindVfx?, trim: TrimVfx?, dash: DashVfx?, lasso: LassoVfx?,
}
export type Presentation = {
	rarity: string,
	model: Model,
	clips: { [string]: Clip },
	-- Joints the clips hold outright instead of layering on the walk/run animation (ToolAnimator):
	-- the Twin Sickles' left arm, which no default tool hold keeps still.
	holdJoints: { string }?,
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
local TWIN_GUARD: Pose = { LeftShoulder = { 79, 0, 6 }, LeftElbow = { 10, 0, -5 }, LeftWrist = { 0, 0, 0 } }
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

-- Long Scythe: two-handed. The right hand holds the shaft at the grip; the left reaches across to
-- the butt end (about a stud behind it), so the left arm is held forward and toward the right in
-- every key. `twoHand` merges that base into a pose; offsets on the left arm add to it.
local SCYTHE_LEFT: Pose = { LeftShoulder = { 40, 0, 40 }, LeftElbow = { 25, 0, 0 }, LeftWrist = { 0, 0, 0 } }
local function twoHand(pose: Pose): Pose
	local merged: Pose = {}
	for name, value in SCYTHE_LEFT do merged[name] = value end
	for name, value in pose do
		local base = SCYTHE_LEFT[name]
		merged[name] = if base then { base[1] + value[1], base[2] + value[2], base[3] + value[3] } else value
	end
	return merged
end

-- Hedge Trimmer: two-handed. The right hand holds the rear loop at the waist (arm dropped and
-- bent, elbow in), the bar pointing ahead and a little left and down; the left hand holds the
-- top of the front bow. With the right arm straight out (the default tool hold, first try) the
-- bow was 3.2 studs from the left shoulder, out of reach. These angles came from a forward-
-- kinematics search on the R15 rig in Play (Nov 6 2026): grip at (0.78, -0.37, -0.93) from the
-- root, left hand 0.24 studs from the bow bar. `trimHands` merges this base into a pose;
-- offsets on these joints add to it.
local TRIM_LEFT: Pose = {
	RightShoulder = { -95, 0, -50 }, RightElbow = { 70, 0, 0 },
	LeftShoulder = { 60, 0, 35 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local function trimHands(pose: Pose): Pose
	local merged: Pose = {}
	for name, value in TRIM_LEFT do merged[name] = value end
	for name, value in pose do
		local base = TRIM_LEFT[name]
		merged[name] = if base then { base[1] + value[1], base[2] + value[2], base[3] + value[3] } else value
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
			-- through the Asset Manager. Fallbacks are the Sickle's swoosh and stalk snap. Equip uses
			-- the Sickle's equip sound (creator, Nov 6 2026).
			Equip = { id = "rbxassetid://116936988986525", fallback = nil, volume = 0.3, pitch = { 0.96, 1.04 } },
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
			-- through the Import Queue. Equip uses the Sickle's equip sound (creator, Nov 6 2026).
			-- Fallbacks: the Sickle's air swoosh and the shared stalk snap. Pull plays when an ear
			-- reaches the player.
			Equip = { id = "rbxassetid://116936988986525", fallback = nil, volume = 0.3, pitch = { 0.96, 1.04 } },
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
		-- The left arm is held by the guard pose alone, so running doesn't swing it (and its
		-- blade) while the right arm stays in the default tool hold (creator, Nov 6).
		holdJoints = { "LeftShoulder", "LeftElbow", "LeftWrist" },
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
	-- Long two-handed scythe (assets/tools/Uncommon/LongScythe, from the creator's reference
	-- render, built the way the creator's weapon pack builds its weapons: flat extruded plates,
	-- solid colours, a dark outline plate behind the blade, SmoothPlastic). Numbers come from
	-- build_long_scythe.py: shaft mesh from -1.3 to 5.36 along X (centre 2.03 ahead of the
	-- grip), blade tip (3.141, 0, 3.665), heel of the edge (4.594, 0, 1.109).
	LongScythe = {
		rarity = "Uncommon",
		-- The left hand holds the butt end; it must not swing with the run animation.
		holdJoints = { "LeftShoulder", "LeftElbow", "LeftWrist" },
		model = {
			template = "LongScythe", handle = "LongScytheHandle", gripFromCentre = -2.03, head = "LongScytheBlade",
			materials = {
				LongScytheHandle = Enum.Material.SmoothPlastic, LongScytheBlade = Enum.Material.SmoothPlastic,
				LongScytheFittings = Enum.Material.SmoothPlastic,
			},
			-- Right hand, shaft held across the body (forward, to the left and up) with the blade
			-- hanging down from its top into the corn, edge toward the player, as in the reference.
			-- A flat-lying blade (first try) was edge-on to the camera behind the player and vanished.
			grip = ToolPresentation.hold(Vector3.new(-0.7, 0.35, -0.65), Vector3.new(0.65, 0, -0.7)),
			points = {
				BladeTip = Vector3.new(3.141, 0, 3.665), BladeHeel = Vector3.new(4.594, 0, 1.109),
				BladeBack = Vector3.new(5.344, 0, 2.35), BladeRoot = Vector3.new(5.101, 0, 0.208),
			},
			-- The whole blade face leaves a wide, pale wind streak.
			trail = { from = "BladeTip", to = "BladeRoot", lifetime = 0.3,
				colors = { Color3.fromRGB(250, 255, 252), Color3.fromRGB(150, 235, 210) } },
		},
		clips = {
			-- Hefted up from the hip into both hands.
			Equip = { seconds = 0.42, keys = {
				{ t = 0, pose = twoHand({ RightShoulder = { -70, 0, 0 }, RightWrist = { 0, 0, 30 }, LeftShoulder = { -40, 0, -20 } }) },
				{ t = 0.65, pose = twoHand({ RightShoulder = { 10, 0, 0 }, RightWrist = { 0, 0, -8 } }), ease = "Back" },
				{ t = 1, pose = twoHand({}) },
			}, markers = { Shing = 0.6 } },
			-- Slow, heavy breathing; the blade rocks a little.
			Idle = { seconds = 2.8, loop = true, keys = {
				{ t = 0, pose = twoHand({}) },
				{ t = 0.5, pose = twoHand({ RightShoulder = { 3, 0, 2 }, LeftShoulder = { 3, 0, 2 }, Waist = { 0, 2, 0 } }) },
				{ t = 1, pose = twoHand({}) },
			} },
			-- Great Harvest, 0.8 s = Config.Tools.LongScythe.swingSeconds: a slow wind-up far to
			-- the right with a deep twist (0.24 s), the blade whipped through a half circle to
			-- the left (Hit at 0.34 s), a held follow-through, then a long heavy recovery: the
			-- catalog's weakness. Sweep starts the wind trail as the blade leaves the right.
			Swing = { seconds = 0.8, keys = {
				{ t = 0, pose = twoHand({}) },
				{ t = 0.3, pose = twoHand({ Waist = { 0, -38, 0 }, RightShoulder = { 6, 0, 62 }, RightWrist = { 0, 0, 22 },
					LeftShoulder = { 0, 0, 40 }, Neck = { 0, 10, 0 } }), ease = "Quad" },
				-- The shaft is already held across to the left, so a short follow-through is enough to
				-- finish on the left; a bigger one (first try: shoulder -80, waist 42) carried the
				-- blade round behind the player.
				{ t = 0.52, pose = twoHand({ Waist = { 0, 24, 0 }, RightShoulder = { -6, 0, -30 }, RightWrist = { 0, 0, -16 },
					LeftShoulder = { 0, 0, -26 }, Neck = { 0, -6, 0 } }), ease = "Quad" },
				{ t = 0.64, pose = twoHand({ Waist = { 0, 28, 0 }, RightShoulder = { -8, 0, -38 }, RightWrist = { 0, 0, -20 },
					LeftShoulder = { 0, 0, -32 }, Neck = { 0, -8, 0 } }) },
				{ t = 1, pose = twoHand({}), ease = "Sine" },
			}, markers = { Sweep = 0.3, Hit = 0.42 } },
		},
		sounds = {
			-- Original synthesised sounds go in assets/tools/Uncommon/LongScythe/audio; until they
			-- are uploaded the fallbacks play: the Sickle's air swoosh pitched down for weight, and
			-- the shared stalk snap. Equip uses the Sickle's equip sound (creator, Nov 6 2026).
			Equip = { id = "rbxassetid://116936988986525", fallback = nil, volume = 0.3, pitch = { 0.96, 1.04 } },
			Swing = { id = nil, fallback = "rbxassetid://136321679774475", volume = 0.4, pitch = { 0.72, 0.8 } },
			Harvest = { id = nil, fallback = "rbxassetid://125411384210572", volume = 0.45, pitch = { 0.9, 1.1 } },
		},
		vfx = {
			leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 5, leafColor = Color3.new(1, 1, 1),
			-- Two pale wind ribbons sweep the half circle: one where the blade passes, one out
			-- near the 15-stud reach, so players see how far Great Harvest cuts.
			wind = {
				seconds = 0.2, degrees = 180, radii = { 6, 11.5 }, width = 2.4, height = -0.6,
				colors = { Color3.fromRGB(235, 255, 245), Color3.fromRGB(160, 240, 205) },
			},
		},
	},
	-- Motorised hedge trimmer (assets/tools/Uncommon/HedgeTrimmer, from the creator's reference
	-- render, built like the weapon pack: flat plates, flat colours, dark outline plates).
	-- Numbers come from build_hedge_trimmer.py: rear loop mesh centred 0.059 behind and 0.43
	-- below the grip bar (gripFromCentre, gripSide), the bar's centre line 0.62 below the grip
	-- (tool Z points from the housing toward the bar), blade from x 2.15 to 4.6, front bow top
	-- at (1.05, 0, -0.96). Design page: "Hedge Trimmer Tool Design".
	HedgeTrimmer = {
		rarity = "Uncommon",
		-- The left hand holds the front bow; it must not swing with the run animation.
		holdJoints = { "LeftShoulder", "LeftElbow", "LeftWrist" },
		model = {
			template = "HedgeTrimmer", handle = "TrimmerHandle", gripFromCentre = 0.059, gripSide = -0.43,
			head = "TrimmerBladeTop",
			materials = {
				TrimmerHandle = Enum.Material.SmoothPlastic, TrimmerBody = Enum.Material.SmoothPlastic,
				TrimmerBar = Enum.Material.Metal, TrimmerBladeTop = Enum.Material.Metal, TrimmerBladeBottom = Enum.Material.Metal,
			},
			-- The two blades slide along the bar on their own motors (the Trim clip's buzz).
			joints = {
				TrimmerBladeTop = { motor = "BladeA", pivot = Vector3.new(3.375, 0, 0.62) },
				TrimmerBladeBottom = { motor = "BladeB", pivot = Vector3.new(3.375, 0, 0.62) },
			},
			-- Bar pointing ahead (a little left and down), turned about 37 degrees off flat: the housing up
			-- and to the left, the side panel facing up and right, so the camera behind the player
			-- sees the teeth, the orange panel and the housing (a blade seen edge-on vanishes, as
			-- found with the Long Scythe).
			-- (Given in the bent hand's frame; from the same search as trimHands' base pose.)
			grip = ToolPresentation.hold(Vector3.new(-0.16, 0.22, -0.96), Vector3.new(0.11, 0.97, 0.2)),
			points = {
				BladeTip = Vector3.new(4.6, 0, 0.62), BladeRoot = Vector3.new(2.25, 0, 0.62),
				BladeMid = Vector3.new(3.375, 0, 0.62), LeftHand = Vector3.new(1.05, 0, -0.96),
				Motor = Vector3.new(1.55, 0, 0.3),
			},
		},
		clips = {
			-- Lifted from the hip into both hands with a motor blip (Shing).
			Equip = { seconds = 0.36, keys = {
				{ t = 0, pose = trimHands({ RightShoulder = { -25, 0, 0 }, RightWrist = { 0, 0, 25 }, LeftShoulder = { -55, 0, -20 } }) },
				{ t = 0.65, pose = trimHands({ RightShoulder = { 6, 0, 0 }, RightWrist = { 0, 0, -6 } }), ease = "Back" },
				{ t = 1, pose = trimHands({}) },
			}, markers = { Shing = 0.55 } },
			-- Ready stance: a slow, small sway. Nothing buzzes while idle.
			Idle = { seconds = 2.2, loop = true, keys = {
				{ t = 0, pose = trimHands({}) },
				{ t = 0.5, pose = trimHands({ RightShoulder = { 2, 0, 1 }, LeftShoulder = { 2, 0, 1 } }) },
				{ t = 1, pose = trimHands({}) },
			} },
			-- Precision Cutting, 0.45 s = Config.Tools.HedgeTrimmer.swingSeconds: a short lift and
			-- push (Hit at 0.12 s: the trim strip and the snips), two side-to-side shakes while the
			-- blades chatter, then settle. Small yaw only: the cut is a straight strip.
			Swing = { seconds = 0.45, keys = {
				{ t = 0, pose = trimHands({}) },
				{ t = 0.27, pose = trimHands({ RightShoulder = { 10, 0, 0 }, RightElbow = { -12, 0, 0 }, LeftShoulder = { 10, 0, 0 },
					LeftElbow = { -8, 0, 0 }, Neck = { -3, 0, 0 } }), ease = "Quad" },
				{ t = 0.45, pose = trimHands({ RightShoulder = { 8, 0, 8 }, LeftShoulder = { 8, 0, 8 }, Waist = { 0, 5, 0 } }) },
				{ t = 0.62, pose = trimHands({ RightShoulder = { 8, 0, -7 }, LeftShoulder = { 8, 0, -7 }, Waist = { 0, -5, 0 } }) },
				{ t = 0.8, pose = trimHands({ RightShoulder = { 5, 0, 0 }, LeftShoulder = { 5, 0, 0 } }) },
				{ t = 1, pose = trimHands({}), ease = "Sine" },
			}, markers = { Hit = 0.27 },
			-- The two blades slide past each other +-0.07 studs at 22 Hz; the wrist jitters.
			buzz = { from = 0.04, to = 0.8, hz = 22, joints = {
				BladeA = { 0, 0, 0, 0.07, 0, 0 }, BladeB = { 0, 0, 0, -0.07, 0, 0 }, RightWrist = { 1.4, 0, 1.4 },
			} } },
		},
		sounds = {
			-- Original synthesised sounds (assets/tools/Uncommon/HedgeTrimmer/audio), uploaded by the
			-- creator Nov 6 2026. Fallbacks: the Sickle's equip, the air swoosh, the clippers' snip.
			Equip = { id = "rbxassetid://129080146516303", fallback = "rbxassetid://116936988986525", volume = 0.3, pitch = { 0.96, 1.04 } },
			Swing = { id = "rbxassetid://137220544623359", fallback = "rbxassetid://136321679774475", volume = 0.32, pitch = { 0.96, 1.05 } },
			Harvest = { id = "rbxassetid://122745530221694", fallback = "rbxassetid://72252775021618", volume = 0.4, pitch = { 0.95, 1.12 } },
		},
		vfx = {
			leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 5, leafColor = Color3.new(1, 1, 1), snipFlash = true,
			trim = {
				seconds = 0.18, fadeSeconds = 0.35, color = Color3.fromRGB(139, 224, 90), transparency = 0.55,
				spraySeconds = 0.32, sprayPoint = "BladeMid", sprayColor = Color3.new(1, 1, 1),
				sparkPoint = "BladeRoot", sparkColor = Color3.fromRGB(255, 178, 56),
			},
		},
	},
	-- Spring-loaded gadget (assets/tools/Uncommon/SpringLoadedPicker, from the creator's reference
	-- render, built like the weapon pack: flat plates, flat colours, dark outline plates). Numbers
	-- come from build_spring_loaded_picker.py: the D-grip mesh is centred 1.053 ahead of and 0.093
	-- above the grip (the rear bar), the barrel runs 0.6 above the grip (tool Z = Blender Y here),
	-- coil from x 1.5 to 3.0, front collar at 3.0, jaw bolts at (3.67, +-0.15 off the barrel).
	-- Design canvas: "Spring-Loaded Picker — Tool Design".
	SpringLoadedPicker = {
		rarity = "Uncommon",
		model = {
			template = "SpringLoadedPicker", handle = "PickerHandle", gripFromCentre = -1.053, gripSide = -0.093,
			head = "PickerJawTop",
			materials = {
				PickerHandle = Enum.Material.SmoothPlastic, PickerHead = Enum.Material.SmoothPlastic,
				PickerSpring = Enum.Material.Metal, PickerRod = Enum.Material.Metal, PickerLatch = Enum.Material.Metal,
				PickerJawTop = Enum.Material.Metal, PickerJawBottom = Enum.Material.Metal,
			},
			-- The rod (with the red head welded on) slides on the Plunger motor; the jaws hang off the
			-- rod so they ride it; the latch flips on the handle; the coil stretches between the rear
			-- collar and the head (stretch).
			joints = {
				PickerRod = { motor = "Plunger", pivot = Vector3.new(3.0, 0, 0.6) },
				PickerJawTop = { motor = "JawTop", pivot = Vector3.new(3.67, 0, 0.75), on = "PickerRod" },
				PickerJawBottom = { motor = "JawBottom", pivot = Vector3.new(3.67, 0, 0.45), on = "PickerRod" },
				PickerLatch = { motor = "Latch", pivot = Vector3.new(0.98, 0, 0.44) },
				PickerSpring = { motor = "Spring", pivot = Vector3.new(1.5, 0, 0.6) },
			},
			welds = { PickerHead = "PickerRod" },
			stretch = { PickerSpring = { motor = "Spring", follow = "Plunger", length = 1.5 } },
			-- Held like a saw: the hand on the D grip's rear bar, the barrel straight ahead above the
			-- hand, rolled a little so the camera behind the player sees the coil's top and the latch side.
			grip = ToolPresentation.hold(Vector3.new(0, 0.05, -1), Vector3.new(-0.9, 0.35, 0)),
			points = {
				ClawTip = Vector3.new(4.58, 0, 0.6), Muzzle = Vector3.new(3.22, 0, 0.6),
				SpringMid = Vector3.new(2.25, 0, 0.6), SpringRear = Vector3.new(1.5, 0, 0.6),
			},
		},
		clips = {
			-- Drawn from the hip with a test pump of the spring (Shing = the ratchet click).
			Equip = { seconds = 0.34, keys = {
				{ t = 0, pose = { RightShoulder = { -75, 0, 0 }, RightWrist = { 0, 0, 35 }, Plunger = { 0, 0, 0, -0.35, 0, 0 } } },
				{ t = 0.55, pose = { RightShoulder = { 8, 0, 0 }, RightWrist = { 0, 0, -8 }, Plunger = { 0, 0, 0, 0.3, 0, 0 },
					JawTop = { 0, 8, 0 }, JawBottom = { 0, -8, 0 } }, ease = "Back" },
				{ t = 0.75, pose = { RightShoulder = { 2, 0, 0 }, Plunger = { 0, 0, 0, -0.1, 0, 0 } } },
				{ t = 1, pose = {} },
			}, markers = { Shing = 0.55 } },
			-- Ready stance: a small sway, the head bobbing on its spring.
			Idle = { seconds = 2.4, loop = true, keys = {
				{ t = 0, pose = { RightShoulder = { 0, 0, 0 }, Plunger = { 0, 0, 0, 0, 0, 0 } } },
				{ t = 0.5, pose = { RightShoulder = { 3, 1, 0 }, RightWrist = { 2, 0, 0 }, Plunger = { 0, 0, 0, 0.05, 0, 0 } } },
				{ t = 1, pose = { RightShoulder = { 0, 0, 0 }, Plunger = { 0, 0, 0, 0, 0, 0 } } },
			} },
			-- Spring Dash, 0.55 s = Config.Tools.SpringLoadedPicker.swingSeconds. Coil: the arm draws
			-- in, the head pulls back 0.45 (coil squashed to 70%), the latch cocks and the jaws gape.
			-- Fire (Dash marker, 0.15 s): the latch flips, the head shoots out 0.6 (coil 140%), the
			-- jaws snap shut and the character lunges. Boing: the head bobs back and forth past rest
			-- with the coil squashing and stretching, the jaws reopen, settle.
			Swing = { seconds = 0.55, keys = {
				{ t = 0, pose = {} },
				{ t = 0.25, pose = { RightShoulder = { -6, 0, 0 }, RightElbow = { 22, 0, 0 }, RightWrist = { -10, 0, 0 },
					Plunger = { 0, 0, 0, -0.45, 0, 0 }, Latch = { 0, -12, 0 }, JawTop = { 0, -6, 0 }, JawBottom = { 0, 6, 0 } }, ease = "Quad" },
				{ t = 0.31, pose = { RightShoulder = { 12, 0, 0 }, RightElbow = { -4, 0, 0 }, RightWrist = { 8, 0, 0 },
					Plunger = { 0, 0, 0, 0.6, 0, 0 }, Latch = { 0, 35, 0 }, JawTop = { 0, 11, 0 }, JawBottom = { 0, -11, 0 } }, ease = "Linear" },
				{ t = 0.45, pose = { RightShoulder = { 10, 0, 0 }, RightWrist = { 4, 0, 0 },
					Plunger = { 0, 0, 0, -0.22, 0, 0 }, Latch = { 0, 35, 0 }, JawTop = { 0, 11, 0 }, JawBottom = { 0, -11, 0 } } },
				{ t = 0.6, pose = { RightShoulder = { 9, 0, 0 }, RightWrist = { 2, 0, 0 },
					Plunger = { 0, 0, 0, 0.22, 0, 0 }, Latch = { 0, 30, 0 }, JawTop = { 0, 10, 0 }, JawBottom = { 0, -10, 0 } } },
				{ t = 0.74, pose = { RightShoulder = { 6, 0, 0 }, Plunger = { 0, 0, 0, -0.08, 0, 0 }, Latch = { 0, 18, 0 },
					JawTop = { 0, 4, 0 }, JawBottom = { 0, -4, 0 } } },
				{ t = 0.86, pose = { RightShoulder = { 3, 0, 0 }, Plunger = { 0, 0, 0, 0.04, 0, 0 }, Latch = { 0, 8, 0 } } },
				{ t = 1, pose = {}, ease = "Sine" },
			}, markers = { Dash = 0.27, Hit = 0.31 } },
		},
		sounds = {
			-- Original synthesised sounds (assets/tools/Uncommon/SpringLoadedPicker/audio), uploaded Nov 6
			-- 2026 through Studio's Import Queue. Swing is timed to the clip: ratchet clicks while the
			-- coil winds, the latch clack and the whoosh at the Dash marker (0.15 s). No "boing" in any
			-- of them (creator, Nov 6). Fallbacks: the Sickle's equip, the Pitchfork's thrust and the
			-- Sickle's snap (not the clippers' equip, which has a faint spring boing).
			Equip = { id = "rbxassetid://86204582948295", fallback = "rbxassetid://116936988986525", volume = 0.3, pitch = { 0.96, 1.04 } },
			Swing = { id = "rbxassetid://83120645218195", fallback = "rbxassetid://76327908959778", volume = 0.36, pitch = { 0.97, 1.03 } },
			Harvest = { id = "rbxassetid://114574428454749", fallback = "rbxassetid://125411384210572", volume = 0.45, pitch = { 0.95, 1.12 } },
		},
		vfx = {
			leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 5, leafColor = Color3.new(1, 1, 1), snipFlash = true,
			dash = {
				trailColors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 140, 120) }, trailSeconds = 0.22, width = 3,
				dustColor = Color3.fromRGB(214, 190, 146), dustCount = 10, sparkPoint = "ClawTip",
			},
		},
	},
	-- A cowboy rope from the creator's reference render (assets/tools/Uncommon/CornLasso, in the
	-- weapon-pack style: flat colour per face, chunky low-poly tubes). Numbers come from
	-- build_corn_lasso.py: grip from -0.85 to 0.80 along X (centre 0.025 behind the grip), the
	-- coil, loop and tassels hang on Blender +Y (sideMargin 0.53), so tool Z is the hanging side and
	-- Blender (x, y, z) -> tool (x, z, y) for points on the profile. The loop's motor turns it in
	-- its own plane about the point where the rope leaves the collar.
	CornLasso = {
		rarity = "Uncommon",
		model = {
			template = "CornLasso", handle = "LassoHandle", gripFromCentre = 0.025, head = "LassoLoop",
			materials = {
				LassoHandle = Enum.Material.Leather, LassoFittings = Enum.Material.Metal, LassoTassels = Enum.Material.Leather,
				LassoCoil = Enum.Material.Fabric, LassoLoop = Enum.Material.Fabric,
			},
			joints = { LassoLoop = { motor = "Loop", pivot = Vector3.new(1.12, 0, 0.05) } },
			-- Right hand, handle forward and up a little, the rope hanging down and slightly right
			-- of the hand with the rings turned 45 degrees toward the camera behind the player.
			grip = ToolPresentation.hold(Vector3.new(0, 0.35, -1), Vector3.new(0.7, 0, 0.7)),
			points = {
				RopeOut = Vector3.new(1.12, 0, 0.05), Honda = Vector3.new(2.3, 0, 0.4),
				LoopCentre = Vector3.new(3.0, 0, 0.95), LoopFar = Vector3.new(3.85, 0, 0.95),
				CoilCentre = Vector3.new(1.55, 0, 0.75), Butt = Vector3.new(-1.25, 0, 0),
			},
		},
		clips = {
			-- Drawn from the hip; the loop flips round into place.
			Equip = { seconds = 0.34, keys = {
				{ t = 0, pose = { RightShoulder = { -70, 0, 0 }, RightWrist = { 0, 0, 30 }, Loop = { 0, -140, 0 } } },
				{ t = 0.62, pose = { RightShoulder = { 8, 0, 0 }, RightWrist = { 0, 0, -8 }, Loop = { 0, 18, 0 } }, ease = "Back" },
				{ t = 1, pose = {} },
			}, markers = { Shing = 0.55 } },
			-- The loop sways a little on its own; the arm bobs.
			Idle = { seconds = 2.6, loop = true, keys = {
				{ t = 0, pose = { RightShoulder = { 0, 0, 0 }, Loop = { 0, -6, 0 } } },
				{ t = 0.5, pose = { RightShoulder = { 3, 0, 1 }, Loop = { 0, 9, 0 } } },
				{ t = 1, pose = { RightShoulder = { 0, 0, 0 }, Loop = { 0, -6, 0 } } },
			} },
			-- Long-Range Retrieval, 0.38 s = Config.Tools.CornLasso.swingSeconds. Twirl: the arm goes
			-- up and the loop spins a full turn on its motor (0.17 s). Throw marker at 0.48: the
			-- request goes out and the rope leaves (the held loop hides). Then a forward throw, a
			-- yank back as the rope cinches, and settle. The loop's motor returns to 0 while hidden.
			Swing = { seconds = 0.38, keys = {
				{ t = 0, pose = {} },
				{ t = 0.2, pose = { RightShoulder = { 70, 0, 6 }, RightElbow = { 10, 0, 0 }, RightWrist = { 0, 0, 0 },
					Waist = { 0, -4, 0 }, Loop = { 0, 200, 0 } }, ease = "Quad" },
				{ t = 0.44, pose = { RightShoulder = { 78, 0, 0 }, RightElbow = { 14, 0, 0 }, RightWrist = { -20, 0, 0 },
					Waist = { 0, -8, 0 }, Loop = { 0, 360, 0 } }, ease = "Linear" },
				{ t = 0.58, pose = { RightShoulder = { -12, 0, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { 22, 0, 0 },
					Waist = { 0, 8, 0 }, Neck = { 0, -3, 0 }, Loop = { 0, 360, 0 } }, ease = "Quad" },
				{ t = 0.62, pose = { RightShoulder = { -10, 0, 0 }, RightWrist = { 18, 0, 0 }, Waist = { 0, 7, 0 }, Loop = { 0, 0, 0 } } },
				{ t = 0.8, pose = { RightShoulder = { 16, 0, 0 }, RightWrist = { -14, 0, 0 }, Waist = { 0, -3, 0 } }, ease = "Quad" },
				{ t = 1, pose = {}, ease = "Sine" },
			}, markers = { Throw = 0.48, Hit = 0.48 } },
		},
		sounds = {
			-- Original synthesised sounds (assets/tools/Uncommon/CornLasso/audio), uploaded Nov 6 2026
			-- through the Import Queue: a leather creak and swish (Equip), two twirl whirs into the
			-- throw whoosh (Swing), a rope zip and stalk snap as the loop cinches (Harvest) and a soft
			-- catch when an ear reaches the hand (Pull). Fallbacks: the Sickle's air swoosh and the
			-- shared stalk snap.
			Equip = { id = "rbxassetid://124286860237545", fallback = nil, volume = 0.3, pitch = { 0.96, 1.04 } },
			Swing = { id = "rbxassetid://93656581803685", fallback = "rbxassetid://136321679774475", volume = 0.36, pitch = { 0.95, 1.05 } },
			Harvest = { id = "rbxassetid://80614267956626", fallback = "rbxassetid://125411384210572", volume = 0.46, pitch = { 0.94, 1.08 } },
			Pull = { id = "rbxassetid://84040969145635", fallback = nil, volume = 0.32, pitch = { 0.95, 1.1 } },
		},
		vfx = {
			leafTexture = ToolPresentation.Textures.LeafFleck, leavesPerStalk = 4, leafColor = Color3.new(1, 1, 1), snipFlash = true,
			lasso = {
				speed = 140, rise = 1.2, openRadius = 1.25, cinchRadius = 0.34, spinTurns = 1.5,
				waitSeconds = 0.35, cinchSeconds = 0.1, backSeconds = 0.34, ropePoint = "RopeOut", loopMesh = "LassoLoop",
				ropeColor = Color3.fromRGB(200, 165, 119), ropeShade = Color3.fromRGB(156, 124, 82), ropeWidth = 0.15,
				earColor = Color3.fromRGB(255, 204, 44), huskColor = Color3.fromRGB(200, 214, 122),
				trailColors = { Color3.fromRGB(255, 244, 186), Color3.fromRGB(255, 196, 40) },
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
		-- A joint hung on another mesh needs that mesh to be a moving joint itself (else weld it).
		for part, joint in model.joints or {} do
			assert(joint.on == nil or (joint.on ~= part and (model.joints :: any)[joint.on] ~= nil),
				toolId .. " joint " .. part .. " hangs on " .. tostring(joint.on) .. ", which is not a joint")
		end
		local motors: { [string]: boolean } = {}
		for _, joint in model.joints or {} do motors[joint.motor] = true end
		for part, spec in model.stretch or {} do
			local own = (model.joints or {})[part]
			assert(own and own.motor == spec.motor and motors[spec.follow] and spec.follow ~= spec.motor and spec.length > 0,
				toolId .. " stretch " .. part .. " needs its own joint and a followed motor")
		end
		local dash = look.vfx.dash
		if dash then
			assert(dash.trailSeconds > 0 and dash.width > 0 and dash.dustCount >= 0 and #dash.trailColors >= 1
				and look.model.points[dash.sparkPoint] ~= nil, toolId .. " dash effect is invalid")
			assert(look.clips.Swing and look.clips.Swing.markers and look.clips.Swing.markers.Dash, toolId .. " dash needs a Dash marker")
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
		local wind = look.vfx.wind
		if wind then
			assert(wind.seconds > 0 and wind.degrees > 0 and wind.degrees <= 360 and #wind.radii >= 1 and #wind.radii <= 3
				and #wind.colors >= 1, toolId .. " wind effect is invalid")
			for _, radius in wind.radii do assert(radius > wind.width / 2, toolId .. " wind ribbon overlaps the player") end
			assert(look.clips.Swing and look.clips.Swing.markers and look.clips.Swing.markers.Sweep, toolId .. " wind needs a Sweep marker")
		end
		local lasso = look.vfx.lasso
		if lasso then
			assert(lasso.speed > 0 and lasso.openRadius > lasso.cinchRadius and lasso.cinchRadius > 0 and lasso.backSeconds > 0
				and lasso.waitSeconds >= 0 and lasso.cinchSeconds > 0 and lasso.ropeWidth > 0 and #lasso.trailColors >= 1,
				toolId .. " lasso effect is invalid")
			assert(look.model.points[lasso.ropePoint] ~= nil, toolId .. " lasso names a missing rope point")
			assert(look.clips.Swing and look.clips.Swing.markers and look.clips.Swing.markers.Throw, toolId .. " lasso needs a Throw marker")
		end
		local trim = look.vfx.trim
		if trim then
			assert(trim.seconds > 0 and trim.fadeSeconds > 0 and trim.spraySeconds > 0 and trim.transparency >= 0 and trim.transparency < 1,
				toolId .. " trim effect is invalid")
			assert(look.model.points[trim.sprayPoint] and look.model.points[trim.sparkPoint], toolId .. " trim effect names a missing point")
			assert(look.clips.Swing and look.clips.Swing.markers and look.clips.Swing.markers.Hit, toolId .. " trim needs a Hit marker")
		end
		for name, clip in look.clips do
			local buzz = clip.buzz
			if buzz then
				assert(buzz.from >= 0 and buzz.to <= 1 and buzz.from < buzz.to and buzz.hz > 0, toolId .. "." .. name .. " buzz is invalid")
			end
		end
	end
end

return ToolPresentation
