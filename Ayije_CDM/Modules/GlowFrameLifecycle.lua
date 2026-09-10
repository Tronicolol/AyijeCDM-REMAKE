local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Glow then return end

local Glow = CDM.Glow
local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
local IsSafeNumber = CDM.IsSafeNumber
if not VIEWERS or type(IsSafeNumber) ~= "function" then return end

if Glow.cdmFrameLifecycleGuardInstalled then return end
Glow.cdmFrameLifecycleGuardInstalled = true

local originalRequestBuffGlow = Glow.RequestBuffGlow
local originalInstallAcquireResetHook = Glow.InstallAcquireResetHook
if type(originalRequestBuffGlow) ~= "function" or type(originalInstallAcquireResetHook) ~= "function" then return end

local bindings = setmetatable({}, { __mode = "k" })
local viewerHooks = setmetatable({}, { __mode = "k" })

local mappingRefreshFrame = CreateFrame("Frame")
local mappingRefreshPending = false
local mappingSettleFrames = 0
mappingRefreshFrame:Hide()

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

local function SafeID(value)
    if IsSafeNumber(value) then
        return value
    end
    return nil
end

local function ReadCooldownInfo(frame)
    if not frame then return nil end
    if frame.GetCooldownInfo then
        return frame:GetCooldownInfo()
    end
    return frame.cooldownInfo
end

local function ReadLiveSpellID(frame)
    if not frame or type(frame.GetSpellID) ~= "function" then return nil end

    local ok, value = pcall(frame.GetSpellID, frame)
    if not ok then return nil end
    return SafeID(value)
end

local function ReadBinding(frame)
    local info = ReadCooldownInfo(frame)

    return {
        cooldownID = SafeID(frame and frame.cooldownID),
        liveSpellID = ReadLiveSpellID(frame),
        tooltipSpellID = SafeID(info and info.overrideTooltipSpellID),
        overrideSpellID = SafeID(info and info.overrideSpellID),
        baseSpellID = SafeID(info and info.spellID),
    }
end

local function BindingsMatch(left, right)
    if not left or not right then return false end

    return left.cooldownID == right.cooldownID
        and left.liveSpellID == right.liveSpellID
        and left.tooltipSpellID == right.tooltipSpellID
        and left.overrideSpellID == right.overrideSpellID
        and left.baseSpellID == right.baseSpellID
end

local function StoreBinding(frame, binding)
    bindings[frame] = binding or ReadBinding(frame)

    local current = bindings[frame]
    frame.cdmGlowLifecycleBindingInitialized = true
    frame.cdmGlowLifecycleBoundCooldownID = current and current.cooldownID or nil
end

local function ClearFrameMatchCaches(frame)
    if not frame then return end

    frame.cdmBuffCategorySpellID = nil
    frame.cdmBarGroupSpellID = nil
    frame.cdmCdGroupSpellID = nil
    frame.cdmCategoryCacheGen = nil
end

local function QueueMappingRefresh()
    mappingRefreshPending = true
    mappingSettleFrames = 2
    mappingRefreshFrame:Show()
end

local function ResetForBinding(frame, binding, queueRefresh)
    if not frame then return end

    Glow:StopGlow(frame)
    ClearFrameMatchCaches(frame)
    StoreBinding(frame, binding)

    if queueRefresh then
        QueueMappingRefresh()
    end
end

local function ValidateBinding(frame, queueRefresh)
    if not IsManagedCooldownFrame(frame) then return false end

    local current = ReadBinding(frame)
    local previous = bindings[frame]

    if not previous then
        StoreBinding(frame, current)
        return false
    end

    if BindingsMatch(previous, current) then
        return false
    end

    ResetForBinding(frame, current, queueRefresh)
    return true
end

local function ValidateAllActiveBindings()
    if not CDM.ForEachActiveFrame then return false end

    local changed = false
    CDM:ForEachActiveFrame({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }, function(frame)
        if ValidateBinding(frame, false) then
            changed = true
        end
    end)
    return changed
end

mappingRefreshFrame:SetScript("OnUpdate", function(self)
    if not mappingRefreshPending then
        self:Hide()
        return
    end

    if mappingSettleFrames > 0 then
        mappingSettleFrames = mappingSettleFrames - 1
        return
    end

    if CDM.loginFinished ~= true then
        mappingRefreshPending = false
        self:Hide()
        return
    end

    if CDM.IsCooldownViewerDataReady and not CDM:IsCooldownViewerDataReady() then
        mappingSettleFrames = 2
        return
    end

    mappingRefreshPending = false
    self:Hide()

    ValidateAllActiveBindings()

    if CDM.MarkSpecDataDirty then
        CDM:MarkSpecDataDirty()
    end
    if CDM.RefreshSpecData then
        CDM:RefreshSpecData()
    end
end)

local function EnsureFrameLifecycleHooks(frame)
    if not IsManagedCooldownFrame(frame) or frame.cdmGlowFrameLifecycleHooked then return end
    frame.cdmGlowFrameLifecycleHooked = true

    if type(frame.SetCooldownID) == "function" then
        hooksecurefunc(frame, "SetCooldownID", function(self)
            ValidateBinding(self, true)
        end)
    end

    if type(frame.ClearCooldownID) == "function" then
        hooksecurefunc(frame, "ClearCooldownID", function(self)
            ValidateBinding(self, true)
        end)
    end

    if type(frame.SetOverrideSpell) == "function" then
        hooksecurefunc(frame, "SetOverrideSpell", function(self)
            ValidateBinding(self, true)
        end)
    end

    frame:HookScript("OnShow", function(self)
        ValidateBinding(self, true)
    end)
end

local function EnsureViewerLifecycleHooks(viewer)
    if not viewer or viewerHooks[viewer] then return end

    local name = viewer:GetName()
    if name ~= VIEWERS.ESSENTIAL and name ~= VIEWERS.UTILITY then return end

    viewerHooks[viewer] = true

    hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
        if not IsManagedCooldownFrame(itemFrame) then return end

        EnsureFrameLifecycleHooks(itemFrame)
        ClearFrameMatchCaches(itemFrame)
        StoreBinding(itemFrame)

        if CDM.loginFinished == true then
            QueueMappingRefresh()
        end
    end)

    if type(viewer.RefreshLayout) == "function" then
        hooksecurefunc(viewer, "RefreshLayout", function()
            if ValidateAllActiveBindings() then
                QueueMappingRefresh()
            end
        end)
    end
end

Glow.RequestBuffGlow = function(self, frame, producerToken, enabled, overrideColor, sourceID)
    if IsManagedCooldownFrame(frame) then
        EnsureFrameLifecycleHooks(frame)

        if ValidateBinding(frame, true) then
            -- This request was calculated for the frame's previous binding.
            -- The settled mapping refresh will recompute the correct state.
            return
        end
    end

    return originalRequestBuffGlow(self, frame, producerToken, enabled, overrideColor, sourceID)
end

Glow.InstallAcquireResetHook = function(self, viewer)
    originalInstallAcquireResetHook(self, viewer)
    EnsureViewerLifecycleHooks(viewer)
end
