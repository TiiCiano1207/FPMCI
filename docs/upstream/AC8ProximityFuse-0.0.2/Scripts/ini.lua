-- ============================================================================
--  AC8ProximityFuse v0.0.2 - INI Configuration Parser (Lua 5.4)
-- ============================================================================
--  Handles numeric values, UTF-8 BOM, comments (# and ;), optional sections,
--  and validates ranges with graceful fallbacks. Never crashes.
-- ============================================================================

local ini = {}

-- Define default configuration and validation schema
local DEFAULTS = {
    enabled               = 1,
    fusemode              = 1,
    triggerradiusmeters   = 30.0,
    explosionradiusmeters = 50.0,
    areadamage            = 30.0,
    loglevel              = 1,
    msl                   = 1,
    qaam                  = 1,
    hvaa                  = 1,
    laam                  = 1,
    hcaa                  = 1,
    hpaa                  = 1,
    saam                  = 1,
    sasm                  = 1,
    ["2aam"]              = 1,
    ["4aam"]              = 1,
    ["6aam"]              = 1,
}

local RULES = {
    enabled               = { min = 0,   max = 1,   integer = true  },
    fusemode              = { min = 0,   max = 1,   integer = true  },
    triggerradiusmeters   = { min = 1,   max = 200, integer = false },
    explosionradiusmeters = { min = 1,   max = 500, integer = false },
    areadamage            = { min = 1,   max = 500, integer = false },
    loglevel              = { min = 0,   max = 2,   integer = true  },
    msl                   = { min = 0,   max = 1,   integer = true  },
    qaam                  = { min = 0,   max = 1,   integer = true  },
    hvaa                  = { min = 0,   max = 1,   integer = true  },
    laam                  = { min = 0,   max = 1,   integer = true  },
    hcaa                  = { min = 0,   max = 1,   integer = true  },
    hpaa                  = { min = 0,   max = 1,   integer = true  },
    saam                  = { min = 0,   max = 1,   integer = true  },
    sasm                  = { min = 0,   max = 1,   integer = true  },
    ["2aam"]              = { min = 0,   max = 1,   integer = true  },
    ["4aam"]              = { min = 0,   max = 1,   integer = true  },
    ["6aam"]              = { min = 0,   max = 1,   integer = true  },
}

-- Normalize key name (lowercase and alias mapping)
local function normalize_key(k)
    local lower = k:lower()
    if lower == "aam2" then return "2aam" end
    if lower == "aam4" then return "4aam" end
    if lower == "aam6" then return "6aam" end
    return lower
end

function ini.parse(file_path)
    local config = {}
    local warnings = {}

    -- Initialize with default values
    for k, v in pairs(DEFAULTS) do
        config[k] = v
    end

    local file, open_err = io.open(file_path, "r")
    if not file then
        table.insert(warnings, "Could not open settings.ini (" .. tostring(open_err) .. "), using default configuration.")
        return config, warnings
    end

    local content = file:read("*a")
    file:close()

    if not content then
        table.insert(warnings, "Empty or unreadable settings.ini, using default configuration.")
        return config, warnings
    end

    -- Strip UTF-8 BOM if present
    content = content:gsub("^\239\187\191", "")

    local line_number = 0
    for raw_line in (content .. "\n"):gmatch("(.-)\r?\n") do
        line_number = line_number + 1

        -- Strip comments (# and ;)
        local line = raw_line:gsub("[#;].*$", ""):match("^%s*(.-)%s*$")

        if line ~= "" then
            -- Check for section header [SectionName] (sections are optional)
            local section = line:match("^%[([^%]]+)%]$")
            if not section then
                -- Match Key = Value
                local raw_key, raw_val = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
                if raw_key and raw_val then
                    local norm_key = normalize_key(raw_key)
                    local rule = RULES[norm_key]

                    if not rule then
                        table.insert(warnings, string.format("Line %d: Unknown configuration key '%s', ignored.", line_number, raw_key))
                    else
                        local num = tonumber(raw_val)
                        if not num or num ~= num or num == math.huge or num == -math.huge then
                            table.insert(warnings, string.format("Line %d: Invalid numeric value '%s' for '%s', keeping default (%s).", line_number, raw_val, raw_key, tostring(DEFAULTS[norm_key])))
                        elseif num < rule.min or num > rule.max then
                            table.insert(warnings, string.format("Line %d: Value %s for '%s' out of range [%s, %s], keeping default (%s).", line_number, tostring(num), raw_key, tostring(rule.min), tostring(rule.max), tostring(DEFAULTS[norm_key])))
                        elseif rule.integer and (num % 1 ~= 0) then
                            table.insert(warnings, string.format("Line %d: Value %s for '%s' must be an integer, keeping default (%s).", line_number, tostring(num), raw_key, tostring(DEFAULTS[norm_key])))
                        else
                            config[norm_key] = num
                        end
                    end
                else
                    table.insert(warnings, string.format("Line %d: Unrecognized syntax '%s', skipped.", line_number, line))
                end
            end
        end
    end

    return config, warnings
end

setmetatable(ini, {
    __call = function(_, file_path)
        return ini.parse(file_path)
    end
})

return ini
