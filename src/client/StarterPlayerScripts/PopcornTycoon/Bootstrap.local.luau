--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Theme = require(script.Parent.UITheme)
local Config = require(Shared:WaitForChild("Config"))
local player = Players.LocalPlayer
local remotes = Shared:WaitForChild("Remotes")
local feedback = remotes:WaitForChild("HarvestResult") :: RemoteEvent
local actions = remotes:WaitForChild("ActionResult") :: RemoteEvent
local shopRequest = remotes:WaitForChild("ShopRequest") :: RemoteEvent
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "PopcornHUD", false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local function frame(name: string, parent: Instance, size: UDim2, position: UDim2): Frame
 local f = Instance.new("Frame")
 f.Name, f.Size, f.Position, f.BackgroundColor3 = name, size, position, Theme.Brown
 Instance.new("UICorner", f).CornerRadius = UDim.new(0, 18)
 local stroke = Instance.new("UIStroke") stroke.Color, stroke.Thickness, stroke.Parent = Theme.Gold, 2, f
 local gradient = Instance.new("UIGradient") gradient.Color = ColorSequence.new(Color3.fromRGB(110, 79, 49), Theme.Dark) gradient.Rotation, gradient.Parent = 90, f
 f.Parent = parent
 return f
end
local function text(name: string, parent: Instance, value: string, size: UDim2, position: UDim2, fontSize: number): TextLabel
 local t = Instance.new("TextLabel")
 t.Name, t.Size, t.Position, t.Text = name, size, position, value
 t.BackgroundTransparency, t.TextColor3, t.TextSize = 1, Theme.Cream, fontSize
 t.Font, t.TextWrapped, t.Parent = Enum.Font.GothamBold, true, parent
 return t
end
local resources = Instance.new("Frame")
resources.Name, resources.BackgroundTransparency = "Resources", 1
resources.AnchorPoint, resources.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 12)
resources.Size, resources.Parent = UDim2.new(0.94, 0, 0, 72), gui
local limit = Instance.new("UISizeConstraint", resources) limit.MaxSize = Vector2.new(660, 72)
local function counter(name: string, caption: string, icon: string, fallback: string, x: number)
 local f = frame(name, resources, UDim2.new(0.32, 0, 1, 0), UDim2.fromScale(x, 0))
 local art = Instance.new("ImageLabel") art.Name, art.BackgroundTransparency = "Icon", 1
 art.Size, art.Position, art.Image = UDim2.fromOffset(52, 52), UDim2.fromOffset(9, 10), icon
 art.ScaleType, art.Parent = Enum.ScaleType.Fit, f
 if icon == "" then -- Drawn coin until an approved icon exists.
  local coin = Instance.new("Frame") coin.Name, coin.Size, coin.Position = "Coin", UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.11, 0.11)
  coin.BackgroundColor3 = Theme.Gold Instance.new("UICorner", coin).CornerRadius = UDim.new(1, 0)
  local rim = Instance.new("UIStroke") rim.Color, rim.Thickness, rim.Parent = Color3.fromRGB(181, 129, 35), 3, coin
  local mark = text("Mark", coin, fallback, UDim2.fromScale(1, 1), UDim2.new(), 22) mark.TextColor3 = Theme.Brown
  coin.Parent = art
 end
 local caption_ = text("Caption", f, caption, UDim2.new(1, -66, 0, 22), UDim2.fromOffset(62, 9), 14)
 caption_.TextScaled = true Instance.new("UITextSizeConstraint", caption_).MaxTextSize = 14
 local value = text("Value", f, "0", UDim2.new(1, -66, 0, 30), UDim2.fromOffset(62, 32), 25)
 value.TextScaled = true Instance.new("UITextSizeConstraint", value).MaxTextSize = 25
 return f, value
