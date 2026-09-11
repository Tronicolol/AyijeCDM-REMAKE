local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local CDM_C = CDM.CONST or {}
local Pixel = CDM.Pixel
local LSM = LibStub("LibSharedMedia-3.0", true)

local BAR_KEY = "Whirlwind"
local POWER_KEY = "Whirlwind"
local FURY_SPEC_ID = 72
local MAX_STACKS = 4
local STACK_DURATION = 20
local WHIRLWIND_SPELL_ID = 190411

-- Improved Whirlwind consumers used by Fury.
-- The tracker is intentionally predictive: it does not read the live aura.
local STACK_SPENDERS = {
    [5308] = true,      -- Execute
    [23881] = true,     -- Bloodthirst
    [85288] = true,     -- Raging Blow
    [184367] = true,    -- Rampage
    [202168] = true,    -- Impending Victory
    [280735] = true,    -- Execute
    [335096] = true,    -- Bloodbath
    [335097] = true,    -- Crushing Blow
}

local _, playerClass = UnitClass("player")

local function CopyTableShallow(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do
        if type(value) == "table" then
            local child = {}
            for childKey, childValue in pairs(value) do
                child[childKey] = childValue
            end
            result[key] = child
        else
            result[key] = value
        end
    end
    return result
end

local function ContainsValue(list, value)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function RegisterResourceMetadata()
    if CDM.CUSTOM_POWER_TYPES then
        CDM.CUSTOM_POWER_TYPES.Whirlwind = POWER_KEY
    end

    if CDM.BAR_KEY_TO_POWER_TYPE then
        CDM.BAR_KEY_TO_POWER_TYPE[BAR_KEY] = POWER_KEY
    end
    if CDM.POWER_TYPE_TO_BAR_KEY then
        CDM.POWER_TYPE_TO_BAR_KEY[POWER_KEY] = BAR_KEY
    end

    if CDM.CLASS_BARS and CDM.CLASS_BARS.WARRIOR and not ContainsValue(CDM.CLASS_BARS.WARRIOR, BAR_KEY) then
        CDM.CLASS_BARS.WARRIOR[#CDM.CLASS_BARS.WARRIOR + 1] = BAR_KEY
    end

    CDM.RESOURCE_BAR_DEFAULTS = CDM.RESOURCE_BAR_DEFAULTS or {}
    if not CDM.RESOURCE_BAR_DEFAULTS[BAR_KEY] then
        local defaults = CopyTableShallow(CDM.RESOURCE_BAR_COMMON_DEFAULTS)
        defaults.color = { r = 0.95, g = 0.55, b = 0.20, a = 1 }
        defaults.bgColor = { r = 0.2, g = 0.2, b = 0.2, a = 0.5 }
        defaults.anchorTo = "Rage"
        defaults.anchorPoint = "BOTTOM"
        defaults.anchorTargetPoint = "TOP"
        defaults.offsetX = 0
        defaults.offsetY = 1
        defaults.tagEnabled = false
        CDM.RESOURCE_BAR_DEFAULTS[BAR_KEY] = defaults
    end

    local peersByClass = CDM.BAR_SPEC_PEERS_BY_CLASS
    if peersByClass then
        peersByClass.WARRIOR = peersByClass.WARRIOR or {}
        local warriorPeers = peersByClass.WARRIOR
        warriorPeers[BAR_KEY] = warriorPeers[BAR_KEY] or {}
        warriorPeers.Rage = warriorPeers.Rage or {}
        warriorPeers[BAR_KEY].Rage = true
        warriorPeers.Rage[BAR_KEY] = true
    end
end

RegisterResourceMetadata()

if playerClass ~= "WARRIOR" then return end
if not Pixel then return end

local currentStacks = 0
local expiryGeneration = 0
local eventFrame = CreateFrame("Frame")
local bar

local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    return GetSpecializationInfo(specIndex)
end

local function IsFury()
    return GetCurrentSpecID() == FURY_SPEC_ID
end

local function GetSetting(key, fallback)
    local value = CDM:GetBarSetting(BAR_KEY, key)
    if value ~= nil then return value end
    return fallback
end

local function GetTexture(mediaType, settingKey, fallback)
    local name = GetSetting(settingKey, fallback)
    if LSM then
        local path = LSM:Fetch(mediaType, name)
        if path then return path end
    end
    return CDM_C.TEX_WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
end

local function GetBorderColor()
    return (CDM.db and CDM.db.borderColor)
        or (CDM.defaults and CDM.defaults.borderColor)
        or { r = 1, g = 1, b = 1, a = 1 }
end

local function ConfigureTexture(texture)
    if not texture then return end
    if texture.SetHorizTile then texture:SetHorizTile(false) end
    if texture.SetVertTile then texture:SetVertTile(false) end
    if Pixel.DisableTextureSnap then Pixel.DisableTextureSnap(texture) end
end

local function EnsureBar()
    if bar then return bar end

    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar.powerType = POWER_KEY
    bar.barKey = BAR_KEY
    bar.isPipBar = true
    bar.pips = {}
    bar.separators = {}

    bar.bgTexture = bar:CreateTexture(nil, "BACKGROUND")
    bar.bgTexture:SetAllPoints(bar)
    ConfigureTexture(bar.bgTexture)

    local barTexturePath = GetTexture("statusbar", "barTexture", "Solid")
    for i = 1, MAX_STACKS do
        local pip = CreateFrame("StatusBar", nil, bar)
        pip:SetMinMaxValues(0, 1)
        pip:SetValue(0, Enum.StatusBarInterpolation.Immediate)
        pip:SetStatusBarTexture(barTexturePath)
        local statusTexture = pip:GetStatusBarTexture()
        ConfigureTexture(statusTexture)
        bar.pips[i] = pip
    end

    if CDM.BORDER and CDM.BORDER.CreateBorder then
        bar.cdmBorder = CDM.BORDER:CreateBorder(bar)
    end

    CDM.resourceBars = CDM.resourceBars or {}
    CDM.resourceBars[POWER_KEY] = bar
    CDM.whirlwindResourceBar = bar

    bar:Hide()
    return bar
end

local function ApplyPipGeometry(targetBar, width, height)
    local onePixel = Pixel.GetSize and Pixel.GetSize() or 1
    if not onePixel or onePixel <= 0 then onePixel = 1 end

    local barPixels = math.max(MAX_STACKS, math.floor((width / onePixel) + 0.5))
    local availablePixels = math.max(MAX_STACKS, barPixels - (MAX_STACKS - 1))
    local previousBoundary = 0

    for i = 1, MAX_STACKS do
        local boundary = math.floor(i * availablePixels / MAX_STACKS)
        local pipPixels = math.max(1, boundary - previousBoundary)
        local xPixels = previousBoundary + (i - 1)
        previousBoundary = boundary

        local pip = targetBar.pips[i]
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", targetBar, "TOPLEFT", xPixels * onePixel, 0)
        pip:SetSize(pipPixels * onePixel, height)
        pip:Show()

        if i < MAX_STACKS then
            local separator = targetBar.separators[i]
            if not separator then
                separator = targetBar:CreateTexture(nil, "OVERLAY")
                targetBar.separators[i] = separator
                ConfigureTexture(separator)
            end
            separator:SetTexture(CDM_C.TEX_WHITE8X8 or "Interface\\Buttons\\WHITE8X8")
            separator:ClearAllPoints()
            separator:SetPoint("TOPLEFT", targetBar, "TOPLEFT", (xPixels + pipPixels) * onePixel, 0)
            separator:SetSize(onePixel, height)
            separator:Show()
        end
    end
end

local function ResolveAnchorTarget(anchorTo)
    if anchorTo == "screen" or not anchorTo then
        return UIParent
    end

    if anchorTo == "playerFrame" then
        return _G.PlayerFrame or UIParent
    end

    if anchorTo == "essential" then
        local viewerName = CDM_C.VIEWERS and CDM_C.VIEWERS.ESSENTIAL
        local container = viewerName and CDM.anchorContainers and CDM.anchorContainers[viewerName]
        return container or (viewerName and _G[viewerName]) or UIParent
    end

    local powerType = CDM.BAR_KEY_TO_POWER_TYPE and CDM.BAR_KEY_TO_POWER_TYPE[anchorTo]
    local target = powerType and CDM.resourceBars and CDM.resourceBars[powerType]
    return target or UIParent
end

local function ApplyLayoutAndStyle()
    local targetBar = EnsureBar()

    local height = GetSetting("height", 16)
    local width = GetSetting("width", 0)
    if width == 0 and CDM.CalculateEssentialRow1Width then
        width = CDM.CalculateEssentialRow1Width()
    end
    if not width or width <= 0 then width = 200 end

    height = Pixel.Snap and Pixel.Snap(height) or height
    width = Pixel.Snap and Pixel.Snap(width) or width
    targetBar:SetSize(width, height)

    local barTexturePath = GetTexture("statusbar", "barTexture", "Solid")
    local bgTexturePath = GetTexture("statusbar", "bgTexture", "Solid")
    local color = GetSetting("color", { r = 0.95, g = 0.55, b = 0.20, a = 1 })
    local bgColor = GetSetting("bgColor", { r = 0.2, g = 0.2, b = 0.2, a = 0.5 })
    local borderColor = GetBorderColor()

    targetBar.bgTexture:SetTexture(bgTexturePath)
    targetBar.bgTexture:SetVertexColor(bgColor.r or 0.2, bgColor.g or 0.2, bgColor.b or 0.2, bgColor.a or 0.5)

    ApplyPipGeometry(targetBar, width, height)

    for i = 1, MAX_STACKS do
        local pip = targetBar.pips[i]
        if pip.cdmWhirlwindTexture ~= barTexturePath then
            pip:SetStatusBarTexture(barTexturePath)
            ConfigureTexture(pip:GetStatusBarTexture())
            pip.cdmWhirlwindTexture = barTexturePath
        end
        pip:SetStatusBarColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
    end

    for i = 1, MAX_STACKS - 1 do
        local separator = targetBar.separators[i]
        if separator then
            separator:SetVertexColor(borderColor.r or 1, borderColor.g or 1, borderColor.b or 1, borderColor.a or 1)
        end
    end

    if CDM.BORDER and CDM.BORDER.CreateBorder then
        targetBar.cdmBorder = CDM.BORDER:CreateBorder(targetBar)
        if targetBar.cdmBorder and targetBar.cdmBorder.SetBackdropBorderColor then
            targetBar.cdmBorder:SetBackdropBorderColor(
                borderColor.r or 1,
                borderColor.g or 1,
                borderColor.b or 1,
                borderColor.a or 1
            )
        end
    end

    local anchorTo = GetSetting("anchorTo", "Rage")
    local anchorPoint = GetSetting("anchorPoint", "BOTTOM")
    local targetPoint = GetSetting("anchorTargetPoint", "TOP")
    local offsetX = GetSetting("offsetX", 0)
    local offsetY = GetSetting("offsetY", 1)
    local anchorTarget = ResolveAnchorTarget(anchorTo)

    targetBar:ClearAllPoints()
    targetBar:SetPoint(anchorPoint, anchorTarget, targetPoint, offsetX, offsetY)
end

local function PassesLoadRules()
    if not IsFury() then return false end
    if not CDM.db or CDM.db.resourcesEnabled == false then return false end

    local loadMode = GetSetting("loadMode", "always")
    if loadMode == "never" then return false end
    if loadMode ~= "conditional" then return true end

    local load = GetSetting("load", nil)
    if type(load) ~= "table" then return true end

    if load.combat ~= nil and load.combat ~= (InCombatLockdown() and true or false) then
        return false
    end
    if load.hideMounted and (IsMounted() or UnitInVehicle("player")) then
        return false
    end
    if load.spec and not load.spec[FURY_SPEC_ID] then
        return false
    end

    return true
end

local function RefreshBar()
    local targetBar = EnsureBar()
    ApplyLayoutAndStyle()

    for i = 1, MAX_STACKS do
        targetBar.pips[i]:SetValue(i <= currentStacks and 1 or 0, Enum.StatusBarInterpolation.Immediate)
    end

    if currentStacks > 0 and PassesLoadRules() then
        targetBar:Show()
        if CDM.Fading and CDM.Fading.ReapplyCurrent then
            CDM.Fading:ReapplyCurrent()
        end
    else
        targetBar:Hide()
    end
end

local function CancelExpiration()
    expiryGeneration = expiryGeneration + 1
end

local function ArmExpiration()
    expiryGeneration = expiryGeneration + 1
    local generation = expiryGeneration

    C_Timer.After(STACK_DURATION, function()
        if generation ~= expiryGeneration then return end
        currentStacks = 0
        RefreshBar()
    end)
end

local function SetStacks(value, resetDuration)
    value = math.max(0, math.min(MAX_STACKS, value or 0))
    currentStacks = value

    if currentStacks == 0 then
        CancelExpiration()
    elseif resetDuration then
        ArmExpiration()
    end

    RefreshBar()
end

local function OnSpellSucceeded(unit, _, spellID)
    if unit ~= "player" or not IsFury() then return end

    if spellID == WHIRLWIND_SPELL_ID then
        SetStacks(MAX_STACKS, true)
        return
    end

    if currentStacks > 0 and STACK_SPENDERS[spellID] then
        SetStacks(currentStacks - 1, false)
    end
end

local function ResetState()
    currentStacks = 0
    CancelExpiration()
    if bar then bar:Hide() end
end

local function OnSpecChanged(unit)
    if unit and unit ~= "player" then return end
    ResetState()
    RefreshBar()
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellSucceeded(...)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        OnSpecChanged(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResetState()
        RefreshBar()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_MOUNT_DISPLAY_CHANGED"
        or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        RefreshBar()
    elseif event == "PLAYER_DEAD" then
        ResetState()
    end
end)

eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
eventFrame:RegisterEvent("PLAYER_DEAD")

if type(CDM.UpdateResources) == "function" then
    hooksecurefunc(CDM, "UpdateResources", function()
        RefreshBar()
    end)
end

function CDM:GetWhirlwindResourceStacks()
    return currentStacks
end

C_Timer.After(0, RefreshBar)
