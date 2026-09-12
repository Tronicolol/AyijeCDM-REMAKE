local Runtime = _G["KCDM"]
if not Runtime then return end

local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns and ns.ConfigUI
local Shared = ns and ns.GroupEditorShared
local L = Runtime.L
local CDM_C = Runtime.CONST or {}
if not API or not ns or not UI or not Shared then return end

local buildingUnifiedTextOverride = false
local lastBuffContext
local lastBarContext
local pendingBarPanels = setmetatable({}, { __mode = "k" })

local function FindGroupForMap(root, map)
    if type(root) ~= "table" or type(map) ~= "table" then return nil end
    for _, groups in pairs(root) do
        if type(groups) == "table" then
            for _, groupData in ipairs(groups) do
                if type(groupData) == "table" and groupData.spellOverrides == map then
                    return groupData
                end
            end
        end
    end
    return nil
end

local function IsUngroupedMap(root, map)
    if type(root) ~= "table" or type(map) ~= "table" then return false end
    for _, specMap in pairs(root) do
        if specMap == map then return true end
    end
    return false
end

local function ClassifyBuffMap(map)
    local db = CDM.db or {}
    local groupData = FindGroupForMap(db.buffGroups, map)
    if groupData then return "buff", groupData end
    if IsUngroupedMap(db.ungroupedBuffOverrides, map) then return "buff", nil end
    return nil, nil
end

local function FindBarGroupForMap(map)
    local db = CDM.db or {}
    return FindGroupForMap(db.barGroups, map)
end

if type(API.GetMergedBuffOverrideEntry) == "function" and not ns.cdmUnifiedBuffContextHooked then
    ns.cdmUnifiedBuffContextHooked = true
    local original = API.GetMergedBuffOverrideEntry
    API.GetMergedBuffOverrideEntry = function(self, overrideMap, spellID)
        local result = original(self, overrideMap, spellID)
        local kind, groupData = ClassifyBuffMap(overrideMap)
        if kind == "buff" then
            lastBuffContext = {
                map = overrideMap,
                spellID = spellID,
                entry = result,
                groupData = groupData,
            }
        end
        return result
    end
end

if type(API.ResolveBarOverrideEntry) == "function" and not ns.cdmUnifiedBarContextHooked then
    ns.cdmUnifiedBarContextHooked = true
    local original = API.ResolveBarOverrideEntry
    API.ResolveBarOverrideEntry = function(self, overrideMap, spellID)
        local result = original(self, overrideMap, spellID)
        lastBarContext = {
            map = overrideMap,
            spellID = spellID,
            entry = result,
            groupData = FindBarGroupForMap(overrideMap),
        }
        return result
    end
end

local function EnsureContextEntry(context)
    if not context or type(context.map) ~= "table" or not context.spellID then return nil end
    if Shared.EnsureResolvedOverrideEntry then
        local entry = Shared.EnsureResolvedOverrideEntry(context.map, context.spellID)
        context.entry = entry
        return entry
    end
    return nil
end

local function SaveBuffContext()
    Shared.SaveVisualRefresh("BUFF_DATA")
end

local function SaveBarContext()
    Shared.SaveVisualRefresh("BAR_DATA")
end

local function CreatePositionDropdown(parent, currentValue, onChange)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(180)
    dropdown:SetDefaultText(currentValue)
    UI.SetupPositionDropdown(dropdown, function() return currentValue end, function(value)
        currentValue = value
        dropdown:SetDefaultText(value)
        onChange(value)
    end)
    return dropdown
end

