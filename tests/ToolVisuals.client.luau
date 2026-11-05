--!strict
-- Client half of the ToolVisuals Play runner (pair with ToolVisualsSetup.server.luau). Equips
-- the Sickle, measures the equip/idle/swing poses on the real avatar, the trail, and the
-- server-confirmed leaf burst, and writes Results (JSON) on the LocalPlayer.
-- Install at StarterPlayer.StarterPlayerScripts.PopcornTestRunners (never in the synced
-- folder); delete after reading Results.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local checks: { { name: string, passed: boolean, detail: string? } } = {}
local function check(name: string, condition: boolean, detail: string?)
	table.insert(checks, { name = name, passed = condition, detail = detail })
end
local function waitFor(condition: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not condition() and os.clock() < deadline do task.wait(0.05) end
	return condition()
end

local ok, err = pcall(function()
	assert(waitFor(function() return player:GetAttribute("ToolVisualsReady") == true end, 45), "server setup never finished")
	local backpack = player:WaitForChild("Backpack")
	local tool: Tool? = nil
	waitFor(function()
		for _, holder in { backpack, player.Character } do
			for _, child in (holder :: Instance):GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("ToolId") == "Sickle" then tool = child end
			end
		end
		return tool ~= nil
	end, 5)
	local sickle = assert(tool, "no Sickle tool")
	check("Sickle tool exists with a rarity", sickle:GetAttribute("Rarity") == "Common", tostring(sickle:GetAttribute("Rarity")))
	check("model source reported", sickle:GetAttribute("ModelSource") ~= nil, tostring(sickle:GetAttribute("ModelSource")))
	local handle = sickle:WaitForChild("Handle", 2)
	local trail = if handle then handle:FindFirstChild("SwingTrail") else nil
	check("handle carries the swing trail", trail ~= nil and trail:IsA("Trail"))

	local character = assert(player.Character)
	local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart
	local function handLocal(): Vector3 return torso.CFrame:PointToObjectSpace(hand.Position) end

	-- Equip: the hand should rise from low at the side to the hold height.
	local equipLow = math.huge
	local sampling = true
	task.spawn(function()
		while sampling do equipLow = math.min(equipLow, handLocal().Y) task.wait() end
	end)
	humanoid:EquipTool(sickle)
	check("equipped", waitFor(function() return sickle.Parent == character end, 2))
	task.wait(0.45)
	sampling = false
	local holdY = handLocal().Y
	check("equip draws the hand up from the side", holdY - equipLow > 0.6, string.format("low %.2f hold %.2f", equipLow, holdY))

	-- Idle sway: the hand moves a little, never a lot.
	local idleMin, idleMax = math.huge, -math.huge
	local started = os.clock()
	while os.clock() - started < 1.3 do
		local p = handLocal()
		idleMin, idleMax = math.min(idleMin, p.Y), math.max(idleMax, p.Y)
		task.wait()
	end
	check("idle sway is subtle", idleMax - idleMin > 0.02 and idleMax - idleMin < 0.6, string.format("%.3f", idleMax - idleMin))

	-- Swing: wind up to the right, then whip across to the left; trail on during the swing.
	local corn0 = player:GetAttribute("RawCorn") :: number? or 0
	local xs: { number } = {}
	local trailSeen = false
	local swinging = true
	task.spawn(function()
		while swinging do
			table.insert(xs, handLocal().X)
			if trail and (trail :: Trail).Enabled then trailSeen = true end
			RunService.Heartbeat:Wait()
		end
	end)
	sickle:Activate()
	task.wait(0.45)
	swinging = false
	local first, minX, maxX = xs[1] or 0, math.huge, -math.huge
	local maxAt, minAt = 0, 0
	for i, x in xs do
		if x > maxX then maxX, maxAt = x, i end
		if x < minX then minX, minAt = x, i end
	end
	check("swing travels across the body", maxX - minX > 1.2, string.format("x from %.2f to %.2f (start %.2f, %d samples)", minX, maxX, first, #xs))
	check("wind-up goes right before the cut goes left", maxAt < minAt, string.format("max at sample %d, min at %d", maxAt, minAt))
	check("trail shows during the swing", trailSeen)
	task.wait(0.4)
	check("trail is off after the swing", trail ~= nil and not (trail :: Trail).Enabled)
	check("swing returns to the hold pose", (handLocal() - Vector3.new(handLocal().X, holdY, handLocal().Z)).Magnitude < 0.5 and math.abs(handLocal().X - first) < 0.6,
		string.format("x %.2f vs %.2f", handLocal().X, first))

	-- Server confirmed the harvest, and the pooled leaf emitter burst for it.
	check("server harvested corn", waitFor(function() return ((player:GetAttribute("RawCorn") :: number?) or 0) > corn0 end, 2),
		tostring(player:GetAttribute("RawCorn")))
	local anchor = workspace.Terrain:FindFirstChild("PopcornToolLeaves")
	check("leaf burst emitter is pooled under Terrain", anchor ~= nil and #workspace.Terrain:GetChildren() < 40)
	local emitter = if anchor then anchor:FindFirstChildOfClass("ParticleEmitter") else nil
	check("leaf emitter uses the uploaded leaf texture", emitter ~= nil and emitter.Texture == "rbxassetid://107437834728710")

	-- Ten swings in a row leave one emitter, not ten.
	for _ = 1, 10 do
		task.wait(0.62)
		sickle:Activate()
	end
	task.wait(0.8)
	local emitters = 0
	for _, child in workspace.Terrain:GetChildren() do
		if child.Name == "PopcornToolLeaves" then emitters += 1 end
	end
	check("repeated swings reuse one emitter", emitters == 1, tostring(emitters))

	humanoid:UnequipTools()
	task.wait(0.3)
	check("unequip puts it away", sickle.Parent == backpack)
end)

local passed = ok
for _, c in checks do if not c.passed then passed = false end end
player:SetAttribute("ToolVisualsResults", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
print("[ToolVisuals tests] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
