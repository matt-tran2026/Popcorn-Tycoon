--!strict
-- Client entry: the HUD (HudController), the Inventory and Shop panels, and feedback for
-- server results. Everything shown is read from replicated attributes and remote results.
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Theme = require(script.Parent.UITheme)
local UIFx = require(script.Parent.UIFx)
local TweenService = game:GetService("TweenService")
local Config = require(Shared:WaitForChild("Config"))
local Money = require(Shared:WaitForChild("Money"))
local player = Players.LocalPlayer
local remotes = Shared:WaitForChild("Remotes")
local feedback = remotes:WaitForChild("HarvestResult") :: RemoteEvent
local actions = remotes:WaitForChild("ActionResult") :: RemoteEvent
local shopRequest = remotes:WaitForChild("ShopRequest") :: RemoteEvent
local toggleShop: (visible: boolean?) -> () = function() end
local hud = require(script.Parent.HudController).start({
 Shop = function() toggleShop() end,
})
local gui = hud.gui
local show = hud.show
local fx = hud.fx
local Brick = Theme.Brick
local BLACK = Color3.new(0, 0, 0)
-- Inventory panel (I key), restyled Nov 3 2026 as a studded blue brick to match the Shop:
-- one dark row per thing you carry, each with its icon and a live amount.
local INV_W, INV_H = 460, 340
local inventory = Instance.new("Frame")
inventory.Name, inventory.AnchorPoint, inventory.Position = "InventoryPanel", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
inventory.Size, inventory.BackgroundColor3 = UDim2.fromOffset(INV_W, INV_H), Brick.BlueRim
inventory.Visible, inventory.ZIndex, inventory.Active = false, 10, true
inventory.Parent = gui
Instance.new("UICorner", inventory).CornerRadius = UDim.new(0, 24)
local invStroke = Instance.new("UIStroke")
invStroke.Color, invStroke.Thickness, invStroke.ApplyStrokeMode, invStroke.Parent = BLACK, 5, Enum.ApplyStrokeMode.Border, inventory
local invFit = Instance.new("UIScale")
invFit.Parent = inventory
local invFace = Instance.new("ImageLabel")
invFace.Name, invFace.Image, invFace.ScaleType = "Face", Theme.Hud.Studs, Enum.ScaleType.Tile
invFace.TileSize, invFace.BackgroundColor3 = UDim2.fromOffset(44, 44), Brick.Blue
invFace.Position, invFace.Size = UDim2.fromOffset(9, 9), UDim2.new(1, -18, 1, -18)
Instance.new("UICorner", invFace).CornerRadius = UDim.new(0, 17)
invFace.Parent = inventory
local invTitle = UIFx.label("Title", inventory, Color3.new(1, 1, 1), 0.1)
invTitle.Text, invTitle.Position, invTitle.Size = "Your Stuff", UDim2.fromOffset(0, 12), UDim2.new(1, 0, 0, 52)
local function invRow(order: number, name: string): (Frame, TextLabel)
 local row = Instance.new("Frame")
 row.Name, row.Position, row.Size = name, UDim2.fromOffset(26, 74 + (order - 1) * 54), UDim2.new(1, -52, 0, 46)
 row.BackgroundColor3, row.BackgroundTransparency = Color3.fromRGB(14, 26, 60), 0.35
 Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
 local edge = Instance.new("UIStroke")
 edge.Color, edge.Thickness, edge.Parent = BLACK, 2.5, row
 local caption = UIFx.label("Name", row, Color3.new(1, 1, 1), 0.1)
 caption.Text, caption.Position, caption.Size = name, UDim2.fromOffset(62, 6), UDim2.new(0.5, -62, 1, -12)
 caption.TextXAlignment = Enum.TextXAlignment.Left
 local value = UIFx.label("Value", row, Color3.fromRGB(255, 226, 74), 0.1)
 value.Position, value.Size, value.TextXAlignment = UDim2.new(0.5, 0, 0, 6), UDim2.new(0.5, -14, 1, -12), Enum.TextXAlignment.Right
 row.Parent = inventory
 return row, value