end
local cornPanel, cornValue = counter("RawCorn", "Raw Corn", Theme.CornIcon, "CORN", 0)
local popcornPanel, popcornValue = counter("Popcorn", "Popcorn", Theme.PopcornIcon, "POP", 0.34)
local coinPanel, coinValue = counter("Coins", "Coins", "", "C", 0.68)
-- A thin fill bar shows how close the bag is to full.
local bagTrack = Instance.new("Frame")
bagTrack.Name, bagTrack.Size, bagTrack.Position = "BagFill", UDim2.new(1, -74, 0, 5), UDim2.new(0, 62, 1, -9)
bagTrack.BackgroundColor3, bagTrack.BorderSizePixel = Theme.Dark, 0
Instance.new("UICorner", bagTrack).CornerRadius = UDim.new(1, 0)
bagTrack.Parent = cornPanel
local bagFill = Instance.new("Frame")
bagFill.Name, bagFill.Size, bagFill.BackgroundColor3, bagFill.BorderSizePixel = "Fill", UDim2.fromScale(0, 1), Theme.Gold, 0
Instance.new("UICorner", bagFill).CornerRadius = UDim.new(1, 0)
bagFill.Parent = bagTrack
-- One line per loop step under the counters: the microwave batch, what selling would pay,
-- and progress toward the next tool. Everything is read from replicated attributes.
local status = Instance.new("Frame")
status.Name, status.BackgroundTransparency = "LoopStatus", 1
status.AnchorPoint, status.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 90)
status.Size, status.Parent = UDim2.new(0.94, 0, 0, 30), gui
Instance.new("UISizeConstraint", status).MaxSize = Vector2.new(660, 30)
local function chip(name: string, x: number): TextLabel
 local f = frame(name, status, UDim2.new(0.32, 0, 1, 0), UDim2.fromScale(x, 0))
 Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
 local label = text("Label", f, "", UDim2.new(1, -12, 1, -6), UDim2.fromOffset(6, 3), 13)
 label.TextScaled = true Instance.new("UITextSizeConstraint", label).MaxTextSize = 13
 return label
end
local batchChip, sellChip, goalChip = chip("Batch", 0), chip("Sale", 0.34), chip("Goal", 0.68)
local toast = frame("Feedback", gui, UDim2.new(0.9, 0, 0, 52), UDim2.new(0.5, 0, 0, 128))
toast.AnchorPoint = Vector2.new(0.5, 0)
Instance.new("UISizeConstraint", toast).MaxSize = Vector2.new(500, 52)
local toastText = text("Message", toast, "Your farm is ready! Pick some golden corn.", UDim2.new(1, -24, 1, -12), UDim2.fromOffset(12, 6), 16)
local nav = Instance.new("Frame")
nav.Name, nav.BackgroundTransparency, nav.Size = "Navigation", 1, UDim2.fromOffset(150, 210)
nav.Position, nav.Parent = UDim2.fromOffset(14, 164), gui
local inventory = frame("InventoryPanel", gui, UDim2.new(0.9, 0, 0, 250), UDim2.fromScale(0.5, 0.52))
inventory.AnchorPoint, inventory.Visible, inventory.ZIndex = Vector2.new(0.5, 0.5), false, 10
Instance.new("UISizeConstraint", inventory).MaxSize = Vector2.new(460, 250)
text("Title", inventory, "YOUR HARVEST", UDim2.new(1, -80, 0, 44), UDim2.fromOffset(16, 12), 22)
local contents = text("Contents", inventory, "", UDim2.new(1, -40, 0, 110), UDim2.fromOffset(20, 65), 20)
text("SessionNotice", inventory, "Progress resets when you leave.\nPop corn at the microwave, sell popcorn at the stand, buy tools in the Shop (B).", UDim2.new(1, -40, 0, 55), UDim2.fromOffset(20, 181), 13)
local close = Instance.new("TextButton")
close.Name, close.Text, close.Size, close.Position = "Close", "X", UDim2.fromOffset(44, 44), UDim2.new(1, -54, 0, 10)
close.BackgroundColor3, close.TextColor3, close.TextSize, close.Font = Theme.Red, Theme.Cream, 22, Enum.Font.GothamBold
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)
close.Parent = inventory
close.Activated:Connect(function() toggleInventory(false) end)
local toggleShop: (visible: boolean?) -> () = function() end
local function toggleInventory(visible: boolean?)
 inventory.Visible = if visible == nil then not inventory.Visible else visible
 if inventory.Visible then toggleShop(false) end
