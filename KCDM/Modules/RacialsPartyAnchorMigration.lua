local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local REMOVED_KEYS = {
    "racialsUsePartyFrame",
    "racialsPartyFrameSide",
    "racialsPartyFrameOffsetX",
    "racialsPartyFrameOffsetY",
    "racialsRaidFrameAnchorPoint",
    "racialsRaidFrameRelativePoint",
    "racialsRaidFrameOffsetX",
    "racialsRaidFrameOffsetY",
}

local function ClearPartyAnchorSettings(profile)
    if type(profile) ~= "table" then return end

    for _, key in ipairs(REMOVED_KEYS) do
        rawset(profile, key, nil)
    end
end

local function ClearSavedPartyAnchorSettings()
    ClearPartyAnchorSettings(CDM.db)

    if KCDMDB and type(KCDMDB.profiles) == "table" then
        for _, profile in pairs(KCDMDB.profiles) do
            ClearPartyAnchorSettings(profile)
        end
    end
end

ClearSavedPartyAnchorSettings()

local originalOnRacialsProfileApplied = CDM.OnRacialsProfileApplied
if type(originalOnRacialsProfileApplied) == "function" then
    CDM.OnRacialsProfileApplied = function(...)
        ClearPartyAnchorSettings(CDM.db)
        return originalOnRacialsProfileApplied(...)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, _, loadedAddon)
    if loadedAddon ~= AddonName then return end

    ClearSavedPartyAnchorSettings()
    self:UnregisterEvent("ADDON_LOADED")
end)
