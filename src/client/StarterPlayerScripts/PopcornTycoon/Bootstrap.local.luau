--!strict
-- Client entry: the HUD (HudController), the Inventory and Shop panels, and feedback for
-- server results. Everything shown is read from replicated attributes and remote results.
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Theme = require(script.Parent.UITheme)
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
-- Panel helpers, shared with ShopController. The panels keep their original look for now.
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
-- Inventory panel (I key): what the player is carrying and holding.
local inventory = frame("InventoryPanel", gui, UDim2.new(0.9, 0, 0, 250), UDim2.fromScale(0.5, 0.52))
inventory.AnchorPoint, inventory.Visible, inventory.ZIndex = Vector2.new(0.5, 0.5), false, 10
Instance.new("UISizeConstraint", inventory).MaxSize = Vector2.new(460, 250)
text("Title", inventory, "YOUR HARVEST", UDim2.new(1, -80, 0, 44), UDim2.fromOffset(16, 12), 22)
local contents = text("Contents", inventory, "", UDim2.new(1, -40, 0, 110), UDim2.fromOffset(20, 65), 20)
text("SessionNotice", inventory, "Progress resets when you leave.\nPop corn at the microwave, sell popcorn at the stand, buy tools in the Shop (B).", UDim2.new(1, -40, 0, 55), UDim2.fromOffset(20, 181), 13)
local function toggleInventory(visible: boolean?)
 inventory.Visible = if visible == nil then not inventory.Visible else visible
 if inventory.Visible then toggleShop(false) end
end
local close = Instance.new("TextButton")
close.Name, close.Text, close.Size, close.Position = "Close", "X", UDim2.fromOffset(44, 44), UDim2.new(1, -54, 0, 10)
close.BackgroundColor3, close.TextColor3, close.TextSize, close.Font = Theme.Red, Theme.Cream, 22, Enum.Font.GothamBold
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)
close.Parent = inventory
close.Activated:Connect(function() toggleInventory(false) end)
local capacity = Config.Inventory.capacity
local function renderInventory()
 local corn = tostring(player:GetAttribute("RawCorn") or 0)
 local popcorn = Money.short((player:GetAttribute("Popcorn") or 0) :: number)
 local cash = Money.cash((player:GetAttribute("Cash") or 0) :: number)
 local equipped = player:GetAttribute("EquippedTool")
 local tool = if typeof(equipped) == "string" then Config.Tools[equipped] else nil
 contents.Text = "Normal Corn     " .. corn .. " / " .. tostring(capacity) .. "\nPopcorn     " .. popcorn .. "     Cash     " .. cash
  .. "\nEquipped: " .. (if tool then tool.displayName else "Hands")
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
feedback.OnClientEvent:Connect(function(response)
 if not response.ok then show(response.reason) return end
 local full = response.reason == "Bag full" or (player:GetAttribute("RawCorn") or 0) >= capacity
 local cut = if typeof(response.targets) == "table" and #response.targets > 1 then "  ·  " .. tostring(#response.targets) .. " stalks" else ""
 show("+" .. tostring(response.amount) .. " Corn" .. cut .. "  ·  " .. (if full then "Bag full! Pop it at the microwave" else "Growing again!"))
 -- Swung tools pulse when their kernels land; hand picks pulse at once.
 if typeof(response.tool) == "string" then task.delay(0.55, hud.pulseCorn) else hud.pulseCorn() end
end)
actions.OnClientEvent:Connect(function(kind: string, response)
 if not response.ok then show(response.reason) return end
 if kind == "Microwave" then
  show("Popping " .. tostring(response.amount) .. " corn…")
 elseif kind == "Collect" then
  show("+" .. tostring(response.amount) .. " Popcorn" .. (if response.reason == "Collected" then "!" else "  ·  " .. response.reason))
  hud.pulsePopcorn()
 elseif kind == "Sell" then
  show(response.reason .. "  ·  +" .. Money.cash(response.amount) .. "!")
  chime("rbxassetid://9113849492", 0.5)
  hud.pulsePopcorn() hud.pulseCash()
 elseif kind == "Tool" then
  show(response.reason .. "  ·  −" .. Money.cash(response.amount))
  chime("rbxassetid://9113849492", 0.35)
  hud.pulseCash()
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
toggleShop = require(script.Parent.ShopController).start(gui, { frame = frame, text = text }, shopRequest)
local openShop = toggleShop
toggleShop = function(visible: boolean?)
 openShop(visible)
 if visible ~= false then inventory.Visible = false end
end
renderInventory()
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
show("Your farm is ready! Pick some golden corn.", 6)
print("[PopcornTycoon] Styled HUD ready.")
