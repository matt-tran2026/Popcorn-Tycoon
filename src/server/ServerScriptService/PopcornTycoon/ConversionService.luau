--!strict
-- Microwave batches and their popcorn burst. Inputs leave the inventory and the reward
-- is fixed when a batch loads. Pieces arc out, then fly to the owner wherever they are;
-- each is credited exactly once when its flight ends, or by settle() on leave.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local State = require(script.Parent.PlayerStateService)
local Farms = require(script.Parent.FarmService)

type Batch = { reward: number, corn: number, readyAt: number }
type Piece = { part: Part, value: number, arrivesAt: number }
local batches: { [number]: Batch } = {}
local pieces: { [number]: { Piece } } = {}
local scatter = Random.new()
local ConversionService = {}

local function result(ok: boolean, reason: string, amount: number?): Types.ActionResult
	return { ok = ok, reason = reason, amount = amount or 0 }
end

local function setStatus(userId: number, text: string, cooking: boolean)
	local view = Farms.microwave(userId)
	if not view then return end
	view.prompt.ObjectText = text
	view.popping.Enabled = cooking
	view.door:SetAttribute("Cooking", cooking)
end

-- Batch state for the owner's HUD: "Popping" (with corn and whole seconds left), "Landing"
-- while popcorn flies to them, else "Idle". Presentation only; the batch tables stay authoritative.
local function publishBatch(userId: number, state: string, corn: number, seconds: number)
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if not player then return end
	player:SetAttribute("BatchState", state)
	player:SetAttribute("BatchCorn", corn)
	player:SetAttribute("BatchSeconds", seconds)
end

function ConversionService.start(player: Player, ownerUserId: unknown): Types.ActionResult
	if typeof(ownerUserId) ~= "number" or ownerUserId ~= player.UserId then return result(false, "Not your microwave") end
	local profile = State.get(player.UserId)
	local view = Farms.microwave(player.UserId)
	if not profile or not view then return result(false, "Profile unavailable") end
	if batches[player.UserId] then return result(false, "Already popping!") end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then return result(false, "Character unavailable") end
	local distance = (root.Position - view.door.Position).Magnitude
	if distance ~= distance or distance > Config.Microwave.range + 2 then return result(false, "Too far away") end
	local reward, corn = 0, 0
	for cropId, count in profile.rawCorn do
		local crop = Config.Crops[cropId]
		if crop and count > 0 then reward += count * crop.popcornValue corn += count end
	end
	if corn == 0 then return result(false, "No corn to pop · go pick some!") end
	-- No yields between validation, consuming the inventory, and reserving the batch.
	for cropId in profile.rawCorn do profile.rawCorn[cropId] = 0 end
	player:SetAttribute("RawCorn", 0)
	local now = DateTime.now().UnixTimestampMillis / 1000 -- Same clock as update().
	batches[player.UserId] = { reward = reward, corn = corn, readyAt = now + Config.Microwave.cookSeconds }
	setStatus(player.UserId, "Popping… " .. tostring(math.ceil(Config.Microwave.cookSeconds)) .. "s", true)
	publishBatch(player.UserId, "Popping", corn, math.ceil(Config.Microwave.cookSeconds))
	return result(true, "Popping", corn)
end

local function burst(userId: number, batch: Batch, now: number)
	local view = Farms.microwave(userId)
	if not view then return end
	local count = math.min(Config.Microwave.pieces, batch.reward)
	local base, extra = batch.reward // count, batch.reward % count
	local list = pieces[userId] or {}
	pieces[userId] = list
	local origin = view.door.Position
	local facing = view.door.CFrame
	local microwave = Config.Microwave
	for i = 1, count do
		-- Landing spots fan out toward the field; the client animates the arc and the flight.
		local spot = origin + facing.RightVector * scatter:NextNumber(-7, 7) + facing.LookVector * scatter:NextNumber(1.5, 5)
		local landing = Vector3.new(spot.X, 0.9, spot.Z)
		local piece = Instance.new("Part")
		piece.Name, piece.Shape = "PopcornPiece", Enum.PartType.Ball
		piece.Size, piece.Position = Vector3.new(1.1, 1.1, 1.1), landing
		piece.Color, piece.Material = Color3.fromRGB(255, 246, 214), Enum.Material.SmoothPlastic
		piece.Anchored, piece.CanCollide, piece.CanTouch, piece.CanQuery = true, false, false, false
		local value = base + (if i <= extra then 1 else 0)
		local delay = (i - 1) * microwave.staggerSeconds -- Pieces leave the ground one after another.
		piece:SetAttribute("Value", value)
		piece:SetAttribute("BurstFrom", origin)
		piece:SetAttribute("FlyDelay", delay)
		piece.Parent = view.popcorn
		table.insert(list, { part = piece, value = value, arrivesAt = now + microwave.landSeconds + delay + microwave.flySeconds })
	end
end

-- Returns popcorn collected per owner this tick so the caller can send one notice each.
function ConversionService.update(now: number): { [number]: number }
	local collected: { [number]: number } = {}
	for userId, batch in batches do
		if now >= batch.readyAt then
			batches[userId] = nil
			burst(userId, batch, now)
			setStatus(userId, "Microwave", false)
			publishBatch(userId, "Landing", batch.corn, 0)
		else
			setStatus(userId, "Popping… " .. tostring(math.ceil(batch.readyAt - now)) .. "s", true)
			publishBatch(userId, "Popping", batch.corn, math.ceil(batch.readyAt - now))
		end
	end
	for userId, list in pieces do
		for i = #list, 1, -1 do
			local piece = list[i]
			if now >= piece.arrivesAt then
				table.remove(list, i)
				piece.part:Destroy()
				State.creditPopcorn(userId, piece.value)
				collected[userId] = (collected[userId] or 0) + piece.value
			end
		end
		if #list == 0 then
			pieces[userId] = nil
			if not batches[userId] then publishBatch(userId, "Idle", 0, 0) end
		end
	end
	return collected
end

function ConversionService.pending(userId: number): number
	local total = 0
	local batch = batches[userId]
	if batch then total += batch.reward end
	for _, piece in pieces[userId] or {} do total += piece.value end
	return total
end

-- Credit everything still in flight. Call while the profile is still loaded.
function ConversionService.settle(userId: number)
	local total = ConversionService.pending(userId)
	batches[userId] = nil
	for _, piece in pieces[userId] or {} do piece.part:Destroy() end
	pieces[userId] = nil
	publishBatch(userId, "Idle", 0, 0)
	if total > 0 and State.get(userId) then State.creditPopcorn(userId, total) end
end

return ConversionService
