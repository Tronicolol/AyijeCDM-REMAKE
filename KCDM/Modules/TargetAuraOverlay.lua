local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local CDM_C = CDM.CONST
local VIEWERS = CDM_C and CDM_C.VIEWERS
if not VIEWERS then return end

-- Cooldown spell -> real target aura spell.
-- Rend's cast/cooldown spell is 772, while the debuff applied to the target is 388539.
local TARGET_AURA_BY_SPELL = {
    [772] = 388539,
}

local TRACKED_VIEWERS = { VIEWERS.ESSENTIAL, VIEWERS.UTILITY }
local SLOT_KEY = "KCDMTargetAuraOverlay"
local states = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })

local auraContainerLoaded = false

local function EnsureAuraContainerLoaded()
    if auraContainerLoaded then return true end

    if not C_AddOns or not C_AddOns.IsAddOnLoaded or not C_AddOns.LoadAddOn then
        return false
    end

    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        local ok = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        if not ok then return false end
    end

    auraContainerLoaded = C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") == true
    return auraContainerLoaded
end

local function IsSafeID(value)
    return CDM.IsSafeNumber and CDM.IsSafeNumber(value) and value > 0
end

local function FindMappedAuraID(frame)
    if not frame then return nil end

    local function Resolve(spellID)
        if not IsSafeID(spellID) then return nil end
        return TARGET_AURA_BY_SPELL[spellID]
    end

    local auraID = Resolve(frame.cdmCdGroupSpellID)
    if auraID then return auraID end

    if type(frame.GetSpellID) == "function" then
        local ok, spellID = pcall(frame.GetSpellID, frame)
        if ok then
            auraID = Resolve(spellID)
            if auraID then return auraID end
        end
    end

    local info
    if type(frame.GetCooldownInfo) == "function" then
        local ok, result = pcall(frame.GetCooldownInfo, frame)
        if ok and type(result) == "table" then
            info = result
        end
    elseif type(frame.cooldownInfo) == "table" then
        info = frame.cooldownInfo
    end

    if info then
        auraID = Resolve(info.overrideTooltipSpellID)
            or Resolve(info.overrideSpellID)
            or Resolve(info.spellID)
        if auraID then return auraID end

        if type(info.linkedSpellIDs) == "table" then
            for i = 1, #info.linkedSpellIDs do
                auraID = Resolve(info.linkedSpellIDs[i])
                if auraID then return auraID end
            end
        end
    end

    if CDM.GetSpellIDCandidates then
        local ok, candidates = pcall(CDM.GetSpellIDCandidates, CDM, frame)
        if ok and type(candidates) == "table" then
            for i = 1, #candidates do
                auraID = Resolve(candidates[i])
                if auraID then return auraID end
            end
        end
    end

    return nil
end

local function IsAuraOverlayEnabled(frame)
    local map = CDM._auraOverlayEnabled
    local cooldownID = frame and frame.cooldownID
    if type(map) ~= "table" or not IsSafeID(cooldownID) then return false end

    local entry = map[cooldownID]
    return entry and entry.auraOverlay == true or false
end

local function ApplyOverlayAppearance(frame, state)
    if not state then return end

    local sourceIcon = frame and frame.Icon
    local icon = state.icon
    if sourceIcon and icon then
        local texture = sourceIcon:GetTexture()
        if texture then
            icon:SetTexture(texture)
        end
        icon:SetTexCoord(sourceIcon:GetTexCoord())
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetDesaturated(false)
    end

    local cooldown = state.cooldown
    if cooldown then
        local db = CDM.db or {}
        local defaults = CDM.defaults or {}
        local swipe = db.swipeColor or defaults.swipeColor
        if swipe then
            cooldown:SetSwipeColor(
                swipe.r or 0,
                swipe.g or 0,
                swipe.b or 0,
                swipe.a or 0.6
            )
        end
    end
end

