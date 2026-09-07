local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

-- Diagnostic only. This file does not change cooldown, glow, colour, swipe or timer state.
-- Enable with /acdmdiag on, reproduce the issue, then /acdmdiag dump.

local TARGET_DEFAULT = 33917 -- Mangle
local MAX_LINES = 160
local DUMP_LINES = 45
local RealTime = Enum.DurationTimeModifier.RealTime

local enabled = false
local targetSpellID = TARGET_DEFAULT
local targetSpellName
local lines = {}
local lastStateSignature
local matchedEver = false
local pollTicker
local hookedFrames = setmetatable({}, { __mode = "k" })

local function Accessible(value)
    return value == nil or not canaccessvalue or canaccessvalue(value)
end

local function F(value)
    if value == nil then return "-" end
    if not Accessible(value) then return "SECRET" end

    local valueType = type(value)
    if valueType == "boolean" then
        return value and "1" or "0"
    elseif valueType == "number" then
        return string.format("%.3f", value)
    end

    return tostring(value)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

local function SafeSpellName(spellID)
    if not spellID or not Accessible(spellID) then return "?" end
    local name = SafeCall(C_Spell.GetSpellName, spellID)
    if not Accessible(name) then return "?" end
    return name or "?"
end

local function SafeFrameMethod(frame, methodName)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then return nil end
    return SafeCall(method, frame)
end

