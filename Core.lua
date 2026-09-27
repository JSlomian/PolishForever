local ADDON, PF = ...
_G.PolishForever = PF

local NBSP = "\194\160" -- marks text we already replaced (WoWpoPolsku does the same)
PF.NBSP = NBSP

-- Cinzel and EB Garamond (Google Fonts, SIL OFL 1.1, see Fonts/*-OFL.txt) -- both verified full
-- Polish glyph coverage. Cinzel is a titling/inscription face (near-unicase: its lowercase
-- glyphs are shaped like small caps), great for headers but hard to read as running prose --
-- kept for "title" only. EB Garamond is a real book-text serif with proper lowercase forms, used
-- for "body" so paragraph-length quest/tooltip text is actually legible.
local FONT_DIR = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"
PF.Fonts = {
    body = FONT_DIR .. "EBGaramond-Body.ttf",
    title = FONT_DIR .. "Cinzel-Bold.ttf",
}

PF.modules = {}
PF.order = {}

local defaults = { modules = {} }

function PF:Print(...)
    print("|cff5fb3ffPolishForever|r:", ...)
end

-- Modules ------------------------------------------------------------------------------------

-- def = { desc = "...", implemented = bool, OnEnable = fn, OnDisable = fn }
function PF:RegisterModule(name, def)
    def.name = name
    self.modules[name] = def
    self.order[#self.order + 1] = name
    defaults.modules[name] = true
end

function PF:IsEnabled(name)
    local db = PolishForeverDB
    return db and db.modules[name] and true or false
end

function PF:SetEnabled(name, on)
    local mod = self.modules[name]
    if not mod then return false end
    on = on and true or false
    if PolishForeverDB.modules[name] == on then return true end
    PolishForeverDB.modules[name] = on
    if self.loggedIn then
        local fn = on and mod.OnEnable or mod.OnDisable
        if fn then fn(mod) end
    end
    return true
end

local function InitDB()
    PolishForeverDB = PolishForeverDB or {}
    PolishForeverDB.modules = PolishForeverDB.modules or {}
    for name, value in pairs(defaults.modules) do
        if PolishForeverDB.modules[name] == nil then
            PolishForeverDB.modules[name] = value
        end
    end
end

-- Text helpers -------------------------------------------------------------------------------

-- WoWpoPolsku's gossip key scheme: 32-bit hash of the English text. Kept byte-for-byte so its
-- Gossip_PL.lua keys match.
-- Wrapped in pcall: some tooltip text is a "secret value" (a protected/opaque string WoW's
-- newer anti-exploit system returns instead of a plain string for certain content) -- any string
-- op on it, even `#text`, throws "attempt to get length of ... a secret string value". Since
-- we can't hash it anyway, just treat it as unmatchable (hash 0, same as an empty string) rather
-- than letting the error propagate and abort whatever loop called us.
function PF.Hash(text)
    local ok, result = pcall(function()
        if not text or #text == 0 then return 0 end
        local counter = 1
        local len = #text
        for i = 1, len, 3 do
            counter = math.fmod(counter * 8161, 4294967279)
            counter = counter + string.byte(text, i) * 16776193
            counter = counter + (string.byte(text, i + 1) or (len - i + 256)) * 8372226
            counter = counter + (string.byte(text, i + 2) or (len - i + 256)) * 3932164
        end
        return math.fmod(counter, 4294967291)
    end)
    return ok and result or 0
end

local CASES = { "M", "D", "C", "B", "N", "K", "W" }

local function playerForms(forms, name)
    return forms and forms[name]
end

local function caseForm(entry, letter, female, fallback)
    return entry and entry[letter .. (female and 2 or 1)] or fallback
end

-- Expand player-dependent placeholders in stored Polish text.
function PF.Expand(msg)
    if not msg or msg == "" then return "" end
    local name = UnitName("player") or ""
    local race = UnitRace("player") or ""
    local class = UnitClass("player") or ""
    local female = UnitSex("player") == 3

    -- raw Blizzard codes (gossip text keeps them) -> tokens
    msg = msg:gsub("%$[bB]", "NEW_LINE")
    msg = msg:gsub("%$[nN]", "YOUR_NAME")
    msg = msg:gsub("%$[rR]", "YOUR_RACE")
    msg = msg:gsub("%$[cC]", "YOUR_CLASS")
    msg = msg:gsub("%$[gG]", "YOUR_GENDER")
    msg = msg:gsub("%$[pP]", "NPC_GENDER")
    msg = msg:gsub("%$[oO]", "OWN_NAME")

    msg = msg:gsub("NEW_LINE", "\n")
    msg = msg:gsub("YOUR_NAME", function() return name end)

    local raceEntry = playerForms(PF.RaceForms, race)
    local classEntry = playerForms(PF.ClassForms, class)
    for i, letter in ipairs(CASES) do
        msg = msg:gsub("YOUR_RACE" .. i, function() return caseForm(raceEntry, letter, female, race) end)
        msg = msg:gsub("YOUR_CLASS" .. i, function() return caseForm(classEntry, letter, female, class) end)
    end
    msg = msg:gsub("YOUR_RACE", function() return race end)
    msg = msg:gsub("YOUR_CLASS", function() return class end)

    msg = msg:gsub("YOUR_GENDER%(([^;()]*);([^()]*)%)", function(m, f) return female and f or m end)
    local npcFemale = UnitSex("npc") == 3
    msg = msg:gsub("NPC_GENDER%(([^;()]*);([^()]*)%)", function(m, f) return npcFemale and f or m end)
    msg = msg:gsub("OWN_NAME%(([^;()]*);([^()]*)%)", function(_, pl) return pl end)
    return msg
end

-- Translate a GameTooltip-family frame's lines in place by hashing each line's current text
-- against `table` (a PF.Text.<Group> table). Lines whose text isn't an exact match (most
-- commonly a spell/item description whose numbers Blizzard has already substituted at render
-- time, when our stored text still carries the raw $s1-style token) simply don't hash-match
-- and are left in English -- no separate filtering needed, the lookup is safe by construction.
function PF.TranslateTooltipLines(tooltip, table)
    if not (tooltip and table) then return end
    local name = tooltip:GetName()
    if not name then return end
    for i = 1, tooltip:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        local pl = text and table[PF.Hash(text)]
        if pl then PF.SetText(fs, pl, i == 1 and "title" or "body") end
    end
end

-- Hook a tooltip's actual SetXxx setter methods (SetHyperlink, SetSpellByID, ...) rather than
-- the virtual OnTooltipSetItem/OnTooltipSetSpell script -- confirmed by a runtime error
-- ("bad argument #2 to HookScript") that this client's GameTooltip doesn't accept those as
-- valid script types. Root cause unconfirmed (could be a client predating that API, or a newer
-- retail-based client that removed it in favor of TooltipDataProcessor -- see
-- PF.HookTooltipPostCalls below); hooksecurefunc on the setter methods themselves is the older
-- technique that's worked across every client era, so it's the safe universal fallback either
-- way. `handler` runs after the real method has populated the tooltip's lines.
function PF.HookTooltipSetters(tooltip, methodNames, handler)
    if not tooltip then return end
    for _, m in ipairs(methodNames) do
        if type(tooltip[m]) == "function" then
            hooksecurefunc(tooltip, m, handler)
        end
    end
end

-- Modern (post-Dragonflight-era retail) tooltips process content through TooltipDataProcessor
-- rather than the old OnTooltipSetItem/OnTooltipSetSpell scripts; if this client has it, hook it
-- too, alongside PF.HookTooltipSetters -- harmless to have both active since PF.SetText is a
-- no-op when the text already matches, and a hash-mismatch always leaves text untouched.
-- dataTypeNames are Enum.TooltipDataType keys, e.g. "Item", "Spell".
function PF.HookTooltipPostCalls(dataTypeNames, handler)
    local proc = _G.TooltipDataProcessor
    local enum = _G.Enum and _G.Enum.TooltipDataType
    if not (proc and proc.AddTooltipPostCall and enum) then return false end
    for _, name in ipairs(dataTypeNames) do
        if enum[name] then proc.AddTooltipPostCall(enum[name], handler) end
    end
    return true
end

-- Recursively walk a frame's regions/children translating any FontString whose current text
-- hash-matches `table` (a PF.Text.<Group> table). For UI panels (skill/recipe lists, ...) that
-- show plain labels rather than tooltips, where the exact button/sub-frame naming can differ
-- between client versions -- bounded depth keeps this cheap and safe to call on every list
-- refresh, same as PF.TranslateTooltipLines is safe to call on every tooltip.
local WALK_MAX_DEPTH = 6
function PF.TranslateFontStrings(root, table, depth)
    if not (root and table) then return end
    depth = depth or 0
    if depth > WALK_MAX_DEPTH then return end
    local ok, objType = pcall(root.GetObjectType, root)
    if not ok then return end
    if objType == "FontString" then
        local text = root:GetText()
        local pl = text and table[PF.Hash(text)]
        if pl then PF.SetText(root, pl, "body") end
        return
    end
    if root.GetRegions then
        for _, region in ipairs({ root:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                PF.TranslateFontStrings(region, table, depth + 1)
            end
        end
    end
    if root.GetChildren then
        for _, child in ipairs({ root:GetChildren() }) do
            if child:IsShown() then PF.TranslateFontStrings(child, table, depth + 1) end
        end
    end
end

-- Set text on a FontString using a Polish-capable font at the original size. The stock enUS fonts
-- lack some Polish glyphs, which is why the addon ships its own.
-- "title" text gets a couple points larger, on top of the Cinzel-Bold face already used for that
-- kind, so it actually reads as a heading rather than same-size-but-different-font body text.
local KIND_SIZE_BOOST = { title = 1 }
function PF.SetText(fs, text, kind)
    if not fs or not text or text == "" then return false end
    if not fs.pfFont then
        local font, size, flags = fs:GetFont()
        fs.pfFont = { font, size, flags }
    end
    local orig = fs.pfFont
    local size = (orig[2] or 12) + (KIND_SIZE_BOOST[kind] or 0)
    if not fs:SetFont(PF.Fonts[kind or "body"], size, orig[3]) then
        fs:SetFont(orig[1], orig[2] or 12, orig[3]) -- shipped font missing: keep the stock one
    end
    fs:SetText(text)
    return true
end

-- EN/PL preview toggle ------------------------------------------------------------------------
-- Session-only (never saved to PolishForeverDB): lets a player flip a currently-open window
-- back to the original English to compare/verify a translation, without it being a persistent
-- setting. PF.ApplyText wraps every PF.SetText call site in Quests/Gossip so both the original
-- and translated text are cached on the widget the first time it's touched, and toggling the
-- flag just re-applies whichever one is wanted -- no need to re-run Blizzard's own display logic.
PF.previewEnglish = false
local activeTexts = setmetatable({}, { __mode = "k" })
local previewWatchers = setmetatable({}, { __mode = "k" })

local function showOriginal(fs)
    if fs.pfFont then fs:SetFont(fs.pfFont[1], fs.pfFont[2] or 12, fs.pfFont[3]) end
    fs:SetText(fs.pfOriginal or "")
end

-- Use this (not PF.SetText) at every "we're about to show a translation" call site that should
-- respect the preview toggle.
function PF.ApplyText(fs, polish, kind)
    if not fs then return end
    if fs.pfOriginal == nil then fs.pfOriginal = fs:GetText() or "" end
    if polish and polish ~= "" then
        fs.pfPolish = polish
        fs.pfKind = kind
    end
    activeTexts[fs] = true
    if PF.previewEnglish then
        showOriginal(fs)
    elseif fs.pfPolish and fs.pfPolish ~= "" then
        PF.SetText(fs, fs.pfPolish, fs.pfKind)
    end
end

function PF.SetPreviewEnglish(on)
    PF.previewEnglish = on and true or false
    for fs in pairs(activeTexts) do
        if fs and fs.GetObjectType and pcall(fs.GetObjectType, fs) then
            if PF.previewEnglish then
                showOriginal(fs)
            elseif fs.pfPolish and fs.pfPolish ~= "" then
                PF.SetText(fs, fs.pfPolish, fs.pfKind)
            end
        end
    end
    for watcher in pairs(previewWatchers) do
        local ok = pcall(watcher)
        if not ok then previewWatchers[watcher] = nil end
    end
end

-- A small "PL/EN" button plus an optional "Report" button, anchored to `parent` at `point`
-- offset by (x, y). `reportFn`, if given, is the report button's OnClick handler. Returns the
-- toggle button (its label auto-updates whenever PF.SetPreviewEnglish is called from anywhere).
function PF.CreatePreviewControls(parent, point, x, y, reportFn)
    if not parent then return end
    local toggle = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    toggle:SetSize(36, 20)
    toggle:SetPoint(point, parent, point, x, y)
    local function updateLabel() toggle:SetText(PF.previewEnglish and "EN" or "PL") end
    updateLabel()
    previewWatchers[updateLabel] = true
    toggle:SetScript("OnClick", function() PF.SetPreviewEnglish(not PF.previewEnglish) end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("PolishForever")
        GameTooltip:AddLine("Click to preview " .. (PF.previewEnglish and "Polish" or "original English") ..
            " (not saved, just for this window).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", GameTooltip_Hide)

    if reportFn then
        local report = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        report:SetSize(56, 20)
        report:SetPoint("LEFT", toggle, "RIGHT", 4, 0)
        report:SetText("Report")
        report:SetScript("OnClick", reportFn)
        report:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Report a translation issue")
            GameTooltip:Show()
        end)
        report:SetScript("OnLeave", GameTooltip_Hide)
    end
    return toggle
end

-- Bug reports -----------------------------------------------------------------------------------
-- CHANGEME once the addon is actually published -- see the GitHub-publish plan; the "Report"
-- buttons are wired up now so they're ready the moment this is a real repo URL.
PF.REPO_URL = "https://github.com/CHANGEME/PolishForever"

local function urlEncode(s)
    s = tostring(s or ""):gsub("\r\n", "\n"):gsub("\n", "\r\n")
    s = s:gsub("([^%w %-%_%.%~])", function(c) return ("%%%02X"):format(c:byte()) end)
    return (s:gsub(" ", "+"))
end

StaticPopupDialogs["POLISHFOREVER_REPORT"] = {
    text = "Copy this link (Ctrl+C) and open it in your browser to file the report:",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self)
        self.editBox:SetText(self.data or "")
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- kind: "quest" / "gossip" / "item" / "spell" / ... ; id: quest ID or other identifier (may be
-- nil); current: the Polish text currently shown, if any; extra: free-form context (e.g. the
-- English source line for gossip, which has no stable ID).
function PF.ReportBug(kind, id, current, extra)
    local title = ("[translation] %s%s"):format(kind, id and (" " .. tostring(id)) or "")
    local body = table.concat({
        "**Content type**: " .. tostring(kind),
        "**Where**: " .. (id and tostring(id) or (extra or "(see below)")),
        "",
        "**Current Polish text**:",
        current or "",
        "",
        "**Suggested Polish text**:",
        "",
        "",
        "**Why**:",
        "",
    }, "\n")
    local url = PF.REPO_URL .. "/issues/new?labels=translation&title=" .. urlEncode(title) ..
        "&body=" .. urlEncode(body)
    StaticPopup_Show("POLISHFOREVER_REPORT", nil, nil, url)
end

-- Lifecycle ----------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    InitDB()
    PF.loggedIn = true
    for _, name in ipairs(PF.order) do
        local mod = PF.modules[name]
        if PF:IsEnabled(name) and mod.OnEnable then
            local ok, err = pcall(mod.OnEnable, mod)
            if not ok then PF:Print("module " .. name .. " failed to enable: " .. tostring(err)) end
        end
    end
    if PF.SetupConfig then PF:SetupConfig() end
end)

-- Slash commands -----------------------------------------------------------------------------

local function status()
    PF:Print("modules:")
    for _, name in ipairs(PF.order) do
        local mod = PF.modules[name]
        print(("  %s: %s%s"):format(name, PF:IsEnabled(name) and "|cff00ff00on|r" or "|cffff4040off|r",
            mod.implemented and "" or " (not implemented yet)"))
    end
end

-- /pl test <Group> <exact English text> -- diagnostic: shows the hash and whether it's a key
-- in PF.Text.<Group> (or PF.Gossip for "Gossip"), so a translation gap can be narrowed down to
-- "data/hash mismatch" vs. "hook never fired" without needing to reproduce it by hovering.
-- Case-sensitive and NOT lowercased (unlike the rest of this command), since the hash depends
-- on exact text.
local function testLookup(raw)
    local group, text = strmatch(raw or "", "^(%S+)%s+(.*)$")
    if not (group and text and text ~= "") then
        PF:Print("usage: /pl test <Group> <exact English text>, e.g. /pl test Items Hearthstone")
        return
    end
    local t = (group == "Gossip") and PF.Gossip or (PF.Text and PF.Text[group])
    local h = PF.Hash(text)
    if not t then
        PF:Print(("test: no such table PF.Text.%s (or PF.Gossip)"):format(group))
        return
    end
    local pl = t[h]
    PF:Print(("test %s %q -> hash %d, %s"):format(group, text, h, pl and ("found: " .. pl) or "NOT FOUND"))
end

SLASH_POLISHFOREVER1 = "/pl"
SLASH_POLISHFOREVER2 = "/polishforever"
SlashCmdList.POLISHFOREVER = function(rawInput)
    local firstWord = strmatch(strtrim(rawInput or ""), "^(%S*)")
    if firstWord and firstWord:lower() == "test" then
        testLookup((strtrim(rawInput or "")):gsub("^%S+%s*", ""))
        return
    end
    local a, b = strmatch(strtrim(rawInput or ""):lower(), "^(%S*)%s*(%S*)$")
    if a == "" or a == "config" then
        if PF.OpenConfig then PF:OpenConfig() end
    elseif a == "status" then
        status()
    elseif a == "dump" then
        PF:Dump()
    else
        for _, name in ipairs(PF.order) do
            if name:lower() == a then
                if b == "on" or b == "off" then
                    PF:SetEnabled(name, b == "on")
                    PF:Print(name .. " " .. b .. " (reopen the window to see the change)")
                else
                    PF:Print(name .. ": " .. (PF:IsEnabled(name) and "on" or "off") .. ". Use /pl " .. a .. " on|off")
                end
                return
            end
        end
        PF:Print("usage: /pl [config] | /pl status | /pl <module> on|off")
    end
end
