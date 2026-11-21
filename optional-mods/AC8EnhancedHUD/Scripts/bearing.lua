-- Only the replacement widgets receive camera headings. The native compass
-- keeps ticking underneath and is available immediately if sampling fails.
local cardinals = {N = 0, NE = 45, E = 90, SE = 135, S = 180, SW = 225, W = 270, NW = 315}
local function valid(o) return o and o:IsValid() end
local function finite(x) return type(x) == "number" and math.abs(x) < math.huge end
local function difference(a, b) return (a - b + 180) % 360 - 180 end
local halfSpan = 50.4

-- Inside an open interval between two visibility changes, every tick and
-- label keeps its state. The shared layer carries the movement of the tape.
local function visibilityInterval(s, heading)
    local edges = s.edges
    local lo, hi = 1, #edges
    while hi - lo > 1 do
        local mid = (lo + hi) // 2
        if edges[mid] <= heading then lo = mid else hi = mid end
    end
    -- At a boundary the stock comparisons are strict. Re-evaluate on either
    -- side, including when modulo arithmetic rounded a tie differently.
    local lower, upper = edges[lo] + 1e-8, edges[hi] - 1e-8
    if heading > lower and heading < upper then return lower, upper end
    return heading, heading
end

local function rayHeading(ctx, view)
    local x, y = view.viewportRay(ctx)
    if not x then return end
    local horizontal = x*x + y*y
    if horizontal <= 1e-8 then return nil, true end
    -- AC8 adds 450 degrees to Unreal yaw before wrapping. World -Y is north.
    return (math.deg(math.atan(y, x)) + 90) % 360
end

local function viewHeading(s, ctx, view, now)
    if now >= (s.retryRayAt or 0) then
        local ok, heading, vertical = pcall(rayHeading, ctx, view)
        if ok then
            if vertical then return s.lastHeading end
            if heading then return heading end
        else
            s.retryRayAt = now + 1
        end
    end
    if valid(ctx.camera) then
        local pitch, yaw = view.cameraAngles(ctx.camera)
        if pitch then
            if math.abs(math.cos(math.rad(pitch))) <= 1e-4 then return s.lastHeading end
            return (yaw + 90) % 360
        end
    end
end

-- Native HUD visibility is authored independently for the tape and the number.
local function mirror(branch, thirdPerson)
    -- Third-person flight hides the stock compass. Let the HUD holder handle
    -- global visibility and fades while drawing the opt-in tape and number.
    local visibility, opacity = 3, 1
    if not thirdPerson then
        local v = branch.source:GetVisibility()
        visibility = (v == 1 or v == 2) and 2 or 3
        opacity = branch.source:GetRenderOpacity()
    end
    if visibility ~= branch.visibility then branch.copy:SetVisibility(visibility); branch.visibility = visibility end
    if opacity ~= branch.opacity then branch.copy:SetRenderOpacity(opacity); branch.opacity = opacity end
end

-- The game can recolour the stock tape while the camera face is mounted.
-- Store scalar channels; UE4SS struct references can change in place.
local function syncTint(state, value, slate, widget, setter)
    local color, rule = value, nil
    if slate then color, rule = value.SpecifiedColor, value.ColorUseRule end
    local r, g, b, a = color.R, color.G, color.B, color.A
    if state.r == r and state.g == g and state.b == b and state.a == a and state.rule == rule then return end
    widget[setter](widget, value)
    state.r, state.g, state.b, state.a, state.rule = r, g, b, a, rule
end

local function updateColor(item)
    syncTint(item, item.source.ColorAndOpacity, not item.brush, item.widget, "SetColorAndOpacity")
    if item.brush then
        syncTint(item.brush, item.source.Brush.TintColor, true, item.widget, "SetBrushTintColor")
    end
end

