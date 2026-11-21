-- Resupply reuses the live player aircraft. Prepare its three configuration
-- records before the game's own refill/rearm flow; never edit equipped instances.
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
local each=dofile(dir..'array_reader.lua')
return function(mounts,paths,log)
    local function identity(o)
        local ok,name=pcall(function()if o and o:IsValid() then return o:GetFullName() end end)
        return ok and type(name)=='string' and name or nil
    end
    local function same(o,name)return name and identity(o)==name end
    local function expectedClass(d)
        local path=assert(paths.planes[d.code],'No verified aircraft blueprint')
        return 'BlueprintGeneratedClass '..path..'.'..path:match('([^/]+)$')..'_C'
    end
    local function playerMatches(d,actor)
        local name=identity(actor)
        if not name or name:find('Default__',1,true) then return false end
        if identity(actor:GetClass())~=expectedClass(d) then return false end
        local world=actor:GetWorld()
        return identity(world)~=nil and not identity(world.NetDriver)
    end
    local function capture(d,actor)
        assert(playerMatches(d,actor),'Resupply player aircraft does not match the selection')
        local object=actor.PlayerWeaponActivator
        local s={definition=d,actor=actor,actorName=assert(identity(actor)),
            object=object,name=assert(identity(object),'Resupply player activator unavailable'),slots={}}
        each(object.SpecialWeaponConfigs,64,'resupply player configs',function(i,row)
            if i<=3 then
                local name=assert(identity(row.WeaponClass),'Resupply source weapon class unavailable')
                assert(name:match('^BlueprintGeneratedClass '),'Resupply source is not a weapon blueprint class')
                s.slots[i]={class=row.WeaponClass,name=name,id=row.SpWeaponID}
            end
        end)
        for i=1,3 do assert(s.slots[i],'Resupply player configuration is incomplete') end
        return s
    end
    local function live(s)
        assert(same(s.actor,s.actorName) and playerMatches(s.definition,s.actor),'Resupply player aircraft changed')
        local current=s.actor.PlayerWeaponActivator
        assert(same(s.object,s.name) and same(current,s.name) and current:GetAddress()==s.object:GetAddress(),
            'Resupply player activator changed')
        return s.object
    end
    local function write(s,values)
        local object=live(s);local rows={}
        for i=1,3 do assert(values[i] and same(values[i].class,values[i].name),'Resupply weapon class changed before write') end
        each(object.SpecialWeaponConfigs,64,'resupply player configs',function(i,row)if i<=3 then rows[i]=row end end)
        for i=1,3 do assert(rows[i],'Resupply player configuration changed') end
        -- All asset preparation and validation is complete. No engine lookups or
        -- asset loads are allowed while these borrowed config records are used.
        for i=1,3 do
            rows[i].WeaponClass=values[i].class;rows[i].SpWeaponID=values[i].id
            assert(rows[i].WeaponClass:GetAddress()==values[i].class:GetAddress() and rows[i].SpWeaponID==values[i].id,
                'Resupply mount readback failed')
        end
    end
    local function restore(s)write(s,s.slots)end
    local function synchronize(d,s)
        -- A continued mission can recreate native class defaults while the
        -- parameter table and saved slot IDs still match the selected plan.
        -- Even an unchanged selection must prepare the actual default classes
        -- before they are copied to the live aircraft for the stock rearm flow.
        local plan=mounts.resolve(d)
        mounts.prepare(d,nil,plan)
        local owner=plan.owner or mounts.defaultOwner(d)
        local source=owner.PlayerWeaponActivator
        local sourceName=assert(identity(source),'Resupply default activator unavailable')
        live(s)
        assert(same(source,sourceName),'Resupply default activator changed')
        if plan.changed then
            assert(same(owner,plan.ownerName) and same(source,plan.name)
                and source:GetAddress()==plan.object:GetAddress(),
                'Resupply prepared default activator changed')
        end
        local values,classNames={},{}
        each(source.SpecialWeaponConfigs,64,'resupply default configs',function(i,row)
            if i<=3 then
                local name=assert(identity(row.WeaponClass),'Resupply prepared class unavailable')
                assert(name:match('^BlueprintGeneratedClass '),'Resupply prepared value is not a blueprint class')
                assert(row.SpWeaponID==0 or row.SpWeaponID==d.target[i],'Resupply prepared weapon ID mismatch')
                if plan.targets[i] then
                    assert(same(row.WeaponClass,identity(plan.targets[i]))
                        and row.WeaponClass:GetAddress()==plan.targets[i]:GetAddress(),
                        'Resupply prepared weapon class mismatch at slot '..i)
                end
                -- Zero is an uninitialized class-default ID. The initial
                -- aircraft setup resolves it from WeaponClass's default, but
                -- returning from resupply reuses the live records. Keep every
                -- live ID explicit, including unchanged original weapons.
                values[i]={class=row.WeaponClass,name=name,id=d.target[i]}
                classNames[i]=name:match('([^/]+)$')
            end
        end)
        write(s,values)
        log('RESUPPLY live mount configs prepared '..d.section..' slots='..table.concat(d.target,',')
            ..' classes='..table.concat(classNames,','))
    end
    local function wrap(apply,findPlayer)
        return function(d,target,context)
            if context~='resupply' then return apply(d,target) end
            local actor=assert(findPlayer(d),'No unique active local player aircraft for resupply')
            mounts.prepareRestore(d.code)
            local s=capture(d,actor)
            local rollback,afterCommit
            local ok,why=pcall(function()
                rollback,afterCommit=apply(d,target)
                synchronize(d,s)
            end)
            local function undo()
                local baseOK,baseError=true,nil
                if rollback then baseOK,baseError=pcall(rollback) end
                -- Restore the exact pre-selection live configs, even if the
                -- general mount rollback also touched a tracked player activator.
                local playerOK,playerError=pcall(restore,s)
                assert(baseOK and playerOK,tostring(baseError or playerError))
            end
            if not ok then
                local restored,err=pcall(undo)
                if not restored then log('RESUPPLY rollback failed: '..tostring(err)) end
                error(why)
            end
            return undo,afterCommit
        end
    end
    return {wrap=wrap,playerMatches=playerMatches}
end
