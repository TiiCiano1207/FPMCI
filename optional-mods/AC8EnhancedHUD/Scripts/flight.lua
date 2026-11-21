-- Resolve the widgets from the active local flight HUD. A still-live widget
-- from a previous checkpoint can have the same name and owning controller.
local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
return function(api, log)
    local loaded, updateGlass = pcall(function()
        return assert(loadfile(directory .. "cockpit_glass.lua"))()(api, log)
    end)
    if not loaded then
        log("Glass profiles unavailable: " .. tostring(updateGlass))
        updateGlass = nil
    end
    local function valid(o) return o ~= nil and o:IsValid() end
    -- The expected object has already been validated in this tick. Reflected
    -- properties can still return fresh wrappers, including a null wrapper.
    local function references(candidate, address)
        return valid(candidate) and candidate:GetAddress() == address
    end
    local function stillBound(current, previous, previousAddress, currentAddress)
        -- All current inputs passed their liveness checks during discovery.
        -- A different wrapper at the same address needs the old serial alive.
        return rawequal(current, previous)
            or (previous:IsValid() and (currentAddress or current:GetAddress()) == previousAddress)
    end
    local function validField(o, key)
        local candidate = o[key]
        if valid(candidate) then return candidate end
    end
    local function field(o, key)
        local ok, value = pcall(validField, o, key)
        if ok then return value end
    end
    local function unwrap(item) return item:get() end

    local frame, scanAt, selectAt = 0, 0, 0
    local planes, pendingPlanes = {}, nil
    local seeded = false
    local pawn, pawnAddress, ctx, bound, viewClass, panelClass, persistentClass, userClass, views, search
    local waitingFor, waitingSince
    local planeClass = "/Script/Live.LivePlayerPlane"
    local flags = api.EObjectFlags
    local excluded = flags and (flags.RF_ClassDefaultObject | flags.RF_ArchetypeObject
        | flags.RF_BeginDestroyed | flags.RF_FinishDestroyed)
    -- Construction can precede possession. Inspect the supplied objects on the
    -- HUD tick, when the controller and its pawn can be checked together.
    pcall(api.NotifyOnNewObject, planeClass, function(plane)
        pendingPlanes = pendingPlanes or {}
        pendingPlanes[#pendingPlanes + 1] = plane
    end)

    local function localPossessor(plane, address)
        -- Keep a live, unpossessed candidate (nil) but discard a stale one (false).
        if not valid(plane) then return false end
        local pc = plane:IsPlayerControlled() and plane.Controller or nil
        if valid(pc) and pc:IsLocalController() and references(pc.Pawn, address) then
            local world = pc:GetWorld()
            if valid(world) then return pc, world end
        end
    end

    local function selectPlane()
        local found, owner, world, ambiguous, foundAddress
        for address, plane in pairs(planes) do
            local ok, pc, candidateWorld = pcall(localPossessor, plane, address)
            if not ok or pc == false then
                planes[address] = nil
            elseif pc then
                ambiguous = found ~= nil
                found, owner, world, foundAddress = plane, pc, candidateWorld, address
            end
        end
        if ambiguous then return nil, nil, nil, true end
        return found, owner, world, false, foundAddress
    end

    local planeType
    local function rememberPlane(plane)
        if not valid(plane) then return end
        if excluded and plane:HasAnyFlags(excluded) then return end
        if not valid(planeType) then planeType = api.StaticFindObject(planeClass) end
        if not valid(planeType) or not plane:IsA(planeType) then return end
        planes[plane:GetAddress()] = plane
    end

    local engine, subsystemLibrary, viewportClass
    local function refreshLocalPawns()
        scanAt = frame + 60
        -- The viewport subsystem's outer is the running engine. Its local
        -- players cover late mod loads and missed aircraft creation events.
        if not valid(engine) then
            if not valid(subsystemLibrary) then
                subsystemLibrary = api.StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
            end
            if not valid(viewportClass) then viewportClass = api.StaticFindObject("/Script/UMG.GameViewportSubsystem") end
            if not valid(subsystemLibrary) or not valid(viewportClass) then return end
            local viewport = subsystemLibrary:GetEngineSubsystem(viewportClass)
            if not valid(viewport) then return end
            engine = viewport:GetOuter()
            if not valid(engine) then return end
        end
        local instance = engine.GameInstance
        if not valid(instance) then return end
        local players = instance.LocalPlayers
        for i = 1, #players do
            local player = players[i]
            local pc = valid(player) and player.PlayerController
            if pc and valid(pc) then pcall(rememberPlane, pc.Pawn) end
        end
    end

    local function currentController()
        if not seeded then
            if frame < scanAt then return end
            refreshLocalPawns()
            seeded = true
        end
        if pendingPlanes then
            local pending = pendingPlanes
            pendingPlanes = nil
            for _, plane in ipairs(pending) do pcall(rememberPlane, plane) end
            selectAt = frame
        end
        if not pawn and frame < scanAt and not next(planes) then return end
        if pawn and frame < selectAt then
            local ok, pc, world = pcall(localPossessor, pawn, pawnAddress)
            if ok and pc then return pc, world end
        end
        -- Recheck known candidates for delayed possession or a second local
        -- owner before checking the current local players for a missed handoff.
        local previous = pawn
        local pc, world, ambiguous
        pawn, pc, world, ambiguous, pawnAddress = selectPlane()
        selectAt = frame + 60
        if not pc and not ambiguous and (previous or frame >= scanAt) then
            refreshLocalPawns()
            pawn, pc, world, ambiguous, pawnAddress = selectPlane()
        end
        return pc, world
    end

    local widgets = {WBP_ChroniclePersistent = "center", WBP_GunReticleWidget = "reticle"}
    local cameras = {cockpit = "CachedCockpitCamera", hud = "CachedFirstPersonCamera", thirdPerson = "CachedThirdPersonCamera"}
    local function ownedViewComponents()
        local result = {}
        for _, item in ipairs(pawn:K2_GetComponentsByClass(viewClass)) do
            local wrapped, view = pcall(unwrap, item)
            if not wrapped then view = item end
            if valid(view) then result[#result + 1] = view end
        end
        return result
    end
    local function activeView(pc)
        if not references(pc:GetViewTarget(), pawnAddress) then
            views = nil
            return
        end
        -- GetComponentByClass returns only the first matching component. An
        -- old component can outlive a camera switch with all its cameras off.
        if not views or frame % 60 == 15 then
            if not valid(viewClass) then viewClass = api.StaticFindObject("/Script/Live.LiveCameraViewComponent") end
            if not valid(viewClass) then views = nil; return nil, "the aircraft camera class" end
            local ok, components = pcall(ownedViewComponents)
            views = ok and components or {}
            if #views == 0 then
                local first = pawn:GetComponentByClass(viewClass)
                if valid(first) then views[1] = first end
            end
        end
        local active, activeCamera
        for _, view in ipairs(views) do
            if valid(view) and references(view:GetOwner(), pawnAddress) then
                for name, key in pairs(cameras) do
                    local camera = field(view, key)
                    if camera and camera.bIsActive then
                        if active and (active ~= name or activeCamera:GetAddress() ~= camera:GetAddress()) then
                            return nil, "a single active aircraft camera"
                        end
                        active, activeCamera = name, camera
                    end
                end
            end
        end
        if active then return active end
        return nil, "an active aircraft camera"
    end
    local function isPanel(widget)
        if not valid(panelClass) then panelClass = api.StaticFindObject("/Script/UMG.PanelWidget") end
        return widget:IsA(valid(panelClass) and panelClass or "/Script/UMG.PanelWidget")
    end
    local function widgetKey(widget)
        local key = widgets[widget:GetFName():ToString()]
        if key then return key end
        if not valid(persistentClass) then persistentClass = api.StaticFindObject("/Script/Live.LivePersistentUserWidget") end
        if valid(persistentClass) and widget:IsA(persistentClass) then return "center" end
    end
    local function refreshWidgets()
        -- Some mission HUDs expose the named blueprint fields directly. For
        -- other layouts, search the panel tree incrementally, starting at its root.
        if not search and (not ctx.widgetsChecked or frame % 60 == 30) then
            ctx.widgetsChecked = true
            search = {queue = {}, head = 1, found = {}}
            local canvas = field(ctx.hud, "WorldToScreenDrawCanvas")
            if valid(canvas) and isPanel(canvas) then
                for i = 0, canvas:GetChildrenCount() - 1 do
                    local child = canvas:GetChildAt(i)
                    local key = valid(child) and widgetKey(child)
                    if key then ctx[key], search.found[key] = child, true end
                end
            end
            for name, key in pairs(widgets) do
                local bound = not search.found[key] and field(ctx.widget, name)
                if bound then ctx[key], search.found[key] = bound, true end
            end
            if search.found.center and search.found.reticle then search = nil; return end
            local tree = field(ctx.widget, "WidgetTree")
            search.queue[1] = tree and field(tree, "RootWidget")
        end
        if not search then return end
        for _ = 1, 12 do
            local node = search.queue[search.head]
            if not node then
                for _, key in pairs(widgets) do
                    if not search.found[key] then ctx[key] = nil end
                end
                search = nil
                return
            end
            search.head = search.head + 1
            if valid(node) then
                local key = widgetKey(node)
                if key and not search.found[key] then ctx[key], search.found[key] = node, true end
                if search.found.center and search.found.reticle then search = nil; return end
                if isPanel(node) then
                    for i = 0, node:GetChildrenCount() - 1 do
                        table.insert(search.queue, node:GetChildAt(i))
                    end
                else
                    -- A nested UserWidget is a leaf in its parent's UPanel
                    -- tree. Its own root can contain the active flight canvas.
                    if not valid(userClass) then userClass = api.StaticFindObject("/Script/UMG.UserWidget") end
                    if valid(userClass) and node:IsA(userClass) then
                        local tree = field(node, "WidgetTree")
                        local root = tree and field(tree, "RootWidget")
                        if root then table.insert(search.queue, root) end
                    end
                end
            end
        end
    end

    return function(needGlass)
        frame = frame + 1
        local pc, world = currentController()
        if not pc then
            ctx = nil
            return
        end
        local camera, hud = pc.PlayerCameraManager, pc:GetHUD()
        local widget = valid(hud) and hud.HudWidget or nil
        local pcAddress = pc:GetAddress()
        if valid(world.NetDriver) or not valid(camera) or not references(camera.PCOwner, pcAddress)
            or not valid(widget) then
            ctx = nil
            return
        end
        if not ctx or not stillBound(pawn, ctx.pawn, bound.pawn, pawnAddress)
            or not stillBound(pc, ctx.pc, bound.pc, pcAddress)
            or not stillBound(world, ctx.world, bound.world) or not stillBound(camera, ctx.camera, bound.camera)
            or not stillBound(hud, ctx.hud, bound.hud) or not stillBound(widget, ctx.widget, bound.widget) then
            ctx = {pawn = pawn, pc = pc, world = world, camera = camera, hud = hud, widget = widget}
            bound = {pawn = pawnAddress, pc = pcAddress, world = world:GetAddress(), camera = camera:GetAddress(),
                hud = hud:GetAddress(), widget = widget:GetAddress()}
            views, search, waitingFor = nil, nil, nil
        end
        local reason
        ctx.view, reason = activeView(pc)
        refreshWidgets()
        if (ctx.view == "cockpit" or ctx.view == "hud") and not valid(ctx.center) then
            reason = "the central instrument widget in " .. ctx.view .. " view"
        end
        if reason ~= waitingFor then
            waitingFor, waitingSince = reason, frame
        elseif reason and waitingSince and frame - waitingSince >= 120 then
            log("Pitch ladder is waiting for " .. reason .. " on " .. ctx.widget:GetFName():ToString())
            waitingSince = nil
        end
        if updateGlass then updateGlass(ctx, frame, needGlass) end
        return ctx
    end
end
