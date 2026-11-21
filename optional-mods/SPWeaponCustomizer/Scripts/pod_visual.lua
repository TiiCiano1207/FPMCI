-- Cosmetic components owned by the display aircraft or local player's pawn.
return function(mounts,log)
    local groups,reported,pylons,visibility={},{},{},{}
    local reused={}
    local function valid(o) return o and o:IsValid() end
    local function identity(o) return valid(o) and o:GetFullName() end
    local function field(o,key)
        local ok,v=pcall(function()return o[key]end)
        if ok then return v end
    end
    local function report(key,text)
        if not reported[key] then reported[key]=true;log('POD '..text) end
    end
    local function remove(key)
        local group=groups[key]
        if not group then return end
        groups[key]=nil
        for _,part in ipairs(group.parts) do
            if identity(part.object)==part.name then
                pcall(function()part.object:SetVisibility(false,false);part.object:K2_DestroyComponent(group.owner)end)
            end
        end
    end
    local function clear(kind)
        if kind==nil or kind=='hangar' then
            for key,v in pairs(reused) do
                if identity(v.c)==v.name and identity(field(v.c,'StaticMesh'))==v.applied and identity(v.original)==v.originalName then
                    pcall(function()v.c:SetStaticMesh(v.original)end)
                end
                reused[key]=nil
            end
            for key,v in pairs(visibility) do
                if identity(v.c)==v.name and field(v.c,'bVisible')==v.applied then
                    pcall(function()v.c:SetVisibility(v.original,false)end)
                end
                visibility[key]=nil
            end
            for key,old in pairs(pylons) do
                if identity(old.component)==old.componentName and identity(field(old.component,'StaticMesh'))==old.applied and identity(old.mesh)==old.original then
                    pcall(function()old.component:SetStaticMesh(old.mesh)end)
                end
                pylons[key]=nil
            end
        end
        for key,g in pairs(groups) do if not kind or g.kind==kind then remove(key) end end
    end
    local one={Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1},Rotation={X=0,Y=0,Z=0,W=1}}
    local assets={}
    local function try(fn)
        local ok,result=pcall(fn)
        if ok then return result end
    end
    local function prepare(d)
        local cached=assets[d.code]
        if cached and (cached.generated or identity(cached.mesh)==cached.name) then return cached end
        local mesh=try(function()return mounts.previewClass(d,20):GetCDO().StaticMesh.StaticMesh end)
        if valid(mesh) and identity(mesh):lower():match('^staticmesh .-mgp') then
            cached={mesh=mesh,name=identity(mesh)}
        else
            cached={generated=true,name='FPMCI cosmetic MGP',bounds={Min={X=-124,Y=-19,Z=-40},Max={X=121,Y=19,Z=14}}}
        end
        assets[d.code]=cached
        return cached
    end
    local none=FName('None')
    -- A single render component per rack, with indexed surfaces for the shell,
    -- nose recess, lip and barrel ends. Coordinates are model-space art units.
    local sections
    local function buildModel(c)
        if not sections then
            sections={}
            for i=1,3 do sections[i]={v={},t={},n={}} end
            local function surface(section,profile,cy,cz)
                local s=sections[section]
                local sides=24
                for j=2,#profile do
                    local a,b=profile[j-1],profile[j]
                    local dx,dr=b[1]-a[1],b[2]-a[2]
                    local len=math.sqrt(dx*dx+dr*dr)
                    local start=#s.v
                    for _,ring in ipairs({a,b}) do
                        for k=0,sides-1 do
                            local angle=2*math.pi*k/sides
                            local y,z=math.cos(angle),math.sin(angle)
                            s.v[#s.v+1]={X=ring[1],Y=cy+ring[2]*y,Z=cz+ring[2]*z}
                            s.n[#s.n+1]={X=-dr/len,Y=dx*y/len,Z=dx*z/len}
                        end
                    end
                    for k=0,sides-1 do
                        local l=start+k
                        local r=start+(k+1)%sides
                        for _,index in ipairs({l,l+sides,r,r,l+sides,r+sides}) do s.t[#s.t+1]=index end
                    end
                end
            end
            -- The saddle intersects the shell and continues above the socket plane
            -- into the mounting rail. Use flat faces so its top has full contact.
            local function face(a,b,c,d,n)
                local s=sections[2]
                local start=#s.v
                for _,pt in ipairs({a,b,c,d}) do
                    s.v[#s.v+1]={X=pt[1],Y=pt[2],Z=pt[3]}
                    s.n[#s.n+1]={X=n[1],Y=n[2],Z=n[3]}
                end
                for _,i in ipairs({0,1,2,0,2,3}) do s.t[#s.t+1]=start+i end
            end
            local a,b,c,d={-38,-5,-7},{38,-5,-7},{38,5,-7},{-38,5,-7}
            local e,f,g,h={-38,-5,14},{38,-5,14},{38,5,14},{-38,5,14}
            face(a,b,f,e,{0,-1,0});face(b,c,g,f,{1,0,0})
            face(c,d,h,g,{0,1,0});face(d,a,e,h,{-1,0,0})
            face(e,f,g,h,{0,0,1});face(d,c,b,a,{0,0,-1})
            surface(1,{{-124,0},{-121,5},{-104,11},{-77,17},{-50,19},{45,19},{74,17},{91,13},{99,10}},0,-20)
            surface(2,{{99,10},{101,10},{101,8},{96,8},{96,0}},0,-20)
            for k=0,5 do
                local angle=k*math.pi/3
                surface(3,{{96,2.2},{119,2.2},{121,2},{121,1.35},{116,1.35},{116,0}},5*math.cos(angle),-20+5*math.sin(angle))
            end
            for _,x in ipairs({-60,48}) do surface(2,{{x,18.6},{x+1,19},{x+2,18.6}},0,-20) end
        end
        local mat=LoadAsset('/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial')
        for i,s in ipairs(sections) do
            c:CreateMeshSection(i-1,s.v,s.t,s.n,{},{},{},false)
            if valid(mat) then
                c:SetMaterial(i-1,mat)
                local mid=c:CreateDynamicMaterialInstance(i-1,mat,none)
                if valid(mid) then
                    local shade=({0.16,0.07,0.035})[i]
                    mid:SetVectorParameterValue(FName('Color'),{R=shade,G=shade*1.04,B=shade*1.08,A=1})
                end
            end
        end
        assert(c:GetNumSections()==#sections,'incomplete pod model')
    end
    local mathLib
    local function socketTransform(rack)
        return rack.parent:GetSocketTransform(rack.socket,0)
    end
    local function inFrame(transform,point,frame)
        return mathLib:InverseTransformLocation(frame,mathLib:TransformLocation(transform,point))
    end
    local function readable(low,high)
        if not low or not high then return false end
        local span=0
        for _,axis in ipairs({'X','Y','Z'}) do
            local a,b=field(low,axis),field(high,axis)
            if type(a)~='number' or type(b)~='number' or not (a<=b) then return false end
            span=span+b-a
        end
        return span>0
    end
    local function localBounds(mesh,component)
        -- GetLocalBounds exposes two reflected FVector output parameters. The
        -- installed UE4SS can return an FBox without accessible Min/Max fields.
        local mounted=field(component,'StaticMesh')
        if mounted and (mounted==mesh or try(function()return mounted:GetAddress()==mesh:GetAddress()end)) then
            local low,high={},{}
            try(function()component:GetLocalBounds(low,high)end)
            if readable(low,high) then return {Min=low,Max=high} end
        end
        local box=try(function()return mesh:GetBoundingBox()end)
        if readable(field(box,'Min'),field(box,'Max')) then return box end
        local bounds=try(function()return mesh:GetBounds()end)
        local center,extent=field(bounds,'Origin'),field(bounds,'BoxExtent')
        if center and extent then
            local low,high={},{}
            for _,axis in ipairs({'X','Y','Z'}) do
                local a,b=field(center,axis),field(extent,axis)
                if type(a)~='number' or type(b)~='number' then return end
                low[axis],high[axis]=a-b,a+b
            end
            if readable(low,high) then return {Min=low,Max=high} end
        end
    end
    local function extents(bounds,transform,frame)
        local low,high=bounds.Min,bounds.Max
        local box={Min={},Max={}}
        for _,x in ipairs({low.X,high.X}) do for _,y in ipairs({low.Y,high.Y}) do for _,z in ipairs({low.Z,high.Z}) do
            local pt=inFrame(transform,{X=x,Y=y,Z=z},frame)
            for _,k in ipairs({'X','Y','Z'}) do
                box.Min[k]=math.min(box.Min[k] or math.huge,pt[k])
                box.Max[k]=math.max(box.Max[k] or -math.huge,pt[k])
            end
        end end end
        return box
    end
    local function fits(bounds,offset,obstacles)
        for _,other in ipairs(obstacles) do
            local overlaps=true
            for _,k in ipairs({'X','Y','Z'}) do
                if bounds.Max[k]+offset[k]+2<=other.Min[k] or bounds.Min[k]+offset[k]>=other.Max[k]+2 then overlaps=false;break end
            end
            if overlaps then return false end
        end
        return true
    end
    local function place(key,kind,owner,rack,asset,offset,rotation)
        local g=groups[key]
        if g and (identity(g.parts[1].object)~=g.parts[1].name or g.mesh~=asset.name) then remove(key);g=nil end
        if not g then
            local cls=StaticFindObject(asset.generated and '/Script/ProceduralMeshComponent.ProceduralMeshComponent' or '/Script/Engine.StaticMeshComponent')
            local c=owner:AddComponentByClass(cls,true,one,false)
            assert(valid(c),'could not create pod component')
            g={owner=owner,kind=kind,mesh=asset.name,parts={{object=c,name=identity(c)}}}
            groups[key]=g
            c:SetCollisionEnabled(0)
            assert(c:K2_AttachToComponent(rack.parent,rack.socket,2,2,2,false)~=false,'attachment declined')
            if asset.generated then buildModel(c)
            else assert(c:SetStaticMesh(asset.mesh)~=false,'mesh assignment declined') end
        end
        local old=g.offset
        if rotation or not old or math.abs(old.X-offset.X)+math.abs(old.Y-offset.Y)+math.abs(old.Z-offset.Z)>0.01 then
            local pose={Translation=offset,Scale3D=one.Scale3D,Rotation=rotation or one.Rotation}
            g.parts[1].object:K2_SetRelativeTransform(pose,false,{},true)
            g.offset=offset
        end
    end
    local function railSurfaces(owner)
        local result={}
        local cls=StaticFindObject('/Script/Engine.PrimitiveComponent')
        for _,wrapper in pairs(owner:K2_GetComponentsByClass(cls) or {}) do
            local c=try(function()return wrapper:get()end) or wrapper
            local label=((identity(c) or '')..' '..(identity(field(c,'StaticMesh')) or '')):lower()
            if (label:find('pylon',1,true) or label:find('rail',1,true) or label:find('skeletalmeshcomponent',1,true)) and
                    field(c,'bHiddenInGame')~=true and field(c,'bVisible')~=false then
                result[#result+1]=c
            end
        end
        return result
    end
    local function railContact(surfaces,frame,pt)
        local start=mathLib:TransformLocation(frame,{X=pt.X,Y=pt.Y,Z=pt.Z-20})
        local finish=mathLib:TransformLocation(frame,{X=pt.X,Y=pt.Y,Z=pt.Z+85})
        local nearest
        for _,c in ipairs(surfaces) do
            local hit={}
            local traced=try(function()return c:K2_LineTraceComponent(start,finish,true,false,false,hit,{},none,{})end)
            if not traced or type(hit.X)~='number' then
                local distance=try(function()return c:GetClosestPointOnCollision(start,hit,none)end)
                traced=type(distance)=='number' and distance>0
            end
            if traced and type(hit.X)=='number' then
                local localHit=mathLib:InverseTransformLocation(frame,hit)
                if math.abs(localHit.Y-pt.Y)<=7 and math.abs(localHit.X-pt.X)<=10 and localHit.Z>=pt.Z-20 and localHit.Z<=pt.Z+85
                        and (not nearest or localHit.Z<nearest.Z) then nearest=localHit end
            end
        end
        return nearest
    end
    local function layout(kind,owner,d,racks,occupied)
        local keep={}
        local ok,err=pcall(function()
            if #racks==0 then return end
            local asset=prepare(d)
            if not valid(mathLib) then mathLib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary') end
            assert(valid(mathLib),'transform library unavailable')
            local usedSides={}
            local body={parent=owner.RootComponent,socket=none}
            local bodyFrame=socketTransform(body)
            local surfaces=railSurfaces(owner)
            local candidates={}
            for index,rack in ipairs(racks) do
                local anchor=mathLib:InverseTransformLocation(bodyFrame,rack.parent:GetSocketLocation(rack.socket))
                if valid(rack.child) then
                    anchor=mathLib:InverseTransformLocation(bodyFrame,rack.child:GetSocketLocation(none))
                end
                local contact=railContact(surfaces,bodyFrame,anchor)
                if contact or not rack.spare then
                    candidates[#candidates+1]={rack=rack,anchor=anchor,contact=contact,index=index,rank=contact and (rack.spare and 2 or 1) or 3}
                end
            end
            table.sort(candidates,function(a,b)
                if a.rank==b.rank then return a.index<b.index end
                return a.rank<b.rank
            end)
            for _,candidate in ipairs(candidates) do
                local frame,rack,anchor,contact=bodyFrame,candidate.rack,candidate.anchor,candidate.contact
                local bounds=asset.bounds or localBounds(asset.mesh)
                if not bounds then
                    local probe=owner:AddComponentByClass(StaticFindObject('/Script/Engine.StaticMeshComponent'),true,one,false)
                    assert(valid(probe),'mesh bounds probe unavailable')
                    local measured,result=pcall(function()
                        probe:SetVisibility(false,false);probe:SetCollisionEnabled(0)
                        probe:SetStaticMesh(asset.mesh)
                        return localBounds(asset.mesh,probe)
                    end)
                    probe:K2_DestroyComponent(owner)
                    if measured then bounds=result end
                    assert(bounds,'cannot measure '..asset.name)
                end
                -- Keep plain Lua numbers; engine property wrappers can expire.
                if not asset.bounds then
                    asset.bounds={Min={},Max={}}
                    for _,axis in ipairs({'X','Y','Z'}) do
                        asset.bounds.Min[axis]=bounds.Min[axis];asset.bounds.Max[axis]=bounds.Max[axis]
                    end
                end
                local x,y,z=anchor.X,anchor.Y,anchor.Z
                if not asset.generated then
                    x=x-(bounds.Min.X+bounds.Max.X)/2
                    y=y-(bounds.Min.Y+bounds.Max.Y)/2
                    z=z-bounds.Max.Z
                end
                if contact then z=contact.Z-bounds.Max.Z+1 end
                local obstacles={}
                for _,other in ipairs(occupied) do
                    local size=localBounds(other.mesh,other.parent)
                    if not size then
                        -- Occupied station with unreadable render bounds: reserve
                        -- space around its socket, then test the remaining racks.
                        size={Min={X=-120,Y=-24,Z=-32},Max={X=120,Y=24,Z=16}}
                        report('unmeasured'..tostring(identity(other.mesh)),'using socket clearance for '..tostring(identity(other.mesh)))
                    end
                    obstacles[#obstacles+1]=extents(size,socketTransform(other),frame)
                end
                -- Only slide along the rack; keep lateral station and mounting height.
                local slide=math.min(20,(bounds.Max.X-bounds.Min.X)*0.08)
                local key=kind..':'..rack.parent:GetAddress()..':'..rack.socket:ToString()
                local side
                do
                    local rootFrame=owner.RootComponent:GetSocketTransform(none,0)
                    local point=mathLib:InverseTransformLocation(rootFrame,rack.parent:GetSocketLocation(rack.socket))
                    side=point.Y<-2 and 'left' or (point.Y>2 and 'right' or 'center')
                end
                for _,delta in ipairs({0,slide/2,-slide/2,slide,-slide}) do
                    if usedSides[side] then break end
                    local offset={X=x+delta,Y=y,Z=z}
                    if fits(bounds,offset,obstacles) then
                        local rackFrame=socketTransform(rack)
                        local relative=mathLib:InverseTransformLocation(rackFrame,mathLib:TransformLocation(frame,offset))
                        local relativePose=try(function()return mathLib:MakeRelativeTransform(frame,rackFrame)end)
                        place(key,kind,owner,rack,asset,relative,relativePose and relativePose.Rotation)
                        keep[key]=true
                        report(key..d.code..tostring(contact~=nil),string.format('%s %s %s mount %s local=(%.1f,%.1f,%.1f)',kind,d.section,rack.socket:ToString(),contact and 'rail surface' or 'socket',offset.X,offset.Y,offset.Z))
                        usedSides[side]=true
                        report(kind..d.code..asset.name,kind..' '..d.section..' displayed '..asset.name)
                        break
                    end
                end
                if not usedSides[side] then report(key..'overlap','overlap on '..d.section..' '..kind..'; no clear pod position') end
            end
        end)
        if not ok then report(kind..tostring(err),kind..' '..tostring(err)) end
        for key,g in pairs(groups) do
            if g.kind==kind and (not valid(g.owner) or g.owner:GetAddress()==owner:GetAddress()) and not keep[key] then remove(key) end
        end
    end
    local function items(array)
        local result={}
        if not array then return result end
        local count=type(array)=='table' and not array.GetArrayNum and #array or array:GetArrayNum()
        assert(count>=0 and count<=8192,'Invalid pod component array length')
        for i=1,count do
            local v=array[i]
            local item=try(function()return v:get()end)
            result[#result+1]=item or v
        end
        return result
    end
    local function owned(c)
        for _,g in pairs(groups) do
            if g.parts[1].name==identity(c) then return true end
        end
        return false
    end
    -- Use aircraft sockets, not the pooled child meshes of a rocket or missile rack.
    local function pylonPath(owner,mask)
        return try(function()
            local value=owner.WeaponEquipmentSettings:Find(mask)
            local row=try(function()return value:get()end) or value
            local ref=row.PylonMeshRef
            return try(function()return ref:GetObjectID():GetAssetPathName():ToString()end)
                or try(function()return ref:GetAssetPathName():ToString()end)
                or try(function()return ref:GetFullName():match('^StaticMesh (.+)$')end)
        end)
    end
    local function usePylon(owner,from,to)
        if from==to then return end
        local src,dst=pylonPath(owner,from),pylonPath(owner,to)
        if not src or not dst or src==dst or not dst:match('^/Game/') then
            report(identity(owner)..from..'>'..to,'no distinct pylon row for '..from..' -> '..to)
            return
        end
        local cls=StaticFindObject('/Script/Engine.StaticMeshComponent')
        for _,c in ipairs(items(owner:K2_GetComponentsByClass(cls))) do
            local mesh=field(c,'StaticMesh')
            local original=identity(mesh)
            if original and original:lower()==('StaticMesh '..src):lower() then
                local replacement=LoadAsset(dst)
                if identity(replacement) and identity(replacement):lower()==('StaticMesh '..dst):lower() then
                    if c:SetStaticMesh(replacement)~=false and identity(c.StaticMesh)==identity(replacement) then
                        pylons[c:GetAddress()]={component=c,componentName=identity(c),mesh=mesh,original=original,applied=identity(replacement)}
                        report(original..dst,'display pylon '..src..' -> '..dst)
                    end
                end
            end
        end
    end
    -- The mesh suffix is a variant number. Its value and the slot bit mask
    -- differ for SWP3 (third slot) and SWP4 (first plus second).
    local variantNumber={[1]=1,[2]=2,[4]=3,[3]=4,[5]=5,[6]=6}
    local function visibleAs(c,show)
        local value=field(c,'bVisible')
        if value==nil or value==show then return end
        local key=c:GetAddress()
        local old=visibility[key]
        if not old or old.name~=identity(c) then
            old={c=c,name=identity(c),original=value};visibility[key]=old
        end
        old.applied=show
        c:SetVisibility(show,false)
    end
    local function selectCarrier(owner,mask)
        local n=variantNumber[mask]
        if not n then return end
        local variants,target,current={},nil,nil
        local cls=StaticFindObject('/Script/Engine.StaticMeshComponent')
        local components=items(owner:K2_GetComponentsByClass(cls))
        for _,c in ipairs(components) do
            local path=(identity(field(c,'StaticMesh')) or ''):match('^StaticMesh (.+)$')
            local number=path and tonumber(path:upper():match('_SWP(%d+)%.'))
            if number then
                variants[c:GetAddress()]=c
                local visible=try(function()return c:IsVisible()end)==true
                if number==n and (not target or visible) then target=c end
                if visible then current=c end
            end
        end
        if not target and current then
            local mesh=current.StaticMesh
            local path=identity(mesh):match('^StaticMesh (.+)$')
            local wanted=path:gsub('(_[Ss][Ww][Pp])%d+',function(prefix)return prefix..n end)
            local replacement=try(function()return LoadAsset(wanted)end)
            if identity(replacement) and identity(replacement):lower()==('StaticMesh '..wanted):lower() then
                local sockets=items(field(replacement,'Sockets'))
                local found=0
                for _,socket in ipairs(sockets) do
                    local group=tonumber((try(function()return socket.SocketName:ToString():lower()end) or ''):match('^soc_swp_([123])%d%d%d$'))
                    if group then found=found | (1<<(group-1)) end
                end
                if found==mask and current:SetStaticMesh(replacement)~=false and identity(current.StaticMesh)==identity(replacement) then
                    local key=current:GetAddress()
                    pylons[key]={component=current,componentName=identity(current),mesh=mesh,original=identity(mesh),applied=identity(replacement)}
                    target=current
                end
            end
        end
        if not target then return end
        for _,c in pairs(variants) do visibleAs(c,c:GetAddress()==target:GetAddress()) end
        for _,c in ipairs(components) do
            local parent=try(function()return c:GetAttachParent()end)
            local socket=try(function()return c:GetAttachSocketName()end)
            if valid(parent) and variants[parent:GetAddress()] and socket and socket:ToString():lower():match('^soc_swp_[123]%d%d%d$') then
                local enabled=parent:GetAddress()==target:GetAddress() and try(function()return parent:DoesSocketExist(socket)end)~=false
                visibleAs(c,enabled)
            end
        end
        report(identity(owner)..' carrier '..n,'selected hangar carrier '..identity(target.StaticMesh))
        return target
    end
    local function pairedRacks(owner,groupsBySlot,entries,carrier)
        local result,seen={{},{},{}},{}
        local function remember(parent,socket,group,child,original)
            local slot=groupsBySlot[group]
            if not slot or not valid(parent) or (carrier and parent:GetAddress()~=carrier:GetAddress()) or field(parent,'bHiddenInGame')==true or field(parent,'bVisible')==false then return end
            if try(function()return parent:DoesSocketExist(socket)end)==false then return end
            local name=socket:ToString():lower()
            local label=((identity(parent) or '')..' '..(identity(field(parent,'StaticMesh')) or '')):lower()
            local rank=(label:find('pylon',1,true) or label:find('rail',1,true)) and 4 or 0
            if child and field(child,'bVisible')~=false and field(child,'bHiddenInGame')~=true then rank=rank+2 end
            local previous=seen[name]
            if previous and previous.rank>=rank then return end
            local rack={parent=parent,socket=socket,child=child,original=original,rank=rank}
            rack.index=previous and previous.index or #result[slot]+1
            result[slot][rack.index]=rack
            seen[name]=rack
        end
        for _,entry in ipairs(entries) do
            local c=entry.object
            if identity(c)==entry.name then
                local socket=c:GetAttachSocketName()
                local group=tonumber(socket:ToString():lower():match('^soc_swp_([123])%d+$'))
                if group then remember(c:GetAttachParent(),socket,group,c,entry.original) end
            end
        end
        local cls=StaticFindObject('/Script/Engine.MeshComponent')
        for _,component in ipairs(items(owner:K2_GetComponentsByClass(cls))) do
            if valid(component) and (not carrier or component:GetAddress()==carrier:GetAddress()) and not owned(component) then
                for _,socket in ipairs(items(component:GetAllSocketNames())) do
                    local group=tonumber(socket:ToString():lower():match('^soc_swp_([123])%d+$'))
                    if group then remember(component,socket,group) end
                end
            end
        end
        -- Some display planes expose a pooled component but no named SP socket.
        local missing={#result[1]==0,#result[2]==0}
        for _,entry in ipairs(entries) do
            local slot=entry.original and groupsBySlot[entry.original.slot]
            if not carrier and slot and missing[slot] and identity(entry.object)==entry.name then
                result[slot][#result[slot]+1]={parent=entry.object,socket=none}
            end
        end
        for _,racks in ipairs(result) do
            table.sort(racks,function(a,b)return a.socket:ToString()<b.socket:ToString()end)
        end
        return result
    end
    local function companion(owner,mesh,id,racks,reuseChildren)
        local keep,occupied,locations,sides={},{},{},{}
        local limit=id==5 and 2 or 1
        local root=socketTransform({parent=owner.RootComponent,socket=none})
        mathLib=mathLib or StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
        local size=localBounds(mesh)
        -- Require separation even when multiple socket names resolve to one point.
        local separation=size and math.max(size.Max.Y-size.Min.Y,size.Max.Z-size.Min.Z,12) or 45
        for _,rack in ipairs(racks) do
            local seat=rack
            if valid(rack.child) and field(rack.child,'bVisible')~=false and field(rack.child,'bHiddenInGame')~=true then
                seat={parent=rack.child,socket=none}
            end
            local pt=mathLib:InverseTransformLocation(root,seat.parent:GetSocketLocation(seat.socket))
            local side=pt.Y<-2 and -1 or (pt.Y>2 and 1 or 0)
            local free=#locations<2*limit and (sides[side] or 0)<limit
            for _,other in ipairs(locations) do
                if (pt.Y-other.Y)^2+(pt.Z-other.Z)^2<separation^2 then free=false;break end
            end
            if free then
                local key='companion:'..seat.parent:GetAddress()..':'..seat.socket:ToString()
                local part
                if reuseChildren and seat.parent==rack.child then
                    part=rack.child
                    local old=rack.original
                    if old then
                        reused[part:GetAddress()]={c=part,name=identity(part),applied=identity(mesh),original=old.mesh,originalName=old.meshName}
                    end
                    if identity(field(part,'StaticMesh'))~=identity(mesh) then
                        assert(part:SetStaticMesh(mesh)~=false,'native weapon mesh replacement declined')
                    end
                else
                    place(key,'companion',owner,seat,{name=identity(mesh),mesh=mesh},one.Translation)
                    keep[key]=true
                    part=groups[key].parts[1].object
                end
                sides[side]=(sides[side] or 0)+1;locations[#locations+1]=pt
                occupied[#occupied+1]={parent=part,socket=none,mesh=mesh}
            end
        end
        for key,g in pairs(groups) do
            if g.kind=='companion' and g.owner:GetAddress()==owner:GetAddress() and not keep[key] then remove(key) end
        end
        report(identity(owner)..id..#occupied,'preview weapon '..id..' sockets='..#racks..' visible meshes='..#occupied)
        return occupied
    end
    local lastPawn
    local function visibleWeapon(parent)
        local mesh=field(parent,'StaticMesh')
        local name=(identity(mesh) or ''):lower()
        if name:match('^staticmesh /game/vehicles/weapons/') and field(parent,'bHiddenInGame')~=true and field(parent,'bVisible')~=false then
            return mesh
        end
    end
    local function flight(pawn,d)
        local slot
        if d then for i,id in ipairs(d.target) do if id==20 and d.original[i]~=20 then slot=i end end end
        local current=slot and identity(pawn) or nil
        if current~=lastPawn then clear('flight');lastPawn=current end
        if not slot then return end
        local equipped=field(field(pawn,'PlayerWeaponActivator'),'EquippedWeapons')
        local selected,sockets,otherMeshes=false,{},{}
        if valid(equipped) then
            for _,cfg in ipairs(items(equipped.Configs)) do
                local cdo=field(cfg,'WeaponClassDefaultObject')
                local isPod=(identity(cdo) or ''):lower():find('bp_plwp_mgp_',1,true)
                if isPod then selected=true end
                local mesh=field(field(cdo,'StaticMesh'),'StaticMesh')
                for _,s in ipairs(items(field(cfg,'WeaponSockets'))) do
                    local text=try(function()return s.SocketName:ToString():lower()end)
                    if text then
                        if isPod then sockets[text]=true elseif valid(mesh) then otherMeshes[text]=mesh end
                    end
                end
            end
        end
        if not selected then clear('flight');return end
        local racks,occupied,seen={},{},{}
        local cls=StaticFindObject('/Script/Engine.MeshComponent')
        local carriers=items(pawn:K2_GetComponentsByClass(cls))
        local function priority(c)
            local label=((identity(c) or '')..' '..(identity(field(c,'StaticMesh')) or '')):lower()
            return (label:find('pylon',1,true) or label:find('rail',1,true)) and 0 or 1
        end
        table.sort(carriers,function(a,b)return priority(a)<priority(b)end)
        for _,parent in ipairs(carriers) do
            if valid(parent) and field(parent,'bVisible')~=false and field(parent,'bHiddenInGame')~=true then
                local mesh=visibleWeapon(parent)
                local own=false
                for _,g in pairs(groups) do if g.parts[1].name==identity(parent) then own=true;break end end
                if not own and mesh then
                    occupied[#occupied+1]={parent=parent,socket=none,mesh=mesh}
                end
                if not own then for _,socket in ipairs(items(parent:GetAllSocketNames())) do
                    local text=socket:ToString():lower()
                    if not seen[text] then
                        if otherMeshes[text] then
                            occupied[#occupied+1]={parent=parent,socket=socket,mesh=otherMeshes[text]};seen[text]=true
                        elseif sockets[text] or (not next(sockets) and text:match('^soc_swp_'..slot..'%d+$')) then
                            racks[#racks+1]={parent=parent,socket=socket};seen[text]=true
                        end
                    end
                end end
            end
        end
        local attached={}
        local children=try(function()return pawn:GetAttachedActors(attached,true,true)end)
        if type(children)=='table' or type(children)=='userdata' then attached=children end
        for _,actor in ipairs(items(attached)) do
            if valid(actor) then
                for _,component in ipairs(items(actor:K2_GetComponentsByClass(cls))) do
                    local mesh=visibleWeapon(component)
                    if mesh then occupied[#occupied+1]={parent=component,socket=none,mesh=mesh} end
                end
            end
        end
        layout('flight',pawn,d,racks,occupied)
    end
    return {layout=layout,clear=clear,flight=flight,owned=owned,selectCarrier=selectCarrier,pairedRacks=pairedRacks,usePylon=usePylon,companion=companion}
end
