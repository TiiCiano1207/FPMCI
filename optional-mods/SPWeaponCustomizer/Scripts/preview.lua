-- Register hangar actors once and load the preview implementation once.
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
return function(defs,mounts,log,pairDisplay,pods)
    local actors={}
    local function remember(o,fresh)
        local ok,key,full=pcall(function()
            if o and o:IsValid() then return o:GetAddress(),o:GetFullName() end
        end)
        if not ok or not key or full:find('Default__',1,true) then return end
        if fresh or not actors[key] or actors[key].name~=full then
            actors[key]={object=o,name=full,kind='LiveDisplayPlane'}
        end
    end
    NotifyOnNewObject('/Script/Live.LiveDisplayPlane',function(o)
        ExecuteInGameThread(function()remember(o,true)end)
    end)
    ExecuteInGameThread(function()
        for _,o in ipairs(FindAllOf('LiveDisplayPlane') or {}) do remember(o) end
    end)
    return dofile(dir..'preview_impl.lua')(defs,mounts,log,actors,pairDisplay,pods)
end
