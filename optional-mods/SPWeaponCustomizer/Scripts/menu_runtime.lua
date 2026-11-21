return function(dir,defs,paths,log,balance)
    local build=dofile(dir..'build.lua')
    local plan=dofile(dir..'menu_plan.lua')
    local planeIDs=dofile(dir..'plane_ids.lua')
    local byCode={};local allowedByCode={}
    for _,d in ipairs(defs.aircraft) do
        byCode[d.code]=d
        local allowed={}
        for id in pairs(assert(balance.pools[d.code])) do allowed[id]=true end
        -- Older native selections can still contain these IDs. This only
        -- validates requests already issued by the game; it grants no items.
        for _,id in ipairs(d.legacyLoadoutIDs or {}) do allowed[id]=true end
        allowedByCode[d.code]=allowed
    end
    local saved={};local persisted={}
    local statePath=assert(os.getenv('FPMCI_SP_LOADOUT_FILE'),'FPMCI loadout path unavailable')
    local file=io.open(statePath,'r')
    if file then
        for line in file:lines() do
            local code,a,b,c=line:match('^(PP[%w_]+)=(%d+),(%d+),(%d+)$')
            if code and byCode[code] and balance.additions[byCode[code].section] then
                local ids={tonumber(a),tonumber(b),tonumber(c)};local good=true
                local plane=byCode[code]
                if plane.legacySlot then
                    local aliases,used={},{}
                    for _,id in ipairs(plane.legacyLoadoutIDs) do aliases[id]=true end
                    for slot,id in ipairs(ids) do
                        local mapped=aliases[id] and plane.catalog[plane.legacySlot] or id
                        if used[mapped] then ids[slot]=0 else ids[slot]=mapped;used[mapped]=true end
                    end
                    for slot,id in ipairs(ids) do
                        if id==0 then
                            for _,candidate in ipairs(plane.catalog) do
                                if not used[candidate] then ids[slot]=candidate;used[candidate]=true;break end
                            end
                        end
                    end
                end
                for _,id in ipairs(ids) do if not allowedByCode[code][id] then good=false end end
                for slot,id in pairs(byCode[code].nativeSlots or {}) do if ids[slot]~=id then good=false end end
                if ids[1]==ids[2] or ids[1]==ids[3] or ids[2]==ids[3] then good=false end
                if good then byCode[code].target=ids;saved[code]=ids;persisted[code]=ids end
            end
        end
        file:close()
    end
    local restored=0
    for code,ids in pairs(saved) do
        restored=restored+1
        log('LOADOUT restored '..code..' physical-slots='..table.concat(ids,',')..' model='..tostring(byCode[code].model or 'default'))
    end
    log('LOADOUT saved aircraft mappings='..restored)
    local function persist(d)
        local old=persisted[d.code]
        if old and old[1]==d.target[1] and old[2]==d.target[2] and old[3]==d.target[3] then return end
        saved[d.code]={table.unpack(d.target)}
        local temp=statePath..'.tmp';local backup=statePath..'.bak'
        local f=assert(io.open(temp,'w'),'Cannot save menu loadout')
        local wrote,writeError=pcall(function()
            assert(f:write('# Managed by the in-game weapon menu. Do not edit while the game is running.\n'))
            for _,entry in ipairs(defs.aircraft) do
                local ids=saved[entry.code]
                if ids then assert(f:write(entry.code..'='..table.concat(ids,',')..'\n')) end
            end
        end)
        local closed,closeError=f:close()
        if not wrote or not closed then os.remove(temp);error(writeError or closeError or 'Cannot finish menu loadout save') end
        local existing=io.open(statePath,'r')
        if existing then
            existing:close();os.remove(backup)
            assert(os.rename(statePath,backup),'Cannot back up menu loadout')
        end
        local ok,err=os.rename(temp,statePath)
        if not ok then if existing then os.rename(backup,statePath) end;error(err) end
        persisted[d.code]={table.unpack(d.target)}
    end
    local function start(applySelection,isOnline,applyPreview,cancelPreview,borrowLoadout,confirmMission)
        local library=dir..'../native/spwmenu_runtime.dll'
        local function load(name)
            local fn,err=package.loadlib(library,'luaopen_spwmenu_'..name)
            return assert(fn,'Cannot load native export '..name..': '..tostring(err)..'; install the complete 2.6 package')
        end
        assert(load('version26')(true),'Native DLL version mismatch; install the complete SPWeaponCustomizer 2.6 package')
        assert(load(build.export)(true),'Native build mismatch; reinstall the complete SPWeaponCustomizer package')
        log('BUILD Lua/native matched '..build.id)
        local init=load('observer');init()
        local ready=load('ready');assert(ready(true),'Native menu build verification failed')
        local poll,commit,abort=load('poll'),load('commit'),load('abort')
        local enable,disable=load('enable'),load('disable')
        local preview=load('preview')
        local refreshAnchors=load('anchors')
        local orderedPlanes={};for plane in pairs(planeIDs) do orderedPlanes[#orderedPlanes+1]=plane end
        table.sort(orderedPlanes)
        local lastAnchors
        local function publishAnchors(committing)
            local lines={}
            for _,plane in ipairs(orderedPlanes) do
                local d=byCode[planeIDs[plane]]
                if d then
                    local slots=d==committing and d.target or d.catalog or d.original
                    lines[#lines+1]=plane..' '..table.concat(slots,' ')..'\n'
                end
            end
            local text=table.concat(lines)
            if text==lastAnchors then return end
            local f=assert(io.open(dir..'../native/preview-anchors.txt','w'))
            local wrote,writeError=f:write(text)
            local closed,closeError=f:close()
            assert(wrote and closed,writeError or closeError or 'Cannot write preview anchors')
            assert(refreshAnchors(true),'Native preview anchor publication failed')
            lastAnchors=text
        end
        local function syncAnchors(committing)
            local ok,err=pcall(publishAnchors,committing)
            if not ok then log('PREVIEW anchor update skipped; weapon menu remains active: '..tostring(err)) end
            return ok
        end
        syncAnchors()
        local onlineState
        LoopInGameThreadAfterFrames(1,function()
            local online=isOnline()
            if online~=onlineState then
                onlineState=online
                if online then
                    disable()
                    if cancelPreview then pcall(cancelPreview) end
                else enable() end
            end
            if online then return end
            if preview(true) then
                local ok,err=pcall(function()
                    local f=assert(io.open(dir..'../native/preview-request.txt','r'))
                    local value=f:read('*a');f:close()
                    local plane,id,slot,first,second,groupFirst,groupSecond=value:match('^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+)%s*$')
                    if not plane then plane,id,slot,first,second=value:match('^(%d+) (%d+) (%d+) (%d+) (%d+)%s*$') end
                    assert(plane,'Invalid preview request')
                    local d=assert(byCode[planeIDs[tonumber(plane)]],'Unknown preview aircraft')
                    if not balance.additions[d.section] or not allowedByCode[d.code][tonumber(id)] then
                        if cancelPreview then cancelPreview() end
                        return
                    end
                    applyPreview(d,tonumber(id),tonumber(slot),tonumber(first),tonumber(second),tonumber(groupFirst),tonumber(groupSecond))
                end)
                if not ok then log('PREVIEW skipped: '..tostring(err)) end
            end
            if not poll(true) then return end
            local rollback
            local ok,err=pcall(function()
                local f=assert(io.open(dir..'../native/selection-request.txt','r'))
                local text=f:read('*a');f:close()
                local plane,first,second,mode=text:match('^(%d+) (%d+) (%d+) (%d+)%s*$')
                if not plane then plane,first,second=text:match('^(%d+) (%d+) (%d+)%s*$') end
                assert(plane and (mode==nil or mode=='1'),'Invalid native menu request')
                local d=assert(byCode[planeIDs[tonumber(plane)]],'Unknown aircraft')
                -- The native preview reserves catalog stations first. Use that same
                -- layout for Su-35 pod pairs, including after an old saved layout.
                local current=d.target
                if d.code=='PP0028_su35' and (first=='20' or second=='20') then current=d.catalog end
                local target=plan(current,d.catalog or d.original,tonumber(first),tonumber(second),allowedByCode[d.code],d.nativeSlots)
                if not balance.additions[d.section] then
                    assert(commit(true),'Game declined original loadout')
                    if not mode then confirmMission(d,tonumber(first),tonumber(second),tonumber(plane)) end
                    return
                end
                local afterCommit
                rollback,afterCommit=applySelection(d,target,mode=='1' and 'resupply' or nil)
                local release=borrowLoadout(d)
                syncAnchors(d)
                local called,accepted=pcall(commit,true)
                release()
                syncAnchors()
                if not called then error(accepted) end
                if not accepted then error('Game declined confirmation or selection changed') end
                rollback=nil
                if not mode then confirmMission(d,tonumber(first),tonumber(second),tonumber(plane)) end
                if afterCommit then
                    local finished,finishError=pcall(afterCommit)
                    if not finished then log('MENU post-confirm update failed: '..tostring(finishError)) end
                end
                local savedOK,saveError=pcall(persist,d)
                if not savedOK then log('MENU SAVE failed: '..tostring(saveError)) end
                log('MENU APPLIED '..d.section..' SP1='..first..' SP2='..second..' slots='..table.concat(d.target,','))
            end)
            if not ok then
                abort()
                if rollback then local restored,why=pcall(rollback);if not restored then log('MENU ROLLBACK failed: '..tostring(why)) end end
                syncAnchors()
                log('MENU selection rejected: '..tostring(err))
            end
        end)
        log('RESUPPLY using game menu and campaign availability')
        log('SPWeaponCustomizer 2.6 in-game menu connected')
    end
    return {start=start}
end
