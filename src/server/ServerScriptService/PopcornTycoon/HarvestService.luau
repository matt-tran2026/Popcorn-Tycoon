--!strict
-- Every harvest path (hand prompts and swung tools) goes through take(), so maturity,
-- capacity, partial fits and regrowth follow one rule.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Growth = require(Shared.Growth)
local ToolRules = require(Shared.ToolRules)
local Types = require(Shared.Types)
local FarmUpgrades = require(Shared.FarmUpgrades)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)
local lastAttempt: { [number]: number } = {}
-- When each player's next swing is due (os.clock). See HarvestService.swing.
local swingDue: { [number]: number } = {}
-- Alternating tools (Twin Sickles): whose hand is next and the streak toward the combo, per
-- player, for the tool it was counted with (switching tools starts afresh).
local combos: { [number]: { toolId: string, state: Types.ComboState } } = {}
-- Held tools (Weed Whacker, ContinuousHarvest): per player, the tool, its heat (ToolRules
-- HeatState on the server clock ToolService passes in) and when the next cut is due.
local cutters: { [number]: { toolId: string, heat: Types.HeatState, nextCut: number } } = {}
local HarvestService = {}

local function result(ok: boolean, reason: string, amount: number?): Types.HarvestResult
	return { ok = ok, reason = reason, amount = amount or 0 }
end

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return nil end
	return root
end

