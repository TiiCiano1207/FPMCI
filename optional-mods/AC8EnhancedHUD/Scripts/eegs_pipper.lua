-- Replace just the two brushes in AC8's gun widget. The replacement lives in
-- their cooked Overlay and follows the game's reticle position and fade.
local function valid(o) return o and o:IsValid() end
local function same(a, b) return valid(a) and valid(b) and a:GetAddress() == b:GetAddress() end
local function vec(x, y) return {X = x, Y = y} end
local function visible(w)
    local value = w:GetVisibility()
    return value ~= 1 and value ~= 2
end

return function(api, log)
    local state, retryOwner, lastError
    local retryFrames = 0
    local function restoreBrushes()
        for _, layer in ipairs(state.layers) do
            -- Suppress only brush drawing. AC8 owns both colour properties,
            -- including alert clears that happen on the frame EEGS exits.
            if layer.drawAs and valid(layer.image) and layer.image.Brush.DrawAs == 0 then
                local brush = layer.image.Brush
                brush.DrawAs = layer.drawAs
                layer.image:SetBrush(brush)
            end
            -- AC8 may choose NoDrawType itself while the ring is parked.
            layer.drawAs = nil
        end
    end
    local function reset()
        retryOwner, retryFrames, lastError = nil, 0, nil
        if not state then return end
        restoreBrushes()
        if valid(state.ring) then state.ring:RemoveFromParent() end
        state = nil
    end
    local function rootOf(reticle)
        local tree = valid(reticle) and reticle.WidgetTree
        return tree, valid(tree) and tree.RootWidget
    end
    local function attached(reticle, host)
        return same(reticle, state.owner) and same(host, state.host) and valid(state.ring)
            and same(state.ring:GetParent(), host)
    end
    local function suspend(reticle)
        if not state then return end
        -- A collapsed ring stays owned by UMG. Check a replaced reticle promptly
        -- and periodically release a replaced root while the sight is inactive.
        if state.idleFrames and state.idleFrames < 60 and rawequal(reticle, state.owner) then
            state.idleFrames = state.idleFrames + 1
            return
        end
        local _, host = rootOf(reticle)
        if not attached(reticle, host) then reset(); return end
        if not state.idleFrames then
            restoreBrushes()
            if state.show then state.ring:SetVisibility(2) end
            state.show = false
        end
        state.owner, state.idleFrames = reticle, 1
    end
    local function mount(reticle, tree, host)
        if not valid(host) or not host:IsA("/Script/UMG.Overlay") then return end
        local layers = {}
        for i = 0, host:GetChildrenCount() - 1 do
            local image = host:GetChildAt(i)
            if valid(image) and image:IsA("/Script/UMG.Image") then
                local name = image:GetFName():ToString()
                if name == "GunReticleBackground" then layers[1] = {image = image}
                elseif name == "GunReticleBar" then layers[2] = {image = image} end
            end
        end
        if not layers[1] or not layers[2] then return end
        local function class(name)
            local found = api.StaticFindObject("/Script/UMG." .. name)
            assert(valid(found), "Missing pipper " .. name .. " class")
            return found
        end
        local function make(kind)
            local w = api.StaticConstructObject(kind, tree, api.FName("None"), api.EObjectFlags.RF_Transient)
            assert(valid(w), "Could not construct pipper")
            return w
        end
        local imageClass = class("Image")
        local ring = make(class("CanvasPanel"))
        state = {owner = reticle, host = host, layers = layers, ring = ring, strokes = {}}
        ring:SetVisibility(2)
        local slot = host:AddChildToOverlay(ring)
        slot:SetHorizontalAlignment(0) -- Fill the overlay, keeping its original desired size.
        slot:SetVerticalAlignment(0)
        ring:SetRenderTransformPivot(vec(0.5, 0.5))
        -- The pipper stays centered on AC8's stock cue.
        local count, radius = 24, 36
        local length = 2 * radius * math.sin(math.pi / count)
        for i = 1, count do
            local a = (i - 1) * 2 * math.pi / count
            local w = make(imageClass)
            local s = ring:AddChildToCanvas(w)
            s:SetAnchors({Minimum = vec(0.5, 0.5), Maximum = vec(0.5, 0.5)})
            s:SetAlignment(vec(0, 0.5))
            s:SetPosition(vec(radius * math.cos(a), radius * math.sin(a)))
            s:SetSize(vec(length + 0.8, 5))
            w:SetRenderTransformPivot(vec(0, 0.5))
            w:SetRenderTransformAngle(math.deg(a + math.pi / 2 + math.pi / count))
            w:SetVisibility(3)
            state.strokes[i] = w
        end
    end
    local function update(reticle, centerToGun)
        local tree, host = rootOf(reticle)
        if state and not attached(reticle, host) then reset() end
        if not state then
            mount(reticle, tree, host)
            if not state then return end -- A different stock layout keeps its native pipper.
        end
        state.idleFrames = nil
        local source, alpha, sourceTint
        for _, layer in ipairs(state.layers) do
            local w = layer.image
            if not valid(w) or not same(w:GetParent(), state.host) then reset(); return end
            local brush = w.Brush
            if brush.DrawAs ~= 0 then
                layer.drawAs = brush.DrawAs
                brush.DrawAs = 0 -- ESlateBrushDrawType::NoDrawType retains desired size and tick.
                w:SetBrush(brush)
            end
            local tint = brush.TintColor
            local current = w:GetRenderOpacity()
            if tint.ColorUseRule == 0 then current = current * tint.SpecifiedColor.A end
            if layer.drawAs and visible(w) and current > 0 and (not alpha or current >= alpha) then
                source, alpha, sourceTint = w, current, tint
            end
        end
        if source then
            local transform, color = source.RenderTransform, source.ColorAndOpacity
            local scale, translation, shear = transform.Scale, transform.Translation, transform.Shear
            -- scaling.lua has applied GunReticle (and compensated for any
            -- scaled parent). Exchange that factor for Center only on our ring.
            local sx, sy = scale.X or scale.x, scale.Y or scale.y
            local tx, ty = translation.X or translation.x, translation.Y or translation.y
            local hx, hy = shear.X or shear.x, shear.Y or shear.y
            local angle = transform.Angle or transform.angle
            if sx ~= state.sx or sy ~= state.sy or tx ~= state.tx or ty ~= state.ty or angle ~= state.angle
                or hx ~= state.hx or hy ~= state.hy or centerToGun ~= state.centerToGun then
                state.ring:SetRenderTransform({Translation = vec(tx, ty), Scale = vec(sx * centerToGun, sy * centerToGun),
                    Shear = vec(hx, hy), Angle = angle})
                state.sx, state.sy, state.tx, state.ty, state.angle = sx, sy, tx, ty, angle
                state.hx, state.hy, state.centerToGun = hx, hy, centerToGun
            end
            local r, g, b, a = color.R or color.r, color.G or color.g, color.B or color.b, color.A or color.a
            if sourceTint.ColorUseRule == 0 then
                local t = sourceTint.SpecifiedColor
                r, g, b = r * t.R, g * t.G, b * t.B
            end
            if r ~= state.r or g ~= state.g or b ~= state.b or a ~= state.a then
                local tint = {R = r, G = g, B = b, A = a}
                for _, w in ipairs(state.strokes) do w:SetColorAndOpacity(tint) end
                state.r, state.g, state.b, state.a = r, g, b, a
            end
            if alpha ~= state.alpha then state.ring:SetRenderOpacity(alpha); state.alpha = alpha end
        end
        if state.show ~= (source ~= nil) then
            state.ring:SetVisibility(source and 3 or 2)
            state.show = source ~= nil
        end
    end
    return {
        update = function(reticle, centerToGun)
            if not reticle and not state then return end
            if retryFrames > 0 and same(reticle, retryOwner) then
                retryFrames = retryFrames - 1
                return
            end
            local ok, why = pcall(update, reticle, centerToGun)
            if not ok then
                local message = tostring(why)
                if message ~= lastError then log("EEGS pipper unavailable: " .. message) end
                reset()
                lastError = message
            elseif state then
                lastError, retryOwner, retryFrames = nil, nil, 0
                return true
            end
            -- Layouts can finish loading or be replaced during a flight.
            retryOwner, retryFrames = reticle, 59
        end,
        suspend = suspend, reset = reset,
    }
end
