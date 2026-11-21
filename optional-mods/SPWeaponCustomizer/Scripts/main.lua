local dir=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
local build=dofile(dir.."build.lua")
local diagnosticsOK,diagnostics=pcall(function()return dofile(dir.."diagnostics.lua")(dir,"2.6",build.id)end)
if not diagnosticsOK then diagnostics={write=function()end,snapshot=function()end} end
local defs=dofile(dir.."definitions.lua")
local balance=dofile(dir.."fpmci_balance.lua")(defs)
local mountPaths=dofile(dir.."mount_paths.lua")
local weaponNames={}
for name,id in pairs(defs.weapons) do weaponNames[id]=name end
local function log(s) print("[AC8SPWeapon] "..s.."\n");diagnostics.write(s) end

local file=assert(io.open(dir.."../Settings.ini","r"),"Cannot open Settings.ini")
local text=file:read("*a");file:close();text=text:gsub("^\239\187\191","")
local config={};local current=nil
for raw in text:gmatch("[^\r\n]+") do
    local line=raw:match("^%s*(.-)%s*$")
    if line~="" and not line:match("^[#;]") then
        local section=line:match("^%[(.-)%]$")
        if section then
            assert(config[section]==nil,"Duplicate section: "..section)
            config[section]={};current=section
        else
            assert(current,"Setting outside a section: "..line)
            local key,value=line:match("^([%w_]+)%s*=%s*([%w_%-]+)%s*$")
            assert(key and value,"Invalid setting: "..line)
            assert(config[current][key]==nil,"Duplicate setting: "..current.."."..key)
            config[current][key]=value
        end
    end
end
assert(config.General and (config.General.Enabled=="0" or config.General.Enabled=="1"),"General.Enabled must be 0 or 1")
for key in pairs(config.General) do assert(key=="Enabled","Unknown General setting: "..key) end
local modelData=dofile(dir.."models.lua")
local ammoConfig=config.Ammo or {UseHighestCapacity="0"}
assert(ammoConfig.UseHighestCapacity=="0" or ammoConfig.UseHighestCapacity=="1","Ammo.UseHighestCapacity must be 0 or 1")
for key in pairs(ammoConfig) do assert(key=="UseHighestCapacity","Unknown Ammo setting: "..key) end
local ammo=dofile(dir.."ammo.lua")(dofile(dir.."ammo_defaults.lua"),ammoConfig.UseHighestCapacity=="1",log,balance.campaign)
local byTable={}
for _,d in ipairs(defs.aircraft) do
    local c=config[d.section]
    if not c then
        c={}
        log("CONFIG default model used for missing aircraft section: "..d.section)
    end
    local defaultModel=modelData.defaults[d.section] or "US"
    d.model=(c.WeaponModel or defaultModel):upper()
    if d.model~="US" and d.model~="EU" and d.model~="RU" then
        log("CONFIG invalid WeaponModel in "..d.section.."; using "..defaultModel)
        d.model=defaultModel
    end
    d.target={table.unpack(d.catalog or d.original)}
    for _,key in ipairs({'GUN','MGP'}) do
        if c[key] and c[key]:upper()~='CTR' and c[key]:upper()~='LOW' then
            log('CONFIG invalid '..key..' direction in '..d.section..'; original direction retained')
        end
    end
    for key in pairs(c) do assert(key=="WeaponModel" or key=="GUN" or key=="MGP","Unknown setting: "..d.section.."."..key) end
    if balance.additions[d.section] then byTable["DT_PlayerParameter_"..d.code]=d end
end
for section in pairs(config) do
    if section~="General" and section~="Ammo" then
        local found=false
        for _,d in ipairs(defs.aircraft) do if d.section==section then found=true;break end end
        assert(found,"Unknown aircraft section: "..section)
    end
