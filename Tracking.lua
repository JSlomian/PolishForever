local _, PF = ...

-- Automatic problem tracking. Everything lands in PolishForeverDB.trace (a ring of the last MAX
-- entries), which WoW writes to WTF/.../SavedVariables/PolishForever.lua on /reload or logout --
-- so after a problem, /reload and the entries can be read from that file (or with /pl trace).
--   * ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN: which function PolishForever was blocked
--     from calling (the popup "has been blocked from an action" never says), plus a stack.
--   * Lua errors whose text mentions PolishForever.
--   * PF.Track(tag, ...): breadcrumbs from the tooltip hooks, so the entries just before a
--     problem show which hook was running.
-- A frozen client that gets killed never writes its SavedVariables; the blocked/error lines are
-- therefore also printed to chat the moment they happen, so they can be screenshotted.
local MAX = 300

local function ring()
    PolishForeverDB = PolishForeverDB or {}
    PolishForeverDB.trace = PolishForeverDB.trace or {}
    return PolishForeverDB.trace
end

local function push(kind, msg)
    local t = ring()
    t[#t + 1] = ("%s %.2f %s %s"):format(date("%H:%M:%S"), GetTime(), kind, msg)
    if #t > MAX then table.remove(t, 1) end
end

-- Cheap breadcrumb; safe to call from hooks.
function PF.Track(tag, ...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    pcall(push, "trk", tag .. (n > 0 and (" " .. table.concat(parts, " ")) or ""))
end

local function report(kind, msg, withStack)
    pcall(push, kind, msg .. (withStack and ("\n" .. (debugstack(3, 8, 0) or "")) or ""))
    if PF.Print then pcall(PF.Print, PF, "|cffff5555" .. kind .. "|r " .. msg) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, addon, func)
    if event == "PLAYER_LOGIN" then
        PF.Track("login", GetBuildInfo())
    elseif addon == "PolishForever" then
        report(event == "ADDON_ACTION_BLOCKED" and "BLOCKED" or "FORBIDDEN", tostring(func), true)
    end
end)

-- Chain the error handler (never replace it): record only errors that mention this addon.
local prev = geterrorhandler()
seterrorhandler(function(err)
    if type(err) == "string" and err:find("PolishForever", 1, true) then
        pcall(push, "err", err:sub(1, 400))
    end
    return prev and prev(err)
end)

function PF.PrintTrace(n)
    local t = ring()
    n = tonumber(n) or 15
    PF:Print(("trace: last %d of %d entries"):format(math.min(n, #t), #t))
    for i = math.max(1, #t - n + 1), #t do
        local line = t[i]:match("^[^\n]*")
        PF:Print(line)
    end
end

function PF.ClearTrace() PolishForeverDB.trace = {} PF:Print("trace cleared") end
