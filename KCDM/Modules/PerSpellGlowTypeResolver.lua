local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Glow then return end

local Glow = CDM.Glow
if Glow.cdmPerSpellGlowTypeResolverInstalled then return end

local originalRequestBuffGlow = Glow.RequestBuffGlow
if type(originalRequestBuffGlow) ~= "function" then return end

local VALID_GLOW_TYPES = {
    pixel = true,
    autocast = true,
    button = true,
    proc = true,
}

local function HasGlowTypeOverride(groupData, spellID)
    if not groupData or not spellID or not CDM.GetCooldownGroupSpellOverride then
        return false
    end

    local override = CDM.GetCooldownGroupSpellOverride(groupData, spellID)
    local glowType = override and override.glowTypeOverride
    return glowType ~= nil and VALID_GLOW_TYPES[glowType] == true
end

local function ResolveGroupedGlowSpellID(frame)
    local sets = CDM.CooldownGroupSets
    if not sets or not sets.groups or not sets.cooldownIDGrouped then return end

    local cooldownID = frame and frame.cooldownID
    if not cooldownID then return end

    local match = sets.cooldownIDGrouped[cooldownID]
    if not match or not match.groupIdx then return end

    local groupData = sets.groups[match.groupIdx]
    if not groupData then return end

    if HasGlowTypeOverride(groupData, match.storedID) then
        frame.cdmCdGroupSpellID = match.storedID
        return
    end

    local seen = {}
    local function TrySpellID(spellID)
        if not spellID or seen[spellID] then return nil end
        seen[spellID] = true
        if HasGlowTypeOverride(groupData, spellID) then
            return spellID
        end
        return nil
    end

    local resolvedID = TrySpellID(frame.cdmCdGroupSpellID)

    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
    if not resolvedID and info then
        resolvedID = TrySpellID(info.overrideTooltipSpellID)
            or TrySpellID(info.overrideSpellID)
            or TrySpellID(info.spellID)
    end

    if not resolvedID then
        resolvedID = TrySpellID(frame.cdmBuffCategorySpellID)
    end

    if not resolvedID and CDM.GetSpellIDCandidates then
        for _, spellID in ipairs(CDM:GetSpellIDCandidates(frame)) do
            resolvedID = TrySpellID(spellID)
            if resolvedID then break end
        end
    end

    if resolvedID then
        match.storedID = resolvedID
        frame.cdmCdGroupSpellID = resolvedID
    end
end

Glow.RequestBuffGlow = function(self, frame, producerToken, enabled, overrideColor, sourceID)
    if frame then
        ResolveGroupedGlowSpellID(frame)
    end

    return originalRequestBuffGlow(self, frame, producerToken, enabled, overrideColor, sourceID)
end

Glow.cdmPerSpellGlowTypeResolverInstalled = true
