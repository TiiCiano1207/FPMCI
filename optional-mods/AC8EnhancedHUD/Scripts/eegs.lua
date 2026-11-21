-- The stock gun widget owns the pipper's position, colour and visibility.
-- Draw the sight on the active instrument canvas and replace the native gun brushes.
local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local makeFunnel = assert(loadfile(directory .. "eegs_funnel.lua"))()
local makePipper = assert(loadfile(directory .. "eegs_pipper.lua"))()
-- The cooked level mark spans 608 HUD units. The other full rungs span
-- about 472. Both groups inherit the pitch host's Center scale and zoom.
local radius, halfSegments = 304, 16
local extent, stroke = 640, 5
local pi, rad, deg = math.pi, math.rad, math.deg
local arcX, arcY = {}, {}
for i = 0, halfSegments do
    local angle = pi * i / halfSegments
    arcX[i], arcY[i] = radius * math.sin(angle), radius * math.cos(angle)
end
local function vec(x, y) return {X = x, Y = y} end
local function valid(o) return o and o:IsValid() end
local function finite(n) return type(n) == "number" and math.abs(n) < math.huge end
local function same(a, b) return valid(a) and valid(b) and a:GetAddress() == b:GetAddress() end
local function exitRange(distance) return distance + distance / 10 end
local function changed(a, b) return a == nil or math.abs(a - b) > 0.02 end

-- Keep rectangular strokes in their canvas slots. All subsequent movement
-- is a paint transform, including trimming the two ends of the attitude arc.
local function line(s, x1, y1, x2, y2, overlap)
    -- An unprojectable rail starts at nil; collapse it just like a zero-length arc stroke.
    local dx, dy = 0, 0
    if x1 then dx, dy = x2 - x1, y2 - y1 end
    local lengthSquared = dx * dx + dy * dy
    local visible = lengthSquared > 0.1 * 0.1
    if s.visible ~= visible then
        s.widget:SetVisibility(visible and 3 or 2)
        s.visible = visible
    end
    if visible and (changed(s.x, x1) or changed(s.y, y1) or changed(s.ex, x2) or changed(s.ey, y2)) then
        local t = s.transform
        t.Translation.X, t.Translation.Y = x1, y1
        t.Scale.X, t.Angle = math.sqrt(lengthSquared) + (overlap or 1), deg(math.atan(dy, dx))
        s.widget:SetRenderTransform(t)
        s.x, s.y, s.ex, s.ey = x1, y1, x2, y2
    end
end

local function groupPose(group, x, y, angle)
    if changed(group.x, x) or changed(group.y, y) then
        group.widget:SetRenderTranslation(vec(x, y))
        group.x, group.y = x, y
    end
    if changed(group.angle, angle) then
        group.widget:SetRenderTransformAngle(angle)
        group.angle = angle
    end
end

local function horizon(group, pitch)
    if group.pitch and math.abs(pitch - group.pitch) < 0.015 then return end
    -- Trace both sides starting at the earthward midpoint. Each extends
    -- 90 degrees at level pitch, 180 at straight down and zero at straight up.
    local reach = rad(math.max(0, math.min(180, 90 - pitch)))
    local full = math.floor(reach * halfSegments / pi)
    local x, y = math.sin(reach), math.cos(reach)
    local tipX, tipY = radius * x, radius * y
    -- Only segments crossed by the moving tip can change. Initialize the
    -- whole arc on first paint, including the strokes that start collapsed.
    local first, last = 1, halfSegments
    if group.full then
        first = math.min(full, group.full) + 1
        last = math.min(halfSegments, math.max(full, group.full) + 1)
    end
    for i = first, last do
        local x1, y1 = tipX, tipY
        local x2, y2 = tipX, tipY
        if i <= full + 1 then x1, y1 = arcX[i - 1], arcY[i - 1] end
        if i <= full then x2, y2 = arcX[i], arcY[i] end
        line(group.left[i], -x1, y1, -x2, y2)
        line(group.right[i], x1, y1, x2, y2)
    end
    -- Short outward radial ticks terminate the arc. At either pole the ends
    -- coincide, so suppress both ticks along with the vanishing gap.
    local outer = radius
    if tipX > stroke then outer = radius + 18 end
    line(group.leftTick, -tipX, tipY, -outer * x, outer * y)
    line(group.rightTick, tipX, tipY, outer * x, outer * y)
    group.pitch, group.full = pitch, full
