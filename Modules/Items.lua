local _, PF = ...

local Items = {
    desc = "Item names, tooltips and descriptions",
    implemented = true,
}

-- Item tooltips render through a small, fixed set of GameTooltip-family frames regardless of
-- where they're shown (bags, merchant, loot, quest rewards, chat item links) -- hooking these
-- covers all of them, no need to touch individual UI panels.
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

-- Every GameTooltip method that sets item content, across client eras (this client's GameTooltip
-- errors on HookScript("OnTooltipSetItem", ...) -- see PF.HookTooltipSetters in Core.lua for why
-- this covers both an older client that predates that virtual script and a newer one that
-- replaced it with TooltipDataProcessor, which is hooked separately below).
-- Checked for existence per-tooltip/per-client before hooking, so a method missing on one
-- version (or one of the smaller tooltip frames) is simply skipped, not an error.
local ITEM_SETTERS = {
    "SetHyperlink", "SetBagItem", "SetInventoryItem", "SetLootItem", "SetLootRollItem",
    "SetMerchantItem", "SetBuybackItem", "SetQuestItem", "SetQuestLogItem", "SetAuctionItem",
    "SetAuctionSellItem", "SetTradePlayerItem", "SetTradeTargetItem", "SetCraftItem",
    "SetTradeSkillItem", "SetInboxItem", "SetSendMailItem", "SetItemByID",
}

local hooked = false

function Items:OnEnable()
    if hooked then return end
    hooked = true
    local handler = function(self)
        if PF:IsEnabled("Items") then PF.TranslateTooltipLines(self, PF.Text.Items) end
    end
    local installed = {}
    for _, name in ipairs(TOOLTIPS) do
        local tt = _G[name]
        if tt then
            PF.HookTooltipSetters(tt, ITEM_SETTERS, handler)
            installed[#installed + 1] = name
        end
    end
    -- Modern (TooltipDataProcessor-based) clients: one registration covers every tooltip frame
    -- for the "Item" data type at once, so this is additive/redundant with the per-frame setter
    -- hooks above, not a replacement for them.
    if PF.HookTooltipPostCalls({ "Item" }, handler) then
        installed[#installed + 1] = "TooltipDataProcessor"
    end
    local n = 0
    for _ in pairs(PF.Text.Items or {}) do n = n + 1 end
    PF:Print(("Items: %d translations loaded, hooked %s"):format(n, table.concat(installed, ", ")))
end

function Items:OnDisable() end

PF:RegisterModule("Items", Items)