end
local function navItem(name: string, caption: string, index: number, onActivated: (() -> ())?)
 local enabled = onActivated ~= nil
 local holder = frame(name, nav, UDim2.new(1, 0, 0, 46), UDim2.fromOffset(0, (index - 1) * 54))
 local button = Instance.new("TextButton")
 button.Name, button.Text, button.Size = "Button", caption, UDim2.fromScale(1, 1)
 button.BackgroundTransparency, button.TextSize, button.Font = 1, 15, Enum.Font.GothamBold
 button.TextColor3, button.Active, button.Selectable = if enabled then Theme.Cream else Theme.Muted, enabled, enabled
 button.Parent = holder
 if onActivated then button.Activated:Connect(onActivated) end
end
navItem("Inventory", "Inventory", 1, function() toggleInventory() end)
navItem("Shop", "Shop", 2, function() toggleShop() end)
navItem("Quests", "Quests · Soon", 3, nil)
navItem("Upgrades", "Upgrades · Soon", 4, nil)
local capacity = Config.Inventory.capacity
local function render()
 local carried = player:GetAttribute("RawCorn") or 0
 local corn = tostring(carried)
 local popcorn = tostring(player:GetAttribute("Popcorn") or 0)
 local coins = tostring(player:GetAttribute("Coins") or 0)
 cornValue.Text, popcornValue.Text, coinValue.Text = corn .. "/" .. tostring(capacity), popcorn, coins
 cornValue.TextColor3 = if carried >= capacity then Theme.Gold else Theme.Cream
 bagFill.Size = UDim2.fromScale(math.clamp(carried / capacity, 0, 1), 1)
 bagFill.BackgroundColor3 = if carried >= capacity then Theme.Red else Theme.Gold
 local batch = player:GetAttribute("BatchState")
 batchChip.Text = if batch == "Popping" then "Popping " .. tostring(player:GetAttribute("BatchCorn") or 0) .. " corn · " .. tostring(player:GetAttribute("BatchSeconds") or 0) .. "s"
  elseif batch == "Landing" then "Popcorn flying to you!"
  elseif carried >= capacity then "Bag full · pop it!"
  elseif carried > 0 then "Microwave ready · pop " .. corn
  else "Microwave ready"
 local popcornCount = (player:GetAttribute("Popcorn") or 0) :: number
 sellChip.Text = if popcornCount > 0 then "Sell " .. popcorn .. " → " .. tostring(popcornCount * Config.Sell.coinsPerPopcorn) .. " coins" else "Sell stand · " .. tostring(Config.Sell.coinsPerPopcorn) .. " coins each"
 local equipped = player:GetAttribute("EquippedTool")
 local tool = if typeof(equipped) == "string" then Config.Tools[equipped] else nil
 -- The next tool to aim for: the cheapest one not yet owned.
 local nextId: string? = nil
 for toolId, def in Config.Tools do
  if not player:GetAttribute("Owned_" .. toolId) and (nextId == nil or def.price < Config.Tools[nextId :: string].price) then nextId = toolId end
 end
 if nextId then
  local def = Config.Tools[nextId]
  local balance = (player:GetAttribute(def.currency) or 0) :: number
  goalChip.Text = if balance >= def.price then def.displayName .. " ready to buy · Shop" else def.displayName .. " " .. tostring(balance) .. "/" .. tostring(def.price) .. " " .. string.lower(def.currency)
 else
  goalChip.Text = if tool then tool.displayName .. " · click, tap or F" else "Tools owned · equip in Shop"
 end
 contents.Text = "Normal Corn     " .. corn .. " / " .. tostring(capacity) .. "\nPopcorn     " .. popcorn .. "     Coins     " .. coins
  .. "\nEquipped: " .. (if tool then tool.displayName else "Hands")
end
player.AttributeChanged:Connect(render)
Input.InputBegan:Connect(function(input, processed)
 if processed then return end
 if input.KeyCode == Enum.KeyCode.I then toggleInventory() end
 if input.KeyCode == Enum.KeyCode.B then toggleShop() end
 if input.KeyCode == Enum.KeyCode.Escape then toggleInventory(false) toggleShop(false) end
end)
local toastRevision = 0
local function show(message: string)
 toastRevision += 1
 local revision = toastRevision
 toast.Visible = true
 toastText.Text = message
 task.delay(2.5, function() if revision == toastRevision then toast.Visible = false end end)
