local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Glow then return end

local Glow = CDM.Glow
local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
local LCG = LibStub("LibCustomGlow-1.0", true)
if not VIEWERS or not LCG then return end

local originalRequestBuffGlow = Glow.RequestBuffGlow
local originalStopGlow = Glow.StopGlow
local originalInstallAcquireResetHook = Glow.InstallAcquireResetHook
if type(originalRequestBuffGlow) ~= "function" or type(originalStopGlow) ~= "function" then return end

local GLOW_KEY = "CDM_SpellAlert"
local PROC_GLOW_FIELD = "_ProcGlow" .. GLOW_KEY

local PRODUCER_PRIORITY = {
    alert = 1,
    aura = 2,
    buff = 2,
    ready = 3,
}

local VALID_GLOW_TYPES = {
    pixel = true,
    autocast = true,
    button = true,
    proc = true,
}

local customStates = setmetatable({}, { __mode = "k" })
local pendingDisableGeneration = setmetatable({}, { __mode = "k" })

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

local function ReadGlowTypeOverride(override)
    local glowType = override and override.glowTypeOverride
    if glowType and VALID_GLOW_TYPES[glowType] then
        return glowType, true
    end
    return nil, false
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

local function GetSpellGlowTypeOverride(frame)
    if not IsManagedCooldownFrame(frame) then return nil end

    local groupedOverride, isGrouped = GetGroupedOverride(frame)
    if isGrouped then
        local glowType = ReadGlowTypeOverride(groupedOverride)
        return glowType
    end

    if not CDM.GetUngroupedCooldownOverride then return nil end

    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
    if info and info.overrideTooltipSpellID then
        local override = CDM:GetUngroupedCooldownOverride(info.overrideTooltipSpellID)
        local glowType, found = ReadGlowTypeOverride(override)
        if found then return glowType end
    end

    if CDM.GetSpellIDCandidates then
        for _, spellID in ipairs(CDM:GetSpellIDCandidates(frame)) do
            local override = CDM:GetUngroupedCooldownOverride(spellID)
            local glowType, found = ReadGlowTypeOverride(override)
            if found then return glowType end
        end
    end

    return nil
end

local function GetCfg(key, fallback)
    local db = CDM.db or {}
    local defaults = CDM.defaults or {}
    if db[key] ~= nil then return db[key] end
    if defaults[key] ~= nil then return defaults[key] end
    return fallback
end

local colorArrayCache = setmetatable({}, { __mode = "k" })

local function ToColorArray(color)
    if type(color) ~= "table" then return nil end

    local arr = colorArrayCache[color]
    if not arr then
        arr = { 1, 1, 1, 1 }
        colorArrayCache[color] = arr
    end

    arr[1] = color.r or 1
    arr[2] = color.g or 1
    arr[3] = color.b or 1
    arr[4] = color.a or 1
    return arr
end

local function GetGlowColor(overrideColor)
    if overrideColor then
        return ToColorArray(overrideColor)
    end
    if GetCfg("glowUseCustomColor", false) then
        return ToColorArray(GetCfg("glowColor", nil))
    end
    return nil
end

local procGlowOpts = {
    color = nil,
    startAnim = false,
    duration = 1,
    xOffset = 0,
    yOffset = 0,
    key = GLOW_KEY,
    frameLevel = 0,
}

local function StopGlowByType(host, glowType)
    if glowType == "pixel" then
        LCG.PixelGlow_Stop(host, GLOW_KEY)
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Stop(host, GLOW_KEY)
    elseif glowType == "button" then
        LCG.ButtonGlow_Stop(host)
    elseif glowType == "proc" then
        local procFrame = host[PROC_GLOW_FIELD]
        if procFrame then
            if procFrame.ProcStartAnim and procFrame.ProcStartAnim:IsPlaying() then
                procFrame.ProcStartAnim:Stop()
            end
            if procFrame.ProcLoopAnim and procFrame.ProcLoopAnim:IsPlaying() then
                procFrame.ProcLoopAnim:Stop()
            end
        end
        LCG.ProcGlow_Stop(host, GLOW_KEY)
    end
