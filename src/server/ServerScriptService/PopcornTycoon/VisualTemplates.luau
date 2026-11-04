--!strict
-- Published model identifiers returned by Studio's generation pipeline.
-- Load once, sanitize, then clone for each owned farm. No asset scripts execute.
-- A model kept in the place (ServerStorage.PopcornTemplates) wins over the published asset id.
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local Templates = {}
local cache: {[string]: Model} = {}
local ids = {Corn = 125811337408333, Microwave = 122309358743155}
-- Corn: the Blender-built blocky stalk (Assets/CornStalk/CornStalk_Roblox.fbx). Parts named "Corn_*"
-- are the cobs and husks, which FarmService only shows once the stalk is ripe.
-- Microwave: the Blender-built brick kiosk (Assets/MicrowaveStand/MicrowaveStand.fbx, Nov 4 2026)
-- with its MicrowaveBody mesh and named anchor attachments; the old generated kiosk asset
-- stays the fallback.
local localNames = {Corn = "CornStalk", Microwave = "MicrowaveStand"}
local function loadLocal(name: string): (boolean, any)
 local folder = ServerStorage:FindFirstChild("PopcornTemplates")
 local source = if folder and localNames[name] then folder:FindFirstChild(localNames[name]) else nil
 if source and source:IsA("Model") then
  local model = Instance.new("Model")
  source:Clone().Parent = model -- Same shape as a LoadAsset result: a wrapper model.
  return true, model
 end
 return false, nil
end
function Templates.load()
 for name,id in ids do
  local ok,result=loadLocal(name)
  if not ok then ok,result=pcall(function() return InsertService:LoadAsset(id) end) end
  if ok then
   local model=result :: Model
   for _,v in model:GetDescendants() do
    if v:IsA("LuaSourceContainer") then v:Destroy()
    elseif v:IsA("BasePart") then v.Anchored=true v.CanCollide=false v.CanTouch=false v.CanQuery=false end
   end
   model.Name=name
   cache[name]=model
  else warn("[PopcornTycoon] Visual template unavailable: "..name) end
 end
end
-- True when the loaded template carries a descendant with this name (e.g. an anchor attachment).
function Templates.has(name: string, descendant: string): boolean
 local template=cache[name]
 return template~=nil and template:FindFirstChild(descendant, true)~=nil
end
function Templates.clone(name: string, parent: Instance, bottom: Vector3, height: number): Model?
 local template=cache[name]
 if not template then return nil end
 local model=template:Clone()
 local _,size=model:GetBoundingBox()
 model:ScaleTo(model:GetScale()*height/size.Y)
 local bounds,scaled=model:GetBoundingBox()
 local delta=bottom+Vector3.new(0,scaled.Y/2,0)-bounds.Position
 model:PivotTo(model:GetPivot()+delta)
 model.Parent=parent
 return model
end
return Templates
