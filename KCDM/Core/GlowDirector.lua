local AddonName = "KCDM"
local CDM = _G[AddonName]

local IsSafeNumber = CDM.IsSafeNumber
local CDM_C = CDM.CONST
local VIEWERS = CDM_C.VIEWERS

local pairs = pairs
local next = next

CDM.GlowDirector = CDM.GlowDirector or {}
local GlowDirector = CDM.GlowDirector

local OWNER_KEY = "GlowDirector"

local framesByCdID = {}
local spellIDByCdID = {}
local cdIDsBySpellID = {}

local GetSpellCharges = C_Spell.GetSpellCharges
local C_Spell_GetSpellCooldown = C_Spell.GetSpellCooldown
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local C_Timer_After = C_Timer.After

local resourceAwareEventFrame = CreateFrame("Frame")
resourceAwareEventFrame:Hide()
local resourceAwareCdIDs = {}
local resourceAwareCount = 0
local resourceAwareRefreshPending = false

local FanoutToFrames
local QueueResourceAwareRefresh
local OnSpellEvent

local function RefreshResourceAwareEventRegistration()
    if resourceAwareCount > 0 then
        resourceAwareEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        resourceAwareEventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
        resourceAwareEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    else
        resourceAwareEventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        resourceAwareEventFrame:UnregisterEvent("SPELL_UPDATE_USABLE")
        resourceAwareEventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
    end
end

local function RegisterResourceAwareCdID(cdID)
    if resourceAwareCdIDs[cdID] then return end
    resourceAwareCdIDs[cdID] = true
    resourceAwareCount = resourceAwareCount + 1
    if resourceAwareCount == 1 then
        RefreshResourceAwareEventRegistration()
    end
end

local function UnregisterResourceAwareCdID(cdID)
    if not resourceAwareCdIDs[cdID] then return end
    resourceAwareCdIDs[cdID] = nil
    resourceAwareCount = resourceAwareCount - 1
    if resourceAwareCount <= 0 then
        resourceAwareCount = 0
        RefreshResourceAwareEventRegistration()
    end
end

local function HasChargeSource(frame)
    return frame.HasVisualDataSource_Charges and frame:HasVisualDataSource_Charges() or false
end

local function ComputeCooldownReady(frame, spellID)
    local ci = GetSpellCharges(spellID)
    if ci and ci.maxCharges and ci.maxCharges > 1 then
        if not ci.isActive then return true end
        return HasChargeSource(frame)
    end

    local info = C_Spell_GetSpellCooldown(spellID)
    if not info then return false end
    return (not info.isActive) or info.isOnGCD
end

local function ComputeFrameReady(frame, spellID, entry)
    if not ComputeCooldownReady(frame, spellID) then return false end
    if entry and entry.readyGlowResourceAware then
        return C_Spell_IsSpellUsable(spellID) == true
    end
    return true
end

FanoutToFrames = function(cdID)
    local frames = framesByCdID[cdID]
    if not frames then return end
    local sync = CDM.SyncReadyGlowForFrame
    if not sync then return end
    local map = CDM._auraOverlayEnabled
    local entry = map and map[cdID] or nil
    local spellID = spellIDByCdID[cdID]
    for frame in pairs(frames) do
        if frame.cdmGlowDirectorCdID == cdID and frame.cooldownID == cdID then
            sync(frame, entry, spellID, ComputeFrameReady(frame, spellID, entry))
        end
    end
end

local function RequestFanout(cdID)
    if resourceAwareCdIDs[cdID] then
        QueueResourceAwareRefresh()
    else
        FanoutToFrames(cdID)
    end
end

local function WireCooldownDone(frame)
    if frame.cdmReadyGlowCooldownDoneHooked then return end

    local cooldown = frame.cd or frame.Cooldown
    if not cooldown or not cooldown.HookScript then return end

    frame.cdmReadyGlowCooldownDoneHooked = true
    cooldown:HookScript("OnCooldownDone", function()
        C_Timer_After(0, function()
            local cdID = frame.cdmGlowDirectorCdID
            if cdID and frame.cooldownID == cdID then
                RequestFanout(cdID)
            end
        end)
    end)
end

QueueResourceAwareRefresh = function()
    if resourceAwareRefreshPending or resourceAwareCount == 0 then return end
    resourceAwareRefreshPending = true
    resourceAwareEventFrame:Show()
end

resourceAwareEventFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    resourceAwareRefreshPending = false
    for cdID in pairs(resourceAwareCdIDs) do
        FanoutToFrames(cdID)
    end
end)

resourceAwareEventFrame:SetScript("OnEvent", function()
    QueueResourceAwareRefresh()
end)

OnSpellEvent = function(spellID, cooldownsChanged, chargesChanged)
    if not (cooldownsChanged or chargesChanged) then return end
    local cdIDs = cdIDsBySpellID[spellID]
    if not cdIDs then return end
    for cdID in pairs(cdIDs) do
        RequestFanout(cdID)
    end
end

