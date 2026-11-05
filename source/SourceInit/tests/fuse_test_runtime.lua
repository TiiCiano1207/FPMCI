local hooks={};local jobs={};local frame=0
local cfg={msl={enabled=true,trigger=30,blast=50,damage=30},qaam={enabled=false,trigger=30,blast=50,damage=30},sasm={enabled=false,trigger=30,blast=50,damage=30}}
local realDofile=dofile
dofile=function(path)if path:match('settings.lua$')then return cfg end;return realDofile(path)end
local function object(t)t.IsValid=function()return true end;return t end
local function weapon(addr,token)
 local w=object({addr=addr,bHidden=false,bCollided=false,WeaponMovement=object({bSimulationEnabled=true}),
 bShouldDetonateOnMiss=false,ProximityFuseRadiusSquared=0,ProximityFuseDuration=0,ExplosionRadius=0,AreaOfEffectDamage=0,
 MaxHomingAngle=75,MaxHomingAngleNotCaptured=75,LifeTime=9,HomingForesightAmount=.7})
 w.GetAddress=function(self)return self.addr end
 w.GetClass=function()return {GetFName=function()return {ToString=function()return 'BP_plwp_'..token..'_a0_C'end}end}end
 w.K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end
 w.TargetToHome=object({GetHealth=function()return 100 end,K2_GetActorLocation=function()return {X=DISTANCE,Y=0,Z=0}end})
 return w
end
local player=object({PlayerWeaponActivator=object({ActiveWeapons={},SpawnedWeapons={}})})
local engine=object({GameViewport={World={OwningGameInstance={LocalPlayers={{PlayerController={Pawn=player}}}}}}})
FindFirstOf=function(name)assert(name=='GameEngine');return engine end
ExecuteInGameThreadAfterFrames=function(n,fn)jobs[#jobs+1]={due=frame+n,fn=fn}end
RegisterHook=function(path,pre,post)hooks[path]={pre,post}end
RegisterLoadMapPreHook=function(fn)map=fn end
RegisterInitGameStatePreHook=function(fn)init=fn end
local function advance(n)
 for i=1,n do
  frame=frame+1;local ready={};local waiting={}
  for _,j in ipairs(jobs)do if j.due<=frame then ready[#ready+1]=j else waiting[#waiting+1]=j end end
  jobs=waiting;for _,j in ipairs(ready)do j.fn()end
 end
end
local function hook(name,phase,w)hooks['/Script/Live.'..name][phase]({get=function()return w end})end
local m=realDofile(TEST_ROOT..'/main.lua');m.start();m.start()
local foreign=weapon(1,'msl');DISTANCE=1000
hook('LiveWeaponBase:OnCreateWeapon_BP',2,foreign);advance(40)
assert(foreign.MaxHomingAngle==75 and foreign.ExplosionRadius==0)
local mine=weapon(2,'msl');local off=weapon(3,'qaam');local sasm=weapon(4,'sasm');sasm.ExplosionRadius=5000;sasm.AreaOfEffectDamage=30
player.PlayerWeaponActivator.ActiveWeapons={mine,off,sasm}
DISTANCE=10000;hook('LivePlayerWeaponActivator:MainWeaponPressed',2,mine);advance(650)
assert(mine.MaxHomingAngle==75)
DISTANCE=2000;advance(1)
assert(mine.MaxHomingAngle==0 and off.MaxHomingAngle==75 and off.ExplosionRadius==0 and sasm.ExplosionRadius==5000)
hook('LiveWeaponBase:OnWeaponDestroyed',1,mine)
assert(mine.MaxHomingAngle==75 and mine.ExplosionRadius==5000 and mine.AreaOfEffectDamage==30)
hook('LiveWeaponBase:OnWeaponDestroyed',2,mine)
assert(mine.ExplosionRadius==0 and mine.AreaOfEffectDamage==0)
mine.LifeTime=20;mine.MaxHomingAngle=100;mine.bHidden=true;advance(3)
assert(mine.LifeTime==20 and mine.MaxHomingAngle==100)
map();init();advance(3)
assert(mine.HomingForesightAmount==.7)
print('PASS local player ownership, mixed enabled/disabled weapons, original SASM, flight longer than 300 frames, pre-destruction restoration and map epoch')
