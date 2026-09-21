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
        PF.SetText(QuestProgressTitleText, PF.Expand(q[TITLE]), "title")
        PF.SetText(QuestProgressText, PF.Expand(q[PROGRESS]), "body")
    else
        PF.SetText(QuestInfoTitleHeader, PF.Expand(q[TITLE]), "title")
        PF.SetText(QuestInfoObjectivesText, PF.Expand(q[OBJECTIVES]), "body")
        PF.SetText(QuestInfoDescriptionText, PF.Expand(q[DESCRIPTION]), "body")
        if shown(QuestFrameRewardPanel) then
            PF.SetText(QuestInfoRewardText, PF.Expand(q[COMPLETION]), "body")
        end
    end
    refreshScroll()
end

-- Objective tracker (the "Quests" list on the right). Structure, from /pl dump on the beta client:
-- QuestObjectiveTracker.ContentsFrame -> blocks (block.poiQuestID, block.HeaderText) -> lines
-- (line.Text, line.objectiveKey). Objective lines like "0/6 Prairie Wolf Paw" are built by the game
-- from item/creature names, so only titles and the "ready to turn in" text are translated here.
local function setIfChanged(fs, text, kind)
    if fs and text and text ~= "" and fs:GetText() ~= text then
        PF.SetText(fs, text, kind)
    end
end

local function ApplyTracker()
    if not PF:IsEnabled("Quests") then return end
    local tracker = QuestObjectiveTracker
    local contents = tracker and tracker.ContentsFrame
    if not (contents and contents.GetChildren) then return end
    for _, block in ipairs({ contents:GetChildren() }) do
        local id = block.poiQuestID
        local q = id and PF.Quests and PF.Quests[id]
        if q and block:IsShown() then
            local header = block.HeaderText
            local current = header and header:GetText()
            if current then
                local prefix = current:match("^(%[[^%]]*%]%s*)") or ""
                setIfChanged(header, prefix .. PF.Expand(q[TITLE]), "body")
            end
            for _, line in ipairs({ block:GetChildren() }) do
                if line.objectiveKey == "QuestComplete" and line.Text then
                    setIfChanged(line.Text, PF.Expand(q[OBJECTIVES]), "body")
                end
            end
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
end

function Quests:OnDisable() end

PF:RegisterModule("Quests", Quests)
