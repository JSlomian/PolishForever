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

-- "Willix Importer says: ..." -- the verb comes from a global format string, not from the text.
local SAY_VERBS = {
    CHAT_MONSTER_SAY_GET = "%s mówi: ", CHAT_MONSTER_PARTY_GET = "%s mówi: ",
    CHAT_MONSTER_YELL_GET = "%s krzyczy: ", CHAT_MONSTER_WHISPER_GET = "%s szepcze: ",
    CHAT_SAY_GET = "%s mówi: ", CHAT_YELL_GET = "%s krzyczy: ",
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
    local clean = PF.CleanGossip(plain)
    local pl = find(clean)
    if not pl then
        -- untranslated line (e.g. escort chatter that is not in the database): record it for the
        -- next translation pass; only chat lines, where the speaker is known, so "%s" is right
        if name and PF.Capture then PF.Capture("speech", clean, { name = name }) end
        return
    end
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

-- Speech bubbles over NPCs' heads are separate frames the game fills from the original message,
-- so the chat filter above never touches them. Right after a say/yell event, find the bubbles
-- and translate their text the same way (the speaker's name is not known here, so lines that
-- contain it are only matched when the stored key has no "%s").
local function translateBubbleFS(fs)
    local ok, text = pcall(fs.GetText, fs)
    if not ok or type(text) ~= "string" then PF.Track("bubble-text", tostring(ok), type(text)) return end
    local ok2, pl = pcall(translate, text, nil)
    if not (ok2 and pl) then PF.Track("bubble-miss", (text:gsub("|", "||"):sub(1, 120))) end
    if ok2 and pl and pl ~= text then PF.SetText(fs, pl, "body") end
end

local function walkBubble(frame, depth)
    if depth > 4 or not frame then return end
    if frame.GetObjectType and frame:GetObjectType() == "FontString" then
        translateBubbleFS(frame)
        return
    end
    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then translateBubbleFS(r) end
        end
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do walkBubble(c, depth + 1) end
    end
end

local function translateBubbles()
    if not PF:IsEnabled("Speech") then return end
    if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return end
    local ok, bubbles = pcall(C_ChatBubbles.GetAllChatBubbles, true)
    if not (ok and bubbles) then PF.Track("bubble-api", tostring(ok), tostring(bubbles)) return end
    if #bubbles == 0 then PF.Track("bubble-none") end
    for _, b in ipairs(bubbles) do pcall(walkBubble, b, 0) end
end

local added = false
function Speech:OnEnable()
    if added or not ChatFrame_AddMessageEventFilter then return end
    added = true
    for name, pl in pairs(SAY_VERBS) do
        if type(_G[name]) == "string" then _G[name] = pl end
    end
    for _, event in ipairs(EVENTS) do
        ChatFrame_AddMessageEventFilter(event, filter)
    end
    local bubbleEvents = CreateFrame("Frame")
    for _, e in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_SAY" }) do
        pcall(bubbleEvents.RegisterEvent, bubbleEvents, e)
    end
    bubbleEvents:SetScript("OnEvent", function()
        -- the bubble is created just after the chat event; its text may be set a moment later
        for _, t in ipairs({ 0.05, 0.2, 0.5, 1, 2 }) do C_Timer.After(t, translateBubbles) end
    end)
    local n = 0
    for _ in pairs((PF.Text and PF.Text.Speech) or {}) do n = n + 1 end
    PF:Print(("NPC speech: %d lines loaded"):format(n))
end

-- The filter checks PF:IsEnabled itself, so turning the module off just makes it a pass-through.
function Speech:OnDisable() end

PF:RegisterModule("Speech", Speech)
