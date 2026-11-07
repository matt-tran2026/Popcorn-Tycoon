--!strict
-- Pure targeting for swung tools, shared so the client preview matches the server's choice.
-- The server is still the only one that decides and awards a harvest. (dashReach is the one
-- exception that reads the world: a shape cast both sides run the same way.)
local Types = require(script.Parent.Types)
local ToolRules = {}

-- A stalk this close (flat distance) counts as underfoot: in front, whatever the angle.
local UNDERFOOT = 0.5
-- LineHarvest lanes start this far behind the character, so a stalk the player is standing
-- in (its centre just behind the root part) still counts as the first in the row.
ToolRules.LaneBehind = 1

type Hit = { id: string, distance: number }

-- Nearest first (ties by id, so the server and the client preview agree), at most maxTargets.
local function nearest(hits: { Hit }, maxTargets: number): { string }
	table.sort(hits, function(a, b)
		if a.distance ~= b.distance then return a.distance < b.distance end
		return a.id < b.id
	end)
	local picked: { string } = {}
	for i = 1, math.min(maxTargets, #hits) do picked[i] = hits[i].id end
	return picked
end

-- ArcSweep / SingleTarget / PullHarvest: inside reach and within arcDegrees / 2 of the facing
-- direction. (PullHarvest is the Harvest Hook's long narrow cone; the pull itself is visual.)
local function inArc(flatFacing: Vector3, candidates: { Types.TargetCandidate }, origin: Vector3, tool: Types.ToolDefinition, arcDegrees: number?): { Hit }
	local halfArc = math.rad((arcDegrees or tool.arcDegrees or 0) / 2)
	local hits: { Hit } = {}
	local seen: { [string]: boolean } = {}
	for _, candidate in candidates do
		local offset = Vector3.new(candidate.position.X - origin.X, 0, candidate.position.Z - origin.Z)
		local distance = offset.Magnitude
		if not seen[candidate.id] and distance == distance and distance <= tool.reach then
			local angle = if distance < UNDERFOOT then 0 else math.acos(math.clamp(offset.Unit:Dot(flatFacing), -1, 1))
			if angle <= halfArc then
				seen[candidate.id] = true
				table.insert(hits, { id = candidate.id, distance = distance })
			end
		end
	end
	return hits
end

-- LineHarvest (Pitchfork): a straight lane along the facing direction, from LaneBehind studs
-- behind the character to reach studs ahead, laneWidth studs wide. Ordered by distance along
-- the lane, so the thrust pierces the row front to back. DashHarvest uses the same lane with
-- `reach` cut short at a wall (ToolRules.dashReach).
local function inLane(flatFacing: Vector3, candidates: { Types.TargetCandidate }, origin: Vector3, tool: Types.ToolDefinition, reach: number): { Hit }
	local halfWidth = (tool.laneWidth or 0) / 2
	local hits: { Hit } = {}
	local seen: { [string]: boolean } = {}
	for _, candidate in candidates do
		local offset = Vector3.new(candidate.position.X - origin.X, 0, candidate.position.Z - origin.Z)
		local ahead = offset:Dot(flatFacing)
		local aside = math.abs((offset - flatFacing * ahead).Magnitude)
		if not seen[candidate.id] and ahead == ahead and aside == aside
			and ahead >= -ToolRules.LaneBehind and ahead <= reach and aside <= halfWidth then
			seen[candidate.id] = true
			table.insert(hits, { id = candidate.id, distance = ahead })
		end
	end
	return hits
end

-- TargetedPull (Corn Lasso). The client aims at a ripe stalk and sends its position as `aim`.
-- The primary target is the candidate nearest the aim point within AimSnap studs (flat), and it
-- must lie within reach (+ slack) of `origin`; with no aim, the nearest candidate in an AimCone
-- ahead. The loop then snags the nearest other candidates within loopRadius of the primary
-- (also within reach), up to maxTargets in all, primary first. The server passes ReachSlack
-- for the character's lag; the client's preview passes none, so it never promises more.
ToolRules.AimSnap = 2.5
ToolRules.AimCone = 40
ToolRules.ReachSlack = 2
local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function ToolRules.lassoTargets(origin: Vector3, flatFacing: Vector3?, candidates: { Types.TargetCandidate }, tool: Types.ToolDefinition, aim: Vector3?, slack: number?): { string }
	local reach = tool.reach + math.max(0, slack or 0)
	local primary: Types.TargetCandidate? = nil
	if aim and aim.X == aim.X and aim.Y == aim.Y and aim.Z == aim.Z
		and math.abs(aim.X) < math.huge and math.abs(aim.Z) < math.huge then
		local best = math.huge
		for _, candidate in candidates do
			local off = flatDistance(candidate.position, aim)
			local away = flatDistance(candidate.position, origin)
			if off == off and away == away and off <= ToolRules.AimSnap and away <= reach then
				local current = primary
				if off < best or (off == best and current and candidate.id < current.id) then
					primary, best = candidate, off
				end
			end
		end
	elseif flatFacing then
		local ids = nearest(inArc(flatFacing, candidates, origin, tool, ToolRules.AimCone), 1)
		for _, candidate in candidates do
			if candidate.id == ids[1] then primary = candidate break end
		end
	end
	local first = primary
	if not first then return {} end
	local others: { Hit } = {}
	local seen: { [string]: boolean } = { [first.id] = true }
	for _, candidate in candidates do
		local near = flatDistance(candidate.position, first.position)
		if not seen[candidate.id] and near == near and near <= (tool.loopRadius or 0)
			and flatDistance(candidate.position, origin) <= reach then
			seen[candidate.id] = true
			table.insert(others, { id = candidate.id, distance = near })
		end
	end
	local picked = { first.id }
	for _, id in nearest(others, tool.maxTargets - 1) do table.insert(picked, id) end
	return picked
end

-- Ripe candidates the tool's next action would harvest from `origin` facing `facing`, nearest
-- first, at most maxTargets. Heights are ignored so a stalk's size never changes whether it is
-- in reach. The tool's behaviour picks the shape (arc or lane). Alternating tools (Twin
-- Sickles) pass the swing's shape: a hand swing turns the arc's centre sideDegrees toward that
-- hand, and a combo swing uses the wider combo arc, centred on the facing direction. Dash tools
-- pass the lane length the dash really covers (`reach`, from ToolRules.dashReach). Targeted
-- tools (Corn Lasso) pass the aim point and, on the server, the reach slack (lassoTargets).
function ToolRules.pickTargets(origin: Vector3, facing: Vector3, candidates: { Types.TargetCandidate }, tool: Types.ToolDefinition, shape: Types.SwingShape?, reach: number?, aim: Vector3?, slack: number?): { string }
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if tool.behavior == "TargetedPull" then
		return ToolRules.lassoTargets(origin, if flatFacing.Magnitude < 1e-3 then nil else flatFacing.Unit, candidates, tool, aim, slack)
	end
	if flatFacing.Magnitude < 1e-3 then return {} end
	flatFacing = flatFacing.Unit
	local arc: number? = nil
	if shape then
		if shape.combo and tool.combo then
			arc = tool.combo.arcDegrees
		elseif tool.sideDegrees then
			-- A positive turn about +Y swings the facing toward the character's left.
			local turn = math.rad(tool.sideDegrees) * (if shape.hand == "Right" then -1 else 1)
			flatFacing = CFrame.fromAxisAngle(Vector3.yAxis, turn):VectorToWorldSpace(flatFacing)
		end
	end
	local hits = if ToolRules.usesLane(tool)
		then inLane(flatFacing, candidates, origin, tool, math.min(reach or tool.reach, tool.reach))
		else inArc(flatFacing, candidates, origin, tool, arc)
	return nearest(hits, tool.maxTargets)
end

-- Whether a tool harvests a straight lane (LineHarvest, DashHarvest) rather than an arc.
function ToolRules.usesLane(tool: Types.ToolDefinition): boolean
	return tool.behavior == "LineHarvest" or tool.behavior == "DashHarvest"
end

-- DashHarvest: how far the dash really goes. A box the size of the character's body (from
-- knee height to the top of the head, DashBody studs wide) is swept along the flat facing from
-- the root part; the dash stops DashClearance short of the first solid thing it would hit
-- (walls, fences and their invisible barriers, stations; walk-through crops and every
-- character are ignored). Both the server (to cut the lane short) and the client (to stop the
-- lunge) call it with the same inputs, so the harvest lane and the movement end in the same
-- place. This is the one function here that reads the world.
ToolRules.DashClearance = 1.5
ToolRules.DashBody = Vector3.new(2, 3.4, 1)
function ToolRules.dashReach(rootCFrame: CFrame, tool: Types.ToolDefinition, ignore: { Instance }): number
	local facing = Vector3.new(rootCFrame.LookVector.X, 0, rootCFrame.LookVector.Z)
	if facing.Magnitude < 1e-3 then return 0 end
	facing = facing.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	-- The box's centre sits 0.4 below the root, so it spans about knee to head height.
	local start = CFrame.lookAt(rootCFrame.Position - Vector3.new(0, 0.4, 0), rootCFrame.Position - Vector3.new(0, 0.4, 0) + facing)
	local hit = workspace:Blockcast(start, ToolRules.DashBody, facing * tool.reach, params)
	if not hit then return tool.reach end
	return math.clamp(hit.Distance - ToolRules.DashClearance, 0, tool.reach)