return function(api, log, view, childNamed, classFor, attach)
    local function build(s, entry, tree)
        local function make(kind)
            local w = api.StaticConstructObject(classFor(kind), tree, api.FName("None"), api.EObjectFlags.RF_Transient)
            assert(valid(w), "Could not construct bearing " .. kind)
            return w
        end
        local function copy(source, parent, kind)
            assert(valid(source) and source:IsA(classFor(kind)), "Unexpected bearing " .. kind)
            local w = make(kind)
            attach(parent, w, source)
            w:SetRenderTransform(source.RenderTransform)
            w:SetRenderTransformPivot(source.RenderTransformPivot)
            w:SetRenderOpacity(source:GetRenderOpacity())
            if kind == "TextBlock" then
                w:SetFont(source.Font)
                w:SetJustification(source.Justification)
                w:SetText(api.FText(source:GetText():ToString()))
            elseif kind == "Image" then
                w:SetBrush(source.Brush)
            end
            return w
        end
        local tape = assert(childNamed(entry.panel, "CompassInnerPanel"), "Missing compass tape")
        local meter = assert(childNamed(entry.panel, "BearingMeter"), "Missing bearing meter")
        local number = assert(childNamed(meter, "BearingText"), "Missing bearing text")
        s.root = make("CanvasPanel")
        s.root:SetVisibility(2)
        attach(entry.holder, s.root, nil)
        s.root:SetRenderTransform(entry.panel.RenderTransform)
        s.root:SetRenderTransformPivot(entry.panel.RenderTransformPivot)
        local tapeCopy = copy(tape, s.root, "CanvasPanel")
        -- Scroll all visible marks with one paint transform. Their canvas slots
        -- only move when a mark enters view or the angular origin changes.
        s.markLayer = make("CanvasPanel")
        s.markLayer:SetVisibility(3)
        attach(tapeCopy, s.markLayer, nil)
        local meterCopy = copy(meter, s.root, "CanvasPanel")
        s.number = copy(number, meterCopy, "TextBlock")
        s.numberInk = {source = number, widget = s.number}
        s.branches = {
            {source = entry.panel, copy = s.root}, {source = tape, copy = tapeCopy},
            {source = meter, copy = meterCopy}, {source = number, copy = s.number},
        }
        -- The cooked 3840-unit tape has 32 ticks at 60-unit intervals.
        -- All original X positions are already being animated by this point.
        local width = tape.Slot:GetSize().X
        assert(finite(width) and width > 0, "Missing compass tape width")
        s.centerX, s.units = width / 2, width / 720
        local meterWidth = meter.Slot:GetSize().X
        s.marks = {}
        local maxLabelWidth, ticks, labels = 0, 0, 0
        for i = 0, tape:GetChildrenCount() - 1 do
            local source = tape:GetChildAt(i)
            local name = source:GetFName():ToString()
            local n = tonumber(name:match("^Marker(%d+)$"))
            local angle = cardinals[name:match("^TextBlock_(%a+)$")]
            local isLabel = angle ~= nil
            if n and n >= 1 and n <= 32 then
                -- Marker25..32 run westward from north in the stock asset.
                angle = (n <= 24 and n - 1 or 24 - n) * 11.25
                ticks = ticks + 1
            elseif isLabel then
                maxLabelWidth = math.max(maxLabelWidth, source.Slot:GetSize().X)
                labels = labels + 1
            end
            if angle then
                s.marks[#s.marks + 1] = {source = source, angle = angle, label = isLabel, brush = not isLabel and {} or nil}
            end
        end
        assert(ticks == 32 and labels == 8, "Unexpected compass tape marks")
        s.labelGap = (meterWidth + maxLabelWidth) / 2
        local edges = {0, 360}
        local gapDegrees = s.labelGap / s.units
        for _, mark in ipairs(s.marks) do
            edges[#edges + 1] = (mark.angle - halfSpan) % 360
            edges[#edges + 1] = (mark.angle + halfSpan) % 360
            if mark.label then
                edges[#edges + 1] = (mark.angle - gapDegrees) % 360
                edges[#edges + 1] = (mark.angle + gapDegrees) % 360
            end
        end
        table.sort(edges)
        s.edges = edges
        s.makeMark = function(mark)
            mark.widget = copy(mark.source, s.markLayer, mark.label and "TextBlock" or "Image")
            mark.slot = mark.widget.Slot
            mark.y = mark.slot:GetPosition().Y
        end
    end

    local function paint(s, heading)
        local value = math.floor(heading)
        if value ~= s.numberValue then
            s.number:SetText(api.FText(tostring(value)))
            s.numberValue = value
        end
        local rebase = not s.origin or math.abs(difference(heading, s.origin)) > 90
        if rebase then s.origin = heading end
        local shift = -difference(heading, s.origin) * s.units
        if shift ~= s.shift then
            s.markLayer:SetRenderTranslation({X = shift, Y = 0})
            s.shift = shift
        end
        if not rebase and s.lower and heading > s.lower and heading < s.upper then return end
        s.lower, s.upper = visibilityInterval(s, heading)
        for _, mark in ipairs(s.marks) do
            local degrees = difference(mark.angle, heading)
            local dx = degrees * s.units
            -- Native tape displays +/- 0.14 turns and clears space for the number.
            local show = math.abs(degrees) < halfSpan and (not mark.label or math.abs(dx) > s.labelGap)
            if show then
                if not mark.shown then
                    if not mark.widget then s.makeMark(mark) end
                    updateColor(mark)
                end
                if not mark.shown or rebase then
                    local x = s.centerX + difference(mark.angle, s.origin) * s.units
                    mark.slot:SetPosition({X = x, Y = mark.y})
                end
            end
            if mark.widget and show ~= mark.shown then mark.widget:SetVisibility(show and 3 or 2) end
            mark.shown = show
        end
    end

    local function showStock(s, entry)
        if valid(s.root) then s.root:SetVisibility(2) end
        if s.branches then s.branches[1].visibility = nil end
        entry.stockParent:SetRenderOpacity(1)
        s.presented = false
    end

    local function update(s, entry, ctx, now, visible)
        if not visible then return end
        local heading = viewHeading(s, ctx, view, now)
        if not heading then
            if s.presented then showStock(s, entry) end
            return
        end
        if not s.root then build(s, entry, ctx.center.WidgetTree) end
        if not s.presented or not s.tintAt or now < s.tintAt or now - s.tintAt >= 0.1 then
            updateColor(s.numberInk)
            for _, mark in ipairs(s.marks) do
                if mark.shown then updateColor(mark) end
            end
            s.tintAt = now
        end
        -- Ignore subpixel jitter, but always update an integer transition.
        if math.floor(heading) ~= s.numberValue or math.abs(difference(heading, s.paintedHeading)) >= 0.05 then
            paint(s, heading)
            s.paintedHeading = heading
        end
        s.lastHeading = heading
        for _, branch in ipairs(s.branches) do
            mirror(branch, ctx.view == "thirdPerson")
        end
        if not s.presented then
            entry.stockParent:SetRenderOpacity(0)
            s.presented = true
        end
    end
    return function(entry, ctx, now, visible)
        entry.bearing = entry.bearing or {}
        local s = entry.bearing
        if s.failed then return end
        local ok, err = pcall(update, s, entry, ctx, now, visible)
        if not ok then
            showStock(s, entry)
            if valid(s.root) then s.root:RemoveFromParent() end
            s.failed = true
            log("Camera bearing unavailable. Showing the stock compass. " .. tostring(err))
        end
    end, function(entry)
        local s = entry.bearing
        if s and s.presented then showStock(s, entry) end
    end
end
