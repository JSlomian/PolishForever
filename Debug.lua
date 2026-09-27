local _, PF = ...

-- /pl dump: record the structure of the quest tracker (and anything named like it) into
-- PolishForeverDB.dump so it can be read from the SavedVariables file after /reload.
local MAX_LINES, MAX_DEPTH = 500, 8

local function fields(obj)
    local parts = {}
    for k, v in pairs(obj) do
        local t = type(v)
        if (t == "number" or t == "boolean") or (t == "string" and #v < 60) then
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        elseif t == "table" and type(v.GetObjectType) == "function" then
            parts[#parts + 1] = tostring(k) .. "=<" .. tostring(v:GetObjectType()) .. ">"
        end
        if #parts >= 14 then break end
    end
    table.sort(parts)
    return table.concat(parts, " ")
end

local function walk(obj, depth, out, label)
    if #out >= MAX_LINES or depth > MAX_DEPTH then return end
    local ok, objType = pcall(obj.GetObjectType, obj)
    if not ok then return end
    local name = obj.GetName and obj:GetName() or nil
    local line = string.rep("  ", depth) .. (label or name or "<anon>") .. " [" .. tostring(objType) .. "]"
    if objType == "FontString" then
        line = line .. " text=" .. tostring(obj:GetText()):sub(1, 70)
    else
        line = line .. " " .. fields(obj)
    end
    out[#out + 1] = line
    if obj.GetRegions then
        for _, region in ipairs({ obj:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                walk(region, depth + 1, out)
            end
        end
    end
    if obj.GetChildren then
        for _, child in ipairs({ obj:GetChildren() }) do
            walk(child, depth + 1, out)
        end
    end
end

local function matchesRoot(name)
    return name:find("Tracker") or name:find("QuestWatch") or name:find("QuestInfo")
        or name:find("QuestFrame") or name:find("QuestMap") or name:find("QuestLog")
        or name:find("Gossip")
end

function PF:Dump()
    local out = {}
    local roots = {}
    for name, value in pairs(_G) do
        if type(name) == "string" and matchesRoot(name) and type(value) == "table"
            and type(value.GetObjectType) == "function" and not name:find("Template") then
            roots[#roots + 1] = name
        end
    end
    table.sort(roots)
    out[#out + 1] = "roots: " .. table.concat(roots, ", ")
    -- Summary line per match regardless of shown/hidden -- this is the part that answers "what
    -- is this global's real parent frame", even for ones we don't deep-walk below.
    for _, name in ipairs(roots) do
        local obj = _G[name]
        local ok, objType = pcall(obj.GetObjectType, obj)
        local okShown, shown = pcall(obj.IsShown, obj)
        local parent = obj.GetParent and select(2, pcall(obj.GetParent, obj))
        local pname = parent and parent.GetName and parent:GetName()
        out[#out + 1] = ("%s :: [%s] shown=%s parent=%s"):format(
            name, ok and objType or "?", okShown and tostring(shown) or "?", tostring(pname))
    end
    -- Deep walk only for ones actually shown right now, to keep the dump a manageable size.
    for _, name in ipairs(roots) do
        local obj = _G[name]
        local ok, shown = pcall(obj.IsShown, obj)
        if not ok or shown then
            local parent = obj.GetParent and obj:GetParent()
            local pname = parent and parent.GetName and parent:GetName()
            if not (pname and _G[pname] and matchesRoot(pname)) then
                walk(obj, 0, out, name)
            end
        end
    end
    PolishForeverDB.dump = out
    self:Print(("dumped %d lines; type /reload to write them to disk"):format(#out))
end
