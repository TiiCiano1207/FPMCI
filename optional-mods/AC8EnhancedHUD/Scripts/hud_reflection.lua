-- These are the members the native math reads or writes inside reflected values.
-- Geometry travels as an opaque value between Slate functions.
local structFields = {
    Vector2D = {x = {0, "DoubleProperty"}, y = {8, "DoubleProperty"}},
    Vector = {x = {0, "DoubleProperty"}, y = {8, "DoubleProperty"}, z = {16, "DoubleProperty"}},
    Quat = {x = {0, "DoubleProperty"}, y = {8, "DoubleProperty"}, z = {16, "DoubleProperty"}, w = {24, "DoubleProperty"}},
    Transform = {rotation = {0, "Quat"}, translation = {32, "Vector"}, scale3d = {64, "Vector"}},
    WidgetTransform = {translation = {0, "Vector2D"}, scale = {16, "Vector2D"}, shear = {32, "Vector2D"}, angle = {48, "FloatProperty"}},
}

-- Order is the wire contract. The DLL reads the size and current offset from
-- each named FProperty during binding; coordinates in the game may move.
return function(api, find, geometryOnly)
    local checked = {}
    local function checkStruct(prop, expected, where)
        local struct = prop:GetStruct()
        assert(struct:GetFName():ToString():lower() == expected:lower(), "Struct changed for " .. where)
        local shape = structFields[expected]
        if not shape or checked[struct:GetAddress()] then return end
        local seen = {}
        struct:ForEachProperty(function(member)
            local key = member:GetFName():ToString():lower()
            local spec = shape[key]
            assert(spec and not seen[key] and member:GetOffset_Internal() == spec[1], "Member layout changed for " .. where .. "." .. key)
            if structFields[spec[2]] then
                assert(member:IsA(api.PropertyTypes.StructProperty), "Member type changed for " .. where .. "." .. key)
                checkStruct(member, spec[2], where .. "." .. key)
            else
                assert(member:GetClass():GetFName():ToString() == spec[2], "Member type changed for " .. where .. "." .. key)
            end
            seen[key] = true
        end)
        for key in pairs(shape) do assert(seen[key], "Missing member " .. where .. "." .. key) end
        checked[struct:GetAddress()] = true
    end
    local function native(path, shape, isStatic)
        local fn = find(path)
        local flags = fn:GetFunctionFlags()
        assert(flags & 0x400 ~= 0 and (flags & 0x2000 ~= 0) == (isStatic == true),
            "Native function flags changed for " .. path)
        local properties = {}
        fn:ForEachProperty(function(property)
            local name = property:GetFName():ToString():lower()
            assert(not properties[name], "Duplicate parameter in " .. path)
            properties[name] = property
        end)
        local ordered = {fn}
        for _, field in ipairs(shape) do
            local key = field[1]:lower()
            local prop = properties[key]
            local where = path .. "." .. field[1]
            assert(prop, "Missing reflected field " .. where)
            local kind = field[2]
            if kind == "ByteOrEnum" then
                assert(prop:IsA(api.PropertyTypes.ByteProperty) or prop:IsA(api.PropertyTypes.EnumProperty),
                    "Expected byte or enum for " .. where)
            elseif kind == "SoftObjectProperty" then
                assert(prop:GetClass():GetFName():ToString() == kind, "Type changed for " .. where)
            else
                assert(prop:IsA(api.PropertyTypes[kind]), "Type changed for " .. where)
            end
            if field[3] then checkStruct(prop, field[3], where) end
            ordered[#ordered + 1] = prop
            properties[key] = nil
        end
        assert(not next(properties), "Unexpected reflected parameter in " .. path)
        return ordered
    end
    local function struct(name, kind) return {name, "StructProperty", kind} end
    local functions = {
        native("/Script/UMG.Widget:GetCachedGeometry", {struct("ReturnValue", "Geometry")}),
        native("/Script/UMG.SlateBlueprintLibrary:GetLocalSize", {struct("Geometry", "Geometry"), struct("ReturnValue", "Vector2D")}, true),
        native("/Script/UMG.SlateBlueprintLibrary:ScreenToWidgetLocal", {
            {"WorldContextObject", "ObjectProperty"}, struct("Geometry", "Geometry"), struct("ScreenPosition", "Vector2D"),
            struct("LocalCoordinate", "Vector2D"), {"bIncludeWindowPosition", "BoolProperty"},
        }, true),
    }
    if not geometryOnly then
        local visorFunctions = {
            native("/Script/Engine.PlayerController:ProjectWorldLocationToScreen", {
                struct("WorldLocation", "Vector"), struct("ScreenLocation", "Vector2D"),
                {"bPlayerViewportRelative", "BoolProperty"}, {"ReturnValue", "BoolProperty"},
            }),
            native("/Script/Engine.SceneComponent:GetSocketTransform", {
                {"InSocketName", "NameProperty"}, {"TransformSpace", "ByteOrEnum"}, struct("ReturnValue", "Transform"),
            }),
            native("/Script/UMG.Widget:SetRenderTransform", {struct("InTransform", "WidgetTransform")}),
            native("/Script/UMG.Widget:SetClipping", {{"InClipping", "ByteOrEnum"}}),
            native("/Script/UMG.Widget:SetRenderOpacity", {{"InOpacity", "FloatProperty"}}),
            native("/Script/UMG.CanvasPanelSlot:SetSize", {struct("InSize", "Vector2D")}),
        }
        for _, fn in ipairs(visorFunctions) do functions[#functions + 1] = fn end
    end
    functions.serialLibrary = find("/Script/Engine.Default__KismetSystemLibrary")
    functions.serialFunction = native("/Script/Engine.KismetSystemLibrary:Conv_ObjectToSoftObjectReference", {
        {"Object", "ObjectProperty"}, {"ReturnValue", "SoftObjectProperty"},
    }, true)
    return functions
end
