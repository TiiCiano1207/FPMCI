-- ============================================================================
--  AC8PropNav — UE4SS / ACE8 Mod Launcher 入口（v2.3.8）
-- ============================================================================
--  这个脚本只做一件事：
--    用 Lua 的 package.loadlib 把同目录的 AC8PropNav.dll 加载进来，
--    再调用它的导出 Ac8LuaStart()。核心会在**它自己的线程**里跑，
--    这里不做任何周期工作、不注册任何回调、不碰游戏对象。
--
--  ★ 为什么不直接调用 Ac8CoreRun：
--    Ac8CoreRun 是 void(void) 且永不返回 —— Lua 会按 lua_CFunction 解释它
--    （返回值个数未定义），而且会把 UE4SS 的 Lua 线程永久占住。
--    Ac8LuaStart 只做 CreateThread(Ac8CoreRun) 后立刻 return 0。
--
--  ★ 核心自己的日志/配置都在本目录（与 AC8PropNav.dll 同目录）：
--      AC8PropNav.log / AC8PropNav.key.log / AC8PropNav.ini
-- ============================================================================
local PREFIX = "[AC8PropNav] "

local dir = ""
do
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and type(src) == "string" then
        src = src:gsub("^@", "")
        dir = src:match("^(.*[/\\])") or ""
    end
end

print(PREFIX .. "UE4SS/ModLauncher 入口启动；DLL 目录 = " .. dir .. "\n")

local fn, err = package.loadlib(dir .. "AC8PropNav.dll", "Ac8LuaStart")
if type(fn) ~= "function" then
    print(PREFIX .. "★ package.loadlib 失败：" .. tostring(err) .. "\n")
    return
end

local ok, e = pcall(fn)
if ok then
    print(PREFIX .. "Ac8LuaStart 已调用；核心日志见同目录 AC8PropNav.log\n")
else
    print(PREFIX .. "★ Ac8LuaStart 调用异常：" .. tostring(e) .. "\n")
end
