local _, PF = ...

local Items = {
    desc = "Item names, tooltips and descriptions",
    implemented = true,
}

-- Item tooltips render through a small, fixed set of GameTooltip-family frames regardless of
-- where they're shown (bags, merchant, loot, quest rewards, chat item links) -- hooking these
-- covers all of them, no need to touch individual UI panels.
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

local hooked = false

function Items:OnEnable()
    if hooked then return end
    hooked = true
    for _, name in ipairs(TOOLTIPS) do
        local tt = _G[name]
        if tt and tt.HookScript then
            tt:HookScript("OnTooltipSetItem", function(self)
                if PF:IsEnabled("Items") then PF.TranslateTooltipLines(self, PF.Text.Items) end
            end)
        end
    end
end

function Items:OnDisable() end

PF:RegisterModule("Items", Items)
