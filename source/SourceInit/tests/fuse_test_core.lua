local Core=dofile(TEST_ROOT..'/core.lua')
local defaults={bShouldDetonateOnMiss=false,ProximityFuseRadiusSquared=0,ProximityFuseDuration=0,
 ExplosionRadius=0,AreaOfEffectDamage=0,MaxHomingAngle=75,MaxHomingAngleNotCaptured=75,LifeTime=9,HomingForesightAmount=.7}
local function copy(t)local c={};for k,v in pairs(t)do c[k]=v end;return c end
local jobs,writes={},0
local failField
local api={id=function(w)return w.id end,valid=function()return true end,flying=function()return true end,
 get=function(w,k)return w[k]end,set=function(w,k,v)if k==failField then error('setter failure')end;writes=writes+1;w[k]=v end,
 after=function(n,fn)jobs[#jobs+1]=fn end,report=function()end}
local c=Core.new(api,{msl={enabled=false,trigger=30,blast=50,damage=30},qaam={enabled=true,trigger=30,blast=50,damage=30},sasm={enabled=false,trigger=30,blast=50,damage=30}})
local w=copy(defaults);w.id=42
assert(not c.trigger(w,'msl',1000)and writes==0)
local sasm=copy(w);sasm.ExplosionRadius=5000;sasm.AreaOfEffectDamage=30
assert(not c.trigger(sasm,'sasm',1000)and sasm.ExplosionRadius==5000 and writes==0)
assert(not c.trigger(w,'qaam',3001)and writes==0)
assert(c.trigger(w,'qaam',2500));assert(w.HomingForesightAmount==.7 and w.MaxHomingAngle==0 and w.ExplosionRadius==5000)
assert(not c.trigger(w,'qaam',100));c.finish(w)
for k,v in pairs(defaults)do assert(w[k]==v,k)end
-- Reuse the same address with new engine-initialized values before old callback.
w.LifeTime=17;w.MaxHomingAngle=90;w.HomingForesightAmount=.85
jobs[1]();assert(w.LifeTime==17 and w.MaxHomingAngle==90 and w.HomingForesightAmount==.85)
assert(c.trigger(w,'qaam',100));jobs[2]();assert(w.LifeTime==.001)
c.finish(w);assert(w.LifeTime==17 and w.MaxHomingAngle==90 and w.HomingForesightAmount==.85)
assert(c.trigger(w,'qaam',100));local stale=jobs[3];c.clear();w.LifeTime=25;stale();assert(w.LifeTime==25)
-- Missing required properties produces no partial write.
local bad=copy(defaults);bad.id=99;bad.MaxHomingAngleNotCaptured=nil
local before=writes;assert(not pcall(c.trigger,bad,'qaam',1));assert(writes==before)
-- Any partial setter failure restores every field that could have changed.
local broken=copy(defaults);broken.id=10
local first=true;api.set=function(o,k,v)if first and k=='ExplosionRadius'then first=false;error('fixture failure')end;writes=writes+1;o[k]=v end
assert(not pcall(c.trigger,broken,'qaam',1));for k,v in pairs(defaults)do assert(broken[k]==v,k)end
print('PASS independent switches, SASM original, distance boundary, field ownership, restoration, address reuse, late callbacks and partial write rollback')
