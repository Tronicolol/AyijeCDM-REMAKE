local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Glow then return end

local Glow = CDM.Glow
local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
if not VIEWERS then return end

if Glow.cdmFrameLifecycleGuardInstalled then return end
Glow.cdmFrameLifecycleGuardInstalled = true

local originalRequestBuffGlow = Glow.RequestBuffGlow
local originalInstallAcquireResetHook = Glow.InstallAcquireResetHook
if type(originalRequestBuffGlow) ~= "function" or type(originalInstallAcquireResetHook) ~= "function" then return end

local refreshGeneration = setmetatable({}, { __mode = "k" })

local function CancelQueuedRefresh(frame)
    refreshGeneration[frame] = (refreshGeneration[frame] or 0) + 1
end

local function QueueSettledRefresh(frame, expectedCooldownID)
    local generation = (refreshGeneration[frame] or 0) + 1
    refreshGeneration[frame] = generation

    C_Timer.After(0, function()
        if refreshGeneration[frame] ~= generation then return end
        if frame.cooldownID ~= expectedCooldownID then return end
        if not frame:IsShown() then return end
        if not CDM.RefreshFrameVisuals then return end

        CDM:RefreshFrameVisuals(frame)
    end)
end

local function ResetForCurrentBinding(frame, queueRefresh)
    if not frame then return end

    local cooldownID = frame.cooldownID
    CancelQueuedRefresh(frame)
    Glow:StopGlow(frame)

    frame.cdmGlowLifecycleBindingInitialized = true
    frame.cdmGlowLifecycleBoundCooldownID = cooldownID

    if queueRefresh and cooldownID then
        QueueSettledRefresh(frame, cooldownID)
    end
end

local function ValidateBinding(frame, queueRefresh)
    if not frame then return false end

    local cooldownID = frame.cooldownID
    if not frame.cdmGlowLifecycleBindingInitialized then
        frame.cdmGlowLifecycleBindingInitialized = true
        frame.cdmGlowLifecycleBoundCooldownID = cooldownID
        return false
    end

    if frame.cdmGlowLifecycleBoundCooldownID == cooldownID then
        return false
    end

    ResetForCurrentBinding(frame, queueRefresh)
    return true
end

local function EnsureFrameLifecycleHooks(frame)
    if not frame or frame.cdmGlowFrameLifecycleHooked then return end
    frame.cdmGlowFrameLifecycleHooked = true

    hooksecurefunc(frame, "SetCooldownID", function(self)
        ValidateBinding(self, true)
    end)

    hooksecurefunc(frame, "ClearCooldownID", function(self)
        ValidateBinding(self, false)
    end)

    frame:HookScript("OnShow", function(self)
        ValidateBinding(self, true)
    end)
end

Glow.RequestBuffGlow = function(self, frame, producerToken, enabled, overrideColor, sourceID)
    if frame then
        EnsureFrameLifecycleHooks(frame)
        ValidateBinding(frame, false)
    end

    return originalRequestBuffGlow(self, frame, producerToken, enabled, overrideColor, sourceID)
end

Glow.InstallAcquireResetHook = function(self, viewer)
    originalInstallAcquireResetHook(self, viewer)

    hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
        EnsureFrameLifecycleHooks(itemFrame)
        CancelQueuedRefresh(itemFrame)
        itemFrame.cdmGlowLifecycleBindingInitialized = true
        itemFrame.cdmGlowLifecycleBoundCooldownID = itemFrame.cooldownID
    end)
end
