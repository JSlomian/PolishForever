local _, PF = ...

local Quests = {
    desc = "Quest titles, descriptions, objectives, progress and completion text",
    implemented = true,
}

-- PF.Quests[id] = { title, objectives, description, progress, completion }
local TITLE, OBJECTIVES, DESCRIPTION, PROGRESS, COMPLETION = 1, 2, 3, 4, 5

local function shown(frame)
    return frame and frame:IsShown()
end

-- Tracker/quest-map title lines are often prefixed with a color code before the "[level] "
-- bracket (confirmed via /pl dump: |cffffd100[13] Bandarion Keep|r) -- the old plain
-- "^(%[...)" pattern only matched a bare bracket at the very start, so it silently failed
-- (empty prefix) whenever a color code came first, dropping both the color and the level
-- number from the translated line. Capture an optional leading color code too.
-- Wrapped in pcall like PF.Hash: some tooltip/UI text is a WoW "secret value" (protected/opaque
-- string) that throws on any string operation, even from an addon that never touches its
-- content maliciously. Titles are unlikely to be secret, but cheap to guard the same way.
local function titlePrefix(text)
    local ok, result = pcall(function()
        if not text then return "" end
        local color = text:match("^(|c%x%x%x%x%x%x%x%x)") or ""
        local bracket = text:sub(#color + 1):match("^(%[[^%]]*%]%s*)") or ""
        return color .. bracket
    end)
    return ok and result or ""
end

-- The quest currently on screen: the selected quest-log entry, or the NPC dialogue quest.
local function CurrentQuestID()
    if QuestInfoFrame and QuestInfoFrame.questLog then
        local id
        if C_QuestLog and C_QuestLog.GetSelectedQuest then
            id = C_QuestLog.GetSelectedQuest()
        elseif GetQuestLogSelection and GetQuestLogTitle then
            local sel = GetQuestLogSelection()
            if sel and sel > 0 then id = select(8, GetQuestLogTitle(sel)) end
        end
        if id and id > 0 then return id end
    end
    local id = GetQuestID and GetQuestID()
    if id and id > 0 then return id end
end

local function refreshScroll()
    for _, name in ipairs({ "QuestDetailScrollFrame", "QuestLogDetailScrollFrame", "QuestRewardScrollFrame", "QuestProgressScrollFrame" }) do
        local sf = _G[name]
        if sf and sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
    end
end

-- Separate preview scopes per distinct UI surface, so toggling one window's PL/EN button
-- doesn't affect any other currently-open window (tracker, quest-map list, the detail view are
-- all independent -- see PF.NewPreviewScope in Core.lua).
local detailScope = PF.NewPreviewScope()
local trackerScope = PF.NewPreviewScope()
local listScope = PF.NewPreviewScope()

-- Forward-declared: translateObjectiveLine/completionLineText are defined further down (next to
-- the tracker code they were written for) but Apply() needs them too, for the quest-detail
-- view's own per-objective counter lines (QuestInfoObjective1, 2, ... under
-- QuestInfoObjectivesFrame) -- previously only the *paragraph* (QuestInfoObjectivesText) was
-- translated here, so an item/creature name embedded in "3/4 Vicious Night Web Spider Venom"
-- stayed English even though the equivalent tracker line correctly translated it.
local translateObjectiveLine, completionLineText