end
local function rowIcon(row: Frame, image: GuiObject)
 image.AnchorPoint, image.Position, image.Size = Vector2.new(0.5, 0.5), UDim2.fromOffset(30, 23), UDim2.fromOffset(52, 52)
 image.ZIndex, image.Parent = 2, row
end
local cornRow, cornValue = invRow(1, "Corn bag")
local popRow, popValue = invRow(2, "Popcorn")
local cashRow, cashValue = invRow(3, "Cash")
local _, toolValue = invRow(4, "Holding")
for row, image in { [cornRow] = Theme.CornIcon, [popRow] = UIFx.Art.Popcorn } do
 local i = Instance.new("ImageLabel")
 i.BackgroundTransparency, i.Image, i.ScaleType = 1, image, Enum.ScaleType.Fit
 rowIcon(row, i)
end
rowIcon(cashRow, UIFx.coin())
local notice = UIFx.label("SessionNotice", inventory, Color3.fromRGB(205, 228, 255), 0.09)
notice.Text, notice.TextWrapped = "Progress resets when you leave · Pop corn at the microwave, sell at the stand, tools in the Shop (B)", true
notice.Position, notice.Size = UDim2.fromOffset(26, INV_H - 58), UDim2.new(1, -52, 0, 36)
local function toggleInventory(visible: boolean?)
 local open = if visible == nil then not inventory.Visible else visible
 if open and not inventory.Visible then
  local screen = gui.AbsoluteSize
  local target = math.clamp(math.min(screen.X * 0.9 / (INV_W + 30), screen.Y * 0.9 / (INV_H + 40)), 0.4, 1.2)
  invFit.Scale = target * 0.6
  inventory.Visible = true
  TweenService:Create(invFit, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = target }):Play()
  toggleShop(false)
 elseif not open then
  inventory.Visible = false
 end
end
local close = Instance.new("TextButton")
close.Name, close.Text, close.Size, close.Position = "Close", "", UDim2.fromOffset(56, 56), UDim2.new(1, -40, 0, -16)
close.BackgroundColor3, close.AutoButtonColor, close.ZIndex = Brick.Red, false, 3
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)
local closeStroke = Instance.new("UIStroke")
closeStroke.Color, closeStroke.Thickness, closeStroke.ApplyStrokeMode, closeStroke.Parent = BLACK, 3, Enum.ApplyStrokeMode.Border, close
local closeX = UIFx.label("Caption", close, Color3.new(1, 1, 1), 0.1)
closeX.Text, closeX.Size = "X", UDim2.fromScale(1, 0.8)
close.Parent = inventory
close.Activated:Connect(function() toggleInventory(false) end)
local capacity = Config.Inventory.capacity
local function renderInventory()
 local equipped = player:GetAttribute("EquippedTool")
 local tool = if typeof(equipped) == "string" then Config.Tools[equipped] else nil
 cornValue.Text = tostring(player:GetAttribute("RawCorn") or 0) .. " / " .. tostring(capacity)
 popValue.Text = Money.short((player:GetAttribute("Popcorn") or 0) :: number)
 cashValue.Text = Money.cash((player:GetAttribute("Cash") or 0) :: number)
 toolValue.Text = if tool then tool.displayName else "Hands"
end
player.AttributeChanged:Connect(renderInventory)
Input.InputBegan:Connect(function(input, processed)
 if processed then return end
 if input.KeyCode == Enum.KeyCode.I then toggleInventory() end
 if input.KeyCode == Enum.KeyCode.B then toggleShop() end
 if input.KeyCode == Enum.KeyCode.Escape then toggleInventory(false) toggleShop(false) end
end)
local function chime(id: string, volume: number)
 local s = Instance.new("Sound") s.SoundId, s.Volume, s.Parent = id, volume, gui
 s:Play() s.Ended:Once(function() s:Destroy() end)
 task.delay(3, function() if s.Parent then s:Destroy() end end)
end
-- Where the local character's head is on screen (fx coordinates); screen centre if off-screen.
local function fromCharacter(): Vector2
 local character = player.Character
 local head = character and character:FindFirstChild("Head") :: BasePart?
 local point = if head then UIFx.worldPoint(fx, head.Position + Vector3.new(0, 1.5, 0)) else nil
 return point or fx.AbsoluteSize / 2
