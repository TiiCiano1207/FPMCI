local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local planeClass = "/Script/Live.LivePlayerPlane"
local mslTimer = "AC8EnhancedHUD_SwitchToMSLRemaining"
local released = -1

-- The retail input component binds native member pointers for INP_SwitchWeapon.
-- RegisterHook on the reflected wrappers does not cover that dispatch.
-- Check the press/release bindings and MSL countdown before reading it through
-- UE4SS. Checks are RVAs in the loaded image.
local press = {rva = 0x1c797b90, bytes = {
    {0x1c797bb5, "\x80\x79\x28\x00\x40\x0f\x94\xd7"}, -- press checks for attached tanks
    {0x1c797c19, "\x40\x84\xff"}, -- attached tanks skip the countdown
    {0x1c797c1c, "\x75\x0c\x8b\x83\xe0\x1a\x00\x00\x89\x83\xe4\x1a\x00\x00"}, -- start MSL countdown
}}
local release = {rva = 0x1c798240, bytes = {
    {0x1c798240, "\x40\x53\x48\x83\xec\x20\x48\x8b\x81\xa8\x16\x00\x00"},
    {0x1c7982aa, "\xc7\x83\xe4\x1a\x00\x00\x00\x00\x80\xbf"}, -- release restores -1
}}
local function wrapper(rva, handler)
    return {rva = rva, bytes = {}, refs = {{rva, "\xe9", handler}}}
end
local bindings = {rva = 0x7d402e0, bytes = {
    {0x7d40945, "\x8b\x45\xfc\x48\x8d\x55\xd8\x89\x45\xec\x49\x8b\xce"},
    {0x7d40937, "\x89\x75\xe8\x48\x89\x45\xe0"},
    {0x7d409cd, "\x89\x75\xe8\x48\x89\x45\xe0\x48\x8d\x55\xd8"},
}, refs = {
    {0x7d40930, "\x48\x8d\x05", wrapper(0x7d52a40, press)},
    {0x7d409c6, "\x48\x8d\x05", wrapper(0x7d52af0, release)},
    {0x7d4093e, "\x4c\x8d\x35", {rva = 0xcb76950, kind = "data", bytes = {{0xcb76950, "INP_SwitchWeapon\0"}}}},
}}
local switchToMissile = {rva = 0x7f4e990, bytes = {
    {0x7f4e997, "\x48\x8b\xd9\x48\x8b\x89\xd0\x02\x00\x00\x48\x8b\x01\xff\x90\xe0\x07\x00\x00"},
}}
local countdown = {rva = 0x7d45a52, bytes = {
    {0x7d45a8e, "\xf3\x0f\x10\x87\xe4\x1a\x00\x00\x41\x0f\x2f\xc0\x76\x23\xf3\x0f\x5c\xc7"},
    {0x7d45aa4, "\xf3\x0f\x11\x87\xe4\x1a\x00\x00\x0f\x92\xc0\x84\xc0\x74\x0c\x48\x8b\x8f\xa8\x16\x00\x00"},
}, refs = {{0x7d45aba, "\xe8", switchToMissile}}}

local function bind(api)
    local result = api.RegisterCustomProperty({Name = mslTimer, Type = api.PropertyTypes.FloatProperty,
        BelongsToClass = planeClass, OffsetInternal = 0x1ae4})
    assert(result ~= false, "Cannot register the Switch Weapon countdown")
    return function(pawn)
        return pawn:GetPropertyValue(mslTimer)
    end
end

return function(api, log, config)
    local inspectLayout = assert(loadfile(directory .. "game_layout.lua"))()
    local poll, cancelDiscovery = inspectLayout(directory, {bindings, countdown}, "switch-weapon input")
    local flight, readRemaining, ready
    local enabled, unavailable, readError = false, false, nil
    local function same(a, b) return a and a:IsValid() and b and b:IsValid() and a:GetAddress() == b:GetAddress() end
    local function sample(pawn)
        -- A tank-drop press leaves the timer at -1, even after jettison. Only
        -- a fresh MSL press starts it; expiry persists until button release.
        local remaining = readRemaining(pawn)
        if remaining == released then
            ready = true
        elseif ready and remaining < 0 then
            enabled, ready = not enabled, false
        end
    end
    local function update(ctx)
        if config.EEGSMode ~= "manual" or not ctx then
            cancelDiscovery()
            flight, ready, enabled = nil, false, false
            return false
        end
        -- Flight discovery reuses ctx while all its owners are live. A HUD
        -- replacement can change ctx without starting a new flight.
        if flight ~= ctx then
            if not flight or not same(flight.pawn, ctx.pawn) or not same(flight.world, ctx.world) then
                ready, enabled = false, false
            end
            flight = ctx
        end
        if ctx.view ~= "cockpit" and ctx.view ~= "hud" then
            ready = false
            return false
        end
        if unavailable then return false end
        if not readRemaining then
            local ok, reader = poll()
            if ok == nil then return false end
            if ok then ok, reader = pcall(bind, api) end
            if not ok then
                unavailable = true
                log("Manual EEGS input unavailable: " .. tostring(reader))
                return false
            end
            readRemaining = reader
        end
        sample(ctx.pawn)
        return enabled
    end
    return function(ctx)
        local ok, active = pcall(update, ctx)
        if ok then readError = nil; return active end
        -- Drop an unfinished hold after a missed sample. Keep the toggle in
        -- the same flight, but never carry it across an unreadable handoff.
        ready = false
        if flight ~= ctx then flight, enabled = nil, false end
        local reason = tostring(active)
        if readError ~= reason then log("Cannot read Manual EEGS input: " .. reason) end
        readError = reason
        return enabled
    end, cancelDiscovery
end
