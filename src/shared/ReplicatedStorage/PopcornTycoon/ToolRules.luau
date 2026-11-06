--!strict
-- Pure targeting for swung tools, shared so the client preview matches the server's choice.
-- The server is still the only one that decides and awards a harvest.
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
-- the lane, so the thrust pierces the row front to back.
local function inLane(flatFacing: Vector3, candidates: { Types.TargetCandidate }, origin: Vector3, tool: Types.ToolDefinition): { Hit }
	local halfWidth = (tool.laneWidth or 0) / 2
	local hits: { Hit } = {}
	local seen: { [string]: boolean } = {}
	for _, candidate in candidates do
		local offset = Vector3.new(candidate.position.X - origin.X, 0, candidate.position.Z - origin.Z)
		local ahead = offset:Dot(flatFacing)
		local aside = math.abs((offset - flatFacing * ahead).Magnitude)
		if not seen[candidate.id] and ahead == ahead and aside == aside
			and ahead >= -ToolRules.LaneBehind and ahead <= tool.reach and aside <= halfWidth then
			seen[candidate.id] = true
			table.insert(hits, { id = candidate.id, distance = ahead })
		end
	end
	return hits
end

-- Ripe candidates the tool's next action would harvest from `origin` facing `facing`, nearest
-- first, at most maxTargets. Heights are ignored so a stalk's size never changes whether it is
-- in reach. The tool's behaviour picks the shape (arc or lane). Alternating tools (Twin
-- Sickles) pass the swing's shape: a hand swing turns the arc's centre sideDegrees toward that
-- hand, and a combo swing uses the wider combo arc, centred on the facing direction.
function ToolRules.pickTargets(origin: Vector3, facing: Vector3, candidates: { Types.TargetCandidate }, tool: Types.ToolDefinition, shape: Types.SwingShape?): { string }
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
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
	local hits = if tool.behavior == "LineHarvest"
		then inLane(flatFacing, candidates, origin, tool)
		else inArc(flatFacing, candidates, origin, tool, arc)
	return nearest(hits, tool.maxTargets)
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
