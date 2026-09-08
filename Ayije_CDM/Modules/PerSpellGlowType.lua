local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Glow then return end

local Glow = CDM.Glow
local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
local LCG = LibStub("LibCustomGlow-1.0", true)
if not VIEWERS or not LCG then return end

local originalRequestBuffGlow = Glow.RequestBuffGlow
if type(originalRequestBuffGlow) ~= "function" then return end

local GLOW_KEY = "CDM_SpellAlert"
local PROC_GLOW_FIELD = "_ProcGlow" .. GLOW_KEY

local VALID_GLOW_TYPES = {
    pixel = true,
    autocast = true,
    button = true,
    proc = true,
}

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

local function StartGlowByType(host, glowType, overrideColor)
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

local function ApplyGlowTypeOverride(frame, glowType)
    if not glowType then return end

    local host = frame.cdmBuffGlowHost
    if not host or not frame:IsShown() or not host.cdmGlowActive then return end

    local overrideColor = frame.cdmBuffGlowOverrideColor
    if host.cdmGlowType == glowType then
        host.cdmGlowOverrideType = glowType
        host.cdmGlowOverrideColor = overrideColor
        return
    end

    StopGlowByType(host, host.cdmGlowType)
    host.cdmGlowActive = false
    host.cdmGlowType = nil

    StartGlowByType(host, glowType, overrideColor)
    host.cdmGlowActive = true
    host.cdmGlowType = glowType
    host.cdmGlowOverrideType = glowType
    host.cdmGlowOverrideColor = overrideColor
end

local function EnsureFrameShowHook(frame)
    if frame.cdmPerSpellGlowTypeShowHooked then return end
    frame.cdmPerSpellGlowTypeShowHooked = true

    frame:HookScript("OnShow", function(self)
        if not self.cdmBuffGlowWanted or not self.cdmGlowProducer then return end
        local glowType = GetSpellGlowTypeOverride(self)
        if glowType then
            ApplyGlowTypeOverride(self, glowType)
        end
    end)
end

Glow.RequestBuffGlow = function(self, frame, producerToken, enabled, overrideColor, sourceID)
    if not frame then return end

    local glowType = enabled and GetSpellGlowTypeOverride(frame) or nil
    local host = frame.cdmBuffGlowHost

    if enabled and glowType
       and frame.cdmGlowProducer == producerToken
       and frame.cdmBuffGlowWanted
       and host and host.cdmGlowActive
       and host.cdmGlowOverrideType == glowType
       and ColorsMatch(host.cdmGlowOverrideColor, overrideColor)
       and frame.cdmBuffGlowSourceID == sourceID then
        frame.cdmBuffGlowOverrideColor = overrideColor
        frame.cdmBuffGlowSourceID = sourceID
        host.cdmGlowOverrideColor = overrideColor
        return
    end

    originalRequestBuffGlow(self, frame, producerToken, enabled, overrideColor, sourceID)

    if not enabled or not glowType then return end
    if frame.cdmGlowProducer ~= producerToken or not frame.cdmBuffGlowWanted then return end

    EnsureFrameShowHook(frame)
    ApplyGlowTypeOverride(frame, glowType)
end

function Glow:RefreshSpellGlowTypeOverrides()
    if not CDM.ForEachActiveFrame then return end

    CDM:ForEachActiveFrame({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }, function(frame)
        if not frame.cdmBuffGlowWanted or not frame.cdmGlowProducer then return end

        local glowType = GetSpellGlowTypeOverride(frame)
        local host = frame.cdmBuffGlowHost

        if glowType then
            EnsureFrameShowHook(frame)
            ApplyGlowTypeOverride(frame, glowType)
            return
        end

        if not host or not host.cdmGlowOverrideType then return end

        if not frame:IsShown() then
            host.cdmGlowOverrideType = nil
            return
        end

        originalRequestBuffGlow(
            self,
            frame,
            frame.cdmGlowProducer,
            true,
            frame.cdmBuffGlowOverrideColor,
            frame.cdmBuffGlowSourceID
        )
    end)
end
