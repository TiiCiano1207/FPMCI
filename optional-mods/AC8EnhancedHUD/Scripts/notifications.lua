local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local class = "/Script/Live.LiveHUDMessageWidget"
local killDelayBytes = string.pack("<f", 0.2)
local function message(name, id, priority, delay, base, key, glyph)
    local prefix = "AC8EnhancedHUD_" .. name
    return {option = name .. "Notification", id = id, priority = priority, delay = delay, base = base, key = key, glyph = glyph,
        priorityField = prefix .. "Priority", delayField = prefix .. "Delay"}
end
local messages = {
    message("Hit", 0x17, 4, 0, 0xa48, "HudAttack_Name_Hit", "+"),
    message("Destroyed", 0x15, 3, string.unpack("<f", killDelayBytes), 0x9f8, "HudAttack_Name_Destroyed", "x"),
    message("Missed", 0x18, 5, 0, 0xa70, "HudAttack_Name_Miss", "o"),
}
local byId = {}
for _, m in ipairs(messages) do byId[m.id] = m end
local layerType = "AC8EnhancedHUD_MessageLayerTwoType"
local layerPriority = "AC8EnhancedHUD_MessageLayerTwoPriority"
local layerDelay = "AC8EnhancedHUD_MessageLayerTwoDelay"
local layerRemaining = "AC8EnhancedHUD_MessageLayerTwoRemaining"
local empty = 99
local inactive = 0x41
-- Give the frame callback time to consume an admitted discreet message before
-- the stock renderer paints it. Clear this delay as soon as we observe it.
local renderDelay = 2

-- RVAs in the reviewed message routines. All three templates select message layer
-- two. Its empty priority is 99, and AC8 rejects an incoming priority greater
-- than the current one before copying any text, timer or artwork to the layer.
local function literal(rva, key)
    return {rva = rva, kind = "data", bytes = {{rva, key .. "\0"}}}
