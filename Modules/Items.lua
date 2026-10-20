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
    -- The "Sell Price:" line is appended by the money-line helpers after the item setter (and its
    -- post-call) already ran, so the pass above never sees it: re-run on the helpers themselves.
    for _, fn in ipairs({ "SetTooltipMoney", "GameTooltip_OnTooltipAddMoney", "GameTooltip_AddMoney" }) do
        if type(_G[fn]) == "function" then
            -- Deferred one frame (not run inside Blizzard's own tooltip layout) and re-entrancy
            -- guarded, so this can never recurse or taint the money-line code path.
            local busy = false
            hooksecurefunc(fn, function(tt)
                if busy or type(tt) ~= "table" or not tt.NumLines then return end
                busy = true
                C_Timer.After(0, function()
                    busy = false
                    PF.Track("money", fn)
                    if tt.IsShown and tt:IsShown() then pcall(handler, tt) end
                end)
            end)
        end
    end
    -- Pieces the setter hooks never see: the "Equipped" header of a comparison tooltip and lines
    -- added after the setter ("Sell Price", comparison stat changes). Re-run, deferred, whenever
    -- one of these tooltips is shown, and walk its frame for plain FontStrings as well as its lines.
    local labels = setmetatable({}, { __index = function(_, k)
        local t = PF.Text or {}
        return (t.UI and t.UI[k]) or (t.Items and t.Items[k])
    end })
    local function showPass(tt)
        if not PF:IsEnabled("Items") then return end
        pcall(handler, tt)
        pcall(PF.TranslateFontStrings, tt, labels)
    end
    local installed = {}
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                            "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
        local tt = _G[name]
        if tt and tt.HookScript then
            pcall(tt.HookScript, tt, "OnShow", function(self)
                C_Timer.After(0, function() if self:IsShown() then showPass(self) end end)
                C_Timer.After(0.1, function() if self:IsShown() then showPass(self) end end)
            end)
        end
    end
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
    -- Loot window and group-loot roll frames show item names as plain FontStrings.
    local function lootRefresh()
        if not PF:IsEnabled("Items") then return end
        for _, f in ipairs({ _G.LootFrame, _G.GroupLootFrame1, _G.GroupLootFrame2,
                             _G.GroupLootFrame3, _G.GroupLootFrame4 }) do
            if f and f:IsShown() then PF.TranslateFontStrings(f, PF.Text.Items) end
        end
    end
    local lootEvents = CreateFrame("Frame")
    for _, e in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CHANGED", "START_LOOT_ROLL", "LOOT_ROLLS_COMPLETE" }) do
        pcall(lootEvents.RegisterEvent, lootEvents, e)
    end
    lootEvents:SetScript("OnEvent", function()
        C_Timer.After(0, lootRefresh)
        C_Timer.After(0.2, lootRefresh)
    end)
    for _, fn in ipairs({ "LootFrame_Update", "LootFrame_UpdateButton", "GroupLootFrame_OpenNewFrame" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, lootRefresh) end
    end
    -- Loot / crafting lines in chat: translate the item link names and the surrounding sentence.
    if ChatFrame_AddMessageEventFilter then
        local function lootFilter(_, _, msg, ...)
            if not PF:IsEnabled("Items") or type(msg) ~= "string" then return false end
            local ok, out = pcall(function()
                local m = PF.TranslateLinks(msg)
                local tpl = PF.MatchTemplate(m)
                if not tpl then PF.Track("loot-miss", (m:gsub("|", "||"))) end
                return tpl or m
            end)
            if ok and out and out ~= msg then return false, out, ... end
            if not ok then PF.Track("lootfilter-err", tostring(out)) end
            return false
        end
        for _, ev in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_TRADESKILLS" }) do
            ChatFrame_AddMessageEventFilter(ev, lootFilter)
        end
    end
    local n = 0
    for _ in pairs(PF.Text.Items or {}) do n = n + 1 end
    PF:Print(("Items: %d translations loaded, hooked %s"):format(n, table.concat(installed, ", ")))
end

function Items:OnDisable() end

PF:RegisterModule("Items", Items)
