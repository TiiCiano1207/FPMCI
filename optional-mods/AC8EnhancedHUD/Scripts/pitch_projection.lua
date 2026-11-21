local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))

local function finite(n)
    return type(n) == "number" and math.abs(n) < math.huge
end

local function screenRay(pc, x, y, origin, ray, out)
    -- Clear both spellings so a partial result cannot inherit a previous ray.
    ray.X, ray.Y, ray.Z, ray.x, ray.y, ray.z = nil, nil, nil, nil, nil, nil
    origin.X, origin.Y, origin.Z, origin.x, origin.y, origin.z = nil, nil, nil, nil, nil, nil
    if not pc:DeprojectScreenPositionToWorld(x, y, origin, ray) then return end
    -- UE4SS copies struct out-parameters into plain, case-sensitive Lua
    -- tables using the spelling in the running game's FName pool.
    local dx, dy, dz = ray.X or ray.x, ray.Y or ray.y, ray.Z or ray.z
    if not (finite(dx) and finite(dy) and finite(dz)) then return end
    out.x, out.y, out.z = dx, dy, dz
    out.ox, out.oy, out.oz = origin.X or origin.x, origin.Y or origin.y, origin.Z or origin.z
    return true
end

-- In a rectilinear view the three ray origins form two edges of the image
-- rectangle on the near plane. After scaling rays to the same normal depth,
-- their tip positions form that same rectangle. Its missing corner is b+c-a.
local function fourthRay(a, b, c, width, height, out)
    if not (finite(a.ox) and finite(a.oy) and finite(a.oz) and finite(b.ox) and finite(b.oy)
        and finite(b.oz) and finite(c.ox) and finite(c.oy) and finite(c.oz)) then return end
    local ux, uy, uz = b.ox - a.ox, b.oy - a.oy, b.oz - a.oz
    local vx, vy, vz = c.ox - a.ox, c.oy - a.oy, c.oz - a.oz
    local usq, vsq = ux*ux + uy*uy + uz*uz, vx*vx + vy*vy + vz*vz
    -- Eye-point origins, skewed samplers and poor world-coordinate precision
    -- fall back to sampling the actual fourth corner.
    if usq < 1e-12 or vsq < 1e-12 or math.abs(ux*vx + uy*vy + uz*vz) > 1e-6 * math.sqrt(usq * vsq)
        or math.abs(usq*height*height - vsq*width*width) > 1e-6 * usq*height*height then return end
    local nx, ny, nz = uy*vz - uz*vy, uz*vx - ux*vz, ux*vy - uy*vx
    local na = nx*a.x + ny*a.y + nz*a.z
    local nb = nx*b.x + ny*b.y + nz*b.z
    local nc = nx*c.x + ny*c.y + nz*c.z
    if na*nb <= 0 or na*nc <= 0 then return end
    -- Work in units where the top left ray already has the desired depth.
    local sb, sc = na/nb, na/nc
    local ex, ey, ez = b.x*sb - a.x, b.y*sb - a.y, b.z*sb - a.z
    local fx, fy, fz = c.x*sc - a.x, c.y*sc - a.y, c.z*sc - a.z
    local span = ex*ex + ey*ey + ez*ez
    if span < 1e-12 then return end
    local distance = (ux*ex + uy*ey + uz*ez) / span
    if distance <= 0 then return end
    local dux, duy, duz = ex*distance - ux, ey*distance - uy, ez*distance - uz
    local dvx, dvy, dvz = fx*distance - vx, fy*distance - vy, fz*distance - vz
    if dux*dux + duy*duy + duz*duz > usq * 1e-12 or dvx*dvx + dvy*dvy + dvz*dvz > vsq * 1e-12 then
        return
    end
    local dx, dy, dz = a.x + ex + fx, a.y + ey + fy, a.z + ez + fz
    local length = math.sqrt(dx*dx + dy*dy + dz*dz)
    if not finite(length) or length == 0 then return end
    out.x, out.y, out.z = dx/length, dy/length, dz/length
    return true
end

-- The plane through rays a and b has value zero on their screen line.
-- Scaling its normal gives it value one at the opposite corner ray.
local function plane(a, b, opposite)
    local x = a.y * b.z - a.z * b.y
    local y = a.z * b.x - a.x * b.z
    local z = a.x * b.y - a.y * b.x
    local divisor = x * opposite.x + y * opposite.y + z * opposite.z
    if math.abs(divisor) < 1e-10 then return end
    return x / divisor, y / divisor, z / divisor
