local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local function StripMap(map)
    local changed = false
    if type(map) ~= "table" then return changed end

    for _, override in pairs(map) do
        if type(override) == "table" then
            if override.auraBorderEnabled ~= nil then
                override.auraBorderEnabled = nil
                changed = true
            end
            if override.auraBorderColor ~= nil then
                override.auraBorderColor = nil
                changed = true
            end
        end
    end

    return changed
end

local function StripSavedSettings()
    local db = CDM.db
    if not db then return false end

    local changed = false
    for _, groups in pairs(db.cooldownGroups or {}) do
        if type(groups) == "table" then
            for _, groupData in ipairs(groups) do
                if type(groupData) == "table" and StripMap(groupData.spellOverrides) then
                    changed = true
                end
            end
        end
    end

    for _, map in pairs(db.ungroupedCooldownOverrides or {}) do
        if StripMap(map) then changed = true end
    end

    return changed
end

local function RestoreLegacyAuraBorder(frame)
    if not frame or not frame.cdmAuraBorderActive then return end

    if CDM.BORDER and CDM.BORDER.RestoreToCurrentBorderColor then
        CDM.BORDER:RestoreToCurrentBorderColor(frame)
    end
    frame.cdmAuraBorderActive = nil
end

if type(CDM.RefreshFrameVisuals) == "function" then
    hooksecurefunc(CDM, "RefreshFrameVisuals", function(_, frame)
        RestoreLegacyAuraBorder(frame)
    end)
end

CDM:RegisterRefreshCallback("removeLegacyAuraBorder", function()
    StripSavedSettings()
end, 1, { "CD_DATA" })

C_Timer.After(0, function()
    local changed = StripSavedSettings()
    if changed then
        CDM:Refresh("CD_DATA")
    end
end)