local function AddCandidate(out, seen, value)
    if value == nil or not Accessible(value) or type(value) ~= "number" then return end
    if seen[value] then return end
    seen[value] = true
    out[#out + 1] = value
end

local function GetFrameCandidates(frame)
    local out, seen = {}, {}

    AddCandidate(out, seen, SafeFrameMethod(frame, "GetSpellID"))
    AddCandidate(out, seen, SafeFrameMethod(frame, "GetBaseSpellID"))

    local info = frame and frame.cooldownInfo
    if info then
        AddCandidate(out, seen, info.spellID)
        AddCandidate(out, seen, info.overrideSpellID)
        AddCandidate(out, seen, info.overrideTooltipSpellID)

        local linked = info.linkedSpellIDs
        if type(linked) == "table" then
            for _, spellID in ipairs(linked) do
                AddCandidate(out, seen, spellID)
            end
        end
    end

    return out
end

local function IsTargetFrame(frame)
    local candidates = GetFrameCandidates(frame)
    for _, spellID in ipairs(candidates) do
        if spellID == targetSpellID then
            return true, spellID, candidates
        end
    end

    -- Cooldown Viewer can use an override spell ID. Compare the localized spell
    -- name too, so Mangle still matches if Blizzard swaps the ID internally.
    if targetSpellName and targetSpellName ~= "?" then
        for _, spellID in ipairs(candidates) do
            if SafeSpellName(spellID) == targetSpellName then
                return true, spellID, candidates
            end
        end
    end

    return false, nil, candidates
end

local function GetDurationRemaining(spellID, ignoreGCD)
    local durationObject = SafeCall(C_Spell.GetSpellCooldownDuration, spellID, ignoreGCD)
    if not durationObject or type(durationObject.GetRemainingDuration) ~= "function" then
        return nil
    end
    return SafeCall(durationObject.GetRemainingDuration, durationObject, RealTime)
end

local function GetCooldownWidgetState(frame)
    local cd = frame and frame.Cooldown
    if not cd then return "ui=-" end

    local startMS, durationMS
    if type(cd.GetCooldownTimes) == "function" then
        local ok, a, b = pcall(cd.GetCooldownTimes, cd)
        if ok then
            startMS, durationMS = a, b
        end
    end

    local drawSwipe = SafeCall(cd.GetDrawSwipe, cd)
    local hideNumbers = SafeCall(cd.GetHideCountdownNumbers, cd)

    return string.format(
        "ui[start=%s dur=%s swipe=%s hideN=%s]",
        F(startMS), F(durationMS), F(drawSwipe), F(hideNumbers)
    )
end

local function GetIconState(frame)
    local icon = frame and frame.Icon
    if not icon then return "icon=-" end

    local desat = SafeCall(icon.GetDesaturation, icon)
    local tintShown = frame.cdmCooldownTintOverlay and frame.cdmCooldownTintOverlay:IsShown() or false

    return string.format("icon[desat=%s tint=%s]", F(desat), F(tintShown))
end

local function CandidateText(candidates)
    if not candidates or #candidates == 0 then return "-" end
    local parts = {}
    for _, id in ipairs(candidates) do
        parts[#parts + 1] = tostring(id) .. ":" .. SafeSpellName(id)
    end
    return table.concat(parts, ",")
end

local function BuildState(frame, origin, matchedSpellID, candidates, note)
    local spellID = matchedSpellID or SafeFrameMethod(frame, "GetSpellID") or targetSpellID
    if not Accessible(spellID) then spellID = targetSpellID end

    local cooldownInfo = SafeCall(C_Spell.GetSpellCooldown, spellID)
    local apiActive = cooldownInfo and cooldownInfo.isActive
    local apiGCD = cooldownInfo and cooldownInfo.isOnGCD
    local apiStart = cooldownInfo and cooldownInfo.startTime
    local apiDuration = cooldownInfo and cooldownInfo.duration

    local realRemaining = GetDurationRemaining(spellID, true)
    local visibleRemaining = GetDurationRemaining(spellID, false)

    local chargeInfo = SafeCall(C_Spell.GetSpellCharges, spellID)
    local currentCharges = chargeInfo and chargeInfo.currentCharges
    local maxCharges = chargeInfo and chargeInfo.maxCharges
    local chargeActive = chargeInfo and chargeInfo.isActive

    local hasChargeSource = SafeFrameMethod(frame, "HasVisualDataSource_Charges")

    return string.format(
        "%s sid=%s api[a=%s gcd=%s start=%s dur=%s] rem[real=%s vis=%s] frame[a=%s gcd=%s actual=%s desat=%s srcCh=%s] charges[%s/%s a=%s] %s %s cand[%s]%s",
        origin,
        F(spellID),
        F(apiActive), F(apiGCD), F(apiStart), F(apiDuration),
        F(realRemaining), F(visibleRemaining),
        F(frame.cooldownIsActive), F(frame.isOnGCD), F(frame.isOnActualCooldown), F(frame.cooldownDesaturated), F(hasChargeSource),
        F(currentCharges), F(maxCharges), F(chargeActive),
        GetCooldownWidgetState(frame),
        GetIconState(frame),
        CandidateText(candidates),
        note and (" " .. note) or ""
    )
end

local function Push(frame, origin, matchedSpellID, candidates, note, force)
    if not enabled or not frame then return end

    local state = BuildState(frame, origin, matchedSpellID, candidates, note)
    -- Polling only records a line when the actual observed state changes.
    local signature = state:gsub("^poll ", "")
    if not force and signature == lastStateSignature then return end
    lastStateSignature = signature

    lines[#lines + 1] = string.format("%.3f %s", GetTime(), state)
    if #lines > MAX_LINES then
        table.remove(lines, 1)
    end
end

local function EnsureDirectHooks(frame, matchedSpellID, candidates)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true

    local cd = frame.Cooldown
    if not cd then return end

    if type(cd.SetCooldown) == "function" then
        hooksecurefunc(cd, "SetCooldown", function(_, startTime, duration, modRate)
            Push(frame, "CD:SetCooldown", matchedSpellID, GetFrameCandidates(frame), "args=" .. F(startTime) .. "/" .. F(duration) .. "/" .. F(modRate), true)
        end)
    end

    if type(cd.SetCooldownFromDurationObject) == "function" then
        hooksecurefunc(cd, "SetCooldownFromDurationObject", function()
            Push(frame, "CD:SetDurationObject", matchedSpellID, GetFrameCandidates(frame), nil, true)
        end)
    end

    if type(cd.Clear) == "function" then
        hooksecurefunc(cd, "Clear", function()
            Push(frame, "CD:Clear", matchedSpellID, GetFrameCandidates(frame), nil, true)
        end)
    end

    if type(cd.HookScript) == "function" then
        cd:HookScript("OnCooldownDone", function()
            Push(frame, "CD:OnCooldownDone", matchedSpellID, GetFrameCandidates(frame), nil, true)
        end)
    end

    local icon = frame.Icon
    if icon and type(icon.SetDesaturated) == "function" then
        hooksecurefunc(icon, "SetDesaturated", function(_, value)
            Push(frame, "Icon:SetDesaturated", matchedSpellID, GetFrameCandidates(frame), "arg=" .. F(value), true)
        end)
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

local function PollTarget()
    if not enabled then return end

    ForEachCooldownFrame(function(frame, viewerName)
        local matched, matchedSpellID, candidates = IsTargetFrame(frame)
        if not matched then return end

        if not matchedEver then
            matchedEver = true
            Push(frame, "FOUND:" .. tostring(viewerName), matchedSpellID, candidates, nil, true)
        end

        EnsureDirectHooks(frame, matchedSpellID, candidates)
        Push(frame, "poll", matchedSpellID, candidates)
    end)
end

local function StartPolling()
    if pollTicker then return end
    pollTicker = C_Timer.NewTicker(0.05, PollTarget)
    PollTarget()
end

local function StopPolling()
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
end

local function PrintActiveFrameList()
    local found = 0
    CDM.Print("Active Cooldown Viewer frames:")
    ForEachCooldownFrame(function(frame, viewerName)
        if found >= 20 then return end
        local candidates = GetFrameCandidates(frame)
        if #candidates > 0 then
            found = found + 1
            print("|cffd8c67a[ACDM-LIST]|r " .. tostring(viewerName) .. " cand[" .. CandidateText(candidates) .. "]")
        end
    end)
    if found == 0 then
        CDM.Print("No active cooldown frames with readable spell IDs were found.")
    end
end

SLASH_ACDMSTRICTDIAG1 = "/acdmdiag"
SlashCmdList.ACDMSTRICTDIAG = function(message)
    local command = string.match(message or "", "^(%S*)") or ""
    command = string.lower(command)

    if command == "" or command == "on" then
        enabled = true
        lines = {}
        lastStateSignature = nil
        matchedEver = false
        targetSpellName = SafeSpellName(targetSpellID)
        StartPolling()
        CDM.Print("Cooldown diagnostic V2 ON for " .. targetSpellName .. " (" .. targetSpellID .. ").")
        CDM.Print("Reproduce el fallo y después escribe /acdmdiag dump")
        return
    end

    if command == "off" then
        enabled = false
        StopPolling()
        CDM.Print("Cooldown diagnostic OFF.")
        return
    end

    if command == "clear" then
        lines = {}
        lastStateSignature = nil
        matchedEver = false
        CDM.Print("Cooldown diagnostic cleared.")
        return
    end

    if command == "list" then
        PrintActiveFrameList()
        return
    end

    if command == "dump" then
        local count = #lines
        local first = math.max(1, count - DUMP_LINES + 1)
        CDM.Print("Cooldown diagnostic V2 dump: " .. count .. " captured, showing last " .. (count - first + 1) .. ".")
        if not matchedEver then
            CDM.Print("Target frame was not matched. Run /acdmdiag list and send that screenshot too.")
        end
        for i = first, count do
            print("|cffd8c67a[ACDM-DIAG]|r " .. lines[i])
        end
        return
    end

    local numericID = tonumber(command)
    if numericID then
        targetSpellID = numericID
        targetSpellName = SafeSpellName(targetSpellID)
        lines = {}
        lastStateSignature = nil
        matchedEver = false
        enabled = true
        StartPolling()
        CDM.Print("Cooldown diagnostic V2 ON for " .. targetSpellName .. " (" .. targetSpellID .. ").")
        return
    end

    CDM.Print("Uso: /acdmdiag on | off | dump | clear | list | <spellID>")
end
