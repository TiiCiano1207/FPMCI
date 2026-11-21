-- A sibling of the projected instruments keeps its screen position in free look.
local durationSeconds = 1
local fontSizeInNoseHeights = 1.56
local offsetInNoseHeights = 1.5

local function valid(o) return o and o:IsValid() end
local function same(a, b) return valid(a) and valid(b) and a:GetAddress() == b:GetAddress() end
local function field(o, name)
    if not valid(o) then return end
    local ok, value = pcall(function() return o[name] end)
    if ok and valid(value) then return value end
end

local function noseHeight(center)
    local mark = field(center, "WhiskyMarkPanel")
    if mark and mark:IsA("/Script/UMG.PanelWidget") and mark:GetChildrenCount() == 1 then
        local slot = field(mark:GetChildAt(0), "Slot")
        if slot and slot:IsA("/Script/UMG.CanvasPanelSlot") then
            local height = slot:GetSize().Y
            if height > 0 then return height end
        end
    end
    return 36 -- Height of the artwork inside the stock 200 x 200 nose-mark panel.
end

return function(api, log)
    local label, host, source, pulse, expires, nextAttempt, lastError
    local glyph, lastScale, red, green, blue, alpha, rule
    local function unmount()
        if valid(label) then label:RemoveFromParent() end
        label, host, source, glyph, lastScale, red = nil, nil, nil, nil, nil, nil
    end
    local function reset()
        unmount()
        pulse, expires, nextAttempt, lastError = nil, nil, nil, nil
    end
    local function mount(ctx)
        local center = ctx.center
        local canvas = field(ctx.hud, "WorldToScreenDrawCanvas")
        if not canvas and valid(center) then
            local parent = center:GetParent()
            if valid(parent) and parent:GetFName():ToString() == "WorldToScreenDrawCanvas" then canvas = parent end
        end
        local ink = field(center, "SpeedValue") or field(center, "AltitudeValueText")
        if same(canvas, host) and same(ink, source) and valid(label) and same(label:GetParent(), host) then
            return true
        end
        unmount()
        if not (canvas and canvas:IsA("/Script/UMG.CanvasPanel") and ink) then return end
        local tree = field(ctx.widget, "WidgetTree") or field(center, "WidgetTree")
        if not tree then return end
        local class = api.StaticFindObject("/Script/UMG.TextBlock")
        assert(valid(class), "TextBlock class unavailable")
        label = api.StaticConstructObject(class, tree, api.FName("None"), api.EObjectFlags.RF_Transient)
        assert(valid(label), "could not construct notification symbol")
        label:SetVisibility(2)
        label:SetFont(ink.Font)
        local slot = canvas:AddChildToCanvas(label)
        assert(valid(slot) and same(label:GetParent(), canvas), "could not attach notification symbol")
        local middle = {X = 0.5, Y = 0.5}
        slot:SetAnchors({Minimum = middle, Maximum = middle})
        slot:SetAlignment(middle)
        slot:SetAutoSize(true)
        local centerSlot = field(center, "Slot")
        slot:SetZOrder(centerSlot and centerSlot:IsA("/Script/UMG.CanvasPanelSlot") and centerSlot:GetZOrder() + 1 or 1)
        host, source = canvas, ink
        return true
    end
    local function paint(ctx, config)
        if not mount(ctx) then return end
        local scale = (ctx.view == "cockpit" or ctx.view == "hud") and config.Center or 1
        if glyph ~= pulse.glyph or lastScale ~= scale then
            local height = noseHeight(ctx.center) * scale
            local offset = height * offsetInNoseHeights
            local font = label.Font -- Only edit the transient label's copy.
            font.Size = math.max(1, math.floor(height * fontSizeInNoseHeights + 0.5))
            label:SetFont(font)
            label:SetText(api.FText(pulse.glyph))
            label.Slot:SetPosition({X = offset, Y = -offset})
            glyph, lastScale = pulse.glyph, scale
        end
        local tint = source.ColorAndOpacity
        local c = tint.SpecifiedColor
        if c.R ~= red or c.G ~= green or c.B ~= blue or c.A ~= alpha or tint.ColorUseRule ~= rule then
            label:SetColorAndOpacity(tint)
            red, green, blue, alpha, rule = c.R, c.G, c.B, c.A, tint.ColorUseRule
        end
        if label:GetVisibility() ~= 3 then label:SetVisibility(3) end -- HitTestInvisible
    end
    local function update(ctx, config, cue)
        if not cue and not pulse then return end
        local now = api.os.clock()
        if cue then pulse, expires = cue, now + durationSeconds end
        if now >= expires or config[pulse.option] ~= "discreet" then
            if valid(label) then label:SetVisibility(2) end
            pulse = nil
        elseif not nextAttempt or now >= nextAttempt then
            local ok, err = pcall(paint, ctx, config)
            if not ok then
                unmount()
                local reason = tostring(err)
                if reason ~= lastError then log("Discreet notification symbol unavailable: " .. reason) end
                lastError, nextAttempt = reason, now + 0.1
            else
                nextAttempt, lastError = nil, nil
            end
        end
    end
    return {update = update, reset = reset}
end
