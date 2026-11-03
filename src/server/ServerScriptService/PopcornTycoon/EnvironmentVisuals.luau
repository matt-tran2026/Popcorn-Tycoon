--!strict
-- Shared ocean and horizon dressing; generated once, outside the hub and player islands.
local Config = require(game.ReplicatedStorage.PopcornTycoon.Config)
local Environment = {}
local Brick = require(script.Parent.BrickStyle)
function Environment.build()
 if workspace:FindFirstChild("PopcornCountryside") then return end
 local root = Instance.new("Model") root.Name = "PopcornCountryside" root.Parent = workspace
 local function shape(name: string, cframe: CFrame, size: Vector3, color: Color3): Part
  local p=Instance.new("Part") p.Name=name p.Anchored=true p.CanCollide=true p.CanTouch=false
  p.CFrame=cframe p.Size=size p.Color=color p.Material=Enum.Material.SmoothPlastic
  p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
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
  Brick.studs(baseplate) -- The sea floor is studded brick like the rest of the map.
  for _,d in baseplate:GetChildren() do if d:IsA("Texture") then d.Transparency=1 end end
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
 -- A ring of distant terraced brick islands frames the horizon without crowding the farms.
 -- They are solid, so a player who swims out can climb them.
 local random=Random.new(7412)
 local count=20
 local sand, grass, rock = Color3.fromRGB(226,200,140), Color3.fromRGB(98,178,62), Color3.fromRGB(150,150,140)
 for i=1,count do
  local theta=(i-1)*2*math.pi/count+random:NextNumber(-0.06,0.06)
  local dir=Vector3.new(math.sin(theta),0,math.cos(theta))
  local at=map.center+dir*random:NextNumber(400,460)
  local frame=CFrame.lookAt(at, map.center) -- Each isle turns its front toward the hub.
  local beach=map.waterLevel+1
  shape("DistantIsle",frame*CFrame.new(0,beach-2-at.Y,0),Vector3.new(72,4,64),sand)
  -- Three stepped grass terraces, highest toward the back like a hillside.
  local top=beach
  for step,size in {Vector3.new(58,random:NextNumber(6,9),46),Vector3.new(42,random:NextNumber(6,9),32),Vector3.new(26,random:NextNumber(5,8),20)} do
   shape("Terrace",frame*CFrame.new(0,top+size.Y/2-at.Y,step*4),size,grass)
   top+=size.Y
  end
  shape("Cliff",frame*CFrame.new(random:NextNumber(-22,-14),beach+5-at.Y,-6),Vector3.new(10,10,8),rock)
  Brick.tree(root, at+frame.LookVector*24+frame.RightVector*random:NextNumber(-16,16)+Vector3.new(0,beach-at.Y,0), random:NextNumber(16,22), 7412+i)
  if i%4==0 then task.wait() end
 end
 Brick.finish(root, map.waterLevel)
 local lighting=game:GetService("Lighting")
 lighting.ClockTime=14.5 lighting.Brightness=2.5 lighting.Ambient=Color3.fromRGB(134,119,98) lighting.OutdoorAmbient=Color3.fromRGB(152,165,169)
 lighting.GlobalShadows=true
 local atmosphere=lighting:FindFirstChildOfClass("Atmosphere")
 if atmosphere then atmosphere.Density=0.23 atmosphere.Haze=1.3 atmosphere.Color=Color3.fromRGB(200,224,239) atmosphere.Decay=Color3.fromRGB(171,190,205) end
end
return Environment
