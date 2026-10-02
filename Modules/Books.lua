local _, PF = ...

-- Books, letters, notes and plaques (the ItemTextFrame window). Blizzard fills the page widget
-- (ItemTextPageText, a SimpleHTML) on every ITEM_TEXT_READY with ItemTextGetText() [+ a "From:"
-- line]; we run right after, look the page up by hash and put the Polish text in its place.
--
-- Key = PF.Hash of the page text with "\r" removed (and trimmed as a fallback): the client's text
-- uses \r\n where the vmangos page_text table uses \n, and tools/vmangos_db.py exports it with the
-- \r dropped, so both sides hash the same string. A page with no entry just stays English.
local Books = {
    desc = "Books, letters, notes and plaques (the reading window)",
    label = "Books",
    implemented = true,
}

local function lookup(text)
    local books = PF.Text and PF.Text.Books
    if not books then return end
    local plain = text:gsub("\r", "")
    local pl = books[PF.Hash(plain)]
    if not pl then
        local trimmed = plain:match("^%s*(.-)%s*$")
        if trimmed ~= plain then pl = books[PF.Hash(trimmed)] end
    end
    return pl
end

-- Our font on the page widget. SimpleHTML takes a font per tag; Blizzard's own call is
-- SetFontObject(tag, fontObject), the file-based SetFont(tag, file, size, flags) is its sibling.
-- Only "P" for the large-parchment material, whose headings use big display fonts we shouldn't flatten.
local function applyFont(page)
    local size = 13
    if QuestFont and QuestFont.GetFont then
        local _, s = QuestFont:GetFont()
        size = s or size
    end
    local large = ItemTextGetMaterial and ItemTextGetMaterial() == "ParchmentLarge"
    local tags = large and { "P" } or { "P", "H1", "H2", "H3" }
    for _, tag in ipairs(tags) do
        local font = (tag == "P") and PF.Fonts.body or PF.Fonts.title
        local ok = pcall(page.SetFont, page, tag, font, size, "")
        if not ok then pcall(page.SetFont, page, font, size, "") end -- older signature, no tag
    end
end

local function apply()
    if not PF:IsEnabled("Books") then return end
    local page = _G.ItemTextPageText
    if not (page and ItemTextGetText and page.SetText) then return end
    local ok = pcall(function()
        local english = ItemTextGetText()
        if type(english) ~= "string" or english == "" then return end
        local pl = lookup(english)
        if not pl then return end

        local text = PF.Expand(pl)
        local creator = ItemTextGetCreator and ItemTextGetCreator()
        if creator then
            local from = _G.ITEM_TEXT_FROM or "From:"
            local uiFrom = PF.Text and PF.Text.UI and PF.Text.UI[PF.Hash(from)]
            text = text .. "\n\n" .. (uiFrom or from) .. "\n" .. creator .. "\n"
        end
        applyFont(page)
        page:SetText(text)

        -- Blizzard sized the scroll area for the English text right after its own SetText: redo
        -- the same step for ours (same call sequence as ItemTextFrame_OnEvent).
        local scroll = _G.ItemTextScrollFrame
        if scroll and scroll.GetScrollChild then
            scroll:GetScrollChild():SetHeight(1)
            scroll:UpdateScrollChildRect()
            if floor(scroll:GetVerticalScrollRange()) > 0 then
                scroll:GetScrollChild():SetHeight(scroll:GetHeight() + scroll:GetVerticalScrollRange() + 30)
            end
            if scroll.ScrollBar and scroll.ScrollBar.ScrollToBegin then scroll.ScrollBar:ScrollToBegin() end
        end
    end)
    return ok
end

local events
function Books:OnEnable()
    if events then return end
    events = CreateFrame("Frame")
    events:RegisterEvent("ITEM_TEXT_READY")
    events:SetScript("OnEvent", function()
        -- Blizzard's handler (registered earlier) must set its text first; run just after, and
        -- once more shortly after in case a page-turn animation re-sets it.
        C_Timer.After(0, apply)
        C_Timer.After(0.1, apply)
    end)
    PF:Print(("Books: %d pages loaded"):format((function()
        local n = 0
        for _ in pairs((PF.Text and PF.Text.Books) or {}) do n = n + 1 end
        return n
    end)()))
end

function Books:OnDisable() end

PF:RegisterModule("Books", Books)