end
local function pulser(panel: Frame): () -> ()
 local scale = Instance.new("UIScale", panel)
 local tween: Tween? = nil
 return function()
  if tween then tween:Cancel() end
  scale.Scale = 1.08
  tween = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), {Scale = 1})
  tween:Play()
 end
end
local pulseCorn, pulsePopcorn, pulseCoins = pulser(cornPanel), pulser(popcornPanel), pulser(coinPanel)
local function chime(id: string, volume: number)
 local s = Instance.new("Sound") s.SoundId, s.Volume, s.Parent = id, volume, gui
 s:Play() s.Ended:Once(function() s:Destroy() end)
 task.delay(3, function() if s.Parent then s:Destroy() end end)
end
feedback.OnClientEvent:Connect(function(response)
 if not response.ok then show(response.reason) return end
 local full = response.reason == "Bag full" or (player:GetAttribute("RawCorn") or 0) >= capacity
 local cut = if typeof(response.targets) == "table" and #response.targets > 1 then "  ·  " .. tostring(#response.targets) .. " stalks" else ""
 show("+" .. tostring(response.amount) .. " Corn" .. cut .. "  ·  " .. (if full then "Bag full! Pop it at the microwave" else "Growing again!"))
 -- Swung tools pulse when their kernels land; hand picks pulse at once.
 if typeof(response.tool) == "string" then task.delay(0.55, pulseCorn) else pulseCorn() end
end)
actions.OnClientEvent:Connect(function(kind: string, response)
 if not response.ok then show(response.reason) return end
 if kind == "Microwave" then
  show("Popping " .. tostring(response.amount) .. " corn…")
 elseif kind == "Collect" then
  show("+" .. tostring(response.amount) .. " Popcorn" .. (if response.reason == "Collected" then "!" else "  ·  " .. response.reason))
  pulsePopcorn()
 elseif kind == "Sell" then
  show(response.reason .. "  ·  +" .. tostring(response.amount) .. " coins!")
  chime("rbxassetid://9113849492", 0.5)
  pulsePopcorn() pulseCoins()
 elseif kind == "Tool" then
  show(response.reason .. "  ·  −" .. tostring(response.amount) .. " coins")
  chime("rbxassetid://9113849492", 0.35)
  pulseCoins()
 elseif kind == "Equip" then
  show(response.reason)
 elseif kind == "Upgrade" then
  local currency = Config.Upgrades.ExtraRow.currency
  show(response.reason .. "  ·  −" .. tostring(response.amount) .. " " .. string.lower(currency))
  if currency == "Coins" then pulseCoins() else pulsePopcorn() end
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
  if t >= 1 then object.Transparency = 1 connection:Disconnect() end
 end)
end
task.spawn(function()
 local farms = workspace:WaitForChild("PopcornFarms", 30)
 if farms then farms.DescendantAdded:Connect(animatePiece) end
end)
local function layout()
 local camera = workspace.CurrentCamera
 if not camera then return end
 local compact = camera.ViewportSize.X < 700 or camera.ViewportSize.Y < 500
 nav.Size = UDim2.fromOffset(if compact then 118 else 150, 210)
 nav.Position = UDim2.fromOffset(12, if compact then 156 else 170)
 for _,name in {"Quests", "Upgrades"} do (nav:FindFirstChild(name) :: Frame).Visible = not compact end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(layout)
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
toggleShop = require(script.Parent.ShopController).start(gui, { frame = frame, text = text }, shopRequest)
local openShop = toggleShop
toggleShop = function(visible: boolean?)
 openShop(visible)
 if visible ~= false then inventory.Visible = false end
end
render() layout()
gui.Parent = player:WaitForChild("PlayerGui")
require(script.Parent.PromptController).start(gui)
require(script.Parent.ToolController).start(feedback)
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
task.delay(6, function() if toastRevision == 0 then toast.Visible = false end end)
print("[PopcornTycoon] Styled HUD ready.")
