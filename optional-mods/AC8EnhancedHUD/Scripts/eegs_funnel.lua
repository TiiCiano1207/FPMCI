-- Continuous fire, reconstructed from launch poses. Unreal world units are cm.
local nearRange, farRange, segments = 20000, 120000, 8
local rangeStep = (farRange - nearRange) / segments
-- Stock BP_plwp_gun_x0 (also inherited by x1/x2). AC8 only applies
-- GravitationalAcceleration after the round reaches EffectiveTime.
local gravityZ, gravityDelay = -9800, 1.08
local samplePeriod, maxGap = 1 / 60, 0.35

local function drop(age)
    local fallingTime = math.max(0, age - gravityDelay)
    return 0.5 * gravityZ * fallingTime * fallingTime
end

-- A recorded launch contributes to dozens of future frames. Its world
-- velocity changes only if the player adjusts the muzzle speed.
local function setRoundVelocity(shot, speed)
    local v, f = shot.velocity, shot.forward
    shot.vx, shot.vy, shot.vz = v.x + speed * f.x, v.y + speed * f.y, v.z + speed * f.z
end

local function discontinuity(previous, sample)
    local dt = sample.time - previous.time
    if dt < 0 or dt > maxGap then return true end
    -- A world-origin shift or checkpoint jump must not leave a false stream.
    local p, q, u, v = previous.origin, sample.origin, previous.velocity, sample.velocity
    local x = (q.x - p.x) - 0.5 * (u.x + v.x) * dt
    local y = (q.y - p.y) - 0.5 * (u.y + v.y) * dt
    local z = (q.z - p.z) - 0.5 * (u.z + v.z) * dt
    return x*x + y*y + z*z > nearRange * nearRange
end

local function wingAt(start, finish, fraction)
    local x = start.x + (finish.x - start.x) * fraction
    local y = start.y + (finish.y - start.y) * fraction
    local z = start.z + (finish.z - start.z) * fraction
    local length = math.sqrt(x*x + y*y + z*z)
    if length < 1e-6 then return start.x, start.y, start.z end
    return x / length, y / length, z / length
end

return function()
    local history, first, last, previous, lastSpeed = {}, 1, 0, nil, nil
    local function reset()
        history, first, last, previous = {}, 1, 0, nil
    end

    local function update(now, sample, camera, metersPerSecond, wingspanMeters, project, drawSegment)
        local speed, halfSpan = metersPerSecond * 100, wingspanMeters * 50
        -- Allow for changes in range rate during a pull or acceleration.
        local maxAge = 2 * farRange / speed
        sample.time = now
        if previous and discontinuity(previous, sample) then reset() end
        previous = sample
        if speed ~= lastSpeed then
            for i = first, last do setRoundVelocity(history[i], speed) end
            lastSpeed = speed
        end
        if last < first or now - history[last].time >= samplePeriod - 1e-6 then
            last = last + 1
            history[last] = sample
            setRoundVelocity(sample, speed)
        elseif now == history[last].time then
            history[last] = sample
            setRoundVelocity(sample, speed)
        end
        while first < last and history[first + 1].time <= now - maxAge do
            history[first] = nil
            first = first + 1
        end

        local ox, oy, oz = sample.origin.x, sample.origin.y, sample.origin.z
        local eyeX, eyeY, eyeZ = ox - camera.x, oy - camera.y, oz - camera.z
        local station, nextRange2 = 0, nearRange * nearRange
        local lastLX, lastLY, lastRX, lastRY
        local function emit(x, y, z, wx, wy, wz)
            local lx, ly, rx, ry
            if x then
                x, y, z = x + eyeX, y + eyeY, z + eyeZ
                lx, ly = project(x - halfSpan * wx, y - halfSpan * wy, z - halfSpan * wz)
                rx, ry = project(x + halfSpan * wx, y + halfSpan * wy, z + halfSpan * wz)
            end
            if station > 0 then
                drawSegment(station, lx and lastLX, lastLY, lx, ly, rx and lastRX, lastRY, rx, ry)
            end
            lastLX, lastLY, lastRX, lastRY = lx, ly, rx, ry
            station = station + 1
            local nextRange = nearRange + station * rangeStep
            nextRange2 = nextRange * nextRange
        end

        -- A sample is one possible launch. Join consecutive impacts in 3D
        -- and intersect that stream with each range sphere, nearest first.
        local lastWing, lastX, lastY, lastZ = sample.right, 0, 0, 0
        local function cross(x, y, z, wing, rangeSquared)
            -- The start is inside the next sphere. Solve for the positive
            -- intersection fraction along the chord to this older round.
            local dx, dy, dz = x - lastX, y - lastY, z - lastZ
            local lengthSquared = dx*dx + dy*dy + dz*dz
            local along = lastX*dx + lastY*dy + lastZ*dz
            local startSquared = lastX*lastX + lastY*lastY + lastZ*lastZ
            repeat
                local discriminant = along*along + lengthSquared * (nextRange2 - startSquared)
                local fraction = (math.sqrt(discriminant) - along) / lengthSquared
                emit(lastX + fraction*dx, lastY + fraction*dy, lastZ + fraction*dz,
                    wingAt(lastWing, wing, fraction))
                if station > segments then return true end
            until rangeSquared < nextRange2
        end
        for i = last, first, -1 do
            local s = history[i]
            local age, p = now - s.time, s.origin
            local x, y, z = (p.x - ox) + s.vx * age, (p.y - oy) + s.vy * age, (p.z - oz) + s.vz * age
            if age > gravityDelay then
                local fallingTime = age - gravityDelay
                z = z + 0.5 * gravityZ * fallingTime * fallingTime
            end
            local rangeSquared = x*x + y*y + z*z
            if rangeSquared >= nextRange2 and cross(x, y, z, s.right, rangeSquared) then return end
            lastX, lastY, lastZ, lastWing = x, y, z, s.right
        end

        -- On entry there is no recorded turn before the oldest pose. Extend
        -- that pose backwards at its measured velocity and fixed gun bearing.
        -- Inherited aircraft velocity then cancels over the extra launch age.
        local oldest = history[first]
        local age = now - oldest.time
        local initialDrop = drop(age)
        local f, x0, y0, z0 = oldest.forward, lastX, lastY, lastZ
        local t = age
        while t < maxAge do
            t = math.min(t + samplePeriod, maxAge)
            local travel = speed * (t - age)
            local z = z0 + f.z * travel + drop(t) - initialDrop
            local x, y = x0 + f.x * travel, y0 + f.y * travel
            local rangeSquared = x*x + y*y + z*z
            if rangeSquared >= nextRange2 and cross(x, y, z, oldest.right, rangeSquared) then return end
            lastX, lastY, lastZ, lastWing = x, y, z, oldest.right
        end
        while station <= segments do emit(nil) end
    end
    return {update = update, reset = reset, segments = segments}
end
