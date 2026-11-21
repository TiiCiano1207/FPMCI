local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local reflection = assert(loadfile(directory .. "hud_reflection.lua"))()
local makeBridge = assert(loadfile(directory .. "hud_bridge.lua"))()
local components = {"width", "height", "ox", "oy", "xx", "xy", "yx", "yy"}

-- FGeometry is opaque in UE4SS Lua. Let Slate convert three screen points
-- using the same native parameter checks as the visor, including with no glass.
return function(api)
    local bridge, panel, world, map
    local function clear()
        if panel then
            local reply = bridge.request({"ladderClear"})
            assert(reply == "ok", reply)
        end
        panel, world, map = nil, nil, nil
    end
    local function find(path)
        local o = api.StaticFindObject(path)
        assert(o and o:IsValid(), "Missing pitch geometry dependency " .. path)
        return o
    end
    local function read(ctx, widget)
        if not panel or not panel:IsValid() or (not rawequal(panel, widget) and panel:GetAddress() ~= widget:GetAddress())
            or not world:IsValid() or (not rawequal(world, ctx.world) and world:GetAddress() ~= ctx.world:GetAddress()) then
            clear()
            bridge = bridge or makeBridge(api, directory)
            local meta = reflection(api, find, true)
            local fields = {"ladderGeometry1"}
            local function add(object) fields[#fields + 1] = ("%x"):format(object:GetAddress()) end
            add(meta.serialLibrary)
            add(meta.serialFunction[1])
            add(meta.serialFunction[2])
            add(widget)
            add(ctx.world)
            add(find("/Script/UMG.Default__SlateBlueprintLibrary"))
            for _, fn in ipairs(meta) do
                for _, obj in ipairs(fn) do add(obj) end
            end
            local reply = bridge.request(fields)
            assert(reply == "ok", reply)
            panel, world = widget, ctx.world
        end
        local reply = bridge.sampleGeometry()
        if reply == "stale" then clear(); return end
        if reply == "wait" then return end
        if #reply == 64 then
            local w, h, ox, oy, xx, xy, yx, yy = string.unpack("<dddddddd", reply)
            map = map or {}
            map.width, map.height, map.ox, map.oy = w, h, ox, oy
            map.xx, map.xy, map.yx, map.yy = xx, xy, yx, yy
        elseif reply ~= "same" then
            assert(map and #reply % 8 == 1 and #reply <= 57, reply)
            local mask, offset = reply:byte(), 2
            for i, name in ipairs(components) do
                if mask & (1 << (i - 1)) ~= 0 then
                    map[name], offset = string.unpack("<d", reply, offset)
                end
            end
            assert(offset == #reply + 1, "Invalid pitch geometry delta")
        end
        return map
    end
    return read, clear
end
