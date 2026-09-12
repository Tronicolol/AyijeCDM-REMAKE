local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local CDM_C = CDM.CONST
local VIEWERS = CDM_C and CDM_C.VIEWERS
if not VIEWERS then return end

-- Exceptional cast/cooldown spell -> real target aura spell mappings.
-- Most spells need no entry here: their own spell ID, base/override variants,
-- or Blizzard's linkedSpellIDs are added automatically below.
local TARGET_AURA_LINKS = {
    [772] = 388539, -- Rend
}

local TRACKED_VIEWERS = { VIEWERS.ESSENTIAL, VIEWERS.UTILITY }
local SLOT_KEY = "KCDMTargetAuraOverlay"
local states = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })
local pendingBinds = setmetatable({}, { __mode = "k" })

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
    if value == nil then return false end
    if issecretvalue and issecretvalue(value) then return false end
    return CDM.IsSafeNumber and CDM.IsSafeNumber(value) and value > 0
end

local function SafeField(source, key)
    if type(source) ~= "table" then return nil end

    local ok, value = pcall(function()
        return source[key]
    end)
    if not ok then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function SafeCall(method, owner)
    if type(method) ~= "function" then return nil end

    local ok, value = pcall(method, owner)
    if not ok then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function AddSpellID(include, queue, spellID)
    if not IsSafeID(spellID) or include[spellID] then return end
    include[spellID] = true
    queue[#queue + 1] = spellID
end

local function AddCooldownInfoIDs(include, queue, info)
    if type(info) ~= "table" then return end

    AddSpellID(include, queue, SafeField(info, "spellID"))
    AddSpellID(include, queue, SafeField(info, "overrideSpellID"))
    AddSpellID(include, queue, SafeField(info, "overrideTooltipSpellID"))
    AddSpellID(include, queue, SafeField(info, "linkedSpellID"))

    local linkedSpellIDs = SafeField(info, "linkedSpellIDs")
    if type(linkedSpellIDs) == "table" then
        for index = 1, #linkedSpellIDs do
            local ok, linkedSpellID = pcall(function()
                return linkedSpellIDs[index]
            end)
            if ok then
                AddSpellID(include, queue, linkedSpellID)
            end
        end
    end
end

local function ExpandSpellID(include, queue, spellID)
    if not IsSafeID(spellID) then return end

    if CDM.ForEachSpellMatchCandidate then
        CDM:ForEachSpellMatchCandidate(spellID, function(candidate)
            AddSpellID(include, queue, candidate)
        end)
    end

    if C_Spell then
        if type(C_Spell.GetBaseSpell) == "function" then
            local ok, baseSpellID = pcall(C_Spell.GetBaseSpell, spellID)
            if ok then AddSpellID(include, queue, baseSpellID) end
        end

        if type(C_Spell.GetOverrideSpell) == "function" then
            local ok, overrideSpellID = pcall(C_Spell.GetOverrideSpell, spellID)
            if ok then AddSpellID(include, queue, overrideSpellID) end
        end
    end

    local linkedAura = TARGET_AURA_LINKS[spellID]
    if type(linkedAura) == "number" then
        AddSpellID(include, queue, linkedAura)
    elseif type(linkedAura) == "table" then
        for index = 1, #linkedAura do
            AddSpellID(include, queue, linkedAura[index])
        end
    end
end

local function BuildIncludeSpellIDs(frame)
    if not frame then return nil, nil end

    local include = {}
    local queue = {}

    AddSpellID(include, queue, frame.cdmCdGroupSpellID)
    AddSpellID(include, queue, frame.cdmBuffCategorySpellID)

    AddSpellID(include, queue, SafeCall(frame.GetSpellID, frame))
    AddSpellID(include, queue, SafeCall(frame.GetBaseSpellID, frame))
    AddSpellID(include, queue, SafeCall(frame.GetLinkedSpell, frame))
    AddSpellID(include, queue, SafeCall(frame.GetAuraSpellID, frame))

    local frameInfo = SafeCall(frame.GetCooldownInfo, frame)
    if type(frameInfo) ~= "table" then
        frameInfo = frame.cooldownInfo
    end
    AddCooldownInfoIDs(include, queue, frameInfo)

    local cooldownID = frame.cooldownID
    if IsSafeID(cooldownID)
        and C_CooldownViewer
        and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function" then
        local ok, viewerInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if ok then
            AddCooldownInfoIDs(include, queue, viewerInfo)
        end
    end

    if CDM.GetSpellIDCandidates then
        local ok, candidates = pcall(CDM.GetSpellIDCandidates, CDM, frame)
        if ok and type(candidates) == "table" then
            for index = 1, #candidates do
                AddSpellID(include, queue, candidates[index])
            end
        end
    end

    local index = 1
    while index <= #queue do
        ExpandSpellID(include, queue, queue[index])
        index = index + 1
    end

    if next(include) == nil then return nil, nil end

    local ordered = {}
    for spellID in pairs(include) do
        ordered[#ordered + 1] = spellID
    end
    table.sort(ordered)

    local signatureParts = {}
    for i = 1, #ordered do
        signatureParts[i] = tostring(ordered[i])
    end

    return include, table.concat(signatureParts, ",")
end

local function GetAuraOverlayEntry(frame)
    local map = CDM._auraOverlayEnabled
    local cooldownID = frame and frame.cooldownID
    if type(map) ~= "table" or not IsSafeID(cooldownID) then return nil end

    local entry = map[cooldownID]
    if entry and entry.auraOverlay == true then
        return entry
    end

    return nil
end

local function IsNativeAuraActive(frame)
    if not frame then return false end
    if frame.cooldownUseAuraDisplayTime == true then return true end

    local auraSpellID = SafeCall(frame.GetAuraSpellID, frame)
    return IsSafeID(auraSpellID)
end

local function ApplyOverlayAppearance(frame, state)
    if not state then return end

    if state.icon then
        if CDM_C.ApplyIconTexCoord and CDM_C.GetEffectiveZoomAmount then
            CDM_C.ApplyIconTexCoord(state.icon, CDM_C.GetEffectiveZoomAmount())
        else
            state.icon:SetTexCoord(0, 1, 0, 1)
        end
        state.icon:SetVertexColor(1, 1, 1, 1)
        state.icon:SetDesaturated(false)
    end

    if state.cooldown then
        local db = CDM.db or {}
        local defaults = CDM.defaults or {}
        local swipe = db.swipeColor or defaults.swipeColor
        if swipe then
            state.cooldown:SetSwipeColor(
                swipe.r or 0,
                swipe.g or 0,
                swipe.b or 0,
                swipe.a or 0.6
            )
        end
    end
end

local function CreateOverlayState(frame, includeSpellIDs, signature)
    if not EnsureAuraContainerLoaded() then return nil end

    local state = {
        signature = signature,
        activeUnit = false,
    }

    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    container:SetAllPoints(frame)
    container:SetFrameLevel(frame:GetFrameLevel() + 1)
    container:SetAlpha(0)
    state.container = container

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
            auraButton:SetIcon(icon)
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
    states[frame] = state
    ApplyOverlayAppearance(frame, state)
    return state
end

local function DisableState(state)
    if not state or not state.container then return end

    state.container:SetAlpha(0)

    if state.activeUnit then
        state.container:SetUnit("none")
        state.container:UpdateAllAuras()
        state.activeUnit = false
    end
end

local function UpdateStateFilter(state, includeSpellIDs, signature)
    if not state or not state.container or state.signature == signature then
        return true
    end

    local ok = pcall(state.container.SetAuraSlotCandidateFilters, state.container, SLOT_KEY, {
        includeSpellIDs = includeSpellIDs,
    })
    if not ok then return false end

    state.signature = signature
    return true
end

local function EnableState(frame, state, includeSpellIDs, signature)
    if not state or not state.container then return end

    if not UpdateStateFilter(state, includeSpellIDs, signature) then
        DisableState(state)
        return
    end

    ApplyOverlayAppearance(frame, state)
    state.container:SetAlpha(1)

    if not state.activeUnit then
        state.container:SetUnit("target")
        state.activeUnit = true
    end

    state.container:UpdateAllAuras()
end

local BindFrame

local function QueueBindFrame(frame)
    if not frame or pendingBinds[frame] then return end

    pendingBinds[frame] = true
    C_Timer.After(0, function()
        pendingBinds[frame] = nil
        BindFrame(frame)
    end)
end

local function EnsureFrameHooks(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true

    frame:HookScript("OnShow", function(self)
        QueueBindFrame(self)
    end)

    frame:HookScript("OnHide", function(self)
        DisableState(states[self])
    end)

    if type(frame.SetCooldownID) == "function" then
        hooksecurefunc(frame, "SetCooldownID", function(self)
            QueueBindFrame(self)
        end)
    end

    if type(frame.ClearCooldownID) == "function" then
        hooksecurefunc(frame, "ClearCooldownID", function(self)
            QueueBindFrame(self)
        end)
    end

    if type(frame.SetOverrideSpell) == "function" then
        hooksecurefunc(frame, "SetOverrideSpell", function(self)
            QueueBindFrame(self)
        end)
    end

    if type(frame.OnAuraInstanceInfoSet) == "function" then
        hooksecurefunc(frame, "OnAuraInstanceInfoSet", function(self)
            QueueBindFrame(self)
        end)
    end

    if type(frame.OnAuraInstanceInfoCleared) == "function" then
        hooksecurefunc(frame, "OnAuraInstanceInfoCleared", function(self)
            QueueBindFrame(self)
        end)
    end
end

BindFrame = function(frame)
    if not frame then return end
    EnsureFrameHooks(frame)

    local entry = GetAuraOverlayEntry(frame)
    local state = states[frame]

    if not entry or not frame:IsShown() or IsNativeAuraActive(frame) then
        DisableState(state)
        return
    end

    local includeSpellIDs, signature = BuildIncludeSpellIDs(frame)
    if not includeSpellIDs then
        DisableState(state)
        return
    end

    if not state then
        state = CreateOverlayState(frame, includeSpellIDs, signature)
        if not state then return end
    end

    EnableState(frame, state, includeSpellIDs, signature)
end

local function BindAllActiveFrames()
    if not CDM.ForEachActiveFrame then return end

    CDM:ForEachActiveFrame(TRACKED_VIEWERS, function(frame)
        BindFrame(frame)
    end)
end

local function RefreshTargetContainers()
    for frame, state in pairs(states) do
        if state.activeUnit and frame:IsShown() and GetAuraOverlayEntry(frame) then
            -- AuraContainer receives UNIT_AURA for the unit token itself. Blizzard
            -- explicitly exposes UpdateAllAuras for external identity changes,
            -- such as PLAYER_TARGET_CHANGED.
            state.container:UpdateAllAuras()
        else
            DisableState(state)
        end
    end
end

local targetWatcher = CreateFrame("Frame")
targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
targetWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
targetWatcher:SetScript("OnEvent", function()
    RefreshTargetContainers()
end)

if CDM.RegisterRefreshCallback then
    CDM:RegisterRefreshCallback("targetAuraOverlay", BindAllActiveFrames, 93, { "CD_DATA" })
end

C_Timer.After(0, BindAllActiveFrames)
