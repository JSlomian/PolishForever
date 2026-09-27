local ADDON, PF = ...

local panel, category

-- Abilities/Talents/Skills all just show translated PF.Text.Spells (Skills also PF.Text.Skills,
-- close enough) in tooltips -- one combined checkbox here instead of three, even though they
-- stay separate modules under the hood (so /pl <module> on|off still works individually).
local SPELL_GROUP = { "Abilities", "Talents", "Skills" }
local grouped = {}
for _, name in ipairs(SPELL_GROUP) do grouped[name] = true end

local function groupChecked()
    for _, name in ipairs(SPELL_GROUP) do
        if not PF:IsEnabled(name) then return false end
    end
    return true
end

local function groupImplemented()
    for _, name in ipairs(SPELL_GROUP) do
        if not PF.modules[name].implemented then return false end
    end
    return true
end

local function setGroup(on)
    for _, name in ipairs(SPELL_GROUP) do PF:SetEnabled(name, on) end
end

local function BuildPanel()
    panel = CreateFrame("Frame", "PolishForeverConfig", UIParent)
    panel.name = "PolishForever"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("PolishForever")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Choose which parts are shown in Polish. Changes apply the next time a window opens.")

    local previous = sub
    panel.checks = {}
    panel.groupCheck = nil
    local spellGroupPlaced = false
    for _, name in ipairs(PF.order) do
        if grouped[name] then
            if not spellGroupPlaced then
                spellGroupPlaced = true
                local check = CreateFrame("CheckButton", "PolishForeverCheckSpells", panel, "UICheckButtonTemplate")
                check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == sub and -2 or 0, previous == sub and -14 or -6)
                local label = _G[check:GetName() .. "Text"]
                label:SetText("Spells" .. (groupImplemented() and "" or "  |cff888888(not implemented yet)|r"))
                local desc = "Spell, talent, ability and skill/profession tooltips"
                check:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Spells")
                    GameTooltip:AddLine(desc, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                check:SetScript("OnLeave", GameTooltip_Hide)
                check:SetScript("OnClick", function(self)
                    setGroup(self:GetChecked())
                end)
                panel.groupCheck = check
                previous = check
            end
        else
            local mod = PF.modules[name]
            local label_ = mod.label or name
            local check = CreateFrame("CheckButton", "PolishForeverCheck" .. name, panel, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == sub and -2 or 0, previous == sub and -14 or -6)
            local label = _G[check:GetName() .. "Text"]
            label:SetText(label_ .. (mod.implemented and "" or "  |cff888888(not implemented yet)|r"))
            check.tooltipText = mod.desc
            check:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label_)
                GameTooltip:AddLine(mod.desc, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            check:SetScript("OnLeave", GameTooltip_Hide)
            check:SetScript("OnClick", function(self)
                PF:SetEnabled(name, self:GetChecked())
            end)
            panel.checks[name] = check
            previous = check

            -- Sub-checkboxes (see Core.lua's PF:IsSubEnabled/SetSubEnabled): indented under
            -- their module's own master checkbox, e.g. Names -> Tooltips/Tracker & log
            -- kill-counter/Nameplates & frames.
            if mod.subs then
                panel.subChecks = panel.subChecks or {}
                panel.subChecks[name] = {}
                for _, subDef in ipairs(mod.subs) do
                    local subCheck = CreateFrame("CheckButton", "PolishForeverCheck" .. name .. subDef.key,
                        panel, "UICheckButtonTemplate")
                    subCheck:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == check and 14 or 0, -4)
                    subCheck:SetSize(24, 24)
                    local subLabel = _G[subCheck:GetName() .. "Text"]
                    subLabel:SetText(subDef.label)
                    subCheck:SetScript("OnClick", function(self)
                        PF:SetSubEnabled(name, subDef.key, self:GetChecked())
                    end)
                    panel.subChecks[name][subDef.key] = subCheck
                    previous = subCheck
                end
            end
        end
    end

    panel:SetScript("OnShow", function()
        for name, check in pairs(panel.checks) do
            check:SetChecked(PF:IsEnabled(name))
        end
        if panel.groupCheck then panel.groupCheck:SetChecked(groupChecked()) end
        for name, subs in pairs(panel.subChecks or {}) do
            for key, subCheck in pairs(subs) do
                subCheck:SetChecked(PF:IsSubEnabled(name, key))
            end
        end
    end)
end

function PF:SetupConfig()
    BuildPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "PolishForever")
        if ok and cat then
            category = cat
            Settings.RegisterAddOnCategory(cat)
            return
        end
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        return
    end
    -- last resort: a plain movable window
    panel:SetSize(360, 260)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    if panel.SetBackdrop then
        Mixin(panel, BackdropTemplateMixin)
        panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    end
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    panel:Hide()
    panel.standalone = true
end

function PF:OpenConfig()
    if not panel then return end
    if panel.standalone then
        panel:SetShown(not panel:IsShown())
    elseif category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
