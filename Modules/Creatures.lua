local _, PF = ...

-- NPC/creature *names* -- distinct from Quests/Gossip (dialogue) and Items/Spells (their own
-- tooltips). Shown under the config label "Names" with its own master checkbox plus three
-- independent sub-checkboxes (see Core.lua's PF:IsSubEnabled/SetSubEnabled and Config.lua's
-- rendering of def.subs), since a player might want e.g. tooltips translated but not nameplates.
local Creatures = {
    desc = "NPC/creature names: tooltips, quest tracker/log kill-counters, nameplates and unit frames",
    label = "Names",
    implemented = true,
    subs = {
        { key = "tooltip", label = "Tooltips" },
        { key = "tracker", label = "Tracker & log kill-counter" },
        { key = "nameplate", label = "Nameplates & frames" },
    },
}

-- Data note: PF.Text.Creatures may be an empty table for a while -- the vmangos-sourced name
-- list (data/vmangos_npc_race.csv, ~10k names) still needs de-duping/filtering and an actual
-- translation pass, same pipeline shape as Items/Spells. Everything below is safe to ship ahead
-- of that data existing: hash-mismatch (or a missing/empty table) just leaves names in English,
-- same principle as every other module here.

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

local events
function Creatures:OnEnable()
    if events then return end
    events = CreateFrame("Frame")
    for _, e in ipairs({
        "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_NAME_UPDATE",
        "NAME_PLATE_UNIT_ADDED", "GROUP_ROSTER_UPDATE",
    }) do
        pcall(events.RegisterEvent, events, e)
    end
    -- Let Blizzard populate the frame/nameplate first.
    events:SetScript("OnEvent", function() C_Timer.After(0, applyFrames) end)

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