local function CreateOverlayState(frame, auraID)
    if not EnsureAuraContainerLoaded() then return nil end

    local state = {
        auraID = auraID,
        activeUnit = false,
    }

    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    container:SetAllPoints(frame)
    container:SetFrameLevel(frame:GetFrameLevel() + 1)
    state.container = container

    local includeSpellIDs = { [auraID] = true }
    local button = container:AddAuraSlot(SLOT_KEY, "HARMFUL|PLAYER", {
        candidateFilters = {
            includeSpellIDs = includeSpellIDs,
        },
        initializeFrame = function(auraButton)
            auraButton:SetAllPoints(container)
            auraButton:SetFrameLevel(container:GetFrameLevel() + 1)

            if auraButton.SetMouseClickEnabled then
                pcall(auraButton.SetMouseClickEnabled, auraButton, false)
            end
            if auraButton.SetMouseMotionEnabled then
                pcall(auraButton.SetMouseMotionEnabled, auraButton, false)
            end

            local icon = auraButton:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(auraButton)
            state.icon = icon

            local cooldown = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
            cooldown:SetAllPoints(auraButton)
            cooldown:SetFrameLevel(auraButton:GetFrameLevel() + 1)
            cooldown:SetDrawEdge(false)
            cooldown:SetDrawBling(false)
            cooldown:SetReverse(true)

            if cooldown.SetCountdownFont and _G.KCDM_CDFont then
                pcall(cooldown.SetCountdownFont, cooldown, "KCDM_CDFont")
            end

            auraButton:SetDurationCooldown(cooldown)
            state.cooldown = cooldown
        end,
    })

    state.button = button

    -- Unit assignment must happen after the slot exists so Blizzard registers
    -- the correct UNIT_AURA processing for the container.
    container:SetUnit("target")
    container:UpdateAllAuras()
    state.activeUnit = true

    states[frame] = state
    ApplyOverlayAppearance(frame, state)
    return state
end

local function DisableState(state)
    if not state or not state.container or not state.activeUnit then return end

    state.container:SetUnit("none")
    state.container:UpdateAllAuras()
    state.activeUnit = false
end

local function EnableState(frame, state, auraID)
    if not state or not state.container then return end

    if state.auraID ~= auraID then
        state.auraID = auraID
        state.container:SetAuraSlotCandidateFilters(SLOT_KEY, {
            includeSpellIDs = { [auraID] = true },
        })
    end

    ApplyOverlayAppearance(frame, state)

    if not state.activeUnit then
        state.container:SetUnit("target")
        state.container:UpdateAllAuras()
        state.activeUnit = true
    end
end

local BindFrame

local function EnsureFrameHooks(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true

    frame:HookScript("OnShow", function(self)
        BindFrame(self)
    end)

    if type(frame.SetCooldownID) == "function" then
        hooksecurefunc(frame, "SetCooldownID", function(self)
            BindFrame(self)
        end)
    end

    if type(frame.ClearCooldownID) == "function" then
        hooksecurefunc(frame, "ClearCooldownID", function(self)
            BindFrame(self)
        end)
    end

    if type(frame.SetOverrideSpell) == "function" then
        hooksecurefunc(frame, "SetOverrideSpell", function(self)
            BindFrame(self)
        end)
    end
end

BindFrame = function(frame)
    if not frame then return end
    EnsureFrameHooks(frame)

    local auraID = FindMappedAuraID(frame)
    local enabled = auraID and IsAuraOverlayEnabled(frame)
    local state = states[frame]

    if not enabled then
        DisableState(state)
        return
    end

    if not state then
        state = CreateOverlayState(frame, auraID)
        if not state then return end
    else
        EnableState(frame, state, auraID)
    end
end

local function BindAllActiveFrames()
    if not CDM.ForEachActiveFrame then return end

    CDM:ForEachActiveFrame(TRACKED_VIEWERS, function(frame)
        BindFrame(frame)
    end)
end

-- Piggyback on KCDM's normal visual lifecycle only to keep a pooled frame bound
-- to the correct spell. This hook never triggers a refresh itself.
if type(CDM.RefreshFrameVisuals) == "function" then
    hooksecurefunc(CDM, "RefreshFrameVisuals", function(_, frame)
        BindFrame(frame)
    end)
end

if CDM.RegisterRefreshCallback then
    CDM:RegisterRefreshCallback("targetAuraOverlay", BindAllActiveFrames, 93, { "CD_DATA" })
end

C_Timer.After(0, BindAllActiveFrames)
