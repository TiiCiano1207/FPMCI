-- Add only configured replacements whose original slot weapon is already owned.
-- Originals are retained. These additions may be persisted by the game's autosave.
return function(defs,planeIDs,log)
    -- Bounds reject malformed data without hardcoding the vanilla aircraft count.
    local MAX_AIRCRAFT_RECORDS=512
    local MAX_OWNED_WEAPONS=128
    -- main.lua calls scheduled updates every 30 frames. Confirmed menu/preset
    -- changes call update() without false and always run immediately.
    local FALLBACK_CHECKS=10 -- 300 frames between settled save traversals
    local EMPTY_FAST_CHECKS=10 -- finite startup grace for unpopulated save data
    local tick=0
    local byCode={};local byPlane={};local saves={}
    for _,d in ipairs(defs.aircraft) do
        byCode[d.code]=d
    end
    for id,code in pairs(planeIDs) do if byCode[code] then byPlane[id]=byCode[code] end end
    if next(byPlane)==nil then return function()end end
    local function identity(o)
        local ok,name=pcall(function()if o and o:IsValid() then return o:GetFullName()end end)
        return ok and name or nil
    end
    local function changed(d)
        for i=1,3 do if d.target[i]~=d.original[i] then return true end end
        return false
    end
    local function checkedCount(array,limit,label)
        local count=array:GetArrayNum()
        assert(type(count)=='number' and count>=0 and count%1==0 and count<=limit,
            'Unexpected '..label..' count')
        return count
    end
    local function readItem(array,index,count,limit,label)
        -- UE4SS indexed reads can grow an array when out of bounds. Check first.
        assert(index>=1 and index<=count,'Invalid '..label..' index')
        assert(checkedCount(array,limit,label)==count,label..' changed during ownership update')
        return array[index]
    end
    local function remember(o,fresh)
        local name=identity(o)
        if name and not name:find('Default__',1,true) then
            local id=o:GetAddress()
            if fresh or not saves[id] or saves[id].name~=name then saves[id]={object=o,name=name,failures=0,nextCheck=0,emptyChecks=0} end
        end
    end
    NotifyOnNewObject('/Script/Live.LiveCampaignSaveGame',function(o)
        ExecuteInGameThread(function()remember(o,true)end)
    end)
    ExecuteInGameThread(function()
        for _,o in ipairs(FindAllOf('LiveCampaignSaveGame') or {}) do remember(o) end
    end)
    local function apply(e)
        -- Keep parent/array wrappers local throughout this synchronous operation.
        -- Indexed access returns values directly; no callback parameter or :get().
        local campaign=e.object.CampaignSaveData
        local records=campaign.AircraftTypeRecords
        local recordCount=checkedCount(records,MAX_AIRCRAFT_RECORDS,'AircraftTypeRecords')
        for recordIndex=1,recordCount do
            local row=readItem(records,recordIndex,recordCount,MAX_AIRCRAFT_RECORDS,'AircraftTypeRecords')
            local d=byPlane[row.PlaneID]
            if d and changed(d) then
                local array=row.OwnedWeapons;local owned={};local pending={};local vanilla={}
                local count=checkedCount(array,MAX_OWNED_WEAPONS,'OwnedWeapons')
                for _,id in ipairs(d.original) do vanilla[id]=true end
                for weaponIndex=1,count do
                    local id=readItem(array,weaponIndex,count,MAX_OWNED_WEAPONS,'OwnedWeapons')
                    assert(type(id)=='number' and id%1==0 and id>=0 and id<=255,'Invalid owned weapon ID')
                    owned[id]=true
                end
                -- Snapshot membership first: one replacement cannot unlock another slot.
                local additions=0
                for i=1,3 do
                    local target=d.target[i]
                    local paid=owned[d.original[i]]
                    if i==d.legacySlot then
                        for _,id in ipairs(d.legacyLoadoutIDs) do paid=paid or owned[id] end
                    end
                    if target~=d.original[i] and paid and not owned[target] and not vanilla[target]
                        and not pending[target] then
                        pending[target]=true;additions=additions+1
                    end
                end
                -- A customization can be saved as equipped even when the campaign
                -- inventory still excludes it. Mirror the paid physical slot for
                -- the Su-35 pod without changing the aircraft's catalog entries.
                if d.podID and not owned[d.podID] and not pending[d.podID] then
                    for i,id in ipairs(d.loadout.target) do
                        if id==d.podID and (owned[d.original[i]] or owned[d.target[i]]) then
                            pending[id]=true
                            additions=additions+1
                            break
                        end
                    end
                end
                assert(count+additions<=MAX_OWNED_WEAPONS,'Unexpected owned weapon count')
                for target in pairs(pending) do
                    assert(identity(e.object)==e.name,'Campaign save changed before ownership append')
                    assert(checkedCount(array,MAX_OWNED_WEAPONS,'OwnedWeapons')==count,
                        'OwnedWeapons changed before ownership append')
                    array[count+1]=target
                    count=count+1
                    assert(checkedCount(array,MAX_OWNED_WEAPONS,'OwnedWeapons')==count
                        and readItem(array,count,count,MAX_OWNED_WEAPONS,'OwnedWeapons')==target,
                        'OwnedWeapons append readback failed')
                    log('OWNERSHIP '..d.section..' PlaneID='..row.PlaneID..' added='..target..' (original weapons retained)')
                end
            end
        end
        return recordCount
    end
    log('OWNERSHIP scheduler active (2.6): immediate confirmations; new saves checked on next maintenance; settled fallback every 300 frames')
    return function(force)
        -- Preserve the existing no-argument afterCommit callback contract.
        -- Only background callbacks advance the frame-based fallback clock.
        if force==false then tick=tick+1 end
        local active=false
        for _,d in pairs(byCode) do if changed(d) then active=true;break end end
        for id,e in pairs(saves) do
            if force~=false or tick>=e.nextCheck then
                e.nextCheck=tick+FALLBACK_CHECKS
                if identity(e.object)~=e.name then saves[id]=nil
                elseif active and e.failures<3 then
                    local ok,count=pcall(apply,e)
                    if not ok then
                        e.failures=e.failures+1
                        if e.failures<3 then e.nextCheck=tick+1 end
                        log('OWNERSHIP failed '..e.failures..'/3: '..tostring(count))
                    else
                        e.failures=0
                        if count==0 then
                            e.emptyChecks=e.emptyChecks+1
                            if e.emptyChecks<EMPTY_FAST_CHECKS then e.nextCheck=tick+1 end
                        else e.emptyChecks=0 end
                    end
                end
            end
        end
    end
end
