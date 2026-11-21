local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
local each=dofile(dir..'array_reader.lua')

return function(podID,log)
    local accepted
    local observed
    local function valid(object)
        return object and object:IsValid()
    end
    local function same(a,b)
        return valid(a) and valid(b) and a:GetAddress()==b:GetAddress()
    end
    local function physicalSlot(d,weapon)
        for i,id in ipairs(d.target) do
            if id==weapon then return i end
        end
    end
    local function isLocalPlayer(pawn,world)
        local instance=world.OwningGameInstance
        if not valid(instance) then return false end
        local players=instance.LocalPlayers
        if not players or players:GetArrayNum()~=1 then return false end
        local controller=players[1].PlayerController
        return valid(controller) and (same(controller.Pawn,pawn) or same(pawn.Controller,controller))
    end
    local function confirm(d,first,second,planeID)
        accepted={first,second,aircraft=d,planeID=planeID}
    end
    local function confirmed(d)
        if accepted and accepted.aircraft==d then return accepted end
    end
    local function recoveryPair(d)
        local pair=confirmed(d)
        if not pair or pair[1]==pair[2] then return end
        if d.code=='PP0028_su35' and (pair[1]==podID or pair[2]==podID) then
            local slot=physicalSlot(d,podID)
            if slot then return pair,slot end
        elseif d.additions and (d.additions[pair[1]] or d.additions[pair[2]])
            and physicalSlot(d,pair[1]) and (pair[2]==0 or physicalSlot(d,pair[2])) then
            return pair
        end
    end
    local function getMission(pawn,d)
        if not d then return end
        local pair,slot=recoveryPair(d)
        local su35Pod=d.code=='PP0028_su35' and physicalSlot(d,podID)
        -- A stock F-4E carrying MGP provides a read-only comparison.
        local stockPod=d.code=='PP0003_f04e' and (pawn.PlaneSpWeaponID1==podID or pawn.PlaneSpWeaponID2==podID)
        if not pair and not su35Pod and not stockPod then return end
        local world=pawn:GetWorld()
        if not valid(world) or valid(world.NetDriver) then return end
        local mission=world:GetFullName():match('%.(PL_Mission[%w_]*)$')
        if mission then return world,mission,pair,slot end
    end
    local function confirmedAircraft()
        if accepted then
            local pair,slot=recoveryPair(accepted.aircraft)
            if pair and not slot then return pair.aircraft,pair end
        end
    end
    local function repair(pawn,d,first,second,pair)
        local ok,why=pcall(function()
            pawn.PlaneSpWeaponID1=pair[1]
            pawn.PlaneSpWeaponID2=pair[2]
            assert(pawn.PlaneSpWeaponID1==pair[1] and pawn.PlaneSpWeaponID2==pair[2],
                'mission selection readback failed')
        end)
        if not ok then
            pawn.PlaneSpWeaponID1=first
            pawn.PlaneSpWeaponID2=second
            error(why)
        end
        log(string.format('MISSION SP repaired %s %d,%d -> %d,%d',d.section,first,second,pair[1],pair[2]))
    end
    local function prepare(pawn,d,availableSelection)
        local world,mission,pair,slot=getMission(pawn,d)
        if not world then return end
        local first,second=pawn.PlaneSpWeaponID1,pawn.PlaneSpWeaponID2
        local localPlayer=isLocalPlayer(pawn,world)
        local active=pawn.PlayerWeaponActivator
        if not valid(active) then return end
        local nativeIDs,configs={},{}
        each(active.SpecialWeaponConfigs,64,'mission mount configs',function(i,row)
            local class=row.WeaponClass
            local defaults=valid(class) and class:GetCDO()
            local id=valid(defaults) and defaults.WeaponID or nil
            nativeIDs[id or 0]=true
            configs[i]=string.format('%s/%s/%s',tostring(row.SpWeaponID),tostring(id),
                valid(class) and (class:GetFullName():match('[^%. /]+$') or '?') or '-')
        end)
        log(string.format('MISSION SP input %s map=%s local=%s native=%s,%s confirmed=%s mounts=%s',
            d.section,mission,tostring(localPlayer),tostring(first),tostring(second),
            pair and table.concat(pair,',') or '-',table.concat(configs,',')))
        if not localPlayer or not pair then return end
        if not slot then
            local ready=availableSelection(d,pair)
            if not ready then
                log('MISSION SP skipped '..d.section..': confirmed weapon ownership not verified')
                return
            end
            if first==ready[1] and second==ready[2] then return end
            local compatible={[0]=true,[pair[1]]=true,[pair[2]]=true}
            for i,id in ipairs(d.target) do
                if id==pair[1] or id==pair[2] then
                    compatible[d.original[i]]=true
                    if d.catalog then compatible[d.catalog[i]]=true end
                end
            end
            if not compatible[first] or not compatible[second] then
                log('MISSION SP skipped '..d.section..': live selection differs from confirmation')
                return
            end
            if not nativeIDs[ready[1]] or (ready[2]~=0 and not nativeIDs[ready[2]]) then
                log('MISSION SP skipped '..d.section..': confirmed weapon class missing')
                return
            end
            if ready~=pair then
                log('MISSION SP owned selection '..d.section..' confirmed='..table.concat(pair,',')
                    ..' available='..table.concat(ready,','))
            end
            repair(pawn,d,first,second,ready)
            return
        end
        if first==podID or second==podID then return end

        -- The spawn path matches PlaneSpWeaponID1/2 against the weapon CDO IDs.
        -- Recover only a missing pod when the other native selection still
        -- matches the accepted pair. The missing slot may be empty, retain its
        -- catalog ID, or duplicate the surviving weapon after native fallback.
        local partner=pair[1]==podID and pair[2] or pair[1]
        if not nativeIDs[podID] or (partner~=0 and not nativeIDs[partner]) then
            log('MISSION SP skipped Su-35: confirmed weapon class missing')
            return
        end
        local function displaced(id)
            return id==0 or id==partner or id==d.original[slot] or id==d.catalog[slot]
        end
        if not ((first==partner and displaced(second)) or (second==partner and displaced(first))) then
            log('MISSION SP skipped Su-35: live selection differs from confirmation')
            return
        end
        repair(pawn,d,first,second,pair)
    end
    local function observe(pawn,d)
        if not valid(pawn) then return end
        local world,mission=getMission(pawn,d)
        if not world or not isLocalPlayer(pawn,world) then return end
        local name=pawn:GetFullName()
        if name==observed then return end
        local active=pawn.PlayerWeaponActivator
        local equipped=valid(active) and active.EquippedWeapons
        if not valid(equipped) or equipped.Configs:GetArrayNum()==0 then return end
        local ids={}
        each(equipped.Configs,64,'mission equipped configs',function(i,row)
            local defaults=row.WeaponClassDefaultObject
            ids[i]=valid(defaults) and tostring(defaults.WeaponID) or '-'
        end)
        observed=name
        log(string.format('MISSION SP equipped %s map=%s native=%s,%s configs=%s',
            d.section,mission,tostring(pawn.PlaneSpWeaponID1),tostring(pawn.PlaneSpWeaponID2),table.concat(ids,',')))
    end
    local function resetObserver()
        observed=nil
    end
    return {confirm=confirm,confirmed=confirmed,confirmedAircraft=confirmedAircraft,
        prepare=prepare,observe=observe,resetObserver=resetObserver}
end