end

-- Alternating tools. A fresh state starts on the right hand with no streak.
function ToolRules.newCombo(): Types.ComboState
	return { hand = "Right", streak = 0, lastHit = -math.huge }
end

-- Whether a tool alternates hands (and so takes a SwingShape).
function ToolRules.alternates(tool: Types.ToolDefinition): boolean
	return tool.sideDegrees ~= nil or tool.combo ~= nil
end

-- The next swing: the hand whose turn it is, and the combo if the last `every - 1` swings all
-- harvested and the latest hit is no older than the combo window. Pure: clock is passed in.
function ToolRules.nextSwing(tool: Types.ToolDefinition, state: Types.ComboState, clock: number): Types.SwingShape
	local combo = tool.combo
	local ready = combo ~= nil and state.streak >= combo.every - 1 and clock - state.lastHit <= combo.windowSeconds
	return { hand = state.hand, combo = ready }
end

-- Advances the state after a swing of `shape`: the hands take turns on every swing, a hit
-- extends the streak (restarting it if the window ran out), and a miss or a combo swing ends it.
function ToolRules.afterSwing(tool: Types.ToolDefinition, state: Types.ComboState, shape: Types.SwingShape, harvested: boolean, clock: number)
	state.hand = if shape.hand == "Right" then "Left" else "Right"
	local combo = tool.combo
	if not combo then return end
	if shape.combo or not harvested then
		state.streak = 0
	else
		if clock - state.lastHit > combo.windowSeconds then state.streak = 0 end
		state.streak += 1
	end
	if harvested then state.lastHit = clock end
end

return ToolRules