local function Apply()
    if not PF:IsEnabled("Quests") then return end
    local id = CurrentQuestID()
    local q = id and PF.Quests and PF.Quests[id]
    if not q then return end

    if shown(QuestFrameProgressPanel) then
        detailScope.ApplyText(QuestProgressTitleText, PF.Expand(q[TITLE]), "title")
        detailScope.ApplyText(QuestProgressText, PF.Expand(q[PROGRESS]), "body")
    else
        detailScope.ApplyText(QuestInfoTitleHeader, PF.Expand(q[TITLE]), "title")
        detailScope.ApplyText(QuestInfoObjectivesText, PF.Expand(q[OBJECTIVES]), "body")
        detailScope.ApplyText(QuestInfoDescriptionText, PF.Expand(q[DESCRIPTION]), "body")
        -- QuestInfoObjective1/2/... (confirmed via /pl dump) are FontString *regions* of
        -- QuestInfoObjectivesFrame, not child frames -- GetChildren() returns none of them
        -- (that's why this silently did nothing before), GetRegions() is what actually holds
        -- them, same distinction Debug.lua's walk() already makes.
        if QuestInfoObjectivesFrame and QuestInfoObjectivesFrame.GetRegions then
            for _, region in ipairs({ QuestInfoObjectivesFrame:GetRegions() }) do
                local okType, regionType = pcall(region.GetObjectType, region)
                if okType and regionType == "FontString" then
                    local text = region.GetText and region:GetText()
                    if text then
                        local pl = translateObjectiveLine(text) or completionLineText(text)
                        if pl then detailScope.ApplyText(region, pl, "body") end
                    end
                end
            end
        end
        if shown(QuestFrameRewardPanel) then
            detailScope.ApplyText(QuestInfoRewardText, PF.Expand(q[COMPLETION]), "body")
        end
    end
    refreshScroll()
end

local function reportCurrentQuest()
    local id = CurrentQuestID()
    local q = id and PF.Quests and PF.Quests[id]
    PF.ReportBug("quest", id, q and PF.Expand(q[TITLE]) or nil)
end

-- Small PL/EN preview + Report buttons on whichever quest frame is actually shown.
-- Confirmed via /pl dump that in this client's map-embedded quest log, QuestInfoFrame itself
-- always reports shown=false (its widgets -- QuestInfoTitleHeader etc. -- are reparented under
-- an anonymous child of QuestMapDetailsScrollFrame instead, which IS reliably shown), so that's
-- the real anchor target for that view. QuestInfoFrame/QuestFrameProgressPanel are kept too in
-- case the NPC quest-accept dialogue (a separate, more classic-style code path per the same
-- dump) uses them directly -- harmless if inactive. Guarded/pcall-wrapped per frame so a wrong
-- assumption about one doesn't stop the others from being created.
local controlsInstalled = false
local function installControls()
    if controlsInstalled then return end
    controlsInstalled = true
    if QuestMapDetailsScrollFrame then
        -- PL/EN toggle: pinned to the parchment's own top-right corner (small negative
        -- offset -- inside the paper, below its edge, not floating above it in the dark
        -- window chrome the way a positive Y offset did).
        -- Report: anchored directly to Blizzard's own "Back" button (found at runtime, not a
        -- guessed pixel offset -- see PF.FindButtonByText) so it sits in the same row as Back
        -- regardless of how this panel's layout shifts between contexts.
        local back = PF.FindButtonByText(WorldMapFrame, "Back", 12)
        local reportAnchor = back and { back, "LEFT", "RIGHT", 8, 0 }
        pcall(detailScope.CreateControls, QuestMapDetailsScrollFrame, "TOPRIGHT", -8, -6,
            reportCurrentQuest, reportAnchor)
    end
    if QuestInfoFrame then
        pcall(detailScope.CreateControls, QuestInfoFrame, "BOTTOMRIGHT", -8, 8, reportCurrentQuest)
    end
    if QuestFrameProgressPanel then
        pcall(detailScope.CreateControls, QuestFrameProgressPanel, "BOTTOMRIGHT", -8, 8, reportCurrentQuest)
    end
end

-- Objective tracker (the "Quests" list on the right). Structure, from /pl dump on the beta client:
-- QuestObjectiveTracker.ContentsFrame -> blocks (block.poiQuestID, block.HeaderText, block.height) -> lines
-- (line.Text, line.objectiveKey). Objective lines like "0/6 Prairie Wolf Paw" are built by the game
-- from item/creature names, so only titles and the "ready to turn in" text are translated here.
--
-- Rescale note: Blizzard's tracker computes each block's height (and therefore where the NEXT
-- block gets anchored) from the English text *before* our hook ever runs -- EndLayout stacks
-- blocks using that already-frozen `block.height`. Polish text is often longer and wraps onto
-- more lines, so swapping the text afterward without correcting `block.height` leaves later
-- blocks/lines anchored too high and overlapping.
--
-- GetStringHeight() can return stale (pre-SetText) metrics when queried in the very same
-- execution frame as the SetFont+SetText call, especially right after a font swap -- measuring
-- the "after" height immediately sometimes computed a wrong (usually zero) delta, under-sizing
-- the block and letting translated text overflow into the next one (the exact bug reported).
-- Defer the "after" measurement and the resulting resize/relayout by one frame via
-- C_Timer.After(0, ...) so the metrics have settled first.
local applyingTracker = false
local function setIfChanged(fs, text, kind, block)
    if not (fs and text and text ~= "" and fs:GetText() ~= text) then return end
    local before = fs.GetStringHeight and fs:GetStringHeight() or 0
    trackerScope.ApplyText(fs, text, kind)
    if not (block and type(block.height) == "number") then return end
    C_Timer.After(0, function()
        if not (fs and fs.GetStringHeight) then return end
        local delta = fs:GetStringHeight() - before
        if delta == 0 then return end
        block.height = block.height + delta
        if block.SetHeight then block:SetHeight(block.height) end
        local tracker = QuestObjectiveTracker
        if tracker and type(tracker.EndLayout) == "function" then
            applyingTracker = true
            tracker:EndLayout()
            applyingTracker = false
        end
    end)
