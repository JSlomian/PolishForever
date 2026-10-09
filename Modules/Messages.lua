local _, PF = ...

-- The yellow text in the middle of the screen: quest progress ("Wretched Zombie slain: 1/8"),
-- "Objective Complete!", "Quest Accepted", ... The game writes it with UIErrorsFrame:AddMessage
-- after filling in the values, so it is translated on the way in with the same template matching
-- the tooltips use (PF.MatchTemplate: "%s slain: %d/%d" + creature/item names looked up by name).
local Messages = {
    desc = "Yellow on-screen messages: quest objective progress, 'Objective Complete', ...",
    label = "Screen messages",
    implemented = true,
}

-- "Prairie Wolf Paw: 3/6" (item objectives; the template "%s: %d/%d" is too generic for
-- PF.MatchTemplate) -- translate the name part from the item/creature tables.
local function translateCounterLine(msg)
    local name, a, b = msg:match("^(.+): (%d+)/(%d+)$")
    if not name then return nil end
    local t = PF.Text or {}
    local h = PF.Hash(name)
    local pl = (t.Items and t.Items[h]) or (t.Creatures and t.Creatures[h])
    if pl then return pl .. ": " .. a .. "/" .. b end
end

local hooked = false

function Messages:OnEnable()
    if hooked then return end
    local frame = _G.UIErrorsFrame
    if not (frame and frame.AddMessage) then return end
    hooked = true
    local orig = frame.AddMessage
    frame.AddMessage = function(self, msg, ...)
        if PF:IsEnabled("Messages") and type(msg) == "string" then
            local ok, pl = pcall(PF.MatchTemplate, msg)
            if not (ok and pl) then ok, pl = pcall(translateCounterLine, msg) end
            if ok and pl then msg = pl end
        end
        return orig(self, msg, ...)
    end
    -- the stock font lacks some Polish letters
    local ok, font, size, flags = pcall(frame.GetFont, frame)
    if ok and font and PF.Fonts and PF.Fonts.body then pcall(frame.SetFont, frame, PF.Fonts.body, size or 14, flags) end
end

function Messages:OnDisable() end

PF:RegisterModule("Messages", Messages)
