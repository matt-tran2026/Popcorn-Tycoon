--!strict
-- Owner-only farm prompts. Your own pick prompts use the Custom style, so Roblox draws no
-- button; HarvestHighlight shows the glow, the key chip and the corn pips instead (Nov 3 2026,
-- replacing the brown "E · Pick corn" button). Other players' farm prompts are disabled here.
local Players = game:GetService("Players")
local Controller = {}
-- Kept for ToolController; while a swung tool is held the highlight shows tool targets instead.
function Controller.setHarvestSuppressed(_value: boolean) end
function Controller.start(_gui: ScreenGui)
 local farmPrompts={Harvest=true, Microwave=true, BuyRow=true, Sell=true}
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
end
return Controller
