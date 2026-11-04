--!strict
-- Local-only motion for the map spectacle (HubSpectacle on the server marks what moves):
--   Ambient = "Spin"  model turns about its pivot (SpinSpeed rad/s)
--   Ambient = "Orbit" model circles OrbitCenter (OrbitRadius, OrbitSpeed, OrbitPhase), bobbing
--                     by Bob studs, optionally spinning (SpinSpeed) and tumbling (Tumble)
--   Ambient = "Fly"   like Orbit but faces its flight path, banks and flaps its wings
--   Ambient = "Hover" BillboardGui bobbing gently
--   Ambient = "Vendor" the sell-stand vendor: breathes and looks around, waves now and then, and
--                     waves both arms and hops when CheerAt (server time) is fresh; arms
--                     (VendorArm*) swing about their own pivots, the shoulders
--   Bulb = n          marquee bulb n in its folder; folders chase their lights
-- One Heartbeat loop moves every part with BulkMoveTo; nothing here reaches the server.
local RunService = game:GetService("RunService")
local AmbientController = {}

type Mover = {
	model: Model,
	kind: string,
	parts: { BasePart },
	offsets: { CFrame },
	base: CFrame,
	wings: { [number]: number }, -- part index -> wing side (-1 / 1)
	arms: { [number]: { hinge: Vector3, side: number, idle: boolean } }, -- part index -> shoulder
}

local VENDOR_WAVE_EVERY, VENDOR_WAVE_SECONDS, CHEER_SECONDS = 8, 1.8, 1.6

-- 0 -> 1 -> 0 over a window, with quick ramps at both ends.
local function envelope(u: number): number
	return if u <= 0 or u >= 1 then 0 else math.min(1, u * 5, (1 - u) * 5)
end

local BULB_ON = Color3.fromRGB(255, 226, 96)
local BULB_OFF = Color3.fromRGB(140, 84, 28)
local CHASE_SECONDS = 0.13

