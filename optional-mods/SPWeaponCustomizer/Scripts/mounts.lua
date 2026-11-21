local dir=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*[/\\])"))
local each=dofile(dir.."array_reader.lua")
-- Prepare class defaults before the aircraft is spawned, rather than changing
-- the activator after it has already built its equipped weapon instances.
return function(paths,log,modelData)
    local saved={};local loaded={};local classes={}
    local selected={}
    local lastMountLog={}
    local function valid(o)return o and o:IsValid()end
    -- A valid UObject address may have been recycled after a map change.
    local function identity(o)
        if not o then return nil end
        local ok,name=pcall(function()
            if o:IsValid() then return o:GetFullName() end
        end)
        if ok and type(name)=='string' then return name end
    end
    local function sameObject(o,name)
        return name~=nil and identity(o)==name
    end
    local function restorable(old)
        return sameObject(old.class,old.className)
            and old.className:match('^BlueprintGeneratedClass ')~=nil
    end
    local function isClass(c,path)
        if not c then return false end
        local ok,full=pcall(function()
            if not c:IsValid() then return nil end
            return c:GetFullName()
        end)
        if not ok or type(full)~='string' then return false end
        local name=path:match('([^/]+)$')
        local expected='BlueprintGeneratedClass '..path..'.'..name..'_C'
        return full:lower()==expected:lower()
    end
    local function loadClass(path)
        if isClass(classes[path],path) then return classes[path] end
        if classes[path] then
            -- A previously successful load was released during a map transition.
            -- Its old failure/retry counter must not suppress the next load.
            classes[path]=nil;loaded[path]=nil
            log('RELOAD invalidated class '..path)
        end
        local name=path:match('([^/]+)$')
        local full=path..'.'..name..'_C'
        local class
        local tries=(loaded[path] or 0)+1;loaded[path]=tries
        -- Load by registered object path; never fall back to a global UObject scan.
        -- Preserve the existing bounded retry schedule and complete class check.
        if tries==1 or tries==61 or tries==121 then
            for _,objectPath in ipairs({full,path..'.'..name}) do
                log('ASSET class request '..objectPath..' attempt='..tries..' via=registry')
                local asset,found,didLoad=LoadAsset(objectPath)
                if isClass(asset,path) then class=asset
                elseif (identity(asset) or ''):lower()==('Blueprint '..path..'.'..name):lower() then
                    -- Some registries expose the Blueprint instead of its class.
                    local ok,generated=pcall(function()return asset.GeneratedClass end)
                    if ok and isClass(generated,path) then class=generated end
                end
                log('LOAD '..objectPath..' found='..tostring(found)..' loaded='..tostring(didLoad)..' classValid='..tostring(isClass(class,path))..' via=registry')
                if isClass(class,path) then break end
            end
        end
        assert(isClass(class,path),'Expected weapon/aircraft class not loaded: '..full)
        classes[path]=class
        return class
    end
    local function modelKey(d,id)
        local key=(d.model or 'US')..':'..id
        if d.code=='PP0028_su35' and id==20 then return d.code..':'..key end
        return key
    end
    local function previewPath(d,id)
        local fallback=assert(paths.weapons[id],'No verified player weapon class for ID '..id)
        local family=d.model or 'US'
        local variants=modelData and modelData.weapons[id]
        local preferred=variants and variants[family]
        return selected[modelKey(d,id)] or preferred or fallback
    end
    local function weaponID(class)
        local defaults=class:GetCDO()
        return valid(defaults) and defaults.WeaponID
    end
    local function replacementClass(d,id)
        local fallback=assert(paths.weapons[id],'No verified player weapon class for ID '..id)
        local family=d.model or 'US'
        local preferred=modelData and modelData.weapons[id] and modelData.weapons[id][family]
        local key=modelKey(d,id)
        local path=previewPath(d,id)
        local ok,class=pcall(loadClass,path)
        if not ok and path:lower()~=fallback:lower() then
            log('MODEL fallback '..family..' weapon='..id..': preferred class unavailable')
            path=fallback;class=loadClass(path)
        elseif not ok then error(class) end
        -- The native mission constructor overwrites SpWeaponID from the weapon
        -- CDO. Use the shipped fallback if the preferred Su-35 pod advertises
        -- a different ID, so both class and selector resolve to MGP.
        if d.code=='PP0028_su35' and id==20 then
            local actual=weaponID(class)
            if actual~=id and path:lower()~=fallback:lower() then
                log('MISSION SP Su-35 preferred MGP class ID='..tostring(actual)..'; checking stock MGP')
                path=fallback;class=loadClass(path)
                actual=weaponID(class)
            end
            assert(actual==id,'Su-35 MGP class has an unexpected native weapon ID: '..tostring(actual))
        end
        if not selected[key] and modelData then
            log('MODEL '..family..' weapon='..id..' -> '..path:match('([^/]+)$')..(not preferred and ' (default fallback)' or ''))
        end
        selected[key]=path
        return class,path
    end
    -- Menu changes/resupply can follow GC of a no-longer-equipped original
    -- class. Refresh saved references by their exact registered class path
    -- before restore() borrows any configuration rows. Never relax its guards.
    local function prepareRestore(code)
        local plan={}
        local function refreshed(object,name)
            assert(type(name)=='string' and name:match('^BlueprintGeneratedClass '),
                'Saved mount is not a blueprint class')
            if sameObject(object,name) then return object end
            local path,leaf=name:match('^BlueprintGeneratedClass (.+)%.([^%.]+)$')
            assert(path and leaf==path:match('([^/]+)$')..'_C','Invalid saved mount class identity')
            local class=loadClass(path)
            assert(sameObject(class,name),'Reloaded mount class identity mismatch')
            log('RESTORE refreshed class reference '..name)
            return class
        end
        for key,e in pairs(saved) do
            if e.code==code and sameObject(e.object,e.name) then
                for _,old in pairs(e.slots) do
                    plan[#plan+1]={key=key,entry=e,old=old,
                        class=refreshed(old.class,old.className),target=refreshed(old.target,old.targetName)}
                end
            end
        end
        -- Asset loading above may invalidate earlier references. Validate the
        -- whole plan before changing even the bookkeeping used by restore().
        for _,item in ipairs(plan) do
            assert(saved[item.key]==item.entry and sameObject(item.entry.object,item.entry.name),
                'Mount owner changed while preparing mount restoration')
            assert(sameObject(item.class,item.old.className) and sameObject(item.target,item.old.targetName),
                'Mount class changed while preparing mount restoration')
        end
        for _,item in ipairs(plan) do item.old.class=item.class;item.old.target=item.target end
    end
    local function restore(code)
        for key,e in pairs(saved) do
            if not code or e.code==code then
            if sameObject(e.object,e.name) then
                each(e.object.SpecialWeaponConfigs,64,"weapon configs",function(i,row)
                    local old=e.slots[i]
                    if old then
                        if sameObject(row.WeaponClass,old.targetName) and restorable(old)
                            and row.WeaponClass:GetAddress()==old.target:GetAddress() then
                            row.WeaponClass=old.class;row.SpWeaponID=old.id
                        end
                    end
                end)
            end
            saved[key]=nil
            end
        end
    end
    -- Resolve assets before borrowing aircraft rows or weapon-config structs.
    -- The returned plan is used synchronously; it must never be kept for a later frame.
    local function resolve(d,instance)
        local plan={definition=d,code=d.code,model=d.model,instance=instance,
            ids={table.unpack(d.target)},targets={},paths={}}
        local instanceName=instance and identity(instance)
        assert(not instance or instanceName,'Aircraft instance unavailable: '..d.code)
        local changed=false;local targets={};local targetPaths={}
        for i=1,3 do
            if d.target[i]~=d.original[i] then
                changed=true
                targets[i],targetPaths[i]=replacementClass(d,d.target[i])
            end
        end
        plan.changed=changed;plan.targets=targets;plan.paths=targetPaths
        if not changed then return plan end
        local owner
        if instance then
            assert(sameObject(instance,instanceName),'Aircraft instance changed during asset loading: '..d.code)
            owner=instance
        else
            local path=assert(paths.planes[d.code],'No verified plane blueprint: '..d.code)
            local planeClass=loadClass(path)
            local default=planeClass:GetCDO()
            assert(valid(default),'Plane default object unavailable: '..d.code)
            owner=default
        end
        local object=owner.PlayerWeaponActivator
        assert(valid(object),'Plane weapon activator unavailable: '..d.code)
        -- Loading another asset can invalidate an earlier class. Validate all
        -- targets again after the last load and before any mount write.
        for i,class in pairs(targets) do
            assert(isClass(class,targetPaths[i]),'Weapon class changed during loading: '..targetPaths[i])
        end
        plan.owner=owner;plan.ownerName=assert(identity(owner))
        plan.object=object;plan.name=assert(identity(object))
        return plan
    end
    local function prepare(d,instance,prepared)
        local plan=prepared or resolve(d,instance)
        assert(plan.definition==d and plan.code==d.code and plan.model==d.model and plan.instance==instance,
            'Prepared mount plan does not match aircraft: '..d.code)
        for i=1,3 do assert(plan.ids[i]==d.target[i],'Weapon selection changed during asset loading: '..d.code) end
        if not plan.changed then return end
        local object=plan.object;local targets=plan.targets;local targetPaths=plan.paths
        assert(sameObject(plan.owner,plan.ownerName) and sameObject(object,plan.name),
            'Weapon activator owner changed after asset preparation: '..d.code)
        local current=plan.owner.PlayerWeaponActivator
        assert(sameObject(current,plan.name) and current:GetAddress()==object:GetAddress(),
            'Weapon activator replaced after asset preparation: '..d.code)
        for i,class in pairs(targets) do
            assert(isClass(class,targetPaths[i]),'Prepared weapon class changed: '..targetPaths[i])
        end
        -- No asset loading below this point. Reacquire config structs for this write only.
        local key=object:GetAddress()
        if saved[key] and not sameObject(object,saved[key].name) then saved[key]=nil end
        if saved[key] then
            local intact=true
            each(object.SpecialWeaponConfigs,64,"weapon configs",function(i,row)
                if targets[i] then
                    if not valid(row.WeaponClass) or row.WeaponClass:GetAddress()~=targets[i]:GetAddress() or row.SpWeaponID~=d.target[i] then intact=false end
                end
            end)
            if intact then return end
            saved[key]=nil
        end
        local e={object=object,name=assert(identity(object)),slots={},code=d.code};local rows={}
        each(object.SpecialWeaponConfigs,64,"weapon configs",function(i,row)
            if targets[i] then
                assert(valid(row.WeaponClass),'Original weapon class is invalid at slot '..i)
                assert(row.SpWeaponID==0 or row.SpWeaponID==d.original[i] or row.SpWeaponID==d.target[i],'Original mount ID mismatch at slot '..i)
                local originalPath=paths.weapons[d.original[i]]
                if originalPath and row.WeaponClass:GetAddress()~=targets[i]:GetAddress() then
                    local prefix=originalPath:match('(BP_plwp_.+)_..$')
                    assert(prefix and row.WeaponClass:GetFullName():lower():find(prefix:lower()..'_',1,true),'Original mount class mismatch at slot '..i)
                end
                rows[i]=row
                e.slots[i]={class=row.WeaponClass,className=identity(row.WeaponClass),id=row.SpWeaponID,target=targets[i],targetName=identity(targets[i])}
            end
        end)
        for i in pairs(targets) do assert(rows[i],'Missing weapon config slot '..i) end
        saved[key]=e
        local ok,err=pcall(function()
            for i,class in pairs(targets) do
                rows[i].WeaponClass=class
                rows[i].SpWeaponID=d.target[i]
                assert(rows[i].WeaponClass:GetAddress()==class:GetAddress() and rows[i].SpWeaponID==d.target[i],'Mount readback failed')
                local stamp=(instance and 'instance:' or 'default:')..d.code..':'..i
                if lastMountLog[stamp]~=targetPaths[i] then
                    log((instance and 'INSTANCE MOUNT ' or 'MOUNT ')..d.section..' slot='..i..' class='..class:GetFullName())
                    lastMountLog[stamp]=targetPaths[i]
                end
            end
        end)
        if not ok then
            for i,old in pairs(e.slots) do
                if restorable(old) then rows[i].WeaponClass=old.class;rows[i].SpWeaponID=old.id end
            end
            saved[key]=nil
            error(err)
        end
    end
    local function prune()
        for key,e in pairs(saved) do if not sameObject(e.object,e.name) then saved[key]=nil end end
        for path,c in pairs(classes) do
            if not isClass(c,path) then classes[path]=nil;loaded[path]=nil end
        end
    end
    log('ASSET registry weapon/aircraft loader active (2.6); global fallback disabled')
    local function defaultOwner(d)
        local path=assert(paths.planes[d.code],'No verified plane blueprint: '..d.code)
        local class=loadClass(path)
        local owner=class:GetCDO()
        assert(valid(owner) and owner:GetClass():GetAddress()==class:GetAddress(),'Resupply aircraft default identity mismatch')
        return owner
    end
    return {resolve=resolve,prepare=prepare,restore=restore,previewClass=replacementClass,previewPath=previewPath,prune=prune,defaultOwner=defaultOwner,prepareRestore=prepareRestore}
end
