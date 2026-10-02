local _, PF = ...

local Quests = {
    desc = "Quest titles, descriptions, objectives, progress and completion text",
    implemented = true,
    subs = {
        { key = "trackerBold", label = "Bold text in the quest tracker (side bar)" },
    },
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

-- Static section headers/labels ("Quest Objectives", "Rewards", "Experience:", "You will
-- receive:") are Blizzard GlobalStrings, not per-quest text -- PF.Text.UI already has them
-- (translated as part of the general UI-text pass), this addon just never applied that table to
-- these specific FontStrings (confirmed via screenshot: title/objectives/rewards paragraph all
-- translated, these header/label lines sitting right next to them weren't). Same
-- hash-mismatch-is-safe lookup as everywhere else -- an untranslated or renamed label just stays
-- English rather than guessing.
-- kind must match whatever font Blizzard's own XML gave this FontString (QuestTitleFont vs
-- QuestFont) -- these are fixed-width, single-line-by-default labels, so using the wrong (larger)
-- kind for a plain QuestFont label is exactly what doesn't fit; the header labels themselves
-- (QuestTitleFont) need "title", not "body".
local function translateStaticLabel(fs, kind)
    local ok = pcall(function()
        local text = fs and fs:GetText()
        local pl = text and PF.Text and PF.Text.UI and PF.Text.UI[PF.Hash(text)]
        if pl then detailScope.ApplyText(fs, pl, kind or "body") end
    end)
    return ok
end

-- Required/reward item buttons (QuestProgressItem1..6, QuestInfoRewardsFrame's reward buttons)
-- show the item's own name as a plain FontString on the button, separate from its (already
-- correctly translated, via Modules/Items.lua's GameTooltip hook) tooltip -- confirmed via
-- screenshot: tooltip said "Klejnot Eteru", the button under it still said "Nether Gem". Recurse
-- through whatever's currently shown looking for FontStrings that hash-match PF.Text.Items,
-- same bounded-depth walk PF.TranslateFontStrings uses elsewhere -- but going through
-- detailScope.ApplyText (not PF.SetText) so these buttons respect this window's own PL/EN preview
-- toggle like everything else in it, instead of always showing Polish regardless of that toggle.
local function translateItemButtonNames(root, depth)
    if not root then return end
    depth = depth or 0
    if depth > 6 then return end
    local okType, objType = pcall(root.GetObjectType, root)
    if okType and objType == "FontString" then
        local text = root.GetText and root:GetText()
        local pl = text and PF.Text and PF.Text.Items and PF.Text.Items[PF.Hash(text)]
        if pl then detailScope.ApplyText(root, pl, "body") end
        return
    end
    if root.GetRegions then
        for _, region in ipairs({ root:GetRegions() }) do
            local okR, rType = pcall(region.GetObjectType, region)
            if okR and rType == "FontString" then translateItemButtonNames(region, depth + 1) end
        end
    end
    if root.GetChildren then
        for _, child in ipairs({ root:GetChildren() }) do
            local okShown, isShown = pcall(child.IsShown, child)
            if okShown and isShown then translateItemButtonNames(child, depth + 1) end
        end
    end
end

local function Apply()
    if not PF:IsEnabled("Quests") then return end
    local id = CurrentQuestID()
    local q = id and PF.Quests and PF.Quests[id]
    if not q then return end

    if shown(QuestFrameProgressPanel) then
        detailScope.ApplyText(QuestProgressTitleText, PF.Expand(q[TITLE]), "title")
        detailScope.ApplyText(QuestProgressText, PF.Expand(q[PROGRESS]), "body")
        translateStaticLabel(QuestProgressRequiredItemsText, "title") -- QuestTitleFont
        translateStaticLabel(QuestProgressRequiredMoneyText, "body")  -- QuestFontNormalSmall
        translateItemButtonNames(QuestProgressScrollChildFrame)
    else
        detailScope.ApplyText(QuestInfoTitleHeader, PF.Expand(q[TITLE]), "title")
        detailScope.ApplyText(QuestInfoObjectivesText, PF.Expand(q[OBJECTIVES]), "body")
        detailScope.ApplyText(QuestInfoDescriptionText, PF.Expand(q[DESCRIPTION]), "body")
        translateStaticLabel(QuestInfoObjectivesHeader, "title")   -- "Quest Objectives" (QuestTitleFont)
        translateStaticLabel(QuestInfoDescriptionHeader, "title")  -- "Quest Description" (QuestTitleFont)
        translateStaticLabel(QuestInfoRequiredMoneyText, "body")
        if QuestInfoRewardsFrame then
            translateStaticLabel(QuestInfoRewardsFrame.Header, "title")          -- "Rewards" (QuestTitleFont)
            translateStaticLabel(QuestInfoRewardsFrame.ItemReceiveText, "body")   -- "You will receive:" (QuestFont)
            if QuestInfoRewardsFrame.XPFrame then
                translateStaticLabel(QuestInfoRewardsFrame.XPFrame.ReceiveText, "body") -- "Experience:" (QuestFont)
            end
            translateItemButtonNames(QuestInfoRewardsFrame)
        end
        if MapQuestInfoRewardsFrame and shown(MapQuestInfoRewardsFrame) then
            translateItemButtonNames(MapQuestInfoRewardsFrame) -- modern map-log's own reward frame variant
        end
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

-- Which part of the quest was actually on screen when Report was clicked, so the filed issue
-- says e.g. "quest 366 -- progress" instead of just the bare ID -- a reader otherwise has no way
-- to know whether the reporter meant the title, the objectives, or the turn-in text.
-- Which panel/part was on screen, so the pre-filled issue title says e.g. "quest 366 (progress)"
-- instead of just the bare ID -- PF.ReportBug no longer takes or needs the actual field text (see
-- its own comment: that belongs in the reporter's own eyes + the repo's issue template, not
-- URL-encoded in-game text).
-- Plain labels, no embedded parens -- PF.ReportBug already wraps `extra` in its own "(...)" for
-- the title, so a value like "progress (in-progress dialogue)" produced a double-nested
-- "(progress (in-progress dialogue))" (confirmed via the actual generated URL/title).
local function currentQuestPart()
    if shown(QuestFrameRewardPanel) then return "rewards" end
    if shown(QuestFrameProgressPanel) then return "progress" end
    if shown(QuestFrameDetailPanel) then return "accept dialogue" end
    return "title"
end

local function reportCurrentQuest()
    local id = CurrentQuestID()
    PF.ReportBug("quest", id, nil, currentQuestPart())
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
    -- PL/EN pinned to the parchment's own top-right corner, at the same height as the quest
    -- title; Report stacked directly above it, in the empty chrome band between the NPC
    -- name bar and the parchment. Pulled straight from Blizzard's own XML (Gethe/wow-ui-source,
    -- Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestFrame*.xml) instead of guessing pixel
    -- offsets from a screenshot again (three guesses in a row were wrong):
    --   * QuestFrame itself is 338x496 -- the real visible window.
    --   * QuestFrameProgressPanel/QuestInfoFrame use QuestFramePanelTemplate, sized 384x512,
    --     anchored TOPLEFT to QuestFrame at (0,0) -- i.e. it's actually BIGGER than the visible
    --     window and shares its top-left corner, so its own RIGHT edge sits ~46px past
    --     QuestFrame's real right edge. That's exactly why anchoring to the panel's own TOPRIGHT
    --     put the buttons outside the frame, off in the background.
    --   * QuestProgressScrollFrame/QuestDetailScrollFrame (both named globals, inherit
    --     QuestScrollFrameTemplate) are the actual parchment content area: TOPLEFT of QuestFrame
    --     +(5,-65), 300 wide -- their own RIGHT edge IS the parchment's real right edge (with the
    --     scrollbar a few px further out). Anchor to that instead of the oversized panel.
    local function pinToTitle(parent, titleText, scrollFrame)
        local ok, toggle = pcall(detailScope.CreateControls, parent, "TOPRIGHT", -8, -6,
            reportCurrentQuest, nil, nil, "above")
        if ok and toggle and titleText and scrollFrame then
            toggle:ClearAllPoints()
            -- +14 nudges it up off the title's own line, into the empty chrome band above the
            -- parchment (confirmed close via screenshot; this was the only remaining tweak).
            toggle:SetPoint("TOP", titleText, "TOP", 0, 14)
            toggle:SetPoint("RIGHT", scrollFrame, "RIGHT", -4, 0)
        end
    end
    -- Accept dialogue (picking up a quest): per Blizzard's QuestInfo.lua (QuestInfo_Display),
    -- QuestInfoFrame is NOT a real visible container -- it's just a declaration bag in the XML.
    -- At runtime every one of its FontStrings (QuestInfoTitleHeader etc.) gets individually
    -- SetParent()'d onto whatever real panel is showing (QuestFrameDetailPanel here); QuestInfoFrame
    -- itself is never shown or positioned. Parenting our controls to it (as a prior attempt did)
    -- put them on an inert, undisplayed frame -- they simply never appeared, which is why Report/PL
    -- only ever showed up on the turn-in (Progress) panel. QuestFrameDetailPanel is the real
    -- container, and (unlike QuestFrameProgressPanel) its XML explicitly overrides
    -- QuestFramePanelTemplate's size back down to 338x496 -- same as QuestFrame -- so its own
    -- TOPRIGHT already lines up with the real window; QuestDetailScrollFrame (real, same
    -- QuestScrollFrameTemplate) is still the correct right-edge reference.
    if QuestFrameDetailPanel then
        pinToTitle(QuestFrameDetailPanel, QuestInfoTitleHeader, QuestDetailScrollFrame)
    end
    -- Turn-in AND "still in progress" (not yet ready to complete) both show QuestFrameProgressPanel
    -- -- same frame, just different text (QuestProgressText vs the required-items list) -- so this
    -- one install already covers both.
    if QuestFrameProgressPanel then
        pinToTitle(QuestFrameProgressPanel, QuestProgressTitleText, QuestProgressScrollFrame)
    end
end

-- Objective tracker (the "Quests" list on the right). Structure, from /pl dump on the beta client:
-- QuestObjectiveTracker.ContentsFrame -> blocks (block.poiQuestID, block.HeaderText, block.height) -> lines
-- (line.Text, line.objectiveKey). Objective lines like "0/6 Prairie Wolf Paw" are built by the game
-- from item/creature names, so only titles and the "ready to turn in" text are translated here.
--
-- Sizing: Blizzard's tracker measures each header/objective line right after its own
-- `fontString:SetText(english)` (ObjectiveTrackerBlock:SetStringText / AddObjective), sums those
-- into block.height and stacks blocks from it. Swapping text afterwards leaves that height frozen
-- from English, and patching block.height ourselves (an earlier before/after-delta version) drifts:
-- the "before" measurement can be stale, which over-counted and left blank lines under most blocks.
-- So, as for the quest-map list below: each header/line FontString gets a one-time SetText
-- post-hook that swaps in the Polish text synchronously -- before Blizzard measures -- looked up by
-- exact English string in a cache ApplyTracker fills. When ApplyTracker translated something new
-- (already measured as English), it asks the tracker to re-run its own update (MarkDirty), which
-- now measures Polish. We never touch a height.
local applyingTracker = false
local trackerCache = {} -- english string -> { polish, kind }

-- Tracker strings are tagged with a semantic kind ("title", "bold" for objectives, "body"); the
-- font weight is decided at the moment text is applied, so flipping the "bold" sub-option in
-- Config takes effect on the next tracker redraw without clearing any cache.
local function trackerFontKind(kind)
    if kind ~= "body" and not PF:IsSubEnabled("Quests", "trackerBold") then return "body" end
    return kind or "body"
end
local inTrackerHook = false

-- Every tracker header/line FontString gets hooked, translated or not: strings with no Polish
-- text still take our font (mixing Blizzard's stock face with ours looks wrong), and that has to
-- be in place before Blizzard measures too. `pfTranslated` marks "holds Polish text"; it is kept
-- apart from scope.ApplyText's own pfPolish, which for a font-only string is just the English.
local function hookTrackerText(fs, kind)
    fs.pfTrackerKind = kind
    if fs.pfTrackerHooked then return end
    fs.pfTrackerHooked = true
    hooksecurefunc(fs, "SetText", function(self, text)
        if inTrackerHook then return end
        if not PF:IsEnabled("Quests") or trackerScope.previewEnglish then return end
        inTrackerHook = true
        -- pcall: `text` may be a protected "secret value" string (see PF.Hash).
        pcall(function()
            if type(text) ~= "string" or text == "" then return end
            local entry = trackerCache[text]
            self.pfOriginal = text -- pooled FontStrings are reused: keep the EN-preview source fresh
            if entry then
                self.pfTranslated = entry[1]
                trackerScope.ApplyText(self, entry[1], trackerFontKind(entry[2]))
            else
                self.pfTranslated = nil
                trackerScope.ApplyText(self, text, trackerFontKind(self.pfTrackerKind or "body"))
            end
        end)
        inTrackerHook = false
    end)
end

-- Returns true when this English string is new to the cache (Blizzard already measured it).
local function setIfChanged(fs, text, kind)
    if not (fs and text and text ~= "") then return false end
    local english = fs:GetText()
    if not english or english == text or english == fs.pfTranslated then return false end
    hookTrackerText(fs, kind)
    local isNew = trackerCache[english] == nil
    trackerCache[english] = { text, kind }
    inTrackerHook = true
    fs.pfOriginal = english
    fs.pfTranslated = text
    trackerScope.ApplyText(fs, text, trackerFontKind(kind))
    inTrackerHook = false
    return isNew
end

-- Untranslated string: just put our font on it. Returns true the first time a string gets styled
-- (Blizzard measured it in its stock font, so a redraw is needed).
local function styleIfUntranslated(fs, kind)
    if not fs then return false end
    local text = fs:GetText()
    if not text or text == "" or text == fs.pfTranslated then return false end
    hookTrackerText(fs, kind)
    local fontKind = trackerFontKind(kind)
    if fs.pfStyledText == text and fs.pfStyledKind == fontKind then return false end
    fs.pfStyledText, fs.pfStyledKind = text, fontKind
    inTrackerHook = true
    fs.pfOriginal = text
    fs.pfTranslated = nil
    trackerScope.ApplyText(fs, text, fontKind)
    inTrackerHook = false
    return true
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
    local needsRefresh = false
    for _, block in ipairs({ contents:GetChildren() }) do
        local id = block.poiQuestID
        local q = id and PF.Quests and PF.Quests[id]
        if id and block:IsShown() then
            local header = block.HeaderText
            local current = header and header:GetText()
            if current then
                local prefix = titlePrefix(current)
                if q and setIfChanged(header, prefix .. PF.Expand(q[TITLE]), "title") then
                    needsRefresh = true
                elseif styleIfUntranslated(header, "title") then
                    needsRefresh = true
                end
            end
            local children = { block:GetChildren() }
            -- Narrative single-objective quests (e.g. "Return Gunther's Spellbook to him, on
            -- the island of Gunther's Retreat.") have no "N/M " counter at all, so
            -- translateObjectiveLine never matches -- confirmed via screenshot: title
            -- translated, this one flavor-text line under it left in English. Same gap already
            -- fixed for the quest-map list widget's q[OBJECTIVES] fallback below; only safe to
            -- reuse here when the block has exactly one numeric-key line (a real multi-objective
            -- quest has one line per objective, and blindly stamping the same summary sentence
            -- over all of them would be the same kind of regression already reverted elsewhere).
            local numericCount = 0
            for _, line in ipairs(children) do
                if type(line.objectiveKey) == "number" then numericCount = numericCount + 1 end
            end
            for _, line in ipairs(children) do
                local fs = line.Text
                if fs and fs:GetText() ~= fs.pfTranslated then
                    local pl
                    if line.objectiveKey == "QuestComplete" then
                        -- Was PF.Expand(q[OBJECTIVES]) -- wrong field: that's the objectives
                        -- *paragraph*, not the "Ready for turn-in"/completion line this widget
                        -- actually shows, so it silently never matched and stayed English.
                        pl = completionLineText(fs:GetText())
                    elseif type(line.objectiveKey) == "number" then
                        local text = fs:GetText()
                        pl = translateObjectiveLine(text) or completionLineText(text)
                            or (q and numericCount == 1 and q[OBJECTIVES] ~= "" and PF.Expand(q[OBJECTIVES]))
                    end
                    -- objectives are drawn bold, like the quest title above them
                    if pl and setIfChanged(fs, pl, "bold") then
                        needsRefresh = true
                    elseif not pl and styleIfUntranslated(fs, "bold") then
                        needsRefresh = true
                    end
                end
            end
        end
    end
    applyingTracker = false
    -- Blizzard measured those strings as English: have it re-run its own update (next frame) so
    -- the SetText hooks + cache put Polish in first. A second pass finds only cache hits.
    if needsRefresh and tracker and type(tracker.MarkDirty) == "function" then
        pcall(tracker.MarkDirty, tracker)
    end
end

-- Modern "Map & Quest Log" list (the quest titles + inline objective bullets shown in the World
-- Map's quest panel, before opening any single quest). Confirmed via Blizzard's own source
-- (Gethe/wow-ui-source, Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua) that this is a
-- completely different, older-style system from Gossip's ScrollBox/EnumerateFrames: titles and
-- objective lines are separate CreateFramePool-managed widgets (QuestScrollFrame.titleFramePool /
-- .objectiveFramePool), each carrying its own .questID, rebuilt from scratch on every
-- QuestLogQuests_Update() call (a bare global function, not a method) -- so like the tracker,
-- this must be re-applied every time that fires, not just once.
-- Sizing: Blizzard's QuestLogQuests_Update does `Text:SetText(english)` and immediately
-- `row:SetHeight(Text:GetStringHeight())`, sums those into the title button's height, then calls
-- Contents:Layout(). A plain post-hook on QuestLogQuests_Update therefore swaps text after every
-- height is frozen from the English string (rows overlap). Manually growing row heights is not an
-- option either: rows are CreateFramePool-managed, and our own SetHeight on a pooled frame fought
-- Blizzard's pool/layout bookkeeping and left ghosted, duplicated rows after a collapse/expand.
-- Instead, each row FontString gets a one-time SetText post-hook that swaps in the Polish text
-- *synchronously*, i.e. before Blizzard's next line (GetStringHeight) runs -- so Blizzard itself
-- measures, sizes and lays out the Polish text. The hook needs no row context: it looks the exact
-- English string up in a cache that ApplyQuestMapList fills the first time it sees a row. When
-- that pass translated something new, Blizzard's own update is re-run once (behind a flag) so
-- the rows already on screen get re-measured too.
local listCache = {} -- english string -> { polish, kind }
local inListHook, refreshingList = false, false

local function hookListText(fs)
    if fs.pfListHooked then return end
    fs.pfListHooked = true
    hooksecurefunc(fs, "SetText", function(self, text)
        if inListHook then return end
        if not PF:IsEnabled("Quests") or listScope.previewEnglish then return end
        -- pcall: `text` may be a protected "secret value" string (see PF.Hash).
        local ok, entry = pcall(function() return type(text) == "string" and listCache[text] end)
        if not (ok and entry) then return end
        inListHook = true
        self.pfOriginal = text -- pooled FontStrings are reused: keep the EN-preview source fresh
        listScope.ApplyText(self, entry[1], entry[2])
        inListHook = false
    end)
end

-- Returns true when `text` is new to the cache (i.e. Blizzard measured it before we translated).
local function setListText(fs, english, text, kind)
    if not (fs and english and text and text ~= "" and english ~= text) then return false end
    hookListText(fs)
    local isNew = listCache[english] == nil
    listCache[english] = { text, kind }
    inListHook = true
    fs.pfOriginal = english
    listScope.ApplyText(fs, text, kind)
    inListHook = false
    return isNew
end

local function ApplyQuestMapList()
    if refreshingList or not PF:IsEnabled("Quests") then return end
    local sf = QuestMapFrame and QuestMapFrame.QuestsFrame and QuestMapFrame.QuestsFrame.ScrollFrame
    if not sf then return end
    local needsRefresh = false
    if sf.titleFramePool then
        for title in sf.titleFramePool:EnumerateActive() do
            local id = title.questID
            local q = id and PF.Quests and PF.Quests[id]
            -- Skip rows our SetText hook already translated (their text is Polish, not a cache key).
            if q and title.Text and title.Text:GetText() ~= title.Text.pfPolish then
                local current = title.Text:GetText()
                local prefix = titlePrefix(current)
                if setListText(title.Text, current, prefix .. PF.Expand(q[TITLE]), "title") then
                    needsRefresh = true
                end
            end
        end
    end
    if sf.objectiveFramePool then
        -- How many objective lines each quest has: the q[OBJECTIVES] paragraph is only a valid
        -- stand-in for a quest with exactly one (see the same rule in ApplyTracker), otherwise
        -- it would get stamped over every line of a multi-objective quest.
        local perQuest = {}
        for line in sf.objectiveFramePool:EnumerateActive() do
            if line.questID then perQuest[line.questID] = (perQuest[line.questID] or 0) + 1 end
        end
        for line in sf.objectiveFramePool:EnumerateActive() do
            if line.Text and line.Text:GetText() ~= line.Text.pfPolish then
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
                    or (q and perQuest[id] == 1 and q[OBJECTIVES] ~= "" and PF.Expand(q[OBJECTIVES]))
                if pl and setListText(line.Text, text, pl, "body") then needsRefresh = true end
            end
        end
    end
    -- Rows already on screen were measured from English; have Blizzard redo its own update now
    -- that the SetText hooks + cache will put Polish in before it measures.
    if needsRefresh and type(_G["QuestLogQuests_Update"]) == "function" then
        refreshingList = true
        pcall(_G["QuestLogQuests_Update"])
        refreshingList = false
    end
end

-- Quest-list row tooltip (hovering a quest in the Map & Quest Log's title list): built from
-- plain GameTooltip:AddLine calls (title, level requirement, then the same kind of
-- objective/flavor lines as the row itself), not a dedicated SetXxx method like Items/Spells
-- get -- so there's nothing clean to hook there. Instead: hooked on GameTooltip:Show() itself
-- (cheap to bail early -- almost every tooltip's owner has no .questID) and translated using the
-- row button's own .questID, same as ApplyQuestMapList.
local retooltipping = false
local function translateQuestTooltip(tt)
    if retooltipping or not PF:IsEnabled("Quests") then return end
    local changed = false
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
            -- Untranslated lines take our font too (same text), so the tooltip doesn't mix
            -- Blizzard's face with ours.
            if pl and pl ~= text then
                PF.SetText(fs, pl, i == 1 and "title" or "body")
                changed = true
            elseif text ~= "" and PF.SetText(fs, text, "body") then
                changed = true
            end
        end
    end
    -- The tooltip sized itself for the English lines when it was shown; Show() again is
    -- Blizzard's own path to re-measure and resize it (guarded: this runs from a Show hook).
    if changed then
        retooltipping = true
        tt:Show()
        retooltipping = false
    end
end

local hooked = false

function Quests:OnEnable()
    if hooked then
        -- Already hooked from a previous enable -- this is a re-enable after OnDisable reverted
        -- everything to English (see OnDisable below). Flip the scopes back and force a fresh
        -- pass so anything that changed while disabled (a new quest picked up, tracker updated,
        -- etc., none of which got registered with these scopes since Apply()/ApplyTracker() bail
        -- out early while disabled) gets (re-)translated now, not just on its next natural update.
        detailScope.SetPreviewEnglish(false)
        trackerScope.SetPreviewEnglish(false)
        listScope.SetPreviewEnglish(false)
        Apply()
        ApplyTracker()
        ApplyQuestMapList()
        return
    end
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

-- Config calls this after a sub-option changes: make the tracker re-run its own update so every
-- line is re-applied (through the SetText hooks above) with the new weight.
function Quests:OnSubChanged()
    local tracker = QuestObjectiveTracker
    if tracker and type(tracker.MarkDirty) == "function" then pcall(tracker.MarkDirty, tracker) end
end

function Quests:OnDisable()
    -- Was a no-op (comment claimed "disabling takes effect on the next window" -- true for
    -- windows that actually get closed/reopened, but the objective tracker is persistent: it
    -- never closes, so an already-translated line just stayed Polish forever since nothing ever
    -- reverted it). Force every currently-registered FontString in all three scopes back to
    -- English immediately, same mechanism the PL/EN preview button itself uses.
    detailScope.SetPreviewEnglish(true)
    trackerScope.SetPreviewEnglish(true)
    listScope.SetPreviewEnglish(true)
end

PF:RegisterModule("Quests", Quests)
