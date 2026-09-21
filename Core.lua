local ADDON, PF = ...
_G.PolishForever = PF

local NBSP = "\194\160" -- marks text we already replaced (WoWpoPolsku does the same)
PF.NBSP = NBSP

local FONT_DIR = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"
PF.Fonts = {
    body = FONT_DIR .. "frizquadratatt_pl.ttf",
    title = FONT_DIR .. "morpheus_pl.ttf",
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
function PF.Hash(text)
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

-- Set text on a FontString using a Polish-capable font at the original size. The stock enUS fonts
-- lack some Polish glyphs, which is why the addon ships its own.
function PF.SetText(fs, text, kind)
    if not fs or not text or text == "" then return false end
    if not fs.pfFont then
        local font, size, flags = fs:GetFont()
        fs.pfFont = { font, size, flags }
    end
    local orig = fs.pfFont
    if not fs:SetFont(PF.Fonts[kind or "body"], orig[2] or 12, orig[3]) then
        fs:SetFont(orig[1], orig[2] or 12, orig[3]) -- shipped font missing: keep the stock one
    end
    fs:SetText(text)
    return true
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

SLASH_POLISHFOREVER1 = "/pl"
SLASH_POLISHFOREVER2 = "/polishforever"
SlashCmdList.POLISHFOREVER = function(input)
    local a, b = strmatch(strtrim(input or ""):lower(), "^(%S*)%s*(%S*)$")
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
