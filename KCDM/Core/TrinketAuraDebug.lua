local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

-- Diagnostic only. Does not modify cooldown, aura, glow, colour or desaturation state.
-- Usage: /kcdmauradiag on -> use the trinket with Show Aura Overlay + Aura Glow enabled -> /kcdmauradiag dump

local RealTime = Enum.DurationTimeModifier.RealTime
local MAX_LINES = 120
local DUMP_LINES = 35

local enabled = false
local lines = {}
local lastByFrame = setmetatable({}, { __mode = "k" })
local ticker

local function Accessible(value)
    return value == nil or not canaccessvalue or canaccessvalue(value)
end

local function F(value)
    if value == nil then return "-" end
    if not Accessible(value) then return "SECRET" end

    local valueType = type(value)
    if valueType == "boolean" then
        return value and "1" or "0"
    end
    if valueType == "number" then
        return string.format("%.3f", value)
    end
    if valueType == "string" then
        return value
    end
    return tostring(value)
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

local function GetEntry(frame)
    local cdID = frame and frame.cooldownID
    if cdID == nil or not Accessible(cdID) then return nil end
    local map = CDM._auraOverlayEnabled
    return map and map[cdID] or nil
end

local function GetAuraSnapshot(frame)
    local auraData = SafeFrameMethod(frame, "GetAuraDataCached")
    local auraUnit = SafeFrameMethod(frame, "GetAuraDataUnit") or "player"

    local instanceID = auraData and auraData.auraInstanceID or nil
    local duration = auraData and auraData.duration or nil
    local expiration = auraData and auraData.expirationTime or nil

    local durationObject
    local durationRemaining
    if auraData
       and Accessible(instanceID)
       and type(instanceID) == "number"
       and C_UnitAuras
       and type(C_UnitAuras.GetUnitAuraDuration) == "function" then
        durationObject = SafeCall(C_UnitAuras.GetUnitAuraDuration, auraUnit, instanceID)
        if durationObject and type(durationObject.GetRemainingDuration) == "function" then
            durationRemaining = SafeCall(durationObject.GetRemainingDuration, durationObject, RealTime)
        end
    end

    return auraData, auraUnit, instanceID, duration, expiration, durationObject, durationRemaining
end

local function GetCooldownWidgetState(frame)
    local cd = frame and frame.Cooldown
    if not cd then return "ui=-" end

    local startMS, durationMS
    if type(cd.GetCooldownTimes) == "function" then
        startMS, durationMS = SafeCall(cd.GetCooldownTimes, cd)
    end

    local drawSwipe = SafeCall(cd.GetDrawSwipe, cd)
    local hideNumbers = SafeCall(cd.GetHideCountdownNumbers, cd)
    local reverse = SafeCall(cd.GetReverse, cd)

    return string.format(
        "ui[start=%s dur=%s swipe=%s hideN=%s rev=%s]",
        F(startMS), F(durationMS), F(drawSwipe), F(hideNumbers), F(reverse)
    )
end

local function GetGlowState(frame)
    local host = frame and frame.cdmBuffGlowHost
    local hostShown = host and host:IsShown() or false
    local hostActive = host and host.cdmGlowActive or false
    local hostW = host and host:GetWidth() or nil
    local hostH = host and host:GetHeight() or nil

    return string.format(
        "glow[producer=%s wanted=%s host=%s active=%s size=%sx%s]",
        F(frame and frame.cdmGlowProducer),
        F(frame and frame.cdmBuffGlowWanted),
        F(hostShown), F(hostActive), F(hostW), F(hostH)
    )
end