end

-- Convert a world plane to components along the aircraft's horizontal
-- heading, world up and the horizontal tangent to the right of that heading.
local function components(out, x, y, z, hx, hy)
    out.horizontal, out.up, out.right = x * hx + y * hy, z, y * hx - x * hy
end

-- Samples span the central half of the viewport, so its visible edges are
-- near -0.5 and 1.5. Allow another half viewport for a partially visible HUD.
local function nearViewport(x, y)
    return x >= -1.5 and x <= 2.5 and y >= -1.5 and y <= 2.5
end

-- Project a world direction into the same local canvas used by the pitch tape.
local function direction(frame, x, y, z)
    local h, r = x * frame.hx + y * frame.hy, y * frame.hx - x * frame.hy
    local u, v, depth = frame.u, frame.v, frame.depth
    local w = depth.horizontal * h + depth.right * r + depth.up * z
    if w <= 1e-6 then return end
    local px = (u.horizontal * h + u.right * r + u.up * z) / w
    local py = (v.horizontal * h + v.right * r + v.up * z) / w
    if not nearViewport(px, py) then return end
    return frame.ox + frame.xx * px + frame.xy * py, frame.oy + frame.yx * px + frame.yy * py
end

-- A single screen-space ruler for AC8's native, equally spaced 2.5° slots.
-- Return the projected pitch origin, a vector per increasing pitch interval,
-- and the common orientation of the rung strokes, in the host's local space.
local function rail(frame, pitch, interval, horizonVisible)
    if not finite(pitch) or not finite(interval) or interval <= 0 then return end
    local p = math.rad(pitch)
    local horizontal, up = math.cos(p), math.sin(p)
    local u, v, depth = frame.u, frame.v, frame.depth
    local w = depth.horizontal * horizontal + depth.up * up
    if w <= 1e-6 then return end
    local x = (u.horizontal * horizontal + u.up * up) / w
    local y = (v.horizontal * horizontal + v.up * up) / w
    if not nearViewport(x, y) then return end
    -- Perspective pixels per radian at the aircraft nose. Along a meridian
    -- P(t) = (U_h cos(t) + U_z sin(t)) / (W_h cos(t) + W_z sin(t)).
    -- Its derivative has a constant numerator and denominator w².
    local perRadianX = (u.up * depth.horizontal - u.horizontal * depth.up) / (w*w)
    local perRadianY = (v.up * depth.horizontal - v.horizontal * depth.up) / (w*w)
    local increment = math.rad(interval)
    local tangentX, tangentY = x, y
    local w0 = depth.horizontal
    if w0 > 1e-6 then
        -- While the horizon is among the seven visible angles, fix both zero
        -- and the nose. The secant [P(p) - P(0)] / p divided by P'(p)
        -- simplifies to sinc(p) * w / w0, including its limit at p=0.
        -- Outside the seven-rung band, blend back to the local angular scale.
        -- Extrapolating from an off-screen horizon at 80° pitch blows up.
        local intervalsAway = math.abs(pitch) / interval
        local fullBand = horizonVisible and 3.5 or 3
        local blend = math.min(1, math.max(0, fullBand + 1 - intervalsAway))
        local zeroX, zeroY = u.horizontal / w0, v.horizontal / w0
        if blend > 0 and nearViewport(zeroX, zeroY) then
            local sinc = math.abs(p) < 1e-6 and 1 or up / p
            increment = increment * (1 + blend * (sinc * w / w0 - 1))
            tangentX = x + blend * (zeroX - x)
            tangentY = y + blend * (zeroY - y)
        end
    end
    -- At zero pitch the tangent is the geometric horizon. Under free look
    -- its screen direction can differ from a perpendicular to the meridian.
    local dx, dy = u.right - tangentX * depth.right, v.right - tangentY * depth.right
    local tx = frame.xx * dx + frame.xy * dy
    local ty = frame.yx * dx + frame.yy * dy
    if not finite(tx) or not finite(ty) or tx * tx + ty * ty < 1e-14 then return end
    local px = frame.ox + frame.xx * x + frame.xy * y
    local py = frame.oy + frame.yx * x + frame.yy * y
    local du, dv = increment * perRadianX, increment * perRadianY
    if math.abs(du) > 2 or math.abs(dv) > 2 then return end -- A single interval spans the entire viewport.
    local stepX, stepY = frame.xx * du + frame.xy * dv, frame.yx * du + frame.yy * dv
    if finite(px) and finite(py) and finite(stepX) and finite(stepY) and stepX*stepX + stepY*stepY > 1e-14 then
        return px, py, stepX, stepY, math.deg(math.atan(ty, tx))
    end
