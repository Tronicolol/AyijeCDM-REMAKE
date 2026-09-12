local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
if not VIEWERS then return end

local REND_SPELL_ID = 772
local TRACKED_VIEWERS = { VIEWERS.ESSENTIAL, VIEWERS.UTILITY }

local function IsReadable(value)
    if value == nil then return false end
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

local function SafeText(value)
    if value == nil then return "nil" end
    if not IsReadable(value) then return "<secret>" end
    return tostring(value)
end

local function PrintLine(text)
    print("|cff00ccff[KCDM Rend Debug]|r " .. text)
end

local function SafeSpellName(spellID)
    if type(spellID) ~= "number" or not IsReadable(spellID) then return nil end
    if not C_Spell or not C_Spell.GetSpellName then return nil end

    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and name and IsReadable(name) then
        return name
    end
    return nil
end

local function AddID(list, seen, label, spellID)
    if spellID == nil then return end
    local key
    if type(spellID) == "number" and IsReadable(spellID) then
        key = spellID
    else
        PrintLine(label .. "=" .. SafeText(spellID))
        return
    end

    if seen[key] then return end
    seen[key] = true
    list[#list + 1] = { label = label, id = key }
end

local function AddCooldownInfoIDs(list, seen, prefix, info)
    if type(info) ~= "table" then return end

    AddID(list, seen, prefix .. ".spellID", info.spellID)
    AddID(list, seen, prefix .. ".overrideSpellID", info.overrideSpellID)
    AddID(list, seen, prefix .. ".overrideTooltipSpellID", info.overrideTooltipSpellID)
    AddID(list, seen, prefix .. ".linkedSpellID", info.linkedSpellID)

    local linked = info.linkedSpellIDs
    if type(linked) == "table" then
        for i = 1, #linked do
            AddID(list, seen, prefix .. ".linkedSpellIDs[" .. i .. "]", linked[i])
        end
    end
end

local function GetFrameCooldownInfo(frame)
    if not frame then return nil end

    if type(frame.GetCooldownInfo) == "function" then
        local ok, info = pcall(frame.GetCooldownInfo, frame)
        if ok and type(info) == "table" then
            return info
        end
    end

    if type(frame.cooldownInfo) == "table" then
        return frame.cooldownInfo
    end

    return nil
end

local function TestAuraByName(name)
    if not name or not C_UnitAuras or not C_UnitAuras.GetAuraDataBySpellName then
        return false, nil
    end

    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", name, "HARMFUL|PLAYER")
    if not ok then
        return false, "API_ERROR"
    end
    return aura ~= nil, aura
end

local function DumpDirectRendLookup()
    local rendName = SafeSpellName(REND_SPELL_ID)
    PrintLine("Target exists=" .. tostring(UnitExists("target") and true or false)
        .. " attackable=" .. tostring(UnitCanAttack("player", "target") and true or false))
    PrintLine("Rend base: id=" .. REND_SPELL_ID .. " name=" .. tostring(rendName))

    local found, aura = TestAuraByName(rendName)
    PrintLine("Direct HARMFUL|PLAYER lookup: found=" .. tostring(found))

    if found and type(aura) == "table" then
        PrintLine("Direct aura duration=" .. SafeText(aura.duration)
            .. " expiration=" .. SafeText(aura.expirationTime)
            .. " applications=" .. SafeText(aura.applications))
    elseif aura == "API_ERROR" then
        PrintLine("Direct aura lookup raised an API error")
    end
end

local function DumpFrame(frame, index)
    local cooldownID = frame and frame.cooldownID
    PrintLine("--- auraOverlay frame #" .. index .. " cooldownID=" .. SafeText(cooldownID)
        .. " nativeAura=" .. tostring(frame and frame.cooldownUseAuraDisplayTime == true))

    local ids, seen = {}, {}
    AddID(ids, seen, "cdmCdGroupSpellID", frame.cdmCdGroupSpellID)
    AddID(ids, seen, "cdmBuffCategorySpellID", frame.cdmBuffCategorySpellID)

    if type(frame.GetSpellID) == "function" then
        local ok, spellID = pcall(frame.GetSpellID, frame)
        if ok then
            AddID(ids, seen, "GetSpellID", spellID)
        else
            PrintLine("GetSpellID=<error>")
        end
    end

    AddCooldownInfoIDs(ids, seen, "frameInfo", GetFrameCooldownInfo(frame))

    if type(cooldownID) == "number" and IsReadable(cooldownID)
        and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
        if ok then
            AddCooldownInfoIDs(ids, seen, "viewerInfo", info)
        else
            PrintLine("viewerInfo=<error>")
        end
    end

    if CDM.GetSpellIDCandidates then
        local ok, candidates = pcall(CDM.GetSpellIDCandidates, CDM, frame)
        if ok and type(candidates) == "table" then
            for i = 1, #candidates do
                AddID(ids, seen, "KCDMcandidate[" .. i .. "]", candidates[i])
            end
        end
    end

    local anyRendName = false
    for _, item in ipairs(ids) do
        local name = SafeSpellName(item.id)
        local found = false
        if name then
            found = TestAuraByName(name)
            if name == SafeSpellName(REND_SPELL_ID) then
                anyRendName = true
            end
        end
        PrintLine(item.label .. "=" .. item.id
            .. " name=" .. tostring(name)
            .. " targetAura=" .. tostring(found and true or false))
    end

    PrintLine("Candidate name matches Rend=" .. tostring(anyRendName))
end

local function RunRendDebug()
    PrintLine("===== START =====")
    DumpDirectRendLookup()

    local map = CDM._auraOverlayEnabled
    if type(map) ~= "table" then
        PrintLine("_auraOverlayEnabled is missing")
        PrintLine("===== END =====")
        return
    end

    local count = 0
    if CDM.ForEachActiveFrame then
        CDM:ForEachActiveFrame(TRACKED_VIEWERS, function(frame)
            local cooldownID = frame and frame.cooldownID
            local entry = cooldownID and map[cooldownID]
            if entry and entry.auraOverlay then
                count = count + 1
                DumpFrame(frame, count)
            end
        end)
    else
        PrintLine("ForEachActiveFrame is missing")
    end

    PrintLine("Frames with Show Aura Overlay=" .. count)
    PrintLine("===== END =====")
end

SLASH_KCDMRENDDEBUG1 = "/kcdmrend"
SlashCmdList["KCDMRENDDEBUG"] = RunRendDebug
