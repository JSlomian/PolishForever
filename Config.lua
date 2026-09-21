local ADDON, PF = ...

local panel, category

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
    for _, name in ipairs(PF.order) do
        local mod = PF.modules[name]
        local check = CreateFrame("CheckButton", "PolishForeverCheck" .. name, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == sub and -2 or 0, previous == sub and -14 or -6)
        local label = _G[check:GetName() .. "Text"]
        label:SetText(name .. (mod.implemented and "" or "  |cff888888(not implemented yet)|r"))
        check.tooltipText = mod.desc
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(name)
            GameTooltip:AddLine(mod.desc, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", GameTooltip_Hide)
        check:SetScript("OnClick", function(self)
            PF:SetEnabled(name, self:GetChecked())
        end)
        panel.checks[name] = check
        previous = check
    end

    panel:SetScript("OnShow", function()
        for name, check in pairs(panel.checks) do
            check:SetChecked(PF:IsEnabled(name))
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