end

local function StartOrUpdateGlowByType(host, glowType, overrideColor)
    local color = GetGlowColor(overrideColor)
    local frameLevel = 5

    if glowType == "pixel" then
        local length = GetCfg("glowPixelLength", 0)
        if length == 0 then length = nil end
        LCG.PixelGlow_Start(
            host,
            color,
            GetCfg("glowPixelLines", 8),
            GetCfg("glowPixelFrequency", 0.2),
            length,
            GetCfg("glowPixelThickness", 2),
            GetCfg("glowPixelXOffset", 0),
            GetCfg("glowPixelYOffset", 0),
            GetCfg("glowPixelBorder", false) and true or false,
            GLOW_KEY,
            frameLevel
        )
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(
            host,
            color,
            GetCfg("glowAutocastParticles", 4),
            GetCfg("glowAutocastFrequency", 0.2),
            GetCfg("glowAutocastScale", 1),
            GetCfg("glowAutocastXOffset", 0),
            GetCfg("glowAutocastYOffset", 0),
            GLOW_KEY,
            frameLevel
        )
    elseif glowType == "button" then
        local frequency = GetCfg("glowButtonFrequency", 0)
        if frequency == 0 then frequency = nil end
        LCG.ButtonGlow_Start(host, color, frequency, frameLevel)
    elseif glowType == "proc" then
        procGlowOpts.color = color
        procGlowOpts.duration = GetCfg("glowProcDuration", 1)
        procGlowOpts.xOffset = GetCfg("glowProcXOffset", 0)
        procGlowOpts.yOffset = GetCfg("glowProcYOffset", 0)
        procGlowOpts.frameLevel = frameLevel
        LCG.ProcGlow_Start(host, procGlowOpts)
        local procFrame = host[PROC_GLOW_FIELD]
        if procFrame then
            procFrame:SetScript("OnHide", nil)
        end
    end
end