end
local function iconSize(): number return math.floor(hud.unit() * 0.42) end
-- Rewards fly out of the player into their counter, then the counter bounces and a "+n" pops.
local function reward(image: string, target: GuiObject, amount: number, text: string, color: Color3, pulse: () -> (), delay: number?)
 task.delay(delay or 0, function()
  local size = iconSize()
  UIFx.fly(fx, image, fromCharacter(), target, math.clamp(amount, 1, 7), size, function()
   pulse()
   local at = UIFx.centerOf(fx, target)
   -- Above counters in the lower half of the screen, below ones at the top.
   local lift = if at.Y < fx.AbsoluteSize.Y / 2 then 0.75 else -0.9
   UIFx.floatText(fx, text, color, at + Vector2.new(target.AbsoluteSize.X * 0.15, target.AbsoluteSize.Y * lift), size * 1.25)
  end)
 end)
end
feedback.OnClientEvent:Connect(function(response)
 if not response.ok then show(response.reason) return end
 local full = response.reason == "Bag full" or (player:GetAttribute("RawCorn") or 0) >= capacity
 local cut = if typeof(response.targets) == "table" and #response.targets > 1 then "  ·  " .. tostring(#response.targets) .. " stalks" else ""
 show("+" .. tostring(response.amount) .. " Corn" .. cut .. "  ·  " .. (if full then "Bag full! Pop it at the microwave" else "Growing again!"))
 -- Corn cobs fly into the bag; swung tools wait for the blade to pass first.
 reward(Theme.CornIcon, hud.targets.bag, response.amount, "+" .. tostring(response.amount), Color3.fromRGB(255, 226, 74), hud.pulseCorn, if typeof(response.tool) == "string" then 0.2 else 0)
end)
actions.OnClientEvent:Connect(function(kind: string, response)
 if not response.ok then show(response.reason) return end
 if kind == "Microwave" then
  show("Popping " .. tostring(response.amount) .. " corn…")
 elseif kind == "Collect" then
  show("+" .. tostring(response.amount) .. " Popcorn" .. (if response.reason == "Collected" then "!" else "  ·  " .. response.reason))
  reward(UIFx.Art.Popcorn, hud.targets.popcorn, response.amount, "+" .. tostring(response.amount), Color3.new(1, 1, 1), function()
   hud.pulsePopcorn()
   local bucket = hud.targets.popcorn
   UIFx.popcornBurst(fx, UIFx.centerOf(fx, bucket) - Vector2.new(0, bucket.AbsoluteSize.Y * 0.3), 7, iconSize() * 0.6, 0.6)
  end)
 elseif kind == "Sell" then
  show(response.reason .. "  ·  +" .. Money.cash(response.amount) .. "!")
  chime("rbxassetid://9113849492", 0.5)
  hud.pulsePopcorn()
  -- A shower of spinning coins pours into the cash bar.
  reward("Coin", hud.targets.cash, 8, "+" .. Money.cash(response.amount), Color3.fromRGB(124, 240, 74), hud.pulseCash)
 elseif kind == "Tool" then
  show(response.reason .. "  ·  −" .. Money.cash(response.amount))
  chime("rbxassetid://9113849492", 0.35)
  hud.pulseCash()
  local cashBar = hud.targets.cash
  UIFx.floatText(fx, "−" .. Money.cash(response.amount), Color3.fromRGB(255, 110, 100), UIFx.centerOf(fx, cashBar) - Vector2.new(0, cashBar.AbsoluteSize.Y), iconSize() * 0.9)
  UIFx.popcornBurst(fx, fx.AbsoluteSize / 2, 14, iconSize() * 0.7, 1)
 elseif kind == "Equip" then
  show(response.reason)
 elseif kind == "Upgrade" then
  local currency = Config.Upgrades.ExtraRow.currency
  show(response.reason .. "  ·  −" .. Money.price(currency, response.amount))
  if currency == "Cash" then hud.pulseCash() else hud.pulsePopcorn() end
 end
end)
-- Server places each popcorn piece where it lands and credits it when its flight ends.
-- Locally: burst arc from the microwave, then a magnet flight that homes in on the owner.
local function animatePiece(object: Instance)
 if object.Name ~= "PopcornPiece" or not object:IsA("BasePart") then return end
 local from = object:GetAttribute("BurstFrom")
 local delay = object:GetAttribute("FlyDelay")
 local farm = object.Parent and object.Parent.Parent
 local owner = if farm then Players:GetPlayerByUserId(farm:GetAttribute("OwnerUserId") or 0) else nil
 if typeof(from) ~= "Vector3" or typeof(delay) ~= "number" then return end
 local landing = object.Position
 local size = object.Size
 -- The popcorn sprite (BillboardGui) shrinks and tumbles with the flight.
 local sprite = object:WaitForChild("Sprite", 2) :: BillboardGui?
 local image = sprite and sprite:FindFirstChild("Popcorn") :: ImageLabel?
 local spriteSize = if sprite then sprite.Size else UDim2.new()
 local spin = math.random(-360, 360)
 local started = os.clock()
 local land, fly = Config.Microwave.landSeconds, Config.Microwave.flySeconds * 0.95
 local connection: RBXScriptConnection
 connection = game:GetService("RunService").RenderStepped:Connect(function()
  if not object.Parent then connection:Disconnect() return end
  local elapsed = os.clock() - started
  if elapsed < land then
   local t = elapsed / land
   object.Position = from:Lerp(landing, t) + Vector3.new(0, math.sin(t * math.pi) * 5, 0)
   return
  end
  local t = math.clamp((elapsed - land - delay) / fly, 0, 1)
  local character = owner and owner.Character
  local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
  if not root then object.Position = landing return end
  local eased = t * t -- Slow pull that speeds up, like a magnet.
  object.Position = landing:Lerp(root.Position, eased) + Vector3.new(0, math.sin(t * math.pi) * 3, 0)
  object.Size = size * (1 - 0.6 * eased)
  if sprite then sprite.Size = UDim2.fromScale(spriteSize.X.Scale * (1 - 0.6 * eased), spriteSize.Y.Scale * (1 - 0.6 * eased)) end
  if image then image.Rotation += spin / 60 end
  if t >= 1 then
   object.Transparency = 1
   if sprite then sprite.Enabled = false end
   connection:Disconnect()
  end
 end)
