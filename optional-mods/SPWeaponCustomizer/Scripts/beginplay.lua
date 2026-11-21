return function(defs,mounts,log,borrowLoadout,borrowMissionLoadout,missionSp,ownsSelection)
    local byName={}
    for _,d in ipairs(defs.aircraft) do
        byName['BP_PlayerPlane_'..d.code..'_C']=d
    end
    if next(byName)==nil then return end
    -- Diagnostics only: one MAP line per loaded world (mission, restart or hangar),
    -- written when its first player-class aircraft begins play.
    local lastWorld
    local function markWorld(world,d)
        local address=world:GetAddress()
        if address==lastWorld then return end
        lastWorld=address
        local full=tostring(world:GetFullName() or '')
        log('MAP '..(full:match('([^%./ ]+)$') or 'unknown')..' first aircraft '..d.section)
    end
    local su35=byName.BP_PlayerPlane_PP0028_su35_C
    local missionRelease,worldChecked
    local function endMissionLoadout()
        if missionRelease then
            local release=missionRelease
            missionRelease=nil
            release()
        end
    end
    RegisterLoadMapPreHook(function()
        worldChecked=nil
        missionSp.resetObserver()
        endMissionLoadout()
    end)
    local function prepareMission(actor)
        local world=actor:GetWorld()
        if not world or not world:IsValid() then return end
        local address=world:GetAddress()
        if worldChecked==address then return end
        endMissionLoadout()
        worldChecked=address
        if world.NetDriver and world.NetDriver:IsValid() then return end
        if not tostring(world:GetFullName()):match('%.PL_Mission[%w_]*$') then return end
        local d,pair=missionSp.confirmedAircraft()
        if d and d.missionWeapon then
            if not ownsSelection(d,pair[1],pair[2]) then
                log('MISSION loadout skipped '..d.section..': confirmed weapon ownership not verified')
                return
            end
        else
            d=su35
            if not d or not (d.target[1]==20 or d.target[2]==20 or d.target[3]==20) then return end
        end
        missionRelease=borrowMissionLoadout(d)
        if missionRelease then
            log('MISSION loadout '..d.section..' slots='..table.concat(d.target,','))
        else
            worldChecked=nil
        end
    end
    local pending={}
    local function finish(id)
        local entry=pending[id]
        if not entry then return end
        pending[id]=nil
        entry.release()
        if entry.timer then CancelDelayedAction(entry.timer) end
    end
    local function afterBegin(context)
        if not next(pending) then return end
        local ok,actor=pcall(function()return context:get()end)
        if not ok or not actor then actor=context end
        if not actor or not actor:IsValid() then return end
        local id=actor:GetAddress()
        finish(id)
    end
    if type(RegisterBeginPlayPostHook)=="function" then RegisterBeginPlayPostHook(afterBegin) end
    RegisterBeginPlayPreHook(function(context)
        local ok,err=pcall(function()
            local actor=context
            -- UE4SS hook arguments may be wrapped, depending on the callback API.
            local got,value=pcall(function()return context:get()end)
            if got and value then actor=value end
            if not actor or not actor:IsValid() then return end
            prepareMission(actor)
            local name=actor:GetClass():GetFullName():match('([^%. ]+)$')
            local d=byName[name]
            if not d then return end
            local world=actor:GetWorld()
            if not world or not world:IsValid() then return end
            if world.NetDriver and world.NetDriver:IsValid() then return end
            pcall(markWorld,world,d)
            if d.target[1]==d.original[1] and d.target[2]==d.original[2] and d.target[3]==d.original[3] then
                missionSp.prepare(actor,d,ownsSelection)
                return
            end
            mounts.prepare(d,actor)
            local id=actor:GetAddress()
            if not pending[id] then
                local entry={}
                -- A destroyed actor may not reach the post hook. Restore on the
                -- next game frame even in that case.
                entry.timer=LoopInGameThreadAfterFrames(1,function()finish(id)end)
                local acquired,release=pcall(borrowLoadout,d)
                if not acquired then CancelDelayedAction(entry.timer);error(release) end
                entry.release=release
                pending[id]=entry
            end
            missionSp.prepare(actor,d,ownsSelection)
        end)
        if not ok then log('BEGIN PRE failed: '..tostring(err)) end
    end)
    log('Aircraft BeginPlay pre-hook registered')
    return endMissionLoadout
end
