local _, PF = ...

local Abilities = {
    desc = "Spell and ability names, descriptions and tooltips",
    implemented = true,
}

-- Spellbook, action bars and aura tooltips all render spells through GameTooltip's
-- OnTooltipSetSpell (SetSpellByID / SetSpellBookItem / SetUnitAura all funnel here) -- one hook
-- covers all of them. PF.Text.Spells also carries full description bodies with unresolved
-- $s1-style value tokens; those simply won't hash-match a live tooltip's already-substituted
-- text (see PF.TranslateTooltipLines), so only names get translated -- no extra filtering needed.
local hooked = false

function Abilities:OnEnable()
    if hooked then return end
    hooked = true
    local ok = GameTooltip and GameTooltip.HookScript
    if ok then
        GameTooltip:HookScript("OnTooltipSetSpell", function(self)
            if PF:IsEnabled("Abilities") then PF.TranslateTooltipLines(self, PF.Text.Spells) end
        end)
    end
    local n = 0
    for _ in pairs(PF.Text.Spells or {}) do n = n + 1 end
    PF:Print(("Abilities: %d translations loaded, hooked %s"):format(n, tostring(ok and true or false)))
end

function Abilities:OnDisable() end

PF:RegisterModule("Abilities", Abilities)
