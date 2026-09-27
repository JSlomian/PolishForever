local _, PF = ...

local Skills = {
    desc = "Skill and profession names and descriptions",
    implemented = true,
}

-- Two halves, since professions are spells but skill/recipe LISTS are plain FontStrings:
-- 1) Profession/skill tooltips (casting a profession, hovering a skill icon) are spells under
--    the hood, so they render via the same setter-hooking path as Abilities (see
--    PF.HookTooltipSetters/PF.HookTooltipPostCalls in Core.lua).
-- 2) The skills list (character pane) and the trade-skill/recipe list show names as plain
--    text rows, not tooltips. The two supported client versions (.toc: 16001 Cata Classic,
--    11509 Classic Era) use different frames for this (ProfessionsFrame vs. TradeSkillFrame),
--    and exact internal button naming can differ/drift between client patches -- rather than
--    hardcode fragile per-version widget names, PF.TranslateFontStrings walks whichever
--    container frame is actually present and hash-replaces any label that matches our data,
--    same safety-by-construction as tooltips (non-matching text is left alone).
local hooked = false

local function walkIfShown(frame)
    if frame and frame:IsShown() then PF.TranslateFontStrings(frame, PF.Text.Skills) end
end

function Skills:OnEnable()
    if hooked then return end
    hooked = true

    local handler = function(self)
        if PF:IsEnabled("Skills") then PF.TranslateTooltipLines(self, PF.Text.Skills) end
    end
    if GameTooltip then PF.HookTooltipSetters(GameTooltip, { "SetSpell", "SetSpellByID" }, handler) end
    PF.HookTooltipPostCalls({ "Spell" }, handler)

    local function refresh()
        if not PF:IsEnabled("Skills") then return end
        -- Character pane's skills list; frame name varies by client version.
        walkIfShown(_G.SkillFrame)
        walkIfShown(_G.PaperDollFrame)
        -- Trade-skill/recipe list: Classic Era vs. Cata Classic profession UIs.
        walkIfShown(_G.TradeSkillFrame)
        walkIfShown(_G.ProfessionsFrame)
    end

    local events = CreateFrame("Frame")
    for _, ev in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
                          "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
        pcall(events.RegisterEvent, events, ev)
    end
    events:SetScript("OnEvent", function() C_Timer.After(0.2, refresh) end)

    for _, fn in ipairs({ "TradeSkillFrame_Update", "PaperDollFrame_SetSkillsTab" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, refresh) end
    end
end

function Skills:OnDisable() end

PF:RegisterModule("Skills", Skills)
