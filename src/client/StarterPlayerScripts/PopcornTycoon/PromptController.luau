--!strict
local Prompts = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local Theme = require(script.Parent.UITheme)
local Controller = {}
function Controller.start(gui: ScreenGui)
 local active: {[ProximityPrompt]: BillboardGui} = {}
 local watchers: {[ProximityPrompt]: RBXScriptConnection} = {}
 local function remove(prompt: ProximityPrompt)
  local watcher=watchers[prompt]
  if watcher then watcher:Disconnect() watchers[prompt]=nil end
  local display=active[prompt]
  if display then display:Destroy() active[prompt]=nil end
 end
 local farmPrompts={Harvest=true, Microwave=true, BuyRow=true}
 local function configure(object: Instance)
  if not object:IsA("ProximityPrompt") or not farmPrompts[object.Name] then return end
  local farm=object.Parent and object.Parent.Parent
  if farm and farm:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
   if object.Name=="Harvest" then object.Style=Enum.ProximityPromptStyle.Custom end
  elseif farm and farm:GetAttribute("OwnerUserId") ~= nil then
   object.Enabled=false -- Client presentation only; server still validates all interactions.
   object:GetPropertyChangedSignal("Enabled"):Connect(function()
    if object.Enabled then object.Enabled=false end
   end)
  end
 end
 local farms=workspace:WaitForChild("PopcornFarms")
 for _,object in farms:GetDescendants() do configure(object) end
 farms.DescendantAdded:Connect(configure)
 Prompts.PromptShown:Connect(function(prompt, inputType)
  if prompt.Name~="Harvest" or prompt.Style~=Enum.ProximityPromptStyle.Custom then return end
  local farm=prompt.Parent and prompt.Parent.Parent
  if not farm or farm:GetAttribute("OwnerUserId")~=Players.LocalPlayer.UserId then return end
  remove(prompt)
  local display=Instance.new("BillboardGui")
  display.Name="HarvestPrompt" display.Size=UDim2.fromOffset(172,64) display.StudsOffset=Vector3.new(0,2,0)
  display.AlwaysOnTop=true display.Adornee=prompt.Parent :: BasePart display.Active=true
  local button=Instance.new("TextButton") button.Name="Pick" button.Size=UDim2.fromScale(1,1)
  button.BackgroundColor3=Theme.Brown button.TextColor3=Theme.Cream button.Font=Enum.Font.GothamBold button.TextSize=15
  local action=if inputType==Enum.ProximityPromptInputType.Touch then "Tap · Pick corn" elseif inputType==Enum.ProximityPromptInputType.Gamepad then "X · Pick corn" else "E · Pick corn"
  local function refresh() button.Text=action.."\n"..prompt.ObjectText end
  refresh()
  watchers[prompt]=prompt:GetPropertyChangedSignal("ObjectText"):Connect(refresh) -- Count keeps growing while shown.
  Instance.new("UICorner",button).CornerRadius=UDim.new(0,14)
  local border=Instance.new("UIStroke",button) border.Color=Theme.Gold border.Thickness=2 border.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
  button.Activated:Connect(function() prompt:InputHoldBegin() prompt:InputHoldEnd() end)
  button.Parent=display display.Parent=gui active[prompt]=display
 end)
 Prompts.PromptHidden:Connect(remove)
end
return Controller
