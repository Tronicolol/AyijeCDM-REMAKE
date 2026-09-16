local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Glow then return end

local Glow = CDM.Glow
local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
local LCG = LibStub("LibCustomGlow-1.0", true)
if not VIEWERS or not LCG then return end
if Glow.cdmUnifiedControllerInstalled then return end
Glow.cdmUnifiedControllerInstalled = true

local GLOW_KEY = "CDM_SpellAlert"
local PROC_GLOW_FIELD = "_ProcGlow" .. GLOW_KEY
local VALID_TYPES = { pixel = true, autocast = true, button = true, proc = true }
local PRODUCER_ORDER = { "alert", "aura", "buff", "ready" }
local VALID_PRODUCERS = { alert = true, aura = true, buff = true, ready = true }

local states = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })
local colorArrays = setmetatable({}, { __mode = "k" })
local originalRefreshActiveGlows = Glow.RefreshActiveGlows
local lastVisualConfigVersion = Glow.visualConfigVersion or 0
local specTransitionSuspended = false
local specTransitionGeneration = 0
local layoutMutationSuspended = false
local layoutMutationGeneration = 0
local resetSnapshot = {}
local LAYOUT_SETTLE_DELAY = 0.12

local procOpts = {
    color = nil,
    startAnim = false,
    duration = 1,
    xOffset = 0,
    yOffset = 0,
    key = GLOW_KEY,
    frameLevel = 5,
}

local function GetCfg(key, fallback)
    local db = CDM.db or {}
    local defaults = CDM.defaults or {}
    if db[key] ~= nil then return db[key] end
    if defaults[key] ~= nil then return defaults[key] end
    return fallback
end

local function ReadColor(color)
    if not color then return nil end
    if type(color.GetRGBA) == "function" then
        return color:GetRGBA()
    end
    if type(color) ~= "table" then return nil end
    return color.r or color[1] or 1,
           color.g or color[2] or 1,
           color.b or color[3] or 1,
           color.a or color[4] or 1
end

local function GetEffectiveColorValues(overrideColor)
    local color = overrideColor
    if not color and GetCfg("glowUseCustomColor", false) then
        color = GetCfg("glowColor", nil)
    end
    if not color then return false end
    local r, g, b, a = ReadColor(color)
    return true, r, g, b, a
end

local function RenderedColorMatches(host, overrideColor)
    local hasColor, r, g, b, a = GetEffectiveColorValues(overrideColor)
    if host.cdmUnifiedGlowHasColor ~= hasColor then return false end
    if not hasColor then return true end
    return host.cdmUnifiedGlowR == r
        and host.cdmUnifiedGlowG == g
        and host.cdmUnifiedGlowB == b
        and host.cdmUnifiedGlowA == a
end

local function StoreRenderedColor(host, overrideColor)
    local hasColor, r, g, b, a = GetEffectiveColorValues(overrideColor)
    host.cdmUnifiedGlowHasColor = hasColor
    host.cdmUnifiedGlowR = r
    host.cdmUnifiedGlowG = g
    host.cdmUnifiedGlowB = b
    host.cdmUnifiedGlowA = a
end

local function ToColorArray(color)
    if type(color) ~= "table" then return nil end
    local arr = colorArrays[color]
    if not arr then
        arr = { 1, 1, 1, 1 }
        colorArrays[color] = arr
    end
    local r, g, b, a = ReadColor(color)
    arr[1], arr[2], arr[3], arr[4] = r, g, b, a
    return arr
end

local function GetVisualColor(overrideColor)
    if overrideColor then return ToColorArray(overrideColor) end
    if GetCfg("glowUseCustomColor", false) then
        return ToColorArray(GetCfg("glowColor", nil))
    end
    return nil
end

local function StopProcAnimations(host)
    local f = host and host[PROC_GLOW_FIELD]
    if not f then return end
    if f.ProcStartAnim and f.ProcStartAnim:IsPlaying() then f.ProcStartAnim:Stop() end
    if f.ProcLoopAnim and f.ProcLoopAnim:IsPlaying() then f.ProcLoopAnim:Stop() end
end

local function HardStopButton(host)
    if not host or not host._ButtonGlow then return end

    -- LibCustomGlow owns the ButtonGlow pool. Calling pool:Release() here can
    -- race its own OnHide/animation cleanup and double-release the same frame.
    -- Use only the public stop API and let the library return the object.
    LCG.ButtonGlow_Stop(host)
end

