local AddonName = "KCDM"
local CDM = _G[AddonName]
local CDM_C = CDM.CONST

local RealCooldownOverlay = {}
CDM.RealCooldownOverlay = RealCooldownOverlay

local VIEWERS = CDM_C.VIEWERS
local GetSpellCooldownDuration = C_Spell.GetSpellCooldownDuration
local GetSpellCharges = C_Spell.GetSpellCharges
local IsSafeNumber = CDM.IsSafeNumber
local After = C_Timer.After

local managedViewers = { VIEWERS.ESSENTIAL, VIEWERS.UTILITY }

local function GetCastSpellID(frame)
    if CDM.GetCastSpellID then
        return CDM.GetCastSpellID(frame)
    end

    local info = frame and frame.cooldownInfo
    if not info then return nil end

    local spellID = info.overrideSpellID or info.spellID
    return IsSafeNumber(spellID) and spellID or nil
end

local function IsMultiChargeSpell(spellID)
    if not spellID then return false end

    local chargeInfo = GetSpellCharges(spellID)
    if not chargeInfo then return false end

    local maxCharges = chargeInfo.maxCharges
    return IsSafeNumber(maxCharges) and maxCharges > 1
end

local function IsAuraOverlayManaged(frame)
    if not frame then return false end

    if frame.cooldownUseAuraDisplayTime == true then
        return true
    end

    local map = CDM._auraOverlayEnabled
    local cooldownID = frame.cooldownID
    return map and cooldownID and map[cooldownID] ~= nil or false
end

local function ShouldUseBlizzardCooldown(frame, spellID)
    if not frame or not spellID then return true end

    if frame.HasEditModeData and frame:HasEditModeData() then
        return true
    end

    if frame.IsItem and frame:IsItem() then
        return true
    end

    if IsAuraOverlayManaged(frame) then
        return true
    end

    if IsMultiChargeSpell(spellID) then
        return true
    end

    return false
end

local function FindFirstFontString(frame)
    if not frame then return nil end

    if frame.Text and frame.Text.IsObjectType and frame.Text:IsObjectType("FontString") then
        return frame.Text
    end
    if frame.text and frame.text.IsObjectType and frame.text:IsObjectType("FontString") then
        return frame.text
    end

    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("FontString") then
            return region
        end
    end

    return nil
end

local function CopyCountdownTextStyle(sourceCooldown, targetCooldown)
    local sourceText = FindFirstFontString(sourceCooldown)
    local targetText = FindFirstFontString(targetCooldown)
    if not sourceText or not targetText then return end

    local fontPath, fontSize, fontFlags = sourceText:GetFont()
    if fontPath and fontSize then
        targetText:SetFont(fontPath, fontSize, fontFlags)
    end

    local r, g, b, a = sourceText:GetTextColor()
    targetText:SetTextColor(r, g, b, a)
    targetText:SetIgnoreParentScale(true)
    targetText:ClearAllPoints()
    targetText:SetPoint("CENTER", targetCooldown, "CENTER", 0, 0)
    targetText:SetJustifyH("CENTER")
    targetText:SetJustifyV("MIDDLE")
    targetText:SetShadowOffset(0, 0)
end

local function ApplyOverlayStyle(frame, overlay)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame.Cooldown:GetFrameLevel())
    overlay:SetReverse(false)
    overlay:SetDrawEdge(false)
    overlay:SetUseAuraDisplayTime(false)
    overlay:SetDrawSwipe(true)
    overlay:SetHideCountdownNumbers(false)
    overlay:SetAlpha(1)

    if overlay.SetCountdownFont then
        overlay:SetCountdownFont("KCDM_CDFont")
    end
    if overlay.SetCountdownFormatter and CDM.CooldownFormatter then
        overlay:SetCountdownFormatter(CDM.CooldownFormatter.Get())
    end

    local styleCache = CDM.styleCache or {}
    local swipeColor = styleCache.swipeColor or CDM_C.SWIPE_COLOR
    overlay:SetSwipeColor(swipeColor.r, swipeColor.g, swipeColor.b, swipeColor.a or 1)

    if styleCache.zoomIcons then
        overlay:SetSwipeTexture(CDM_C.TEX_WHITE8X8)
    else
        overlay:SetSwipeTexture(DEFAULT_COOLDOWN_ICON_SWIPE_TEXTURE)
    end
end

local function RestoreBlizzardCooldown(frame)
    if not frame or not frame.Cooldown then return end

    if frame.cdmRealCooldownBlizzardAlpha ~= nil then
        frame.Cooldown:SetAlpha(frame.cdmRealCooldownBlizzardAlpha)
        frame.cdmRealCooldownBlizzardAlpha = nil
    end

    frame.cdmRealCooldownOverlayActive = nil
end

local function HideOverlay(frame)
    if not frame then return end

    local overlay = frame.cdmRealCooldownOverlay
    if overlay then
        overlay:Hide()
    end

    RestoreBlizzardCooldown(frame)
end

local function EnsureOverlay(frame)
    local overlay = frame.cdmRealCooldownOverlay
    if overlay then return overlay end

    overlay = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame.Cooldown:GetFrameLevel())
    overlay:EnableMouse(false)
    overlay:Hide()
    frame.cdmRealCooldownOverlay = overlay

    overlay:HookScript("OnCooldownDone", function()
        -- The overlay's own DurationObject is authoritative. When it naturally
        -- expires, the spell is ready; do not immediately re-query during a GCD.
        HideOverlay(frame)
    end)

    return overlay
end

