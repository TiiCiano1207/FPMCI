local function finite(x) return type(x) == "number" and math.abs(x) < math.huge end

local function cameraAngles(camera)
    local rotation = camera:GetCameraRotation()
    -- AC8's reflected rotator can be a Lua table with a lowercase pitch key.
    local pitch, yaw = rotation.pitch or rotation.Pitch, rotation.Yaw or rotation.yaw
    if finite(pitch) and finite(yaw) then return pitch, yaw end
end

return function(api)
    local library
    local origin, dir = {}, {}
    local function viewportRay(ctx)
        if not library or not library:IsValid() then
            library = api.StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            if not library or not library:IsValid() then return end
        end
        local size = library:GetViewportSize(ctx.pc)
        local width, height = size.X or size.x, size.Y or size.y
        if not finite(width) or not finite(height) or width <= 0 or height <= 0 then return end
        dir.X, dir.Y, dir.Z, dir.x, dir.y, dir.z = nil, nil, nil, nil, nil, nil
        if not ctx.pc:DeprojectScreenPositionToWorld(width / 2, height / 2, origin, dir) then return end
        local x, y, z = dir.X or dir.x, dir.Y or dir.y, dir.Z or dir.z
        if finite(x) and finite(y) and finite(z) and math.abs(x*x + y*y + z*z - 1) <= 0.01 then return x, y, z end
    end
    return {
        viewportRay = viewportRay,
        cameraAngles = function(camera)
            local ok, pitch, yaw = pcall(cameraAngles, camera)
            if ok then return pitch, yaw end
        end,
    }
end
