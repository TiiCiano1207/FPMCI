-- ============================================================================
-- AC8ProximityFuse v0.0.2 - Player Air-to-Air Missile Proximity Fuse Mod
-- Target: ACE COMBAT 8 (UE5.4 / UE4SS v3.0.1 Lua 5.4)
-- Scope : Player air-to-air missiles ONLY (BP_plwp_* + DT_WeaponSettings)
-- Mode 1: Multi-layer property write (CDO + DataTable + Live Instance)
--         + Active Mode 1 Proximity Airburst trigger & HP telemetry
-- ============================================================================

local PREFIX = "[AC8ProximityFuse] "
local VERSION = "0.0.2"

-- ----------------------------------------------------------------------------
-- 1. Path Resolution & File Logger
-- ----------------------------------------------------------------------------
local script_dir = ""
local mod_root = ""
do
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and type(src) == "string" then
        src = src:gsub("^@", "")
        script_dir = src:match("^(.*[/\\])") or ""
        mod_root = script_dir:match("^(.*[/\\])Scripts[/\\]?$") or script_dir
    end
end

local log_path = mod_root .. "AC8ProximityFuse.log"

local function log_msg(level, msg)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local line = string.format("[%s] [%s] %s\n", timestamp, level, tostring(msg))
    print(PREFIX .. "[" .. level .. "] " .. tostring(msg) .. "\n")
    pcall(function()
        local f = io.open(log_path, "a")
        if f then
            f:write(line)
            f:close()
        end
    end)
end

-- Initialize fresh log on startup
pcall(function()
    local f = io.open(log_path, "w")
    if f then
        f:write(string.format("=== AC8ProximityFuse v%s Log Started at %s ===\n", VERSION, os.date("%Y-%m-%d %H:%M:%S")))
        f:close()
    end
end)

-- Safe reflection helpers (never call methods on invalid wrappers)
local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function valid(o)
    return o ~= nil and safe(function() return o:IsValid() end) == true
