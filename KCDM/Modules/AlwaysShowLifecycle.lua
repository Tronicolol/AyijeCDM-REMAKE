local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS or {}
local EMPTY_FRAMES = {}

local function HasBuffAlwaysShow(groupData)
    if not groupData or type(groupData.spells) ~= "table" or type(groupData.spellOverrides) ~= "table" then return false end
    for _, spellID in ipairs(groupData.spells) do
        local override = CDM.ResolveBuffOverrideEntry and CDM:ResolveBuffOverrideEntry(groupData.spellOverrides, spellID)
        if override and override.alwaysShow == true then return true end
    end
    return false
end

local function HasBarAlwaysShow(groupData)
    if not groupData or type(groupData.spells) ~= "table" or type(groupData.spellOverrides) ~= "table" then return false end
    for _, spellID in ipairs(groupData.spells) do
        local override = CDM.ResolveBarOverrideEntry and CDM:ResolveBarOverrideEntry(groupData.spellOverrides, spellID)
        if override and override.alwaysShow == true then return true end
    end
    return false
end

local function RefreshEmptyBuffGroups(viewer)
    local sets = CDM.BuffGroupSets
    if not (viewer and viewer.itemFramePool and sets and sets.groups) then return end
    if not CDM.CheckBuffRegistryMatch or not CDM.PositionBuffGroupFrames then return end

    local occupied = {}
    local editMode = CDM.isEditModeActive or (_G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown())
    for frame in viewer.itemFramePool:EnumerateActive() do
        if editMode or frame:IsShown() or frame.cooldownInfo then
            local matchType, _, groupIndex = CDM.CheckBuffRegistryMatch(frame)
            if matchType == "buffgroup" and groupIndex then occupied[groupIndex] = true end
        end
    end

    for groupIndex, groupData in ipairs(sets.groups) do
        if not occupied[groupIndex] and HasBuffAlwaysShow(groupData) then
            CDM:PositionBuffGroupFrames(groupIndex, EMPTY_FRAMES, nil, false)
        end
    end
end

local function RefreshEmptyBarGroups(viewer)
    local sets = CDM.BarGroupSets
    if not (viewer and viewer.itemFramePool and sets and sets.groups) then return end
    if not CDM.CheckBarRegistryMatch or not CDM.PositionBarGroupFrames then return end

    local occupied = {}
    for frame in viewer.itemFramePool:EnumerateActive() do
        local matchType, _, groupIndex = CDM.CheckBarRegistryMatch(frame)
        if matchType == "bargroup" and groupIndex then occupied[groupIndex] = true end
    end

    local viewerName = viewer:GetName()
    for groupIndex, groupData in ipairs(sets.groups) do
        if not occupied[groupIndex] and HasBarAlwaysShow(groupData) then
            CDM:PositionBarGroupFrames(groupIndex, EMPTY_FRAMES, viewerName)
        end
    end
end

if type(CDM.ForceReanchor) == "function" then
    hooksecurefunc(CDM, "ForceReanchor", function(_, viewer)
        if not viewer then return end
        local viewerName = viewer:GetName()
        if viewerName == VIEWERS.BUFF then
            RefreshEmptyBuffGroups(viewer)
        elseif viewerName == VIEWERS.BUFF_BAR then
            RefreshEmptyBarGroups(viewer)
        end
    end)
end

CDM:RegisterRefreshCallback("alwaysShowEmptyBuffGroups", function()
    C_Timer.After(0, function()
        local viewer = VIEWERS.BUFF and _G[VIEWERS.BUFF]
        if viewer then RefreshEmptyBuffGroups(viewer) end
    end)
end, 70, { "BUFF_DATA" })

CDM:RegisterRefreshCallback("alwaysShowEmptyBarGroups", function()
    C_Timer.After(0, function()
        local viewer = VIEWERS.BUFF_BAR and _G[VIEWERS.BUFF_BAR]
        if viewer then RefreshEmptyBarGroups(viewer) end
    end)
end, 70, { "BAR_DATA" })