local function BuildUnifiedTextOverrideWidgets(rc, yOff, cfg)
    local existingOv = cfg.existingOv
    local ensureOv = cfg.ensureOv
    local save = cfg.save
    local fields = cfg.fields or {}
    local defaults = cfg.defaults or {}

    local cdSizeKey = fields.cdSize or "cooldownFontSize"
    local cdColorKey = fields.cdColor or "cooldownColor"
    local cdPosKey = fields.cdPos or "cooldownPosition"
    local cdXKey = fields.cdX or "cooldownOffsetX"
    local cdYKey = fields.cdY or "cooldownOffsetY"
    local hideCooldownKey = fields.hideCooldown or "hideCooldownTimer"

    local chargeSizeKey = fields.chargeSize or "chargeFontSize"
    local chargeColorKey = fields.chargeColor or "chargeColor"
    local chargePosKey = fields.chargePos or "chargePosition"
    local chargeXKey = fields.chargeX or "chargeOffsetX"
    local chargeYKey = fields.chargeY or "chargeOffsetY"
    local hideChargesKey = fields.hideCharges or "hideCharges"

    if cfg.showHeader then
        yOff = yOff - 10
        local header = rc:CreateFontString(nil, "ARTWORK", "KCDM_Font18")
        header:SetPoint("TOPLEFT", 0, yOff)
        header:SetText(L["Text Overrides"])
        header:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
        yOff = yOff - 34
    end

    local useTextOverride = existingOv and existingOv.textOverride == true
    buildingUnifiedTextOverride = true
    local overrideCheckbox = UI.CreateModernCheckbox(rc, L["Override Text Settings"], useTextOverride, function(checked)
        local override = ensureOv()
        if not override then return end
        override.textOverride = checked or nil
        save()
        if cfg.onToggle then cfg.onToggle(checked) end
    end)
    buildingUnifiedTextOverride = false
    overrideCheckbox:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 36

    if not useTextOverride then return yOff end

    local override = existingOv or {}
    local function Write(key, value)
        local entry = ensureOv()
        if not entry then return end
        entry[key] = value
        save()
    end

    local function WriteColor(key, r, g, b, a)
        local entry = ensureOv()
        if not entry then return end
        if cfg.colorAlpha then
            entry[key] = { r = r, g = g, b = b, a = a or 1 }
        else
            entry[key] = { r = r, g = g, b = b }
        end
        save()
    end

    local hideCooldown = override[hideCooldownKey] == true or override.hideCooldown == true or override.durationHidden == true
    buildingUnifiedTextOverride = true
    local hideCooldownCheckbox = UI.CreateModernCheckbox(rc, L["Hide Cooldown Timer"], hideCooldown, function(checked)
        local entry = ensureOv()
        if not entry then return end
        entry[hideCooldownKey] = checked or nil
        entry.hideCooldown = nil
        entry.durationHidden = nil
        save()
    end)
    buildingUnifiedTextOverride = false
    hideCooldownCheckbox:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 36

    local cooldownSize = Shared.CreateSlider(rc, L["Cooldown Size"], 6, 32, override[cdSizeKey] or defaults[cdSizeKey] or 12, function(value)
        Write(cdSizeKey, value)
    end)
    cooldownSize:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local cooldownColorLabel = rc:CreateFontString(nil, "OVERLAY", "KCDM_Font14")
    cooldownColorLabel:SetText(L["Cooldown Color"])
    cooldownColorLabel:SetPoint("TOPLEFT", 0, yOff)
    local cooldownColor = UI.CreateSimpleColorPicker(rc, override[cdColorKey] or defaults[cdColorKey] or { r = 1, g = 1, b = 1 }, function(r, g, b, a)
        WriteColor(cdColorKey, r, g, b, a)
    end, cfg.colorAlpha and true or false)
    cooldownColor:SetPoint("LEFT", cooldownColorLabel, "RIGHT", 6, 0)
    yOff = yOff - 30

    local cooldownPositionLabel = rc:CreateFontString(nil, "OVERLAY", "KCDM_Font14")
    cooldownPositionLabel:SetText(L["Cooldown Position"])
    cooldownPositionLabel:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 22
    local cooldownPosition = cfg.createDropdown(rc)
    cooldownPosition:SetWidth(180)
    cooldownPosition:SetPoint("TOPLEFT", 0, yOff)
    cooldownPosition:SetDefaultText(override[cdPosKey] or defaults[cdPosKey] or "CENTER")
    UI.SetupPositionDropdown(cooldownPosition,
        function() return override[cdPosKey] or defaults[cdPosKey] or "CENTER" end,
        function(value) Write(cdPosKey, value) end
    )
    yOff = yOff - 40

    local cooldownX = Shared.CreateSlider(rc, L["Cooldown X Offset"], -40, 40, override[cdXKey] or defaults[cdXKey] or 0, function(value)
        Write(cdXKey, value)
    end)
    cooldownX:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local cooldownY = Shared.CreateSlider(rc, L["Cooldown Y Offset"], -40, 40, override[cdYKey] or defaults[cdYKey] or 0, function(value)
        Write(cdYKey, value)
    end)
    cooldownY:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    buildingUnifiedTextOverride = true
    local hideChargesCheckbox = UI.CreateModernCheckbox(rc, L["Hide Charges"], override[hideChargesKey] == true, function(checked)
        Write(hideChargesKey, checked or nil)
    end)
    buildingUnifiedTextOverride = false
    hideChargesCheckbox:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 36

    local chargeSize = Shared.CreateSlider(rc, L["Charge Size"], 6, 32, override[chargeSizeKey] or defaults[chargeSizeKey] or 15, function(value)
        Write(chargeSizeKey, value)
    end)
    chargeSize:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local chargeColorLabel = rc:CreateFontString(nil, "OVERLAY", "KCDM_Font14")
    chargeColorLabel:SetText(L["Charge Color"])
    chargeColorLabel:SetPoint("TOPLEFT", 0, yOff)
    local chargeColor = UI.CreateSimpleColorPicker(rc, override[chargeColorKey] or defaults[chargeColorKey] or { r = 1, g = 1, b = 1 }, function(r, g, b, a)
        WriteColor(chargeColorKey, r, g, b, a)
    end, cfg.colorAlpha and true or false)
    chargeColor:SetPoint("LEFT", chargeColorLabel, "RIGHT", 6, 0)
    yOff = yOff - 30

    local chargePositionLabel = rc:CreateFontString(nil, "OVERLAY", "KCDM_Font14")
    chargePositionLabel:SetText(L["Charge Position"])
    chargePositionLabel:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 22
    local chargePosition = cfg.createDropdown(rc)
    chargePosition:SetWidth(180)
    chargePosition:SetPoint("TOPLEFT", 0, yOff)
    chargePosition:SetDefaultText(override[chargePosKey] or defaults[chargePosKey] or "BOTTOMRIGHT")
    UI.SetupPositionDropdown(chargePosition,
        function() return override[chargePosKey] or defaults[chargePosKey] or "BOTTOMRIGHT" end,
        function(value) Write(chargePosKey, value) end
    )
    yOff = yOff - 40

    local chargeX = Shared.CreateSlider(rc, L["Charge X Offset"], -40, 40, override[chargeXKey] or defaults[chargeXKey] or 0, function(value)
        Write(chargeXKey, value)
    end)
    chargeX:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local chargeY = Shared.CreateSlider(rc, L["Charge Y Offset"], -40, 40, override[chargeYKey] or defaults[chargeYKey] or 0, function(value)
        Write(chargeYKey, value)
    end)
    chargeY:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    return yOff
