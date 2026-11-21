local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local function valid(o)
    return o and o:IsValid()
end
local function same(a, b)
    return valid(a) and (rawequal(a, b) or valid(b) and a:GetAddress() == b:GetAddress())
end
local function finite(x)
    return type(x) == "number" and math.abs(x) < math.huge
end
local function xy(v)
    return v.X or v.x, v.Y or v.y
end
local function vec(x, y)
    return { X = x, Y = y }
end
local function close(a, b)
    return a ~= nil and b ~= nil and math.abs(a - b) < 1e-6
end
local function rotate(c, s, x, y)
    return c * x - s * y, s * x + c * y
end
local function angle(x, y)
    return math.deg(math.atan(y, x))
end
local function wrap(a)
    return (a + 180) % 360 - 180
end

local function snapshot(slot)
    local l = slot:GetLayout()
    local a, p, o = l.Anchors or l.anchors, l.Alignment or l.alignment, l.Offsets or l.offsets
    -- Some UE4SS builds expose live views into the slot. Keep only numbers
    -- across RemoveFromParent, which can destroy that native slot.
    local layout = {
        Anchors = { Minimum = vec(xy(a.Minimum or a.minimum)), Maximum = vec(xy(a.Maximum or a.maximum)) },
        Alignment = vec(xy(p)),
        Offsets = {
            Left = o.Left or o.left,
            Top = o.Top or o.top,
            Right = o.Right or o.right,
            Bottom = o.Bottom or o.bottom,
        },
    }
    return { layout = layout, auto = slot:GetAutoSize(), z = slot:GetZOrder() }
end

local function applyLayout(slot, saved)
    slot:SetLayout(saved.layout)
    slot:SetAutoSize(saved.auto)
    slot:SetZOrder(saved.z)
end

local function attach(parent, widget)
    local slot = parent:AddChildToCanvas(widget)
    assert(valid(slot) and same(widget:GetParent(), parent), "Cannot attach pitch canvas")
    return slot
end

-- The stock slot uses a fixed-size anchor. Its rectangle is in the same
-- coordinates before and after inserting our full-size CanvasPanel.
local function rectangle(slot, hostW, hostH)
    local l = slot:GetLayout()
    local a, p, o = l.Anchors or l.anchors, l.Alignment or l.alignment, l.Offsets or l.offsets
    local lx, ly = xy(a.Minimum or a.minimum)
    local hx, hy = xy(a.Maximum or a.maximum)
    local ax, ay = xy(p)
    if lx ~= hx or ly ~= hy then
        return
    end
    local w, h = o.Right or o.right, o.Bottom or o.bottom
    if not finite(w) or not finite(h) or w <= 0 or h <= 0 then
        return
    end
    return lx * hostW + (o.Left or o.left) + (0.5 - ax) * w, ly * hostH + (o.Top or o.top) + (0.5 - ay) * h, w, h
end

local function readWidget(owner, key)
    local widget = owner[key]
    if valid(widget) then return widget end
end

local function optionalWidget(owner, key)
    -- Some cooked widget trees expose a named child only through the panel hierarchy.
    local ok, widget = pcall(readWidget, owner, key)
    if ok then return widget end
end

local function childCheck(parent, index, widget)
    local slot = widget.Slot
    local slotAddress, widgetAddress = slot:GetAddress(), widget:GetAddress()
    local hasContent = same(optionalWidget(slot, "Content"), widget)
    return function()
        if not valid(widget) or not valid(slot) then return false end
        local live = widget.Slot
        if not rawequal(live, slot) and (not valid(live) or live:GetAddress() ~= slotAddress) then return false end
        -- ReplaceChildAt can reuse the same slot while the outgoing widget
        -- still references it. Check which child the panel actually displays.
        local content
        if hasContent then content = slot.Content else content = parent:GetChildAt(index) end
        return rawequal(content, widget) or valid(content) and content:GetAddress() == widgetAddress
    end
end