local function ColorsMatch(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return a.r == b.r and a.g == b.g and a.b == b.b and (a.a or 1) == (b.a or 1)
end

local function EnsureHost(frame)
    local host = frame.cdmBuffGlowHost
    if host then return host end

    host = CreateFrame("Frame", nil, frame)
    host:SetClampedToScreen(false)
    frame.cdmBuffGlowHost = host
    frame.cdmBuffGlowHostAnchorTarget = nil
    frame.cdmBuffGlowHostStrata = nil
    frame.cdmBuffGlowHostLevel = nil
    return host
end

local function SyncHost(frame, host)
    if not frame or not host then return end

    if frame.cdmBuffGlowHostAnchorTarget ~= frame then
        host:SetParent(frame)
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.cdmBuffGlowHostAnchorTarget = frame
    end

    local strata = frame:GetFrameStrata()
    if strata and frame.cdmBuffGlowHostStrata ~= strata then
        host:SetFrameStrata(strata)
        frame.cdmBuffGlowHostStrata = strata
    end

    local level = frame:GetFrameLevel()
    if level and frame.cdmBuffGlowHostLevel ~= level then
        host:SetFrameLevel(level)
        frame.cdmBuffGlowHostLevel = level
    end
end

local function DoesGlowSourceMatchID(sourceID, sourceBase, id)
    if not sourceID or not id then return false end
    if id == sourceID or id == sourceBase then
        return true
    end

    local base = CDM.NormalizeToBase and CDM.NormalizeToBase(id)
    return base == sourceID or base == sourceBase
end

local function IsSourceStillValid(frame, sourceID)
    if not sourceID then return true end
    if not CDM.GetCurrentSpecID or not CDM.GetSpellGlowEnabled then return true end

    local specID = CDM:GetCurrentSpecID()
    if not specID or not CDM:GetSpellGlowEnabled(specID, sourceID) then
        return false
    end

    local sourceBase = CDM.NormalizeToBase and CDM.NormalizeToBase(sourceID) or sourceID
    if DoesGlowSourceMatchID(sourceID, sourceBase, frame.cdmBuffCategorySpellID) then
        return true
    end

    if CDM.GetSpellIDCandidates then
        for _, id in ipairs(CDM:GetSpellIDCandidates(frame)) do
            if DoesGlowSourceMatchID(sourceID, sourceBase, id) then
                return true
            end
        end
    end

    return false
end

local function CanTakeProducer(frame, producerToken)
    local current = frame.cdmGlowProducer
    if not current or current == producerToken then return true end

    local currentPri = PRODUCER_PRIORITY[current]
    local requestPri = PRODUCER_PRIORITY[producerToken]
    if currentPri and requestPri and currentPri < requestPri then
        return false
    end

    return true
end

local function StopCustomState(frame, state)
    if not state then return end

    pendingDisableGeneration[frame] = nil

    local host = frame.cdmBuffGlowHost
    if host and host.cdmGlowActive then
        StopGlowByType(host, host.cdmGlowType)
        host.cdmGlowActive = false
        host.cdmGlowType = nil
        host.cdmGlowOverrideType = nil
        host.cdmGlowOverrideColor = nil
        host:Hide()
    elseif host then
        host:Hide()
    end

    frame.cdmGlowProducer = nil
    frame.cdmBuffGlowWanted = nil
    frame.cdmBuffGlowOverrideColor = nil
    frame.cdmBuffGlowSourceID = nil
    customStates[frame] = nil
end

local function ApplyCustomVisual(frame, state, glowType, overrideColor, forceUpdate)
    local host = EnsureHost(frame)
    SyncHost(frame, host)

    local sameType = host.cdmGlowActive
        and host.cdmGlowType == glowType
        and host.cdmGlowOverrideType == glowType

    if sameType then
        if forceUpdate or not ColorsMatch(host.cdmGlowOverrideColor, overrideColor) then
            StartOrUpdateGlowByType(host, glowType, overrideColor)
            host.cdmGlowOverrideColor = overrideColor
        end
    else
        if host.cdmGlowActive then
            StopGlowByType(host, host.cdmGlowType)
        end

        StartOrUpdateGlowByType(host, glowType, overrideColor)
        host.cdmGlowActive = true
        host.cdmGlowType = glowType
        host.cdmGlowOverrideType = glowType
        host.cdmGlowOverrideColor = overrideColor
    end

    state.glowType = glowType
    state.overrideColor = overrideColor

    if frame:IsShown() then
        host:Show()
    else
        host:Hide()
    end
end

local function EnsureFrameHooks(frame)
    if frame.cdmPerSpellGlowLifecycleHooked then return end
    frame.cdmPerSpellGlowLifecycleHooked = true

    frame:HookScript("OnShow", function(self)
        local currentState = customStates[self]
        if not currentState or not self.cdmGlowProducer then return end
        if not IsSourceStillValid(self, self.cdmBuffGlowSourceID) then
            StopCustomState(self, currentState)
            return
        end

        local glowType = GetSpellGlowTypeOverride(self)
        if not glowType then return end

        local host = EnsureHost(self)
        SyncHost(self, host)

        if not host.cdmGlowActive then
            ApplyCustomVisual(self, currentState, glowType, self.cdmBuffGlowOverrideColor, false)
        else
            host:Show()
        end
    end)

    frame:HookScript("OnSizeChanged", function(self)
        local currentState = customStates[self]
        if not currentState or not self.cdmGlowProducer then return end

        local host = self.cdmBuffGlowHost
        if host then
            SyncHost(self, host)
        end
    end)
end

local function CancelPendingDisable(frame)
    if pendingDisableGeneration[frame] then
        pendingDisableGeneration[frame] = pendingDisableGeneration[frame] + 1
    end
end

local function ScheduleDisableResolution(frame)
    local generation = (pendingDisableGeneration[frame] or 0) + 1
    pendingDisableGeneration[frame] = generation

    C_Timer.After(0, function()
        if pendingDisableGeneration[frame] ~= generation then return end
        pendingDisableGeneration[frame] = nil

        local state = customStates[frame]
        if not state or frame.cdmGlowProducer then return end

        if frame:IsShown() and CDM.RefreshFrameVisuals then
            CDM:RefreshFrameVisuals(frame)
        end

        if customStates[frame] == state and not frame.cdmGlowProducer then
            StopCustomState(frame, state)
        end
    end)
end

local function TransitionBackToGlobal(frame, state)
    if not state then return end

    local producerToken = frame.cdmGlowProducer
    local overrideColor = frame.cdmBuffGlowOverrideColor
    local sourceID = frame.cdmBuffGlowSourceID

    pendingDisableGeneration[frame] = nil
    customStates[frame] = nil

    frame.cdmGlowProducer = nil
    frame.cdmBuffGlowWanted = nil
    frame.cdmBuffGlowOverrideColor = nil
    frame.cdmBuffGlowSourceID = nil

    if producerToken then
        originalRequestBuffGlow(Glow, frame, producerToken, true, overrideColor, sourceID)
    else
        local host = frame.cdmBuffGlowHost
        if host and host.cdmGlowActive then
            StopGlowByType(host, host.cdmGlowType)
            host.cdmGlowActive = false
            host.cdmGlowType = nil
            host.cdmGlowOverrideType = nil
            host.cdmGlowOverrideColor = nil
            host:Hide()
        end
    end
end

Glow.RequestBuffGlow = function(self, frame, producerToken, enabled, overrideColor, sourceID)
    if not frame then return end

    local state = customStates[frame]
    local glowType = GetSpellGlowTypeOverride(frame)

    if not enabled then
        if state then
            if frame.cdmGlowProducer ~= producerToken then return end

            frame.cdmGlowProducer = nil
            frame.cdmBuffGlowWanted = nil
            frame.cdmBuffGlowOverrideColor = nil
            frame.cdmBuffGlowSourceID = nil
            ScheduleDisableResolution(frame)
            return
        end

        originalRequestBuffGlow(self, frame, producerToken, false, overrideColor, sourceID)
        return
    end

    if not glowType then
        if state then
            TransitionBackToGlobal(frame, state)
        end
        originalRequestBuffGlow(self, frame, producerToken, true, overrideColor, sourceID)
        return
    end

    if not CanTakeProducer(frame, producerToken) then return end

    CancelPendingDisable(frame)

    if not state then
        state = {}
        customStates[frame] = state
    end

    EnsureFrameHooks(frame)

    frame.cdmGlowProducer = producerToken
    frame.cdmBuffGlowWanted = nil
    frame.cdmBuffGlowOverrideColor = overrideColor
    frame.cdmBuffGlowSourceID = sourceID

    ApplyCustomVisual(frame, state, glowType, overrideColor, false)
end

Glow.StopGlow = function(self, frame)
    local state = frame and customStates[frame]
    if state then
        StopCustomState(frame, state)
    end
    originalStopGlow(self, frame)
end

if type(originalInstallAcquireResetHook) == "function" then
    Glow.InstallAcquireResetHook = function(self, viewer)
        originalInstallAcquireResetHook(self, viewer)

        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
            local state = customStates[itemFrame]
            if state then
                StopCustomState(itemFrame, state)
            end
        end)
    end
end

function Glow:RefreshSpellGlowTypeOverrides(forceUpdate)
    if not CDM.ForEachActiveFrame then return end

    CDM:ForEachActiveFrame({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }, function(frame)
        local state = customStates[frame]
        local glowType = GetSpellGlowTypeOverride(frame)

        if state and not glowType then
            TransitionBackToGlobal(frame, state)
            return
        end

        if not state or not glowType or not frame.cdmGlowProducer then return end

        ApplyCustomVisual(
            frame,
            state,
            glowType,
            frame.cdmBuffGlowOverrideColor,
            forceUpdate == true
        )
    end)
end

CDM:RegisterRefreshCallback("perSpellGlowType", function()
    Glow:RefreshSpellGlowTypeOverrides(true)
end, 55, { "STYLE" })
