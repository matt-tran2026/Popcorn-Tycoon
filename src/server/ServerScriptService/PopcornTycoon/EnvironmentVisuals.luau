--!strict
-- Shared countryside dressing; generated once, outside the reusable player plots.
local Environment = {}
local Templates = require(script.Parent.VisualTemplates)
function Environment.build()
 if workspace:FindFirstChild("PopcornCountryside") then return end
 local root = Instance.new("Model") root.Name = "PopcornCountryside" root.Parent = workspace
 local function shape(name: string, pos: Vector3, size: Vector3, color: Color3, material: Enum.Material, ball: boolean?): Part
  local p=Instance.new("Part") p.Name=name p.Anchored=true p.CanCollide=false p.CanTouch=false p.CanQuery=false
  p.Position=pos p.Size=size p.Color=color p.Material=material
  if ball then p.Shape=Enum.PartType.Ball end
  p.Parent=root return p
 end
 shape("Meadow",Vector3.new(180,0.015,50),Vector3.new(900,0.1,700),Color3.fromRGB(101,158,66),Enum.Material.Grass)
 local random=Random.new(7412)
 for i=1,22 do
  local x=-200+(i-1)*32
  local z=115+random:NextNumber(0,45)
  shape("DistantHill",Vector3.new(x,-8,z+95),Vector3.new(120,random:NextNumber(45,65),110),Color3.fromRGB(103,153,78),Enum.Material.Grass,true)
  shape("Cliff",Vector3.new(x,5,z+20),Vector3.new(35,random:NextNumber(18,30),24),Color3.fromRGB(133,143,133),Enum.Material.Rock,true)
  Templates.clone("Oak", root, Vector3.new(x,0,z), random:NextNumber(18,28))
  if i%4==0 then task.wait() end
 end
 -- Frame the first plot entrance (spawn faces it) without crowding its front fence.
 for _,x in {-32,65} do
  Templates.clone("Oak", root, Vector3.new(x,0,5), 23)
 end
 -- A bounded, non-interactive stream behind the plots gives the background depth.
 -- Keep its banks beyond the player plot footprint and future outward expansion gap.
 local water = shape("CountrysideStream", Vector3.new(180,0.18,103), Vector3.new(900,0.15,15), Color3.fromRGB(80,181,202), Enum.Material.Glass)
 water.Transparency=0.2 water.Reflectance=0.12
 for i=1,18 do
  local x=-190+(i-1)*45
  local bank=shape("Riverbank",Vector3.new(x,-0.7,94),Vector3.new(50,3,8),Color3.fromRGB(150,153,117),Enum.Material.Rock,true)
  bank.Orientation=Vector3.new(0,random:NextNumber(-8,8),0)
 end
 -- Static overlapping ribbons avoid expensive particles and per-effect scripts.
 shape("WaterfallCliff",Vector3.new(-60,12,131),Vector3.new(28,28,18),Color3.fromRGB(124,139,141),Enum.Material.Rock)
 shape("WaterfallGrassCap",Vector3.new(-60,26,131),Vector3.new(30,1,20),Color3.fromRGB(102,157,67),Enum.Material.Grass)
 for i=1,5 do
  local ribbon=shape("WaterfallRibbon",Vector3.new(-68+i*2.6,13,120.8),Vector3.new(2.8,25,0.3),Color3.fromRGB(127+i*15,210+i*6,238),Enum.Material.Glass)
  ribbon.Transparency=0.18
 end
 shape("WaterfallPool",Vector3.new(-60,0.23,114),Vector3.new(25,0.2,27),Color3.fromRGB(107,204,220),Enum.Material.Glass,true)
 local lighting=game:GetService("Lighting")
 lighting.ClockTime=14.5 lighting.Brightness=2.5 lighting.Ambient=Color3.fromRGB(134,119,98) lighting.OutdoorAmbient=Color3.fromRGB(152,165,169)
 lighting.GlobalShadows=true
 local atmosphere=lighting:FindFirstChildOfClass("Atmosphere")
 if atmosphere then atmosphere.Density=0.23 atmosphere.Haze=1.3 atmosphere.Color=Color3.fromRGB(200,224,239) atmosphere.Decay=Color3.fromRGB(171,190,205) end
 local spawn=workspace:FindFirstChildOfClass("SpawnLocation")
 if spawn then
  spawn.Transparency=1
  for _,d in spawn:GetChildren() do if d:IsA("Decal") then d.Transparency=1 end end
  -- Face newcomers toward their starter plot.
  spawn.CFrame=CFrame.new(spawn.Position)*CFrame.Angles(0,math.pi,0)
 end
end
return Environment
