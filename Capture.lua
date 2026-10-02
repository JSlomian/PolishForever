local _, PF = ...

-- Collects English text we have no translation for (gossip so far, books/readable objects) into
-- PolishForeverCapture -- a SavedVariables file of its own, so it can be read, shared or deleted
-- without touching settings. tools/import_captured.py reads the file after /reload and feeds it
-- to the same text_merge -> translate_batch -> build_addon_data flow as everything else.
--
-- Entries are keyed by PF.Hash(english) (the same key the translation tables use), so files from
-- several players merge by simple union.

local MAX_PER_KIND = 5000
local MAX_LEN = 8000

local function store()
    local db = PolishForeverCapture
    if type(db) ~= "table" then
        db = {}
        PolishForeverCapture = db
    end
    db.version = 1
    db.entries = db.entries or {}
    db.counts = db.counts or {}
    local v, b = GetBuildInfo()
    db.build = tostring(v) .. "." .. tostring(b)
    return db
end

local function enabled()
    return not (PolishForeverDB and PolishForeverDB.noCapture)
end

-- kind: "gossip" | "book". meta (all optional): sub, npc, name, title, page, zone.
-- Safe to call from any hook: never throws, never records the same text twice.
function PF.Capture(kind, english, meta)
    if not enabled() then return end
    pcall(function()
        if type(english) ~= "string" or english == "" or #english > MAX_LEN then return end
        if english:sub(-2) == PF.NBSP then return end -- our own output
        local hash = PF.Hash(english)
        if hash == 0 then return end
        local db = store()
        local bucket = db.entries[kind]
        if not bucket then
            bucket = {}
            db.entries[kind] = bucket
        end
        local key = string.format("%d", hash)
        local e = bucket[key]
        if e then
            if e.n < 1000 then e.n = e.n + 1 end
            return
        end
        if (db.counts[kind] or 0) >= MAX_PER_KIND then return end
        db.counts[kind] = (db.counts[kind] or 0) + 1
        e = { en = english, n = 1, zone = GetZoneText() }
        if meta then
            for k, v in pairs(meta) do e[k] = v end
        end
        bucket[key] = e
    end)
end

-- NPC currently being talked to: numeric ID from its GUID ("Creature-0-..-..-..-<id>-..") and name.
function PF.CaptureNpc()
    local ok, npc, name = pcall(function()
        local guid = UnitGUID("npc")
        local id = guid and select(6, strsplit("-", guid))
        return tonumber(id), UnitName("npc")
    end)
    if ok then return npc, name end
end

-- Books, letters, notes, plaques: one ITEM_TEXT_READY per page.
local events = CreateFrame("Frame")
events:RegisterEvent("ITEM_TEXT_READY")
events:SetScript("OnEvent", function()
    if not (ItemTextGetText and enabled()) then return end
    local ok, text, title, page = pcall(function()
        return ItemTextGetText(), ItemTextGetItem and ItemTextGetItem(), ItemTextGetPage and ItemTextGetPage()
    end)
    if ok then PF.Capture("book", text, { title = title, page = page }) end
end)

function PF:CaptureStatus()
    local db = PolishForeverCapture
    local c = db and db.counts or {}
    self:Print(("capture %s: gossip %d, books %d -- /reload writes them to WTF\\...\\SavedVariables\\PolishForeverCapture.lua")
        :format(enabled() and "on" or "off", c.gossip or 0, c.book or 0))
end

function PF:SetCapture(on)
    PolishForeverDB.noCapture = not on or nil
    self:Print("capture " .. (on and "on" or "off"))
end
