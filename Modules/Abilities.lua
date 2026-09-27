local _, PF = ...

local Abilities = {
    desc = "Spell and ability names, descriptions and tooltips",
    implemented = true,
}

-- Every GameTooltip method that sets spell content, across client eras (this client's
-- GameTooltip errors on HookScript("OnTooltipSetSpell", ...) -- see PF.HookTooltipSetters in
-- Core.lua for why this covers both an older client that predates that virtual script and a
-- newer one that replaced it with TooltipDataProcessor, hooked separately below).
-- PF.Text.Spells also carries full description bodies with unresolved $s1-style value tokens;
-- those simply won't hash-match a live tooltip's already-substituted text (see
-- PF.TranslateTooltipLines), so only names get translated -- no extra filtering needed.
local SPELL_SETTERS = {
    "SetSpell", "SetSpellByID", "SetAction", "SetPetAction", "SetShapeshift",
    "SetUnitBuff", "SetUnitDebuff", "SetUnitAura", "SetTrainerService",
}

local hooked = false

function Abilities:OnEnable()
    if hooked then return end
    hooked = true
    local handler = function(self)
        if PF:IsEnabled("Abilities") then PF.TranslateTooltipLines(self, PF.Text.Spells) end
    end
    local installed = {}
    if GameTooltip then
        PF.HookTooltipSetters(GameTooltip, SPELL_SETTERS, handler)
        installed[#installed + 1] = "GameTooltip"
    end
    if PF.HookTooltipPostCalls({ "Spell" }, handler) then
        installed[#installed + 1] = "TooltipDataProcessor"
    end
    local n = 0
    for _ in pairs(PF.Text.Spells or {}) do n = n + 1 end
    PF:Print(("Abilities: %d translations loaded, hooked %s"):format(n, table.concat(installed, ", ")))
end

function Abilities:OnDisable() end

PF:RegisterModule("Abilities", Abilities)
