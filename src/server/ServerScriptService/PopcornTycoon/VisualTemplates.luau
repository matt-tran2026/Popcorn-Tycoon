--!strict
-- Published model identifiers returned by Studio's generation pipeline.
-- Load once, sanitize, then clone for each owned farm. No asset scripts execute.
local InsertService = game:GetService("InsertService")
local Templates = {}
local cache: {[string]: Model} = {}
local ids = {Corn = 125811337408333, Microwave = 122309358743155, Shed = 74041170609438}
function Templates.load()
 for name,id in ids do
  local ok,result=pcall(function() return InsertService:LoadAsset(id) end)
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
