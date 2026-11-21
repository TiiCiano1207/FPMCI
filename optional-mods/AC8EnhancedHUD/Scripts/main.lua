local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local function module(name) return assert(loadfile(directory .. name .. ".lua"))() end
local function log(message) print("[AC8EnhancedHUD] " .. message .. "\n") end

local config, ranges = module("config")(directory .. "../config.ini", log)
local currentFlight = module("flight")(_G, log)
local inputLoaded, manualInput, cancelInputDiscovery = pcall(function()
    return module("eegs_input")(_G, log, config)
end)
if not inputLoaded then
    log("Manual EEGS input unavailable: " .. tostring(manualInput))
    manualInput = nil
end
local features = {}
for _, name in ipairs({"scaling", "target_boxes", "readouts", "visor_mask", "pitch_ladder", "notifications"}) do
    local ok, feature = pcall(function() return module(name)(_G, log) end)
    if ok then
        features[#features + 1] = {name = name, effect = feature}
    else
        log(name .. " unavailable: " .. tostring(feature))
    end
end
local function reset(f)
    local ok, restored = pcall(f.effect.reset)
    if not ok or restored == false then
        if not ok and not f.dirty then log("Will retry " .. f.name .. " cleanup: " .. tostring(restored)) end
        f.dirty = true
    else
        f.dirty = false
    end
end

local previous, stopped, discoveryError
local function tick()
    if stopped then return true end
    -- Cockpit and HUD-only projection also applies at stock instrument size.
    local needGlass = config.VisorMask or (config.DetachForward and (config.FixedReadouts or config.RelativeBearing))
    local ok, ctx = pcall(currentFlight, needGlass)
    if not ok then
        if discoveryError ~= tostring(ctx) then
            discoveryError = tostring(ctx)
            log("Flight HUD unavailable: " .. discoveryError)
        end
        ctx = nil
    else
        discoveryError = nil
    end
    local manual = manualInput and manualInput(ctx) or false
    if ctx then ctx.manualEEGS = manual end
    for _, f in ipairs(features) do
        if previous ~= ctx then f.stopped = false end
        if (previous and ctx ~= previous) or f.dirty then reset(f) end
        if ctx and not f.stopped and not f.dirty then
            local options = config
            if f.name == "visor_mask" then options = config.VisorMask end
            local applied, err = pcall(f.effect.update, ctx, options)
            if not applied then
                log(f.name .. " stopped for this flight HUD: " .. tostring(err))
                f.stopped = true
                reset(f)
            elseif err == false then
                f.dirty = true
            end
        end
    end
    previous = ctx
end

local scheduled, action = pcall(LoopInGameThreadAfterFrames, 1, tick)
if not scheduled or action == false then
    local frameError = tostring(action)
    scheduled, action = pcall(LoopInGameThreadWithDelay, 16, tick)
    if not scheduled or action == false then
        log("Cannot schedule HUD updates. Frame loop: " .. frameError .. ". Timed game-thread loop: " .. tostring(action))
        return
    end
    log("Using the 16 ms game-thread loop. Frame loop unavailable: " .. frameError)
end
log("Loaded 0.7.3.")
local attached, handle = pcall(function() return module("mod_settings")(config, ranges) end)
if not attached then
    local reason = tostring(handle)
    if not reason:find("module 'AC8ModSettings' not found:", 1, true) then
        log("AC8ModSettings unavailable; using INI configuration: " .. reason)
    end
    handle = nil
end
if ModRef then
    local onUnload = ModRef.OnUnload
    ModRef.OnUnload = function(...)
        stopped = true
        if action and CancelDelayedAction then pcall(CancelDelayedAction, action) end
        local function cleanup()
            if cancelInputDiscovery then cancelInputDiscovery() end
            for _, f in ipairs(features) do reset(f) end
            if handle then handle.detach() end
        end
        local known, inGameThread = pcall(IsInGameThread)
        local ok, err
        if known and inGameThread then
            ok, err = pcall(cleanup)
        else
            ok, err = pcall(ExecuteInGameThread, cleanup)
        end
        if not ok then log("Unload cleanup unavailable: " .. tostring(err)) end
        if type(onUnload) == "function" then return onUnload(...) end
    end
end