local function attr(model: Instance, name: string, default: number): number
	local v = model:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local function newMover(model: Model, kind: string): Mover
	local pivot = model:GetPivot()
	local parts, offsets, wings, arms = {}, {}, {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local offset = pivot:ToObjectSpace(d.CFrame)
			table.insert(offsets, offset)
			if kind == "Fly" and (d.Name == "Wing" or d.Name == "WingTip") then
				wings[#parts] = if offset.Position.X < 0 then -1 else 1
			elseif kind == "Vendor" and string.sub(d.Name, 1, 9) == "VendorArm" then
				local hinge = pivot:PointToObjectSpace(d:GetPivot().Position)
				arms[#parts] = { hinge = hinge, side = if hinge.X < 0 then -1 else 1, idle = d.Name == "VendorArmL" }
			end
		end
	end
	return { model = model, kind = kind, parts = parts, offsets = offsets, base = pivot, wings = wings, arms = arms }
end

function AmbientController.start()
	local movers: { Mover } = {}
	local tracked: { [Instance]: boolean } = {}
	local hovers: { BillboardGui } = {}
	local bulbFolders: { [Instance]: { BasePart } } = {}

	local function consider(d: Instance)
		if tracked[d] then return end
		local kind = d:GetAttribute("Ambient")
		if d:IsA("Model") and typeof(kind) == "string" then
			tracked[d] = true
			-- Wait a frame so every child part has replicated before offsets are taken.
			task.defer(function() table.insert(movers, newMover(d, kind)) end)
		elseif d:IsA("BillboardGui") and kind == "Hover" then
			tracked[d] = true
			table.insert(hovers, d)
		elseif d:IsA("BasePart") and typeof(d:GetAttribute("Bulb")) == "number" and d.Parent then
			tracked[d] = true
			local list = bulbFolders[d.Parent] or {}
			bulbFolders[d.Parent] = list
			table.insert(list, d)
		end
	end

	-- The map, plus every farm and open plot (the microwave kiosks' sign bulbs).
	for _, name in { "PopcornMap", "PopcornFarms", "PopcornOpenPlots" } do
		task.spawn(function()
			local root = workspace:WaitForChild(name, 60)
			if not root then return end
			for _, d in root:GetDescendants() do consider(d) end
			root.DescendantAdded:Connect(consider)
		end)
	end

	local started = os.clock()
	local lastChase, step = 0, 0
	RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		local moveParts: { BasePart } = {}
		local moveFrames: { CFrame } = {}
		for i = #movers, 1, -1 do
			local m = movers[i]
			if not m.model.Parent then
				table.remove(movers, i)
				continue
			end
			local model = m.model
			local pivot: CFrame
			local armLift, idleLift = 0, 0
			if m.kind == "Spin" then
				pivot = m.base * CFrame.Angles(0, t * attr(model, "SpinSpeed", 0.3), 0)
			elseif m.kind == "Vendor" then
				local cheer = attr(model, "CheerAt", 0)
				local since = if cheer > 0 then workspace:GetServerTimeNow() - cheer else math.huge
				-- Two quick hops while both arms wave.
				local hop = if since >= 0 and since < 0.9 then math.abs(math.sin(since * math.pi / 0.45)) * 0.7 else 0
				armLift = envelope(since / CHEER_SECONDS) * (2.6 + math.sin(t * 16) * 0.3)
				idleLift = envelope((t % VENDOR_WAVE_EVERY) / VENDOR_WAVE_SECONDS) * (2.3 + math.sin(t * 11) * 0.35)
				pivot = m.base * CFrame.new(0, math.sin(t * 2.1) * 0.05 + hop, 0) * CFrame.Angles(0, math.sin(t * 0.5) * 0.12, 0)
			else
				local center = model:GetAttribute("OrbitCenter")
				if typeof(center) ~= "Vector3" then continue end
				local speed, phase = attr(model, "OrbitSpeed", 0.2), attr(model, "OrbitPhase", 0)
				local theta = phase + t * speed
				local r = attr(model, "OrbitRadius", 20)
				local bob = math.sin(t * 1.3 + phase * 2) * attr(model, "Bob", 0)
				local at = center + Vector3.new(math.cos(theta) * r, bob, math.sin(theta) * r)
				if m.kind == "Fly" then
					local dir = Vector3.new(-math.sin(theta), 0, math.cos(theta)) * math.sign(speed)
					pivot = CFrame.lookAt(at, at + dir) * CFrame.Angles(0, 0, -math.sign(speed) * 0.3)
				else
					local tumble = attr(model, "Tumble", 0)
					pivot = CFrame.new(at) * CFrame.Angles(math.sin(t * 0.7 + phase) * 0.4 * tumble, t * attr(model, "SpinSpeed", 0) + phase, math.cos(t * 0.9 + phase) * 0.4 * tumble)
				end
			end
			local flap = if m.kind == "Fly" then math.sin(t * 9 + attr(model, "OrbitPhase", 0) * 3) * 0.45 else 0
			for index, p in m.parts do
				local offset = m.offsets[index]
				local side = m.wings[index]
				if side then
					local hinge = Vector3.new(side * 0.35, 0.3, 0)
					offset = CFrame.new(hinge) * CFrame.Angles(0, 0, side * flap) * CFrame.new(-hinge) * offset
				end
				local arm = m.arms[index]
				if arm then
					-- Raise the arm outward about the shoulder (a cheer beats the idle wave).
					local lift = math.max(armLift, if arm.idle then idleLift else 0)
					offset = CFrame.new(arm.hinge) * CFrame.Angles(0, 0, arm.side * lift) * CFrame.new(-arm.hinge) * offset
				end
				table.insert(moveParts, p)
				table.insert(moveFrames, pivot * offset)
			end
		end
		if #moveParts > 0 then workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged) end

		for _, board in hovers do
			board.StudsOffsetWorldSpace = Vector3.new(0, math.sin(t * 0.8) * 1.8, 0)
		end

		if t - lastChase >= CHASE_SECONDS then
			lastChase, step = t, step + 1
			for folder, bulbs in bulbFolders do
				if not folder.Parent then bulbFolders[folder] = nil continue end
				for _, bulb in bulbs do
					local n = (bulb:GetAttribute("Bulb") :: number) or 0
					bulb.Color = if (n + step) % 3 == 0 then BULB_ON else BULB_OFF
				end
			end
		end
	end)
end

return AmbientController
