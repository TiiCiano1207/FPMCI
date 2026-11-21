-- Bounded event logging; no UObject access, new timer, process hook or full-file hashing.
return function(dir,version,build)
    local path=dir..'../native/native-menu.log'
    local warned=false
    local bytes=0
    local previous,count,last=nil,0,0
    local function clean(value)
        local s=tostring(value):gsub('[\r\n]+',' | ')
        -- Keep error filenames/line numbers without exposing the installation path.
        s=s:gsub('%a:[/\\][^\r\n]-[/\\]([^/\\%s:]+%.lua)', '%1')
        s=s:gsub('%a:[/\\][^\r\n]-[/\\]([^/\\%s:]+%.dll)', '%1')
        return s:sub(1,1600)
    end
    -- Rotate only at startup, outside all native hooks and per-frame callbacks.
    pcall(function()
        local f=io.open(path,'rb')
        if not f then return end
        local size=f:seek('end') or 0;f:close()
        if size>4*1024*1024 then
            local backup=path..'.previous'
            os.remove(backup);os.rename(path,backup)
        end
    end)
    local function write(message)
        if bytes>=2*1024*1024 then return end
        local s=clean(message)
        local now=os.time()
        if s==previous and now-last<5 then
            count=count+1
            if count>4 then return end
        else previous=s;count=1 end
        last=now
        local line='['..os.date('!%Y-%m-%dT%H:%M:%SZ')..'] [Lua] '..s..'\n'
        local f=io.open(path,'ab')
        if f then
            local ok=f:write(line);f:close()
            if ok then bytes=bytes+#line;return end
        end
        if not warned then warned=true;print('[AC8SPWeapon] Native log is not writable; diagnostics continue in UE4SS.log\n') end
    end
    local function readLimited(file,limit)
        local f=io.open(file,'rb');if not f then return nil end
        local text=f:read(limit);f:close();return text or ''
    end
    local captured={}
    local function snapshot()
        local source=readLimited(dir..'../../../UE4SS.log',256*1024)
        if source then
            for line in source:gmatch('[^\r\n]+') do
                local detail=line:match('(UE4SS %- v.+)') or line:match('(UE4SS Build Configuration:.+)') or
                    line:match("(Starting Lua mod '[^']+')") or line:match("(Mod '[^']+' has enabled%.txt, starting mod%.)") or
                    line:match("(Mod '[^']+' disabled in mods%.txt%.)")
                if detail and not captured[detail] then captured[detail]=true;write('HOST '..detail) end
            end
        else write('HOST UE4SS.log unavailable at standard relative location') end
        local settings=readLimited(dir..'../../../UE4SS-settings.ini',64*1024)
        if settings and not captured.settings then
            captured.settings=true
            write('HOST settings source=standard-relative UE4SS-settings.ini; values recorded as written; overrides may differ')
            local wanted={bUseUObjectArrayCache=true,bForceGUObjectArrayForIteration=true,EnableHotReloadSystem=true,
                EnableAutoReloadingLuaMods=true,DefaultExecuteInGameThreadMethod=true,UseCache=true,
                InvalidateCacheIfDLLDiffers=true,DoEarlyScan=true,DefaultFNameToStringMethod=true}
            for line in settings:gmatch('[^\r\n]+') do
                local key,value=line:match('^%s*([%w_]+)%s*=%s*([^;\r\n]*)')
                if key and wanted[key] then write('HOST setting '..key..'='..value:match('^%s*(.-)%s*$'));wanted[key]=nil end
            end
            for key in pairs(wanted) do write('HOST setting '..key..'=<not specified; UE4SS default applies>') end
        end
    end
    local function safeWrite(message)pcall(write,message)end
    local function safeSnapshot()pcall(snapshot)end
    safeWrite('SESSION SPWeaponCustomizer '..version..' Lua bootstrap; log-format=3; timestamps UTC')
    safeWrite('BUILD Lua '..tostring(build or 'unspecified'))
    safeSnapshot()
    return {write=safeWrite,snapshot=safeSnapshot}
end
