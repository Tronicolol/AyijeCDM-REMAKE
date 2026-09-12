local Runtime = _G["KCDM"]
if not Runtime then return end

local CDM = Runtime
if not CDM.db then return end

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

EnsureOverrideMaps()

if CDM.RegisterRefreshCallback then
    CDM:RegisterRefreshCallback("unifiedOptionsEnsureMaps", EnsureOverrideMaps, 2, { "BUFF_DATA", "BAR_DATA" })
end

C_Timer.After(0, EnsureOverrideMaps)