end

Shared.BuildTextOverrideWidgets = BuildUnifiedTextOverrideWidgets

local function GetBarDefaults(context)
    local groupData = context and context.groupData
    local db = CDM.db or {}
    return {
        durationFontSize = (groupData and groupData.durationFontSize) or db.buffBarDurationFontSize or 15,
        durationColor = (groupData and groupData.durationColor) or db.buffBarDurationColor or { r = 1, g = 1, b = 1, a = 1 },
        durationPosition = (groupData and groupData.durationPosition) or db.buffBarDurationPosition or "RIGHT",
        durationOffsetX = (groupData and groupData.durationOffsetX) or db.buffBarDurationOffsetX or 0,
        durationOffsetY = (groupData and groupData.durationOffsetY) or db.buffBarDurationOffsetY or 0,
        applicationsFontSize = (groupData and groupData.applicationsFontSize) or db.buffBarApplicationsFontSize or 15,
        applicationsColor = (groupData and groupData.applicationsColor) or db.buffBarApplicationsColor or { r = 1, g = 1, b = 1, a = 1 },
        applicationsPosition = (groupData and groupData.applicationsPosition) or db.buffBarApplicationsPosition or "CENTER",
        applicationsOffsetX = (groupData and groupData.applicationsOffsetX) or db.buffBarApplicationsOffsetX or 0,
        applicationsOffsetY = (groupData and groupData.applicationsOffsetY) or db.buffBarApplicationsOffsetY or 0,
    }
end

