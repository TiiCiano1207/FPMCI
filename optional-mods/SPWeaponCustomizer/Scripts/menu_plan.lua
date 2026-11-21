-- Keep selected weapons in their existing physical slots whenever possible.
-- New choices replace a free slot; the other selected SP weapon is protected.
return function(current,original,first,second,supported,nativeSlots)
    assert(first~=0 and supported[first],'Unsupported SP1')
    assert(second==0 or supported[second],'Unsupported SP2')
    assert(second==0 or first~=second,'Duplicate selected weapons')
    local selected={first};if second~=0 then selected[2]=second end
    local result={current[1],current[2],current[3]}
    local reserved={};local found={}
    -- A native-only weapon keeps its original activator/configuration untouched.
    -- The two remaining physical slots still accommodate any selected pair.
    for slot,id in pairs(nativeSlots or {}) do
        assert(slot>=1 and slot<=3 and original[slot]==id and current[slot]==id,
            'Native weapon slot mismatch')
        result[slot]=id;reserved[slot]=true
        for _,selectedID in ipairs(selected) do if selectedID==id then found[id]=true end end
    end
    -- A stock rocket pod includes the launcher and individual tube sockets.
    -- Prefer the aircraft's ordinary rails for a custom gun pod and its partner.
    if first==20 or second==20 then
        local free,needed=0,0
        for _,id in ipairs(selected) do if not found[id] then needed=needed+1 end end
        for i=1,3 do if not reserved[i] and original[i]~=22 then free=free+1 end end
        if first~=22 and second~=22 and free>=needed then
            for i=1,3 do
                if original[i]==22 then result[i]=22;reserved[i]=true end
            end
        end
    end
    for _,id in ipairs(selected) do
        for slot=1,3 do
            if result[slot]==id and not reserved[slot] then
                reserved[slot]=true;found[id]=true;break
            end
        end
    end
    for _,id in ipairs(selected) do
        if not found[id] then
            local slot
            for i=1,3 do if not reserved[i] and original[i]==id then slot=i;break end end
            if not slot then for i=1,3 do if not reserved[i] then slot=i;break end end end
            assert(slot,'No available physical weapon slot')
            result[slot]=id;reserved[slot]=true
        end
    end
    return result
end