end

return function(api, readGeometry, clearGeometry)
    if not readGeometry then
        readGeometry, clearGeometry = assert(loadfile(directory .. "pitch_geometry.lua"))()(api)
    end
    local layout, previousPlane, lastHX, lastHY
    -- The ladder and sight consume this instance's frame synchronously.
    local origin, ray = {}, {}
    local a, b, c, d = {}, {}, {}, {}
    local result = {rail = rail, direction = direction, u = {}, v = {}, depth = {}}
    local function frame(ctx, parent)
        if not layout or not layout:IsValid() then
            layout = api.StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            if not layout or not layout:IsValid() then return nil, "viewport library unavailable" end
        end
        local size = layout:GetViewportSize(ctx.pc)
        local width, height = size.X or size.x, size.Y or size.y
        if not finite(width) or not finite(height) or width < 4 or height < 4 then return nil, "no viewport dimensions" end
        local left, right = math.floor(width * 0.25), math.floor(width * 0.75)
        local top, bottom = math.floor(height * 0.25), math.floor(height * 0.75)
        if not screenRay(ctx.pc, left, top, origin, ray, a)
            or not screenRay(ctx.pc, right, top, origin, ray, b)
            or not screenRay(ctx.pc, left, bottom, origin, ray, c) then return nil, "viewport rays unavailable" end
        if not fourthRay(a, b, c, right - left, bottom - top, d)
            and not screenRay(ctx.pc, right, bottom, origin, ray, d) then return nil, "viewport rays unavailable" end

        -- In homogeneous screen coordinates the left and top edges are u=0
        -- and v=0. The other diagonal (b,c) is u+v=1. At d both u and v
        -- equal 1, so its homogeneous depth is u+v-diagonal. The ratios
        -- recover every ray's screen position for the live perspective view.
        local ux, uy, uz = plane(a, c, d)
        local vx, vy, vz = plane(a, b, d)
        local qx, qy, qz = plane(b, c, d)
        if not (ux and vx and qx) then return nil, "degenerate viewport projection" end

        local nose = ctx.pawn:GetActorForwardVector()
        local nx, ny, nz = nose.X or nose.x, nose.Y or nose.y, nose.Z or nose.z
        if not finite(nx) or not finite(ny) or not finite(nz)
            or math.abs(nx * nx + ny * ny + nz * nz - 1) > 0.01 then return nil, "aircraft forward direction unavailable" end
        local length = math.sqrt(nx * nx + ny * ny)
        local hx, hy
        if length > 1e-6 then
            hx, hy = nx / length, ny / length
        elseif previousPlane == ctx.pawn and lastHX then
            hx, hy = lastHX, lastHY
        else
            -- Looking straight up/down has no unique horizontal bearing.
            -- At first attachment Unreal's yaw supplies the aircraft convention.
            local attitude = ctx.pawn:K2_GetActorRotation()
            local yaw = attitude.Yaw or attitude.yaw
            if not finite(yaw) then return nil, "aircraft heading unavailable at vertical pitch" end
            hx, hy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
        end
        previousPlane, lastHX, lastHY = ctx.pawn, hx, hy

        local map = readGeometry(ctx, parent)
        if not map then return nil, "waiting for pitch panel layout" end
        components(result.u, ux, uy, uz, hx, hy)
        components(result.v, vx, vy, vz, hx, hy)
        components(result.depth, ux + vx - qx, uy + vy - qy, uz + vz - qz, hx, hy)
        result.pitch, result.width, result.height = math.deg(math.atan(nz, length)), map.width, map.height
        result.hx, result.hy, result.nx, result.ny, result.nz = hx, hy, nx, ny, nz
        result.ox = map.ox + map.xx * left + map.xy * top
        result.oy = map.oy + map.yx * left + map.yy * top
        result.xx, result.xy = map.xx * (right - left), map.xy * (bottom - top)
        result.yx, result.yy = map.yx * (right - left), map.yy * (bottom - top)
        return result
    end
    local function reset()
        layout, previousPlane, lastHX, lastHY = nil, nil, nil, nil
        if clearGeometry then return clearGeometry() end
    end
    return {frame = frame, reset = reset}
end
