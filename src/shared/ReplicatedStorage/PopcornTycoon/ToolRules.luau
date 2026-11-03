--!strict
-- Pure targeting for swung tools, shared so the client preview matches the server's choice.
-- The server is still the only one that decides and awards a harvest.
local Types = require(script.Parent.Types)
local ToolRules = {}

-- Ripe candidates inside the tool's flat sweep in front of `origin`, nearest first, at most
-- maxTargets. Heights are ignored so a stalk's size never changes whether it is in reach.
function ToolRules.pickTargets(origin: Vector3, facing: Vector3, candidates: { Types.TargetCandidate }, tool: Types.ToolDefinition): { string }
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatFacing.Magnitude < 1e-3 then return {} end
	flatFacing = flatFacing.Unit
	local halfArc = math.rad(tool.arcDegrees / 2)
	local inRange: { { id: string, distance: number } } = {}
	local seen: { [string]: boolean } = {}
	for _, candidate in candidates do
		local offset = Vector3.new(candidate.position.X - origin.X, 0, candidate.position.Z - origin.Z)
		local distance = offset.Magnitude
		if not seen[candidate.id] and distance == distance and distance <= tool.reach then
			-- A stalk right underfoot counts as in front.
			local angle = if distance < 0.5 then 0 else math.acos(math.clamp(offset.Unit:Dot(flatFacing), -1, 1))
			if angle <= halfArc then
				seen[candidate.id] = true
				table.insert(inRange, { id = candidate.id, distance = distance })
			end
		end
	end
	table.sort(inRange, function(a, b)
		if a.distance ~= b.distance then return a.distance < b.distance end
		return a.id < b.id
	end)
	local picked: { string } = {}
	for i = 1, math.min(tool.maxTargets, #inRange) do picked[i] = inRange[i].id end
	return picked
end

return ToolRules
