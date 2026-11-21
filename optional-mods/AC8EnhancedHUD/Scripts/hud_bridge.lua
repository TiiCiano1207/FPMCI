-- Lua supplies all arguments and results. The DLL never accesses lua_State.
return function(api, directory)
    local function entry(name)
        return assert(api.package.loadlib(directory .. "enhanced_hud.dll", "ac8hud_" .. name))
    end
    local begin, finish, read, abort = entry("begin"), entry("finish"), entry("read"), entry("abort")
    local tick, clear = entry("tick"), entry("clear")
    local sample = entry("ladder_sample")
    local writers = {}
    for i = 0, 15 do writers[i] = entry(("write_%x"):format(i)) end

    local function nibble()
        return read(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
    end
    local function response()
        local chars = {}
        while true do
            local high = nibble()
            if high == nil then break end
            local low = assert(nibble())
            chars[#chars + 1] = string.char(high * 16 + low)
        end
        return table.concat(chars)
    end

    local function request(fields)
        local request = table.concat(fields, " ")
        assert(begin(true), "HUD channel busy")
        local ok, result = pcall(function()
            for i = 1, #request do
                local byte = request:byte(i)
                writers[byte >> 4]()
                writers[byte & 15]()
            end
            assert(finish(true), "HUD request timed out")
            return response()
        end)
        if not ok then abort(); error(result, 0) end
        return result
    end

    -- Use a stable, private Lua thread as the binding owner, including when
    -- unload is dispatched by a different game-thread callback.
    local run = coroutine.wrap(function(operation, argument)
        while true do
            operation, argument = coroutine.yield(pcall(operation, argument))
        end
    end)
    local function call(operation, argument)
        local ok, result = run(operation, argument)
        if not ok then error(result, 0) end
        return result
    end
    local function project() return tick("error", "wait", "hidden", "ready") end
    local function sampleGeometry()
        local result = sample("busy", "error", "payload", "stale", "wait", "same")
        assert(result ~= "busy", "Pitch geometry channel busy")
        assert(result ~= "error", "Pitch geometry query failed")
        if result ~= "payload" then return result end
        local ok, reply = pcall(response)
        if not ok then abort(); error(reply, 0) end
        return reply
    end
    return {
        request = function(fields) return call(request, fields) end,
        sampleGeometry = function() return call(sampleGeometry) end,
        configure = function(fields)
            local reply = call(request, fields)
            assert(reply == "ok", reply)
            return true
        end,
        tick = function() return call(project) end,
        clear = function() assert(call(clear, true), "Visor cleanup busy") end,
    }
end