end
task.spawn(function()
 local farms = workspace:WaitForChild("PopcornFarms", 30)
 if farms then farms.DescendantAdded:Connect(animatePiece) end
end)
toggleShop = require(script.Parent.ShopController).start(gui, shopRequest)
local openShop = toggleShop
toggleShop = function(visible: boolean?)
 openShop(visible)
 if visible ~= false then inventory.Visible = false end
end
renderInventory()
require(script.Parent.PromptController).start(gui)
require(script.Parent.HarvestHighlight).start(gui)
require(script.Parent.ToolController).start(feedback)
require(script.Parent.AmbientController).start()
require(script.Parent.MicrowaveController).start()
-- Orient the initial normal third-person camera toward this player's farm.
-- Camera controls remain Roblox's default after this one-time placement.
task.spawn(function()
 local farms = workspace:WaitForChild("PopcornFarms", 30)
 local farm = farms and farms:WaitForChild("Farm_" .. player.UserId, 30)
 local character = player.Character or player.CharacterAdded:Wait()
 local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
 if not farm or not root then return end
 local soil = farm:FindFirstChild("Soil") :: BasePart?
 if not soil then return end
 local direction = Vector3.new(soil.Position.X - root.Position.X, 0, soil.Position.Z - root.Position.Z)
 if direction.Magnitude < 1 then return end
 game:GetService("RunService").RenderStepped:Wait()
 local camera = workspace.CurrentCamera
 if camera then camera.CFrame = CFrame.lookAt(root.Position - direction.Unit * 16 + Vector3.new(0, 8, 0), root.Position + direction.Unit * 9) end
end)
UIFx.splash(fx)
task.delay(3.2, function() show("Your farm is ready! Pick some golden corn.", 6) end)
print("[PopcornTycoon] Styled HUD ready.")
