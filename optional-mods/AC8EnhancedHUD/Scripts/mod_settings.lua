-- The INI supplies both the standalone config and the menu's reset defaults.
return function(config, ranges)
    local provider = require("AC8ModSettings")
    local compatible = provider.apiVersion == 1
        or (type(provider.supportsApi) == "function" and provider.supportsApi(1))
    assert(compatible, "Unsupported Mod Settings API")
    local features = provider.features or {}
    assert(features.sections and features.sliders and features.collapsibleSections,
        "Mod Settings requires sections, sliders and collapsible section support")

    local fields, keys = {}, {}
    local function add(key, id, section, label, description)
        local range = ranges[key]
        keys[id] = key
        fields[#fields + 1] = {
            id = id, section = section, label = label, description = description,
            default = config[key], applyMode = "mainMenu",
            pauseEditable = features.pauseMenu == true or nil,
            type = range and "number" or "boolean", control = range and "slider" or nil,
            min = range and range.min, max = range and range.max, step = range and range.step,
        }
        return fields[#fields]
    end
    local function placement(key, id, label, section, follow)
        local x = add(key .. "OffsetX", id .. "_offset_x", section, label .. " horizontal offset (%)",
            "Zero uses the stock position at the selected readout size. Positive moves right in 1% steps of scaled HUD width.")
        local y = add(key .. "OffsetY", id .. "_offset_y", section, label .. " vertical offset (%)",
            "Zero uses the stock position at the selected readout size. Positive moves up in 1% steps of scaled HUD height.")
        if follow then
            x.hiddenWhen = {setting = follow, equals = false}
            y.hiddenWhen = x.hiddenWhen
        end
    end

    add("Center", "center", "sizes", "Pitch ladder size",
        "Scale the pitch marks, center instruments, EEGS circle and pipper. The camera FOV sets the spacing between marks.")
    add("GunReticle", "gun_reticle", "sizes", "Gun reticle size",
        "Scale the stock gun reticle in cockpit and HUD views. The EEGS pipper uses Pitch ladder size.")
    add("TargetBoxes", "target_boxes", "sizes", "Target box size",
        "Scale target boxes for all factions in cockpit, HUD and third-person views. 1.00 uses the stock size.")
    -- Retain the original speed slider's storage ID for existing player overrides.
    add("ReadoutSize", "speed_size", "sizes", "Readout size",
        "Set the shared size and spacing of speed, altitude and bearing, including the optional third-person bearing. In the cockpit this applies to followed readouts.")
    add("VisorMask", "visor_mask", "cockpit", "Mask HUD to cockpit sight",
        "Keep the center HUD inside the cockpit sight on aircraft with a HUD glass profile.")
    add("FixedReadouts", "fixed_readouts", "cockpit", "Follow camera with speed and altitude",
        "Keep speed and altitude readouts at their screen positions as you look around the cockpit.")
    -- Keep the stored compass IDs so existing cockpit and HUD menu overrides still apply.
    add("RelativeBearing", "fixed_compass", "cockpit", "Relative bearing",
        "Keep the bearing fixed on screen and show the camera heading. Turn off to use the aircraft compass on the cockpit HUD.")
    local detach = add("DetachForward", "detach_forward", "cockpit", "Detach readouts when facing forward",
        "Place followed readouts on the cockpit HUD within 15 degrees of the nose. A bearing on the cockpit HUD shows aircraft heading.")
    if features.readOnlyWhenAll then
        detach.readOnlyWhenAll = {{setting = "fixed_readouts", equals = false}, {setting = "fixed_compass", equals = false}}
    end
    add("HUDFixedReadouts", "hud_fixed_readouts", "hud_view", "Follow camera with speed and altitude",
        "Keep speed and altitude fixed on screen during HUD free look. Turn off to move them with the flight instruments.")
    add("HUDRelativeBearing", "hud_fixed_compass", "hud_view", "Relative bearing",
        "Keep the bearing fixed on screen and show the camera heading. Turn off to move it with the HUD and show aircraft heading.")
    local hudDetach = add("HUDDetachForward", "hud_detach_forward", "hud_view", "Detach readouts when facing forward",
        "Within 15 degrees of the nose, place followed readouts on the HUD using Fixed readout positions. The bearing there shows aircraft heading.")
    if features.readOnlyWhenAll then
        hudDetach.readOnlyWhenAll = {{setting = "hud_fixed_readouts", equals = false}, {setting = "hud_fixed_compass", equals = false}}
    end
    add("ThirdPersonBearing", "third_person_bearing", "third_person", "Show camera bearing",
        "Draw the camera bearing above the aircraft. The tape and heading use the shared readout size.")
    local function notification(name, glyph)
        local setting = add(name .. "Notification", name:lower() .. "_notification", "notifications", name:upper(),
            "Show uses the game's popup. Hide suppresses this notification. Discreet shows a small " .. glyph .. " just off center for one second.")
        setting.type = "enum"
        setting.choices = {{value = "show", label = "SHOW"}, {value = "hide", label = "HIDE"},
            {value = "discreet", label = "DISCREET"}}
    end
    notification("Hit", "+")
    notification("Destroyed", "x")
    notification("Missed", "o")
    -- Retain the mode ID used by existing three-position menu overrides.
    local mode = add("EEGSMode", "eegs_enabled", "eegs", "EEGS mode",
        "Off keeps the pitch ladder. Automatic shows EEGS when the selected airborne target is in range. In Manual, hold Switch Weapon to toggle EEGS.")
    mode.type = "enum"
    mode.choices = {{value = "off", label = "Off"}, {value = "automatic", label = "Automatic"}, {value = "manual", label = "Manual"}}
    local range = add("EEGSRange", "eegs_range", "eegs", "Activation range (m)",
        "Sets the Automatic entry distance. In both modes the active gun reticle reaches 110% of this setting. Automatic EEGS closes beyond that distance.")
    range.hiddenWhen = {setting = "eegs_enabled", equals = "off"}
    local advancedSection = features.embeddedSections and "eegs_advanced" or "eegs"
    local function advancedSlider(key, id, label, description)
        add(key, id, advancedSection, label, description).hiddenWhen = range.hiddenWhen
    end
    advancedSlider("EEGSCircleHeight", "eegs_circle_height", "Circle height (%)",
        "Move the circle by a percentage of its diameter. Positive values raise it. Zero centers it on the nose. At -10%, the nose sits 60% of the way up.")
    advancedSlider("FunnelMuzzleSpeed", "eegs_muzzle_speed", "Muzzle speed (m/s)",
        "Set the reference bullet speed for the funnel calculation. The stock gun fires at about 1390 m/s.")
    advancedSlider("FunnelWingspan", "eegs_wingspan", "Reference wingspan (m)",
        "Set the wingspan represented by the gap between the funnel rails at each range.")
    local sections = {
        { id = "sizes", label = "Shared sizes" },
        { id = "cockpit", label = "Cockpit view" },
        { id = "eegs", label = "Enhanced Envelope Gun Sight", collapsible = true },
        { id = "hud_view", label = "HUD view" },
        { id = "third_person", label = "Third-person view" },
        { id = "notifications", label = "Notifications" },
        { id = "positions", label = "Fixed readout positions", collapsible = true },
        { id = "forward_positions", label = "Cockpit forward readout positions", collapsible = true,
            readOnlyWhen = {setting = "detach_forward", equals = false} },
    }
    if features.embeddedSections then
        sections[#sections + 1] = {id = advancedSection, parent = "eegs", label = "Advanced"}
    end
    placement("Speed", "speed", "Speed", "positions")
    placement("Altitude", "altitude", "Altitude", "positions")
    placement("Compass", "compass", "Bearing", "positions")
    placement("ForwardSpeed", "forward_speed", "Speed", "forward_positions", "fixed_readouts")
    placement("ForwardAltitude", "forward_altitude", "Altitude", "forward_positions", "fixed_readouts")
    placement("ForwardCompass", "forward_compass", "Bearing", "forward_positions", "fixed_compass")

    return provider.attach({
        id = "ac8.enhancedhud", name = "Enhanced HUD", schemaVersion = 17,
        sections = sections,
        settings = fields,
        read = function()
            local snapshot = {}
            for id, key in pairs(keys) do snapshot[id] = config[key] end
            return snapshot
        end,
        onChanged = function(snapshot)
            for id, key in pairs(keys) do config[key] = snapshot[id] end
        end,
    })
end
