-- Read the installed image as data. A profile has exact byte runs and optional
-- signed RIP-relative references to other reviewed code or data.
local function read(file, offset, length)
    if not file:seek("set", offset) then return end
    local data = file:read(length)
    if data and #data == length then return data end
end

local function readSections(file)
    local dos = read(file, 0, 64)
    if not dos or dos:sub(1, 2) ~= "MZ" then return false end
    local pe = string.unpack("<I4", dos, 61)
    local header = read(file, pe, 26)
    if not header or header:sub(1, 4) ~= "PE\0\0" then return false end
    local machine, count = string.unpack("<I2I2", header, 5)
    local optional = string.unpack("<I2", header, 21)
    if machine ~= 0x8664 or count < 1 or count > 96 or optional < 2
        or string.unpack("<I2", header, 25) ~= 0x20b then return false end
    local headers = read(file, pe + 24 + optional, 40 * count)
    if not headers then return end
    local sections = {}
    for i = 0, count - 1 do
        local size, start, rawSize, raw = string.unpack("<I4I4I4I4", headers, i * 40 + 9)
        for _, other in ipairs(sections) do
            if start < other.start + other.size and other.start < start + size then return end
        end
        local flags = string.unpack("<I4", headers, i * 40 + 37)
        sections[#sections + 1] = {start = start, size = size, mapped = math.min(size, rawSize),
            raw = raw, code = flags & 0x20000000 ~= 0}
    end
    return sections
end

local function locate(sections, rva, size)
    for _, section in ipairs(sections) do
        local delta = rva - section.start
        if delta >= 0 and delta + size <= section.mapped then return section, section.raw + delta end
    end
end

local function matchesAt(file, sections, node, address, resolved)
    if resolved[node] then return resolved[node] == address end
    if resolved[address] then return false end
    resolved[node], resolved[address] = address, node
    local owner = locate(sections, address, 1)
    if not owner or owner.code ~= (node.kind ~= "data") then return false end
    for _, run in ipairs(node.bytes) do
        local rva = address + (run[1] - node.rva)
        local section, offset = locate(sections, rva, #run[2])
        if section ~= owner or read(file, offset, #run[2]) ~= run[2] then return false end
    end
    for _, ref in ipairs(node.refs or {}) do
        local rva = address + (ref[1] - node.rva)
        local section, offset = locate(sections, rva, #ref[2] + 4)
        if section ~= owner then return false end
        local bytes = read(file, offset, #ref[2] + 4)
        if not bytes or bytes:sub(1, #ref[2]) ~= ref[2] then return false end
        local target = rva + #bytes + string.unpack("<i4", bytes, #ref[2] + 1)
        if not matchesAt(file, sections, ref[3], target, resolved) then return false end
    end
    return true
end

local function matches(file, roots)
    local sections = readSections(file)
    if not sections then return false end
    local known = true
    for _, root in ipairs(roots) do
        if not matchesAt(file, sections, root, root.rva, {}) then
            known = false
            break
        end
    end
    if known then return true end
    -- A partial miss can leave old, still-matching routines alongside the new
    -- ones. Require one complete match for every root during rediscovery.
    local candidates = {}
    for _, root in ipairs(roots) do candidates[#candidates + 1] = {root = root, hits = 0} end
    for _, section in ipairs(sections) do
        if section.code then
            local carry = ""
            for pos = 0, section.mapped - 1, 1024 * 1024 do
                coroutine.yield()
                local chunk = read(file, section.raw + pos, math.min(1024 * 1024, section.mapped - pos))
                if not chunk then return false end
                local bytes, overlap = carry .. chunk, 0
                for _, candidate in ipairs(candidates) do
                    local root = candidate.root
                    local anchor = root.bytes[1]
                    overlap = math.max(overlap, #anchor[2] - 1)
                    local from = math.max(1, #carry - #anchor[2] + 2)
                    while true do
                        local found = bytes:find(anchor[2], from, true)
                        if not found then break end
                        candidate.hits = candidate.hits + 1
                        if candidate.hits > 256 then return false end
                        local rva = section.start + pos - #carry + found - 1 - (anchor[1] - root.rva)
                        if matchesAt(file, sections, root, rva, {}) then
                            if candidate.winner then return false end
                            candidate.winner = rva
                        end
                        from = found + 1
                    end
                end
                carry = bytes:sub(#bytes - overlap + 1)
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        if not candidate.winner then return false end
    end
    return true
end

-- poll returns nil while scanning, true on a match, or false and a diagnostic.
-- Only file inspection runs on the worker. The caller registers UE4SS properties
-- on its own callback state after poll succeeds.
return function(directory, roots, description)
    local worker
    local function scan()
        local file <close> = assert(io.open(directory .. "../../../../AceCombat8.exe", "rb")
            or io.open(directory .. "../../../AceCombat8.exe", "rb") or io.open("AceCombat8.exe", "rb"),
            "Cannot locate the AC8 executable")
        assert(matches(file, roots), "Unrecognized AC8 " .. description .. " layout")
    end
    local function cancel()
        if worker then coroutine.close(worker); worker = nil end
    end
    local function poll()
        worker = worker or coroutine.create(scan)
        local ok, why = coroutine.resume(worker)
        if ok and coroutine.status(worker) == "suspended" then return nil end
        cancel()
        return ok, why
    end
    return poll, cancel
end