end

-- Copy reflected UE vectors while their owning return value is live.
local function vector(value)
    if not value then return end
    local x, y, z = value.X or value.x, value.Y or value.y, value.Z or value.z
    if finite(x) and finite(y) and finite(z) then return {x = x, y = y, z = z} end
end

local function worldSocketPose(mesh, socket)
    local transform = mesh:GetSocketTransform(socket, 0) -- RTS_World
    local q = transform.Rotation or transform.rotation
    local x, y, z, w = q.X or q.x, q.Y or q.y, q.Z or q.z, q.W or q.w
    if not finite(x) or not finite(y) or not finite(z) or not finite(w) then return end
    local norm = x*x + y*y + z*z + w*w
    if math.abs(norm - 1) > 0.01 then return end
    local origin = vector(transform.Translation or transform.translation)
    if not origin then return end
    -- Rotate the socket's local +X gun axis into world space.
    local k = 2 / norm
    return origin, {x = 1 - k*(y*y + z*z), y = k*(x*y + w*z), z = k*(x*z - w*y)}
end

return function(api, log)
    local overlay, activeTarget, lastView, aiClass
    local retry, lastError = 0, nil
    local pipper = makePipper(api, log)
    local predictor = makeFunnel()
    local gunSocket, statics, lastOriginSource, projection, visibleRails, separatePoseMesh
    local rangeOwner, originalRange, appliedRange, entryMeters, rangeError

    local function restoreGunRange()
        if valid(rangeOwner) and rangeOwner.MaxDistanceToShowGunReticle == appliedRange
            and originalRange ~= appliedRange then
            rangeOwner.MaxDistanceToShowGunReticle = originalRange
        end
        rangeOwner, originalRange, appliedRange, entryMeters = nil, nil, nil, nil
    end

    local function applyGunRange(pawn, meters)
        local owner = pawn.PlayerWeaponActivator
        if rangeOwner and not same(rangeOwner, owner) then restoreGunRange() end
        if not valid(owner) then return end
        local current = owner.MaxDistanceToShowGunReticle
        if not finite(current) then return end
        -- Preserve this aircraft's value, including a change from another writer.
        if current ~= appliedRange then originalRange = current end
        if meters ~= entryMeters then
            -- An INI entry can produce a fractional exit range. Compare at UE's float precision.
            appliedRange = string.unpack("f", string.pack("f", exitRange(meters)))
            entryMeters = meters
        end
        rangeOwner = owner
        if current ~= appliedRange then owner.MaxDistanceToShowGunReticle = appliedRange end
    end

    local function socketPose(pawn)
        local mesh = pawn.PlaneBodyMesh
        if not valid(mesh) then return end
        gunSocket = gunSocket or api.FName("SOC_Gun_01")
        -- These getters return the component pose when the socket is absent.
        if not mesh:DoesSocketExist(gunSocket) then return end
        if not separatePoseMesh or not same(separatePoseMesh, mesh) then
            local ok, origin, forward = pcall(worldSocketPose, mesh, gunSocket)
            if ok and origin then
                separatePoseMesh = nil
                return origin, forward, mesh
            end
            -- A loader can expose the individual getters without usable
            -- FTransform members. Keep tracking the gun on that mesh.
            separatePoseMesh = mesh
        end
        local origin = vector(mesh:GetSocketLocation(gunSocket))
        if not origin then return end
        local rot = mesh:GetSocketRotation(gunSocket)
        local pitch, yaw = rot.Pitch or rot.pitch, rot.Yaw or rot.yaw
        if not finite(pitch) or not finite(yaw) then return end
        pitch, yaw = rad(pitch), rad(yaw)
        local horizontal = math.cos(pitch)
        return origin, {x = horizontal * math.cos(yaw), y = horizontal * math.sin(yaw), z = math.sin(pitch)}, mesh
    end

    local function readShot(ctx, frame, right)
        if not valid(statics) then
            statics = api.StaticFindObject("/Script/Engine.Default__GameplayStatics")
            if not valid(statics) then return end
        end
        local now = statics:GetTimeSeconds(ctx.world)
        if type(now) == "table" or type(now) == "userdata" then now = now:get() end
        if not finite(now) then return end
        local camera = vector(ctx.camera:GetCameraLocation())
        local velocity = vector(ctx.pawn:GetVelocity())
        if not camera or not velocity then return end
        local ok, origin, forward, source = pcall(socketPose, ctx.pawn)
        if not ok or not origin then
            origin = vector(ctx.pawn:K2_GetActorLocation())
            if not origin then return end
            forward, source = {x = frame.nx, y = frame.ny, z = frame.nz}, ctx.pawn
        end
        return now, {origin = origin, forward = forward, right = right, velocity = velocity}, camera, source
    end

    local function resetTrajectory()
        predictor.reset()
        lastOriginSource, projection = nil, nil
    end

    local function project(dx, dy, dz)
        return projection:direction(dx, dy, dz)
    end

    local function drawSegment(i, lx1, ly1, lx2, ly2, rx1, ry1, rx2, ry2)
        local group = overlay.funnel
        -- Overlap internal joints. The exposed tips end at exactly 1,200 m.
        local overlap = i == predictor.segments and 0 or 1
        line(group.left[i], lx1, ly1, lx2, ly2, overlap)
        line(group.right[i], rx1, ry1, rx2, ry2, overlap)
        visibleRails = visibleRails or lx1 ~= nil or rx1 ~= nil
    end

    local function drawFunnel(ctx, settings, frame, right)
        local group = overlay.funnel
        local ok, now, sample, camera, source = pcall(readShot, ctx, frame, right)
        visibleRails = false
        if ok and now then
            if lastOriginSource and not same(source, lastOriginSource) then resetTrajectory() end
            lastOriginSource = source
            -- These are finite world positions. Their projections are already
            -- local to the pitch host, including its transform and Center scale.
            projection = frame
            predictor.update(now, sample, camera, settings.FunnelMuzzleSpeed, settings.FunnelWingspan, project, drawSegment)
            projection = nil
        elseif lastOriginSource then
            resetTrajectory()
        end
        if group.inView ~= visibleRails then
            group.widget:SetVisibility(visibleRails and 3 or 2)
            group.inView = visibleRails
        end
    end

    local function hide(reticle)
        if rangeOwner then restoreGunRange() end
        if overlay and overlay.active then
            if valid(overlay.ladder) then overlay.ladder:SetRenderOpacity(1) end
            if valid(overlay.root) then overlay.root:SetVisibility(2) end
            overlay.active = false
        end
        if lastOriginSource then resetTrajectory() end
        if reticle then pipper.suspend(reticle) else pipper.reset() end
        activeTarget = nil
    end

    local function detach()
        hide()
        if overlay and valid(overlay.root) then overlay.root:RemoveFromParent() end
        overlay, separatePoseMesh = nil, nil
    end

    local function mount(state)
        local tree = state.center.WidgetTree
        local canvas = api.StaticFindObject("/Script/UMG.CanvasPanel")
        local image = api.StaticFindObject("/Script/UMG.Image")
        assert(valid(canvas) and valid(image), "EEGS widget classes unavailable")
        local function make(class)
            local w = api.StaticConstructObject(class, tree, api.FName("None"), api.EObjectFlags.RF_Transient)
            assert(valid(w), "Could not construct EEGS widget")
            return w
        end
        local root = make(canvas)
        overlay = {root = root, scene = state, ladder = state.wrapper, strokes = {}}
        root:SetVisibility(2)
        local slot = state.host:AddChildToCanvas(root)
        slot:SetAnchors({Minimum = vec(0, 0), Maximum = vec(1, 1)})
        slot:SetOffsets({Left = 0, Top = 0, Right = 0, Bottom = 0})
        slot:SetAlignment(vec(0, 0))
        slot:SetAutoSize(false)
        slot:SetZOrder(state.z or state.saved.z)
        if state.rows then
            -- The cockpit bars remain live when individual pitch rows are recycled.
            for i = 0, state.host:GetChildrenCount() - 1 do
                local child = state.host:GetChildAt(i)
                if child:GetFName():ToString():lower():match("^pitchbarleft_?%d*$") and child:IsA(image) then
                    overlay.ink = child
                    break
                end
            end
        end

        local function makeStroke(parent, anchor)
            local w = make(image)
            overlay.strokes[#overlay.strokes + 1] = w
            w:SetRenderTransformPivot(vec(0, 0.5))
            local s = parent:AddChildToCanvas(w)
            s:SetAnchors({Minimum = vec(anchor, anchor), Maximum = vec(anchor, anchor)})
            s:SetAlignment(vec(0, 0.5))
            s:SetPosition(vec(0, 0))
            s:SetSize(vec(1, stroke))
            return {widget = w, transform = {Translation = vec(0, 0), Scale = vec(1, 1), Shear = vec(0, 0), Angle = 0}}
        end
        local function makeGroup(count, fill)
            local w = make(canvas)
            w:SetVisibility(3)
            w:SetRenderTransformPivot(vec(0.5, 0.5))
            local s = root:AddChildToCanvas(w)
            if fill then
                s:SetAnchors({Minimum = vec(0, 0), Maximum = vec(1, 1)})
                s:SetAlignment(vec(0, 0))
                s:SetOffsets({Left = 0, Top = 0, Right = 0, Bottom = 0})
            else
                s:SetAnchors({Minimum = vec(0, 0), Maximum = vec(0, 0)})
                s:SetAlignment(vec(0.5, 0.5))
                s:SetPosition(vec(0, 0))
                s:SetSize(vec(extent * 2, extent * 2))
            end
            local group = {widget = w, left = {}, right = {}}
            local anchor = fill and 0 or 0.5
            for i = 1, count do
                group.left[i], group.right[i] = makeStroke(w, anchor), makeStroke(w, anchor)
            end
            return group
        end
        overlay.arc, overlay.funnel = makeGroup(halfSegments, false), makeGroup(predictor.segments, true)
        overlay.arc.leftTick = makeStroke(overlay.arc.widget, 0.5)
        overlay.arc.rightTick = makeStroke(overlay.arc.widget, 0.5)
    end

    -- Our canvas is beside the ladder under the same HUD retainer. Mirror
    -- the remaining tint from the nested stock pitch widget and its artwork.
    local function palette(s, state, now)
        if s.nextTint and now >= s.lastTint and now < s.nextTint then return end
        s.lastTint, s.nextTint = now, now + 0.10
        if state.rows and not valid(s.ink) then
            for _, row in ipairs(state.rows) do
                local panel = row.neutral
                if valid(panel) then
                    for i = 0, panel:GetChildrenCount() - 1 do
                        local image = panel:GetChildAt(i)
                        if valid(image) and image:IsA("/Script/UMG.Image") then
                            s.ink, s.glyph = image, row.glyph
                            break
                        end
                    end
                end
                if valid(s.ink) then break end
            end
        end
        local rgba, brush
        if valid(s.ink) then
            rgba, brush = s.ink.ColorAndOpacity, s.ink.Brush.TintColor
        else
            -- Some HUD layouts expose the pitch labels alone.
            brush = (state.tintSource or state.rows[1].label).ColorAndOpacity
        end
        local r, g, b, a = 1, 1, 1, 1
        if rgba then r, g, b, a = rgba.R, rgba.G, rgba.B, rgba.A end
        if valid(s.glyph) then
            local tint = s.glyph.ColorAndOpacity
            r, g, b, a = r * tint.R, g * tint.G, b * tint.B, a * tint.A
        end
        -- Copy the Slate colour-use rule too, so inherited/theme colours
        -- remain live on the new strokes. No fixed green is needed.
        local t = brush.SpecifiedColor
        if r == s.r and g == s.g and b == s.b and a == s.a and brush.ColorUseRule == s.rule
            and t.R == s.br and t.G == s.bg and t.B == s.bb and t.A == s.ba then return end
        local color = {R = r, G = g, B = b, A = a}
        for _, w in ipairs(s.strokes) do
            w:SetColorAndOpacity(color)
            w:SetBrushTintColor(brush)
        end
        s.r, s.g, s.b, s.a, s.rule = r, g, b, a, brush.ColorUseRule
        s.br, s.bg, s.bb, s.ba = t.R, t.G, t.B, t.A
    end

    local function eligible(ctx, meters)
        local target = ctx.pawn:GetSelectedTarget()
        if not valid(target) then return end
        local distance = ctx.pawn:GetDistanceTo(target)
        local limit = meters * 100 -- Unreal centimetres
        if same(target, activeTarget) then limit = exitRange(limit) end
        if not finite(distance) or distance < 0 or distance > limit then return end
        if not valid(aiClass) then aiClass = api.StaticFindObject("/Script/Live.LiveAIGameObject") end
        if valid(aiClass) and target:IsA(aiClass) and target:IsAir() == true and target:IsReallyOnGround() == false then
            return target
        end
    end

    local function draw(ctx, settings, frame, state)
        local target
        if settings.EEGSMode == "automatic" then
            target = eligible(ctx, settings.EEGSRange)
            if not target then return false end
        elseif settings.EEGSMode ~= "manual" or not ctx.manualEEGS then
            return false
        end
        local chase = ctx.view == "thirdPerson"
        local x, y, upX, upY = frame:rail(frame.pitch, 1, false)
        if not x or (chase and (x < 0 or x > frame.width or y < 0 or y > frame.height)) then return false end
        if chase and not valid(ctx.reticle) then return false end
        local right = vector(ctx.pawn:GetActorRightVector())
        if not right then return false end
        local rightX, rightY = frame:direction(frame.nx + 0.01 * right.x, frame.ny + 0.01 * right.y, frame.nz + 0.01 * right.z)
        if not rightX then return false end
        local angle = math.atan(rightY - y, rightX - x)
        local pipperReady = pipper.update(ctx.reticle, chase and settings.Center or settings.Center / settings.GunReticle)
        if chase and not pipperReady then return false end
        if not overlay then mount(state) end
        -- Raise the circle along aircraft up. Its opening follows world up.
        -- The chase canvas is unscaled; the cockpit pitch host already carries Center.
        local scale = chase and settings.Center or 1
        if chase and overlay.arcScale ~= scale then
            overlay.arc.widget:SetRenderScale(vec(scale, scale))
            overlay.arcScale = scale
        end
        local height = (2 * radius) * scale * settings.EEGSCircleHeight / 100
        groupPose(overlay.arc, x + height * math.sin(angle), y - height * math.cos(angle), deg(math.atan(upX, -upY)))
        drawFunnel(ctx, settings, frame, right)
        local now = api.os.clock()
        palette(overlay, state, now)
        horizon(overlay.arc, frame.pitch)
        if chase then overlay.root:SetRenderOpacity(state.center:GetRenderOpacity()) end
        if not overlay.active then
            overlay.active = true -- Reset can unwind either visibility write.
            overlay.root:SetVisibility(3)
            -- Opacity on our wrapper keeps native descendants ticking through
            -- the alert and its clear event, even while their paint is hidden.
            if valid(overlay.ladder) then overlay.ladder:SetRenderOpacity(0) end
        end
        activeTarget = target
        local ok, why = pcall(applyGunRange, ctx.pawn, settings.EEGSRange)
        if ok then
            rangeError = nil
        elseif tostring(why) ~= rangeError then
            rangeError = tostring(why)
            log("EEGS gun reticle range unavailable: " .. rangeError)
        end
        return true
    end

    return {
        update = function(ctx, settings, frame, state)
            if ctx.view ~= lastView or (overlay and state and overlay.scene ~= state) then
                detach()
                lastView, lastError, retry = ctx.view, nil, 0
            end
            if not settings or settings.EEGSMode == "off" then hide(); return false end
            if not frame or not state then hide(ctx.reticle); return false end
            if retry > 0 then retry = retry - 1; return false end
            local ok, active = pcall(draw, ctx, settings, frame, state)
            if not ok then
                detach()
                local message = tostring(active)
                if message ~= lastError then log("EEGS unavailable: " .. message) end
                lastError, retry = message, 60
                return false
            end
            if active then lastError = nil end
            if not active then hide(ctx.reticle) end
            return active
        end,
        reset = function()
            detach()
            lastView, lastError, retry = nil, nil, 0
        end,
    }
end