-- Take the ready cycles of one stalk that fit in the bag. One cycle is worth the field's corn
-- per cycle (Corn Yield upgrade) times the tool's multiplier; only whole cycles are taken and
-- the stalk keeps the rest (its timer is backdated so exactly the remainder stays ready, under
-- the field's own growth time). Returns corn granted, cycles that were ready, and whether
-- any ready cycle had to stay on the stalk because the bag ran out of room.
-- Must not yield: callers rely on validation and commit happening in one step.
local function take(profile: Types.Profile, field: Types.Field, stalk: Types.Stalk, at: number, multiplier: number): (number, number, boolean)
	local rules = FarmUpgrades.fieldRules(field)
	local available = Growth.yields(stalk.growthStartedAt, at, rules)
	local perCycle = rules.cornPerYield * multiplier
	local space = math.max(0, State.bagCapacity(profile) - State.carried(profile))
	local taken = math.min(available, space // perCycle)
	if taken <= 0 then return 0, available, available > 0 end
	local corn = taken * perCycle
	profile.rawCorn[field.cropId] = (profile.rawCorn[field.cropId] or 0) + corn
	stalk.growthStartedAt = at - (available - taken) * rules.growthSeconds
	return corn, available, taken < available
end

-- Hand picking through a stalk's prompt, only with empty hands: while a swung tool is held, corn
-- comes only from its swings (creator, Nov 6 2026; before, E still picked mid-cooldown).
function HarvestService.attempt(player: Player, ownerUserId: unknown, fieldId: unknown, stalkId: unknown): Types.HarvestResult
	local clock = os.clock()
	local previous = lastAttempt[player.UserId]
	if previous and clock - previous < Config.Manual.cooldownSeconds then return result(false, "Too fast") end
	lastAttempt[player.UserId] = clock
	if typeof(ownerUserId) ~= "number" or typeof(fieldId) ~= "string" or typeof(stalkId) ~= "string" then
		return result(false, "Invalid target")
	end
	if ownerUserId ~= player.UserId then return result(false, "Not your field") end
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	if not profile.ownedTools.Manual then return result(false, "Manual tool required") end
	if Config.Tools[profile.equippedTool] then return result(false, "Swing your tool to harvest") end
	local field = profile.fields[fieldId]
	if not field or field.ownerUserId ~= player.UserId then return result(false, "Not your field") end
	local stalk = field.stalks[stalkId]
	local target = Farms.target(player.UserId, fieldId, stalkId)
	if not stalk or not target then return result(false, "Invalid target") end
	local root = livingRoot(player)
	if not root then return result(false, "Character unavailable") end
	local distance = (root.Position - target.Position).Magnitude
	if distance ~= distance or distance > Config.Manual.range then return result(false, "Too far away") end
	if not Config.Crops[field.cropId] then return result(false, "Invalid crop") end
	local at = now()
	local corn, available, leftOver = take(profile, field, stalk, at, 1)
	if available == 0 then return result(false, "Corn is growing") end
	if corn == 0 then return result(false, "Bag full · pop it at the microwave") end
	player:SetAttribute("RawCorn", State.carried(profile))
	return result(true, if leftOver then "Bag full" else "Harvested", corn)
end

-- The player's ripe stalks, from every owned plot, as targeting candidates (each remembers its
-- plot). Only ripe stalks are candidates, so growing corn never soaks up a tool's targets.
local function ripeCandidates(player: Player, profile: Types.Profile, at: number): ({ Types.TargetCandidate }, { [string]: Types.Field })
	local candidates: { Types.TargetCandidate } = {}
	local fieldOf: { [string]: Types.Field } = {}
	local rulesOf: { [string]: Types.GrowthRules } = {}
	for fieldId, field in profile.fields do
		if Config.Crops[field.cropId] then rulesOf[fieldId] = FarmUpgrades.fieldRules(field) end
	end
	for id, part in Farms.stalkParts(player.UserId) do
		local fieldId = Farms.fieldOf(player.UserId, id)
		local field = if fieldId then profile.fields[fieldId] else nil
		local rules = if fieldId then rulesOf[fieldId] else nil
		local stalk = if field then field.stalks[id] else nil
		if field and rules and stalk and field.ownerUserId == player.UserId and Growth.yields(stalk.growthStartedAt, at, rules) > 0 then
			table.insert(candidates, { id = id, position = part.Position })
			fieldOf[id] = field
		end
	end
	return candidates, fieldOf
end

-- Takes every picked stalk that fits in the bag and builds the reply. Must not yield: callers
-- pick and commit in one step.
local function commit(player: Player, profile: Types.Profile, toolId: string, tool: Types.ToolDefinition, picked: { string }, fieldOf: { [string]: Types.Field }, at: number): Types.HarvestResult
	if State.carried(profile) >= State.bagCapacity(profile) then
		return result(false, "Bag full · pop it at the microwave")
	end
	local total, full = 0, false
	local targets: { Vector3 } = {}
	for _, id in picked do
		local field = fieldOf[id]
		local corn, _, leftOver = take(profile, field, field.stalks[id], at, tool.yieldMultiplier)
		if corn > 0 then
			total += corn
			table.insert(targets, (Farms.target(player.UserId, field.id, id) :: Part).Position)
		end
		if leftOver then full = true end
	end
	if total == 0 then return result(false, "Bag full · pop it at the microwave") end
	player:SetAttribute("RawCorn", State.carried(profile))
	local response = result(true, if full then "Bag full" else "Harvested", total)
	response.tool, response.targets = toolId, targets
	return response
end

-- One swing of an owned, equipped tool. The server picks the targets from the character's
-- position and facing; the client never names stalks. Targeted tools (Corn Lasso) also take the
-- client's aim point, which only says where it aimed: the server snaps it to one of the player's
-- own ripe stalks within reach of its own root part, or the throw takes nothing.
function HarvestService.swing(player: Player, toolId: string, aim: unknown?): Types.HarvestResult
	local tool = Config.Tools[toolId]
	if not tool then return result(false, "Unknown tool") end
	if tool.behavior ~= "ArcSweep" and tool.behavior ~= "SingleTarget" and tool.behavior ~= "LineHarvest"
		and tool.behavior ~= "PullHarvest" and tool.behavior ~= "DashHarvest" and tool.behavior ~= "TargetedPull" then
		return result(false, "Unknown tool")
	end
	-- Only a finite Vector3 counts as an aim, and only for targeted tools.
	local aimPoint: Vector3? = nil
	if tool.behavior == "TargetedPull" and typeof(aim) == "Vector3" then
		local v = aim :: Vector3
		if v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6 then aimPoint = v end
	end
	-- Cadence: each accepted swing moves the due time one cooldown on from the later of now and
	-- the previous due time, and a swing may arrive up to half a cooldown early. Network jitter
	-- between two honest swings (it matters at the clippers' 0.12 s) is absorbed, yet over any
	-- stretch no more than one swing per cooldown (plus one) is ever accepted.
	local clock = os.clock()
	local due = swingDue[player.UserId]
	if due and clock < due - tool.cooldownSeconds * 0.5 then return result(false, "Too fast") end
	swingDue[player.UserId] = math.max(clock, due or clock) + tool.cooldownSeconds
	local profile = State.get(player.UserId)
	if not profile then return result(false, "Profile unavailable") end
	if not profile.ownedTools[toolId] or profile.equippedTool ~= toolId then return result(false, tool.displayName .. " not equipped") end
	local root = livingRoot(player)
	if not root then return result(false, "Character unavailable") end
	-- Alternating tools: this swing's hand and whether it is the combo come from the server's own
	-- count of this player's swings (ToolRules.nextSwing); every outcome below advances it, and
	-- the response reports it so the client's prediction stays in step.
	local shape: Types.SwingShape? = nil
	local comboState: Types.ComboState? = nil
	if ToolRules.alternates(tool) then
		local entry = combos[player.UserId]
		if not entry or entry.toolId ~= toolId then
			entry = { toolId = toolId, state = ToolRules.newCombo() }
			combos[player.UserId] = entry
		end
		comboState = entry.state
		shape = ToolRules.nextSwing(tool, entry.state, clock)
	end
	local function outcome(response: Types.HarvestResult): Types.HarvestResult
		if shape and comboState then
			ToolRules.afterSwing(tool, comboState, shape, response.ok, clock)
			response.hand, response.combo, response.streak = shape.hand, shape.combo, comboState.streak
		end
		return response
	end
	local at = now()
	-- Candidates come from every owned plot; each stalk remembers its plot (Farms.fieldOf).
	local candidates, fieldOf = ripeCandidates(player, profile, at)
	-- ArcSweep and SingleTarget share the arc rule; SingleTarget tools have maxTargets 1 and a
	-- narrow arc (Config.validate), so they cut the one nearest ripe stalk in front. LineHarvest
	-- (Pitchfork) takes the nearest ripe stalks in a straight lane along the facing direction.
	-- PullHarvest (Harvest Hook) uses the arc rule with a long reach and a 60 degree cone.
	-- The Twin Sickles are ArcSweep with each hand's arc turned to its side and a combo arc.
	-- The shape comes from the server's own root part, never from the client.
	-- Alternating tools turn each hand's arc toward its side, and the combo widens it.
	-- DashHarvest (Spring-Loaded Picker): the lane the dash will travel from where the server sees
	-- the character now, cut short where a wall stops it (the client runs the same cast to stop
	-- the lunge there). Every character is ignored, so other players never shorten it.
	local dashReach: number? = nil
	if tool.behavior == "DashHarvest" then
		local ignore: { Instance } = {}
		for _, other in Players:GetPlayers() do
			if other.Character then table.insert(ignore, other.Character) end
		end
		dashReach = ToolRules.dashReach(root.CFrame, tool, ignore)
	end
	-- TargetedPull (Corn Lasso): the aimed stalk (snapped from the client's aim point, within
	-- reach of the server's root plus a little slack for lag) and the loop's neighbours.
	local slack = if tool.behavior == "TargetedPull" then ToolRules.ReachSlack else nil
	local picked = ToolRules.pickTargets(root.Position, root.CFrame.LookVector, candidates, tool, shape, dashReach, aimPoint, slack)
	if #picked == 0 then
		local missed = result(false, if tool.behavior == "TargetedPull" then "Aim at ripe corn in range" else "Swing closer to ripe corn")
		missed.dashReach = dashReach
		return outcome(missed)
	end
	-- No yields between picking targets and committing every take.
	local response = commit(player, profile, toolId, tool, picked, fieldOf, at)
	if response.ok then response.dashReach = dashReach end
	return outcome(response)
end

-- Held tools (ContinuousHarvest). The heat state of a player's cutter for this tool, made fresh
-- when they switch tools (so heat belongs to the tool it was built up on).
local function cutter(userId: number, toolId: string): { toolId: string, heat: Types.HeatState, nextCut: number }
	local entry = cutters[userId]
	if not entry or entry.toolId ~= toolId then
		entry = { toolId = toolId, heat = ToolRules.newHeat(), nextCut = -math.huge }
		cutters[userId] = entry
	end
	return entry
end

-- Starts (want true) or stops the engine of a held tool at `clock` (the server clock ToolService
-- uses for every cutter). Starting needs the tool owned and equipped, a living character and no
-- overheat lock; stopping always works. Returns the heat state for the Tool's attributes, or nil
-- for a tool that is not a held tool.
function HarvestService.hold(player: Player, toolId: string, want: boolean, clock: number): Types.HeatState?
	local tool = Config.Tools[toolId]
	if not tool or tool.behavior ~= "ContinuousHarvest" then return nil end
	local profile = State.get(player.UserId)
	if want and (not profile or not profile.ownedTools[toolId] or profile.equippedTool ~= toolId or not livingRoot(player)) then
		want = false
	end
	local entry = cutter(player.UserId, toolId)
	local was = entry.heat.running
	ToolRules.setRunning(tool, entry.heat, want, clock)
	-- A fresh start cuts at once; a stop-start never cuts sooner than the cadence allows.
	if entry.heat.running and not was then entry.nextCut = math.max(entry.nextCut, clock) end
	return entry.heat
end

-- The running held tool's id and heat state for a player, if any.
function HarvestService.cutterOf(userId: number): (string?, Types.HeatState?)
	local entry = cutters[userId]
	if not entry then return nil, nil end
	return entry.toolId, entry.heat
end

-- One tick of a player's held tool (ToolService's shared loop, every frame). Settles the heat
-- (an overheat stops it: second return true) and, when a cut is due, cuts the ripe stalk the
-- server's own targeting picks from its root part. Cadence: one cut per cooldownSeconds on
-- average (the due time moves on by a cooldown per cut) and never two within half a cooldown;
-- a tick with nothing in reach looks again half a cooldown later. Returns nil when nothing was
-- due. Losing the tool or the character stops the engine.
function HarvestService.cutTick(player: Player, clock: number): (Types.HarvestResult?, boolean)
	local entry = cutters[player.UserId]
	if not entry or not entry.heat.running then return nil, false end
	local tool = Config.Tools[entry.toolId]
	if ToolRules.settleHeat(tool, entry.heat, clock) then return nil, true end
	if clock < entry.nextCut then return nil, false end
	local profile = State.get(player.UserId)
	if not profile or not profile.ownedTools[entry.toolId] or profile.equippedTool ~= entry.toolId then
		ToolRules.setRunning(tool, entry.heat, false, clock)
		return result(false, tool.displayName .. " not equipped"), false
	end
	local root = livingRoot(player)
	if not root then
		ToolRules.setRunning(tool, entry.heat, false, clock)
		return result(false, "Character unavailable"), false
	end
	local at = now()
	local candidates, fieldOf = ripeCandidates(player, profile, at)
	local picked = ToolRules.pickTargets(root.Position, root.CFrame.LookVector, candidates, tool)
	if #picked == 0 then
		entry.nextCut = clock + tool.cooldownSeconds * 0.5
		return result(false, "Walk into ripe corn"), false
	end
	entry.nextCut = math.max(entry.nextCut + tool.cooldownSeconds, clock + tool.cooldownSeconds * 0.5)
	return commit(player, profile, entry.toolId, tool, picked, fieldOf, at), false
end

function HarvestService.release(userId: number)
	lastAttempt[userId] = nil
	swingDue[userId] = nil
	combos[userId] = nil
	cutters[userId] = nil
end

return HarvestService
