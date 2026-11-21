-- The target renderer adds a selection bonus to the base box size. Both are
-- floats on the container actor, independent of its transform and text size.
local fields = {"ContainerBoxImageSize", "SelectTargetAddContainerBoxSize"}
local refreshFrames = 15

local function scale(entry, factor)
    local actor = entry.actor
    if not actor:IsValid() then return end
    for _, name in ipairs(fields) do
        local current = actor[name]
        if type(current) == "number" and math.abs(current) < math.huge then
            local state = entry[name]
            if not state then
                state = {base = current}
                entry[name] = state
            end
            if current ~= state.written or factor ~= entry.factor then
                -- A pooled container can acquire a new game-authored size.
                if current ~= state.written then state.base = current end
                local desired = string.unpack("f", string.pack("f", state.base * factor))
                state.written = desired
                if desired ~= current then actor[name] = desired end
            end
        end
    end
    entry.factor = factor
end

local function restore(entry)
    if not entry.actor:IsValid() then return end
    for _, name in ipairs(fields) do
        local state = entry[name]
        if state and state.base ~= state.written and entry.actor[name] == state.written then
            entry.actor[name] = state.base
        end
    end
end

return function(_, log)
    local entries, active = {}, {}
    local generation, remaining, cursor = 0, 0, 1
    local lastFactor

    local function releaseUnused()
        local restored = true
        for id, entry in pairs(entries) do
            if entry.generation ~= generation then
                local ok, err = pcall(restore, entry)
                if ok then
                    entries[id] = nil
                else
                    restored = false
                    local reason = tostring(err)
                    if reason ~= entry.error then log("Could not restore target box: " .. reason) end
                    entry.error = reason
                end
            end
        end
        return restored
    end

    local function reset()
        if not lastFactor and not next(entries) then return true end
        generation = generation + 1
        active, lastFactor, remaining = {}, nil, 0
        return releaseUnused()
    end

    local function update(ctx, settings)
        local factor = settings.TargetBoxes
        if not ctx.view or factor == 1 then return reset() end
        if remaining == 0 or lastFactor ~= factor then
            -- Visit only the active HUD's target map. Reconcile removals even
            -- when the manager disappears or the mission has no targets.
            generation = generation + 1
            active, cursor = {}, 1
            local manager = ctx.hud.TargetContainerManager
            if manager and manager:IsValid() then
                manager.TargetContainers:ForEach(function(_, value)
                    local actor = value:get()
                    if not actor or not actor:IsValid() then return end
                    local id = actor:GetAddress()
                    local entry = entries[id]
                    if not entry or not entry.actor:IsValid() then
                        entry = {actor = actor}
                        entries[id] = entry
                    end
                    if entry.generation ~= generation then
                        entry.generation = generation
                        active[#active + 1] = entry
                    end
                end)
            end
            if not releaseUnused() then return false end
            remaining, lastFactor = refreshFrames, factor
        end
        -- Spread property reads across updates in target-rich missions.
        local count = math.max(8, math.ceil(#active / refreshFrames))
        for i = cursor, math.min(#active, cursor + count - 1) do scale(active[i], factor) end
        cursor, remaining = cursor + count, remaining - 1
    end

    return {update = update, reset = reset}
end
