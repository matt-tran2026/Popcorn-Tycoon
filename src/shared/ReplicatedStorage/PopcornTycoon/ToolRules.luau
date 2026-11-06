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
local function inArc(flatFacing: Vector3, candidates: { Types.TargetCandidate }, origin: Vector3, tool: Types.ToolDefinition): { Hit }
	local halfArc = math.rad((tool.arcDegrees or 0) / 2)
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
-- in reach. The tool's behaviour picks the shape (arc or lane).
function ToolRules.pickTargets(origin: Vector3, facing: Vector3, candidates: { Types.TargetCandidate }, tool: Types.ToolDefinition): { string }
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatFacing.Magnitude < 1e-3 then return {} end
	flatFacing = flatFacing.Unit
	local hits = if tool.behavior == "LineHarvest"
		then inLane(flatFacing, candidates, origin, tool)
		else inArc(flatFacing, candidates, origin, tool)
	return nearest(hits, tool.maxTargets)
end

return ToolRules