end

-- Objective progress lines ("0/8 Bleeding Horror slain", "0/1 Spells of Shadow") are built by
-- the client from an item or creature name plus an optional trailing verb -- confirmed via
-- /pl dump against QuestObjectiveTracker: each objectiveKey=N line is its own FontString holding
-- exactly this text, separate from the flavor-text objectives paragraph. Strip the "N/M " counter
-- and any trailing " <verb>", hash-match the remaining name against Items (works today) and
-- Creatures (once that group exists -- PF.Text.Creatures may simply be nil for now, harmless),
-- and rebuild the line. Same hash-mismatch-is-safe principle as tooltips: a name we don't have a
-- translation for just leaves the line as-is.
local OBJ_SUFFIXES = { " slain", " killed", " collected", " looted", " used", " completed" }
-- Wrapped in pcall (see titlePrefix above): guards against "secret value" protected strings.
function translateObjectiveLine(text)
    local ok, result = pcall(function()
        if not text then return nil end
        local counter, rest = text:match("^(%d+/%d+%s+)(.*)$")
        if not counter then return nil end
        local text2 = PF.Text
        -- A finished objective gets a trailing " (Complete)" bracket appended (confirmed via
        -- screenshot: "4/4 Vicious Night Web Spider Venom (Complete)") -- this sits *after* any
        -- OBJ_SUFFIXES verb and wasn't stripped at all, so the whole rest-of-string never
        -- hash-matched the plain item/creature name and silently stayed English. Peel it off (and
        -- translate the bracketed word too, best-effort) before the suffix/name matching below.
        local base, bracketWord = rest:match("^(.-)%s+%((.-)%)$")
        local bracket
        if base then
            rest = base
            local plWord = text2 and text2.UI and text2.UI[PF.Hash(bracketWord)]
            bracket = " (" .. (plWord or bracketWord) .. ")"
        end
        local suffix = ""
        for _, s in ipairs(OBJ_SUFFIXES) do
            if rest:sub(-#s) == s then
                suffix = s
                rest = rest:sub(1, -#s - 1)
                break
            end
        end
        -- Creature-name lookup is separately gated by the "Names" module's own "Tracker & log
        -- kill-counter" sub-checkbox (Items is not -- that's a different module/checkbox
        -- entirely, always consulted here regardless of the Names settings).
        local creaturesOn = PF:IsEnabled("Creatures") and PF:IsSubEnabled("Creatures", "tracker")
        local pl = (text2 and text2.Items and text2.Items[PF.Hash(rest)])
            or (creaturesOn and text2 and text2.Creatures and text2.Creatures[PF.Hash(rest)])
        if pl then return counter .. pl .. suffix .. (bracket or "") end
    end)
    return ok and result or nil
end

-- The tracker's "QuestComplete" line and the quest-map list's completion bullet show the short
-- generic GlobalStrings "Ready for turn-in" text -- an exact hash match against the UI text
-- table (translated once via PF.Text.UI) is all this needs. q[COMPLETION] is NOT a valid
-- fallback here: it's the NPC's full multi-paragraph turn-in dialogue (shown elsewhere, in the
-- reward panel/gossip greeting), and substituting it into this one-line status field showed the
-- entire speech in place of "Ready for turn-in" for quests whose questgiver you haven't even
-- gone back to yet. If the hash doesn't match, leave the line as-is (same hash-mismatch-is-safe
-- principle as translateObjectiveLine) rather than guess at a replacement.
-- Wrapped in pcall like translateObjectiveLine (secret-value protection).
function completionLineText(text)
    local ok, result = pcall(function()
        if not text then return nil end
        local text2 = PF.Text
        return text2 and text2.UI and text2.UI[PF.Hash(text)]
    end)
    return ok and result or nil
end

