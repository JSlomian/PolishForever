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

local function Apply()
    if not PF:IsEnabled("Quests") then return end
    local id = CurrentQuestID()
    local q = id and PF.Quests and PF.Quests[id]
    if not q then return end

    if shown(QuestFrameProgressPanel) then
        PF.ApplyText(QuestProgressTitleText, PF.Expand(q[TITLE]), "title")
        PF.ApplyText(QuestProgressText, PF.Expand(q[PROGRESS]), "body")
    else
        PF.ApplyText(QuestInfoTitleHeader, PF.Expand(q[TITLE]), "title")
        PF.ApplyText(QuestInfoObjectivesText, PF.Expand(q[OBJECTIVES]), "body")
        PF.ApplyText(QuestInfoDescriptionText, PF.Expand(q[DESCRIPTION]), "body")
        if shown(QuestFrameRewardPanel) then
            PF.ApplyText(QuestInfoRewardText, PF.Expand(q[COMPLETION]), "body")
        end
    end
    refreshScroll()
end

local function reportCurrentQuest()
    local id = CurrentQuestID()
    local q = id and PF.Quests and PF.Quests[id]
    PF.ReportBug("quest", id, q and PF.Expand(q[TITLE]) or nil)
end

-- Small PL/EN preview + Report buttons on whichever quest frame is actually shown. QuestInfoFrame
-- is shared by both the quest-log detail view and the NPC quest-accept dialogue (see
-- CurrentQuestID above), so one set of controls there covers both; QuestFrameProgressPanel (the
-- turn-in panel) is a separate frame and gets its own. Guarded/pcall-wrapped per frame so a wrong
-- assumption about one doesn't stop the other from being created.
local controlsInstalled = false
local function installControls()
    if controlsInstalled then return end
    controlsInstalled = true
    if QuestInfoFrame then
        pcall(PF.CreatePreviewControls, QuestInfoFrame, "BOTTOMRIGHT", -8, 8, reportCurrentQuest)
    end
    if QuestFrameProgressPanel then
        pcall(PF.CreatePreviewControls, QuestFrameProgressPanel, "BOTTOMRIGHT", -8, 8, reportCurrentQuest)
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
-- blocks/lines anchored too high and overlapping (this is what the screenshot in the report
-- showed). We fix it by measuring the wrapped-text height before/after each SetText and folding
-- the delta into the block's height so the tracker's own layout math stacks everything correctly.
local function setIfChanged(fs, text, kind, block)
    if fs and text and text ~= "" and fs:GetText() ~= text then
        local before = fs.GetStringHeight and fs:GetStringHeight() or 0
        PF.ApplyText(fs, text, kind)
        local after = fs.GetStringHeight and fs:GetStringHeight() or 0
        local delta = after - before
        if delta ~= 0 and block and type(block.height) == "number" then
            block.height = block.height + delta
        end
        return delta
    end
    return 0
end

local applyingTracker = false

local function ApplyTracker()
    if applyingTracker or not PF:IsEnabled("Quests") then return end
    local tracker = QuestObjectiveTracker
    local contents = tracker and tracker.ContentsFrame
    if not (contents and contents.GetChildren) then return end
    applyingTracker = true
    local grew = false
    for _, block in ipairs({ contents:GetChildren() }) do
        local id = block.poiQuestID
        local q = id and PF.Quests and PF.Quests[id]
        if q and block:IsShown() then
            local header = block.HeaderText
            local current = header and header:GetText()
            if current then
                local prefix = current:match("^(%[[^%]]*%]%s*)") or ""
                if setIfChanged(header, prefix .. PF.Expand(q[TITLE]), "body", block) ~= 0 then grew = true end
            end
            for _, line in ipairs({ block:GetChildren() }) do
                if line.objectiveKey == "QuestComplete" and line.Text then
                    if setIfChanged(line.Text, PF.Expand(q[OBJECTIVES]), "body", block) ~= 0 then grew = true end
                end
            end
            if block.SetHeight and type(block.height) == "number" then
                block:SetHeight(block.height)
            end
        end
    end
    applyingTracker = false
    -- Re-run the tracker's own stacking pass now that block heights reflect the Polish text;
    -- setIfChanged above is idempotent (checks GetText() first) so this doesn't loop or re-fetch
    -- English text -- it just repositions blocks/lines using the corrected heights.
    if grew then
        if type(tracker.EndLayout) == "function" then
            applyingTracker = true
            tracker:EndLayout()
            applyingTracker = false
        elseif type(contents.Layout) == "function" then
            contents:Layout()
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
