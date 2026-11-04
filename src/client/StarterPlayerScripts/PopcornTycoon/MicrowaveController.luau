--!strict
-- The kiosk show while a microwave cooks (creator request, Nov 4 2026). For every farm's brick
-- kiosk (FarmVisuals.dressMicrowave), driven by the door's replicated Cooking / CookEndsAt
-- attributes: the microwave shakes harder as the popping builds and jolts on every pop, the
-- window glows and flickers, the display counts down, popcorn hops out of the top, and it
-- sounds right: a hum, pops that speed up like a real bag, and a ding when it is done.
-- Purely local presentation; the server decides the batch and its reward.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared:WaitForChild("Config"))
local MicrowaveController = {}

-- Creator Store sounds (free): microwave hum, a cartoon pop, a microwave "done" ding.
local SOUND = {
	Hum = { id = "rbxassetid://4399963971", volume = 0.28 },
	Pop = { id = "rbxassetid://6586979979", volume = 0.45 },
	Ding = { id = "rbxassetid://106123953900389", volume = 0.6 },
}
local POP_VOICES = 5
local rng = Random.new()

type Kiosk = {
	door: BasePart, model: Model, parts: { BasePart }, offsets: { CFrame }, rest: { CFrame }, pivot: CFrame, scale: number,
	glow: BasePart?, light: PointLight?, readout: TextLabel?, burst: ParticleEmitter?,
	hum: Sound, pops: { Sound }, ding: Sound, voice: number,
	cooking: boolean, started: number, endsAt: number, nextPop: number, jolt: number, doneAt: number,
}

local function newSound(spec: { id: string, volume: number }, parent: Instance, looped: boolean?): Sound
	local s = Instance.new("Sound")
	s.SoundId, s.Volume, s.Looped = spec.id, spec.volume, looped == true
	s.RollOffMode, s.RollOffMinDistance, s.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 10, 80
	s.Parent = parent
	return s
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function setup(door: BasePart, model: Model): Kiosk
	local parts, offsets, rest = {}, {}, {}
	local pivot = model:GetPivot()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(rest, d.CFrame)
			table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
		end
	end
	local body = model:FindFirstChild("MicrowaveBody") :: BasePart?
	local glow = model:FindFirstChild("WindowGlow") :: BasePart?
	local holder: Instance = glow or door
	local pops = {}
	for _ = 1, POP_VOICES do table.insert(pops, newSound(SOUND.Pop, holder)) end
	local screen = model:FindFirstChild("Display")
	local readout = screen and screen:FindFirstChild("Time", true) :: TextLabel?
	local vent = model:FindFirstChild("PopVent")
	return {
		door = door, model = model, parts = parts, offsets = offsets, rest = rest, pivot = pivot,
		scale = if body then body.Size.Y / 4.34 else 1,
		glow = glow, light = if glow then glow:FindFirstChildOfClass("PointLight") else nil,
		readout = readout, burst = if vent then vent:FindFirstChildOfClass("ParticleEmitter") else nil,
		hum = newSound(SOUND.Hum, holder, true), pops = pops, ding = newSound(SOUND.Ding, holder), voice = 1,
		cooking = false, started = 0, endsAt = 0, nextPop = 0, jolt = 0, doneAt = 0,
	}
end

local function rest(k: Kiosk)
	workspace:BulkMoveTo(k.parts, k.rest, Enum.BulkMoveMode.FireCFrameChanged)
end

local function setCooking(k: Kiosk, on: boolean)
	if on == k.cooking then return end
	k.cooking = on
	if on then
		k.started = os.clock()
		local ends = k.door:GetAttribute("CookEndsAt")
		k.endsAt = if typeof(ends) == "number" then ends else serverNow() + Config.Microwave.cookSeconds
		k.nextPop = os.clock() + 0.6
		k.hum.PlaybackSpeed = 1
		k.hum:Play()
	else
		k.hum:Stop()
		k.ding:Play()
		k.doneAt = os.clock()
		if k.burst then k.burst:Emit(10) end
		if k.glow then k.glow.Transparency = 1 end
		if k.light then k.light.Brightness = 0 end
		if k.readout then k.readout.Text = "POP!" end
		rest(k)
	end
