-- A transient pitch tape for the chase camera. The native cockpit widgets
-- stay in their original tree. Both views use the same live camera projection.
return function(api, project)
    local layer, sight, rows
    local function valid(w) return w and w:IsValid() end
    local function reset()
        if valid(layer) then layer:RemoveFromParent() end
        layer, sight, rows = nil, nil, nil
    end
    local function build(center, parent)
        local tree = center.WidgetTree
        local function widget(kind)
            local class = api.StaticFindObject("/Script/UMG." .. kind)
            assert(valid(class), kind .. " unavailable")
            local w = api.StaticConstructObject(class, tree, api.FName("None"), api.EObjectFlags.RF_Transient)
            assert(valid(w), "Cannot create chase HUD " .. kind)
            return w
        end
        layer, rows = widget("CanvasPanel"), {}
        sight = {center = center, host = parent, z = center.Slot:GetZOrder(), tintSource = center.SpeedValue}
        layer:SetVisibility(2)
        local slot = parent:AddChildToCanvas(layer)
        slot:SetAnchors({Minimum={X=0,Y=0}, Maximum={X=1,Y=1}})
        slot:SetAlignment({X=0,Y=0})
        slot:SetOffsets({Left=0,Top=0,Right=0,Bottom=0})
        slot:SetZOrder(sight.z)
        for i = 1, 7 do
            local label = widget("TextBlock")
            label:SetFont(center.SpeedValue.Font)
            local s = layer:AddChildToCanvas(label)
            s:SetAnchors({Minimum={X=0,Y=0},Maximum={X=0,Y=0}})
            s:SetAlignment({X=0.5,Y=0.5})
            s:SetAutoSize(true)
            label:SetRenderTransformPivot({X=0.5,Y=0.5})
            rows[i] = {label=label,slot=s}
        end
    end
    local function update(ctx, settings)
        local center = ctx.center
        local parent = valid(center) and center:GetParent()
        if not valid(parent) or parent:GetFName():ToString() ~= "WorldToScreenDrawCanvas"
            or not valid(center.SpeedValue) or not valid(center.Slot) then reset(); return end
        if not sight or not valid(layer) or not valid(sight.host) or not valid(sight.center)
            or parent:GetAddress() ~= sight.host:GetAddress() or center:GetAddress() ~= sight.center:GetAddress() then
            reset(); build(center, parent)
        end
        sight.tintSource = center.SpeedValue
        local frame = project.frame(ctx, parent)
        local x,y,dx,dy,angle
        if frame then x,y,dx,dy,angle = frame:rail(frame.pitch,5,math.abs(frame.pitch)<12.5) end
        local visibility = center:GetVisibility()
        if not x or visibility == 1 or visibility == 2 or x<0 or x>frame.width or y<0 or y>frame.height then
            layer:SetVisibility(2); return
        end
        -- The chase camera supplies direction and bank; use cockpit instrument
        -- spacing for the tape (about 58 pixels per half-step at 1600p).
        local interval = 2.5
        local length = math.sqrt(dx*dx + dy*dy)
        if length < 1e-6 then layer:SetVisibility(2); return end
        local gap = frame.height * (58 / 1600)
        dx,dy = dx/length*gap, dy/length*gap
        local middle = math.floor(frame.pitch / interval + 0.5)
        local scale = settings.Center
        local tint = center.SpeedValue.ColorAndOpacity
        for i,row in ipairs(rows) do
            local tick = middle + i - 4
            local pitch = tick * interval
            local steps = (pitch-frame.pitch)/interval
            local px,py = x+steps*dx,y+steps*dy
            if math.abs(pitch)>90 or px<0 or px>frame.width or py<0 or py>frame.height then
                row.label:SetVisibility(2)
            else
                if row.pitch ~= pitch then
                    local glyph
                    if tick % 2 == 0 then
                        local n = ("%d"):format(pitch)
                        local line = pitch < 0 and "- -" or "──"
                        glyph = n.." "..line.."            "..line.." "..n
                    else
                        glyph = "─            ─"
                    end
                    row.label:SetText(api.FText(glyph))
                    row.pitch=pitch
                end
                row.label:SetRenderScale({X=scale,Y=scale})
                row.label:SetColorAndOpacity(tint)
                row.slot:SetPosition({X=px,Y=py})
                row.label:SetRenderTransformAngle(angle)
                row.label:SetVisibility(3)
            end
        end
        layer:SetRenderOpacity(center:GetRenderOpacity())
        layer:SetVisibility(3)
        return frame, sight
    end
    return {update=update, reset=reset}
end
