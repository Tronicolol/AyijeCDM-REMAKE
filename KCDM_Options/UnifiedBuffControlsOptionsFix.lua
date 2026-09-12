local Runtime = _G["KCDM"]
if not Runtime then return end

local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns and ns.ConfigUI
local Shared = ns and ns.GroupEditorShared
local L = Runtime.L
if not API or not ns or not UI or not Shared then return end

local function EnsureOverrideMaps()
    local db = CDM.db
    if type(db) ~= "table" then return end

    local function EnsureGroupRoot(groupKey, ungroupedKey)
        local root = db[groupKey]
        if type(root) ~= "table" then return end

        if type(db[ungroupedKey]) ~= "table" then
            db[ungroupedKey] = {}
        end

        for specID, groups in pairs(root) do
            if type(groups) == "table" then
                if type(db[ungroupedKey][specID]) ~= "table" then
                    db[ungroupedKey][specID] = {}
                end

                for _, groupData in ipairs(groups) do
                    if type(groupData) == "table" and type(groupData.spellOverrides) ~= "table" then
                        groupData.spellOverrides = {}
                    end
                end
            end
        end
    end

    EnsureGroupRoot("buffGroups", "ungroupedBuffOverrides")
    EnsureGroupRoot("barGroups", "ungroupedBarOverrides")

    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex)
    if specID then
        db.ungroupedBuffOverrides = db.ungroupedBuffOverrides or {}
        db.ungroupedBarOverrides = db.ungroupedBarOverrides or {}
        db.ungroupedBuffOverrides[specID] = db.ungroupedBuffOverrides[specID] or {}
        db.ungroupedBarOverrides[specID] = db.ungroupedBarOverrides[specID] or {}
    end
end

local function FindGroupForMap(root, overrideMap)
    if type(root) ~= "table" or type(overrideMap) ~= "table" then return nil end

    for _, groups in pairs(root) do
        if type(groups) == "table" then
            for _, groupData in ipairs(groups) do
                if type(groupData) == "table" and groupData.spellOverrides == overrideMap then
                    return groupData
                end
            end
        end
    end

    return nil
end

local function NowMs()
    if debugprofilestop then return debugprofilestop() end
    return (GetTime and GetTime() or 0) * 1000
end

local function IsFresh(context)
    return context and context.at and (NowMs() - context.at) < 1000
end

EnsureOverrideMaps()

if CDM.RegisterRefreshCallback then
    CDM:RegisterRefreshCallback("unifiedOptionsEnsureMaps", EnsureOverrideMaps, 2, { "BUFF_DATA", "BAR_DATA" })
end

local buffContext
if type(API.GetMergedBuffOverrideEntry) == "function" then
    local previousGetMergedBuffOverrideEntry = API.GetMergedBuffOverrideEntry
    API.GetMergedBuffOverrideEntry = function(self, overrideMap, spellID)
        local result = previousGetMergedBuffOverrideEntry(self, overrideMap, spellID)
        buffContext = {
            map = overrideMap,
            spellID = spellID,
            entry = result,
            groupData = FindGroupForMap(CDM.db and CDM.db.buffGroups, overrideMap),
            at = NowMs(),
        }
        return result
    end
end

local barContext
if type(API.ResolveBarOverrideEntry) == "function" then
    local previousResolveBarOverrideEntry = API.ResolveBarOverrideEntry
    API.ResolveBarOverrideEntry = function(self, overrideMap, spellID)
        local result = previousResolveBarOverrideEntry(self, overrideMap, spellID)
        barContext = {
            map = overrideMap,
            spellID = spellID,
            entry = result,
            groupData = FindGroupForMap(CDM.db and CDM.db.barGroups, overrideMap),
            at = NowMs(),
        }
        return result
    end
end

local insideUnifiedTextBuilder = false
local previousBuildTextOverrideWidgets = Shared.BuildTextOverrideWidgets

Shared.BuildTextOverrideWidgets = function(rc, yOff, cfg)
    local fields = cfg and cfg.fields or {}
    local isBuffOverride = fields.chargeSize == "countFontSize"
        or fields.chargePos == "countPosition"
        or fields.chargeX == "countOffsetX"

    if isBuffOverride and IsFresh(buffContext) and buffContext.groupData then
        local existing = cfg.existingOv or buffContext.entry or {}

        local alwaysShow = UI.CreateModernCheckbox(rc, L["Always Show"], existing.alwaysShow == true, function(checked)
            local entry = cfg.ensureOv and cfg.ensureOv()
            if not entry then return end
            entry.alwaysShow = checked or nil
            entry.placeholder = nil
            if cfg.save then cfg.save() end
        end)
        alwaysShow:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 36

        local desaturate = UI.CreateModernCheckbox(rc, L["Desaturate when inactive"], existing.desaturateWhenInactive == true, function(checked)
            local entry = cfg.ensureOv and cfg.ensureOv()
            if not entry then return end
            entry.desaturateWhenInactive = checked or nil
            entry.placeholder = nil
            if cfg.save then cfg.save() end
        end)
        desaturate:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 36
    end

    insideUnifiedTextBuilder = true
    local ok, result = pcall(previousBuildTextOverrideWidgets, rc, yOff, cfg)
    insideUnifiedTextBuilder = false

    if ok then return result end
    error(result)
end

local previousCreateModernCheckbox = UI.CreateModernCheckbox
UI.CreateModernCheckbox = function(parent, label, checked, onChange, ...)
    if not insideUnifiedTextBuilder then
        if label == L["Hide Cooldown Timer"] and IsFresh(buffContext) then
            local hidden = previousCreateModernCheckbox(parent, label, checked, onChange, ...)
            hidden:Hide()
            return hidden
        end

        if label == L["Show Placeholder"] and IsFresh(buffContext) then
            local hidden = previousCreateModernCheckbox(parent, label, checked, onChange, ...)
            hidden:Hide()
            return hidden
        end
    end

    return previousCreateModernCheckbox(parent, label, checked, onChange, ...)
end

-- Keep bar context warm even when a spell has never had an override before.
-- The original unified options layer consumes this context when Bars creates
-- its legacy "Hide Duration" row, replacing it with Always Show / Desaturate
-- and appending the Text Overrides block.
C_Timer.After(0, EnsureOverrideMaps)
