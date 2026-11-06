--!strict
-- Owner-only farm prompts. Your own pick prompts use the Custom style, so Roblox draws no
-- button; HarvestHighlight shows the glow, the key chip and the corn pips instead (Nov 3 2026,
-- replacing the brown "E · Pick corn" button). Other players' farm prompts are disabled here.
local Players = game:GetService("Players")
local Controller = {}
-- Your own pick prompts and their normal reach. While a swung tool is held (ToolController) they
-- are switched off by a zero reach, so corn comes only from swings (creator, Nov 6 2026); the
-- server refuses hand picks with a tool equipped as well (HarvestService.attempt). Reach is used
-- rather than Enabled because the server drives Enabled.
local own: { [ProximityPrompt]: number } = {}
local suppressed = false
local function apply(prompt: ProximityPrompt)
 prompt.MaxActivationDistance = if suppressed then 0 else own[prompt]
end
function Controller.setHarvestSuppressed(value: boolean)
 suppressed = value
 for prompt in own do
  if prompt.Parent then apply(prompt) else own[prompt] = nil end
 end
end
function Controller.start(_gui: ScreenGui)
 local farmPrompts={Harvest=true, Microwave=true, Sell=true} -- Land is bought on step-on pads (PadController).
 local function configure(object: Instance)
  if not object:IsA("ProximityPrompt") or not farmPrompts[object.Name] then return end
  local farm=object.Parent and object.Parent.Parent
  if farm and farm:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
   if object.Name=="Harvest" then
    object.Style=Enum.ProximityPromptStyle.Custom
    own[object] = object.MaxActivationDistance
    apply(object)
    object.Destroying:Connect(function() own[object] = nil end)
   end
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