local function ApplyTracker()
    if applyingTracker or not PF:IsEnabled("Quests") then return end
    local tracker = QuestObjectiveTracker
    local contents = tracker and tracker.ContentsFrame
    if not (contents and contents.GetChildren) then return end
    applyingTracker = true
    for _, block in ipairs({ contents:GetChildren() }) do
        local id = block.poiQuestID
        local q = id and PF.Quests and PF.Quests[id]
        if q and block:IsShown() then
            local header = block.HeaderText
            local current = header and header:GetText()
            if current then
                local prefix = titlePrefix(current)
                setIfChanged(header, prefix .. PF.Expand(q[TITLE]), "title", block)
            end
            for _, line in ipairs({ block:GetChildren() }) do
                if line.objectiveKey == "QuestComplete" and line.Text then
                    -- Was PF.Expand(q[OBJECTIVES]) -- wrong field: that's the objectives
                    -- *paragraph*, not the "Ready for turn-in"/completion line this widget
                    -- actually shows, so it silently never matched and stayed English.
                    local pl = completionLineText(line.Text:GetText())
                    if pl then setIfChanged(line.Text, pl, "body", block) end
                elseif type(line.objectiveKey) == "number" and line.Text then
                    local pl = translateObjectiveLine(line.Text:GetText())
                    if pl then setIfChanged(line.Text, pl, "body", block) end
                end
            end
        end
    end
    applyingTracker = false
    -- Per-widget height/relayout correction happens inside setIfChanged itself, deferred one
    -- frame (see comment above it) -- nothing further to do here.
end

-- Modern "Map & Quest Log" list (the quest titles + inline objective bullets shown in the World
-- Map's quest panel, before opening any single quest). Confirmed via Blizzard's own source
-- (Gethe/wow-ui-source, Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua) that this is a
-- completely different, older-style system from Gossip's ScrollBox/EnumerateFrames: titles and
-- objective lines are separate CreateFramePool-managed widgets (QuestScrollFrame.titleFramePool /
-- .objectiveFramePool), each carrying its own .questID, rebuilt from scratch on every
-- QuestLogQuests_Update() call (a bare global function, not a method) -- so like the tracker,
-- this must be re-applied every time that fires, not just once.
-- Unlike the tracker (which stacks blocks off a manually-tracked block.height), this list's
-- Contents:Layout() apparently re-measures each row from its OWN frame height, not just the
-- FontString's -- calling Layout() alone after translating (previous attempt) did nothing,
-- because the row widget itself (title/line) never grew even though its text now wraps onto
-- more lines. So: measure the FontString's height before/after (same staleness-safe deferred
-- pattern as setIfChanged), grow the row widget by that delta if it exposes Set/GetHeight, then
-- re-run Contents:Layout() so later rows re-stack using the corrected height.
local function setListText(fs, text, kind, widget, id)
    if not (fs and text and text ~= "" and fs:GetText() ~= text) then return end
    local before = fs.GetStringHeight and fs:GetStringHeight() or 0
    listScope.ApplyText(fs, text, kind)
    if not (widget and widget.GetHeight and widget.SetHeight) then return end
    C_Timer.After(0, function()
        -- This is a CreateFramePool-managed row -- QuestLogQuests_Update can run again (a
        -- scroll, a category collapse/expand, another quest update) before this deferred
        -- callback fires, recycling `widget` for a *different* quest in the meantime. Resizing
        -- or forcing a re-layout on someone else's row is exactly what produced ghost/duplicate
        -- text bleeding between rows -- bail out unless it's still showing the quest we expect.
        if not (fs and fs.GetStringHeight and widget.GetHeight and widget.questID == id) then return end
        local delta = fs:GetStringHeight() - before
        if delta == 0 then return end
        widget:SetHeight(widget:GetHeight() + delta)
        local sf = QuestMapFrame and QuestMapFrame.QuestsFrame and QuestMapFrame.QuestsFrame.ScrollFrame
        if sf and sf.Contents and type(sf.Contents.Layout) == "function" then
            sf.Contents:Layout()
        end
    end)
end

