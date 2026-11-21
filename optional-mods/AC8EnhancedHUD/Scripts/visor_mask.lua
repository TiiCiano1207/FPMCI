local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))

local function valid(object)
    return object and object:IsValid()
end

local function same(a, b)
    return valid(a) and valid(b) and a:GetAddress() == b:GetAddress()
end

local function xy(v)
    return { X = v.X, Y = v.Y }
end

local function snapshot(slot)
    local offsets, anchors = slot:GetOffsets(), slot:GetAnchors()
    return {
        offsets = { Left = offsets.Left, Top = offsets.Top, Right = offsets.Right, Bottom = offsets.Bottom },
        anchors = { Minimum = xy(anchors.Minimum), Maximum = xy(anchors.Maximum) },
        alignment = xy(slot:GetAlignment()),
        auto = slot:GetAutoSize(),
        z = slot:GetZOrder(),
    }
end

local function layout(slot, saved)
    assert(valid(slot), "Missing visor canvas slot")
    slot:SetAnchors(saved.anchors)
    slot:SetAlignment(saved.alignment)
    slot:SetOffsets(saved.offsets)
    slot:SetAutoSize(saved.auto)
    slot:SetZOrder(saved.z)
end

local reflection = assert(loadfile(directory .. "hud_reflection.lua"))()

