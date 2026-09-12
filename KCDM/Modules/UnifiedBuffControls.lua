local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local CDM_C = CDM.CONST or {}
local VIEWERS = CDM_C.VIEWERS or {}
local Pixel = CDM.Pixel
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local pointCache = setmetatable({}, { __mode = "k" })
local buffPlaceholders = {}
local barPlaceholders = {}
local hookedBuffFrames = setmetatable({}, { __mode = "k" })
local hookedBarFrames = setmetatable({}, { __mode = "k" })
local refreshQueued = false

local function IsSafeNumber(value)
    return CDM.IsSafeNumber and CDM.IsSafeNumber(value)
end

local function SavePoints(region)
    if not region or pointCache[region] then return end
    local points = {}
    local count = region:GetNumPoints() or 0
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(index)
        points[#points + 1] = { point, relativeTo, relativePoint, x, y }
    end
    pointCache[region] = points
end

local function RestorePoints(region)
    local points = region and pointCache[region]
    if not points then return end
    region:ClearAllPoints()
    for _, pointData in ipairs(points) do
        region:SetPoint(unpack(pointData))
    end
end

local function ApplyTextPosition(region, target, position, offsetX, offsetY)
    if not region or not target then return end
    if not position then
        RestorePoints(region)
        return
    end

    SavePoints(region)
    region:ClearAllPoints()
    if Pixel and Pixel.SetPoint then
        Pixel.SetPoint(region, position, target, position, offsetX or 0, offsetY or 0)
    else
        region:SetPoint(position, target, position, offsetX or 0, offsetY or 0)
    end
end

local function SetTextAlpha(region, hidden)
    if not region or not region.SetAlpha then return end
    region:SetAlpha(hidden and 0 or 1)
end

local function ApplyFont(region, size, color)
    if not region then return end
    if size and region.GetFont and region.SetFont then
        local fontPath, _, flags = region:GetFont()
        if fontPath then
            local pixelSize = Pixel and Pixel.FontSize and Pixel.FontSize(size) or size
            region:SetFont(fontPath, pixelSize, flags)
        end
    end
    if color and region.SetTextColor then
        region:SetTextColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
    end
end

local function CollectCooldownTexts(frame, output)
    table.wipe(output)
    local seen = {}
    local function Add(region)
        if region and not seen[region] then
            seen[region] = true
            output[#output + 1] = region
        end
    end

    local cooldown = frame and frame.Cooldown
    if cooldown then
        Add(cooldown.Text or cooldown.text)
        if cooldown.GetRegions then
            for _, region in ipairs({ cooldown:GetRegions() }) do
                if region and region.IsObjectType and region:IsObjectType("FontString") then
                    Add(region)
                end
            end
        end
    end
    Add(frame and frame.Time)
    Add(frame and frame.Duration)
    return output
end

local cooldownTextScratch = {}

local function ApplyCooldownTextControls(frame, override, target)
    if not frame then return end
    local enabled = override and override.textOverride == true
    local hidden = enabled and (override.hideCooldownTimer == true or override.hideCooldown == true or override.durationHidden == true)
    local position = enabled and override.cooldownPosition or nil
    local offsetX = enabled and override.cooldownOffsetX or 0
    local offsetY = enabled and override.cooldownOffsetY or 0

    local cooldown = frame.Cooldown
    if cooldown and cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(hidden and true or false)
    end

    for _, region in ipairs(CollectCooldownTexts(frame, cooldownTextScratch)) do
        SetTextAlpha(region, hidden)
        if enabled and not hidden and position then
            ApplyTextPosition(region, target or frame, position, offsetX, offsetY)
        elseif not enabled or not position then
            RestorePoints(region)
        end
    end
end

local function ApplyChargeTextControls(region, override, target, sizeKey, colorKey, positionKey, xKey, yKey)
    if not region then return end
    local enabled = override and override.textOverride == true
    local hidden = enabled and override.hideCharges == true
    SetTextAlpha(region, hidden)

    if not enabled then
        RestorePoints(region)
        return
    end

    if not hidden then
        ApplyFont(region, override[sizeKey], override[colorKey])
        local position = override[positionKey]
        if position then
            ApplyTextPosition(region, target, position, override[xKey] or 0, override[yKey] or 0)
        else
            RestorePoints(region)
        end
    end
end

local function GetCooldownFrameSpellID(frame)
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

local function IsLayoutCooldownFrame(frame)
    if not frame then return false end
    local viewer = frame.GetViewerFrame and frame:GetViewerFrame() or nil
    local name = viewer and viewer:GetName() or frame.cdmViewerName
    return name == VIEWERS.ESSENTIAL or name == VIEWERS.UTILITY
end

local function ResolveLayoutOverride(frame)
    if not IsLayoutCooldownFrame(frame) then return nil end
    local spellID = GetCooldownFrameSpellID(frame)
    if not spellID then return nil end

    local groupIndex = CDM.CheckCdGroupMatch and CDM.CheckCdGroupMatch(frame) or nil
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

local function ApplyLayoutTextExtensions(frame)
    if not IsLayoutCooldownFrame(frame) then return end
    local override = ResolveLayoutOverride(frame)
    ApplyCooldownTextControls(frame, override, frame)
    local chargeText = frame.ChargeCount and frame.ChargeCount.Current
    ApplyChargeTextControls(
        chargeText,
        override,
        frame,
        "chargeFontSize",
        "chargeColor",
        "chargePosition",
        "chargeOffsetX",
        "chargeOffsetY"
    )
end

local function ResolveBuffOverride(groupData, spellID)
    if not groupData or not groupData.spellOverrides or not spellID then return nil end
    if CDM.ResolveBuffOverrideEntry then
        return CDM:ResolveBuffOverrideEntry(groupData.spellOverrides, spellID)
    end
    return nil
end

local function ApplyBuffTextExtensions(frame, groupData)
    if not frame or not groupData then return end
    local spellID = frame.cdmBuffCategorySpellID
    local override = ResolveBuffOverride(groupData, spellID)
    ApplyCooldownTextControls(frame, override, frame)
    local applications = frame.Applications and frame.Applications.Applications
    ApplyChargeTextControls(
        applications,
        override,
        frame,
        "countFontSize",
        "countColor",
        "countPosition",
        "countOffsetX",
        "countOffsetY"
    )
end

local function ResolveBarOverride(frame, groupData, explicitOverride)
    if explicitOverride then return explicitOverride end
    if CDM.ResolveBarSpellOverride then
        return CDM.ResolveBarSpellOverride(frame, groupData)
    end
    return nil
end

local function ApplyBarTextExtensions(frame, groupData, explicitOverride)
    if not frame then return end
    local override = ResolveBarOverride(frame, groupData, explicitOverride)
    local bar = frame.Bar or frame
    local duration = (frame.Bar and frame.Bar.Duration) or frame.Duration
    local applications = frame.Icon and frame.Icon.Applications
    local enabled = override and override.textOverride == true

    if duration then
        local hidden = enabled and (override.hideCooldownTimer == true or override.durationHidden == true)
        SetTextAlpha(duration, hidden)
        if enabled and not hidden then
            ApplyFont(duration, override.durationFontSize, override.durationColor)
            if override.durationPosition then
                ApplyTextPosition(duration, bar, override.durationPosition, override.durationOffsetX or 0, override.durationOffsetY or 0)
            else
                RestorePoints(duration)
            end
        elseif not enabled then
            RestorePoints(duration)
        end
    end

    ApplyChargeTextControls(
        applications,
        override,
        frame.Icon or frame,
        "applicationsFontSize",
        "applicationsColor",
        "applicationsPosition",
        "applicationsOffsetX",
        "applicationsOffsetY"
    )
end

local function GetConfiguredBorderColor()
    if CDM.GetConfiguredBorderColor then
        return CDM.GetConfiguredBorderColor()
    end
    local color = (CDM.db and CDM.db.borderColor) or (CDM.defaults and CDM.defaults.borderColor) or { r = 1, g = 1, b = 1, a = 1 }
    return color.r or 1, color.g or 1, color.b or 1, color.a or 1
end

local function CreateBuffPlaceholder(container)
    local frame = CreateFrame("Frame", nil, container)
    frame:EnableMouse(false)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if Pixel and Pixel.DisableTextureSnap then Pixel.DisableTextureSnap(icon) end
    frame.Icon = icon
    if CDM.BORDER and CDM.BORDER.CreateBorder then
        frame.cdmBorder = CDM.BORDER:CreateBorder(frame, true)
        if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[frame] = nil end
    end
    return frame
end

local function StyleBuffPlaceholder(frame, spellID, groupData, override)
    local width = groupData.iconWidth or 30
    local height = groupData.iconHeight or 30
    local snappedWidth = Pixel and Pixel.Snap and Pixel.Snap(width) or width
    local snappedHeight = Pixel and Pixel.Snap and Pixel.Snap(height) or height
    frame:SetSize(snappedWidth, snappedHeight)
    frame.Icon:SetTexture(C_Spell.GetSpellTexture(spellID))
    if CDM_C.ApplyIconTexCoord then
        CDM_C.ApplyIconTexCoord(frame.Icon, CDM_C.GetEffectiveZoomAmount and CDM_C.GetEffectiveZoomAmount() or 0, snappedWidth, snappedHeight)
    end
    frame.Icon:SetDesaturated(override and override.desaturateWhenInactive == true or false)
    frame.Icon:SetAlpha(1)
    if frame.cdmBorder and frame.cdmBorder.SetBackdropBorderColor then
        frame.cdmBorder:SetBackdropBorderColor(GetConfiguredBorderColor())
    end
    frame:Show()
end

local function ReleaseBuffPlaceholder(groupIndex, spellID)
    local group = buffPlaceholders[groupIndex]
    local frame = group and group[spellID]
    if not frame then return end
    frame:Hide()
    frame:ClearAllPoints()
    group[spellID] = nil
    if not next(group) then buffPlaceholders[groupIndex] = nil end
end

local function GetBuffPlaceholder(groupIndex, spellID, container)
    local group = buffPlaceholders[groupIndex]
    if not group then
        group = {}
        buffPlaceholders[groupIndex] = group
    end
    local frame = group[spellID]
    if not frame then
        frame = CreateBuffPlaceholder(container)
        group[spellID] = frame
    elseif frame:GetParent() ~= container then
        frame:SetParent(container)
    end
    return frame
end

local function QueueBuffReanchor()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        local viewer = VIEWERS.BUFF and _G[VIEWERS.BUFF]
        if viewer and CDM.ForceReanchor then CDM:ForceReanchor(viewer) end
    end)
end

local function HookBuffFrame(frame)
    if not frame or hookedBuffFrames[frame] then return end
    hookedBuffFrames[frame] = true
    frame:HookScript("OnHide", QueueBuffReanchor)
    frame:HookScript("OnShow", QueueBuffReanchor)
end

local function ApplyBuffAlwaysShow(groupIndex, frames)
    local sets = CDM.BuffGroupSets
    local groupData = sets and sets.groups and sets.groups[groupIndex]
    local container = CDM.buffGroupContainers and CDM.buffGroupContainers[groupIndex]
    if not groupData or not container or not groupData.spells then return end

    local activeBySpell = {}
    local consumed = {}
    for _, frame in ipairs(frames or {}) do
        HookBuffFrame(frame)
        if frame:IsShown() then
            local spellID = frame.cdmBuffCategorySpellID
            if spellID then
                activeBySpell[spellID] = frame
                local base = CDM.NormalizeToBase and CDM.NormalizeToBase(spellID)
                if base then activeBySpell[base] = frame end
            end
        end
    end

    local hasAlwaysShow = false
    for _, spellID in ipairs(groupData.spells) do
        local override = ResolveBuffOverride(groupData, spellID)
        if override and override.alwaysShow == true then
            hasAlwaysShow = true
            break
        end
    end

    if not hasAlwaysShow then
        local old = buffPlaceholders[groupIndex]
        if old then
            local ids = {}
            for spellID in pairs(old) do ids[#ids + 1] = spellID end
            for _, spellID in ipairs(ids) do ReleaseBuffPlaceholder(groupIndex, spellID) end
        end
        return
    end

    local entries = {}
    local neededPlaceholders = {}
    for _, spellID in ipairs(groupData.spells) do
        local base = CDM.NormalizeToBase and CDM.NormalizeToBase(spellID) or spellID
        local active = activeBySpell[spellID] or activeBySpell[base]
        local override = ResolveBuffOverride(groupData, spellID)
        if active then
            consumed[active] = true
            entries[#entries + 1] = active
            ReleaseBuffPlaceholder(groupIndex, spellID)
        elseif override and override.alwaysShow == true then
            local placeholder = GetBuffPlaceholder(groupIndex, spellID, container)
            StyleBuffPlaceholder(placeholder, spellID, groupData, override)
            neededPlaceholders[spellID] = true
            entries[#entries + 1] = placeholder
        end
    end

    for _, frame in ipairs(frames or {}) do
        if frame:IsShown() and not consumed[frame] then entries[#entries + 1] = frame end
    end

    local old = buffPlaceholders[groupIndex]
    if old then
        local ids = {}
        for spellID in pairs(old) do
            if not neededPlaceholders[spellID] then ids[#ids + 1] = spellID end
        end
        for _, spellID in ipairs(ids) do ReleaseBuffPlaceholder(groupIndex, spellID) end
    end

    local count = #entries
    if count == 0 then return end
    local layoutCtx = CDM._LayoutCtx
    if not layoutCtx or not layoutCtx.PositionFrameAtSlot then return end

    local grow = groupData.grow or "RIGHT"
    local anchorPoint = groupData.anchorPoint or "CENTER"
    local selfPoint = layoutCtx.DeriveSelfPoint and layoutCtx.DeriveSelfPoint(anchorPoint, grow) or anchorPoint
    local width = Pixel and Pixel.Snap and Pixel.Snap(groupData.iconWidth or 30) or (groupData.iconWidth or 30)
    local height = Pixel and Pixel.Snap and Pixel.Snap(groupData.iconHeight or 30) or (groupData.iconHeight or 30)
    local spacing = Pixel and Pixel.Snap and Pixel.Snap(groupData.spacing or 4) or (groupData.spacing or 4)

    for index, frame in ipairs(entries) do
        layoutCtx.PositionFrameAtSlot(frame, container, index - 1, width, height, spacing, grow, count, anchorPoint, selfPoint)
    end
end

local function CreateBarPlaceholder(container)
    local frame = CreateFrame("Frame", nil, container)
    frame:EnableMouse(false)

    local bar = CreateFrame("StatusBar", nil, frame)
    frame.Bar = bar
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    frame.Background = bg

    local iconFrame = CreateFrame("Frame", nil, frame)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    iconFrame.Texture = icon
    frame.IconFrame = iconFrame

    local name = bar:CreateFontString(nil, "OVERLAY")
    name:SetFontObject("GameFontHighlightSmall")
    name:SetJustifyH("LEFT")
    frame.Name = name

    if CDM.BORDER and CDM.BORDER.CreateBorder then
        frame.cdmBorder = CDM.BORDER:CreateBorder(frame, true)
        if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[frame] = nil end
    end
    return frame
end

local function ResolveBarField(groupData, override, groupKey, dbKey, fallback)
    if override and override[groupKey] ~= nil then return override[groupKey] end
    if groupData and groupData[groupKey] ~= nil then return groupData[groupKey] end
    local db = CDM.db or {}
    if db[dbKey] ~= nil then return db[dbKey] end
    local defaults = CDM.defaults or {}
    if defaults[dbKey] ~= nil then return defaults[dbKey] end
    return fallback
end

local function StyleBarPlaceholder(frame, spellID, groupData, override, width, height)
    frame:SetSize(width, height)
    local textureName = ResolveBarField(groupData, nil, "texture", "buffBarTexture", "Solid")
    local texturePath = (LSM and LSM:Fetch("statusbar", textureName)) or "Interface\\TargetingFrame\\UI-StatusBar"
    frame.Bar:SetStatusBarTexture(texturePath)
    frame.Background:SetTexture(texturePath)

    local color = ResolveBarField(groupData, override, "barColor", "buffBarColor", { r = 0.4, g = 0.6, b = 0.9, a = 1 })
    local bgColor = ResolveBarField(groupData, override, "backgroundColor", "buffBarBackgroundColor", { r = 0.1, g = 0.1, b = 0.1, a = 0.8 })
    frame.Bar:SetMinMaxValues(0, 1)
    frame.Bar:SetValue(0)
    frame.Bar:SetStatusBarColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
    frame.Background:SetVertexColor(bgColor.r or 0.1, bgColor.g or 0.1, bgColor.b or 0.1, bgColor.a or 0.8)

    local iconPosition = ResolveBarField(groupData, override, "iconPosition", "buffBarIconPosition", "LEFT")
    local iconGap = ResolveBarField(groupData, nil, "iconGap", "buffBarIconGap", 1)
    local iconFrame = frame.IconFrame
    iconFrame:ClearAllPoints()
    frame.Bar:ClearAllPoints()

    if iconPosition == "HIDDEN" then
        iconFrame:Hide()
        frame.Bar:SetAllPoints(frame)
    else
        iconFrame:Show()
        iconFrame:SetSize(height, height)
        if iconPosition == "RIGHT" then
            iconFrame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            frame.Bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.Bar:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMLEFT", -iconGap, 0)
        else
            iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
            frame.Bar:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", iconGap, 0)
            frame.Bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
    end

    frame.IconFrame.Texture:SetTexture(C_Spell.GetSpellTexture(spellID))
    local desaturated = override and override.desaturateWhenInactive == true or false
    frame.IconFrame.Texture:SetDesaturated(desaturated)
    local statusTexture = frame.Bar:GetStatusBarTexture()
    if statusTexture and statusTexture.SetDesaturated then statusTexture:SetDesaturated(desaturated) end

    local showName = ResolveBarField(groupData, nil, "showName", "buffBarShowName", true)
    if override and override.nameHidden == true then showName = false end
    frame.Name:SetShown(showName and true or false)
    if showName then
        local customName = override and override.customName
        frame.Name:SetText((customName and customName ~= "") and customName or (C_Spell.GetSpellName(spellID) or ""))
        local fontSize = ResolveBarField(groupData, nil, "nameFontSize", "buffBarNameFontSize", 12)
        local nameColor = ResolveBarField(groupData, nil, "nameColor", "buffBarNameColor", { r = 1, g = 1, b = 1, a = 1 })
        local fontPath = (CDM_C.GetBaseFontPath and CDM_C.GetBaseFontPath()) or STANDARD_TEXT_FONT
        local outline = (CDM_C.GetBaseFontOutline and CDM_C.GetBaseFontOutline()) or ""
        frame.Name:SetFont(fontPath, Pixel and Pixel.FontSize and Pixel.FontSize(fontSize) or fontSize, outline)
        frame.Name:SetTextColor(nameColor.r or 1, nameColor.g or 1, nameColor.b or 1, nameColor.a or 1)
        frame.Name:ClearAllPoints()
        frame.Name:SetPoint("LEFT", frame.Bar, "LEFT", ResolveBarField(groupData, nil, "nameOffsetX", "buffBarNameOffsetX", 4), ResolveBarField(groupData, nil, "nameOffsetY", "buffBarNameOffsetY", 0))
    end

    if frame.cdmBorder and frame.cdmBorder.SetBackdropBorderColor then
        frame.cdmBorder:SetBackdropBorderColor(GetConfiguredBorderColor())
    end
    frame:Show()
end

local function ReleaseBarPlaceholder(groupIndex, spellID)
    local group = barPlaceholders[groupIndex]
    local frame = group and group[spellID]
    if not frame then return end
    frame:Hide()
    frame:ClearAllPoints()
    group[spellID] = nil
    if not next(group) then barPlaceholders[groupIndex] = nil end
end

local function GetBarPlaceholder(groupIndex, spellID, container)
    local group = barPlaceholders[groupIndex]
    if not group then
        group = {}
        barPlaceholders[groupIndex] = group
    end
    local frame = group[spellID]
    if not frame then
        frame = CreateBarPlaceholder(container)
        group[spellID] = frame
    elseif frame:GetParent() ~= container then
        frame:SetParent(container)
    end
    return frame
end

local function QueueBarReanchor()
    C_Timer.After(0, function()
        local viewer = VIEWERS.BUFF_BAR and _G[VIEWERS.BUFF_BAR]
        if viewer and CDM.ForceReanchor then CDM:ForceReanchor(viewer) end
    end)
end

local function HookBarFrame(frame)
    if not frame or hookedBarFrames[frame] then return end
    hookedBarFrames[frame] = true
    frame:HookScript("OnHide", QueueBarReanchor)
    frame:HookScript("OnShow", QueueBarReanchor)
end

local function ApplyBarAlwaysShow(groupIndex, frames)
    local sets = CDM.BarGroupSets
    local groupData = sets and sets.groups and sets.groups[groupIndex]
    local container = CDM.barGroupContainers and CDM.barGroupContainers[groupIndex]
    if not groupData or not container or not groupData.spells then return end

    local activeBySpell = {}
    local consumed = {}
    for _, frame in ipairs(frames or {}) do
        HookBarFrame(frame)
        if frame:IsShown() then
            local spellID = frame.cdmBarGroupSpellID
            if spellID then
                activeBySpell[spellID] = frame
                local base = CDM.NormalizeToBase and CDM.NormalizeToBase(spellID)
                if base then activeBySpell[base] = frame end
            end
        end
    end

    local hasAlwaysShow = false
    for _, spellID in ipairs(groupData.spells) do
        local override = CDM.ResolveBarOverrideEntry and CDM:ResolveBarOverrideEntry(groupData.spellOverrides, spellID) or nil
        if override and override.alwaysShow == true then hasAlwaysShow = true break end
    end
    if not hasAlwaysShow then
        local old = barPlaceholders[groupIndex]
        if old then
            local ids = {}
            for spellID in pairs(old) do ids[#ids + 1] = spellID end
            for _, spellID in ipairs(ids) do ReleaseBarPlaceholder(groupIndex, spellID) end
        end
        return
    end

    local entries = {}
    local needed = {}
    local defaultHeight = groupData.barHeight or 20
    local barWidth = groupData.barWidth
    if not barWidth or barWidth == 0 then barWidth = CDM.CalculateEssentialRow1Width and CDM.CalculateEssentialRow1Width() or 200 end
    barWidth = Pixel and Pixel.Snap and Pixel.Snap(barWidth) or barWidth
    local spacing = Pixel and Pixel.Snap and Pixel.Snap(groupData.spacing or 1) or (groupData.spacing or 1)

    for _, spellID in ipairs(groupData.spells) do
        local base = CDM.NormalizeToBase and CDM.NormalizeToBase(spellID) or spellID
        local active = activeBySpell[spellID] or activeBySpell[base]
        local override = CDM.ResolveBarOverrideEntry and CDM:ResolveBarOverrideEntry(groupData.spellOverrides, spellID) or nil
        local height = (override and override.barHeight) or defaultHeight
        height = Pixel and Pixel.Snap and Pixel.Snap(height) or height
        if active then
            consumed[active] = true
            entries[#entries + 1] = { frame = active, height = height }
            ReleaseBarPlaceholder(groupIndex, spellID)
        elseif override and override.alwaysShow == true then
            local placeholder = GetBarPlaceholder(groupIndex, spellID, container)
            StyleBarPlaceholder(placeholder, spellID, groupData, override, barWidth, height)
            needed[spellID] = true
            entries[#entries + 1] = { frame = placeholder, height = height }
        end
    end

    for _, frame in ipairs(frames or {}) do
        if frame:IsShown() and not consumed[frame] then
            entries[#entries + 1] = { frame = frame, height = defaultHeight }
        end
    end

    local old = barPlaceholders[groupIndex]
    if old then
        local ids = {}
        for spellID in pairs(old) do if not needed[spellID] then ids[#ids + 1] = spellID end end
        for _, spellID in ipairs(ids) do ReleaseBarPlaceholder(groupIndex, spellID) end
    end

    if #entries == 0 then return end
    local grow = groupData.grow or "DOWN"
    local isCenter = CDM.IsBarCenterGrow and CDM.IsBarCenterGrow(grow)

    if isCenter then
        local limit = groupData.wrapLimit or 2
        if limit < 2 then limit = 2 elseif limit > 5 then limit = 5 end
        local hSpacing = Pixel and Pixel.Snap and Pixel.Snap(groupData.hSpacing or 1) or (groupData.hSpacing or 1)
        local numRows = math.ceil(#entries / limit)
        local rowHeights = {}
        local rowCounts = {}
        for index, entry in ipairs(entries) do
            local row = math.floor((index - 1) / limit) + 1
            rowCounts[row] = (rowCounts[row] or 0) + 1
            rowHeights[row] = math.max(rowHeights[row] or 0, entry.height)
        end
        local rowOffsets = {}
        local totalHeight = 0
        for row = 1, numRows do
            rowOffsets[row] = totalHeight
            totalHeight = totalHeight + rowHeights[row]
            if row < numRows then totalHeight = totalHeight + spacing end
        end
        local containerWidth = limit * barWidth + (limit - 1) * hSpacing
        for index, entry in ipairs(entries) do
            local row = math.floor((index - 1) / limit) + 1
            local col = (index - 1) % limit
            local rowCount = rowCounts[row]
            local rowWidth = rowCount * barWidth + (rowCount - 1) * hSpacing
            local x = (containerWidth - rowWidth) / 2 + col * (barWidth + hSpacing)
            local y = rowOffsets[row]
            entry.frame:ClearAllPoints()
            if grow == "CENTER_DOWN" then
                entry.frame:SetPoint("TOPLEFT", container, "TOPLEFT", x, -y)
            else
                entry.frame:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", x, y)
            end
        end
        if Pixel and Pixel.SetSize then Pixel.SetSize(container, containerWidth, math.max(totalHeight, defaultHeight)) else container:SetSize(containerWidth, math.max(totalHeight, defaultHeight)) end
        return
    end

    local offset = 0
    for _, entry in ipairs(entries) do
        entry.frame:ClearAllPoints()
        if grow == "UP" then
            entry.frame:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, offset)
        else
            entry.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -offset)
        end
        offset = offset + entry.height + spacing
    end
    local totalHeight = math.max(defaultHeight, offset - spacing)
    if Pixel and Pixel.SetSize then Pixel.SetSize(container, barWidth, totalHeight) else container:SetSize(barWidth, totalHeight) end
end

local function StripAuraBorderSettings()
    local db = CDM.db
    if not db then return end

    local function CleanMap(map)
        if type(map) ~= "table" then return end
        for _, override in pairs(map) do
            if type(override) == "table" then
                override.auraBorderEnabled = nil
                override.auraBorderColor = nil
            end
        end
    end

    for _, groups in pairs(db.cooldownGroups or {}) do
        if type(groups) == "table" then
            for _, groupData in ipairs(groups) do
                if type(groupData) == "table" then CleanMap(groupData.spellOverrides) end
            end
        end
    end
    for _, map in pairs(db.ungroupedCooldownOverrides or {}) do CleanMap(map) end
end

local function MigrateLegacyAlwaysShow()
    local db = CDM.db
    if not db then return end
    for _, groups in pairs(db.buffGroups or {}) do
        if type(groups) == "table" then
            for _, groupData in ipairs(groups) do
                local map = groupData and groupData.spellOverrides
                if type(map) == "table" then
                    for _, override in pairs(map) do
                        if type(override) == "table" and override.placeholder then
                            if override.alwaysShow == nil then override.alwaysShow = true end
                            if override.desaturateWhenInactive == nil then override.desaturateWhenInactive = true end
                            override.placeholder = nil
                        end
                    end
                end
            end
        end
    end
end

if type(CDM.RefreshFrameVisuals) == "function" then
    hooksecurefunc(CDM, "RefreshFrameVisuals", function(_, frame)
        ApplyLayoutTextExtensions(frame)
    end)
end

if type(CDM.PositionBuffGroupFrames) == "function" then
    hooksecurefunc(CDM, "PositionBuffGroupFrames", function(_, groupIndex, frames)
        local sets = CDM.BuffGroupSets
        local groupData = sets and sets.groups and sets.groups[groupIndex]
        if groupData then
            for _, frame in ipairs(frames or {}) do ApplyBuffTextExtensions(frame, groupData) end
        end
        ApplyBuffAlwaysShow(groupIndex, frames)
    end)
end

if type(CDM.ApplyGroupStyleOverrides) == "function" then
    hooksecurefunc(CDM, "ApplyGroupStyleOverrides", function()
        local sets = CDM.BuffGroupSets
        if not sets or not sets.groups then return end
        CDM:ForEachActiveFrame({ VIEWERS.BUFF }, function(frame)
            local spellID = frame.cdmBuffCategorySpellID
            local groupIndex = spellID and sets.grouped and sets.grouped[spellID]
            local groupData = groupIndex and sets.groups[groupIndex]
            if groupData then ApplyBuffTextExtensions(frame, groupData) end
        end)
    end)
end

if type(CDM.ApplyBarStyle) == "function" then
    hooksecurefunc(CDM, "ApplyBarStyle", function(_, frame, _, _, _, _, groupData, spellOverride)
        ApplyBarTextExtensions(frame, groupData, spellOverride)
    end)
end

if type(CDM.PositionBarGroupFrames) == "function" then
    hooksecurefunc(CDM, "PositionBarGroupFrames", function(_, groupIndex, frames)
        ApplyBarAlwaysShow(groupIndex, frames)
    end)
end

CDM:RegisterRefreshCallback("unifiedBuffControls", function()
    StripAuraBorderSettings()
    MigrateLegacyAlwaysShow()
end, 29, { "CD_DATA", "BUFF_DATA", "BAR_DATA" })

C_Timer.After(0, function()
    StripAuraBorderSettings()
    MigrateLegacyAlwaysShow()
end)