end
local template = {rva = 0x7263ac0, bytes = {
    {0x7263ae2, "\x48\x8b\xd9\x89\x41\x18"},
    {0x7263b00, "\xf3\x0f\x10\x84\x24\xa0\x00\x00\x00"},
    {0x7263b0c, "\xf3\x0f\x11\x41\x24"},
    {0x7263b11, "\x88\x11\x44\x88\x41\x01\x44\x88\x49\x02"},
}}
local storeTemplate = {rva = 0x725b720, bytes = {
    {0x725b735, "\x0f\xb6\x02\x48\x8d\x72\x08\x88\x01"},
    {0x725b785, "\x8b\x47\x18\x48\x8b\x74\x24\x38\x89\x43\x18"},
    {0x725b7a4, "\x8b\x47\x24\x48\x8b\x7c\x24\x40\x89\x43\x24"},
}}
local initialize = {rva = 0x7259550, bytes = {
    {0x725a336, "\xb2\x15\xf3\x44\x0f\x11\x54\x24\x30\xc7\x44\x24\x28\x03\x00\x00\x00"},
    {0x72595bb, "\x0f\x57\xff"},
    {0x725a315, "\xf3\x0f\x11\x44\x24\x50"},
    {0x725a325, "\x41\xb1\x01\x40\x88\x74\x24\x40\x45\x0f\xb6\xc1"},
    {0x725a354, "\x48\x8d\x8b\xf8\x09\x00\x00"},
    {0x725a414, "\x41\xb1\x01\x40\x88\x74\x24\x38\x45\x0f\xb6\xc1"},
    {0x725a3fa, "\xf3\x0f\x11\x7c\x24\x50"},
    {0x725a427, "\xb2\x17\xc7\x44\x24\x28\x04\x00\x00\x00"},
    {0x725a43e, "\x48\x8d\x8b\x48\x0a\x00\x00"},
    {0x725a490, "\xc7\x44\x24\x28\x05\x00\x00\x00\x41\xb1\x01"},
    {0x725a46f, "\xf3\x0f\x11\x7c\x24\x50"},
    {0x725a4a8, "\xb2\x18"},
    {0x725a4b2, "\x48\x8d\x8b\x70\x0a\x00\x00"},
}, refs = {
    {0x725a2f7, "\x48\x8d\x15", literal(0xcb46060, "{HudAttack_Name_Destroyed}")},
    {0x725a308, "\xf3\x0f\x10\x05", {rva = 0xd293488, kind = "data", bytes = {{0xd293488, killDelayBytes}}}},
    {0x725a3e9, "\x48\x8d\x15", literal(0xcb46028, "{HudAttack_Name_Hit}")},
    {0x725a45e, "\x48\x8d\x15", literal(0xcb45ea8, "{HudAttack_Name_Miss}")},
    {0x725a34c, "\xe8", template}, {0x725a436, "\xe8", template}, {0x725a4aa, "\xe8", template},
    {0x725a35b, "\xe8", storeTemplate}, {0x725a445, "\xe8", storeTemplate}, {0x725a4b9, "\xe8", storeTemplate},
}}
local assignMessage = {rva = 0x7263dd0, bytes = {
    {0x7263dda, "\x0f\xb6\x02\x48\x8b\xda\x88\x01"},
    {0x7263df9, "\x8b\x43\x18\x89\x47\x18\x8b\x43\x1c\x89\x47\x1c"},
    {0x7263e13, "\x8b\x43\x24\x48\x8b\x5c\x24\x30\x89\x47\x24"},
}}
local admit = {rva = 0x725b7c0, bytes = {
    {0x725b7e3, "\x4e\x8d\x3c\xa5\xd6\x00\x00\x00\x4d\x03\xfc\x46\x0f\xb6\x6c\xf9\x02\x4e\x8d\x3c\xf9"},
    {0x725ba22, "\x41\x0f\xb6\x07\x4e\x8d\x34\xad\xbc\x00\x00\x00\x4d\x03\xf5\x42\x38\x04\xf7\x4e\x8d\x34\xf7\x74\x36"},
    {0x725ba3b, "\x41\x8b\x47\x18\x41\x39\x46\x18\x7c\x2c"},
}, refs = {{0x725ba4b, "\xe8", assignMessage}}}
local hitEvent = {rva = 0x7f24a68, bytes = {
    {0x7f24ad4, "\x33\xc9\x4c\x8d\x44\x24\x20\x48\x89\x4c\x24\x20\xb2\x17\x48\x89\x4c\x24\x28\x48\x8b\x88\xe8\x07\x00\x00"},
}, refs = {{0x7f24aee, "\xe8", admit}}}
local expire = {rva = 0x72588e1, bytes = {
    {0x7258ac6, "\xf3\x0f\x10\x87\x2c\x06\x00\x00\x0f\x2f\xc7\x76\x0f\xf3\x41\x0f\x5c\xc0\xf3\x0f\x11\x87\x2c\x06\x00\x00"},
    {0x7258ae2, "\xf3\x0f\x10\x87\x24\x06\x00\x00\xf3\x41\x0f\x5c\xc0\xf3\x0f\x11\x87\x24\x06\x00\x00"},
    {0x7258b00, "\x0f\x2f\xc7\x77\x29"},
    {0x7258b0c, "\xc7\x87\x20\x06\x00\x00\x63\x00\x00\x00"},
    {0x7258b27, "\xc6\x87\x08\x06\x00\x00\x41"},
}}
local render = {rva = 0x725df50, bytes = {
    {0x725e0b1, "\x0f\xb6\x84\xfe\xe0\x05\x00\x00\x48\x8d\x14\xfa\x88\x44\x24\x50"},
    {0x725e0ec, "\x44\x8b\xb4\xfe\xf8\x05\x00\x00"},
    {0x725e0e3, "\xf3\x0f\x10\xb4\xfe\x04\x06\x00\x00"},
    {0x725e117, "\x41\x0f\x2f\xf5\x76\x2e"},
    {0x725e146, "\xe9\x37\x09\x00\x00"},
    {0x725e14b, "\x41\x83\xfe\x63\x0f\x84\xd0\x06\x00\x00"},
    {0x725e825, "\x49\x8b\x04\x24\xb2\x01\x49\x8b\xcc\xff\x90\xc8\x02\x00\x00"},
}}

local function bind(api)
    local function register(name, kind, offset)
        local result = api.RegisterCustomProperty({Name = name, Type = api.PropertyTypes[kind],
            BelongsToClass = class, OffsetInternal = offset})
        assert(result ~= false, "Cannot register " .. name)
    end
    for _, m in ipairs(messages) do
        register(m.priorityField, "IntProperty", m.base + 0x18)
        register(m.delayField, "FloatProperty", m.base + 0x24)
    end
    register(layerType, "ByteProperty", 0x608)
    register(layerPriority, "IntProperty", 0x620)
    register(layerDelay, "FloatProperty", 0x62c)
    register(layerRemaining, "FloatProperty", 0x624)
end

