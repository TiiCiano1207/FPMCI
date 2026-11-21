-- Game weapon names are resolved through the supplied 2.6 definitions.
local additions = {
    ["F-14A"] = {"LAAM"}, ["F-14D"] = {"2AAM"}, ["F-15C"] = {"HPAA"},
    ["F-15J"] = {"HVAA"}, ["F-16C"] = {"GPB"}, ["F-22A"] = {"SAAM"},
    ["F/A-36"] = {"4AAM"}, ["MiG-21bis"] = {"RKT"}, ["MiG-29A"] = {"4AAM"},
    ["MiG-31B"] = {"4AAM"}, ["Su-57"] = {"HVAA"}, ["Typhoon"] = {"HCAA"},
    ["A-10C"] = {"SFFS"}, ["A-6E"] = {"GPB"}, ["A-6E (MS15)"] = {"GPB"},
    ["F-2A"] = {"4AGM"}, ["F-15E"] = {"LAGM"}, ["Su-25"] = {"RKT"}, ["Su-34"] = {"LASM"},
    ["EA-6B"] = {"2AAM"}, ["EA-18G"] = {"LAGM"}, ["EA-36"] = {"HCAA"},
    ["F-4E"] = {"4AAM", "GPB"},
    ["F/A-18C"] = {"MGP", "HCAA"}, ["F/A-18E"] = {"MGP", "4AGM"},
    ["F/A-18F"] = {"MGP", "SAAM"}, ["Gripen E"] = {"MGP", "HCAA"},
    ["Mirage 2000-5"] = {"MGP", "QAAM"}, ["Rafale M"] = {"MGP", "GPB"},
    ["Su-33"] = {"MGP", "4AGM"}, ["Su-35"] = {"MGP", "HPAA"},
    ["Su-47"] = {"MGP", "4AGM"}, ["F-35C"] = {"MGP", "SAAM"},
    ["X-40A"] = {"MGP", "GPB"}, ["ADFX-02"] = {"MGP", "4AAM"},
}

-- Vanilla campaign single/paired reserves. Donors (in order below):
-- F-4E, Mirage 2000-5, F-14D, F-15C, Su-25SM, F-14A, F-16C, MiG-29A.
local reserves = {
    -- Campaign donors: F-14D, F-16C, F-2A, A-10C, Su-25SM, A-6E, F/A-18C.
    LAAM={22,12}, ["2AAM"]={26,14}, HVAA={22,12}, RKT={26,13},
    SFFS={22,12}, LAGM={18,10}, LASM={10,6},
    MGP={2400,1200}, ["4AAM"]={24,12}, GPB={12,6}, HCAA={30,16},
    ["4AGM"]={24,12}, SAAM={22,12}, QAAM={20,10}, HPAA={22,12},
}

return function(defs)
    local pools, campaign = {}, {}
    for _,d in ipairs(defs.aircraft) do
        local pool = {}
        for _,id in ipairs(d.catalog or d.original) do pool[id] = true end
        for _,name in ipairs(additions[d.section] or {}) do
            local id = assert(defs.weapons[name],name)
            assert(not pool[id],"Duplicate candidate: "..d.section.." "..name)
            pool[id] = true
        end
        pools[d.code] = pool
    end
    for name,pair in pairs(reserves) do campaign[assert(defs.weapons[name])] = pair end
    return {pools=pools, additions=additions, campaign=campaign}
end