local function HardStopHost(host)
    if not host then return end

    -- Stop library-owned objects before hiding their parent. In particular,
    -- ButtonGlow has an OnHide cleanup path that may release its pooled frame.
    LCG.PixelGlow_Stop(host, GLOW_KEY)
    LCG.AutoCastGlow_Stop(host, GLOW_KEY)
    HardStopButton(host)
    StopProcAnimations(host)
    LCG.ProcGlow_Stop(host, GLOW_KEY)
    host:Hide()
    host.cdmGlowActive = nil
    host.cdmGlowType = nil
    host.cdmGlowOverrideType = nil
    host.cdmGlowOverrideColor = nil
    host.cdmUnifiedGlowVersion = nil
    host.cdmUnifiedGlowHasColor = nil
    host.cdmUnifiedGlowR = nil
    host.cdmUnifiedGlowG = nil
    host.cdmUnifiedGlowB = nil
    host.cdmUnifiedGlowA = nil
end

local function StartOrUpdateHost(host, glowType, overrideColor)
    local color = GetVisualColor(overrideColor)
    if glowType == "pixel" then
        local length = GetCfg("glowPixelLength", 0)
        if length == 0 then length = nil end
        LCG.PixelGlow_Start(
            host, color,
            GetCfg("glowPixelLines", 8),
            GetCfg("glowPixelFrequency", 0.2),
            length,
            GetCfg("glowPixelThickness", 2),
            GetCfg("glowPixelXOffset", 0),
            GetCfg("glowPixelYOffset", 0),
            GetCfg("glowPixelBorder", false) and true or false,
            GLOW_KEY, 5
        )
    elseif glowType == "autocast" then
        LCG.AutoCastGlow_Start(
            host, color,
            GetCfg("glowAutocastParticles", 4),
            GetCfg("glowAutocastFrequency", 0.2),
            GetCfg("glowAutocastScale", 1),
            GetCfg("glowAutocastXOffset", 0),
            GetCfg("glowAutocastYOffset", 0),
            GLOW_KEY, 5
        )
    elseif glowType == "button" then
        local frequency = GetCfg("glowButtonFrequency", 0)
        if frequency == 0 then frequency = nil end
        LCG.ButtonGlow_Start(host, color, frequency, 5)
    else
        procOpts.color = color
        procOpts.duration = GetCfg("glowProcDuration", 1)
        procOpts.xOffset = GetCfg("glowProcXOffset", 0)
        procOpts.yOffset = GetCfg("glowProcYOffset", 0)
        LCG.ProcGlow_Start(host, procOpts)
    end
end

local function EnsureHost(frame)
    local host = frame.cdmBuffGlowHost
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host:SetClampedToScreen(false)
        host:EnableMouse(false)
        frame.cdmBuffGlowHost = host
        frame.cdmBuffGlowHostAnchorTarget = nil
        frame.cdmBuffGlowHostStrata = nil
        frame.cdmBuffGlowHostLevel = nil
    end
    return host
end

local function SyncHost(frame, host)
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

local function IsManagedCooldownFrame(frame)
    local viewer = frame.GetViewerFrame and frame:GetViewerFrame() or nil
    if viewer == _G[VIEWERS.ESSENTIAL] or viewer == _G[VIEWERS.UTILITY] then return true end
    local parent = frame:GetParent()
    while parent do
        local name = parent:GetName()
        if name == VIEWERS.ESSENTIAL or name == VIEWERS.UTILITY then return true end
        parent = parent:GetParent()
    end
    return false
end

local function ReadType(override)
    local glowType = override and override.glowTypeOverride
    return VALID_TYPES[glowType] and glowType or nil
end

local function ResolveGroupedType(frame)
    local sets = CDM.CooldownGroupSets
    if not sets or not sets.groups then return nil, false end
    local cooldownID = frame.cooldownID
    local match = cooldownID and sets.cooldownIDGrouped and sets.cooldownIDGrouped[cooldownID]
    local groupIdx = match and match.groupIdx
    if not groupIdx and CDM.CheckCdGroupMatch then groupIdx = CDM.CheckCdGroupMatch(frame) end
    if not groupIdx then return nil, false end
    local groupData = sets.groups[groupIdx]
    if not groupData or not CDM.GetCooldownGroupSpellOverride then return nil, true end

    local seen = {}
    local function Try(spellID)
        if not spellID or seen[spellID] then return nil end
        seen[spellID] = true
        return ReadType(CDM.GetCooldownGroupSpellOverride(groupData, spellID))
    end

    local glowType = match and Try(match.storedID)
    if not glowType then glowType = Try(frame.cdmCdGroupSpellID) end
    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
    if not glowType and info then
        glowType = Try(info.overrideTooltipSpellID) or Try(info.overrideSpellID) or Try(info.spellID)
    end
    if not glowType then glowType = Try(frame.cdmBuffCategorySpellID) end
    if not glowType and CDM.GetSpellIDCandidates then
        for _, spellID in ipairs(CDM:GetSpellIDCandidates(frame)) do
            glowType = Try(spellID)
            if glowType then break end
        end
    end
    return glowType, true