local function BuildState(frame, viewerName)
    local equipSlot = SafeFrameMethod(frame, "GetEquipSlot")
    if not equipSlot or not Accessible(equipSlot) or type(equipSlot) ~= "number" or equipSlot <= 0 then
        return nil
    end

    local itemStart, itemDuration, itemEnable = SafeCall(GetInventoryItemCooldown, "player", equipSlot)
    local spellID = SafeFrameMethod(frame, "GetSpellID")
    local spellName = spellID and Accessible(spellID) and SafeCall(C_Spell.GetSpellName, spellID) or nil
    local entry = GetEntry(frame)

    local auraData, auraUnit, auraInstanceID, auraDuration, auraExpiration, durationObject, durationRemaining = GetAuraSnapshot(frame)

    local iconDesat
    if frame.Icon and type(frame.Icon.GetDesaturation) == "function" then
        iconDesat = SafeCall(frame.Icon.GetDesaturation, frame.Icon)
    end

    return string.format(
        "%s frame=%s slot=%s cdid=%s sid=%s name=%s item[start=%s dur=%s en=%s] entry[present=%s overlay=%s glow=%s] aura[cached=%s unit=%s id=%s dur=%s exp=%s obj=%s rem=%s] native[srcAura=%s useAura=%s actual=%s cdmLast=%s nativeOv=%s] %s %s icon[desat=%s]",
        tostring(viewerName or "?"), tostring(frame),
        F(equipSlot), F(frame.cooldownID), F(spellID), F(spellName),
        F(itemStart), F(itemDuration), F(itemEnable),
        F(entry ~= nil), F(entry and entry.auraOverlay), F(entry and entry.auraGlowEnabled),
        F(auraData ~= nil), F(auraUnit), F(auraInstanceID), F(auraDuration), F(auraExpiration), F(durationObject ~= nil), F(durationRemaining),
        F(frame.wasSetFromAura), F(frame.cooldownUseAuraDisplayTime), F(frame.isOnActualCooldown), F(frame.cdmLastAuraActive), F(frame.cdmEquippedItemNativeOverlay),
        GetCooldownWidgetState(frame), GetGlowState(frame), F(iconDesat)
    )
end

local function Push(frame, viewerName, force)
    local state = BuildState(frame, viewerName)
    if not state then return end

    if not force and lastByFrame[frame] == state then return end
    lastByFrame[frame] = state

    lines[#lines + 1] = string.format("%.3f %s", GetTime(), state)
    if #lines > MAX_LINES then
        table.remove(lines, 1)
    end
end

local function ForEachCooldownFrame(fn)
    local viewers = (CDM.CONST and CDM.CONST.COOLDOWN_VIEWER_NAMES) or {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
    }

    if CDM.ForEachActiveFrame then
        CDM:ForEachActiveFrame(viewers, fn)
        return
    end

    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                fn(frame, viewerName)
            end
        end
    end
end

local function Poll()
    if not enabled then return end
    ForEachCooldownFrame(function(frame, viewerName)
        Push(frame, viewerName, false)
    end)
end

local function Start()
    enabled = true
    lines = {}
    lastByFrame = setmetatable({}, { __mode = "k" })
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.08, Poll)
    Poll()
    CDM.Print("Trinket Aura diagnostic ON.")
    CDM.Print("Activa Show Aura Overlay + Aura Glow, usa el trinket y escribe /kcdmauradiag dump")
end

local function Stop()
    enabled = false
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    CDM.Print("Trinket Aura diagnostic OFF.")
end

local function Dump()
    local count = #lines
    local first = math.max(1, count - DUMP_LINES + 1)
    CDM.Print("Trinket Aura diagnostic: " .. count .. " captured, showing last " .. (count - first + 1) .. ".")
    for i = first, count do
        print("|cffd8c67a[KCDM-AURA-DIAG]|r " .. lines[i])
    end
end

SLASH_KCDMAURADIAG1 = "/kcdmauradiag"
SlashCmdList.KCDMAURADIAG = function(message)
    local command = string.lower((message or ""):match("^(%S*)") or "")
    if command == "" or command == "on" then
        Start()
        return
    end
    if command == "off" then
        Stop()
        return
    end
    if command == "dump" then
        Dump()
        return
    end
    if command == "clear" then
        lines = {}
        lastByFrame = setmetatable({}, { __mode = "k" })
        CDM.Print("Trinket Aura diagnostic cleared.")
        return
    end
    CDM.Print("Uso: /kcdmauradiag on | dump | clear | off")
end