end

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function eq_num(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    return math.abs(a - b) <= math.max(1e-4, math.max(math.abs(a), math.abs(b)) * 1e-5)
end

-- ----------------------------------------------------------------------------
-- 2. Configuration Schema & Hot-Reloadable INI Parser
-- ----------------------------------------------------------------------------
-- Load local ini.lua via dofile to avoid UE4SS global package.loaded["ini"] collisions
local ok_ini_mod, ini_mod = pcall(dofile, script_dir .. "ini.lua")

local function make_default_cfg()
    return {
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
end

local cfg = make_default_cfg()
local ini_path = mod_root .. "settings.ini"

local function reload_config()
    if ok_ini_mod and type(ini_mod) == "table" and type(ini_mod.parse) == "function" then
        local ok_cfg, loaded_cfg, warnings = pcall(ini_mod.parse, ini_path)
        if ok_cfg and type(loaded_cfg) == "table" then
            cfg = loaded_cfg
            if type(warnings) == "table" then
                for _, w in ipairs(warnings) do
                    log_msg("WARN", "INI: " .. tostring(w))
                end
            end
            log_msg("INFO", string.format(
                "Loaded settings.ini -> FuseMode=%d, TriggerRadius=%.1fm, ExplosionRadius=%.1fm, AreaDamage=%.1f",
                cfg.fusemode or 1, cfg.triggerradiusmeters or 30.0, cfg.explosionradiusmeters or 50.0, cfg.areadamage or 30.0))
            return true
        else
            log_msg("WARN", "settings.ini parse warning (" .. tostring(loaded_cfg) .. "), keeping current/default values.")
            return false
        end
    else
        log_msg("WARN", "Scripts/ini.lua not available (" .. tostring(ini_mod) .. "), using default settings.")
        return false
    end
end

reload_config()

-- ----------------------------------------------------------------------------
-- 3. Player Air-to-Air Missile Blueprint Profiles (30 Variants) & DataTable
-- ----------------------------------------------------------------------------
local BASE_MSL_CLASS_PATH = "/Game/Blueprints/Weapons/MSL/BP_wp_msl_BaseClass.BP_wp_msl_BaseClass_C"
local WEAPON_TABLE_PATH   = "/Game/Datatables/Player/DT_WeaponSettings.DT_WeaponSettings"
local DIFFICULTY_ROWS     = { "C.STORY", "EASY", "NORMAL", "HARD", "ACE", "VERY EASY", "CASUAL", "EXPERT", "FREE" }

local MISSILE_PROFILES = {
    -- 2aam (1 variant)
    { type = "2aam", row = "BP_plwp_2aam_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/2aam/BP_plwp_2aam_a0.BP_plwp_2aam_a0_C" },

    -- 4aam (2 variants)
    { type = "4aam", row = "BP_plwp_4aam_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/4aam/BP_plwp_4aam_a0.BP_plwp_4aam_a0_C" },
    { type = "4aam", row = "BP_plwp_4aam_f0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/4aam/BP_plwp_4aam_f0.BP_plwp_4aam_f0_C" },

    -- 6aam (2 variants)
    { type = "6aam", row = "BP_plwp_6aam_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/6aam/BP_plwp_6aam_a0.BP_plwp_6aam_a0_C" },
    { type = "6aam", row = "BP_plwp_6aam_r0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/6aam/BP_plwp_6aam_r0.BP_plwp_6aam_r0_C" },

    -- hcaa (5 variants)
    { type = "hcaa", row = "BP_plwp_hcaa_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hcaa/BP_plwp_hcaa_a0.BP_plwp_hcaa_a0_C" },
    { type = "hcaa", row = "BP_plwp_hcaa_f0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hcaa/BP_plwp_hcaa_f0.BP_plwp_hcaa_f0_C" },
    { type = "hcaa", row = "BP_plwp_hcaa_j0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hcaa/BP_plwp_hcaa_j0.BP_plwp_hcaa_j0_C" },
    { type = "hcaa", row = "BP_plwp_hcaa_r0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hcaa/BP_plwp_hcaa_r0.BP_plwp_hcaa_r0_C" },
    { type = "hcaa", row = "BP_plwp_hcaa_r1", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hcaa/BP_plwp_hcaa_r1.BP_plwp_hcaa_r1_C" },

    -- hpaa (3 variants)
    { type = "hpaa", row = "BP_plwp_hpaa_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hpaa/BP_plwp_hpaa_a0.BP_plwp_hpaa_a0_C" },
    { type = "hpaa", row = "BP_plwp_hpaa_j0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hpaa/BP_plwp_hpaa_j0.BP_plwp_hpaa_j0_C" },
    { type = "hpaa", row = "BP_plwp_hpaa_r0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hpaa/BP_plwp_hpaa_r0.BP_plwp_hpaa_r0_C" },

    -- hvaa (2 variants)
    { type = "hvaa", row = "BP_plwp_hvaa_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hvaa/BP_plwp_hvaa_a0.BP_plwp_hvaa_a0_C" },
    { type = "hvaa", row = "BP_plwp_hvaa_r0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Hvaa/BP_plwp_hvaa_r0.BP_plwp_hvaa_r0_C" },

    -- laam (3 variants)
    { type = "laam", row = "BP_plwp_laam_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Laam/BP_plwp_laam_a0.BP_plwp_laam_a0_C" },
    { type = "laam", row = "BP_plwp_laam_e0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Laam/BP_plwp_laam_e0.BP_plwp_laam_e0_C" },
    { type = "laam", row = "BP_plwp_laam_r0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Laam/BP_plwp_laam_r0.BP_plwp_laam_r0_C" },

    -- msl (5 variants)
    { type = "msl",  row = "BP_plwp_msl_a0",  path = "/Game/Blueprints/Weapons/MSL/PLAYER/MSL/BP_plwp_msl_a0.BP_plwp_msl_a0_C" },
    { type = "msl",  row = "BP_plwp_msl_a1",  path = "/Game/Blueprints/Weapons/MSL/PLAYER/MSL/BP_plwp_msl_a1.BP_plwp_msl_a1_C" },
    { type = "msl",  row = "BP_plwp_msl_f0",  path = "/Game/Blueprints/Weapons/MSL/PLAYER/MSL/BP_plwp_msl_f0.BP_plwp_msl_f0_C" },
    { type = "msl",  row = "BP_plwp_msl_j0",  path = "/Game/Blueprints/Weapons/MSL/PLAYER/MSL/BP_plwp_msl_j0.BP_plwp_msl_j0_C" },
    { type = "msl",  row = "BP_plwp_msl_r0",  path = "/Game/Blueprints/Weapons/MSL/PLAYER/MSL/BP_plwp_msl_r0.BP_plwp_msl_r0_C" },

    -- qaam (2 variants)
    { type = "qaam", row = "BP_plwp_qaam_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Qaam/BP_plwp_qaam_a0.BP_plwp_qaam_a0_C" },
    { type = "qaam", row = "BP_plwp_qaam_r0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Qaam/BP_plwp_qaam_r0.BP_plwp_qaam_r0_C" },

    -- saam (3 variants)
    { type = "saam", row = "BP_plwp_saam_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Saam/BP_plwp_saam_a0.BP_plwp_saam_a0_C" },
    { type = "saam", row = "BP_plwp_saam_r0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Saam/BP_plwp_saam_r0.BP_plwp_saam_r0_C" },
    { type = "saam", row = "BP_plwp_saam_r1", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Saam/BP_plwp_saam_r1.BP_plwp_saam_r1_C" },

    -- sasm (2 variants)
    { type = "sasm", row = "BP_plwp_sasm_a0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Sasm/BP_plwp_sasm_a0.BP_plwp_sasm_a0_C" },
    { type = "sasm", row = "BP_plwp_sasm_r0", path = "/Game/Blueprints/Weapons/MSL/PLAYER/Sasm/BP_plwp_sasm_r0.BP_plwp_sasm_r0_C" },
}

-- Fast lookup by lowercased class leaf name (e.g. "bp_plwp_msl_a0_c" -> "msl")
local LEAF_TO_TYPE = {}
local LEAF_TO_PATH = {}
for _, p in ipairs(MISSILE_PROFILES) do
    local k1 = string.lower(p.row .. "_c")
    local k2 = string.lower(p.row)
    LEAF_TO_TYPE[k1] = p.type
    LEAF_TO_TYPE[k2] = p.type
    LEAF_TO_PATH[k1] = p.path
    LEAF_TO_PATH[k2] = p.path
end

local function get_object_leaf(obj)
    if not valid(obj) then return nil end
    local cls = safe(function() return obj:GetClass() end)
    if not valid(cls) then return nil end
    local fname = safe(function() return cls:GetFName():ToString() end)
    return type(fname) == "string" and fname or nil
end

local function get_missile_type(obj)
    local leaf = get_object_leaf(obj)
    if not leaf then return nil, nil, nil end
    local lower = string.lower(leaf)
    return LEAF_TO_TYPE[lower], leaf, LEAF_TO_PATH[lower]
end

-- ----------------------------------------------------------------------------
-- 4. State Tracking & Verified GC Retention
-- ----------------------------------------------------------------------------
local original_cdo_values   = {} -- [path] = { [field] = val }
local original_table_values = {} -- [rowName] = { [field] = val }
local missile_journals      = {} -- [addr] = { orig_MaxHomingAngle, orig_MaxHomingAngleNotCaptured, orig_LifeTime, triggered }
local is_applying           = false
local bp_prox_hooked        = false
local flight_monitor_active = false
local flight_monitor_ticks  = 0

-- Acquire GameInstance.ReferencedObjects retention handle with readback verification
local function acquire_gc_holder()
    local engine = safe(function() return FindFirstOf("GameEngine") end)
    if not valid(engine) then return nil end
    local viewport = safe(function() return engine.GameViewport end)
    if not valid(viewport) then return nil end
    local world = safe(function() return viewport.World end)
    if not valid(world) then return nil end
    local gi = safe(function() return world.OwningGameInstance end)
    if not valid(gi) then return nil end
    local refs = safe(function() return gi.ReferencedObjects end)
    if not refs then return nil end
    local len = safe(function() return #refs end)
    if type(len) ~= "number" or len < 0 or len > 2048 then return nil end

    local existing = {}
    for i = 1, len do
        local item = safe(function() return refs[i] end)
        if valid(item) then
            local addr = safe(function() return item:GetAddress() end)
            if addr then existing[addr] = true end
        end
    end

    local total_held = 0
    return {
        hold = function(obj)
            if not valid(obj) then return false end
            local addr = safe(function() return obj:GetAddress() end)
            if not addr then return false end
            if existing[addr] then
                total_held = total_held + 1
                return true
            end
            local cur_len = safe(function() return #refs end)
            if type(cur_len) ~= "number" or cur_len >= 2048 then return false end
            local at = cur_len + 1
            local ok_set = pcall(function() refs[at] = obj end)
            if not ok_set then return false end
            local stored = safe(function() return refs[at] end)
            local stored_addr = valid(stored) and safe(function() return stored:GetAddress() end) or nil
            if stored_addr == addr then
                existing[addr] = true
                total_held = total_held + 1
                return true
            end
            return false
        end,
        count = function() return total_held end
    }
end

local function load_or_find_asset(path)
    local obj = safe(function() return LoadAsset(path) end)
    if valid(obj) then return obj end
    obj = safe(function() return StaticFindObject(path) end)
    if valid(obj) then return obj end
    return nil
end

-- ----------------------------------------------------------------------------
-- 5. Pooled Missile Restoration & Live Instance Patching
-- ----------------------------------------------------------------------------
local function restore_pooled_missile(weapon)
    if not valid(weapon) then return end
    local addr = safe(function() return weapon:GetAddress() end)
    if not addr then return end
    local j = missile_journals[addr]
    if not j then return end

    if j.orig_MaxHomingAngle ~= nil then
        pcall(function() weapon.MaxHomingAngle = j.orig_MaxHomingAngle end)
    end
    if j.orig_MaxHomingAngleNotCaptured ~= nil then
        pcall(function() weapon.MaxHomingAngleNotCaptured = j.orig_MaxHomingAngleNotCaptured end)
    end
    if j.orig_LifeTime ~= nil then
        pcall(function() weapon.LifeTime = j.orig_LifeTime end)
    end
    missile_journals[addr] = nil
end

local function apply_fields_to_weapon_object(obj, mtype, cdo_path)
    if not valid(obj) then return 0 end
    local enabled = (cfg.enabled ~= 0) and (cfg[mtype] ~= 0)
    local orig_map = cdo_path and original_cdo_values[cdo_path] or nil

    local target_rad_sq = (cfg.triggerradiusmeters * 100.0) ^ 2
    local target_blast  = cfg.explosionradiusmeters * 100.0
    local target_dmg    = cfg.areadamage
    local changed = 0

    local function set_prop(k, enabled_val, is_bool)
        local cur = safe(function() return obj[k] end)
        if cur == nil then return end
        local desired = enabled_val
        if not enabled then
            if orig_map and orig_map[k] ~= nil then
                desired = orig_map[k]
            else
                return
            end
        end
        local same = is_bool and (cur == desired) or eq_num(cur, desired)
        if not same then
            if pcall(function() obj[k] = desired end) then
                changed = changed + 1
            end
        end
    end

    set_prop("bShouldDetonateOnMiss",      true,          true)
    set_prop("ProximityFuseRadiusSquared", target_rad_sq, false)
    set_prop("ProximityFuseDuration",      0.0,           false)
    set_prop("ExplosionRadius",            target_blast,  false)
    set_prop("AreaOfEffectDamage",         target_dmg,    false)
    return changed
end

local function patch_live_missile(weapon, reason)
    if not valid(weapon) then return end
    local mtype, leaf, cdo_path = get_missile_type(weapon)
    if not mtype then return end

    -- Always restore any prior Mode 1 homing override on pooled missile reuse
    restore_pooled_missile(weapon)

    apply_fields_to_weapon_object(weapon, mtype, cdo_path)
end

-- ----------------------------------------------------------------------------
-- 6. Mode 1 Active Proximity Airburst & Telemetry
-- ----------------------------------------------------------------------------
local function is_missile_in_flight(weapon)
    if not valid(weapon) then return false end
    if safe(function() return weapon.bHidden end) ~= false then return false end
    if safe(function() return weapon.bCollided end) ~= false then return false end
    local mov = safe(function() return weapon.WeaponMovement end)
    if valid(mov) and safe(function() return mov.bSimulationEnabled end) == false then
        return false
    end
    return true
end

local function get_distance_cm(weapon, target)
    local a = safe(function() return weapon:K2_GetActorLocation() end)
    local b = safe(function() return target:K2_GetActorLocation() end)
    if a and b and finite(a.X) and finite(a.Y) and finite(a.Z) and finite(b.X) and finite(b.Y) and finite(b.Z) then
        local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    local dsq = safe(function() return weapon.DistanceFromTargetSquared end)
    if finite(dsq) and dsq >= 0 then
        return math.sqrt(dsq)
    end
    return nil
end

local function check_or_trigger_proximity(weapon, source_tag)
    if cfg.enabled == 0 then return false end
    if not is_missile_in_flight(weapon) then return false end
    local mtype, leaf, cdo_path = get_missile_type(weapon)
    if not mtype or cfg[mtype] == 0 then return false end

    local addr = safe(function() return weapon:GetAddress() end)
    if not addr then return false end
    local j = missile_journals[addr]
    if j and j.triggered then return false end

    local target = safe(function() return weapon.TargetToHome end)
    if not valid(target) then
        local mov = safe(function() return weapon.WeaponMovement end)
        if valid(mov) then
            target = safe(function() return mov.HomingTarget end)
        end
    end
    if not valid(target) then return false end

    local hp_before = safe(function() return target:GetHealth() end)
    if finite(hp_before) and hp_before <= 0 then return false end

    local dist_cm = get_distance_cm(weapon, target)
    local limit_cm = cfg.triggerradiusmeters * 100.0
    if not finite(dist_cm) or dist_cm > limit_cm then return false end

    -- If a stale journal existed from an uncleaned cycle, restore before reading baseline
    if missile_journals[addr] then
        restore_pooled_missile(weapon)
    end

    -- Ensure explosion parameters are live on the missile right before airburst
    apply_fields_to_weapon_object(weapon, mtype, cdo_path)

    local entry = {
        orig_MaxHomingAngle            = safe(function() return weapon.MaxHomingAngle end),
        orig_MaxHomingAngleNotCaptured = safe(function() return weapon.MaxHomingAngleNotCaptured end),
        orig_LifeTime                  = safe(function() return weapon.LifeTime end),
        triggered                      = true,
    }
    missile_journals[addr] = entry

    local dist_m = dist_cm / 100.0

    if cfg.fusemode == 1 then
        -- Mode 1: Force immediate seeker cone miss so native bShouldDetonateOnMiss
        -- triggers airburst right at Closest Point of Approach (CPA) beside target
        pcall(function() weapon.bShouldDetonateOnMiss = true end)
        pcall(function() weapon.MaxHomingAngle = 0.0 end)
        pcall(function() weapon.MaxHomingAngleNotCaptured = 0.0 end)

        if type(ExecuteInGameThreadAfterFrames) == "function" then
            -- Frame +2 fallback: only if this exact journal entry is still active and missile still in flight
            pcall(function()
                ExecuteInGameThreadAfterFrames(2, function()
                    if missile_journals[addr] == entry
                        and is_missile_in_flight(weapon)
                        and safe(function() return weapon:GetAddress() end) == addr then
                        pcall(function() weapon.LifeTime = 0.001 end)
                    end
                end)
            end)

            -- Frame +4 telemetry: log target health delta and detonation confirmation
            pcall(function()
                ExecuteInGameThreadAfterFrames(4, function()
                    local hp_after = valid(target) and safe(function() return target:GetHealth() end) or nil
                    local still_same_entry = (missile_journals[addr] == entry)
                    local detonated = (not still_same_entry) or (not is_missile_in_flight(weapon))
                    log_msg("INFO", string.format(
                        "[PROX-AIRBURST] %s (%s) triggered at dist=%.1fm <= %.1fm | Target HP: %s -> %s | Detonated=%s",
                        tostring(leaf), tostring(source_tag), dist_m, cfg.triggerradiusmeters,
                        tostring(hp_before), tostring(hp_after), tostring(detonated)))
                    if still_same_entry and detonated and valid(weapon) and safe(function() return weapon:GetAddress() end) == addr then
                        restore_pooled_missile(weapon)
                    end
                end)
            end)
        else
            log_msg("INFO", string.format(
                "[PROX-AIRBURST] %s (%s) triggered at dist=%.1fm <= %.1fm | Target HP before=%s",
                tostring(leaf), tostring(source_tag), dist_m, cfg.triggerradiusmeters, tostring(hp_before)))
        end
    else
        log_msg("INFO", string.format(
            "[PROX-PASSIVE] %s (%s) entered proximity dist=%.1fm <= %.1fm (FuseMode=0 passive) | Target HP=%s",
            tostring(leaf), tostring(source_tag), dist_m, cfg.triggerradiusmeters, tostring(hp_before)))
    end

    return true
end

-- Get local player pawn via Engine ownership chain
local function get_local_player_pawn()
    local engine = safe(function() return FindFirstOf("GameEngine") end)
    if not valid(engine) then return nil end
    local viewport = safe(function() return engine.GameViewport end)
    if not valid(viewport) then return nil end
    local world = safe(function() return viewport.World end)
    if not valid(world) then return nil end
    local gi = safe(function() return world.OwningGameInstance end)
    if not valid(gi) then return nil end
    local players = safe(function() return gi.LocalPlayers end)
    local n = safe(function() return #players end)
    if type(n) ~= "number" or n < 1 or n > 4 then return nil end
    local p1 = safe(function() return players[1] end)
    if not valid(p1) then return nil end
    local pc = safe(function() return p1.PlayerController end)
    if not valid(pc) then return nil end
    local pawn = safe(function() return pc.Pawn end)
    if valid(pawn) then return pawn end
    return nil
end

-- Patch player plane's EquippedWeapons.Configs + pooled SpawnedWeapons / ActiveWeapons
local function patch_player_equipment(reason)
    local pawn = get_local_player_pawn()
    if not valid(pawn) then return 0, 0 end
    local act = safe(function() return pawn.PlayerWeaponActivator end)
    if not valid(act) then return 0, 0 end

    local cfg_patched = 0
    local inst_patched = 0

    local eq = safe(function() return act.EquippedWeapons end)
    if valid(eq) then
        local configs = safe(function() return eq.Configs end)
        local total = safe(function() return #configs end)
        if type(total) == "number" and total >= 1 and total <= 16 then
            for i = 1, total do
                local c = safe(function() return configs[i] end)
                local cdo = c and safe(function() return c.WeaponClassDefaultObject end) or nil
                if valid(cdo) then
                    local mtype, _, cdo_path = get_missile_type(cdo)
                    if mtype then
                        apply_fields_to_weapon_object(cdo, mtype, cdo_path)
                        cfg_patched = cfg_patched + 1
                    end
                end
            end
        end
    end

    for _, arr_name in ipairs({ "SpawnedWeapons", "ActiveWeapons" }) do
        local arr = safe(function() return act[arr_name] end)
        local n = safe(function() return #arr end)
        if type(n) == "number" and n >= 1 and n <= 512 then
            for i = 1, n do
                local w = safe(function() return arr[i] end)
                if valid(w) then
                    local mtype, _, cdo_path = get_missile_type(w)
                    if mtype then
                        apply_fields_to_weapon_object(w, mtype, cdo_path)
                        inst_patched = inst_patched + 1
                    end
                end
            end
        end
    end

    if cfg_patched > 0 or inst_patched > 0 then
        log_msg("DEBUG", string.format("Equipment sync (%s): Config CDOs=%d, Pooled instances=%d",
            tostring(reason), cfg_patched, inst_patched))
    end
    return cfg_patched, inst_patched
end

-- Bounded active flight monitor (only runs while player missiles are actively in flight)
local function step_flight_monitor()
    if not flight_monitor_active then return end
    flight_monitor_ticks = flight_monitor_ticks - 1
    if flight_monitor_ticks <= 0 then
        flight_monitor_active = false
        return
    end

    local in_flight_count = 0
    local visited = {}
    local pawn = get_local_player_pawn()
    if valid(pawn) then
        local act = safe(function() return pawn.PlayerWeaponActivator end)
        if valid(act) then
            for _, arr_name in ipairs({ "ActiveWeapons", "SpawnedWeapons" }) do
                local arr = safe(function() return act[arr_name] end)
                local n = safe(function() return #arr end)
                if type(n) == "number" and n >= 1 and n <= 256 then
                    for i = 1, n do
                        local w = safe(function() return arr[i] end)
                        if is_missile_in_flight(w) then
                            local addr = safe(function() return w:GetAddress() end)
                            if addr and not visited[addr] then
                                visited[addr] = true
                                local mtype = get_missile_type(w)
                                if mtype and cfg.enabled ~= 0 and cfg[mtype] ~= 0 then
                                    in_flight_count = in_flight_count + 1
                                    check_or_trigger_proximity(w, "FlightMonitor")
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if in_flight_count == 0 and flight_monitor_ticks < 280 then
        -- No missiles currently flying after initial launch window; stop monitor early
        flight_monitor_active = false
        return
    end

    if type(ExecuteInGameThreadAfterFrames) == "function" then
        pcall(function()
            ExecuteInGameThreadAfterFrames(1, step_flight_monitor)
        end)
    else
        flight_monitor_active = false
    end
end

local function start_flight_monitor()
    if cfg.enabled == 0 then return end
    flight_monitor_ticks = 300 -- ~5 seconds @ 60fps, renewed on each shot
    if flight_monitor_active then return end
    if type(ExecuteInGameThreadAfterFrames) ~= "function" then return end
    flight_monitor_active = true
    pcall(function()
        ExecuteInGameThreadAfterFrames(1, step_flight_monitor)
    end)
end

-- Install Blueprint hook on BP_wp_msl_BaseClass_C:OnTargetWithinProximity once loaded
local function install_proximity_bp_hook()
    if bp_prox_hooked or type(RegisterHook) ~= "function" then return end
    local base_cls = load_or_find_asset(BASE_MSL_CLASS_PATH)
    if not valid(base_cls) then return end

    local hook_path = BASE_MSL_CLASS_PATH .. ":OnTargetWithinProximity"
    local ok = pcall(function()
        RegisterHook(hook_path, function(context)
            local w = safe(function() return context:get() end)
            if valid(w) then
                check_or_trigger_proximity(w, "OnTargetWithinProximity")
            end
        end)
    end)
    if ok then
        bp_prox_hooked = true
        log_msg("INFO", "Hooked Blueprint proximity event: " .. hook_path)
    end
end

-- ----------------------------------------------------------------------------
-- 7. Core Patching Routine (CDOs + DT_WeaponSettings + Equipment)
-- ----------------------------------------------------------------------------
local function apply_patches(trigger_source)
    if is_applying then return end
    is_applying = true

    local ok_exec, exec_err = pcall(function()
        local holder = acquire_gc_holder()
        local classes_ok      = 0
        local classes_missing = 0
        local fields_written  = 0
        local fields_verified = 0
        local fields_same     = 0
        local table_rows_ok   = 0
        local table_written   = 0

        local target_bShouldDetonateOnMiss      = true
        local target_ProximityFuseRadiusSquared = (cfg.triggerradiusmeters * 100.0) ^ 2
        local target_ProximityFuseDuration      = 0.0
        local target_ExplosionRadius            = cfg.explosionradiusmeters * 100.0
        local target_AreaOfEffectDamage         = cfg.areadamage

        -- Also hold base missile blueprint class & install OnTargetWithinProximity hook
        local base_cls = load_or_find_asset(BASE_MSL_CLASS_PATH)
        if valid(base_cls) and holder then holder.hold(base_cls) end
        install_proximity_bp_hook()

        -- 7.1 Patch all 30 Player Missile Blueprint CDOs
        for _, profile in ipairs(MISSILE_PROFILES) do
            local cls = load_or_find_asset(profile.path)
            if not valid(cls) then
                classes_missing = classes_missing + 1
                log_msg("WARN", string.format("Class asset not found: %s (%s)", profile.row, profile.path))
            else
                classes_ok = classes_ok + 1
                if holder then holder.hold(cls) end

                local cdo = safe(function() return cls:GetCDO() end)
                if valid(cdo) then
                    if not original_cdo_values[profile.path] then
                        original_cdo_values[profile.path] = {}
                    end
                    local orig_map = original_cdo_values[profile.path]
                    local enabled = (cfg.enabled ~= 0) and (cfg[profile.type] ~= 0)

                    local function patch_cdo_field(field_name, enabled_val, is_bool)
                        local cur_val = safe(function() return cdo[field_name] end)
                        if cur_val == nil then return end

                        if orig_map[field_name] == nil then
                            orig_map[field_name] = cur_val
                        end

                        local desired = enabled and enabled_val or orig_map[field_name]
                        local already_same = is_bool and (cur_val == desired) or eq_num(cur_val, desired)

                        if already_same then
                            fields_same = fields_same + 1
                        else
                            local ok_w = pcall(function() cdo[field_name] = desired end)
                            if ok_w then
                                fields_written = fields_written + 1
                                local rb = safe(function() return cdo[field_name] end)
                                local ver = (rb ~= nil) and (is_bool and (rb == desired) or eq_num(rb, desired))
                                if ver then
                                    fields_verified = fields_verified + 1
                                else
                                    log_msg("WARN", string.format("Readback mismatch on %s.%s (wrote %s, got %s)",
                                        profile.row, field_name, tostring(desired), tostring(rb)))
                                end
                            end
                        end
                    end

                    patch_cdo_field("bShouldDetonateOnMiss",      target_bShouldDetonateOnMiss,      true)
                    patch_cdo_field("ProximityFuseRadiusSquared", target_ProximityFuseRadiusSquared, false)
                    patch_cdo_field("ProximityFuseDuration",      target_ProximityFuseDuration,      false)
                    patch_cdo_field("ExplosionRadius",            target_ExplosionRadius,            false)
                    patch_cdo_field("AreaOfEffectDamage",         target_AreaOfEffectDamage,         false)
                end
            end
        end

        -- 7.2 Patch Player Difficulty DataTable (/Game/Datatables/Player/DT_WeaponSettings)
        local dt = load_or_find_asset(WEAPON_TABLE_PATH)
        if valid(dt) then
            if holder then holder.hold(dt) end
            local msl_enabled = (cfg.enabled ~= 0) and (cfg.msl ~= 0)
            for _, row_name in ipairs(DIFFICULTY_ROWS) do
                local row = safe(function() return dt:FindRow(row_name) end)
                if row then
                    table_rows_ok = table_rows_ok + 1
                    if not original_table_values[row_name] then
                        original_table_values[row_name] = {}
                    end
                    local orig_row = original_table_values[row_name]

                    local function patch_row_field(field_name, enabled_val, is_bool)
                        local cur_val = safe(function() return row[field_name] end)
                        if cur_val == nil then return end
                        if orig_row[field_name] == nil then
                            orig_row[field_name] = cur_val
                        end
                        local desired = msl_enabled and enabled_val or orig_row[field_name]
                        local already_same = is_bool and (cur_val == desired) or eq_num(cur_val, desired)
                        if not already_same then
                            if pcall(function() row[field_name] = desired end) then
                                table_written = table_written + 1
                            end
                        end
                    end

                    patch_row_field("bShouldDetonateOnMiss", msl_enabled and true or false, true)
                    patch_row_field("ProximityFuseMeters",   cfg.triggerradiusmeters,       false)
                    patch_row_field("ExplosionRadiusMeters", cfg.explosionradiusmeters,     false)
                    patch_row_field("AreaOfEffectDamage",    cfg.areadamage,                false)
                end
            end
        else
            log_msg("WARN", "DT_WeaponSettings not loaded yet: " .. WEAPON_TABLE_PATH)
        end

        -- 7.3 Sync Local Player Equipment & Pooled Instances (if in mission)
        local eq_cfgs, eq_insts = patch_player_equipment(trigger_source)
        local gc_cnt = holder and holder.count() or 0

        log_msg("INFO", string.format(
            "Apply complete (%s) -> CDOs OK: %d/%d (Wrote: %d, Verified: %d, Same: %d) | DT_WeaponSettings Rows: %d (Wrote: %d) | Live Equip CDOs: %d, Pooled: %d | GC Held: %d",
            tostring(trigger_source), classes_ok, #MISSILE_PROFILES, fields_written, fields_verified, fields_same,
            table_rows_ok, table_written, eq_cfgs, eq_insts, gc_cnt))
    end)

    if not ok_exec then
        log_msg("ERROR", "Unhandled error inside apply_patches: " .. tostring(exec_err))
    end

    is_applying = false
end

-- ----------------------------------------------------------------------------
-- 8. Triggers, Lifecycle Hooks & F7 Hotkey
-- ----------------------------------------------------------------------------
local function safe_trigger_apply(source)
    if type(ExecuteInGameThread) == "function" then
        pcall(function()
            ExecuteInGameThread(function()
                apply_patches(source)
            end)
        end)
    else
        pcall(function() apply_patches(source) end)
    end
end

-- 8.1 Startup Trigger
if type(ExecuteInGameThreadAfterFrames) == "function" then
    pcall(function()
        ExecuteInGameThreadAfterFrames(2, function()
            safe_trigger_apply("StartupAfterFrames(2)")
        end)
    end)
else
    safe_trigger_apply("StartupImmediate")
end

-- 8.2 Map Load Cleanup & Mission Init Hook
if type(RegisterLoadMapPreHook) == "function" then
    pcall(function()
        RegisterLoadMapPreHook(function()
            missile_journals = {}
            flight_monitor_active = false
            flight_monitor_ticks = 0
        end)
    end)
end

if type(RegisterInitGameStatePreHook) == "function" then
    pcall(function()
        RegisterInitGameStatePreHook(function(context)
            local gm = context
            if context and type(context.get) == "function" then
                gm = safe(function() return context:get() end)
            end
            local full_name = valid(gm) and safe(function() return gm:GetFullName() end) or ""
            if type(full_name) == "string" and full_name:find("/Game/Maps/Ingame/", 1, true) then
                safe_trigger_apply("MissionInitGameState")
                -- Schedule delayed passes to catch on-demand streaming weapon assets
                if type(ExecuteInGameThreadAfterFrames) == "function" then
                    for _, f in ipairs({ 30, 120, 300 }) do
                        pcall(function()
                            ExecuteInGameThreadAfterFrames(f, function()
                                apply_patches("MissionDelayed(" .. tostring(f) .. "f)")
                            end)
                        end)
                    end
                end
            end
        end)
    end)
end

-- 8.3 Player Plane BeginPlay & Live Weapon Hooks
if type(RegisterBeginPlayPostHook) == "function" then
    pcall(function()
        RegisterBeginPlayPostHook(function(context)
            local actor = context and type(context.get) == "function" and safe(function() return context:get() end) or context
            if not valid(actor) then return end
            local leaf = get_object_leaf(actor)
            if not leaf then return end
            if leaf:match("^BP_PlayerPlane_") then
                patch_player_equipment("PlayerPlaneBeginPlay")
                if type(ExecuteInGameThreadAfterFrames) == "function" then
                    for _, f in ipairs({ 2, 30, 120 }) do
                        pcall(function()
                            ExecuteInGameThreadAfterFrames(f, function()
                                patch_player_equipment("PlayerPlaneDelayed(" .. tostring(f) .. "f)")
                            end)
                        end)
                    end
                end
            elseif LEAF_TO_TYPE[string.lower(leaf)] then
                patch_live_missile(actor, "MissileBeginPlay")
                start_flight_monitor()
            end
        end)
    end)
end

if type(RegisterHook) == "function" then
    -- Live weapon initialization hooks
    for _, ev in ipairs({ "OnInitialized", "OnCreateWeapon_BP" }) do
        local path = "/Script/Live.LiveWeaponBase:" .. ev
        pcall(function()
            RegisterHook(path, function() end, function(context)
                local w = context and type(context.get) == "function" and safe(function() return context:get() end) or context
                if valid(w) then
                    patch_live_missile(w, ev)
                    start_flight_monitor()
                end
            end)
        end)
    end

    -- Player weapon fire hook
    pcall(function()
        local function on_fire()
            patch_player_equipment("MainWeaponPressed")
            start_flight_monitor()
        end
        RegisterHook("/Script/Live.LivePlayerWeaponActivator:MainWeaponPressed", on_fire, on_fire)
    end)

    -- Pooled weapon pre-destruction cleanup hook
    pcall(function()
        RegisterHook("/Script/Live.LiveWeaponBase:OnWeaponDestroyed", function(context)
            local w = context and type(context.get) == "function" and safe(function() return context:get() end) or context
            if valid(w) then
                restore_pooled_missile(w)
            end
        end, function() end)
    end)
end

-- 8.4 Manual Hot-Reload Hotkey (F7): Re-reads settings.ini and re-applies immediately
if Key and Key.F7 then
    local function on_f7_pressed()
        log_msg("INFO", "F7 pressed -> Reloading settings.ini and re-applying proximity fuse patches...")
        reload_config()
        safe_trigger_apply("ManualHotkey(F7)")
    end

    local hooked_key = false
    if type(RegisterKeyBind) == "function" then
        local ok = pcall(function() RegisterKeyBind(Key.F7, on_f7_pressed) end)
        if ok then hooked_key = true end
    end
    if not hooked_key and type(RegisterKeyBindAsync) == "function" then
        local ok = pcall(function() RegisterKeyBindAsync(Key.F7, on_f7_pressed) end)
        if ok then hooked_key = true end
    end

    if hooked_key then
        log_msg("INFO", "Registered hotkey [F7] for hot-reloading settings.ini & re-applying patches.")
    else
        log_msg("WARN", "Failed to register [F7] hotkey in this UE4SS environment.")
    end
end

log_msg("INFO", string.format("AC8ProximityFuse v%s initialized successfully.", VERSION))
