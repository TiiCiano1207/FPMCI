local directory = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local profiles = assert(loadfile(directory .. "visor_profiles.lua"))()

local function valid(object) return object and object:IsValid() end
-- The caller has checked the new wrapper. Retain the old binding only while
-- its object is live, even when an aircraft swap reuses an address.
local function stillBound(current, previous, address)
    return rawequal(current, previous) or (previous:IsValid() and current:GetAddress() == address)
end
local function unwrap(entry) return entry:get() end

-- Masking and forward readout placement use the same live cockpit mesh and bone.
return function(api, log)
    local meshClass
    local function resolve(ctx, frame)
        local glass = ctx.glass
        if frame < (ctx.nextGlassScan or 0) then
            if not glass then return end
            local asset = valid(glass.mesh) and glass.mesh:GetSkeletalMeshAsset()
            if valid(asset) and stillBound(asset, glass.asset, glass.assetAddress) then return glass end
        end
        if not valid(meshClass) then meshClass = api.StaticFindObject("/Script/Engine.SkeletalMeshComponent") end
        assert(valid(meshClass), "SkeletalMeshComponent unavailable")
        local found
        ctx.nextGlassScan = frame + 120 - (frame - 45) % 120
        for _, entry in ipairs(ctx.pawn:K2_GetComponentsByClass(meshClass)) do
            local wrapped, mesh = pcall(unwrap, entry)
            if not wrapped then mesh = entry end
            local asset = valid(mesh) and mesh:GetSkeletalMeshAsset()
            local profile = valid(asset) and profiles[asset:GetFName():ToString()]
            if profile and mesh:GetBoneIndex(api.FName(profile.bone)) >= 0 then
                if found then return nil end -- Two matching meshes during an aircraft swap.
                if glass and stillBound(mesh, glass.mesh, glass.meshAddress)
                    and stillBound(asset, glass.asset, glass.assetAddress) then
                    found = glass -- Keep the existing native binding across the periodic check.
                else
                    found = {mesh = mesh, asset = asset, meshAddress = mesh:GetAddress(),
                        assetAddress = asset:GetAddress(), profile = profile}
                end
            end
        end
        return found
    end

    return function(ctx, frame, needed)
        if not needed or ctx.view ~= "cockpit" or not valid(ctx.center) then
            ctx.glass, ctx.nextGlassScan, ctx.glassError = nil, nil, nil
            return
        end
        local ok, result = pcall(resolve, ctx, frame)
        ctx.glass = ok and result or nil
        if not ok then
            ctx.nextGlassScan = frame + 120 - (frame - 45) % 120
            if result ~= ctx.glassError then log("Cockpit glass lookup failed: " .. tostring(result)) end
            ctx.glassError = result
        elseif result then
            ctx.glassError = nil
        end
    end
end
