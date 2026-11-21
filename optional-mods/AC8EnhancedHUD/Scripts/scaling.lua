-- Apply size at the two widgets positioned by the game's projector. Their
-- translations and the persistent HUD's zoom transform stay under game control.
local function valid(object)
    return object and object:IsValid()
end

local function same(a, b)
    return valid(a) and valid(b) and a:GetAddress() == b:GetAddress()
end

local function vector(v)
    return {X = v.X, Y = v.Y}
end

local function equal(a, b)
    return a and b and math.abs(a.X - b.X) < 0.000001 and math.abs(a.Y - b.Y) < 0.000001
end

local function binding(owner, name)
    if not valid(owner) then return nil end
    local ok, widget = pcall(function() return owner[name] end)
    if ok and valid(widget) then return widget end
end

local function findImage(panel, name, panelClass)
    if not valid(panel) then return nil end
    if panel:GetFName():ToString() == name then return panel end
    if panel:IsA(panelClass) then
        for index = 0, panel:GetChildrenCount() - 1 do
            local widget = findImage(panel:GetChildAt(index), name, panelClass)
            if widget then return widget end
        end
    end
end

-- The root of a UserWidget has no panel parent. Only cross its WidgetTree
-- at that root, so a widget reparented to a new canvas uses its actual layout.
local function layoutParent(widget, treeClass)
    local parent = widget:GetParent()
    if valid(parent) then return parent end
    local tree = widget:GetOuter()
    if valid(tree) and tree:IsA(treeClass) and same(tree.RootWidget, widget) then
        return tree:GetOuter()
    end
end

-- Getters return live UE struct wrappers. Copy numbers before invoking setters.
local properties = {
    {name = "scale", get = function(w) return w.RenderTransform.Scale end, set = "SetRenderScale"},
    {name = "pivot", get = function(w) return w.RenderTransformPivot end, set = "SetRenderTransformPivot"},
}

local function restore(entry)
    if not valid(entry.widget) then return end
    for _, prop in ipairs(properties) do
        local last = entry.written[prop.name]
        if last and equal(last, prop.get(entry.widget)) then
            entry.widget[prop.set](entry.widget, entry.base[prop.name])
        end
        entry.written[prop.name] = nil
    end
end

local function apply(entry, factor)
    local widget = entry.widget
    for _, prop in ipairs(properties) do
        local key = prop.name
        local current = vector(prop.get(widget))
        if not equal(current, entry.written[key]) then
            entry.base[key] = current -- First use or a new game-authored transform.
            entry.written[key] = nil
        end
        local base = entry.base[key]
        local target = key == "scale" and {X = base.X * factor, Y = base.Y * factor} or {X = 0.5, Y = 0.5}
        if not equal(current, target) then
            entry.written[key] = target
            widget[prop.set](widget, target)
            entry.written[key] = vector(prop.get(widget))
        end
    end
end

local instrumentNames = {"Altimeter", "VelocityIcon"}
local imageNames = {"GunReticleBackground", "GunReticleBar"}
return function(api, log)
    local effects = {}
    local remaining = 0
    local lastCenter, lastReticle, lastSize, lastGunSize, treeClass, panelClass

    local function setSize(key, widget, factor)
        local entry = effects[key]
        if entry and (factor == 1 or not same(entry.widget, widget)) then
            restore(entry)
            effects[key] = nil
        end
        if factor == 1 or not valid(widget) then return end
        if not effects[key] then
            effects[key] = {widget = widget, base = {}, written = {}}
        end
        apply(effects[key], factor)
    end

    local function reset()
        local restored = true
        for key, entry in pairs(effects) do
            local ok, err = pcall(restore, entry)
            if ok then
                effects[key] = nil
            else
                restored = false
                local reason = tostring(err)
                if entry.restoreError ~= reason then log("Could not restore " .. key .. ": " .. reason) end
                entry.restoreError = reason
            end
        end
        remaining = 0
        lastCenter, lastReticle = nil, nil
        return restored
    end

    local function update(ctx, settings)
        if not ctx or (ctx.view ~= "cockpit" and ctx.view ~= "hud") then return reset() end
        local center, reticle = ctx.center, ctx.reticle
        remaining = remaining - 1
        -- Discovery keeps these Lua handles between widget-tree refreshes.
        -- No Unreal calls are needed on frames that do not touch a widget.
        if remaining > 0 and rawequal(center, lastCenter) and rawequal(reticle, lastReticle)
            and lastSize == settings.Center and lastGunSize == settings.GunReticle then return end
        remaining = 15
        lastCenter, lastReticle = center, reticle
        lastSize, lastGunSize = settings.Center, settings.GunReticle

        for _, name in ipairs(instrumentNames) do
            setSize(name, binding(center, name), settings.Center)
        end

        -- Compensate only size changes made above. Native zoom applies equally
        -- to the reticle and instruments when they share a parent.
        local inherited = 1
        if valid(reticle) and settings.Center ~= 1 then
            if not valid(treeClass) then treeClass = api.StaticFindObject("/Script/UMG.WidgetTree") end
            local treeType = valid(treeClass) and treeClass or "/Script/UMG.WidgetTree"
            local parent = layoutParent(reticle, treeType)
            while valid(parent) do
                for _, name in ipairs(instrumentNames) do
                    if effects[name] and same(effects[name].widget, parent) then
                        inherited = inherited * settings.Center
                    end
                end
                parent = layoutParent(parent, treeType)
            end
        end
        local factor = settings.GunReticle / inherited
        for _, name in ipairs(imageNames) do
            local image = binding(reticle, name)
            if not image and factor ~= 1 and valid(reticle) then
                local tree = reticle.WidgetTree
                if not valid(panelClass) then panelClass = api.StaticFindObject("/Script/UMG.PanelWidget") end
                image = valid(tree) and findImage(tree.RootWidget, name, valid(panelClass) and panelClass or "/Script/UMG.PanelWidget") or nil
            end
            setSize(name, image, factor)
        end
    end

    return {update = update, reset = reset}
end
