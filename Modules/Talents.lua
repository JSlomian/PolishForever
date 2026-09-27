local _, PF = ...

local Talents = {
    desc = "Talent names and descriptions (reuses spell data -- talents are spells)",
    implemented = true,
}

-- Talents have no separate translation pipeline: WoW talents are spells under the hood, so we
-- reuse PF.Text.Spells here too. Same setter-hooking technique as Abilities.lua (see
-- PF.HookTooltipSetters/PF.HookTooltipPostCalls in Core.lua), plus SetTalent for the classic
-- talent-frame tooltip specifically. Gated on this module's own toggle so it can be switched
-- independently of Abilities even though they hook some of the same methods.
local SPELL_SETTERS = { "SetSpell", "SetSpellByID", "SetTalent" }

local hooked = false

function Talents:OnEnable()
    if hooked then return end
    hooked = true
    local handler = function(self)
        if PF:IsEnabled("Talents") then PF.TranslateTooltipLines(self, PF.Text.Spells) end
    end
    if GameTooltip then PF.HookTooltipSetters(GameTooltip, SPELL_SETTERS, handler) end
    PF.HookTooltipPostCalls({ "Spell" }, handler)
end

function Talents:OnDisable() end

PF:RegisterModule("Talents", Talents)