local function neutralPanel(glyph, panelClass)
    local direct = optionalWidget(glyph, "NeutralPanel")
    if direct then
        return direct
    end
    local tree = glyph.WidgetTree
    local root = valid(tree) and tree.RootWidget
    if valid(root) and root:IsA(panelClass) then
        for i = 0, root:GetChildrenCount() - 1 do
            local child = root:GetChildAt(i)
            if valid(child) and child:GetFName():ToString():lower():match("^neutralpanel_?%d*$") then
                return child
            end
        end
    end
end

local function discover(panel, classes)
    -- Only the stock row panels receive a reciprocal artwork scale. The game
    -- continues to position their slots, select glyph styles and assign labels.
    local rows = {}
    for i = 0, panel:GetChildrenCount() - 1 do
        local w = panel:GetChildAt(i)
        if valid(w) and w:IsA(classes.panel) and valid(w.Slot) then
            local glyph, label, labelIndex
            for j = 0, w:GetChildrenCount() - 1 do
                local child = w:GetChildAt(j)
                if valid(child) then
                    if child:IsA(classes.text) then
                        if not label then label, labelIndex = child, j end
                    elseif child:IsA(classes.user) then
                        glyph = child
                    end
                end
            end
            if glyph and label and valid(label.Slot) then
                rows[#rows + 1] = {
                    w = w, slot = w.Slot, label = label,
                    inPanel = childCheck(panel, i, w), hasLabel = childCheck(w, labelIndex, label),
                    glyph = glyph, neutral = neutralPanel(glyph, classes.panel),
                }
            end
        end
    end
    if #rows == 7 then
        return rows
    end
end

local function resolvePanel(center, panelClass)
    local host = optionalWidget(center, "PitchMeterPanel")
    local altimeter = not host and optionalWidget(center, "Altimeter")
    if altimeter then
        for i = 0, altimeter:GetChildrenCount() - 1 do
            local child = altimeter:GetChildAt(i)
            if valid(child) and child:GetFName():ToString():lower():match("^pitchmeterpanel") then
                host = child
                break
            end
        end
    end
    if valid(host) then
        for i = 0, host:GetChildrenCount() - 1 do
            local child = host:GetChildAt(i)
            if valid(child) and child:IsA(panelClass) and child:GetChildrenCount() >= 7 then
                return child
            end
        end
    end
end

local function intervalOf(center)
    local ok, value = pcall(function()
        local t = center.PitchMeterSettings
        return t and (t.PitchMeterAngleInterval or t.pitchMeterAngleInterval or t.pitchmeterangleinterval)
    end)
    return ok and finite(value) and value > 0 and value <= 90 and value or 2.5
end

