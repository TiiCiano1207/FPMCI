-- Load the supplied upstream core once; this is not proof of in-game guidance.
local directory=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
local started=false
local M={}
function M.start()
 if started then return end
 local fn,err=package.loadlib(directory..'propnav/AC8PropNav.dll','Ac8LuaStart')
 assert(type(fn)=='function','AC8PropNav 2.3.9 load failed: '..tostring(err))
 fn()
 started=true
 print('[FPMCIPropNav] CORE_START_REQUESTED version=2.3.9; runtime validation pending\n')
end
return M
