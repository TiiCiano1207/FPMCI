-- For unrecognized executable layouts, use the game's localized captions and
-- reflected UMG controls. The game owns message selection and expiry here.
local function valid(o) return o and o:IsValid() end
local function same(a, b) return valid(a) and valid(b) and a:GetAddress() == b:GetAddress() end

local function field(owner, name)
    local ok, value = pcall(function() return owner[name] end)
    if ok then return value end
end

local function pair(panel, background)
    if not valid(panel) or not panel:IsA("/Script/UMG.PanelWidget") or panel:GetChildrenCount() ~= 2 then return end
    local first, second = panel:GetChildAt(0), panel:GetChildAt(1)
    local label
    if same(first, background) then label = second elseif same(second, background) then label = first end
    if valid(label) and label:IsA("/Script/UMG.TextBlock") and same(label:GetParent(), panel) then
        return {panel = panel, label = label, background = background}
    end
end

local function findLayer(hud, widget)
    if valid(widget) then
        local bg = field(widget, "LayerTwoBackgroundImage")
        local found = valid(bg) and pair(bg:GetParent(), bg)
        local panels, texts = field(widget, "MessageWidgets"), field(widget, "MessageTexts")
        if found and panels and texts then
            for i = 1, math.min(#panels, #texts) do
                if same(panels[i], found.panel) and same(texts[i], found.label) then return found end
            end
        end
    end

    -- The cooked layer lives under the current HUD's separate NonGlowWidget.
    -- Search only its panel tree, including through newly inserted containers.
    local nonGlow = field(hud, "NonGlowWidget")
    local tree = valid(nonGlow) and field(nonGlow, "WidgetTree")
    local root = valid(tree) and field(tree, "RootWidget")
    if not valid(root) then return nil, "waiting for the registered combat popup" end
    local stack, match, visited = {root}, nil, 0
    while #stack > 0 do
        local node = table.remove(stack)
        if valid(node) then
            visited = visited + 1
            if visited > 512 then return nil, "combat popup tree exceeds search limit" end
            if node:IsA("/Script/UMG.PanelWidget") then
                local count = node:GetChildrenCount()
                if count + #stack + visited > 512 then return nil, "combat popup tree exceeds search limit" end
                for i = 0, count - 1 do stack[#stack + 1] = node:GetChildAt(i) end
            elseif node:GetFName():ToString() == "LayerTwoBackground" and node:IsA("/Script/UMG.Image") then
                local candidate = pair(node:GetParent(), node)
                if candidate and candidate.label:GetFName():ToString() == "LayerTwoText" then
                    if match then return nil, "ambiguous combat popup in the active HUD" end
                    match = candidate
                end
            end
        end
    end
    if match then match.treeOwner = nonGlow end
    return match, "waiting for the combat popup in the active HUD"
end

return function(api, log, messages, resetSymbol)
    local owner, layer, opacity, manager, culture, captions, lastReason
    local previousCue
    local retry, refresh = 0, 0
    local function restore()
        if opacity ~= nil and valid(layer.panel) and layer.panel:GetRenderOpacity() == 0 then
            layer.panel:SetRenderOpacity(opacity)
        end
        opacity = nil
    end
    local function releaseLayer()
        restore()
        resetSymbol()
        layer, previousCue, refresh = nil, nil, 0
    end
    local function reset()
        releaseLayer()
        owner, manager, culture, captions, lastReason = nil, nil, nil, nil, nil
        retry = 0
    end
    local function bind(hud, widget)
        local found, reason = findLayer(hud, widget)
        if not found then return nil, reason end
        if not valid(manager) then manager = api.StaticFindObject("/Script/Live.Default__LiveLocalizationManager") end
        if not valid(manager) then return nil, "waiting for the localization manager" end
        local locale = manager:GetCulture():ToString()
        if culture ~= locale then
            captions = {}
            local complete = true
            for _, m in ipairs(messages) do
                local text = manager:LocalizeString(m.key, false, "(DUMMY)", "(UNTRANSLATED)"):ToString()
                if text == "" or text == m.key or text == "(DUMMY)" or text == "(UNTRANSLATED)" then
                    complete = false
                elseif captions[text] ~= nil then
                    captions[text] = false -- Two events share a translation. Leave that caption alone.
                else
                    captions[text] = m
                end
            end
            culture = complete and locale or nil
        end
        return found
    end
    local function update(ctx, config)
        if retry > 0 and not owner then retry = retry - 1; return end
        local widget = field(ctx.hud, "HUDMessageWidget")
        local source = valid(widget) and widget or field(ctx.hud, "NonGlowWidget")
        if owner and not same(owner, source) then reset() end
        if not valid(source) then retry = 59; return end
        owner = source
        if retry > 0 then retry = retry - 1; return end
        if layer and ((layer.treeOwner and not same(layer.treeOwner, field(ctx.hud, "NonGlowWidget")))
            or not valid(layer.label) or not valid(layer.panel) or not valid(layer.background)
            or not same(layer.label:GetParent(), layer.panel) or not same(layer.background:GetParent(), layer.panel)
            or layer.panel:GetChildrenCount() ~= 2) then
            releaseLayer()
        end
        if refresh == 0 then
            local ok, found, reason = pcall(bind, ctx.hud, widget)
            if not ok or not found then
                releaseLayer()
                retry = 59
                if not ok then reason = tostring(found) end
                if reason ~= lastReason then log("Widget notification filter: " .. reason); lastReason = reason end
                return
            end
            if layer and not same(layer.panel, found.panel) then releaseLayer() end
            layer, lastReason, refresh = found, nil, 60
        end
        refresh = refresh - 1
        -- AC8 can leave the last caption in a collapsed panel after expiry.
        local m = captions[layer.label:GetText():ToString()]
        local mode = m and config[m.option]
        local cue
        if mode and mode ~= "show" and layer.panel:IsVisible() and layer.label:IsVisible() then
            local current = layer.panel:GetRenderOpacity()
            if current ~= 0 then
                opacity = current
                layer.panel:SetRenderOpacity(0)
            end
            if opacity and mode == "discreet" then cue = m end
        else
            restore()
        end
        -- Only a new presentation starts the timer. The caption can stay visible for many frames.
        if cue ~= previousCue then
            previousCue = cue
            return cue
        end
    end
    return {update = update, reset = reset}
end