local function AppendBarTextControls(parent, context)
    if not parent or parent.cdmUnifiedBarTextControls or not context or not context.map then return end
    parent.cdmUnifiedBarTextControls = true

    local baseHeight = parent:GetHeight()
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(baseHeight - 14))
    container:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local y = 0
    local header = container:CreateFontString(nil, "ARTWORK", "KCDM_Font18")
    header:SetPoint("TOPLEFT", 0, y)
    header:SetText(L["Text Overrides"])
    header:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
    y = y - 34

    local function GetEntry()
        if type(API.ResolveBarOverrideEntry) == "function" then
            return API:ResolveBarOverrideEntry(context.map, context.spellID)
        end
        return context.entry
    end

    local function Ensure()
        local entry = EnsureContextEntry(context)
        return entry
    end

    local function Save()
        SaveBarContext()
    end

    local initial = GetEntry() or {}
    local overrideCheckbox
    local fieldsFrame = CreateFrame("Frame", nil, container)
    fieldsFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y - 36)
    fieldsFrame:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    local fullFieldHeight = 560
    local collapsedHeight = 76

    local function UpdateExpandedState(enabled)
        fieldsFrame:SetShown(enabled)
        local extra = enabled and (collapsedHeight + fullFieldHeight) or collapsedHeight
        container:SetHeight(extra)
        parent:SetHeight(baseHeight + extra)
    end

    buildingUnifiedTextOverride = true
    overrideCheckbox = UI.CreateModernCheckbox(container, L["Override Text Settings"], initial.textOverride == true, function(checked)
        local entry = Ensure()
        if not entry then return end
        entry.textOverride = checked or nil
        Save()
        UpdateExpandedState(checked)
    end)
    buildingUnifiedTextOverride = false
    overrideCheckbox:SetPoint("TOPLEFT", 0, y)

    local fy = 0
    local defaults = GetBarDefaults(context)
    local function Current() return GetEntry() or {} end
    local function Write(key, value)
        local entry = Ensure()
        if not entry then return end
        entry[key] = value
        Save()
    end
    local function WriteColor(key, r, g, b, a)
        Write(key, { r = r, g = g, b = b, a = a or 1 })
    end

    buildingUnifiedTextOverride = true
    local hideCooldown = UI.CreateModernCheckbox(fieldsFrame, L["Hide Cooldown Timer"], initial.hideCooldownTimer == true or initial.durationHidden == true, function(checked)
        local entry = Ensure()
        if not entry then return end
        entry.hideCooldownTimer = checked or nil
        entry.durationHidden = nil
        Save()
    end)
    buildingUnifiedTextOverride = false
    hideCooldown:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 36

    local cdSize = Shared.CreateSlider(fieldsFrame, L["Cooldown Size"], 6, 32, initial.durationFontSize or defaults.durationFontSize, function(value) Write("durationFontSize", value) end)
    cdSize:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 50

    local cdColorLabel = fieldsFrame:CreateFontString(nil, "OVERLAY", "KCDM_Font14")
    cdColorLabel:SetText(L["Cooldown Color"])
    cdColorLabel:SetPoint("TOPLEFT", 0, fy)
    local cdColor = UI.CreateSimpleColorPicker(fieldsFrame, initial.durationColor or defaults.durationColor, function(r, g, b, a) WriteColor("durationColor", r, g, b, a) end, true)
    cdColor:SetPoint("LEFT", cdColorLabel, "RIGHT", 6, 0)
    fy = fy - 30

    local cdPosLabel = fieldsFrame:CreateFontString(nil, "OVERLAY", "KCDM_Font14")
    cdPosLabel:SetText(L["Cooldown Position"])
    cdPosLabel:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 22
    local cdPosValue = initial.durationPosition or defaults.durationPosition
    local cdPos = CreatePositionDropdown(fieldsFrame, cdPosValue, function(value) Write("durationPosition", value) end)
    cdPos:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 40

    local cdX = Shared.CreateSlider(fieldsFrame, L["Cooldown X Offset"], -60, 60, initial.durationOffsetX or defaults.durationOffsetX, function(value) Write("durationOffsetX", value) end)
    cdX:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 50
    local cdY = Shared.CreateSlider(fieldsFrame, L["Cooldown Y Offset"], -40, 40, initial.durationOffsetY or defaults.durationOffsetY, function(value) Write("durationOffsetY", value) end)
    cdY:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 50

    buildingUnifiedTextOverride = true
    local hideCharges = UI.CreateModernCheckbox(fieldsFrame, L["Hide Charges"], initial.hideCharges == true, function(checked) Write("hideCharges", checked or nil) end)
    buildingUnifiedTextOverride = false
    hideCharges:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 36

    local chargeSize = Shared.CreateSlider(fieldsFrame, L["Charge Size"], 6, 32, initial.applicationsFontSize or defaults.applicationsFontSize, function(value) Write("applicationsFontSize", value) end)
    chargeSize:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 50

    local chargeColorLabel = fieldsFrame:CreateFontString(nil, "OVERLAY", "KCDM_Font14")
    chargeColorLabel:SetText(L["Charge Color"])
    chargeColorLabel:SetPoint("TOPLEFT", 0, fy)
    local chargeColor = UI.CreateSimpleColorPicker(fieldsFrame, initial.applicationsColor or defaults.applicationsColor, function(r, g, b, a) WriteColor("applicationsColor", r, g, b, a) end, true)
    chargeColor:SetPoint("LEFT", chargeColorLabel, "RIGHT", 6, 0)
    fy = fy - 30

    local chargePosLabel = fieldsFrame:CreateFontString(nil, "OVERLAY", "KCDM_Font14")
    chargePosLabel:SetText(L["Charge Position"])
    chargePosLabel:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 22
    local chargePosValue = initial.applicationsPosition or defaults.applicationsPosition
    local chargePos = CreatePositionDropdown(fieldsFrame, chargePosValue, function(value) Write("applicationsPosition", value) end)
    chargePos:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 40

    local chargeX = Shared.CreateSlider(fieldsFrame, L["Charge X Offset"], -60, 60, initial.applicationsOffsetX or defaults.applicationsOffsetX, function(value) Write("applicationsOffsetX", value) end)
    chargeX:SetPoint("TOPLEFT", 0, fy)
    fy = fy - 50
    local chargeY = Shared.CreateSlider(fieldsFrame, L["Charge Y Offset"], -40, 40, initial.applicationsOffsetY or defaults.applicationsOffsetY, function(value) Write("applicationsOffsetY", value) end)
    chargeY:SetPoint("TOPLEFT", 0, fy)

    fullFieldHeight = math.max(520, math.abs(fy) + 60)
    UpdateExpandedState(initial.textOverride == true)