end
log("CONFIG Enabled="..config.General.Enabled.." UseHighestCapacity="..ammoConfig.UseHighestCapacity.." aircraft="..#defs.aircraft)
if config.General.Enabled=="0" then log("Disabled");return end
local menuRuntime=dofile(dir..'menu_runtime.lua')(dir,defs,mountPaths,log,balance)
local missionSp=dofile(dir.."mission_mgp.lua")(defs.weapons.MGP,log)
-- Physical layouts remain in the workbench. Only paid selections are mirrored
-- into campaign ownership; the technology tree still uses the catalog.
local migrations={aircraft={}}
for _,d in ipairs(defs.aircraft) do
    local candidates=balance.additions[d.section]
    if d.catalog or candidates then
        d.additions={}
        for _,name in ipairs(candidates or {}) do d.additions[defs.weapons[name]]=true end
        local migration={code=d.code,section=d.section,original=d.original,target=d.catalog or d.original,
            legacySlot=d.legacySlot,legacyLoadoutIDs=d.legacyLoadoutIDs,loadout=d,additions=d.additions}
        if d.code=='PP0028_su35' then migration.podID=defs.weapons.MGP end
        migrations.aircraft[#migrations.aircraft+1]=migration
    end
end
local updateOwnership,availableSelection=dofile(dir.."ownership.lua")(migrations,dofile(dir.."plane_ids.lua"),log,missionSp.confirmed)
local mounts=dofile(dir.."mounts.lua")(mountPaths,log,modelData)

local pods=dofile(dir.."pod_visual.lua")(mounts,log)
local podAircraft={}
for _,d in ipairs(defs.aircraft) do podAircraft['BP_PlayerPlane_'..d.code..'_C']=d end
local tracked={};local controllers={};local network=false
local function valid(o)
    local ok,value=pcall(function()return o and o:IsValid()end)
    return ok and value
end
local function identity(o)
    local ok,value=pcall(function()if valid(o) then return o:GetFullName()end end)
    return ok and value or nil
end
local function alive(e)return e.name~=nil and identity(e.object)==e.name end
local function rememberController(pc)
    local name=identity(pc)
    if name then controllers[pc:GetAddress()]={object=pc,name=name} end
end
local function remember(dt,fresh)
    if not valid(dt) then return end
    local full=dt:GetFullName()
    if not full:lower():find("/datatables/player/parameter/",1,true) then return end
    local name=full:match("%.(DT_PlayerParameter_[%w_]+)$")
    local d=name and byTable[name]
    if d then
        local id=dt:GetAddress()
        if not tracked[id] or not alive(tracked[id]) then tracked[id]={object=dt,name=full,definition=d,attempts=0} end
    end
end
local function restoreEntry(e)
    if e.catalogApplied and alive(e) then
        local d=e.definition
        local row=e.object:FindRow(d.row)
        if row then
            for i=1,3 do
                local key='SpWeaponID'..i
                if d.catalog[i]~=d.original[i] and row[key]==d.catalog[i] then row[key]=d.original[i] end
            end
        end
    end
    e.catalogApplied=nil
    e.done=false;e.attempts=0
end
-- The technology tree enumerates these same three catalog IDs. Expose physical
-- loadout IDs only to synchronous consumers, then return the original catalog.
local leases={}
local function includeRow(lease,d,e)
    local row=assert(e.object:FindRow(d.row))
    for i=1,3 do assert(row['SpWeaponID'..i]==(d.catalog or d.original)[i],'Unexpected catalog ID on '..d.section) end
    local record={entry=e,definition=d,target={table.unpack(d.target)}}
    lease.rows[#lease.rows+1]=record
    ammo.apply(record,row)
    for i=1,3 do row['SpWeaponID'..i]=record.target[i] end
end
local function borrowLoadout(d)
    if leases[d] then
        local lease=leases[d]
        lease.count=lease.count+1
        return lease.release
    end
    local lease={count=1,rows={}}
    function lease.release()
        lease.count=lease.count-1
        if lease.count>0 then return end
        leases[d]=nil
        local firstError
        for _,record in ipairs(lease.rows) do
            local ok,why=pcall(function()
                local row=alive(record.entry) and record.entry.object:FindRow(d.row)
                if row then
                    for i=1,3 do
                        local key='SpWeaponID'..i
                        if row[key]==record.target[i] then row[key]=(d.catalog or d.original)[i] end
                    end
                    ammo.restore(record,row)
                end
            end)
            if not ok then firstError=firstError or why end
        end
        if firstError then error(firstError) end
    end
    leases[d]=lease
    local ok,why=pcall(function()
        for _,e in pairs(tracked) do
            if e.definition==d and alive(e) then
                includeRow(lease,d,e)
            end
        end
    end)
    if not ok then lease.release();error(why) end
    return lease.release
end
local function borrowMissionLoadout(d)
    -- Only begin the longer lease once a prepared parameter table exists.
    for _,entry in pairs(tracked) do
        if entry.definition==d and entry.done and alive(entry) then return borrowLoadout(d) end
    end
end
local endMissionLoadout=dofile(dir.."beginplay.lua")(defs,mounts,log,borrowLoadout,borrowMissionLoadout,missionSp,availableSelection)
local function restore()
    mounts.restore()
    for _,e in pairs(tracked) do restoreEntry(e) end
end
local function apply(e)
    local d=e.definition
    -- Asset loading may release/recreate an earlier table. Never carry its row
    -- across that boundary, and reject entries replaced by a fresh notification.
    local prepared=mounts.resolve(d)
    assert(alive(e) and tracked[e.object:GetAddress()]==e,
        'Aircraft parameter table changed during asset preparation: '..d.code)
    local row=e.object:FindRow(d.row)
    assert(row,"Aircraft row unavailable: "..d.code)
    for i=1,3 do
        assert(row['SpWeaponID'..i]==d.original[i],"Original SP weapon mismatch: "..d.code.." slot "..i)
    end
    mounts.prepare(d,nil,prepared)
    if d.catalog then
        e.catalogApplied=true
        for i=1,3 do
            if d.catalog[i]~=d.original[i] then row['SpWeaponID'..i]=d.catalog[i] end
        end
    end
    if leases[d] then includeRow(leases[d],d,e) end
    e.done=true
    if d.target[1]~=d.original[1] or d.target[2]~=d.original[2] or d.target[3]~=d.original[3] then
        log("VERIFIED "..d.section.." = "..table.concat({
            weaponNames[d.target[1]],weaponNames[d.target[2]],weaponNames[d.target[3]]},", "))
    end
end

-- Called every frame by the menu loop, so online play is still detected on the
-- next frame. The full identity check (GetFullName builds a path string) runs on
-- every 30th call per controller; other calls check validity before the world.
local function menuOnline()
    for id,e in pairs(controllers) do
        e.checks=(e.checks or 0)-1
        local live
        if e.checks<=0 then e.checks=30;live=alive(e) else live=valid(e.object) end
        if not live then controllers[id]=nil
        else local w=e.object:GetWorld();if valid(w) and valid(w.NetDriver) then return true end end
    end
    return false
end
local function menuApply(d,target)
    assert(not menuOnline(),'Online play is not supported')
    if d.additions then endMissionLoadout() end
    local entries={}
    local function collect()
        for id,e in pairs(tracked) do
            if not alive(e) then tracked[id]=nil
            elseif e.definition==d then entries[#entries+1]=e end
        end
    end
    collect()
    if #entries==0 then
        for _,dt in ipairs(FindAllOf('DataTable') or {}) do remember(dt) end
        collect()
    end
    assert(#entries>0,'Aircraft parameter table is not loaded')
    local previous=d.target
    local unchanged=true
    for i=1,3 do if target[i]~=previous[i] then unchanged=false;break end end
    if unchanged then
        for _,e in ipairs(entries) do
            if not e.done then unchanged=false;break end
            local row=e.object:FindRow(d.row)
            if not row then unchanged=false;break end
            for i=1,3 do if row['SpWeaponID'..i]~=(d.catalog or d.original)[i] then unchanged=false;break end end
            if not unchanged then break end
        end
    end
    if unchanged then return function()end,updateOwnership end
    local function switch(ids)
        -- Preview loading/GC may release a no-longer-equipped original class.
        -- Refresh exact saved identities before restore borrows config rows.
        mounts.prepareRestore(d.code)
        -- Restoration preparation can load assets and replace parameter tables.
        -- Recollect current entries before touching any saved table state.
        entries={};collect()
        assert(#entries>0,'Aircraft parameter table changed during restoration preparation')
        mounts.restore(d.code)
        for _,e in ipairs(entries) do restoreEntry(e) end
        d.target=ids
        for _,e in ipairs(entries) do apply(e) end
    end
    local ok,err=pcall(switch,target)
    if not ok then
        local restored,why=pcall(switch,previous)
        if not restored then log('MENU restore failed: '..tostring(why)) end
        error(err)
    end
    return function()switch(previous)end,updateOwnership
end
local resupply=dofile(dir..'resupply.lua')(mounts,mountPaths,log)
menuApply=resupply.wrap(menuApply,function(d)
    local found
    for id,e in pairs(controllers) do
        if not alive(e) then controllers[id]=nil
        else
            local actor=e.object.Pawn
            if resupply.playerMatches(d,actor) then
                if found and found:GetAddress()~=actor:GetAddress() then return nil end
                found=actor
            end
        end
    end
    return found
end)
-- Personal build only: optional two-model display (pair_models.lua plus
-- PairModels.ini). Absent or disabled, every path below is the standard one.
local pairDisplay=nil
do
    local present=io.open(dir.."pair_models.lua","rb")
    if present then
        present:close()
        local ok,result=pcall(function()return dofile(dir.."pair_models.lua")(defs,log)end)
        if ok then pairDisplay=result else log("PAIR unavailable; standard 2.6 behaviour: "..tostring(result)) end
    end
end
log("STAGE initialize hangar preview")
local previewOK,applyPreview,cancelPreview=pcall(function()return dofile(dir.."preview.lua")(defs,mounts,log,pairDisplay,pods)end)
if not previewOK then
    log('Preview unavailable; weapon menu remains active: '..tostring(applyPreview))
    applyPreview=function()end;cancelPreview=nil
end
log("STAGE initialize native menu")
local menuOK,menuError=pcall(menuRuntime.start,menuApply,menuOnline,applyPreview,cancelPreview,borrowLoadout,missionSp.confirm)
if not menuOK then log('STATUS native-menu=disabled: '..tostring(menuError))
else log('STATUS native-menu=active preview='..(previewOK and 'active' or 'unavailable')) end

NotifyOnNewObject("/Script/Engine.DataTable",function(dt)
    ExecuteInGameThread(function()remember(dt,true)end)
end)
NotifyOnNewObject("/Script/Engine.PlayerController",function(pc)
    ExecuteInGameThread(function()rememberController(pc)end)
end)
ExecuteInGameThread(function()
    log("STAGE initial table/controller discovery begin")
    for _,dt in ipairs(FindAllOf("DataTable") or {}) do remember(dt) end
    for _,pc in ipairs(FindAllOf("PlayerController") or {}) do rememberController(pc) end
    log("STAGE initial table/controller discovery complete")
end)
local maintenanceTicks=0
local livenessPasses=0
local diagnosticSnapshotPending=true
LoopInGameThreadAfterFrames(30,function()
    if diagnosticSnapshotPending then diagnosticSnapshotPending=false;diagnostics.snapshot();log("STAGE first scheduled maintenance callback reached") end
    local online=menuOnline()
    if online then
        if not network then endMissionLoadout();pods.flight(nil,nil);pods.clear();restore();network=true end
        return
    end
    network=false
    local pawn,pawnDefinition
    local podOK,podError=pcall(function()
        for _,entry in pairs(controllers) do
            local candidate=entry.object.Pawn
            if valid(candidate) then
                local definition=podAircraft[candidate:GetClass():GetFName():ToString()]
                if definition then pawn,pawnDefinition=candidate,definition;break end
            end
        end
        pods.flight(pawn,pawnDefinition)
    end)
    if not podOK and not pods.warned then pods.warned=true;log('POD flight: '..tostring(podError)) end
    local missionOK,missionError=pcall(missionSp.observe,pawn,pawnDefinition)
    if not missionOK and not missionSp.warned then
        missionSp.warned=true
        log('MISSION SP observe failed: '..tostring(missionError))
    end
    maintenanceTicks=maintenanceTicks+1
    if maintenanceTicks>=10 then maintenanceTicks=0;mounts.prune() end
    updateOwnership(false)
    -- Applied tables are rechecked for liveness on every tenth pass only; menu
    -- apply and restore recheck each entry's identity before touching it.
    livenessPasses=livenessPasses+1
    local fullPass=livenessPasses>=10
    if fullPass then livenessPasses=0 end
    for id,e in pairs(tracked) do
        if e.done and not fullPass then
            -- settled; nothing to do this pass
        elseif not alive(e) then tracked[id]=nil
        elseif not e.done and e.attempts<300 then
            e.attempts=e.attempts+1
            local ok,err=pcall(apply,e)
            if not ok then
                local attempts=e.attempts
                restoreEntry(e)
                e.attempts=attempts
                if attempts==1 or attempts==300 then log("APPLY "..attempts.."/300 "..e.definition.section..": "..tostring(err)) end
            end
        end
    end
end)
if menuOK then log("Ready SPWeaponCustomizer 2.6: in-game weapon selection, model preferences and replacement ammunition")
else log("SPWeaponCustomizer 2.6 initialized with native menu DISABLED; inspect native/native-menu.log") end
log("Optimized runtime active: one-time preview initialization and guarded cached data")
log("BUILD "..build.id..": exact original-class refresh before menu restore; staged previews and bounded diagnostics retained")
