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

    -- Every top-level checkbox aligns its LEFT edge to `sub` (the subtitle), independent of
    -- whatever `previous` is -- previously it inherited x=0 relative to `previous`'s BOTTOMLEFT,
    -- which was correct when `previous` was another top-level check (same x already) but wrong
    -- when `previous` was the last SUB-checkbox of the module above it (indented +14): the next
    -- top-level module then inherited that same indent and visually looked like a sub-item of the
    -- one before it (confirmed: "Menus" right after "Names"/Creatures, which has sub-checkboxes,
    -- appeared indented like one of Names' own sub-options). Only the vertical (TOP) anchor
    -- chains to `previous`; horizontal is always pinned back to the same baseline.
    local previous = sub
    panel.checks = {}
    panel.groupCheck = nil
    local spellGroupPlaced = false
    for _, name in ipairs(PF.order) do
        if grouped[name] then
            if not spellGroupPlaced then
                spellGroupPlaced = true
                local check = CreateFrame("CheckButton", "PolishForeverCheckSpells", panel, "UICheckButtonTemplate")
                check:SetPoint("TOP", previous, "BOTTOM", 0, previous == sub and -14 or -6)
                check:SetPoint("LEFT", sub, "LEFT", -2, 0)
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
            check:SetPoint("TOP", previous, "BOTTOM", 0, previous == sub and -14 or -6)
            check:SetPoint("LEFT", sub, "LEFT", -2, 0)
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
                        if mod.OnSubChanged then pcall(mod.OnSubChanged, mod, subDef.key) end
                    end)
                    panel.subChecks[name][subDef.key] = subCheck
                    previous = subCheck
                end
            end
        end
    end

    -- Font selector: a dropdown over PF.FontChoices. The preview line is drawn in the chosen
    -- font right away; windows already open pick the new font up the next time they open.
    -- Two widget generations: the modern menu dropdown (WowStyle1DropdownTemplate + SetupMenu) when
    -- the client has it, otherwise the classic UIDropDownMenu.
    local fontTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontTitle:SetPoint("TOP", previous, "BOTTOM", 0, -20)
    fontTitle:SetPoint("LEFT", sub, "LEFT", 0, 0)
    fontTitle:SetText("Text font")

    local preview = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    local function showPreview()
        local choice = PF:GetFontChoice()
        preview:SetFont(choice.bodyPath, 14, "")
        preview:SetText("Zażółć gęślą jaźń. Witaj, wędrowcze! Zabij dziesięć wilków i wróć po nagrodę.")
    end

    local function choiceText(c) return c.label .. " - " .. c.note end
    local refreshFontDropdown = function() end
    local dropdown

    local okModern, modern = pcall(function()
        local dd = CreateFrame("DropdownButton", "PolishForeverFontDropdown", panel, "WowStyle1DropdownTemplate")
        dd:SetWidth(360)
        dd:SetupMenu(function(_, root)
            for _, c in ipairs(PF.FontChoices) do
                root:CreateRadio(choiceText(c),
                    function() return PF:GetFontChoice().key == c.key end,
                    function() PF:SetFontChoice(c.key); showPreview() end)
            end
        end)
        refreshFontDropdown = function() dd:GenerateMenu() end
        return dd
    end)
    if okModern and modern then
        dropdown = modern
        dropdown:SetPoint("TOPLEFT", fontTitle, "BOTTOMLEFT", 0, -6)
    else
        dropdown = CreateFrame("Frame", "PolishForeverFontDropdown", panel, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", fontTitle, "BOTTOMLEFT", -16, -4)
        UIDropDownMenu_SetWidth(dropdown, 340)
        UIDropDownMenu_Initialize(dropdown, function()
            for _, c in ipairs(PF.FontChoices) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = choiceText(c)
                info.checked = PF:GetFontChoice().key == c.key
                info.func = function()
                    PF:SetFontChoice(c.key)
                    UIDropDownMenu_SetText(dropdown, choiceText(c))
                    showPreview()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        refreshFontDropdown = function()
            UIDropDownMenu_SetText(dropdown, choiceText(PF:GetFontChoice()))
        end
    end
    panel.fontDropdown = dropdown

    preview:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", okModern and 4 or 20, -10)
    preview:SetWidth(520)
    preview:SetJustifyH("LEFT")
    previous = preview

    -- General feedback: the in-game Report button on quest windows is scoped to the quest on
    -- screen, but there's nowhere to report a bad spell/item/UI-label translation noticed outside
    -- that context (e.g. a wrong tooltip while browsing the spellbook). One general-purpose button
    -- here, reusing the same issue template/popup, with no ID/part prefilled -- the reporter
    -- describes what's wrong themselves.
    local reportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reportBtn:SetSize(160, 22)
    reportBtn:SetPoint("TOP", previous, "BOTTOM", 0, -16)
    reportBtn:SetPoint("LEFT", sub, "LEFT", -2, 0)
    reportBtn:SetText("Report an issue")
    reportBtn:SetScript("OnClick", function() PF.ReportBug("general") end)
    reportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Report an issue")
        GameTooltip:AddLine("Spell, item, UI label, or anything else not covered by a window's own Report button.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    reportBtn:SetScript("OnLeave", GameTooltip_Hide)

    panel:SetScript("OnShow", function()
        for name, check in pairs(panel.checks) do
            check:SetChecked(PF:IsEnabled(name))
        end
        if panel.groupCheck then panel.groupCheck:SetChecked(groupChecked()) end
        refreshFontDropdown()
        showPreview()
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
