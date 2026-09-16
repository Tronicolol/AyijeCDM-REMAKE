local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

-- Diagnostic only. Does not change saved settings.
-- Usage: /kcdmauramapdiag while Show Aura Overlay + Aura Glow are enabled.

local function Accessible(value)
    return value == nil or not canaccessvalue or canaccessvalue(value)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

local function SafeFrameMethod(frame, methodName)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then return nil end
    return SafeCall(method, frame)
end

local function F(value)
    if value == nil then return "-" end
    if not Accessible(value) then return "SECRET" end
    if type(value) == "boolean" then return value and "1" or "0" end
    return tostring(value)
end

local function EntryFlags(entry)
    if type(entry) ~= "table" then return "-" end
    return string.format(
        "show=%s aura=%s glow=%s ready=%s",
        F(entry.showAuraOverlay), F(entry.auraOverlay),
        F(entry.auraGlowEnabled), F(entry.readyGlowEnabled)
    )
end

local function AddID(list, seen, value)
    if not Accessible(value) or type(value) ~= "number" or value <= 0 or seen[value] then return end
    seen[value] = true
    list[#list + 1] = value
end

local function AddVariants(list, seen, spellID)
    AddID(list, seen, spellID)
    if type(CDM.ForEachSpellMatchCandidate) == "function" and type(spellID) == "number" then
        CDM:ForEachSpellMatchCandidate(spellID, function(candidate)
            AddID(list, seen, candidate)
        end)
    end
end

local function GetInfo(frame)
    local info = SafeFrameMethod(frame, "GetCooldownInfo") or frame.cooldownInfo
    local cooldownID = frame.cooldownID
    if type(cooldownID) == "number"
       and C_CooldownViewer
       and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function" then
        local viewerInfo = SafeCall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if type(viewerInfo) == "table" then
            info = viewerInfo
        end
    end
    return info
end

local function GetRelevantIDs(frame, info)
    local ids, seen = {}, {}
    AddVariants(ids, seen, SafeFrameMethod(frame, "GetSpellID"))
    AddVariants(ids, seen, SafeFrameMethod(frame, "GetBaseSpellID"))

    if type(info) == "table" then
        AddVariants(ids, seen, info.overrideTooltipSpellID)
        AddVariants(ids, seen, info.overrideSpellID)
        AddVariants(ids, seen, info.spellID)
        if type(info.linkedSpellIDs) == "table" then
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                AddVariants(ids, seen, linkedID)
            end
        end
    end

    table.sort(ids)
    return ids
end

local function PrintOverrideMap(prefix, overrideMap, ids)
    if type(overrideMap) ~= "table" then
        print("|cffd8c67a[KCDM-MAP]|r " .. prefix .. " map=-")
        return
    end

    local found = false
    for _, id in ipairs(ids) do
        local direct = overrideMap[id]
        if type(direct) == "table" then
            found = true
            print(string.format("|cffd8c67a[KCDM-MAP]|r %s direct[%d] %s", prefix, id, EntryFlags(direct)))
        end
    end

    if not found then
        print("|cffd8c67a[KCDM-MAP]|r " .. prefix .. " directRelevant=NONE")
    end

    local enabled = {}
    for key, entry in pairs(overrideMap) do
        if type(key) == "number" and type(entry) == "table"
           and (entry.showAuraOverlay ~= nil or entry.auraGlowEnabled or entry.readyGlowEnabled) then
            enabled[#enabled + 1] = key
        end
    end
    table.sort(enabled)

    local parts = {}
    for _, key in ipairs(enabled) do
        parts[#parts + 1] = tostring(key) .. "{" .. EntryFlags(overrideMap[key]) .. "}"
    end
    print("|cffd8c67a[KCDM-MAP]|r " .. prefix .. " configured=" .. (#parts > 0 and table.concat(parts, ",") or "NONE"))
end

local function GetCategories()
    if type(CDM.ALL_VIEWER_CATEGORIES) == "table" then
        return CDM.ALL_VIEWER_CATEGORIES
    end

    local categories = {}
    local evc = Enum and Enum.CooldownViewerCategory
    if evc then
        if evc.Essential ~= nil then categories[#categories + 1] = evc.Essential end
        if evc.Utility ~= nil then categories[#categories + 1] = evc.Utility end
        if evc.TrackedBuff ~= nil then categories[#categories + 1] = evc.TrackedBuff end
        if evc.TrackedBar ~= nil then categories[#categories + 1] = evc.TrackedBar end
    end
    return categories
end

local function PrintCategoryMembership(cooldownID, info)
    print("|cffd8c67a[KCDM-MAP]|r infoCategory=" .. F(info and info.category))

    if not C_CooldownViewer or type(C_CooldownViewer.GetCooldownViewerCategorySet) ~= "function" then
        print("|cffd8c67a[KCDM-MAP]|r categorySets=UNAVAILABLE")
        return
    end

    local any = false
    for _, category in ipairs(GetCategories()) do
        local ids = SafeCall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
        local contains = false
        local count = type(ids) == "table" and #ids or 0
        if type(ids) == "table" then
            for _, id in ipairs(ids) do
                if id == cooldownID then
                    contains = true
                    any = true
                    break
                end
            end
        end
        print(string.format(
            "|cffd8c67a[KCDM-MAP]|r category[%s] contains=%s count=%d",
            F(category), F(contains), count
        ))
    end

    print("|cffd8c67a[KCDM-MAP]|r categoryAny=" .. F(any))
end

local function PrintFrame(frame, viewerName, specID, compact)
    local equipSlot = SafeFrameMethod(frame, "GetEquipSlot")
    if not Accessible(equipSlot) or type(equipSlot) ~= "number" or equipSlot <= 0 then return end

    local info = GetInfo(frame)
    local ids = GetRelevantIDs(frame, info)
    local cooldownID = frame.cooldownID

    local idParts = {}
    for _, id in ipairs(ids) do
        idParts[#idParts + 1] = tostring(id)
    end

    print(string.format(
        "|cffd8c67a[KCDM-MAP]|r FRAME viewer=%s slot=%s cdid=%s frameSID=%s info[spell=%s override=%s tooltip=%s] ids=%s",
        tostring(viewerName), F(equipSlot), F(cooldownID), F(SafeFrameMethod(frame, "GetSpellID")),
        F(info and info.spellID), F(info and info.overrideSpellID), F(info and info.overrideTooltipSpellID),
        #idParts > 0 and table.concat(idParts, ",") or "NONE"
    ))

    local runtimeEntry = type(CDM._auraOverlayEnabled) == "table" and CDM._auraOverlayEnabled[cooldownID] or nil
    print("|cffd8c67a[KCDM-MAP]|r runtimeEntry " .. EntryFlags(runtimeEntry))
    PrintCategoryMembership(cooldownID, info)

    if compact then return end

    local builtMap = type(CDM._BuildAuraOverlaySpellMap) == "function" and CDM:_BuildAuraOverlaySpellMap(specID) or nil
    local builtFound = false
    if type(builtMap) == "table" then
        for _, id in ipairs(ids) do
            local entry = builtMap[id]
            if type(entry) == "table" then
                builtFound = true
                print(string.format("|cffd8c67a[KCDM-MAP]|r built[%d] %s", id, EntryFlags(entry)))
            end
        end
    end
    if not builtFound then
        print("|cffd8c67a[KCDM-MAP]|r builtRelevant=NONE")
    end

    local ungrouped = CDM.db and CDM.db.ungroupedCooldownOverrides and CDM.db.ungroupedCooldownOverrides[specID]
    PrintOverrideMap("ungrouped", ungrouped, ids)

    local sets = CDM.CooldownGroupSets
    local groups = sets and sets.groups
    if type(groups) == "table" then
        for groupIndex, group in ipairs(groups) do
            if type(group) == "table" and type(group.spellOverrides) == "table" then
                PrintOverrideMap("group" .. groupIndex, group.spellOverrides, ids)
            end
        end
    end

    if type(CDM.GetUngroupedCooldownOverride) == "function" then
        for _, id in ipairs(ids) do
            local resolved = CDM:GetUngroupedCooldownOverride(id, specID)
            if type(resolved) == "table" then
                print(string.format("|cffd8c67a[KCDM-MAP]|r resolvedUngrouped[%d] %s", id, EntryFlags(resolved)))
            end
        end
    end
end

local function ForEachEquippedFrame(fn)
    local viewers = (CDM.CONST and CDM.CONST.COOLDOWN_VIEWER_NAMES) or {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
    }

    if type(CDM.ForEachActiveFrame) ~= "function" then return false end

    local found = false
    CDM:ForEachActiveFrame(viewers, function(frame, viewerName)
        local equipSlot = SafeFrameMethod(frame, "GetEquipSlot")
        if Accessible(equipSlot) and type(equipSlot) == "number" and equipSlot > 0 then
            found = true
            fn(frame, viewerName)
        end
    end)
    return found
end

SLASH_KCDMAURAMAPDIAG1 = "/kcdmauramapdiag"
SlashCmdList.KCDMAURAMAPDIAG = function()
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex) or nil
    local dataReady = type(CDM.IsCooldownViewerDataReady) == "function" and CDM:IsCooldownViewerDataReady() or nil
    print("|cffd8c67a[KCDM-MAP]|r START spec=" .. F(specID) .. " dataReady=" .. F(dataReady))

    local found = ForEachEquippedFrame(function(frame, viewerName)
        PrintFrame(frame, viewerName, specID, false)
    end)

    if not found then
        print("|cffd8c67a[KCDM-MAP]|r NO_EQUIPPED_ITEM_FRAMES")
        print("|cffd8c67a[KCDM-MAP]|r END")
        return
    end

    print("|cffd8c67a[KCDM-MAP]|r FORCE_REFRESH")
    if type(CDM.MarkSpecDataDirty) == "function" then
        CDM:MarkSpecDataDirty()
    end
    if type(CDM.RefreshSpecData) == "function" then
        CDM:RefreshSpecData()
    end

    ForEachEquippedFrame(function(frame, viewerName)
        PrintFrame(frame, viewerName, specID, true)
    end)

    print("|cffd8c67a[KCDM-MAP]|r END")
end
