-- FPMCI instance-only integration derived from AC8ProximityFuse v0.0.2.
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
local enabled=dofile(dir..'settings.lua')
local Core=dofile(dir..'core.lua')
local M={};local started=false
local function safe(fn)local ok,v=pcall(fn);if ok then return v end end
local function valid(o)return o~=nil and safe(function()return o:IsValid()end)==true end
local function id(o)return o:GetAddress()end
local function flying(o)
 if not valid(o)then return false end
 return safe(function()return not o.bHidden and not o.bCollided end)==true
  and safe(function()return o.WeaponMovement.bSimulationEnabled end)~=false
end
local notices=0
local function report(err)
 if notices<8 then notices=notices+1;print('[FPMCIFuse] '..tostring(err)..'\n')end
end
local function kind(o)
 return safe(function()return o:GetClass():GetFName():ToString():lower():match('^bp_plwp_([a-z0-9]+)_[a-z0-9]+_c$')end)
end
local core=Core.new({id=id,valid=valid,flying=flying,get=function(o,k)return o[k]end,
 set=function(o,k,v)o[k]=v end,after=function(n,fn)ExecuteInGameThreadAfterFrames(n,fn)end,report=report},enabled)
local engine;local tracked={};local destroying={};local active=false;local warmup=0;local epoch=0
local function pawn()
 if not valid(engine)then return nil end
 return safe(function()return engine.GameViewport.World.OwningGameInstance.LocalPlayers[1].PlayerController.Pawn end)
end
local function collect()
 local current={};local player=pawn()
 if not valid(player)then return current end
 local act=safe(function()return player.PlayerWeaponActivator end)
 if not valid(act)then return current end
 for _,name in ipairs({'ActiveWeapons','SpawnedWeapons'})do
  local arr=safe(function()return act[name]end);local n=arr and safe(function()return #arr end)
  if type(n)=='number'and n>=0 and n<=512 then
   for i=1,n do
    local w=safe(function()return arr[i]end)
    if flying(w)then local t=kind(w);if t and enabled[t]and enabled[t].enabled then current[id(w)]={weapon=w,kind=t}end end
   end
  end
 end
 return current
end
local function distance(w,target)
 local a=safe(function()return w:K2_GetActorLocation()end)
 local b=safe(function()return target:K2_GetActorLocation()end)
 if a and b then
  local ok,d=pcall(function()local x,y,z=b.X-a.X,b.Y-a.Y,b.Z-a.Z;return math.sqrt(x*x+y*y+z*z)end)
  if ok and d==d then return d end
 end
 local sq=safe(function()return w.DistanceFromTargetSquared end)
 if type(sq)=='number'and sq>=0 then return math.sqrt(sq)end
end
local function check(entry)
 local w=entry.weapon
 local target=safe(function()return w.TargetToHome end)
 if not valid(target)then target=safe(function()return w.WeaponMovement.HomingTarget end)end
 if not valid(target)then return end
 local hp=safe(function()return target:GetHealth()end)
 if type(hp)=='number'and hp<=0 then return end
 local d=distance(w,target)
 if d then local ok,err=pcall(core.trigger,w,entry.kind,d);if not ok then report(err)end end
end
local function step(token)
 if token~=epoch then return end
 warmup=math.max(0,warmup-1)
 local current=collect()
 -- Restore instances that leave the player's active pools while still valid.
 for addr,entry in pairs(tracked)do
  if not current[addr]then
   if valid(entry.weapon)then
    local ok,err=pcall(core.finish,entry.weapon);if not ok then report(err)end
   else core.forget(addr)end
  end
 end
 tracked=current
 for _,entry in pairs(current)do check(entry)end
 if next(current)or warmup>0 then ExecuteInGameThreadAfterFrames(1,function()step(token)end)
 else active=false end
end
local function wake()
 warmup=30
 if active then return end
 active=true;local token=epoch
 ExecuteInGameThreadAfterFrames(1,function()step(token)end)
end
local function restore(context)
 local w=safe(function()return context:get()end)
 if not valid(w)then return end
 local addr=id(w)
 destroying[addr]=nil
 local ok,err=pcall(core.finish,w);if not ok then report(err)end
 tracked[addr]=nil
end
function M.start()
 if started then return end
 local any=false;for _,v in pairs(enabled)do if v.enabled then any=true;break end end
 if not any then started=true;return end
 assert(type(ExecuteInGameThreadAfterFrames)=='function'and type(RegisterHook)=='function','Fuse requires game-thread hooks')
 engine=FindFirstOf('GameEngine')
 RegisterHook('/Script/Live.LivePlayerWeaponActivator:MainWeaponPressed',function()end,wake)
 RegisterHook('/Script/Live.LiveWeaponBase:OnWeaponDestroyed',function(context)
  local w=safe(function()return context:get()end)
  if valid(w)then
   local ok,token=pcall(core.prepare_destroy,w)
   if ok then destroying[id(w)]=token else report(token)end
  end
 end,function(context)
  local w=safe(function()return context:get()end)
  if valid(w)then
   local addr=id(w);local token=destroying[addr];destroying[addr]=nil
   if token then local ok,err=pcall(core.finish,w,token);if not ok then report(err)end end
   tracked[addr]=nil
  end
 end)
 -- Restoration precedes engine initialization, never overwrites fresh new-use data.
 RegisterHook('/Script/Live.LiveWeaponBase:OnInitialized',restore,wake)
 RegisterHook('/Script/Live.LiveWeaponBase:OnCreateWeapon_BP',function()end,wake)
 RegisterLoadMapPreHook(function()
  epoch=epoch+1;active=false;warmup=0
  for _,entry in pairs(tracked)do if valid(entry.weapon)then
   local ok,err=pcall(core.finish,entry.weapon);if not ok then report(err)end
  end end
  tracked={};destroying={};core.clear();engine=nil
 end)
 RegisterInitGameStatePreHook(function()engine=FindFirstOf('GameEngine')end)
 started=true
 print('[FPMCIFuse] Instance-only hooks ready; live validation pending\n')
end
return M