end

local function ResolveGlowType(frame)
    if IsManagedCooldownFrame(frame) then
        local groupedType, isGrouped = ResolveGroupedType(frame)
        if isGrouped then return groupedType or GetCfg("glowType", "proc") end
        if CDM.GetUngroupedCooldownOverride then
            local seen = {}
            local function Try(spellID)
                if not spellID or seen[spellID] then return nil end
                seen[spellID] = true
                return ReadType(CDM:GetUngroupedCooldownOverride(spellID))
            end
            local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
            local glowType
            if info then
                glowType = Try(info.overrideTooltipSpellID) or Try(info.overrideSpellID) or Try(info.spellID)
            end
            if not glowType and CDM.GetSpellIDCandidates then
                for _, spellID in ipairs(CDM:GetSpellIDCandidates(frame)) do
                    glowType = Try(spellID)
                    if glowType then break end
                end
            end
            if glowType then return glowType end
        end
    end
    local globalType = GetCfg("glowType", "proc")
    return VALID_TYPES[globalType] and globalType or "proc"
end

local function SourceMatches(sourceID, sourceBase, id)
    if not sourceID or not id then return false end
    if id == sourceID or id == sourceBase then return true end
    local base = CDM.NormalizeToBase and CDM.NormalizeToBase(id)
    return base == sourceID or base == sourceBase
end

local function SourceStillValid(frame, sourceID)
    if not sourceID then return true end
    if not CDM.GetCurrentSpecID or not CDM.GetSpellGlowEnabled then return true end
    local specID = CDM:GetCurrentSpecID()
    if not specID or not CDM:GetSpellGlowEnabled(specID, sourceID) then return false end
    local sourceBase = CDM.NormalizeToBase and CDM.NormalizeToBase(sourceID) or sourceID
    if SourceMatches(sourceID, sourceBase, frame.cdmBuffCategorySpellID) then return true end
    if CDM.GetSpellIDCandidates then
        for _, id in ipairs(CDM:GetSpellIDCandidates(frame)) do
            if SourceMatches(sourceID, sourceBase, id) then return true end
        end
    end
    return false
end

local function GetState(frame, create)
    local state = states[frame]
    if not state and create then
        state = { requests = {}, stopGeneration = 0, acquireGeneration = 0, boundCooldownID = frame.cooldownID }
        states[frame] = state
    end
    return state
end

local function SelectWinner(frame, state)
    for _, token in ipairs(PRODUCER_ORDER) do
        local request = state.requests[token]
        if request then
            if SourceStillValid(frame, request.sourceID) then return token, request end
            state.requests[token] = nil
        end
    end
end

local RefreshFrame

local function ClearCompat(frame)
    frame.cdmGlowProducer = nil
    frame.cdmBuffGlowWanted = nil
    frame.cdmBuffGlowOverrideColor = nil
    frame.cdmBuffGlowSourceID = nil
end

local function ResetPrimary(frame)
    states[frame] = nil
    ClearCompat(frame)
    local host = frame.cdmBuffGlowHost
    if host then HardStopHost(host) end
end

local function ResetAllPrimaryGlows()
    local count = 0
    for frame in pairs(states) do
        count = count + 1
        resetSnapshot[count] = frame
    end

    for i = 1, count do
        local frame = resetSnapshot[i]
        resetSnapshot[i] = nil
        if frame then
            ResetPrimary(frame)
        end
    end

    if CDM.ForEachActiveFrame then
        CDM:ForEachActiveFrame({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }, function(frame)
            ClearCompat(frame)
            local host = frame.cdmBuffGlowHost
            if host then
                HardStopHost(host)
            end
        end)
    end
end

local function StopAllPrimaryVisuals()
    local seen = setmetatable({}, { __mode = "k" })

    for frame in pairs(states) do
        seen[frame] = true
        local host = frame.cdmBuffGlowHost
        if host then
            HardStopHost(host)
        end
    end

    if CDM.ForEachActiveFrame then
        CDM:ForEachActiveFrame({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }, function(frame)
            if seen[frame] then return end
            local host = frame.cdmBuffGlowHost
            if host then
                HardStopHost(host)
            end
        end)
    end
end

local function IsPrimaryGlowSuspended()
    return specTransitionSuspended or layoutMutationSuspended
