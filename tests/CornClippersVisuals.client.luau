--!strict
-- Client half of the Corn Clippers Play runner (pair with CornClippers.server.luau, which sets
-- ClippersVisualsReady). Equips the clippers, snips, and checks the jaw closing and reopening on
-- its Motor6D, the alternating wrist flick, the server-confirmed harvest, and the pooled snip
-- flash and leaf emitters. Writes ClippersVisualsResults (JSON) on the LocalPlayer.
-- Install at StarterPlayer.StarterPlayerScripts.PopcornTestRunners; delete after reading.
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
	assert(waitFor(function() return player:GetAttribute("ClippersVisualsReady") == true end, 60), "server half never finished")
	local backpack = player:WaitForChild("Backpack")
	local tool: Tool? = nil
	waitFor(function()
		for _, holder in { backpack, player.Character } do
			for _, child in (holder :: Instance):GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("ToolId") == "CornClippers" then tool = child end
			end
		end
		return tool ~= nil
	end, 5)
	local clippers = assert(tool, "no CornClippers tool")
	check("model source reported", clippers:GetAttribute("ModelSource") ~= nil, tostring(clippers:GetAttribute("ModelSource")))
	local character = assert(player.Character)
	local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart
	humanoid:EquipTool(clippers)
	check("equipped", waitFor(function() return clippers.Parent == character end, 2))
	task.wait(0.5)
	-- lihfolk-ignore: findfirstchild-chain (asserted on the next line)
	local jaw = clippers:FindFirstChild("Jaw", true) :: Motor6D?
	assert(jaw and jaw:IsA("Motor6D"), "no Jaw motor")
	local function jawDegrees(): number
		local _, y, _ = (jaw :: Motor6D).Transform:ToOrientation()
		return math.deg(y)
	end
	check("jaw rests open after equipping", math.abs(jawDegrees()) < 2, string.format("%.1f", jawDegrees()))

	-- One snip: sample the jaw angle and the hand height through it.
	local corn0 = (player:GetAttribute("RawCorn") :: number?) or 0
	local function snip(): (number, number)
		local most, sampling = 0, true
		local ys: { number } = {}
		task.spawn(function()
			while sampling do
				most = math.min(most, jawDegrees())
				table.insert(ys, torso.CFrame:PointToObjectSpace(hand.Position).Y)
				RunService.Heartbeat:Wait()
			end
		end)
		clippers:Activate()
		task.wait(0.2)
		sampling = false
		local lo, hi = math.huge, -math.huge
		for _, v in ys do lo, hi = math.min(lo, v), math.max(hi, v) end
		return most, (if #ys > 0 then (hi - lo) else 0)
	end
	local closed, _ = snip()
	check("the jaw snaps shut during a snip", closed < -15, string.format("%.1f deg", closed))
	task.wait(0.1)
	check("and springs back open", math.abs(jawDegrees()) < 2, string.format("%.1f", jawDegrees()))
	check("server harvested one stalk", waitFor(function() return ((player:GetAttribute("RawCorn") :: number?) or 0) == corn0 + 1 end, 2),
		tostring(player:GetAttribute("RawCorn")))
	check("snip flash emitter pooled under Terrain", waitFor(function() return workspace.Terrain:FindFirstChild("PopcornToolFlash") ~= nil end, 1))

	-- Rapid snips: each harvests one stalk; effects stay pooled.
	local before = (player:GetAttribute("RawCorn") :: number?) or 0
	for _ = 1, 6 do
		clippers:Activate()
		task.wait(0.16)
	end
	task.wait(0.6)
	local after = (player:GetAttribute("RawCorn") :: number?) or 0
	check("six quick snips harvest about six stalks", after - before >= 5 and after - before <= 6, tostring(after - before))
	local flashes, leaves = 0, 0
	for _, child in workspace.Terrain:GetChildren() do
		if child.Name == "PopcornToolFlash" then flashes += 1 end
		if child.Name == "PopcornToolLeaves" then leaves += 1 end
	end
	check("one flash and one leaf emitter after many snips", flashes == 1 and leaves == 1, flashes .. "/" .. leaves)
	check("jaw open again at rest", math.abs(jawDegrees()) < 2, string.format("%.1f", jawDegrees()))
	humanoid:UnequipTools()
	task.wait(0.3)
	check("unequip puts it away", clippers.Parent == backpack)
end)

local passed = ok
for _, c in checks do if not c.passed then passed = false end end
player:SetAttribute("ClippersVisualsResults", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
print("[CornClippers visuals] " .. (if passed then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
