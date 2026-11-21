local dir=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
local each=dofile(dir.."array_reader.lua")
-- Precomputed vanilla capacities; no runtime aircraft discovery is needed.
return function(defaults,enabled,log,campaign)
    local function restore(e,row)
        -- Row wrappers borrow engine memory; never retain them across a map load.
        local saved=e.ammoSaved
        if saved and row then
            local ordinal=0
            each(row.LevelParameter,31,"ammunition levels",function(_,level)
                ordinal=ordinal+1
                for _,s in ipairs(saved[ordinal] or {}) do
                    local info=level['SPWeaponInfo'..s.slot]
                    if info then for i,key in ipairs({'SpWeaponLoadCount1','SpWeaponLoadCount2'}) do
                        if info[key]==s.target[i] then info[key]=s.original[i] end
                    end end
                end
            end)
        end
        e.ammoSaved=nil
    end
    local function apply(e,row)
        if not enabled then return end
        local d=e.definition;local targets={}
        for slot=1,3 do
            if d.target[slot]~=d.original[slot] then
                local id=d.target[slot]
                for originalSlot,original in ipairs(d.original) do
                    if original==id then targets[slot]={originalSlot=originalSlot};break end
                end
                if not targets[slot] and campaign[id] then targets[slot]={pair=campaign[id]} end
                if not targets[slot] then
                    log('AMMO fallback '..d.section..' slot='..slot..': no vanilla donor; keeping original capacity')
                end
            end
        end
        if next(targets)==nil then return end
        local saved={};local writes={};local ordinal=0
        each(row.LevelParameter,31,"ammunition levels",function(_,level)
            ordinal=ordinal+1
            if ordinal~=1 then return end
            for slot,data in pairs(targets) do
                local info=level['SPWeaponInfo'..slot]
                local pair=data.pair
                if data.originalSlot then
                    local donor=level['SPWeaponInfo'..data.originalSlot]
                    pair={donor.SpWeaponLoadCount1,donor.SpWeaponLoadCount2}
                end
                assert(info,'Missing ammunition slot: '..slot)
                local original={info.SpWeaponLoadCount1,info.SpWeaponLoadCount2}
                for i=1,2 do
                    assert(type(original[i])=='number' and original[i]>=0,'Invalid original ammunition')
                    assert(type(pair[i])=='number' and pair[i]>=0 and pair[i]%1==0,'Invalid donor ammunition')
                end
                saved[ordinal]=saved[ordinal] or {}
                saved[ordinal][#saved[ordinal]+1]={slot=slot,original=original,target={pair[1],pair[2]}}
                writes[#writes+1]={row=info,target=pair}
            end
        end)
        assert(ordinal>0,'Missing campaign ammunition entry')
        -- Validate the entire table before the first write; caller rolls back failures.
        e.ammoSaved=saved
        for _,s in ipairs(writes) do
            s.row.SpWeaponLoadCount1=s.target[1];s.row.SpWeaponLoadCount2=s.target[2]
            assert(s.row.SpWeaponLoadCount1==s.target[1] and s.row.SpWeaponLoadCount2==s.target[2],'Ammunition readback failed')
        end
    end
    return {apply=apply,restore=restore}
end
