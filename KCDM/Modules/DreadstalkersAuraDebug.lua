local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
}

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

local function SpellName(spellID)
    if not Accessible(spellID) or type(spellID) ~= "number" or not C_Spell or type(C_Spell.GetSpellName) ~= "function" then
        return "-"
    end
    local name = SafeCall(C_Spell.GetSpellName, spellID)
    if not Accessible(name) then return "SECRET" end
    return name or "-"
end

local function LinkedIDs(info)
    if type(info) ~= "table" or not Accessible(info) then return "-" end
    local linked = info.linkedSpellIDs
    if type(linked) ~= "table" or not Accessible(linked) then return "-" end

    local parts = {}
    for _, id in ipairs(linked) do
        parts[#parts + 1] = F(id)
    end
    return #parts > 0 and table.concat(parts, ",") or "-"
end

local function EntryFlags(entry)
    if type(entry) ~= "table" then return "-" end
    return string.format(
        "overlay=%s glow=%s lastAura=%s",
        F(entry.auraOverlay),
        F(entry.auraGlowEnabled),
        "-"
    )
end

local function PrintFrame(frame, viewerName)
    if not frame then return false end

    local info = SafeFrameMethod(frame, "GetCooldownInfo") or frame.cooldownInfo
    if type(info) ~= "table" or not Accessible(info) then
        info = nil
    end

    local sid = SafeFrameMethod(frame, "GetSpellID")
    local baseSID = SafeFrameMethod(frame, "GetBaseSpellID")
    local cdid = frame.cooldownID

    local auraData = SafeFrameMethod(frame, "GetAuraDataCached")
    if type(auraData) ~= "table" or not Accessible(auraData) then
        auraData = nil
    end

    local auraSID = auraData and auraData.spellId or nil
    local auraID = auraData and auraData.auraInstanceID or nil
    local auraName = auraData and auraData.name or nil
    local auraUnit = SafeFrameMethod(frame, "GetAuraDataUnit")

    local entry = type(CDM._auraOverlayEnabled) == "table" and CDM._auraOverlayEnabled[cdid] or nil

    local relevant = entry ~= nil or auraData ~= nil or frame.cdmLastAuraActive == true
    if viewerName == "BuffIconCooldownViewer" then
        relevant = auraData ~= nil
    end
    if not relevant then return false end

    print(string.format(
        "|cffd8c67a[KCDM-DREAD]|r viewer=%s cdid=%s sid=%s(%s) base=%s(%s) info[s=%s(%s) ov=%s(%s) tip=%s(%s) linked=%s] aura[s=%s(%s) id=%s name=%s unit=%s] flags[wasAura=%s useAura=%s lastAura=%s] entry[%s]",
        tostring(viewerName), F(cdid),
        F(sid), SpellName(sid),
        F(baseSID), SpellName(baseSID),
        F(info and info.spellID), SpellName(info and info.spellID),
        F(info and info.overrideSpellID), SpellName(info and info.overrideSpellID),
        F(info and info.overrideTooltipSpellID), SpellName(info and info.overrideTooltipSpellID),
        LinkedIDs(info),
        F(auraSID), F(auraName or SpellName(auraSID)), F(auraID), F(auraName), F(auraUnit),
        F(frame.wasSetFromAura), F(frame.cooldownUseAuraDisplayTime), F(frame.cdmLastAuraActive),
        EntryFlags(entry)
    ))

    return true
end

local function Dump()
    print("|cffd8c67a[KCDM-DREAD]|r START")
    local count = 0

    for _, viewerName in ipairs(VIEWERS) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if PrintFrame(frame, viewerName) then
                    count = count + 1
                end
            end
        end
    end

    print("|cffd8c67a[KCDM-DREAD]|r END count=" .. tostring(count))
end

SLASH_KCDMDREAD1 = "/kcdmdread"
SlashCmdList.KCDMDREAD = Dump
