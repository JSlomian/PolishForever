local _, PF = ...

local Gossip = {
    desc = "NPC gossip greetings and options",
    implemented = true,
}

-- WoWpoPolsku keys gossip by PF.Hash(english text) with the player's name, race, class and line
-- breaks removed, so the same greeting hashes identically for every character.
local function escape(s)
    return (s:gsub("(%W)", "%%%1"))
end

local function stripWord(text, word)
    if not word or word == "" then return text end
    for _, variant in ipairs({ word, word:lower(), word:upper() }) do
        text = text:gsub("%f[%w]" .. escape(variant) .. "%f[%W]", "")
    end
    return text
end

local function Clean(text)
    text = text:gsub("[\r\n]", "")
    local name = UnitName("player")
    if name and name ~= "" then
        text = text:gsub(escape(name), "")
        text = text:gsub(escape(name:upper()), "")
    end
    text = stripWord(text, UnitRace("player"))
    text = stripWord(text, UnitClass("player"))
    text = text:gsub("%$[BbNnRrCc]%$?", "")
    return text
end
PF.CleanGossip = Clean -- shared with Modules/Speech.lua: NPC chat lines are keyed the same way

-- Wrapped in pcall (same reasoning as PF.Hash in Core.lua): some UI text is now a WoW "secret
-- value" (protected/opaque string) that throws on any string operation. Unlikely for plain NPC
-- gossip text, but cheap insurance against a translation-disabling error the moment Blizzard
-- extends that protection further.
local function Lookup(english, kind)
    local ok, result = pcall(function()
        if not english or english == "" or english:sub(-2) == PF.NBSP then return end
        local clean = Clean(english)
        local gossip = PF.Gossip
        local pl = gossip and gossip[PF.Hash(clean)]
        if not pl and gossip then
            -- quest titles in the option list may carry a " (low level)" suffix
            local trimmed = clean:gsub(" %(low level%)", "")
            if trimmed ~= clean then pl = gossip[PF.Hash(trimmed)] end
        end
        if not pl then
            -- Not everything in the gossip list is gossip text -- a completable quest's option
            -- can read a plain generic string like "Ready for turn-in" instead of its title,
            -- which PF.Gossip (vmangos-sourced NPC lines) has no entry for. Same fix as the
            -- quest tracker/map-list's completion line: fall back to the UI text table.
            local text2 = PF.Text
            pl = text2 and text2.UI and text2.UI[PF.Hash(clean)]
        end
        if not pl and PF.Capture then
            -- untranslated: remember it (greeting or option) with the NPC for the next data build
            local npc, name = PF.CaptureNpc()
            PF.Capture("gossip", clean, { sub = kind, npc = npc, name = name })
        end
        return pl
    end)
    return ok and result or nil
end

-- Own preview scope (see PF.NewPreviewScope in Core.lua) so toggling gossip's PL/EN button
-- doesn't affect any other open window (quest log, tracker, ...).
local previewScope = PF.NewPreviewScope()

-- Last thing translated, for the Report button's context (gossip has no stable ID to key a
-- bug report on, unlike quests -- the English source line is the best we can offer).
local lastEnglish, lastPolish

local function Translate(fs, english, kind)
    local pl = Lookup(english, "greeting")
    if pl then
        local text = PF.Expand(pl) .. PF.NBSP
        previewScope.ApplyText(fs, text, kind)
        lastEnglish, lastPolish = english, text
    end
end

-- Option buttons hold coloured text like "|cff0000ffTitle|r"; hash only the plain text.
-- Wrapped in pcall like Lookup above (secret-value protection).
local function ApplyOption(button)
    local text = button.GetText and button:GetText()
    if not text or text == "" then return end
    local ok, prefix, suffix, plain = pcall(function()
        local p = text:match("^(|c%x%x%x%x%x%x%x%x)") or ""
        local s = p ~= "" and "|r" or ""
        local t = text:gsub("^|c%x%x%x%x%x%x%x%x", "")
        t = t:gsub("|r$", "")
        return p, s, t
    end)
    if not ok then return end
    local pl = Lookup(plain, "option")
    if pl and button.GetFontString then
        local fs = button:GetFontString()
        if fs then
            local out = prefix .. PF.Expand(pl) .. PF.NBSP .. suffix
            previewScope.ApplyText(fs, out, "body")
            lastEnglish, lastPolish = plain, out
        end
    end
end

local function reportGossip()
    -- Same hash the Gossip data table is keyed by, so the ID maps straight back to the entry.
    local hash = lastEnglish and PF.Hash(lastEnglish)
    PF.ReportBug("gossip", hash and hash ~= 0 and hash or nil, lastPolish, lastEnglish)
end

local controlsInstalled = false
local function installControls()
    if controlsInstalled then return end
    controlsInstalled = true
    if GossipFrame then
        pcall(previewScope.CreateControls, GossipFrame, "BOTTOMRIGHT", -8, 8, reportGossip)
    end
end

-- The quest window's greeting ("Hello there, $c. ...", shown when an NPC offers several quests)
-- is a plain GreetingText label Blizzard fills in QuestFrameGreetingPanel_OnShow; same lookup as a
-- gossip greeting (PF.Gossip holds the quest_greeting + npc_trainer_greeting lines too).
local function ApplyQuestGreeting()
    if not PF:IsEnabled("Gossip") then return end
    local fs = _G.GreetingText
    local text = GetGreetingText and GetGreetingText()
    if fs and fs.SetText and text and text ~= "" then Translate(fs, text, "body") end
end

local function Apply()
    if not PF:IsEnabled("Gossip") then return end
    local panel = GossipFrame and GossipFrame.GreetingPanel
    local scrollBox = panel and panel.ScrollBox
    if not (scrollBox and scrollBox.EnumerateFrames) then return end
    local greeting = C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText()
    for _, f in scrollBox:EnumerateFrames() do
        if f.GreetingText then
            Translate(f.GreetingText, greeting, "body")
        elseif f.GetText then
            ApplyOption(f)
        end
    end
end

local events

function Gossip:OnEnable()
    if events then return end
    events = CreateFrame("Frame")
    events:RegisterEvent("GOSSIP_SHOW")
    events:RegisterEvent("QUEST_GREETING")
    events:SetScript("OnEvent", function(_, event)
        -- let Blizzard populate the frame first
        local fn = (event == "QUEST_GREETING") and ApplyQuestGreeting or Apply
        C_Timer.After(0, fn)
        C_Timer.After(0.15, fn)
    end)
    installControls()
end

function Gossip:OnDisable() end

PF:RegisterModule("Gossip", Gossip)