end

local function ScheduleBarTextControls(parent, context)
    if not parent or pendingBarPanels[parent] then return end
    pendingBarPanels[parent] = true
    local snapshot = {
        map = context.map,
        spellID = context.spellID,
        entry = context.entry,
        groupData = context.groupData,
    }
    C_Timer.After(0, function()
        pendingBarPanels[parent] = nil
        if not parent:GetParent() then return end
        AppendBarTextControls(parent, snapshot)
    end)
end

local originalCreateModernCheckbox = UI.CreateModernCheckbox
UI.CreateModernCheckbox = function(parent, label, checked, onChange, ...)
    if buildingUnifiedTextOverride then
        return originalCreateModernCheckbox(parent, label, checked, onChange, ...)
    end

    if label == L["Aura Border Color"] then
        local hidden = originalCreateModernCheckbox(parent, label, false, function() end, ...)
        hidden:Hide()
        return hidden
    end

    if label == L["Hide Cooldown Timer"] and lastBuffContext and lastBuffContext.map then
        local context = lastBuffContext
        local current = context.entry or {}
        local alwaysShow = current.alwaysShow == true
        local row = originalCreateModernCheckbox(parent, L["Always Show"], alwaysShow, function(value)
            local entry = EnsureContextEntry(context)
            if not entry then return end
            entry.alwaysShow = value or nil
            entry.placeholder = nil
            SaveBuffContext()
        end, ...)
        return row
    end

    if label == L["Show Placeholder"] and lastBuffContext and lastBuffContext.map then
        local context = lastBuffContext
        local current = context.entry or {}
        local row = originalCreateModernCheckbox(parent, L["Desaturate when inactive"], current.desaturateWhenInactive == true, function(value)
            local entry = EnsureContextEntry(context)
            if not entry then return end
            entry.desaturateWhenInactive = value or nil
            entry.placeholder = nil
            SaveBuffContext()
        end, ...)
        C_Timer.After(0, function()
            if row.checkbox and row.checkbox.Enable then row.checkbox:Enable() end
            if row.label then UI.SetTextWhite(row.label) end
        end)
        return row
    end

    if label == L["Hide Duration"] and lastBarContext and lastBarContext.map then
        local context = {
            map = lastBarContext.map,
            spellID = lastBarContext.spellID,
            entry = lastBarContext.entry,
            groupData = lastBarContext.groupData,
        }
        local current = context.entry or {}
        local canAlwaysShow = context.groupData ~= nil

        local row = originalCreateModernCheckbox(parent, L["Always Show"], canAlwaysShow and current.alwaysShow == true or false, function(value)
            if not canAlwaysShow then return end
            local entry = EnsureContextEntry(context)
            if not entry then return end
            entry.alwaysShow = value or nil
            SaveBarContext()
        end, ...)

        local desaturate = originalCreateModernCheckbox(parent, L["Desaturate when inactive"], canAlwaysShow and current.desaturateWhenInactive == true or false, function(value)
            if not canAlwaysShow then return end
            local entry = EnsureContextEntry(context)
            if not entry then return end
            entry.desaturateWhenInactive = value or nil
            SaveBarContext()
        end)
        desaturate:SetPoint("LEFT", row, "LEFT", 170, 0)

        if not canAlwaysShow then
            if row.checkbox and row.checkbox.Disable then row.checkbox:Disable() end
            if desaturate.checkbox and desaturate.checkbox.Disable then desaturate.checkbox:Disable() end
            if row.label then UI.SetTextMuted(row.label) end
            if desaturate.label then UI.SetTextMuted(desaturate.label) end
        end

        ScheduleBarTextControls(parent, context)
        return row
    end

    return originalCreateModernCheckbox(parent, label, checked, onChange, ...)
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

StripAuraBorderSettings()