return function(api, log)
    local inspectLayout = assert(loadfile(directory .. "game_layout.lua"))()
    local poll, cancelDiscovery = inspectLayout(directory, {initialize, hitEvent, expire, render}, "HUD message")
    local symbol = assert(loadfile(directory .. "notification_symbol.lua"))()(api, log)
    local bound, owner, hidden, hiddenId, visual, active
    local edits = {}
    local function valid(o) return o and o:IsValid() end

    local function restoreTemplate(m)
        local edit = edits[m]
        if edit and owner:GetPropertyValue(edit.field) == edit.value then
            owner:SetPropertyValue(edit.field, edit.original)
        end
        edits[m] = nil
    end
    local function applyTemplate(m, mode)
        if edits[m] and mode ~= edits[m].mode then restoreTemplate(m) end
        local field, original, value
        if mode == "hide" then
            field, original, value = m.priorityField, m.priority, empty + 1
        elseif mode == "discreet" then
            field, original, value = m.delayField, m.delay, renderDelay
        else
            return
        end
        if owner:GetPropertyValue(field) == original then
            edits[m] = {mode = mode, field = field, original = original, value = value}
            owner:SetPropertyValue(field, value)
        end
    end
    local function releaseDelay(m)
        if m and edits[m] and edits[m].mode == "discreet" and owner:GetPropertyValue(m.delayField) == renderDelay then
            local delay = owner:GetPropertyValue(layerDelay)
            -- Preserve the elapsed part of AC8's original 0.2 s delay on DESTROYED.
            if delay > m.delay and delay <= renderDelay then
                owner:SetPropertyValue(layerDelay, math.max(0, m.delay - (renderDelay - delay)))
            end
        end
    end
    local function restoreLayer()
        if hidden and owner:GetPropertyValue(layerType) == hiddenId
            and owner:GetPropertyValue(layerPriority) == empty
            and (hiddenId ~= inactive or owner:GetPropertyValue(layerRemaining) > 0) then
            if hiddenId == inactive then owner:SetPropertyValue(layerType, hidden.id) end
            owner:SetPropertyValue(layerPriority, hidden.priority)
        end
        hidden, hiddenId = nil, nil
    end
    local function reset()
        cancelDiscovery()
        active = false
        if visual then
            visual.reset()
            if bound then visual = nil end
        else
            symbol.reset()
        end
        if valid(owner) then
            releaseDelay(byId[owner:GetPropertyValue(layerType)])
            for _, m in ipairs(messages) do restoreTemplate(m) end
            restoreLayer()
        end
        owner, hidden, hiddenId, edits = nil, nil, nil, {}
    end
    local function useWidgets(reason, ctx, config)
        if not visual then
            reset()
            log("Using widget-based notification filtering: " .. reason)
            visual = assert(loadfile(directory .. "notification_widgets.lua"))()(api, log, messages, symbol.reset)
        end
        return visual.update(ctx, config)
    end
    local function messageWidget(hud)
        local message = hud.HUDMessageWidget
        if valid(message) and message:IsA(class) then return message end
        return nil, hud.NonGlowWidget
    end
    local function filter(ctx, config)
        if bound == false then return visual.update(ctx, config) end
        if bound == nil then
            local ok, why = poll()
            if ok == nil then return end
            if ok then ok, why = pcall(bind, api) end
            bound = ok
            if not bound then return useWidgets(tostring(why), ctx, config) end
        end
        local accessible, widget, nonGlow = pcall(messageWidget, ctx.hud)
        if not accessible or not widget then
            if accessible and not valid(nonGlow) then
                if owner or visual then reset() end
                return
            end
            return useWidgets("waiting for HUDMessageWidget", ctx, config)
        end
        if visual then visual.reset(); visual = nil end
        if owner and not (valid(owner) and widget:GetAddress() == owner:GetAddress()) then reset() end
        owner = widget
        local id = owner:GetPropertyValue(layerType)
        local current = byId[id]
        releaseDelay(current)
        for _, m in ipairs(messages) do applyTemplate(m, config[m.option]) end

        if hidden and id ~= hiddenId then hidden, hiddenId = nil, nil end
        if hidden and config[hidden.option] == "show" then restoreLayer() end
        local mode = current and config[current.option]
        if current and (mode == "hide" or mode == "discreet") then
            local priority = owner:GetPropertyValue(layerPriority)
            if priority == current.priority then
                hidden, hiddenId = current, id
                owner:SetPropertyValue(layerPriority, empty)
                priority = empty
            end
            if mode == "discreet" and hidden == current and priority == empty then
                -- Admission rejects a matching type even at empty priority. Release it
                -- now so consecutive hits can each start a new pulse before stock expiry.
                owner:SetPropertyValue(layerType, inactive)
                hiddenId = inactive
                return current
            end
        end
    end
    local function update(ctx, config)
        if config.HitNotification == "show" and config.DestroyedNotification == "show" and config.MissedNotification == "show" then
            if active then reset() end
            return
        end
        local cue = filter(ctx, config)
        symbol.update(ctx, config, cue)
        active = true
    end
    return {update = update, reset = reset}
end
