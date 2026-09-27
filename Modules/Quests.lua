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
        -- Positive Y here extends *above* the scrollframe's own top edge, into the gap between
        -- it and "Back" -- confirmed safe (plain frames don't clip non-scroll-child siblings,
        -- only the designated ScrollChild content is clipped) and clears the title text that a
        -- small negative offset collided with.
        pcall(detailScope.CreateControls, QuestMapDetailsScrollFrame, "TOPRIGHT", -6, 16, reportCurrentQuest)
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
local function translateObjectiveLine(text)
    local ok, result = pcall(function()
        if not text then return nil end
        local counter, rest = text:match("^(%d+/%d+%s+)(.*)$")
        if not counter then return nil end
        local suffix = ""
        for _, s in ipairs(OBJ_SUFFIXES) do
            if rest:sub(-#s) == s then
                suffix = s
                rest = rest:sub(1, -#s - 1)
                break
            end
        end
        local text2 = PF.Text
        local pl = (text2 and text2.Items and text2.Items[PF.Hash(rest)])
            or (text2 and text2.Creatures and text2.Creatures[PF.Hash(rest)])
        if pl then return counter .. pl .. suffix end
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
                    setIfChanged(line.Text, PF.Expand(q[OBJECTIVES]), "body", block)
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
local function ApplyQuestMapList()
    if not PF:IsEnabled("Quests") then return end
    local sf = QuestMapFrame and QuestMapFrame.QuestsFrame and QuestMapFrame.QuestsFrame.ScrollFrame
    if not sf then return end
    local changed = false
    if sf.titleFramePool then
        for title in sf.titleFramePool:EnumerateActive() do
            local id = title.questID
            local q = id and PF.Quests and PF.Quests[id]
            if q and title.Text then
                local current = title.Text:GetText()
                local prefix = titlePrefix(current)
                listScope.ApplyText(title.Text, prefix .. PF.Expand(q[TITLE]), "title")
                changed = true
            end
        end
    end
    if sf.objectiveFramePool then
        for line in sf.objectiveFramePool:EnumerateActive() do
            if line.Text then
                local pl = translateObjectiveLine(line.Text:GetText())
                if pl then
                    listScope.ApplyText(line.Text, pl, "body")
                    changed = true
                end
            end
        end
    end
    -- Unlike the tracker, this list had NO relayout call at all -- Blizzard's own
    -- QuestLogQuests_Update() already ran QuestScrollFrame.Contents:Layout() using the
    -- (English) row heights *before* our post-hook ever translates anything, so a title/
    -- objective line that wraps onto more lines in Polish just overflowed into the row below
    -- with nothing to correct it. Re-running Layout() (deferred one frame for the same
    -- GetStringHeight() staleness reason as the tracker) forces it to re-measure and re-stack
    -- using the now-translated text.
    if changed and sf.Contents and type(sf.Contents.Layout) == "function" then
        C_Timer.After(0, function()
            if sf.Contents and type(sf.Contents.Layout) == "function" then sf.Contents:Layout() end
        end)
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
