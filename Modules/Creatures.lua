local _, PF = ...

-- NPC/creature *names* -- distinct from Quests/Gossip (dialogue) and Items/Spells (their own
-- tooltips). Shown under the config label "Names" with its own master checkbox plus three
-- independent sub-checkboxes (see Core.lua's PF:IsSubEnabled/SetSubEnabled and Config.lua's
-- rendering of def.subs), since a player might want e.g. tooltips translated but not nameplates.
local Creatures = {
    desc = "NPC/creature names: tooltips, quest tracker/log kill-counters, nameplates and unit frames",
    label = "Names",
    -- Names + <Title> lines translated (10.4k entries from the Haiku + Sonnet pipeline).
    implemented = true,
    subs = {
        { key = "tooltip", label = "Tooltips" },
        { key = "tracker", label = "Tracker & log kill-counter" },
        { key = "nameplate", label = "Nameplates & frames" },
        { key = "dialog", label = "NPC name in dialogs & chat" },
    },
}

-- Translated name for an NPC (nil if Names or its "dialog" sub-option is off, or no translation).
-- Shared with Modules/Speech.lua so a speaker's name in chat matches the one on its nameplate.
function PF.NpcName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not (PF:IsEnabled("Creatures") and PF:IsSubEnabled("Creatures", "dialog")) then return nil end
    local ok, pl = pcall(function()
        local t = PF.Text and PF.Text.Creatures
        return t and t[PF.Hash(name)]
    end)
    if ok and pl and pl ~= name then return pl end
end

-- The NPC's name in the gossip / quest windows' header.
local function applyDialogName()
    if not (PF:IsEnabled("Creatures") and PF:IsSubEnabled("Creatures", "dialog")) then return end
    for _, fs in ipairs({ _G.QuestFrameNpcNameText, _G.GossipFrameNpcNameText }) do
        if fs and fs.GetText then
            local pl = PF.NpcName(fs:GetText())
            if pl then pcall(PF.SetText, fs, pl, "title") end
        end
    end
    local g = _G.GossipFrame
    local tc = g and g.TitleContainer
    if tc and PF.Text and PF.Text.Creatures then pcall(PF.TranslateFontStrings, tc, PF.Text.Creatures) end
end

-- Data note: PF.Text.Creatures holds NPC names AND the "<Title>" line under them (kept with its
-- angle brackets, so the whole tooltip line hashes exactly). Source: vmangos creature_template
-- (tools/vmangos_db.py -> data/text/creatures_english.csv -> text_merge.py -> translate_batch.py
-- --group Creatures -> build_addon_data.py). It may be empty until that translation pass has run;
-- everything below is safe to ship ahead of that: hash-mismatch (or a missing/empty table) just
-- leaves names in English, same principle as every other module here.

-- Tooltip: same pattern as Items/Abilities in Core.lua -- hook the actual SetUnit setter (this
-- client errors on HookScript("OnTooltipSetUnit", ...), see PF.HookTooltipSetters) plus
-- TooltipDataProcessor for modern clients. The name is always tooltip line 1; other lines
-- (level, reaction, "Rare", ...) simply won't hash-match PF.Text.Creatures and stay English.
local function tooltipHandler(tt)
    if PF:IsEnabled("Creatures") and PF:IsSubEnabled("Creatures", "tooltip") then
        PF.TranslateTooltipLines(tt, PF.Text.Creatures)
    end
end

-- Nameplates & unit frames: target/focus/party name fontstrings plus every currently-visible
-- world nameplate. Re-applied on the handful of events that actually change a shown name/unit
-- (not polled every frame).
local FRAMES = {
    "TargetFrame", "FocusFrame",
    "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4",
}

local function applyFrames()
    if not (PF:IsEnabled("Creatures") and PF:IsSubEnabled("Creatures", "nameplate")) then return end
    for _, name in ipairs(FRAMES) do
        local f = _G[name]
        if f and f:IsShown() then PF.TranslateFontStrings(f, PF.Text.Creatures) end
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and plates then
            for _, plate in ipairs(plates) do
                local unitFrame = plate.UnitFrame
                if unitFrame then PF.TranslateFontStrings(unitFrame, PF.Text.Creatures) end
            end
        end
    end
end

-- Blizzard rewrites the name fontstring on every status change (threat, health colour, combat,
-- raid marker, ...) via these refresh functions, which reverts it to English. Re-translate right
-- after each rewrite instead of relying on the handful of events above.
local function translateNameFS(fs)
    if not (PF:IsEnabled("Creatures") and PF:IsSubEnabled("Creatures", "nameplate")) then return end
    if not (fs and fs.GetText and PF.Text and PF.Text.Creatures) then return end
    local text = fs:GetText()
    local pl = text and PF.Text.Creatures[PF.Hash(text)]
    if pl and pl ~= text then PF.SetText(fs, pl, "body") end
end

local function hookNameRefresh()
    -- Nameplates / compact unit frames
    if _G.CompactUnitFrame_UpdateName then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            if frame then translateNameFS(frame.name) end
        end)
    end
    -- Target / focus frames
    for _, fn in ipairs({ "TargetFrame_Update", "TargetFrame_CheckFaction", "UnitFrame_Update" }) do
        if _G[fn] then
            hooksecurefunc(fn, function()
                for _, fname in ipairs({ "TargetFrame", "FocusFrame" }) do
                    local f = _G[fname]
                    if f and f:IsShown() then translateNameFS(f.name or _G[fname .. "TextureFrameName"]) end
                end
            end)
        end
    end
end

local events
function Creatures:OnEnable()
    if events then return end
    hookNameRefresh()
    events = CreateFrame("Frame")
    for _, e in ipairs({
        "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_NAME_UPDATE",
        "NAME_PLATE_UNIT_ADDED", "GROUP_ROSTER_UPDATE",
    }) do
        pcall(events.RegisterEvent, events, e)
    end
    -- Let Blizzard populate the frame/nameplate first.
    events:SetScript("OnEvent", function() C_Timer.After(0, applyFrames) end)

    local dialogEvents = CreateFrame("Frame")
    for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
        pcall(dialogEvents.RegisterEvent, dialogEvents, e)
    end
    dialogEvents:SetScript("OnEvent", function()
        C_Timer.After(0, applyDialogName)
        C_Timer.After(0.15, applyDialogName)
    end)

    local installed = {}
    if GameTooltip then
        PF.HookTooltipSetters(GameTooltip, { "SetUnit" }, tooltipHandler)
        installed[#installed + 1] = "GameTooltip"
    end
    if PF.HookTooltipPostCalls({ "Unit" }, tooltipHandler) then
        installed[#installed + 1] = "TooltipDataProcessor"
    end
    local n = 0
    for _ in pairs(PF.Text.Creatures or {}) do n = n + 1 end
    PF:Print(("Names: %d translations loaded, hooked %s"):format(n, table.concat(installed, ", ")))
end

function Creatures:OnDisable() end

PF:RegisterModule("Creatures", Creatures)
