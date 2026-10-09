local _, PF = ...

-- Zone / subzone names: the minimap's zone label (and its hover tooltip), the zone-entry banner
-- and the world map title. Data is PF.Text.Places (client AreaTable names); a name with no
-- translation simply hash-misses and stays English, like every other module.
local Places = {
    desc = "Zone and subzone names: minimap, zone-entry banner, world map title",
    label = "Places",
    implemented = true,
}

local function translateFS(fs)
    if not (fs and fs.GetText and PF.Text and PF.Text.Places) then return end
    local text = fs:GetText()
    local pl = text and PF.Text.Places[PF.Hash(text)]
    if pl and pl ~= text then PF.SetText(fs, pl, "body") end
end

local function apply()
    if not PF:IsEnabled("Places") then return end
    -- Classic keeps the label in MinimapZoneText; newer clients nest it under MinimapCluster.
    translateFS(_G.MinimapZoneText)
    local cluster = _G.MinimapCluster
    local zb = cluster and (cluster.ZoneTextButton or cluster.ZoneText)
    if zb then translateFS(zb.Text or zb) end
    -- Zone-entry banner
    translateFS(_G.ZoneTextString)
    translateFS(_G.SubZoneTextString)
    translateFS(_G.PVPInfoTextString)
    translateFS(_G.PVPArenaTextString)
    -- World map title
    local map = _G.WorldMapFrame
    if map and map:IsShown() and map.BorderFrame and map.BorderFrame.TitleContainer then
        translateFS(map.BorderFrame.TitleContainer.TitleText)
    end
end

local function minimapTooltip()
    if not PF:IsEnabled("Places") then return end
    if GameTooltip and GameTooltip:IsShown() then PF.TranslateTooltipLines(GameTooltip, PF.Text.Places) end
end

local hooked
function Places:OnEnable()
    if hooked then return end
    hooked = true
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
                         "ZONE_CHANGED_NEW_AREA" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    -- Blizzard sets the text in its own handler for the same event; run after it.
    ev:SetScript("OnEvent", function()
        C_Timer.After(0, apply)
        C_Timer.After(0.3, apply)
    end)
    for _, fn in ipairs({ "Minimap_Update", "MinimapZoneText_Update", "SetMapToCurrentZone" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, apply) end
    end
    for _, b in ipairs({ _G.MinimapZoneTextButton, _G.MinimapCluster and _G.MinimapCluster.ZoneTextButton }) do
        if b and b.HookScript then
            pcall(b.HookScript, b, "OnEnter", function() C_Timer.After(0, minimapTooltip) end)
        end
    end
    if _G.WorldMapFrame and WorldMapFrame.HookScript then
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function() C_Timer.After(0, apply) end)
    end
    apply()
end

function Places:OnDisable() end

PF:RegisterModule("Places", Places)