return function(api, log, injectedNative)
    local mask = {}
    local state, flight, failedCenter, native, cleanupPending
    local function find(path)
        local object = api.StaticFindObject(path)
        assert(valid(object), "Missing visor dependency " .. path)
        return object
    end

    local function detach()
        if not state then
            return
        end
        local s = state
        if s.bound then
            native.clear()
            s.bound = false
        end
        if s.moved and valid(s.retainer) and valid(s.root) then
            local parent = s.retainer:GetParent()
            if same(parent, s.content) or not valid(parent) then
                s.restoring = true
                if valid(parent) then
                    s.retainer:RemoveFromParent()
                end
                s.root:AddChildToCanvas(s.retainer)
                assert(same(s.retainer:GetParent(), s.root), "Could not restore original HUD retainer")
            end
            if s.restoring and same(s.retainer:GetParent(), s.root) then
                layout(s.retainer.Slot, s.layout)
            end
        end
        if valid(s.wrapper) then
            s.wrapper:RemoveFromParent()
        end
        state = nil
    end

    function mask.reset()
        local ok, err = pcall(detach)
        if ok then
            flight, failedCenter, cleanupPending = nil, nil, false
        else
            if not cleanupPending then log("Visor cleanup failed: " .. tostring(err)) end
            cleanupPending = true
        end
        return ok
    end

    local function mount(ctx)
        local center = ctx.center
        local root, retainer, tree = center.RootPanel, center.BlurEffectBox, center.WidgetTree
        assert(
            valid(root) and valid(retainer) and valid(tree) and same(retainer:GetParent(), root),
            "Unexpected center HUD hierarchy"
        )
        assert(
            root:IsA("/Script/UMG.CanvasPanel") and retainer:IsA("/Script/UMG.RetainerBox"),
            "Unexpected visor parent classes"
        )
        local metadata = reflection(api, find)
        native = native or injectedNative or assert(loadfile(directory .. "hud_bridge.lua"))()(api, directory)
        local canvas = find("/Script/UMG.CanvasPanel")
        local slate = find("/Script/UMG.Default__SlateBlueprintLibrary")
        local profile = ctx.glass.profile
        local s = {
            glass = ctx.glass,
            root = root,
            retainer = retainer,
            center = center,
            layout = snapshot(retainer.Slot),
            edges = {},
            wait = 0,
        }
        state = s

        local function panel(name)
            local widget = api.StaticConstructObject(canvas, tree, api.FName("None"), api.EObjectFlags.RF_Transient)
            assert(valid(widget), "Could not create visor " .. name)
            widget:SetVisibility(3) -- HitTestInvisible
            widget:SetRenderTransformPivot({ X = 0, Y = 0 })
            return widget
        end
        local function attach(parent, child)
            local slot = parent:AddChildToCanvas(child)
            assert(valid(slot) and same(child:GetParent(), parent), "Could not attach visor panel")
            return slot
        end
        s.wrapper = panel("Root")
        layout(attach(root, s.wrapper), {
            anchors = { Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } },
            alignment = { X = 0, Y = 0 },
            offsets = { Left = 0, Top = 0, Right = 0, Bottom = 0 },
            auto = false,
            z = s.layout.z,
        })
        local parent = s.wrapper
        for i = 1, #profile.points do
            local edge = panel("Edge" .. i)
            local slot = attach(parent, edge)
            slot:SetPosition({ X = 0, Y = 0 })
            slot:SetSize({ X = 1024, Y = 1024 })
            slot:SetAutoSize(false)
            edge:SetClipping(0)
            s.edges[i], parent = edge, edge
        end
        s.content = panel("Content")
        local contentSlot = attach(parent, s.content)
        contentSlot:SetPosition({ X = 0, Y = 0 })
        contentSlot:SetSize({ X = 3840, Y = 2160 })
        contentSlot:SetAutoSize(false)

        local values = { "mask6", tostring(#s.edges), tostring(profile.firstPaneSize or #s.edges) }
        local function pointer(o)
            values[#values + 1] = ("%x"):format(o:GetAddress())
        end
        pointer(metadata.serialLibrary)
        pointer(metadata.serialFunction[1])
        pointer(metadata.serialFunction[2])
        for _, object in ipairs({ root, s.wrapper, s.content, contentSlot, ctx.world, ctx.pc, ctx.glass.mesh, slate }) do
            pointer(object)
        end
        for _, edge in ipairs(s.edges) do
            pointer(edge)
        end
        for _, fn in ipairs(metadata) do
            for _, member in ipairs(fn) do pointer(member) end
        end
        values[#values + 1] = ("%x"):format(api.FName(profile.bone):GetComparisonIndex())
        for _, point in ipairs(profile.points) do
            values[#values + 1] = ("%.7f %.7f %.7f"):format(point[1], point[2], point[3])
        end
        native.configure(values)
        s.bound = true
        s.moved = true
        retainer:RemoveFromParent()
        layout(attach(s.content, retainer), s.layout)
    end

    local function update(ctx, enabled)
        if not enabled or not ctx or not ctx.glass or ctx.view ~= "cockpit" or not valid(ctx.center) then
            detach()
            flight, failedCenter = nil, nil
            return
        end
        if flight ~= ctx then
            detach()
            flight = ctx
            failedCenter = nil
        end
        if same(failedCenter, ctx.center) then
            return
        end
        if
            state
            and (
                state.glass ~= ctx.glass
                or not same(state.center, ctx.center)
                or not same(state.root, ctx.center.RootPanel)
                or not same(state.retainer, ctx.center.BlurEffectBox)
                or not same(state.retainer:GetParent(), state.content)
            )
        then
            detach()
        end
        if not state then
            mount(ctx)
        end
        local status = native.tick()
        assert(status == "ready" or status == "hidden" or status == "wait", "Native visor projection failed")
        if status == "wait" then
            state.wait = state.wait + 1
            assert(state.wait <= 120, "Visor geometry did not become ready")
        else
            state.wait = 0
        end
    end

    function mask.update(ctx, enabled)
        if cleanupPending then
            if not pcall(detach) then return end
            cleanupPending = false
        end
        local ok, err = pcall(update, ctx, enabled)
        if not ok then
            mask.reset()
            -- Keep a failed HUD suppressed while a busy cleanup is retried.
            if ctx then
                flight, failedCenter = ctx, ctx.center
            end
            log("Visor mask unavailable: " .. tostring(err))
        end
    end
    return mask
end