local function stockTape(s, fallback)
    -- The game caches its step when initializing the ring; resizing the slot
    -- later does not necessarily recalculate it. Read the regular native
    -- positions themselves, before render transforms, in any recycling order.
    local low, high = math.huge, -math.huge
    for _, row in ipairs(s.rows) do
        local _, y = xy(row.slot:GetPosition())
        if not finite(y) then
            return
        end
        row.y = y
        low, high = math.min(low, y), math.max(high, y)
    end
    local measured = (high - low) / (#s.rows - 1)
    local regular = false
    if measured > 0 then
        local seen = 0
        for _, row in ipairs(s.rows) do
            local rank = math.floor((row.y - low) / measured + 0.5)
            if math.abs(row.y - low - rank * measured) > 0.05 then
                break
            end
            seen = seen | (1 << rank)
        end
        if seen == (1 << #s.rows) - 1 then
            s.step = measured
            regular = true
        end
    end
    local step = s.step
    if not step then
        -- Wait for the first complete native layout.
        return
    end
    if not regular then
        -- A zero glyph in a partly recycled slot is an unreliable anchor for
        -- the whole ladder. Keep its last good stride and use aircraft pitch.
        return step, fallback, math.abs(fallback) <= 3 * s.interval
    end
    -- One mark is enough to read the origin of AC8's linear tape, including
    -- its smoothed flight attitude. No row is individually assigned an angle.
    for _, row in ipairs(s.rows) do
        if valid(row.neutral) and row.neutral:GetVisibility() == 4 then
            return step, row.y * s.interval / step, true
        end
    end
    for _, row in ipairs(s.rows) do
        local visible = row.label:GetVisibility()
        if visible ~= 1 and visible ~= 2 then
            local text = row.label:GetText():ToString()
            if text ~= row.text then
                row.text = text
                row.elevation = tonumber(text) or tonumber((text:gsub("−", "-"):gsub("°", ""):gsub(",", ".")))
            end
            if finite(row.elevation) then
                local pitch = row.elevation + row.y * s.interval / step
                return step, pitch, math.abs(pitch) <= 3 * s.interval
            end
        end
    end
    return step, fallback, math.abs(fallback) <= 3 * s.interval
end

local function rowTransform(row, inverseScale, turn)
    local t = row.w.RenderTransform
    local sx, sy = xy(t.Scale or t.scale)
    local a = t.Angle or t.angle
    if not close(sx, row.lastX) or not close(sy, row.lastY) then
        row.baseX, row.baseY, row.lastX, row.lastY = sx, sy, nil, nil
    end
    if not close(a, row.lastAngle) then
        row.baseAngle, row.lastAngle = a, nil
    end
    local x, y = row.baseX * inverseScale, row.baseY * inverseScale
    local target = wrap(row.baseAngle + turn)
    if not close(sx, x) or not close(sy, y) then
        row.w:SetRenderScale(vec(x, y))
        local written = row.w.RenderTransform
        row.lastX, row.lastY = xy(written.Scale or written.scale)
    end
    if not close(wrap(a - target), 0) then
        row.w:SetRenderTransformAngle(target)
        local written = row.w.RenderTransform
        row.lastAngle = written.Angle or written.angle
    end
end

local function restoreRow(row)
    if (row.lastX == nil and row.lastAngle == nil) or not valid(row.w) then
        return
    end
    local t = row.w.RenderTransform
    local sx, sy = xy(t.Scale or t.scale)
    if close(sx, row.lastX) and close(sy, row.lastY) then
        row.w:SetRenderScale(vec(row.baseX, row.baseY))
    end
    row.lastX, row.lastY = nil, nil
    if close(t.Angle or t.angle, row.lastAngle) then
        row.w:SetRenderTransformAngle(row.baseAngle)
    end
    row.lastAngle = nil
end

local function groupTransform(s, k, turn, x, y)
    local w = s.wrapper
    if not close(s.k, k) then
        w:SetRenderScale(vec(k, k))
        s.k = k
    end
    if not close(s.angle, turn) then
        w:SetRenderTransformAngle(turn)
        s.angle = turn
    end
    if not close(s.x, x) or not close(s.y, y) then
        w:SetRenderTranslation(vec(x, y))
        s.x, s.y = x, y
    end
end

return function(api, log, project)
    project = project or assert(loadfile(directory .. "pitch_projection.lua"))()(api)
    local eegs = assert(loadfile(directory .. "eegs.lua"))()(api, log)
    local chase = assert(loadfile(directory .. "third_person_ladder.lua"))()(api, project)
    local chaseActive = false
    local state, classes, lastView, lastStatus
    local waitFrames = 0
    local function report(view, message)
        if lastView ~= view or lastStatus ~= message then
            lastView, lastStatus, waitFrames = view, message, 0
        end
        if not message then return end
        waitFrames = waitFrames + 1
        if waitFrames == 60 then
            log(("Pitch ladder [%s] %s"):format(view, message))
        end
    end
    local function unmount()
        chase.reset()
        chaseActive = false
        eegs.reset()
        local s = state
        if not s then
            return
        end
        local failure
        for _, row in ipairs(s.rows) do
            local ok, why = pcall(restoreRow, row)
            if not ok then
                failure = failure or why
            end
        end
        if s.slotState and valid(s.panel) and valid(s.host) then
            local parent = s.panel:GetParent()
            if same(parent, s.wrapper) or not valid(parent) then
                if same(parent, s.wrapper) then
                    -- Preserve any layout changes authored on the live native
                    -- slot during the flight or a camera transition.
                    if s.slotState == "mounted" then
                        s.saved = snapshot(s.panel.Slot)
                    end
                    s.panel:RemoveFromParent()
                end
                s.slotState = "restoring"
                attach(s.host, s.panel)
            end
            if s.slotState == "restoring" and same(s.panel:GetParent(), s.host) then
                applyLayout(s.panel.Slot, s.saved)
                s.slotState = nil -- AC8 owns this slot again, even if a row still needs cleanup.
            end
        end
        if valid(s.wrapper) and valid(s.wrapper:GetParent()) then
            s.wrapper:RemoveFromParent()
        end
        if failure then
            error(failure, 0)
        end
        state = nil
    end
    local function reset()
        local ok, err = pcall(unmount)
        local cleared, why = true, nil
        if project.reset then
            cleared, why = pcall(project.reset)
        end
        if not ok then
            error(err, 0)
        end
        if not cleared then
            error(why, 0)
        end
        lastView, lastStatus, waitFrames = nil, nil, 0
        return true
    end

    local function mount(ctx, panel, rows)
        local host, tree = panel:GetParent(), ctx.center.WidgetTree
        assert(valid(host) and host:IsA(classes.canvas) and valid(tree), "Missing pitch panel host or widget tree")
        local s = {
            center = ctx.center,
            panel = panel,
            host = host,
            rows = rows,
            saved = snapshot(panel.Slot),
            interval = intervalOf(ctx.center),
        }
        state = s -- keep rollback information before the first layout mutation
        s.wrapper = api.StaticConstructObject(classes.canvas, tree, api.FName("None"), api.EObjectFlags.RF_Transient)
        assert(valid(s.wrapper), "Cannot construct shared pitch canvas")
        s.wrapper:SetVisibility(3) -- HitTestInvisible, as for the original instrument.
        s.wrapper:SetRenderTransformPivot(vec(0.5, 0.5))
        local slot = attach(host, s.wrapper)
        slot:SetAnchors({ Minimum = vec(0, 0), Maximum = vec(1, 1) })
        slot:SetAlignment(vec(0, 0))
        slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        slot:SetAutoSize(false)
        slot:SetZOrder(s.saved.z)
        s.slotState = "moving"
        panel:RemoveFromParent()
        applyLayout(attach(s.wrapper, panel), s.saved)
        s.slotState = "mounted"
        return s
    end

    local function current(s)
        if
            not valid(s.wrapper)
            or not valid(s.panel)
            or not same(s.wrapper:GetParent(), s.host)
            or not same(s.panel:GetParent(), s.wrapper)
        then
            return false
        end
        for _, r in ipairs(s.rows) do
            if not r.inPanel() or not r.hasLabel() then return false end
        end
        return true
    end

    local function apply(s, frame)
        local cx, cy, w, h = rectangle(s.panel.Slot, frame.width, frame.height)
        if not cx then
            return false
        end
        local step, pitch, horizon = stockTape(s, frame.pitch)
        if not step then
            return false
        end
        local x, y, dx, dy, tangent = frame:rail(pitch, s.interval, horizon)
        if not x then
            return false
        end

        local t = s.panel.RenderTransform
        local sx, sy = xy(t.Scale or t.scale)
        local shearX, shearY = xy(t.Shear or t.shear)
        local nativeAngle = t.Angle or t.angle
        local tx, ty = xy(t.Translation or t.translation)
        local px, py = xy(s.panel.RenderTransformPivot)
        if not finite(sx) or not finite(sy) or sx == 0 or sy == 0 or shearX ~= 0 or shearY ~= 0 then
            return false
        end
        local radians = math.rad(nativeAngle)
        local c, sn = math.cos(radians), math.sin(radians)
        local vx, vy = rotate(c, sn, 0, -sy * step)
        local k = math.sqrt((dx * dx + dy * dy) / (vx * vx + vy * vy))
        local turn = wrap(angle(dx, dy) - angle(vx, vy))
        if not finite(k) or k <= 0 then
            return false
        end
        local ca, sa = math.cos(math.rad(turn)), math.sin(math.rad(turn))
        local ox, oy = (px - 0.5) * w, (py - 0.5) * h
        local pivotX, pivotY = rotate(c, sn, sx * ox, sy * oy)
        local hx, hy = frame.width / 2, frame.height / 2
        local nx, ny = rotate(ca, sa, k * (cx + tx + ox - pivotX - hx), k * (cy + ty + oy - pivotY - hy))
        local ax, ay = x - hx - nx, y - hy - ny
        if not finite(ax) or not finite(ay) then
            return false
        end
        groupTransform(s, k, turn, ax, ay)
        -- Undo the shared scale on each row's artwork. The text and stroke
        -- then inherit the user's size and the native instrument styling.
        local localTangent = math.rad(tangent - turn - nativeAngle)
        local glyphTurn = angle(math.cos(localTangent) / sx, math.sin(localTangent) / sy)
        for _, row in ipairs(s.rows) do
            rowTransform(row, 1 / k, glyphTurn)
        end
        return true
    end

    local function update(ctx, settings)
        local firstPerson = ctx and (ctx.view == "cockpit" or ctx.view == "hud")
        local center = firstPerson and ctx.center
        local direct = valid(center) and optionalWidget(center, "PitchMeterCenter")
        if
            state
            and (
                not same(state.center, center)
                or direct and not same(state.panel, direct)
                or not current(state)
            )
        then
            local ok, why = pcall(reset)
            if not ok then
                log("Will retry pitch ladder cleanup: " .. tostring(why))
                return false -- The feature manager retries cleanup before the next update.
            end
        end
        if ctx and ctx.view == "thirdPerson" and settings.ChaseCockpitHUD then
            chaseActive = true
            local frame, sight = chase.update(ctx, settings)
            eegs.update(ctx, settings, frame, sight)
            return
        end
        if chaseActive then reset() end
        if not firstPerson then return end
        if not valid(center) then
            return report(ctx.view, "waiting for the flight HUD's persistent instrument widget")
        end
        if not state then
            if not classes or not valid(classes.canvas) then
                -- IsA also accepts a class path. StaticConstructObject requires a live UClass.
                local canvas = api.StaticFindObject("/Script/UMG.CanvasPanel")
                if not valid(canvas) then
                    return report(ctx.view, "waiting for the UMG canvas class")
                end
                local function classOrPath(name)
                    local path = "/Script/UMG." .. name
                    local object = api.StaticFindObject(path)
                    return valid(object) and object or path
                end
                classes = {
                    canvas = canvas,
                    panel = classOrPath("PanelWidget"),
                    text = classOrPath("TextBlock"),
                    user = classOrPath("UserWidget"),
                }
            end
            local panel = direct or resolvePanel(center, classes.panel)
            if not valid(panel) or not valid(panel.Slot) then
                return report(ctx.view, "waiting for the pitch canvas")
            end
            local rows = discover(panel, classes)
            if not rows then
                return report(ctx.view, "waiting for seven pitch rows with artwork and text")
            end
            mount(ctx, panel, rows)
        end
        local frame, reason = project.frame(ctx, state.host)
        if eegs.update(ctx, settings, frame, state) then
            report(ctx.view, nil)
            return
        end
        if not frame or not apply(state, frame) then
            -- An unavailable projection must never leave a prior camera's
            -- correction on the displayed instruments.
            groupTransform(state, 1, 0, 0, 0)
            for _, r in ipairs(state.rows) do
                restoreRow(r)
            end
        end
        -- An off-screen direction during free look is ordinary gameplay.
        -- Only a persistent missing dependency or layout merits a message.
        report(ctx.view, reason)
    end
    return { update = update, reset = reset }
end