local function ApplyQuestMapList()
    if not PF:IsEnabled("Quests") then return end
    local sf = QuestMapFrame and QuestMapFrame.QuestsFrame and QuestMapFrame.QuestsFrame.ScrollFrame
    if not sf then return end
    if sf.titleFramePool then
        for title in sf.titleFramePool:EnumerateActive() do
            local id = title.questID
            local q = id and PF.Quests and PF.Quests[id]
            if q and title.Text then
                local current = title.Text:GetText()
                local prefix = titlePrefix(current)
                setListText(title.Text, prefix .. PF.Expand(q[TITLE]), "title", title, id)
            end
        end
    end
    if sf.objectiveFramePool then
        for line in sf.objectiveFramePool:EnumerateActive() do
            if line.Text then
                local text = line.Text:GetText()
                local id = line.questID
                local q = id and PF.Quests and PF.Quests[id]
                -- translateObjectiveLine handles "N/M name" bullets; completionLineText covers
                -- the "Ready for turn-in"/completion bullet shown once a quest's objectives are
                -- all done (same generic-string gap as the tracker's QuestComplete branch above).
                -- Neither matches a plain narrative single-objective quest (e.g. "Take
                -- Apothecary Johaan's findings to Apothecary Renferrel...") -- this widget only
                -- ever shows one of these three things, so once the first two have ruled
                -- themselves out, q[OBJECTIVES] (the same short summary sentence used in the
                -- detail view) is the remaining possibility, not an open-ended guess.
                local pl = translateObjectiveLine(text) or completionLineText(text)
                    or (q and q[OBJECTIVES] ~= "" and PF.Expand(q[OBJECTIVES]))
                if pl then setListText(line.Text, pl, "body", line, id) end
            end
        end
    end
end

-- Quest-list row tooltip (hovering a quest in the Map & Quest Log's title list): built from
-- plain GameTooltip:AddLine calls (title, level requirement, then the same kind of
-- objective/flavor lines as the row itself), not a dedicated SetXxx method like Items/Spells
-- get -- so there's nothing clean to hook there. Instead: hooked on GameTooltip:Show() itself
-- (cheap to bail early -- almost every tooltip's owner has no .questID) and translated using the
-- row button's own .questID, same as ApplyQuestMapList.
local function translateQuestTooltip(tt)
    if not PF:IsEnabled("Quests") then return end
    local okOwner, owner = pcall(tt.GetOwner, tt)
    local id = okOwner and owner and owner.questID
    local q = id and PF.Quests and PF.Quests[id]
    if not q then return end
    local name = tt.GetName and tt:GetName()
    if not name then return end
    for i = 1, tt:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            local pl
            if i == 1 then
                pl = titlePrefix(text) .. PF.Expand(q[TITLE])
            else
                -- Deliberately NOT falling back to q[OBJECTIVES] here like the list's own
                -- bullet widget does: that widget only ever shows one of three things (a closed
                -- enumeration), but this tooltip has many unrelated lines (level requirement, a
                -- blank separator, an "Objectives:" header, rewards, ...) -- blindly substituting
                -- every non-matching line with the objectives sentence overwrote all of them
                -- with the same text instead of leaving them alone. Only apply a verified
                -- hash-match; anything else stays English.
                -- Unlike the list/tracker widgets (whose bullet is a separate decoration next
                -- to the FontString), this tooltip's per-objective rows have a literal "- "
                -- baked into the line text itself (confirmed via screenshot: "- 0/1 Captain
                -- Melrache slain") -- translateObjectiveLine's counter pattern only matches at
                -- the very start of the string, so that leading dash silently blocked every
                -- counter line from ever matching. Strip it, translate, reattach.
                local dash, rest = text:match("^(%- )(.*)$")
                local core = rest or text
                pl = translateObjectiveLine(core) or completionLineText(core)
                if pl and dash then pl = dash .. pl end
            end
            if pl and pl ~= text then PF.SetText(fs, pl, i == 1 and "title" or "body") end
        end
    end
end

local hooked = false

function Quests:OnEnable()
    if hooked then return end
    hooked = true
    -- Hooks stay installed; Apply() checks the toggle so disabling takes effect on the next window.
    for _, fn in ipairs({ "QuestInfo_Display", "QuestLog_UpdateQuestDetails", "QuestLogFrame_Update" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, Apply) end
    end
    -- tracker: hook the module's update methods where they exist, and refresh on quest events as a backup
    if QuestObjectiveTracker then
        for _, fn in ipairs({ "Update", "EndLayout" }) do
            if type(QuestObjectiveTracker[fn]) == "function" then
                hooksecurefunc(QuestObjectiveTracker, fn, ApplyTracker)
            end
        end
    end
    if type(_G["QuestLogQuests_Update"]) == "function" then
        hooksecurefunc("QuestLogQuests_Update", ApplyQuestMapList)
    end
    if GameTooltip then
        hooksecurefunc(GameTooltip, "Show", function() translateQuestTooltip(GameTooltip) end)
    end
    local events = CreateFrame("Frame")
    for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_POI_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        pcall(events.RegisterEvent, events, ev)
    end
    events:SetScript("OnEvent", function() C_Timer.After(0.2, ApplyTracker) end)
    C_Timer.After(1, ApplyTracker)
    if QuestFrameProgressPanel then
        QuestFrameProgressPanel:HookScript("OnShow", Apply)
    end
    if QuestFrameRewardPanel then
        QuestFrameRewardPanel:HookScript("OnShow", Apply)
    end
    installControls()
end

function Quests:OnDisable() end

PF:RegisterModule("Quests", Quests)
