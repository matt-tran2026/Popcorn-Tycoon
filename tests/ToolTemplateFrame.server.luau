-- Checks ToolModels' Blender-template path without a real import. In Edit mode first create a
-- stand-in at ServerStorage.PopcornTemplates.Tools.Sickle laid out like the exported FBX
-- (a Model with attribute MockForTest = true):
--   Part SickleHandle  Size (1.91, 0.48, 0.48)  CFrame (-0.175, 0, 0)
--   Part SickleBlade   Size (2.2, 0.48, 2.39)   CFrame (1.5, 0, -1.07)
-- Then install this at ServerScriptService.PopcornTestRunners.TemplateFrame, start Play, read
-- its Results attribute, stop, and delete both the runner folder and the stand-in.
local Http = game:GetService("HttpService")
local ToolModels = require(game.ServerScriptService.PopcornTycoon.ToolModels)
local Look = require(game.ReplicatedStorage.PopcornTycoon.ToolPresentation).get("Sickle")
local checks = {}
local function check(n, c, d) table.insert(checks, { name = n, passed = c, detail = d }) end
-- Everything below runs inside pcall: a missing child fails the run with its error, which is
-- the intended test outcome, so the FindFirstChild chains are deliberate.
-- lihfolk-ignore: findfirstchild-chain
local ok, err = pcall(function()
	local tool = ToolModels.build("Sickle")
	check("template path used", tool:GetAttribute("ModelSource") == "Blender", tostring(tool:GetAttribute("ModelSource")))
	local handle = tool:FindFirstChild("Handle") :: BasePart
	check("handle is the grip mesh, blade welded", handle ~= nil and tool:FindFirstChild("SickleBlade") ~= nil and tool.SickleBlade:FindFirstChildOfClass("WeldConstraint") ~= nil)
	check("materials and white colour", handle.Material == Enum.Material.Wood and tool.SickleBlade.Material == Enum.Material.Metal and handle.Color == Color3.new(1, 1, 1))
	-- Mock sits at the FBX origin: the grip point is the world origin; X along the handle,
	-- Z toward the blade (Roblox -Z), Y = X x Z handedness (Roblox -Y).
	local expected = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, -Vector3.yAxis, -Vector3.zAxis) * Look.model.grip
	local got = handle.CFrame * tool.Grip
	local posErr = (got.Position - expected.Position).Magnitude
	local rotErr = (got.LookVector - expected.LookVector).Magnitude + (got.UpVector - expected.UpVector).Magnitude
	check("grip lands on the grip point with the expected orientation", posErr < 1e-3 and rotErr < 1e-3, string.format("pos %.4f rot %.4f", posErr, rotErr))
	local tip = handle:FindFirstChild("BladeTip") :: Attachment
	check("blade tip attachment on the blade side", tip ~= nil and (tip.WorldPosition - Vector3.new(0.12, 0, -1.45)).Magnitude < 1e-3, tip and tostring(tip.WorldPosition))
	check("trail added between named points", handle:FindFirstChild("SwingTrail") ~= nil)
	check("rarity attribute", tool:GetAttribute("Rarity") == "Common")
	tool:Destroy()
end)
local passed = ok
for _, c in checks do if not c.passed then passed = false end end
script:SetAttribute("Results", Http:JSONEncode({ passed = passed, error = if ok then nil else tostring(err), checks = checks }))
