local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS or {}
local Pixel = CDM.Pixel
local originalPoints = setmetatable({}, { __mode = "k" })
local scratchTexts = {}
local scratchSeen = {}

local function IsSafeNumber(value)
    return CDM.IsSafeNumber and CDM.IsSafeNumber(value)
end

local function GetSpellID(frame)
    if not frame then return nil end
    if IsSafeNumber(frame.cdmCdGroupSpellID) then return frame.cdmCdGroupSpellID end
    if frame.GetSpellID then
        local ok, spellID = pcall(frame.GetSpellID, frame)
        if ok and IsSafeNumber(spellID) then return spellID end
    end
    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
    if info then
        local spellID = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
        if IsSafeNumber(spellID) then return spellID end
    end
    return nil
end

local function GetOverride(frame)
    local spellID = GetSpellID(frame)
    if not spellID then return nil end

    local groupIndex = CDM.CheckCdGroupMatch and CDM.CheckCdGroupMatch(frame)
    if groupIndex then
        local sets = CDM.CooldownGroupSets
        local groupData = sets and sets.groups and sets.groups[groupIndex]
        if groupData and CDM.GetCooldownGroupSpellOverride then
            return CDM.GetCooldownGroupSpellOverride(groupData, spellID)
        end
    end

    if CDM.GetUngroupedCooldownOverride then
        return CDM:GetUngroupedCooldownOverride(spellID)
    end
    return nil
end

local function RememberPoints(region)
    if not region or originalPoints[region] then return end
    local points = {}
    for index = 1, region:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(index)
        points[#points + 1] = { point, relativeTo, relativePoint, x, y }
    end
    originalPoints[region] = points
end

local function RestorePoints(region)
    local points = region and originalPoints[region]
    if not points then return end
    region:ClearAllPoints()
    for _, data in ipairs(points) do
        region:SetPoint(unpack(data))
    end
end

local function PositionText(region, frame, position, x, y)
    if not region or not frame or not position then return end
    RememberPoints(region)
    region:ClearAllPoints()
    if Pixel and Pixel.SetPoint then
        Pixel.SetPoint(region, position, frame, position, x or 0, y or 0)
    else
        region:SetPoint(position, frame, position, x or 0, y or 0)
    end
end

local function AddText(region)
    if not region or scratchSeen[region] then return end
    scratchSeen[region] = true
    scratchTexts[#scratchTexts + 1] = region
end

local function CollectCooldownTexts(frame)
    table.wipe(scratchTexts)
    table.wipe(scratchSeen)

    local cooldown = frame.Cooldown
    if cooldown then
        AddText(cooldown.Text or cooldown.text)
        if cooldown.GetRegions then
            for _, region in ipairs({ cooldown:GetRegions() }) do
                if region and region.IsObjectType and region:IsObjectType("FontString") then AddText(region) end
            end
        end
    end
    AddText(frame.Time)
    AddText(frame.Duration)
    return scratchTexts
end

local function Apply(frame, viewerName)
    if viewerName ~= VIEWERS.ESSENTIAL and viewerName ~= VIEWERS.UTILITY then return end

    local override = GetOverride(frame)
    local enabled = override and override.textOverride == true
    local hideCooldown = enabled and (override.hideCooldownTimer == true or override.hideCooldown == true)
    local hideCharges = enabled and override.hideCharges == true
    local cooldown = frame.Cooldown

    if cooldown and cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(hideCooldown and true or false)
    end

    for _, text in ipairs(CollectCooldownTexts(frame)) do
        if text.SetAlpha then text:SetAlpha(hideCooldown and 0 or 1) end
        if enabled and not hideCooldown and override.cooldownPosition then
            PositionText(text, frame, override.cooldownPosition, override.cooldownOffsetX, override.cooldownOffsetY)
        else
            RestorePoints(text)
        end
    end

    local charges = frame.ChargeCount and frame.ChargeCount.Current
    if charges and charges.SetAlpha then charges:SetAlpha(hideCharges and 0 or 1) end
end

if type(CDM.ApplyStyle) == "function" then
    hooksecurefunc(CDM, "ApplyStyle", function(_, frame, viewerName)
        Apply(frame, viewerName)
    end)
end

if type(CDM.PositionCooldownGroupFrames) == "function" then
    hooksecurefunc(CDM, "PositionCooldownGroupFrames", function(_, _, frames)
        for _, frame in ipairs(frames or EMPTY_FRAMES or {}) do
            Apply(frame, frame.cdmViewerName)
        end
    end)
end
