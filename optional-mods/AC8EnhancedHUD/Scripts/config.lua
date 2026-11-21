local scale = {min = 0.25, max = 2, step = 0.01}
local offset = {min = -100, max = 100, step = 1}
local sections = {
    Sizes = {Center = {0.60, scale}, GunReticle = {0.60, scale}, ReadoutSize = {0.60, scale},
        TargetBoxes = {1.00, scale}},
    EEGS = {
        Mode = {"automatic", nil, "EEGSMode"},
        RangeMeters = {1400, {min = 100, max = 3000, step = 50}, "EEGSRange"},
        CircleHeightPercent = {-10, {min = -50, max = 50, step = 1}, "EEGSCircleHeight"},
        FunnelMuzzleSpeed = {1390, {min = 200, max = 2000, step = 10}},
        FunnelWingspan = {15, {min = 4, max = 80, step = 0.5}},
    },
    Cockpit = {VisorMask = {true}, FixedReadouts = {true}, RelativeBearing = {true}, DetachForward = {true}},
    HUDView = {FixedReadouts = {true, nil, "HUDFixedReadouts"}, RelativeBearing = {true, nil, "HUDRelativeBearing"},
        DetachForward = {true, nil, "HUDDetachForward"}},
    ThirdPerson = {CockpitHUD = {false, nil, "ChaseCockpitHUD"}, CustomBearing = {false, nil, "ThirdPersonBearing"}},
    Notifications = {Hit = {"show", nil, "HitNotification"}, Destroyed = {"show", nil, "DestroyedNotification"},
        Missed = {"show", nil, "MissedNotification"}},
    ReadoutPositions = {
        SpeedOffsetX = {0, offset}, SpeedOffsetY = {0, offset},
        AltitudeOffsetX = {0, offset}, AltitudeOffsetY = {0, offset},
        CompassOffsetX = {0, offset}, CompassOffsetY = {0, offset},
    },
    ForwardReadoutPositions = {},
}
local forwardOffsets = {SpeedOffsetX = 10, AltitudeOffsetX = -10, CompassOffsetY = -6}
for key in pairs(sections.ReadoutPositions) do
    sections.ForwardReadoutPositions[key] = {forwardOffsets[key] or 0, offset, "Forward" .. key}
end
-- Accept personalized INIs from releases through 0.4.3.
sections.FlightHUD = {VisorMask = sections.Cockpit.VisorMask, Center = sections.Sizes.Center, GunReticle = sections.Sizes.GunReticle}
sections.Readouts = {FixedReadouts = sections.Cockpit.FixedReadouts, RelativeBearing = sections.Cockpit.RelativeBearing,
    ReadoutSize = sections.Sizes.ReadoutSize}
local booleans = {["true"] = true, ["false"] = false, ["1"] = true, ["0"] = false,
    yes = true, no = false, on = true, off = false}
local legacyEEGS = {Enabled = "Mode"}

local function parse(raw, range)
    if not range then return booleans[raw:lower()] end
    local number = tonumber(raw)
    if not number or number ~= number or math.abs(number) == math.huge then return nil end
    local clamped = math.max(range.min, math.min(range.max, number))
    local units = 1 / range.step
    return math.floor(clamped * units + 0.5 + 1e-9) / units
end

return function(path, log)
    local config, ranges = {}, {}
    for _, fields in pairs(sections) do
        for key, spec in pairs(fields) do
            local name = spec[3] or key
            config[name], ranges[name] = spec[1], spec[2]
        end
    end
    local file, reason = io.open(path, "r")
    if not file then
        log("Using built-in defaults: " .. tostring(reason))
        return config, ranges
    end
    local fields
    local explicit = {}
    for raw in file:lines() do
        local line = raw:gsub("^\239\187\191", ""):gsub("[;#].*$", ""):match("^%s*(.-)%s*$")
        local section = line:match("^%[%s*(.-)%s*%]$")
        if section then
            fields = sections[section]
        elseif fields then
            local key, value = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
            -- A valid current spelling takes precedence over an alias in either order.
            local alias = fields == sections.EEGS and legacyEEGS[key]
            if key == "FixedCompass" then alias = "RelativeBearing" end
            local spec = fields[alias or key]
            if spec then
                local name = spec[3] or alias or key
                local parsed
                if fields == sections.Notifications then
                    local mode = value:lower()
                    if mode == "show" or mode == "hide" or mode == "discreet" then parsed = mode end
                elseif name == "EEGSMode" then
                    if key == "Enabled" then
                        local enabled = booleans[value:lower()]
                        if enabled ~= nil then parsed = enabled and "automatic" or "off" end
                    else
                        local mode = value:lower()
                        if mode == "off" or mode == "automatic" or mode == "manual" then parsed = mode end
                    end
                else
                    parsed = parse(value, spec[2])
                end
                if parsed == nil then
                    log("Invalid config.ini value for " .. name .. "; using " .. tostring(config[name]))
                elseif not alias or not explicit[name] then
                    config[name] = parsed
                    if not alias then explicit[name] = true end
                end
            end
        end
    end
    file:close()
    return config, ranges
end