end

local function FinishLayoutMutation(generation)
    if not layoutMutationSuspended then return end
    if layoutMutationGeneration ~= generation then return end
    if specTransitionSuspended then return end

    -- Reapply our own layout while rendering is still suspended. This restores
    -- grouped/buff glow requests without exposing LibCustomGlow to intermediate
    -- frame geometry. ForceReanchorAll does not ask Blizzard to RefreshLayout.
    if CDM.ForceReanchorAll then
        CDM:ForceReanchorAll()
    end

    -- A nested acquire wins and starts a new settle window.
    if layoutMutationGeneration ~= generation then return end
    if specTransitionSuspended then return end

    layoutMutationSuspended = false

    -- Rebuild only glow state. Do not call CDM:Refresh() here: that can trigger
    -- another CooldownViewer layout rebuild and create a suspend/refresh loop.
    if CDM.GlowDirector and CDM.GlowDirector.RebuildIndex then
        CDM.GlowDirector:RebuildIndex()
    end

    for frame in pairs(states) do
        RefreshFrame(frame, false)
    end
end

local function ScheduleLayoutMutationFinish()
    local generation = layoutMutationGeneration
    C_Timer.After(LAYOUT_SETTLE_DELAY, function()
        FinishLayoutMutation(generation)
    end)
end

local function BeginLayoutMutation()
    layoutMutationGeneration = layoutMutationGeneration + 1

    if not layoutMutationSuspended then
        layoutMutationSuspended = true
        StopAllPrimaryVisuals()
    end

    ScheduleLayoutMutationFinish()
end

function Glow:BeginSpecTransition()
    specTransitionGeneration = specTransitionGeneration + 1
    specTransitionSuspended = true
    ResetAllPrimaryGlows()
end

function Glow:EndSpecTransition()
    if not specTransitionSuspended then return end

    -- Blizzard recycles/reparents cooldown frames while specialization data is
    -- rebuilding. Purge again before re-enabling requests so no transient host
    -- geometry survives into the settled specialization.
    ResetAllPrimaryGlows()

    local generation = specTransitionGeneration
    C_Timer.After(0, function()
        if not specTransitionSuspended then return end
        if specTransitionGeneration ~= generation then return end

        specTransitionSuspended = false
        if layoutMutationSuspended then
            layoutMutationGeneration = layoutMutationGeneration + 1
            ScheduleLayoutMutationFinish()
        end

        if CDM.Refresh then
            CDM:Refresh()
        elseif CDM.GlowDirector and CDM.GlowDirector.RebuildIndex then
            CDM.GlowDirector:RebuildIndex()
        end
    end)
end

local function ScheduleStop(frame, state)
    state.stopGeneration = state.stopGeneration + 1
    local generation = state.stopGeneration
    C_Timer.After(0, function()
        if states[frame] ~= state or state.stopGeneration ~= generation then return end
        if SelectWinner(frame, state) then return end
        ResetPrimary(frame)
    end)
end

local function ApplyVisual(frame, request, forceUpdate)
    local host = EnsureHost(frame)
    SyncHost(frame, host)
    local glowType = ResolveGlowType(frame)
    local version = Glow.visualConfigVersion or 0
    local sameVisual = host.cdmGlowActive == true
        and host.cdmGlowType == glowType
        and RenderedColorMatches(host, request.overrideColor)
        and host.cdmUnifiedGlowVersion == version

    if not sameVisual then
        if host.cdmGlowActive and host.cdmGlowType == glowType then
            StartOrUpdateHost(host, glowType, request.overrideColor)
        else
            HardStopHost(host)
            StartOrUpdateHost(host, glowType, request.overrideColor)
        end
        host.cdmGlowActive = true
        host.cdmGlowType = glowType
        host.cdmGlowOverrideType = glowType
        host.cdmGlowOverrideColor = request.overrideColor
        host.cdmUnifiedGlowVersion = version
        StoreRenderedColor(host, request.overrideColor)
    elseif forceUpdate then
        StartOrUpdateHost(host, glowType, request.overrideColor)
        StoreRenderedColor(host, request.overrideColor)
    end
    host:SetShown(frame:IsShown())
end

