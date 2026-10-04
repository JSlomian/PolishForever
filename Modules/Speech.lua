local _, PF = ...

-- What NPCs say, yell and emote in the chat frame ("Skarr growls and looks around aggressively.",
-- boss shouts, escort-quest chatter). Chat lines are rewritten by message filters, which only
-- change the text on its way to the chat window -- nothing is blocked and every other argument
-- (sender, channel, flags) is passed through untouched.
--
-- Keying: the same as gossip (PF.CleanGossip: line breaks and player name/race/class removed), with
-- the speaker's own name turned back into "%s" first, which is how the database stores emotes
-- ("%s growls ...") and how the Polish text is stored too. Looked up in PF.Text.Speech, then in
-- PF.Gossip (an NPC line can also be a gossip line). No entry = the line stays English.
local Speech = {
    desc = "What NPCs say, yell and emote in chat, and boss shouts",
    label = "NPC speech",
    implemented = true,
}

local EVENTS = {
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_PARTY",
    "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_WHISPER",
}

local function escape(s)
    return (s:gsub("(%W)", "%%%1"))
end

local function find(clean)
    local text = PF.Text and PF.Text.Speech
    local pl = text and text[PF.Hash(clean)]
    if not pl and PF.Gossip then pl = PF.Gossip[PF.Hash(clean)] end
    return pl
end

local function translate(msg, sender)
    if type(msg) ~= "string" or msg == "" or msg:sub(-2) == PF.NBSP then return end
    local plain = msg
    local name = type(sender) == "string" and sender ~= "" and sender or nil
    if name then plain = plain:gsub(escape(name), "%%s") end
    local pl = find(PF.CleanGossip(plain))
    if not pl then return end
    pl = PF.Expand(pl)
    -- the speaker's name: the translated one when Names (dialog option) is on, as on its nameplate
    local shown = name and PF.NpcName and PF.NpcName(name) or name
    if name then pl = pl:gsub("%%s", function() return shown end) end
    return pl
end

-- Never throws and never blocks: any problem (a protected "secret" string, missing data) returns
-- false with the arguments unchanged. The speaker (arg2) is swapped for its translated name only
-- when Names -> "NPC name in dialogs & chat" is on; every other argument passes through as is.
local function filter(_, _, msg, ...)
    if not PF:IsEnabled("Speech") then return false end
    local sender = ...
    local ok, pl = pcall(translate, msg, sender)
    local okName, shownName = pcall(function() return PF.NpcName and PF.NpcName(sender) end)
    if not okName then shownName = nil end
    if ok and pl then
        if shownName then return false, pl, shownName, select(2, ...) end
        return false, pl, ...
    end
    return false
end

local added = false
function Speech:OnEnable()
    if added or not ChatFrame_AddMessageEventFilter then return end
    added = true
    for _, event in ipairs(EVENTS) do
        ChatFrame_AddMessageEventFilter(event, filter)
    end
    local n = 0
    for _ in pairs((PF.Text and PF.Text.Speech) or {}) do n = n + 1 end
    PF:Print(("NPC speech: %d lines loaded"):format(n))
end

-- The filter checks PF:IsEnabled itself, so turning the module off just makes it a pass-through.
function Speech:OnDisable() end

PF:RegisterModule("Speech", Speech)
