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
    local function getMission(pawn,d)
        if not d then return end
        local slot
        local replacement=d.missionWeapon or (d.code=='PP0028_su35' and podID)
        if replacement then
            for i,id in ipairs(d.target) do
                if id==replacement then slot=i;break end
            end
            if not slot then return end
        elseif d.code=='PP0003_f04e' then
            -- A stock F-4E carrying MGP provides a read-only comparison.
            if pawn.PlaneSpWeaponID1~=podID and pawn.PlaneSpWeaponID2~=podID then return end
        else
            return
        end
        local world=pawn:GetWorld()
        if not valid(world) or valid(world.NetDriver) then return end
        local mission=world:GetFullName():match('%.(PL_Mission[%w_]*)$')
        if not mission then return end
        return world,mission,slot
    end
    local function isLocalPlayer(pawn,world)
        local instance=world.OwningGameInstance
        if not valid(instance) then return false end
        local players=instance.LocalPlayers
        if not players or players:GetArrayNum()~=1 then return false end
        local controller=players[1].PlayerController
        return valid(controller) and (same(controller.Pawn,pawn) or same(pawn.Controller,controller))
    end
    local function confirm(d,first,second)
        accepted={first,second,aircraft=d}
    end
    local function confirmed(d)
        if accepted and accepted.aircraft==d then return accepted end
    end
    local function recoveryPair(d)
        local pair=confirmed(d)
        local replacement=d.missionWeapon or (d.code=='PP0028_su35' and podID)
        if pair and replacement and (pair[1]==replacement or pair[2]==replacement) and pair[1]~=pair[2] then
            return pair
        end
    end
    local function confirmedAircraft()
        local pair=accepted and recoveryPair(accepted.aircraft)
        if pair then return pair.aircraft,pair end
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
    local function prepare(pawn,d,ownsSelection)
        local world,mission,slot=getMission(pawn,d)
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
        local pair=recoveryPair(d)
        log(string.format('MISSION SP input %s map=%s local=%s native=%s,%s confirmed=%s mounts=%s',
            d.section,mission,tostring(localPlayer),tostring(first),tostring(second),
            slot and pair and table.concat(pair,',') or '-',table.concat(configs,',')))
        if not slot or not localPlayer or not pair then return end
        if d.missionWeapon then
            if first==pair[1] and second==pair[2] then return end
            local function compatible(id)
                return id==0 or id==pair[1] or id==pair[2] or id==d.original[slot]
            end
            if not compatible(first) or not compatible(second) then
                log('MISSION SP skipped '..d.section..': live selection differs from confirmation')
                return
            end
            if not nativeIDs[pair[1]] or (pair[2]~=0 and not nativeIDs[pair[2]]) then
                log('MISSION SP skipped '..d.section..': confirmed weapon class missing')
                return
            end
            if not ownsSelection(d,pair[1],pair[2]) then
                log('MISSION SP skipped '..d.section..': confirmed weapon ownership not verified')
                return
            end
            repair(pawn,d,first,second,pair)
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
