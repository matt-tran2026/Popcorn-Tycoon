--!strict
-- Shared ocean and horizon dressing; generated once, outside the hub and player islands.
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
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
 local map=Config.Map
 local ocean=map.oceanSize
 -- The baseplate becomes the sea floor; swimmable terrain water fills the bay above it.
 local floorTop=map.waterLevel-16
 local baseplate=workspace:FindFirstChild("Baseplate")
 if baseplate and baseplate:IsA("BasePart") then
  baseplate.Size=Vector3.new(ocean,4,ocean)
  baseplate.Position=map.center+Vector3.new(0,floorTop-2,0)
  baseplate.Color=Color3.fromRGB(205,186,140) baseplate.Material=Enum.Material.Sand
  for _,d in baseplate:GetChildren() do if d:IsA("Texture") or d:IsA("Decal") then d.Transparency=1 end end
 end
 local terrain=workspace.Terrain
 terrain.WaterColor=Color3.fromRGB(64,170,206) terrain.WaterTransparency=0.55
 terrain.WaterWaveSize=0.08 terrain.WaterWaveSpeed=6 terrain.WaterReflectance=0.4
 -- Filled in strips so one call never blocks the server for long.
 local depth=map.waterLevel-floorTop
 local strips=8
 for i=0,strips-1 do
  local z=-ocean/2+(i+0.5)*ocean/strips
  terrain:FillBlock(CFrame.new(map.center+Vector3.new(0,floorTop+depth/2,z)),Vector3.new(ocean,depth,ocean/strips),Enum.Material.Water)
  task.wait()
 end
 -- A ring of distant hill islands frames the horizon without crowding the farms.
 local random=Random.new(7412)
 local count=20
 for i=1,count do
  local theta=(i-1)*2*math.pi/count+random:NextNumber(-0.06,0.06)
  local dir=Vector3.new(math.sin(theta),0,math.cos(theta))
  local at=map.center+dir*random:NextNumber(400,460)
  shape("DistantIsle",at+Vector3.new(0,map.waterLevel-1,0),Vector3.new(70,6,70),Color3.fromRGB(205,186,140),Enum.Material.Sand,true)
  shape("DistantHill",at+Vector3.new(0,-10,0)+dir*12,Vector3.new(80,random:NextNumber(45,70),75),Color3.fromRGB(103,153,78),Enum.Material.Grass,true)
  shape("Cliff",at+Vector3.new(0,4,0)-dir*14,Vector3.new(30,random:NextNumber(16,26),22),Color3.fromRGB(133,143,133),Enum.Material.Rock,true)
  Templates.clone("Oak", root, at-dir*24+Vector3.new(0,map.waterLevel+1,0), random:NextNumber(18,26))
  if i%4==0 then task.wait() end
 end
 local lighting=game:GetService("Lighting")
 lighting.ClockTime=14.5 lighting.Brightness=2.5 lighting.Ambient=Color3.fromRGB(134,119,98) lighting.OutdoorAmbient=Color3.fromRGB(152,165,169)
 lighting.GlobalShadows=true
 local atmosphere=lighting:FindFirstChildOfClass("Atmosphere")
 if atmosphere then atmosphere.Density=0.23 atmosphere.Haze=1.3 atmosphere.Color=Color3.fromRGB(200,224,239) atmosphere.Decay=Color3.fromRGB(171,190,205) end
end
return Environment