local function WatchCdIDForSpell(cdID, spellID)
    spellIDByCdID[cdID] = spellID
    local set = cdIDsBySpellID[spellID]
    if not set then
        set = {}
        cdIDsBySpellID[spellID] = set
        if CDM.WatchSpell then
            CDM.WatchSpell(OWNER_KEY, spellID, OnSpellEvent)
        end
    end
    set[cdID] = true

    local map = CDM._auraOverlayEnabled
    local entry = map and map[cdID] or nil
    if entry and entry.readyGlowResourceAware then
        RegisterResourceAwareCdID(cdID)
    end
end

local function UnwatchCdIDFromSpell(cdID)
    local spellID = spellIDByCdID[cdID]
    if not spellID then return end
    spellIDByCdID[cdID] = nil
    local set = cdIDsBySpellID[spellID]
    if set then
        set[cdID] = nil
        if not next(set) then
            cdIDsBySpellID[spellID] = nil
            if CDM.UnwatchSpell then
                CDM.UnwatchSpell(OWNER_KEY, spellID)
            end
        end
    end
end

local function UnregisterCdID(cdID)
    framesByCdID[cdID] = nil
    UnregisterResourceAwareCdID(cdID)
    UnwatchCdIDFromSpell(cdID)
end

local function RemoveFrameFromCdID(frame, cdID)
    local set = framesByCdID[cdID]
    if not set then return end
    set[frame] = nil
    if not next(set) then
        UnregisterCdID(cdID)
    end
end

function GlowDirector:OnCooldownIDSet(frame)
    if not frame then return end
    local oldCdID = frame.cdmGlowDirectorCdID
    if oldCdID then
        RemoveFrameFromCdID(frame, oldCdID)
        frame.cdmGlowDirectorCdID = nil
    end

    local cdID = frame.cooldownID
    if not cdID then return end
    local readySet = CDM._readyGlowCooldownIDs
    if not readySet or not readySet[cdID] then return end

    local info = frame.cooldownInfo
    local spellID = info and (info.overrideSpellID or info.spellID)
    if not IsSafeNumber(spellID) then return end

    local set = framesByCdID[cdID]
    if not set then
        set = {}
        framesByCdID[cdID] = set
        WatchCdIDForSpell(cdID, spellID)
    end
    set[frame] = true
    frame.cdmGlowDirectorCdID = cdID

    WireCooldownDone(frame)
    RequestFanout(cdID)
end

function GlowDirector:OnCooldownIDCleared(frame)
    if not frame then return end
    local cdID = frame.cdmGlowDirectorCdID
    if not cdID then return end
    RemoveFrameFromCdID(frame, cdID)
    frame.cdmGlowDirectorCdID = nil
end

function GlowDirector:InstallAcquireResetHook(v)
    hooksecurefunc(v, "OnAcquireItemFrame", function(_, itemFrame)
        -- Keep the previous registration until SetCooldownID/ClearCooldownID can remove it.
        -- Clearing it here leaves recycled frames registered under an old cooldownID.
        if itemFrame.cdmGlowLifecycleHooked then return end
        itemFrame.cdmGlowLifecycleHooked = true

        hooksecurefunc(itemFrame, "SetCooldownID", function(self)
            if self.cooldownID == self.cdmGlowDirectorCdID then return end
            GlowDirector:OnCooldownIDSet(self)
        end)

        hooksecurefunc(itemFrame, "ClearCooldownID", function(self)
            GlowDirector:OnCooldownIDCleared(self)
        end)

        hooksecurefunc(itemFrame, "SetOverrideSpell", function(self)
            if not self.cdmGlowDirectorCdID then return end
            GlowDirector:OnCooldownIDSet(self)
        end)
    end)
end

function GlowDirector:RefreshFrame(frame)
    if not frame then return end
    local sync = CDM.SyncReadyGlowForFrame
    if not sync then return end

    local cdID = frame.cooldownID
    local map = CDM._auraOverlayEnabled
    local entry = map and map[cdID] or nil

    local readySet = CDM._readyGlowCooldownIDs
    local registered = cdID and framesByCdID[cdID] and framesByCdID[cdID][frame]
    if not registered or not readySet or not readySet[cdID] then
        sync(frame, entry, nil, false)
        return
    end

    local spellID = spellIDByCdID[cdID]
    if resourceAwareCdIDs[cdID] then
        QueueResourceAwareRefresh()
        return
    end
    sync(frame, entry, spellID, ComputeFrameReady(frame, spellID, entry))
end

function GlowDirector:RebuildIndex()
    wipe(framesByCdID)
    wipe(spellIDByCdID)
    wipe(cdIDsBySpellID)
    wipe(resourceAwareCdIDs)
    resourceAwareCount = 0
    resourceAwareRefreshPending = false
    resourceAwareEventFrame:Hide()
    RefreshResourceAwareEventRegistration()
    if CDM.UnwatchAllSpells then
        CDM.UnwatchAllSpells(OWNER_KEY)
    end

    if not VIEWERS then return end
    CDM:ForEachActiveFrame({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }, function(frame)
        self:OnCooldownIDSet(frame)
        CDM:RefreshFrameVisuals(frame)
    end)
end
