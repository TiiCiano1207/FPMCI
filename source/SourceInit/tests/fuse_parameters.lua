
local Core=dofile(ROOT..'/core.lua')
local jobs={};local writes=0
local api={id=function(w)return w.id end,get=function(w,k)return w[k]end,set=function(w,k,v)writes=writes+1;w[k]=v end,
 valid=function()return true end,flying=function()return true end,after=function(n,fn)jobs[#jobs+1]=fn end,report=function()end}
local cfg={msl={enabled=true,trigger=15,blast=25,damage=40},qaam={enabled=true,trigger=60,blast=80,damage=90},sasm={enabled=false,trigger=30,blast=50,damage=30}}
local c=Core.new(api,cfg)
local function weapon(id)return{id=id,bShouldDetonateOnMiss=false,ProximityFuseRadiusSquared=0,ProximityFuseDuration=0,ExplosionRadius=0,AreaOfEffectDamage=0,MaxHomingAngle=75,MaxHomingAngleNotCaptured=75,LifeTime=9,HomingForesightAmount=.7}end
local a,b=weapon(1),weapon(2)
assert(not c.trigger(a,'msl',1501)and writes==0)
assert(c.trigger(b,'qaam',6000)and b.ProximityFuseRadiusSquared==36000000 and b.ExplosionRadius==8000 and b.AreaOfEffectDamage==90)
assert(c.trigger(a,'msl',1500)and a.ProximityFuseRadiusSquared==2250000 and a.ExplosionRadius==2500 and a.AreaOfEffectDamage==40)
assert(a.HomingForesightAmount==.7 and b.HomingForesightAmount==.7)
local old=c.prepare_destroy(a);assert(a.ExplosionRadius==2500 and a.MaxHomingAngle==75);c.finish(a,old);assert(a.ExplosionRadius==0)
a.LifeTime=17;assert(c.trigger(a,'msl',100));c.finish(a,old);assert(a.MaxHomingAngle==0)
jobs[2]();assert(a.LifeTime==17);c.finish(a);assert(a.LifeTime==17 and a.AreaOfEffectDamage==0)
local off=weapon(3);off.ExplosionRadius=5000;off.AreaOfEffectDamage=30;assert(not c.trigger(off,'sasm',0)and off.ExplosionRadius==5000)
for _,bad in ipairs({0,-1,201,0/0,math.huge})do local ok=pcall(Core.new,api,{msl={enabled=true,trigger=bad,blast=50,damage=30}});assert(not ok)end
print('PASS independent trigger/blast/damage, unit conversion, boundaries, disabled original, homing independence, restore and stale-token guard')
