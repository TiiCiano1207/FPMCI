-- Screen-fixed panels follow the camera. Moving panels inherit the game's
-- instrument projection and use the shared readout size within that canvas.
local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local cameraBearing = assert(loadfile(directory .. "bearing.lua"))()
local makeViewDirection = assert(loadfile(directory .. "view_direction.lua"))()
local sampleInterval = 1 / 30
local panels = {
    {key = "Speed", name = "SpeedMeterPanel", outline = "SpeedOutline"},
    {key = "Altitude", name = "AltitudeMeterPanel", outline = "AltOutline"},
    {key = "Compass", name = "CompassPanel"},
}

-- LiveLocatorWidget's forward locator skips its line draw at or above this
-- dot product (the game's single-precision cos(15 degrees), promoted to double).
local forwardDot = 0.9659258127212524
local innerDot, outerDot = math.cos(math.rad(14.5)), math.cos(math.rad(15.5))
local function noseDot(ctx, view)
    local nose = ctx.pawn:GetActorForwardVector()
    local nx, ny, nz = nose.X or nose.x, nose.Y or nose.y, nose.Z or nose.z
    assert(math.abs(nx*nx + ny*ny + nz*nz - 1) <= 0.01, "aircraft forward vector unavailable")
    local pitch, yaw = view.cameraAngles(ctx.camera)
    if pitch then
        pitch, yaw = math.rad(pitch), math.rad(yaw)
        return math.cos(pitch) * (nx * math.cos(yaw) + ny * math.sin(yaw)) + nz * math.sin(pitch)
    end
    local x, y, z = view.viewportRay(ctx)
    assert(x, "camera rotation and center viewport ray unavailable")
    return nx*x + ny*y + nz*z
end

local function layouts(view, settings, forward)
    local followed = forward and "forward" or "screen"
    if view == "cockpit" then
        return settings.FixedReadouts and followed, settings.RelativeBearing and followed
    elseif view == "hud" then
        local moving = settings.ReadoutSize ~= settings.Center and "moving"
        return settings.HUDFixedReadouts and followed or moving, settings.HUDRelativeBearing and followed or moving
    elseif view == "thirdPerson" then
        if settings.ChaseCockpitHUD then return "screen", "screen" end
        return settings.ReadoutSize ~= 1 and "moving", settings.ThirdPersonBearing and "screen"
    end
end

local function placement(key, mode, ctx, settings)
    if mode == "screen" then
        return settings[key .. "OffsetX"], settings[key .. "OffsetY"], settings.ReadoutSize
    end
    if mode == "forward" then
        local offsetKey = ctx.view == "cockpit" and ctx.glass and "Forward" .. key or key
        return settings[offsetKey .. "OffsetX"], settings[offsetKey .. "OffsetY"],
            settings.ReadoutSize / settings.Center
    end
    -- Moving HUD panels inherit the center scale as well as the native projection.
    if ctx.view == "hud" then return 0, 0, settings.ReadoutSize / settings.Center end
    return 0, 0, settings.ReadoutSize
end

local function layoutChanged(entry, key, mode, ctx, settings)
    if not entry then return false end
    local x, y, size = placement(key, mode, ctx, settings)
    return entry.x ~= x or entry.y ~= y or entry.size ~= size
end

local function valid(object)
    return object and object:IsValid()
end

local function same(a, b)
    return valid(a) and (rawequal(a, b) or valid(b) and a:GetAddress() == b:GetAddress())
end

local function xy(v)
    return {X = v.X, Y = v.Y}
end

local function snapshot(slot)
    local offsets, anchors = slot:GetOffsets(), slot:GetAnchors()
    return {
        anchors = {Minimum = xy(anchors.Minimum), Maximum = xy(anchors.Maximum)},
        alignment = xy(slot:GetAlignment()),
        offsets = {Left = offsets.Left, Top = offsets.Top, Right = offsets.Right, Bottom = offsets.Bottom},
        z = slot:GetZOrder(), auto = slot:GetAutoSize(),
    }
end

local function setLayout(slot, layout)
    slot:SetAnchors(layout.anchors)
    slot:SetAlignment(layout.alignment)
    slot:SetOffsets(layout.offsets)
    slot:SetAutoSize(layout.auto)
    slot:SetZOrder(layout.z)
end

local fill = {
    anchors = {Minimum = {X = 0, Y = 0}, Maximum = {X = 1, Y = 1}},
    alignment = {X = 0, Y = 0}, offsets = {Left = 0, Top = 0, Right = 0, Bottom = 0},
    auto = false, z = 0,
}

local function childNamed(parent, name)
    local found
    for index = 0, parent:GetChildrenCount() - 1 do
        local widget = parent:GetChildAt(index)
        if valid(widget) and widget:GetFName():ToString() == name then
            if found then return nil end
            found = widget
        end
    end
    return found
end

local function attach(canvas, widget)
    local slot = canvas:AddChildToCanvas(widget)
    assert(valid(slot) and same(widget:GetParent(), canvas), "Could not attach panel")
    return slot
end

-- AC8's alert handler writes SpeedValue directly, then recursively colours
-- images and text below Altimeter. A screen-fixed panel is outside that walk.
-- Repair only the properties that the walk would write. In particular, retain
-- brush tints, fonts and opacity. The reference also carries the clear colour.
local function readoutInk(panel, spec, classFor)
    local ink = {}
    if spec.outline then
        local outline = childNamed(panel, spec.outline)
        if valid(outline) then ink[1] = {widget = outline} end
    else
        local image, text = classFor("Image"), classFor("TextBlock")
        for _, name in ipairs({"BearingMeter", "CompassInnerPanel"}) do
            local group = childNamed(panel, name)
            if valid(group) then
                for i = 0, group:GetChildrenCount() - 1 do
                    local w = group:GetChildAt(i)
                    if w:IsA(image) then
                        ink[#ink + 1] = {widget = w}
                    elseif w:IsA(text) then
                        ink[#ink + 1] = {widget = w, text = true}
                    end
                end
            end
        end
    end
    return ink
end

local function readScreenColor(ink, center)
    local source = center.SpeedValue
    if valid(source) then
        local slate = source.ColorAndOpacity
        local c = slate.SpecifiedColor
        ink.r, ink.g, ink.b, ink.a, ink.rule = c.R, c.G, c.B, c.A, slate.ColorUseRule
        ink.slate, ink.color = slate, c
    end
    ink.read = true
end

local function syncScreenColor(entry, center, ink)
    ink = ink or {} -- Teardown can run independently of an update.
    if not ink.read then readScreenColor(ink, center) end
    if not ink.slate or (entry.red == ink.r and entry.green == ink.g and entry.blue == ink.b
        and entry.alpha == ink.a and entry.rule == ink.rule) then return end
    for _, item in ipairs(entry.ink) do
        if valid(item.widget) then
            item.widget:SetColorAndOpacity(item.text and ink.slate or ink.color)
        end
    end
    entry.red, entry.green, entry.blue, entry.alpha, entry.rule = ink.r, ink.g, ink.b, ink.a, ink.rule
end

return function(api, log)
    local mounted, retryAt, failures = {}, {}, {}
    local center, host, visibilityChain, nextSampleAt
    local lastOwner, lastView, wasCompass, wasReadouts
    local trackingForward, forward, pendingCrossing = false, false, false
    local direction, warnedDirection = makeViewDirection(api), {}
    local frame = 0
    local classes = {}
    local ink = {}
    local function classFor(kind)
        if not valid(classes[kind]) then
            classes[kind] = api.StaticFindObject("/Script/UMG." .. kind)
            assert(valid(classes[kind]), kind .. " class unavailable")
        end
        return classes[kind]
    end
    local updateBearing, suspendBearing = cameraBearing(api, log, direction, childNamed, classFor, function(parent, child, original)
        setLayout(attach(parent, child), original and snapshot(original.Slot) or fill)
    end)

    local function unmount(key)
        local entry = mounted[key]
        if not entry then return end
        if entry.moved and valid(entry.panel) and valid(entry.origin) then
            local parent = entry.panel:GetParent()
            if same(parent, entry.stockParent) or not valid(parent) then
                -- Tint is best effort during teardown. The stock panel must
                -- return to its original slot even if its colour source expired.
                if entry.mode == "screen" and valid(center) then pcall(syncScreenColor, entry, center) end
                entry.panel:RemoveFromParent()
                entry.restoring = true
                attach(entry.origin, entry.panel)
            end
            -- A second attempt can finish restoring a partially written slot.
            -- A different parent means the game has taken ownership of this panel.
            if entry.restoring and same(entry.panel:GetParent(), entry.origin) then
                setLayout(entry.panel.Slot, entry.layout)
            end
        end
        if valid(entry.holder) then entry.holder:RemoveFromParent() end
        mounted[key] = nil
    end

    local function tryUnmount(key)
        local ok, err = pcall(unmount, key)
        if not ok then
            local entry = mounted[key]
            local reason = tostring(err)
            if entry.restoreError ~= reason then log("Could not restore " .. key .. ": " .. reason) end
            entry.restoreError = reason
        end
        return ok
    end

    local function reset()
        local restored = true
        for _, spec in ipairs(panels) do
            if not tryUnmount(spec.key) then restored = false end
        end
        if restored then
            center, host, visibilityChain, nextSampleAt, lastOwner, lastView = nil, nil, nil, nil, nil, nil
            retryAt, failures = {}, {}
        end
        return restored
    end

    local function placeHolder(entry, mode)
        local screen = mode == "screen"
        local slot = attach(screen and host or entry.origin, entry.holder)
        slot:SetAnchors({Minimum = {X = 0.5, Y = 0.5}, Maximum = {X = 0.5, Y = 0.5}})
        slot:SetAlignment({X = 0.5, Y = 0.5})
        slot:SetOffsets({Left = 0, Top = 0, Right = entry.layout.offsets.Right, Bottom = entry.layout.offsets.Bottom})
        slot:SetAutoSize(false)
        slot:SetZOrder(screen and center.Slot:GetZOrder() + 1 or entry.layout.z)
        entry.mode, entry.x, entry.red = mode, nil, nil
    end

    local function mount(spec, mode)
        local origin = visibilityChain[1]
        local panel = childNamed(origin, spec.name)
        if not panel then return end
        local canvas = classFor("CanvasPanel")
        assert(panel:IsA(canvas) and valid(panel.Slot), "Unexpected panel type")
        local layout = snapshot(panel.Slot)
        assert(layout.anchors.Minimum.X == layout.anchors.Maximum.X and layout.anchors.Minimum.Y == layout.anchors.Maximum.Y
            and not layout.auto and layout.offsets.Right > 0 and layout.offsets.Bottom > 0, "Unexpected readout layout")
        local design = xy(origin.Slot:GetSize())
        assert(design.X > 0 and design.Y > 0, "Missing instrument canvas dimensions")
        -- Stock panel center relative to the instrument canvas center, before look-around and zoom.
        local anchor, offsets = layout.anchors.Minimum, layout.offsets
        local stock = {
            X = (anchor.X - 0.5) * design.X + offsets.Left + (0.5 - layout.alignment.X) * offsets.Right,
            Y = (anchor.Y - 0.5) * design.Y + offsets.Top + (0.5 - layout.alignment.Y) * offsets.Bottom,
        }

        -- NAME_None asks Unreal for a unique transient object name across reloads.
        local holder = api.StaticConstructObject(canvas, center.WidgetTree, api.FName("None"), api.EObjectFlags.RF_Transient)
        assert(valid(holder), "Could not construct readout holder")
        local entry = {holder = holder, stockParent = holder, panel = panel, origin = origin, layout = layout,
            stock = stock, design = design, mode = mode}
        mounted[spec.key] = entry
        placeHolder(entry, mode)
        holder:SetRenderTransformPivot({X = 0.5, Y = 0.5})
        holder:SetClipping(0)
        if spec.key == "Compass" and mode ~= "moving" then
            -- The game's compass keeps its original children and live slots.
            -- This extra parent lets the replacement conceal it in one operation.
            entry.stockParent = api.StaticConstructObject(canvas, center.WidgetTree, api.FName("None"), api.EObjectFlags.RF_Transient)
            assert(valid(entry.stockParent), "Could not construct stock compass layer")
            entry.stockParent:SetVisibility(3)
            setLayout(attach(holder, entry.stockParent), fill)
        end
        entry.ink = readoutInk(panel, spec, classFor)
        entry.moved = true -- Every subsequent operation can be rolled back.
        panel:RemoveFromParent()
        setLayout(attach(entry.stockParent, panel), fill)
        return entry
    end

    local function updatePanel(spec, mode, settings, visibility, opacity, ctx, sampleTime)
        local key = spec.key
        local entry = mounted[key]
        -- Cross the HUD/HMD boundary with the same panels and compass artwork.
        if entry and ((entry.mode == "screen" and mode == "forward") or (entry.mode == "forward" and mode == "screen")) then
            if mode == "forward" then
                syncScreenColor(entry, center, ink)
                suspendBearing(entry)
            end
            placeHolder(entry, mode)
        end
        if entry and entry.mode ~= mode then
            unmount(key)
            entry = nil
            retryAt[key] = nil
        end
        if not mode then return end
        local customBearing = key == "Compass" and mode == "screen"
        if customBearing and not sampleTime then return end
        if not entry then
            if frame < (retryAt[key] or 0) then return end
            retryAt[key] = frame + 30
            entry = mount(spec, mode)
            if not entry then return end
        end
        assert(valid(entry.holder) and same(entry.holder:GetParent(), mode == "screen" and host or entry.origin)
            and valid(entry.stockParent) and valid(entry.panel) and same(entry.panel:GetParent(), entry.stockParent), "Panel tree changed")
        local x, y, size = placement(key, mode, ctx, settings)
        if mode ~= "screen" then
            -- Opacity and visibility already propagate from its instrument parent.
            visibility, opacity = 3, 1
        end
        if entry.x ~= x or entry.y ~= y or entry.size ~= size then
            local spacing = ctx.view == "thirdPerson" and settings.ChaseCockpitHUD and key ~= "Compass" and 0.65 or 1
            entry.holder.Slot:SetPosition({
                X = (entry.stock.X * spacing + x / 100 * entry.design.X) * size,
                Y = (entry.stock.Y - y / 100 * entry.design.Y) * size,
            })
            entry.x, entry.y = x, y
        end
        if entry.size ~= size then
            entry.holder:SetRenderScale({X = size, Y = size})
            entry.size = size
        end
        if entry.visibility ~= visibility then
            entry.holder:SetVisibility(visibility)
            entry.visibility = visibility
        end
        if entry.opacity ~= opacity then
            entry.holder:SetRenderOpacity(opacity)
            entry.opacity = opacity
        end
        if mode == "screen" then syncScreenColor(entry, center, ink) end
        if customBearing then updateBearing(entry, ctx, sampleTime, visibility == 3 and opacity > 0) end
    end

    local function dueTime(force)
        -- Windows Lua's CRT clock measures elapsed time with millisecond precision.
        local now = api.os.clock()
        if not force and nextSampleAt and now + 0.001 < nextSampleAt then return end
        -- Preserve the cadence across frame rounding. After a hitch start fresh.
        if force or not nextSampleAt or now - nextSampleAt >= sampleInterval then nextSampleAt = now end
        nextSampleAt = nextSampleAt + sampleInterval
        return now
    end

    local function update(ctx, settings)
        local view = ctx and ctx.view
        local track = view == "cockpit" and settings.DetachForward and (settings.FixedReadouts or settings.RelativeBearing)
            or view == "hud" and settings.HUDDetachForward and (settings.HUDFixedReadouts or settings.HUDRelativeBearing)
        if not track then forward, pendingCrossing = false, false end
        local readoutMode, compassMode = layouts(view, settings, forward)
        if not (readoutMode or compassMode) or not valid(ctx.center) then
            if center then reset() end
            return
        end
        frame = frame + 1
        local owner = ctx.center
        local newOwner = not rawequal(owner, lastOwner) and not same(owner, lastOwner)
        local sampleTime = dueTime(newOwner or track ~= trackingForward or view ~= lastView
            or wasCompass ~= compassMode or wasReadouts ~= readoutMode)
        if track and sampleTime then
            local ok, dot = pcall(noseDot, ctx, direction)
            local wanted = ok and dot >= forwardDot
            -- Filter a single jitter sample at the locator boundary. A steady
            -- look still switches at 15 degrees, and a wider turn switches now.
            if ok and wanted ~= forward and dot < innerDot and dot > outerDot
                and trackingForward and view == lastView and not newOwner and not pendingCrossing then
                pendingCrossing = true
            else
                forward, pendingCrossing = wanted, false
            end
            if not ok and not warnedDirection[view] then
                warnedDirection[view] = true
                local prefix = view == "hud" and "HUD detach" or "Cockpit detach"
                log(prefix .. ": using camera follow until a valid direction is available: " .. tostring(dot))
            end
            readoutMode, compassMode = layouts(view, settings, forward)
        end
        trackingForward = track
        if wasCompass ~= compassMode then failures.Compass, retryAt.Compass = nil, nil end
        if wasReadouts ~= readoutMode then
            failures.Speed, failures.Altitude, retryAt.Speed, retryAt.Altitude = nil, nil, nil, nil
        end
        wasCompass, wasReadouts = compassMode, readoutMode
        -- The original speed/altitude widgets continue updating under their
        -- holders. Only their placement and inherited visibility need polling.
        if not sampleTime and rawequal(owner, lastOwner)
            and not layoutChanged(mounted.Speed, "Speed", readoutMode, ctx, settings)
            and not layoutChanged(mounted.Altitude, "Altitude", readoutMode, ctx, settings) then
            return
        end
        if view ~= lastView or not same(center, owner) or not same(host, owner:GetParent())
            or not same(visibilityChain[1], owner.Altimeter) then
            if not reset() then return end
            local parent = owner:GetParent()
            if not valid(parent) or parent:GetFName():ToString() ~= "WorldToScreenDrawCanvas"
                or not parent:IsA(classFor("CanvasPanel")) or not valid(owner.WidgetTree)
                or not valid(owner.Slot) then return end
            local chain = {owner.Altimeter, owner.AltimeterPanel, owner.BlurEffectBox, owner.RootPanel, owner}
            for i = 1, 5 do
                if not valid(chain[i]) then return end
            end
            if not chain[1]:IsA(classFor("CanvasPanel")) then return end
            center, host, visibilityChain = owner, parent, chain
            sampleTime = dueTime(true)
        end
        lastOwner, lastView = owner, view

        -- The holder is a sibling of the persistent HUD. Reproduce fades and
        -- hiding from its native ancestors, excluding the visor's clip wrapper.
        local visibility, opacity = 3, 1 -- ESlateVisibility::HitTestInvisible
        if readoutMode == "screen" or compassMode == "screen" and sampleTime then
            for _, ancestor in ipairs(visibilityChain) do
                if not valid(ancestor) then
                    assert(reset(), "Could not remove expired readouts")
                    return
                end
                local value = ancestor:GetVisibility()
                if value == 1 or value == 2 then visibility = 2 end
                opacity = opacity * ancestor:GetRenderOpacity()
            end
        end

        -- All detached panels mirror SpeedValue from the same HUD sample.
        ink.read, ink.slate, ink.color = false, nil, nil
        for _, spec in ipairs(panels) do
            local mode = readoutMode
            if spec.key == "Compass" then mode = compassMode end
            if not failures[spec.key] then
                local ok, err = pcall(updatePanel, spec, mode, settings, visibility, opacity, ctx, sampleTime)
                if not ok then
                    failures[spec.key] = true
                    retryAt[spec.key] = nil
                    log(spec.key .. " readout unavailable: " .. tostring(err))
                end
            end
            if failures[spec.key] and mounted[spec.key] and frame >= (retryAt[spec.key] or 0) then
                tryUnmount(spec.key)
                retryAt[spec.key] = frame + 30
            end
        end
        ink.slate, ink.color = nil, nil
    end

    return {update = update, reset = reset}
end
