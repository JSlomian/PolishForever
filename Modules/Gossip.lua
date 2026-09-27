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

local function Lookup(english)
    if not english or english == "" or english:sub(-2) == PF.NBSP then return end
    local gossip = PF.Gossip
    if not gossip then return end
    local clean = Clean(english)
    local pl = gossip[PF.Hash(clean)]
    if not pl then
        -- quest titles in the option list may carry a " (low level)" suffix
        local trimmed = clean:gsub(" %(low level%)", "")
        if trimmed ~= clean then pl = gossip[PF.Hash(trimmed)] end
    end
    return pl
end

-- Last thing translated, for the Report button's context (gossip has no stable ID to key a
-- bug report on, unlike quests -- the English source line is the best we can offer).
local lastEnglish, lastPolish

local function Translate(fs, english, kind)
    local pl = Lookup(english)
    if pl then
        local text = PF.Expand(pl) .. PF.NBSP
        PF.ApplyText(fs, text, kind)
        lastEnglish, lastPolish = english, text
    end
end

-- Option buttons hold coloured text like "|cff0000ffTitle|r"; hash only the plain text.
local function ApplyOption(button)
    local text = button.GetText and button:GetText()
    if not text or text == "" then return end
    local prefix = text:match("^(|c%x%x%x%x%x%x%x%x)") or ""
    local suffix = prefix ~= "" and "|r" or ""
    local plain = text:gsub("^|c%x%x%x%x%x%x%x%x", "")
    plain = plain:gsub("|r$", "")
    local pl = Lookup(plain)
    if pl and button.GetFontString then
        local fs = button:GetFontString()
        if fs then
            local out = prefix .. PF.Expand(pl) .. PF.NBSP .. suffix
            PF.ApplyText(fs, out, "body")
            lastEnglish, lastPolish = plain, out
        end
    end
end

local function reportGossip()
    PF.ReportBug("gossip", nil, lastPolish, lastEnglish)
end

local controlsInstalled = false
local function installControls()
    if controlsInstalled then return end
    controlsInstalled = true
    if GossipFrame then
        pcall(PF.CreatePreviewControls, GossipFrame, "BOTTOMRIGHT", -8, 8, reportGossip)
    end
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
    events:SetScript("OnEvent", function()
        -- let Blizzard populate the frame first
        C_Timer.After(0, Apply)
        C_Timer.After(0.15, Apply)
    end)
    installControls()
end

function Gossip:OnDisable() end

PF:RegisterModule("Gossip", Gossip)
