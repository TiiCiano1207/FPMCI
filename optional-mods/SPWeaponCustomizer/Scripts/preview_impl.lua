-- Hangar-only visual mesh update. Selection IDs are restored by the native bridge.
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
-- pairDisplay (personal build, optional): keeps two display components and
-- their scale for replacement TLS/EMLB/IEWS/MPBM. nil = standard preview.
return function(defs,mounts,log,actors,pairDisplay,pods)
    local readArray=dofile(dir..'array_reader.lua')
    local assetPaths=dofile(dir..'preview_assets.lua')
    -- Mirrors native previewRackPlanes: audited aircraft with sockets for all
    -- three rack groups. Others keep the original two-slot preview.
    local groupedAircraft={}
    for _,code in ipairs({'PP0001_a10c','PP0002_f02a','PP0003_f04e','PP0004_f15c','PP0005_f22a','PP0006_f35c',
        'PP0007_f18c','PP0008_j39e','PP0009_su34','PP0011_typn','PP0012_f15j','PP0013_a06e','PP0014_rflm',
        'PP0015_su25','PP0017_mr2k','PP0018_fa36','PP0020_m29a','PP0021_su57','PP0022_f16c','PP0023_f14d',
        'PP0024_f18f','PP0025_f15e','PP0026_su47','PP0027_m21b','PP0028_su35','PP0029_m31b','PP0030_su33',
        'PP0032_f18e','PP0034_f14a'}) do groupedAircraft[code]=true end
    local weaponNames={};for key,id in pairs(defs.weapons) do weaponNames[id]=key:lower() end
    local assetCache={};local generation=0;local activeRequest
    local missingWarned={}
    local componentClass
    local stats={requests=0,cancelled=0,completed=0,cold=0,hits=0,clockMs=0,maxClockMs=0,scans=0}
    local coldReports,slowReports,summaryReports=0,0,0
    -- os.clock is diagnostic only: it is not a GPU/frame-time measurement.
    local function clock()return os.clock()end
    local function report(request,reason)
        stats.completed=stats.completed+1
        stats.scans=stats.scans+request.scans
        if summaryReports<24 and (stats.completed<=4 or stats.completed%32==0) then
            summaryReports=summaryReports+1
            log(string.format('PREVIEW summary completed=%d cancelled=%d cold=%d hits=%d clock=lua-os.clock total_ms=%.3f max_ms=%.3f scans=%d last_scans=%d last_updates=%d end=%s',
                stats.completed,stats.cancelled,stats.cold,stats.hits,stats.clockMs,stats.maxClockMs,
                stats.scans,request.scans,request.updates,reason))
        end
    end
    -- These weapons retain their gameplay functionality but have no custom
    -- standalone preview. Their native models are combined with aircraft pylons.
    local noPreview={[20]=true,[34]=true,[40]=true} -- MGP, ESM, ECM
    local function valid(o)
        local ok,value=pcall(function()return o and o:IsValid()end)
        return ok and value
    end
    local function name(o)
        if not valid(o) then return nil end
        local ok,value=pcall(function()return o:GetFullName()end)
        return ok and value or nil
    end
    local function field(o,key)
        local ok,value=pcall(function()return o[key]end)
        return ok and value or nil
    end
    local function unwrap(value)
        if valid(value) then return value end
        local ok,result=pcall(function()return value:get()end)
        return ok and result or nil
    end
    local function asset(d,id)
        if not id or id==0 then return nil end
        local key=(d.model or 'US')..':'..id
        local cached=assetCache[key]
        if cached and name(cached.object)==cached.name then return cached.object,true end
        -- Keep the established class/CDO initialization order. Loading only a
        -- mesh is not equivalent to preparing its owning weapon blueprint.
        local cls,path=mounts.previewClass(d,id)
        local cdo=cls:GetCDO()
        local mesh=field(field(cdo,'StaticMesh'),'StaticMesh')
        local function mapped(path)
            local key=path and path:match('([^/]+)$'):lower()
            local objectPath=key and assetPaths[key]
            if key and not objectPath then
                local weapon,suffix=key:match('^bp_plwp_(%w+)_(%w+)$')
                local proxy=({hpaa='qaam',hvaa='saam',hcaa='4aam',['2aam']='4aam',['6aam']='4aam',['8aam']='4aam'})[weapon]
                if proxy then objectPath=assetPaths['bp_plwp_'..proxy..'_'..suffix] or assetPaths['bp_plwp_'..proxy..'_a0'] end
            end
            if objectPath then
                local expected=('StaticMesh '..objectPath):lower()
                log('ASSET preview request '..objectPath..' via=registry')
                local found=LoadAsset(objectPath)
                if (name(found) or ''):lower()==expected then return found end
            end
        end
        if not (name(mesh) or ''):match('^StaticMesh ') then mesh=mapped(path) end
        assert((name(mesh) or ''):match('^StaticMesh '),'No verified static preview mesh for weapon '..id)
        assetCache[key]={object=mesh,name=name(mesh)}
        return mesh,false
    end
    local function resolve(d,id)
        if not id or id==0 or noPreview[id] then return nil,false end
        local started=clock()
        local ok,mesh,hit=pcall(asset,d,id)
        local elapsed=math.max(0,(clock()-started)*1000)
        stats.clockMs=stats.clockMs+elapsed
        stats.maxClockMs=math.max(stats.maxClockMs,elapsed)
        if ok and hit then stats.hits=stats.hits+1 else stats.cold=stats.cold+1 end
        local coldReport,slowReport=not hit and coldReports<8,elapsed>=25 and slowReports<8
        if coldReport or slowReport then
            if coldReport then coldReports=coldReports+1 end
            if slowReport then slowReports=slowReports+1 end
            log(string.format('PREVIEW prepare weapon=%d cache=%s ok=%s clock=lua-os.clock duration_ms=%.3f',
                id,hit and 'hit' or 'miss',tostring(ok),elapsed))
        end
        if ok then return mesh,not hit end
        local key=d.code..':'..d.model..':'..id
        if not missingWarned[key] then
            missingWarned[key]=true
            log('PREVIEW mesh unavailable; clearing weapon '..id..': '..tostring(mesh))
        end
        return nil,true
    end
    local function each(array,callback)
        if not array then return end
        if type(array)=='table' then
            for i,value in pairs(array) do callback(i,unwrap(value)) end
        else
            readArray(array,256,'preview native mesh cache',function(i,value)callback(i,unwrap(value))end)
        end
    end
    local function nativeMeshes(actor,grouped)
        local bySlot,byName,main={},{},{}
        -- Read the renderer's real original meshes. Weapon names are not model
        -- names: F-35C HCAA, for example, uses the 4AAM model.
        each(field(actor,'WeaponMeshAssetsCache'),function(i,mesh)
            local full=name(mesh)
            if type(i)=='number' and i>=1 and i<=(grouped and 3 or 2) and full then
                bySlot[i]=mesh
                if byName[full] then byName[full]=false else byName[full]=i end
            end
        end)
        each(field(actor,'MainWeaponMeshList'),function(_,component)
            if valid(component) then main[component:GetAddress()]=true end
        end)
        return bySlot,byName,main
    end
    local function componentSlot(c,current,d,byName,main,grouped)
        if main[c:GetAddress()] then return nil end
        local full=name(current) or ''
        if full~='' and not full:lower():find('staticmesh /game/vehicles/weapons/w_',1,true) then return nil end
        local ok,socket=pcall(function()return c:GetAttachSocketName():ToString():lower()end)
        if ok and socket:find('msl',1,true) then return nil end
        local slot=ok and tonumber(socket:match(grouped and '^soc_swp_([123])%d+$' or '^soc_swp_([12])%d+$')) or nil
        if slot then return slot end
        if full=='' then return nil end
        if byName[full] then return byName[full] end
        -- Older/custom display actors may not expose the populated cache yet.
        -- Retain the old name fallback only while no native cache is available.
        if next(byName)==nil then
            for i=1,(grouped and 3 or 2) do
                local key=weaponNames[d.original[i]]
                if key and full:lower():find('/w_'..key..'_',1,true) then return i end
            end
        end
    end
    local pairSeen,pairReports={},0
    local function pairReport(s)
        if pairSeen[s] or pairReports>=64 then return end
        pairSeen[s]=true;pairReports=pairReports+1;log('PREVIEW '..s)
    end
    -- Personal pair display: native decides (same function, scale and roll as
    -- the mission) and applies scale/roll; here only the model is kept or cleared.
    local function pairPlan(d,cache,wanted,meshes,request)
        if not pairDisplay or not pairDisplay.active() then return nil end
        local items={}
        for _,entry in ipairs(cache.items) do
            if name(entry.object)==entry.name then
                local o=entry.original
                local slot=request.groupSlots and request.groupSlots[o.slot] or (not request.groupSlots and o.slot or nil)
                local id=slot and wanted[slot] or 0
                if id~=0 and not valid(meshes[slot]) then id=0 end
                items[#items+1]={address=entry.object:GetAddress(),group=o.slot,id=id}
            end
        end
        local ok,result=pcall(pairDisplay.plan,d.code,items)
        if not ok then pairReport('pair plan failed; standard preview shown: '..tostring(result));return nil end
        return result
    end
    local function update(d,first,second,meshes,meshNames,request,forceScan)
        local wanted={first,second}
        if name(componentClass)~='Class /Script/Engine.StaticMeshComponent' then
            componentClass=StaticFindObject('/Script/Engine.StaticMeshComponent')
        end
        local cls=componentClass
        assert(valid(cls),'Static mesh component class unavailable')
        for i=1,2 do if name(meshes[i])~=meshNames[i] then meshes[i]=nil end end
        local matched,changed=0,0
        for key,e in pairs(actors) do
            if activeRequest~=request or request.serial~=generation then return matched,changed end
            if name(e.object)~=e.name then actors[key]=nil
            else
                local row=field(field(e.object,'HangarPlaneDataHandle'),'RowName')
                local ok,code=pcall(function()return row:ToString()end)
                if ok and code==d.code then
                    e.originalMeshes=e.originalMeshes or {}
                    local cache=request.components[key]
                    local scan=forceScan or not cache or cache.owner~=e
                    if not scan then
                        for _,entry in ipairs(cache.items) do
                            if name(entry.object)~=entry.name then scan=true;break end
                        end
                        if #cache.items==0 then scan=true end
                    end
                    if scan then
                        local native,byName,main=nativeMeshes(e.object,request.groupSlots)
                        local components=e.object:K2_GetComponentsByClass(cls)
                        request.scans=request.scans+1
                        cache={owner=e,items={}}
                        for _,entry in pairs(components) do
                            local c=unwrap(entry)
                            local cn=name(c)
                            if cn and not (pods and pods.owned(c)) then
                                local ck=c:GetAddress()
                                local original=e.originalMeshes[ck]
                                if original and original.name~=cn then original=nil end
                                local current=field(c,'StaticMesh')
                                if not original then
                                    local slot=componentSlot(c,current,d,byName,main,request.groupSlots)
                                    if slot then
                                        local baseline=native[slot] or current
                                        original={name=cn,mesh=baseline,meshName=name(baseline),slot=slot}
                                        e.originalMeshes[ck]=original
                                    end
                                end
                                if original then cache.items[#cache.items+1]={object=c,name=cn,original=original} end
                            end
                        end
                        request.components[key]=cache
                    end
                    local podRacks,occupied={},{}
                    local podSlot=first==20 and 1 or (second==20 and 2 or nil)
                    local other=podSlot and (3-podSlot)
                    local pairRacks,podSockets,unusedGroup
                    local physicalPod,carrier,activeGroups
                    if pods and podSlot then
                        local slotGroups=request.groupSlots or {[1]=1,[2]=2}
                        for group,slot in pairs(slotGroups) do
                            if slot==podSlot then physicalPod=group end
                        end
                        local visualGroups={}
                        for group,slot in pairs(slotGroups) do visualGroups[group]=slot end
                        for group=1,3 do
                            if not slotGroups[group] and d.original[group]~=22 then unusedGroup=group end
                        end
                        -- A rocket station has one socket per projectile inside the pod.
                        -- Use the spare missile station for the replacement model.
                        for group,slot in pairs(slotGroups) do
                            if unusedGroup and d.original[group]==22 and wanted[slot]~=22 then
                                visualGroups[group]=nil;visualGroups[unusedGroup]=slot
                                break
                            end
                        end
                        if request.groupSlots and d.original[physicalPod]~=20 then
                            local mask=0
                            for group,slot in pairs(visualGroups) do
                                if wanted[slot] and wanted[slot]~=0 then mask=mask | (1<<(group-1)) end
                            end
                            carrier=pods.selectCarrier(e.object,mask)
                            if carrier then
                                activeGroups=visualGroups
                            else
                                local nativeMask=0
                                for group in pairs(slotGroups) do nativeMask=nativeMask | (1<<(group-1)) end
                                pods.usePylon(e.object,nativeMask,mask)
                            end
                        end
                        if unusedGroup and not visualGroups[unusedGroup] then visualGroups[unusedGroup]=3 end
                        local racks=pods.pairedRacks(e.object,visualGroups,cache.items,carrier)
                        podSockets=racks[podSlot]
                        for _,spare in ipairs(racks[3]) do
                            spare.spare=true
                            podSockets[#podSockets+1]=spare
                        end
                        if (wanted[other]==5 or wanted[other]==14) and valid(meshes[other]) and #racks[other]>0 then pairRacks=racks end
                    end
                    local plan=pairPlan(d,cache,wanted,meshes,request)
                    for _,entry in ipairs(cache.items) do
                        if activeRequest~=request or request.serial~=generation then return matched,changed end
                        local c,original=entry.object,entry.original
                        -- No component references are used until asset preparation is over.
                        if name(c)==entry.name and (not carrier or name(c:GetAttachParent())==name(carrier)) then
                            matched=matched+1
                            local mapping=activeGroups or request.groupSlots
                            local slot=mapping and mapping[original.slot] or (not mapping and original.slot or nil)
                            local to=slot and meshes[slot] or nil
                            if not slot or not wanted[slot] or wanted[slot]==0 or (slot==podSlot and d.original[original.slot]==20) then
                                to=name(original.mesh)==original.meshName and original.mesh or nil
                            end
                            if podSlot and request.groupSlots and not slot then to=nil end
                            if pairRacks and slot==other then to=nil end
                            if not valid(to) then to=nil end
                            if plan and to and plan[c:GetAddress()]=='D' then to=nil end
                            if name(field(c,'StaticMesh'))~=name(to) then
                                assert(c:SetStaticMesh(to)~=false,'Preview mesh assignment declined')
                                assert(name(c.StaticMesh)==name(to),'Preview mesh readback failed')
                                changed=changed+1
                            end
                            if slot and wanted[slot]==20 and d.original[original.slot]~=20 then
                                podRacks[#podRacks+1]={parent=c,socket=FName('None')}
                            elseif valid(to) and field(c,'bHiddenInGame')~=true and field(c,'bVisible')~=false then
                                occupied[#occupied+1]={parent=c,socket=FName('None'),mesh=to}
                            end
                        end
                    end
                    if pods then
                        if physicalPod and d.original[physicalPod]~=20 and podSockets and #podSockets>0 then podRacks=podSockets end
                        if pairRacks then
                            for _,item in ipairs(pods.companion(e.object,meshes[other],wanted[other],pairRacks[other],carrier~=nil)) do
                                occupied[#occupied+1]=item
                            end
                        end
                        if #podRacks>0 then
                            each(field(e.object,'MainWeaponMeshList'),function(_,part)
                                local mesh=field(part,'StaticMesh')
                                if valid(mesh) and field(part,'bHiddenInGame')~=true and field(part,'bVisible')~=false then
                                    occupied[#occupied+1]={parent=part,socket=FName('None'),mesh=mesh}
                                end
                            end)
                        end
                        pods.layout('hangar',e.object,d,podRacks,occupied)
                    end
                end
            end
        end
        return matched,changed
    end
    local function cancel()
        if pods then pods.clear("hangar");pods.clear("companion") end
        generation=generation+1
        if activeRequest then
            stats.cancelled=stats.cancelled+1
            if activeRequest.timer then CancelDelayedAction(activeRequest.timer) end
            activeRequest.components={};activeRequest.meshes={};activeRequest.names={}
            activeRequest=nil
        end
    end
    -- Personal pair display only: after a confirmed or hovered selection the
    -- game may re-render the loadout on the hangar display (the menu after
    -- weapon selection), restoring models the pair plan dropped (a replacement
    -- MPBM with more than two native mounts). Re-apply the same plan in a short
    -- bounded window; any new preview request cancels it.
    local settleReports=0
    local function settle(d,first,second,meshes,names,groupSlots)
        if first~=20 and second~=20 and (not pairDisplay or not pairDisplay.active()) then return end
        local w={serial=generation,components={},scans=0,updates=0,settle=true,groupSlots=groupSlots}
        activeRequest=w
        local checks,restored=0,0
        local function finish(reason)
            if w.timer then CancelDelayedAction(w.timer);w.timer=nil end
            if activeRequest==w then activeRequest=nil end
            w.components={}
            if restored>0 and settleReports<16 then
                settleReports=settleReports+1
                log(string.format('PREVIEW pair settle %s: hangar re-render restored %d model(s); pair plan re-applied (checks=%d end=%s)',d.code,restored,checks,reason))
            end
        end
        w.timer=LoopInGameThreadAfterFrames(20,function()
            if activeRequest~=w or w.serial~=generation then return end
            checks=checks+1
            local ok,matched,changed=pcall(update,d,first,second,{meshes[1],meshes[2]},names,w,checks%3==1)
            if not ok then log('PREVIEW pair settle stopped: '..tostring(matched));finish('error');return end
            restored=restored+changed
            if checks>=12 then finish('window') end
        end)
    end
    local function hasDisplayPlane(d)
        for key,e in pairs(actors) do
            if name(e.object)~=e.name then actors[key]=nil
            else
                local row=field(field(e.object,'HangarPlaneDataHandle'),'RowName')
                local ok,code=pcall(function()return row:ToString()end)
                if ok and code==d.code then return true end
            end
        end
        return false
    end
    local function apply(d,id,slot,first,second,groupFirst,groupSecond)
        local groupSlots
        if groupFirst~=nil or groupSecond~=nil then
            assert(groupedAircraft[d.code],'Unexpected paired preview aircraft')
            assert(type(groupFirst)=='number' and groupFirst%1==0 and groupFirst>=1 and groupFirst<=3,'Invalid SP1 preview group')
            assert(type(groupSecond)=='number' and groupSecond%1==0 and groupSecond>=0 and groupSecond<=3,'Invalid SP2 preview group')
            assert((second==0 and groupSecond==0) or (second~=0 and groupSecond~=0 and groupSecond~=groupFirst),'Invalid paired preview groups')
            groupSlots={[groupFirst]=1};if groupSecond~=0 then groupSlots[groupSecond]=2 end
        end
        cancel()
        local request={serial=generation,components={},scans=0,updates=0,ticks=0,
            meshes={},names={},prepared={},attempts={},settled=0,groupSlots=groupSlots}
        activeRequest=request;stats.requests=stats.requests+1
        local wanted={first,second}
        local function current()return activeRequest==request and request.serial==generation end
        local function stop(reason)
            if not current() then return end
            if request.timer then CancelDelayedAction(request.timer);request.timer=nil end
            activeRequest=nil
            request.components={};request.meshes={};request.names={}
            report(request,reason)
        end
        local function prepare()
            -- At most one uncached weapon preparation per callback. A single
            -- synchronous engine load is still allowed to take its usual time.
            for i=1,2 do
                if not request.prepared[i] then
                    request.attempts[i]=(request.attempts[i] or 0)+1
                    assert(request.attempts[i]<=3,'Preview assets changed repeatedly during preparation')
                    local mesh,cold=resolve(d,wanted[i])
                    if not current() then return false end
                    request.meshes[i]=mesh;request.names[i]=name(mesh);request.prepared[i]=true
                    if cold and i<2 and not request.prepared[2] then return false end
                end
            end
            -- A later load may invalidate an earlier mesh. Reacquire it on a
            -- subsequent callback, never after borrowing display components.
            for i=1,2 do
                if request.meshes[i] and name(request.meshes[i])~=request.names[i] then
                    request.prepared[i]=false;request.meshes[i]=nil;return false
                end
            end
            return true
        end
        local function finalCheck()
            if not current() then return end
            local ok,err=pcall(function()
                if hasDisplayPlane(d) then
                    request.updates=request.updates+1
                    update(d,first,second,request.meshes,request.names,request,true)
                end
            end)
            if not ok then log('PREVIEW final check stopped: '..tostring(err)) end
            local meshes,names,groupSlots={request.meshes[1],request.meshes[2]},{request.names[1],request.names[2]},request.groupSlots
            stop(ok and 'final-check' or 'error')
            if ok then settle(d,first,second,meshes,names,groupSlots) end
        end
        request.timer=LoopInGameThreadAfterFrames(3,function()
            if not current() then return end
            request.ticks=request.ticks+1
            if request.ticks<2 then return end -- preserve six quiet frames
            local ok,err=pcall(function()
                if not hasDisplayPlane(d) then
                    if request.ticks>=7 then stop('no-display') end
                    return
                end
                if not prepare() or not current() then return end
                request.updates=request.updates+1
                local matched,changed=update(d,first,second,request.meshes,request.names,request,false)
                if not current() then return end
                if matched>0 and changed==0 then request.settled=request.settled+1 else request.settled=0 end
                if request.updates>=6 then stop('retry-window')
                elseif request.settled>=1 and request.updates>=2 then
                    -- Stop dense updates once stable. One final fresh discovery
                    -- keeps the original six-pass window for late components.
                    CancelDelayedAction(request.timer)
                    request.timer=LoopInGameThreadAfterFrames((6-request.updates)*3,finalCheck)
                end
            end)
            if not ok and current() then
                log('PREVIEW retry stopped: '..tostring(err));stop('error')
            elseif current() and request.ticks>=14 then
                stop('preparation-limit')
            end
        end)
    end
    log('PREVIEW staged loader active (2.6): six quiet frames; one cold weapon preparation per callback; settled component cache plus final discovery; timings use lua-os.clock')
    return apply,cancel
end
