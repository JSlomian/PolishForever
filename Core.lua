local ADDON, PF = ...
_G.PolishForever = PF

local NBSP = "\194\160" -- marks text we already replaced (WoWpoPolsku does the same)
PF.NBSP = NBSP

-- EB Garamond (Google Fonts, SIL OFL 1.1, see Fonts/EBGaramond-OFL.txt), Regular for body and a
-- Bold instance for title -- both verified full Polish glyph coverage. Tried a separate display
-- face (Cinzel, then Metamorphous) for "title" earlier, but in practice most of this addon's
-- "title" spots (quest log rows, tooltip headers) are stock WoW's own bold body font, not an
-- ornate different typeface like Morpheus -- so a bold weight of the same body face actually
-- matches the original look better than a stylistically distinct one.
local FONT_DIR = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"
PF.Fonts = {
    body = FONT_DIR .. "EBGaramond-Body.ttf",
    title = FONT_DIR .. "EBGaramond-Title.ttf",
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

-- Sub-toggles: a module can offer finer-grained surfaces under its own master checkbox (e.g.
-- Creatures: "Names" master + Tooltips/Tracker & log/Nameplates & frames sub-checkboxes).
-- def.subs = { key = "label", ... } declares them; PF:IsSubEnabled defaults a sub to true (same
-- opt-out-not-opt-in default as top-level modules) until the player unchecks it. A sub only
-- matters if the module's own master checkbox is also on -- callers should check both.
function PF:IsSubEnabled(name, key)
    local db = PolishForeverDB
    if not db then return true end
    local subs = db.subs and db.subs[name]
    if not subs or subs[key] == nil then return true end
    return subs[key] and true or false
end

function PF:SetSubEnabled(name, key, on)
    PolishForeverDB.subs = PolishForeverDB.subs or {}
    PolishForeverDB.subs[name] = PolishForeverDB.subs[name] or {}
    PolishForeverDB.subs[name][key] = on and true or false
end

local function InitDB()
    PolishForeverDB = PolishForeverDB or {}
    PolishForeverDB.modules = PolishForeverDB.modules or {}
    PolishForeverDB.subs = PolishForeverDB.subs or {}
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
-- "title" now just reuses the body face at a bold weight (see PF.Fonts above), so it doesn't need
-- a size boost on top -- left at 0, kept as a table in case a future title font needs one again.
local KIND_SIZE_BOOST = { title = 0 }
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

-- Recursively search a frame tree for a Button whose GetText() equals `label` -- lets us anchor
-- our own controls to one of Blizzard's own buttons (e.g. "Back") instead of a pixel offset
-- guessed off some other frame's corner, which breaks the moment that frame's layout shifts.
-- Depth-capped and pcall-wrapped throughout (secret-value protection, same as PF.Hash).
function PF.FindButtonByText(root, label, maxDepth)
    maxDepth = maxDepth or 8
    local function walk(obj, depth)
        if depth > maxDepth or not (obj and obj.GetChildren) then return nil end
        local ok, children = pcall(function() return { obj:GetChildren() } end)
        if not ok then return nil end
        for _, child in ipairs(children) do
            local okType, childType = pcall(child.GetObjectType, child)
            if okType and childType == "Button" then
                local okText, text = pcall(child.GetText, child)
                if okText and text == label then return child end
            end
            local found = walk(child, depth + 1)
            if found then return found end
        end
    end
    local ok, result = pcall(walk, root, 0)
    return ok and result or nil
end

-- EN/PL preview toggle ------------------------------------------------------------------------
-- Session-only (never saved to PolishForeverDB): lets a player flip a currently-open window
-- back to the original English to compare/verify a translation, without it being a persistent
-- setting. Each *scope* (one per distinct UI surface -- the quest detail view, the tracker, the
-- quest-map list, gossip, ...) has its own independent flag/widget-registry, so toggling one
-- window doesn't affect any other currently-open window; call PF.NewPreviewScope() once per
-- surface and use that scope's own ApplyText/CreateControls, not a single shared global.
local function showOriginal(fs)
    if fs.pfFont then fs:SetFont(fs.pfFont[1], fs.pfFont[2] or 12, fs.pfFont[3]) end
    fs:SetText(fs.pfOriginal or "")
end

function PF.NewPreviewScope()
    local scope = { previewEnglish = false }
    local activeTexts = setmetatable({}, { __mode = "k" })
    local watchers = setmetatable({}, { __mode = "k" })

    -- Use this (not PF.SetText) at every "we're about to show a translation" call site in this
    -- scope's UI surface.
    function scope.ApplyText(fs, polish, kind)
        if not fs then return end
        if fs.pfOriginal == nil then fs.pfOriginal = fs:GetText() or "" end
        if polish and polish ~= "" then
            fs.pfPolish = polish
            fs.pfKind = kind
        end
        activeTexts[fs] = true
        if scope.previewEnglish then
            showOriginal(fs)
        elseif fs.pfPolish and fs.pfPolish ~= "" then
            PF.SetText(fs, fs.pfPolish, fs.pfKind)
        end
    end

    function scope.SetPreviewEnglish(on)
        scope.previewEnglish = on and true or false
        for fs in pairs(activeTexts) do
            if fs and fs.GetObjectType and pcall(fs.GetObjectType, fs) then
                if scope.previewEnglish then
                    showOriginal(fs)
                elseif fs.pfPolish and fs.pfPolish ~= "" then
                    PF.SetText(fs, fs.pfPolish, fs.pfKind)
                end
            end
        end
        for watcher in pairs(watchers) do
            local ok = pcall(watcher)
            if not ok then watchers[watcher] = nil end
        end
    end

    -- A small "PL/EN" button plus an optional "Report" button, anchored to `parent` at `point`
    -- offset by (x, y). `reportFn`, if given, is the report button's OnClick handler.
    -- `reportAnchor`, if given, is {frame, point, relativePoint, x, y} -- anchors Report to that
    -- frame instead of relative to the toggle (see PF.FindButtonByText: used to line Report up
    -- with Blizzard's own "Back" button rather than a guessed pixel offset).
    -- `toggleAnchor`, if given, is the same {frame, point, relativePoint, x, y} shape but for the
    -- toggle button itself -- used when a fixed (point, x, y) offset isn't safe because the
    -- frame's own bottom button row (Continue/Cancel/Accept/...) moves depending on which quest
    -- is shown (confirmed via screenshot: a fixed BOTTOMRIGHT offset put PL half outside the
    -- parchment and Report hidden behind the Cancel button on the NPC turn-in dialogue).
    -- `reportPlacement`, if "above", stacks Report directly above the toggle instead of to its
    -- left (used on narrow parchment where left of the toggle runs into the scrollbar).
    function scope.CreateControls(parent, point, x, y, reportFn, reportAnchor, toggleAnchor, reportPlacement)
        if not parent then return end
        local toggle = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        toggle:SetSize(36, 20)
        if toggleAnchor then
            toggle:SetPoint(toggleAnchor[2], toggleAnchor[1], toggleAnchor[3], toggleAnchor[4], toggleAnchor[5])
        else
            toggle:SetPoint(point, parent, point, x, y)
        end
        local function updateLabel() toggle:SetText(scope.previewEnglish and "EN" or "PL") end
        updateLabel()
        watchers[updateLabel] = true
        toggle:SetScript("OnClick", function() scope.SetPreviewEnglish(not scope.previewEnglish) end)

        if reportFn then
            local report = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            report:SetSize(56, 20)
            if reportAnchor then
                report:SetPoint(reportAnchor[2], reportAnchor[1], reportAnchor[3], reportAnchor[4], reportAnchor[5])
            elseif reportPlacement == "above" then
                report:SetPoint("BOTTOMRIGHT", toggle, "TOPRIGHT", 0, 4)
            else
                -- Grows inward (left of the toggle), not outward past the parent's right edge --
                -- anchoring it to toggle's RIGHT side pushed it past the frame's own boundary and
                -- got it clipped by whatever sits beyond (scrollbar/border), since `toggle` itself
                -- already sits right at that edge.
                report:SetPoint("RIGHT", toggle, "LEFT", -4, 0)
            end
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

    return scope
end

-- Bug reports -----------------------------------------------------------------------------------
PF.REPO_URL = "https://github.com/JSlomian/PolishForever"

local function urlEncode(s)
    s = tostring(s or ""):gsub("\r\n", "\n"):gsub("\n", "\r\n")
    s = s:gsub("([^%w %-%_%.%~])", function(c) return ("%%%02X"):format(c:byte()) end)
    return (s:gsub(" ", "+"))
end

StaticPopupDialogs["POLISHFOREVER_REPORT"] = {
    text = "Copy this link (Ctrl+C) and open it in your browser to file the report. " ..
        "The ID and context are already filled in -- just describe what's wrong.",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 350,
    -- This client's StaticPopup is built from the newer Blizzard_StaticPopup_Game/GameDialog.xml
    -- template (confirmed via the Lua error's own stack trace), not the classic StaticPopup.lua
    -- one -- its edit box field is capitalized (self.EditBox), unlike the classic self.editBox
    -- this addon originally assumed. Try both, and don't error if neither exists.
    OnShow = function(self)
        local box = self.EditBox or self.editBox
        if not box then return end
        box:SetText(self.data or "")
        box:HighlightText()
        box:SetFocus()
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- kind: "quest" / "gossip" / "item" / "spell" / ... ; id: the quest/item/spell ID (may be nil);
-- extra: free-form context -- for quests, which panel/part was open (e.g. "objectives",
-- "rewards"); for gossip, the English source line (its ID is PF.Hash of that line). `current`
-- is accepted for callers that still pass it but is intentionally UNUSED here: full in-game
-- text in the URL risks pushing the link past a sane length and can silently fail to open. The
-- field layout lives in .github/ISSUE_TEMPLATE/translation.yml; the URL only prefills its short
-- kind/id/context fields and the title, and the reporter describes the problem themselves.
function PF.ReportBug(kind, id, current, extra)
    -- The template is an issue form (translation.yml): GitHub prefills any form field whose
    -- `id:` matches a query parameter, so kind/id/context arrive already filled in. `extra` is
    -- capped so a long gossip line can't push the link past a length browsers/GitHub accept.
    if type(id) == "number" then id = ("%.0f"):format(id) end
    extra = extra and tostring(extra):sub(1, 200)
    local title = ("[translation] %s%s"):format(kind, id and (" " .. id) or "")
    local url = PF.REPO_URL .. "/issues/new?template=translation.yml&title=" .. urlEncode(title)
        .. "&kind=" .. urlEncode(kind)
        .. (id and "&id=" .. urlEncode(id) or "")
        .. (extra and extra ~= "" and "&context=" .. urlEncode(extra) or "")
    StaticPopup_Show("POLISHFOREVER_REPORT", nil, nil, url)
end

-- Keybind: report whatever tooltip is currently under the mouse (spell/item/generic UI label),
-- for things noticed outside a quest window (which has its own Report button) or the config
-- panel's general one (which has no specific target at all). WoW auto-adds a bindable action for
-- any global function that has a matching BINDING_NAME_<funcname> global string set -- no
-- Bindings.xml needed. Shows up under Key Bindings -> AddOns -> PolishForever; unbound by default.
BINDING_HEADER_POLISHFOREVER = "PolishForever"
BINDING_NAME_PolishForeverReportHover = "Report the spell/item/tooltip currently under the mouse"

function PolishForeverReportHover()
    local ok, err = pcall(function()
        if not (GameTooltip and GameTooltip:IsShown()) then
            PF:Print("Hover over a spell, item, or other tooltip first, then use this keybind.")
            return
        end
        -- GetItem/GetSpell are the tooltip's own accessors for what it's currently displaying --
        -- more reliable than re-deriving it from the owner widget, and gives a real ID (not just
        -- the displayed name) when one exists.
        local kind, id, name
        local itemName, itemLink = GameTooltip:GetItem()
        if itemLink then
            kind, name = "item", itemName
            id = tonumber(itemLink:match("item:(%d+)"))
        else
            local spellName, spellID = GameTooltip:GetSpell()
            if spellName then kind, id, name = "spell", spellID, spellName end
        end
        if not kind then
            -- Generic tooltip (a UI label, not a spell/item) -- no reliable ID, so at least
            -- capture its first line as context for the report.
            local fs = _G[(GameTooltip:GetName() or "GameTooltip") .. "TextLeft1"]
            kind, name = "ui", fs and fs:GetText()
        end
        PF.ReportBug(kind, id, nil, name)
    end)
    if not ok then PF:Print("Report hover failed: " .. tostring(err)) end
end

-- Default the report-hover keybind to F7, once ever -- only if F7 isn't already bound to
-- something else (never clobber an existing binding) and only on first login (a `boundF7` flag,
-- not "is F7 still free", so a player who deliberately unbinds/rebinds it later doesn't get it
-- silently forced back on their next login).
local function SetDefaultBinding()
    if PolishForeverDB.boundF7 then return end
    PolishForeverDB.boundF7 = true
    local current = GetBindingAction and GetBindingAction("F7")
    if not current or current == "" then
        SetBinding("F7", "PolishForeverReportHover")
        SaveBindings(GetCurrentBindingSet())
    end
end

-- Lifecycle ----------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    InitDB()
    SetDefaultBinding()
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