local function EnsureFrameHooks(frame)
    if hookedFrames[frame] then return end
    hookedFrames[frame] = true
    frame:HookScript("OnShow", function(self)
        if states[self] then RefreshFrame(self, false) end
    end)
    frame:HookScript("OnHide", function(self)
        local host = self.cdmBuffGlowHost
        if host then host:Hide() end
    end)
    frame:HookScript("OnSizeChanged", function(self)
        if states[self] then RefreshFrame(self, true) end
    end)
    if type(frame.SetCooldownID) == "function" then
        hooksecurefunc(frame, "SetCooldownID", function(self)
            local state = states[self]
            if state and state.boundCooldownID ~= nil and self.cooldownID ~= state.boundCooldownID then
                ResetPrimary(self)
            end
        end)
    end
    if type(frame.ClearCooldownID) == "function" then
        hooksecurefunc(frame, "ClearCooldownID", function(self)
            if states[self] then ResetPrimary(self) end
        end)
    end
end

RefreshFrame = function(frame, forceUpdate)
    local state = states[frame]
    if not state then return end
    local token, request = SelectWinner(frame, state)
    if not token then
        ClearCompat(frame)
        ScheduleStop(frame, state)
        return
    end
    state.stopGeneration = state.stopGeneration + 1
    frame.cdmGlowProducer = token
    frame.cdmBuffGlowWanted = true
    frame.cdmBuffGlowOverrideColor = request.overrideColor
    frame.cdmBuffGlowSourceID = request.sourceID
    EnsureFrameHooks(frame)

    if IsPrimaryGlowSuspended() then
        local host = frame.cdmBuffGlowHost
        if host then
            HardStopHost(host)
        end
        return
    end

    ApplyVisual(frame, request, forceUpdate == true)
end

Glow.RequestBuffGlow = function(self, frame, producerToken, enabled, overrideColor, sourceID)
    if not frame or not VALID_PRODUCERS[producerToken] then return end
    if specTransitionSuspended then
        ClearCompat(frame)
        local host = frame.cdmBuffGlowHost
        if host then HardStopHost(host) end
        states[frame] = nil
        return
    end
    local state = GetState(frame, false)
    if state and state.boundCooldownID ~= nil and frame.cooldownID ~= nil and state.boundCooldownID ~= frame.cooldownID then
        ResetPrimary(frame)
        state = nil
    end
    if not state and enabled then state = GetState(frame, true) end
    if not state then return end
    if enabled then
        if frame.cooldownID ~= nil then state.boundCooldownID = frame.cooldownID end
        local request = state.requests[producerToken] or {}
        state.requests[producerToken] = request
        request.overrideColor = overrideColor
        request.sourceID = sourceID
    else
        state.requests[producerToken] = nil
    end
    RefreshFrame(frame, false)
end

Glow.StopGlow = function(self, frame)
    if not frame then return end
    ResetPrimary(frame)
    if self.HidePandemicGlow then self:HidePandemicGlow(frame) end
end

Glow.InstallAcquireResetHook = function(self, viewer)
    hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
        -- Any CooldownViewer acquire means Blizzard is rebuilding layout or
        -- identity. Suspend all primary glow rendering until acquires go quiet.
        BeginLayoutMutation()

        local state = states[itemFrame]
        if not state then
            ClearCompat(itemFrame)
            local host = itemFrame.cdmBuffGlowHost
            if host then
                HardStopHost(host)
            end
        else
            -- Preserve logical requests if Blizzard reacquires the same cooldown,
            -- but never redraw here. If identity changes, discard the old state.
            state.acquireGeneration = state.acquireGeneration + 1
            local generation = state.acquireGeneration
            local oldCooldownID = state.boundCooldownID
            C_Timer.After(0, function()
                if states[itemFrame] ~= state then return end
                if state.acquireGeneration ~= generation then return end
                if oldCooldownID ~= nil and itemFrame.cooldownID ~= oldCooldownID then
                    ResetPrimary(itemFrame)
                end
            end)
        end

        if self.HidePandemicGlow then
            self:HidePandemicGlow(itemFrame)
        end
    end)
end

Glow.RefreshActiveGlows = function(self, forceUpdate)
    if IsPrimaryGlowSuspended() then return end
    local version = self.visualConfigVersion or 0
    local configChanged = version ~= lastVisualConfigVersion
    lastVisualConfigVersion = version
    for frame in pairs(states) do
        RefreshFrame(frame, forceUpdate == true or configChanged)
    end
    if configChanged and type(originalRefreshActiveGlows) == "function" then
        originalRefreshActiveGlows(self)
    end
end

Glow.RefreshSpellGlowTypeOverrides = function(self)
    if IsPrimaryGlowSuspended() then return end
    for frame in pairs(states) do RefreshFrame(frame, false) end
end

CDM:RegisterRefreshCallback("unifiedGlowController", function()
    Glow:RefreshSpellGlowTypeOverrides()
end, 55, { "STYLE", "CD_DATA" })