function RealCooldownOverlay:RefreshFrame(frame, deferNilHide)
    if not frame or not frame.Cooldown then return false end

    local spellID = GetCastSpellID(frame)
    if ShouldUseBlizzardCooldown(frame, spellID) then
        HideOverlay(frame)
        return false
    end

    -- 12.0.5+ API: ignoreGCD=true returns the spell's own active cooldown
    -- DurationObject without replacing it with the current global cooldown.
    -- We never inspect secret remaining-time values; the Cooldown widget
    -- consumes the DurationObject directly.
    local durationObject = GetSpellCooldownDuration(spellID, true)
    if not durationObject then
        -- SPELL_UPDATE_COOLDOWN can be observed while the client is still
        -- settling the spell-specific state. Keep the current overlay for the
        -- first probe and only clear it on the confirmation probe.
        if not deferNilHide then
            HideOverlay(frame)
        end
        return false
    end

    local overlay = EnsureOverlay(frame)
    ApplyOverlayStyle(frame, overlay)
    overlay:SetCooldownFromDurationObject(durationObject)
    CopyCountdownTextStyle(frame.Cooldown, overlay)

    if not frame.cdmRealCooldownOverlayActive then
        frame.cdmRealCooldownBlizzardAlpha = frame.Cooldown:GetAlpha()
    end

    frame.Cooldown:SetAlpha(0)
    frame.cdmRealCooldownOverlayActive = true
    overlay:Show()
    return true
end

local function EventMatchesFrameSpell(frame, spellID, baseSpellID)
    -- A nil spellID means Blizzard requested a full cooldown refresh.
    if spellID == nil then
        return true
    end

    local castSpellID = GetCastSpellID(frame)
    local frameBaseSpellID = CDM.GetBaseSpellID and CDM.GetBaseSpellID(frame) or nil

    if IsSafeNumber(spellID) then
        if spellID == castSpellID or spellID == frameBaseSpellID then
            return true
        end
    end

    if IsSafeNumber(baseSpellID) then
        if baseSpellID == castSpellID or baseSpellID == frameBaseSpellID then
            return true
        end
    end

    return false
end

function RealCooldownOverlay:ScheduleAuthoritativeRefresh(frame)
    if not frame then return end

    frame.cdmRealCooldownRefreshToken = (frame.cdmRealCooldownRefreshToken or 0) + 1
    local token = frame.cdmRealCooldownRefreshToken

    -- First probe: update immediately if the new real cooldown is already
    -- available, but never clear an existing overlay from a transient nil.
    After(0, function()
        if not frame or frame.cdmRealCooldownRefreshToken ~= token then return end
        RealCooldownOverlay:RefreshFrame(frame, true)
    end)

    -- Confirmation probe: by this point the spell-specific update has settled.
    -- A nil here is authoritative (proc/reset/ready), so the overlay is cleared.
    After(0.06, function()
        if not frame or frame.cdmRealCooldownRefreshToken ~= token then return end
        RealCooldownOverlay:RefreshFrame(frame, false)
    end)
end

function RealCooldownOverlay:ResetFrame(frame)
    if not frame then return end
    HideOverlay(frame)
end

function RealCooldownOverlay:AttachFrame(frame)
    if not frame or frame.cdmRealCooldownOverlayHooked then return end
    frame.cdmRealCooldownOverlayHooked = true

    -- This is the key distinction from V1: Blizzard calls this method for every
    -- cooldown event and tells the item whether the event belongs to its spell
    -- or is merely another spell starting the global cooldown. We only re-query
    -- the real cooldown for spell-specific/full updates. Unrelated GCD events are
    -- deliberately ignored so they cannot erase a still-running real cooldown.
    if frame.OnSpellUpdateCooldownEvent then
        hooksecurefunc(frame, "OnSpellUpdateCooldownEvent", function(self, spellID, baseSpellID)
            if EventMatchesFrameSpell(self, spellID, baseSpellID) then
                RealCooldownOverlay:ScheduleAuthoritativeRefresh(self)
            end
        end)
    end

    if frame.SetCooldownID then
        hooksecurefunc(frame, "SetCooldownID", function(self)
            RealCooldownOverlay:ScheduleAuthoritativeRefresh(self)
        end)
    end

    if frame.ClearCooldownID then
        hooksecurefunc(frame, "ClearCooldownID", function(self)
            self.cdmRealCooldownRefreshToken = (self.cdmRealCooldownRefreshToken or 0) + 1
            RealCooldownOverlay:ResetFrame(self)
        end)
    end

    if frame.SetOverrideSpell then
        hooksecurefunc(frame, "SetOverrideSpell", function(self)
            RealCooldownOverlay:ScheduleAuthoritativeRefresh(self)
        end)
    end
end

function RealCooldownOverlay:InstallAcquireResetHook(viewer)
    if not viewer or viewer.cdmRealCooldownOverlayAcquireHooked then return end
    viewer.cdmRealCooldownOverlayAcquireHooked = true

    hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
        RealCooldownOverlay:AttachFrame(itemFrame)
        RealCooldownOverlay:ResetFrame(itemFrame)
        RealCooldownOverlay:ScheduleAuthoritativeRefresh(itemFrame)
    end)
end

function RealCooldownOverlay:RefreshAll()
    CDM:ForEachActiveFrame(managedViewers, function(frame)
        RealCooldownOverlay:AttachFrame(frame)
        RealCooldownOverlay:ScheduleAuthoritativeRefresh(frame)
    end)
end

function RealCooldownOverlay:Initialize()
    if self.initialized then return end
    self.initialized = true

    CDM:RegisterRefreshCallback("realCooldownOverlay", function()
        RealCooldownOverlay:RefreshAll()
    end, 46, { "STYLE", "CD_DATA" })

    self:RefreshAll()
end
