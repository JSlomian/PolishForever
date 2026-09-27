local _, PF = ...

local Talents = {
    desc = "Talent names and descriptions (reuses spell data -- talents are spells)",
    implemented = true,
}

-- Talents have no separate translation pipeline: WoW talents are spells under the hood, and
-- their tooltips render through the same GameTooltip:OnTooltipSetSpell path as Abilities, so we
-- reuse PF.Text.Spells here too. Same hook as Abilities.lua, gated on this module's own toggle
-- so the two can be switched independently even though they share one underlying event.
local hooked = false

function Talents:OnEnable()
    if hooked then return end
    hooked = true
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetSpell", function(self)
            if PF:IsEnabled("Talents") then PF.TranslateTooltipLines(self, PF.Text.Spells) end
        end)
    end
end

function Talents:OnDisable() end

PF:RegisterModule("Talents", Talents)
