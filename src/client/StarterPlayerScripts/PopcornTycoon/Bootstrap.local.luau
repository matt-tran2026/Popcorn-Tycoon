--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local Theme = require(script.Parent.UITheme)
local player = Players.LocalPlayer
local feedback = Shared:WaitForChild("Remotes"):WaitForChild("HarvestResult") :: RemoteEvent
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
local limit = Instance.new("UISizeConstraint", resources) limit.MaxSize = Vector2.new(540, 72)
local function counter(name: string, caption: string, icon: string, fallback: string, x: number)
 local f = frame(name, resources, UDim2.new(0.48, 0, 1, 0), UDim2.fromScale(x, 0))
 local art = Instance.new("ImageLabel") art.Name, art.BackgroundTransparency = "Icon", 1
 art.Size, art.Position, art.Image = UDim2.fromOffset(58, 58), UDim2.fromOffset(7, 7), icon
 art.ScaleType, art.Parent = Enum.ScaleType.Fit, f
 local placeholder = text("Fallback", art, fallback, UDim2.fromScale(1, 1), UDim2.new(), 12)
 placeholder.Visible = icon == ""
 text("Caption", f, caption, UDim2.new(1, -72, 0, 24), UDim2.fromOffset(66, 9), 15)
 local value = text("Value", f, "0", UDim2.new(1, -72, 0, 30), UDim2.fromOffset(66, 32), 27)
 return f, value
end
local cornPanel, cornValue = counter("RawCorn", "Raw Corn", Theme.CornIcon, "CORN", 0)
local _, popcornValue = counter("Popcorn", "Popcorn", Theme.PopcornIcon, "POP", 0.52)
local toast = frame("Feedback", gui, UDim2.new(0.9, 0, 0, 52), UDim2.new(0.5, 0, 0, 96))
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
text("SessionNotice", inventory, "Progress resets when you leave.\nMicrowave conversion is coming later.", UDim2.new(1, -40, 0, 55), UDim2.fromOffset(20, 181), 13)
local close = Instance.new("TextButton")
close.Name, close.Text, close.Size, close.Position = "Close", "X", UDim2.fromOffset(44, 44), UDim2.new(1, -54, 0, 10)
close.BackgroundColor3, close.TextColor3, close.TextSize, close.Font = Theme.Red, Theme.Cream, 22, Enum.Font.GothamBold
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)
close.Parent = inventory
close.Activated:Connect(function() inventory.Visible = false end)
local function navItem(name: string, caption: string, index: number, enabled: boolean)
 local holder = frame(name, nav, UDim2.new(1, 0, 0, 46), UDim2.fromOffset(0, (index - 1) * 54))
 local button = Instance.new("TextButton")
 button.Name, button.Text, button.Size = "Button", caption, UDim2.fromScale(1, 1)
 button.BackgroundTransparency, button.TextSize, button.Font = 1, 15, Enum.Font.GothamBold
 button.TextColor3, button.Active, button.Selectable = if enabled then Theme.Cream else Theme.Muted, enabled, enabled
 button.Parent = holder
 if enabled then button.Activated:Connect(function() inventory.Visible = not inventory.Visible end) end
end
navItem("Inventory", "Inventory", 1, true)
navItem("Shop", "Shop · Soon", 2, false)
navItem("Quests", "Quests · Soon", 3, false)
navItem("Upgrades", "Upgrades · Soon", 4, false)
local function render()
 local corn = tostring(player:GetAttribute("RawCorn") or 0)
 local popcorn = tostring(player:GetAttribute("Popcorn") or 0)
 cornValue.Text, popcornValue.Text = corn, popcorn
 contents.Text = "Normal Corn     " .. corn .. "\nPopcorn     " .. popcorn .. "\nEquipped: Manual harvest"
end
player:GetAttributeChangedSignal("RawCorn"):Connect(render)
player:GetAttributeChangedSignal("Popcorn"):Connect(render)
Input.InputBegan:Connect(function(input, processed)
 if processed then return end
 if input.KeyCode == Enum.KeyCode.I then inventory.Visible = not inventory.Visible end
 if input.KeyCode == Enum.KeyCode.Escape then inventory.Visible = false end
end)
local toastRevision = 0
local pulse = Instance.new("UIScale", cornPanel)
local pulseTween: Tween? = nil
feedback.OnClientEvent:Connect(function(response)
 toastRevision += 1
 local revision = toastRevision
 toast.Visible = true
 toastText.Text = if response.ok then "+" .. tostring(response.amount) .. " Corn  ·  Growing again!" else response.reason
 if response.ok then
  if pulseTween then pulseTween:Cancel() end
  pulse.Scale = 1.08
  pulseTween = TweenService:Create(pulse, TweenInfo.new(0.25, Enum.EasingStyle.Back), {Scale = 1})
  pulseTween:Play()
 end
 task.delay(2.5, function() if revision == toastRevision then toast.Visible = false end end)
end)
local function layout()
 local camera = workspace.CurrentCamera
 if not camera then return end
 local compact = camera.ViewportSize.X < 700 or camera.ViewportSize.Y < 500
 nav.Size = UDim2.fromOffset(if compact then 118 else 150, 210)
 nav.Position = UDim2.fromOffset(12, if compact then 156 else 170)
 for _,name in {"Shop", "Quests", "Upgrades"} do (nav:FindFirstChild(name) :: Frame).Visible = not compact end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(layout)
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
render() layout()
gui.Parent = player:WaitForChild("PlayerGui")
require(script.Parent.PromptController).start(gui)
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
