-- Instance-only adaptation of AC8ProximityFuse 0.0.2's active airburst.
-- No assets, CDOs, DataTables or input bindings are accessed here.
local M={}
local fields={'bShouldDetonateOnMiss','ProximityFuseRadiusSquared','ProximityFuseDuration',
 'ExplosionRadius','AreaOfEffectDamage','MaxHomingAngle','MaxHomingAngleNotCaptured','LifeTime'}
local function equal(a,b)
 return type(a)==type(b) and (a==b or type(a)=='number' and math.abs(a-b)<=math.max(1e-5,math.abs(b)*1e-6))
end
function M.new(api,settings)
 for _,s in pairs(settings)do
  assert(type(s)=='table'and type(s.enabled)=='boolean','Invalid fuse switch')
  for _,r in ipairs({{'trigger',200},{'blast',500},{'damage',500}})do local v=s[r[1]];assert(type(v)=='number'and v==v and v>=1 and v<=r[2],'Invalid fuse parameter: '..r[1])end
 end
 local journals={}
 local self={}
 function self.finish(w,expected)
  local id=api.id(w);local j=journals[id]
  if not j or expected and j~=expected then return true end
  -- Invalidate delayed callbacks before restoring a pooled object.
  j.live=false
  for _,k in ipairs(fields)do
   api.set(w,k,j.original[k])
   assert(equal(api.get(w,k),j.original[k]),'Fuse restoration failed: '..k)
  end
  journals[id]=nil
  return true
 end
 function self.prepare_destroy(w)
  local j=journals[api.id(w)]
  if not j then return nil end
  j.live=false
  -- Preserve blast fields until the engine's destruction/damage call completes.
  for _,k in ipairs({'MaxHomingAngle','MaxHomingAngleNotCaptured','LifeTime'})do
   api.set(w,k,j.original[k]);assert(equal(api.get(w,k),j.original[k]),'Fuse restoration failed: '..k)
  end
  return j
 end
 function self.trigger(w,kind,distance)
  local setting=settings[kind]
  if not setting or not setting.enabled or distance>setting.trigger*100 or distance<0 or distance~=distance then return false end
  local burst={bShouldDetonateOnMiss=true,ProximityFuseRadiusSquared=(setting.trigger*100)^2,
   ProximityFuseDuration=0,ExplosionRadius=setting.blast*100,AreaOfEffectDamage=setting.damage,
   MaxHomingAngle=0,MaxHomingAngleNotCaptured=0}
  local id=api.id(w)
  if journals[id] then return false end
  local original={}
  for _,k in ipairs(fields)do
   local v=api.get(w,k)
   assert(k=='bShouldDetonateOnMiss' and type(v)=='boolean' or k~='bShouldDetonateOnMiss' and type(v)=='number' and v==v and math.abs(v)<math.huge,'Missing fuse field: '..k)
   original[k]=v
  end
  local j={original=original,live=true};journals[id]=j
  local ok,err=pcall(function()
   for k,v in pairs(burst)do api.set(w,k,v);assert(equal(api.get(w,k),v),'Fuse readback failed: '..k)end
   api.after(2,function()
    if journals[id]==j and j.live and api.valid(w) and api.id(w)==id and api.flying(w)then
     local applied,why=pcall(function()api.set(w,'LifeTime',0.001);assert(equal(api.get(w,'LifeTime'),0.001),'Fuse lifetime readback failed')end)
     if not applied then j.live=false;api.report(why)end
    end
   end)
  end)
  if not ok then self.finish(w);error(err)end
  return true
 end
 function self.clear()
  -- World transition invalidates all callbacks; old-world objects are not reused.
  for _,j in pairs(journals)do j.live=false end
  journals={}
 end
 function self.forget(id)
  if journals[id]then journals[id].live=false;journals[id]=nil end
 end
 return self
end
return M