end

local function pop(k: Kiosk)
	local s = k.pops[k.voice]
	k.voice = k.voice % #k.pops + 1
	s.PlaybackSpeed = rng:NextNumber(0.85, 1.35)
	s.Volume = SOUND.Pop.volume * rng:NextNumber(0.6, 1)
	s:Play()
	k.jolt = 1
	if k.burst and rng:NextNumber() < 0.6 then k.burst:Emit(1) end
end

function MicrowaveController.start()
	local kiosks: { [BasePart]: Kiosk } = {}

	local function track(farm: Instance)
		task.spawn(function()
			local door = farm:WaitForChild("MicrowaveDoor", 30)
			local scenery = farm:WaitForChild("Scenery", 30)
			local station = scenery and scenery:WaitForChild("MicrowaveStation", 30)
			local model = station and station:WaitForChild("MicrowaveUnit", 30)
			if not door or not door:IsA("BasePart") or not model or not model:IsA("Model") then return end
			model:WaitForChild("WindowGlow", 10)
			model:WaitForChild("Display", 10)
			local k = setup(door, model)
			kiosks[door] = k
			door:GetAttributeChangedSignal("Cooking"):Connect(function()
				setCooking(k, door:GetAttribute("Cooking") == true)
			end)
			door.AncestryChanged:Connect(function()
				if not door:IsDescendantOf(workspace) then kiosks[door] = nil end
			end)
			if door:GetAttribute("Cooking") == true then setCooking(k, true) end
		end)
	end
	task.spawn(function()
		local farms = workspace:WaitForChild("PopcornFarms", 60)
		if not farms then return end
		for _, farm in farms:GetChildren() do track(farm) end
		farms.ChildAdded:Connect(track)
	end)

	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		for _, k in kiosks do
			if k.cooking then
				local total = Config.Microwave.cookSeconds
				local left = math.max(0, k.endsAt - serverNow())
				local p = math.clamp(1 - left / total, 0, 1)
				-- Popping builds to a frenzy, then thins out just before the ding, like a real bag.
				local rate = 1.5 + 13 * math.sin(math.min(p * 1.15, 1) * math.pi * 0.5) ^ 2 * (if p > 0.88 then 0.45 else 1)
				if now >= k.nextPop then
					pop(k)
					k.nextPop = now + rng:NextNumber(0.4, 1.6) / rate
				end
				k.jolt *= math.exp(-dt * 14)
				local s = k.scale
				local amp = (0.06 + 0.1 * p + 0.16 * k.jolt) * s
				local t = now * 32
				local shake = CFrame.new(math.noise(t, 1.3) * amp, math.abs(math.noise(t, 7.1)) * amp * 0.8, math.noise(t, 4.7) * amp * 0.6)
					* CFrame.Angles(math.noise(t, 9.9) * amp * 0.05 / s, math.noise(t, 2.2) * amp * 0.08 / s, math.noise(t, 5.5) * amp * 0.12 / s)
				local pivot = k.pivot * shake
				local frames = table.create(#k.parts)
				for i, offset in k.offsets do frames[i] = pivot * offset end
				workspace:BulkMoveTo(k.parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
				local flicker = math.noise(now * 9, 3.3)
				-- Warm, flickering, and see-through enough that the turntable shows.
				if k.glow then k.glow.Transparency = math.clamp(0.3 + 0.15 * flicker + 0.12 * (1 - k.jolt), 0.2, 0.6) end
				if k.light then k.light.Brightness = 0.5 + 0.4 * k.jolt + 0.15 * flicker end
				k.hum.PlaybackSpeed = 1 + 0.04 * p
				if k.readout then
					local secs = math.ceil(left)
					k.readout.Text = string.format(if now % 1 < 0.5 then "0:%02d" else "0 %02d", secs)
				end
			elseif k.readout and k.doneAt > 0 and now - k.doneAt > 2 then
				k.readout.Text = "0:00"
				k.doneAt = 0
			end
		end
	end)
end

return MicrowaveController
