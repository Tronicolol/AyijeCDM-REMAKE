local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Glow then return end

local Glow = CDM.Glow
local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
if not VIEWERS then return end

local originalHookAlertManager = Glow.HookAlertManager
if type(originalHookAlertManager) ~= "function" then return end

local function IsManagedCooldownFrame(frame)
    if not frame then return false end

    local viewer
    if frame.GetViewerFrame then
        viewer = frame:GetViewerFrame()
    end

    if viewer == _G[VIEWERS.ESSENTIAL] or viewer == _G[VIEWERS.UTILITY] then
        return true
    end

    local parent = frame:GetParent()
    while parent do
        local name = parent:GetName()
        if name == VIEWERS.ESSENTIAL or name == VIEWERS.UTILITY then
            return true
        end
        parent = parent:GetParent()
    end

    return false
end

local function ReadHideFlag(override)
    if override and override.hideBlizzardProcGlow ~= nil then
        return override.hideBlizzardProcGlow == true, true
    end
    return false, false
end

local function GetGroupedOverride(frame)
    local sets = CDM.CooldownGroupSets
    if not sets then return nil, false end

    local match
    local cooldownID = frame.cooldownID
    if cooldownID and sets.cooldownIDGrouped then
        match = sets.cooldownIDGrouped[cooldownID]
    end

    local groupIdx = match and match.groupIdx
    local storedID = match and match.storedID

    if not groupIdx and CDM.CheckCdGroupMatch then
        groupIdx = CDM.CheckCdGroupMatch(frame)
        storedID = frame.cdmCdGroupSpellID
    end

    if not groupIdx then
        return nil, false
    end

    local groupData = sets.groups and sets.groups[groupIdx]
    if not groupData or not CDM.GetCooldownGroupSpellOverride then
        return nil, true
    end

    return CDM.GetCooldownGroupSpellOverride(groupData, storedID), true
end

local function ShouldHideBlizzardProcGlow(frame)
    local groupedOverride, isGrouped = GetGroupedOverride(frame)
    if isGrouped then
        local hide = ReadHideFlag(groupedOverride)
        return hide
    end

    if not CDM.GetUngroupedCooldownOverride then return false end

    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
    if info and info.overrideTooltipSpellID then
        local override = CDM:GetUngroupedCooldownOverride(info.overrideTooltipSpellID)
        local hide, found = ReadHideFlag(override)
        if found then return hide end
    end

    if CDM.GetSpellIDCandidates then
        for _, spellID in ipairs(CDM:GetSpellIDCandidates(frame)) do
            local override = CDM:GetUngroupedCooldownOverride(spellID)
            local hide, found = ReadHideFlag(override)
            if found then return hide end
        end
    end

    return false
end

function Glow:RefreshBlizzardProcSuppression()
    if not CDM.ForEachActiveFrame then return end

    CDM:ForEachActiveFrame({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }, function(frame)
        if ShouldHideBlizzardProcGlow(frame) then
            self:HideBlizzardGlow(frame)
            self:RequestBuffGlow(frame, "alert", false)
        end
    end)
end

Glow.HookAlertManager = function(self)
    originalHookAlertManager(self)

    if self.blizzardProcSuppressionHooked then return end

    local alertManager = _G.ActionButtonSpellAlertManager
    if not alertManager then return end

    hooksecurefunc(alertManager, "ShowAlert", function(_, frame)
        if not IsManagedCooldownFrame(frame) then return end
        if not ShouldHideBlizzardProcGlow(frame) then return end

        self:HideBlizzardGlow(frame)
        self:RequestBuffGlow(frame, "alert", false)
    end)

    self.blizzardProcSuppressionHooked = true
end
