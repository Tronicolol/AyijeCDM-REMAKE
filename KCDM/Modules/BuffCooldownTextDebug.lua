local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM then return end

local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
if not VIEWERS or not VIEWERS.BUFF then return end

local enabled = false
local records = {}
local counts = {}
local MAX_RECORDS = 240

local function Count(event)
    counts[event] = (counts[event] or 0) + 1
end

local function SafeString(value)
    local ok, result = pcall(tostring, value)
    if not ok then return "?" end
    return result
end

local function SafeNumber(value)
    if type(value) ~= "number" then return "?" end
    if canaccessvalue and not canaccessvalue(value) then return "?" end
    return string.format("%.2f", value)
end

local function SafeBool(value)
    if value == true then return "1" end
    if value == false then return "0" end
    return "?"
end

local function SafeCall(obj, method, ...)
    if not obj then return nil end
    local fn = obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, obj, ...)
    if not ok then return nil end
    return a, b, c, d
end

local function Push(line)
    records[#records + 1] = string.format("%.3f %s", GetTime(), line)
    if #records > MAX_RECORDS then
        table.remove(records, 1)
    end
end

local function GetOverride(frame)
    local sets = CDM.BuffGroupSets
    local spellID = frame and frame.cdmBuffCategorySpellID
    local groupIndex = spellID and sets and sets.grouped and sets.grouped[spellID]
    local groupData = groupIndex and sets.groups and sets.groups[groupIndex]
    if not groupData or not spellID then
        return spellID, groupIndex, nil
    end
    local override
    if CDM.ResolveBuffOverrideEntry then
        override = CDM:ResolveBuffOverrideEntry(groupData.spellOverrides, spellID)
    end
    return spellID, groupIndex, override
end

local function IsTargetFrame(frame)
    local _, _, override = GetOverride(frame)
    return override and override.textOverride == true
end

local function FontObjectState(fontName)
    if type(fontName) ~= "string" then
        return "font=" .. SafeString(fontName)
    end

    local font = _G[fontName]
    if not font then
        return "font=" .. fontName .. " missing"
    end

    local path, size, flags = SafeCall(font, "GetFont")
    local r, g, b, a = SafeCall(font, "GetTextColor")
    return string.format(
        "font=%s size=%s color=%s,%s,%s,%s flags=%s",
        fontName,
        SafeNumber(size),
        SafeNumber(r),
        SafeNumber(g),
        SafeNumber(b),
        SafeNumber(a),
        SafeString(flags)
    )
end

local function RegionState(region, index)
    if not region or not region.IsObjectType or not region:IsObjectType("FontString") then
        return nil
    end

    local text = SafeCall(region, "GetText")
    local _, size, flags = SafeCall(region, "GetFont")
    local r, g, b, a = SafeCall(region, "GetTextColor")
    local alpha = SafeCall(region, "GetAlpha")
    local shown = SafeCall(region, "IsShown")

    return string.format(
        "R%d text=%s size=%s color=%s,%s,%s,%s alpha=%s shown=%s flags=%s",
        index,
        SafeString(text),
        SafeNumber(size),
        SafeNumber(r),
        SafeNumber(g),
        SafeNumber(b),
        SafeNumber(a),
        SafeNumber(alpha),
        SafeBool(shown),
        SafeString(flags)
    )
end

local function Snapshot(frame, reason)
    if not enabled or not frame or not IsTargetFrame(frame) then return end

    local spellID, groupIndex, override = GetOverride(frame)
    local name = spellID and C_Spell.GetSpellName(spellID) or "?"
    local color = override and override.cooldownColor
    local cooldown = frame.Cooldown

    Push(string.format(
        "SNAP %s spell=%s name=%s group=%s ovSize=%s ovColor=%s,%s,%s aura=%s useAura=%s fromAura=%s",
        reason or "?",
        SafeString(spellID),
        SafeString(name),
        SafeString(groupIndex),
        SafeString(override and override.cooldownFontSize),
        SafeNumber(color and color.r),
        SafeNumber(color and color.g),
        SafeNumber(color and color.b),
        SafeBool(frame.cdmLastAuraActive),
        SafeBool(frame.cooldownUseAuraDisplayTime),
        SafeBool(frame.wasSetFromAura)
    ))

    if cooldown then
        local currentFont = SafeCall(cooldown, "GetCountdownFont")
        if currentFont ~= nil then
            Push("COUNTDOWN_FONT " .. FontObjectState(currentFont))
        end

        local directText = cooldown.Text or cooldown.text
        if directText then
            local state = RegionState(directText, 0)
            if state then Push("DIRECT " .. state) end
        end

        if cooldown.GetRegions then
            local regions = { cooldown:GetRegions() }
            for index, region in ipairs(regions) do
                local state = RegionState(region, index)
                if state then Push(state) end
            end
        end
    end

    for label, region in pairs({
        Time = frame.Time,
        Duration = frame.Duration,
        Applications = frame.Applications and frame.Applications.Applications,
    }) do
        local state = RegionState(region, 90)
        if state then Push(label .. " " .. state) end
    end
end

local function QueueSnapshot(frame, reason)
    Snapshot(frame, reason .. ":now")
    C_Timer.After(0, function()
        Snapshot(frame, reason .. ":next")
    end)
end

local function WatchFrame(frame)
    if not frame or frame.cdmBuffTextDiagHooked then return end
    frame.cdmBuffTextDiagHooked = true

    local cooldown = frame.Cooldown
    if cooldown then
        if type(cooldown.SetCountdownFont) == "function" then
            hooksecurefunc(cooldown, "SetCountdownFont", function(_, fontName)
                if not enabled or not IsTargetFrame(frame) then return end
                Count("SetCountdownFont")
                Push("CALL SetCountdownFont " .. FontObjectState(fontName))
                QueueSnapshot(frame, "after_SetCountdownFont")
            end)
        end

        if type(cooldown.SetCooldown) == "function" then
            hooksecurefunc(cooldown, "SetCooldown", function()
                if not enabled or not IsTargetFrame(frame) then return end
                Count("SetCooldown")
                QueueSnapshot(frame, "after_SetCooldown")
            end)
        end

        if type(cooldown.SetCooldownFromDurationObject) == "function" then
            hooksecurefunc(cooldown, "SetCooldownFromDurationObject", function()
                if not enabled or not IsTargetFrame(frame) then return end
                Count("SetCooldownFromDurationObject")
                QueueSnapshot(frame, "after_SetCooldownFromDurationObject")
            end)
        end

        if type(cooldown.SetUseAuraDisplayTime) == "function" then
            hooksecurefunc(cooldown, "SetUseAuraDisplayTime", function(_, value)
                if not enabled or not IsTargetFrame(frame) then return end
                Count("SetUseAuraDisplayTime")
                Push("CALL SetUseAuraDisplayTime=" .. SafeBool(value))
                QueueSnapshot(frame, "after_SetUseAuraDisplayTime")
            end)
        end
    end

    frame:HookScript("OnShow", function()
        if enabled and IsTargetFrame(frame) then
            Count("FrameShow")
            QueueSnapshot(frame, "frame_show")
        end
    end)
end

local function WatchAll()
    local viewer = _G[VIEWERS.BUFF]
    if not viewer or not viewer.itemFramePool then return end
    for frame in viewer.itemFramePool:EnumerateActive() do
        WatchFrame(frame)
    end
end

if type(CDM.PositionBuffGroupFrames) == "function" then
    hooksecurefunc(CDM, "PositionBuffGroupFrames", function(_, _, frames)
        for _, frame in ipairs(frames or {}) do
            WatchFrame(frame)
            if enabled and IsTargetFrame(frame) then
                QueueSnapshot(frame, "position_group")
            end
        end
    end)
end

if type(CDM.ApplyGroupStyleOverrides) == "function" then
    hooksecurefunc(CDM, "ApplyGroupStyleOverrides", function()
        WatchAll()
        if not enabled then return end
        local viewer = _G[VIEWERS.BUFF]
        if not viewer or not viewer.itemFramePool then return end
        for frame in viewer.itemFramePool:EnumerateActive() do
            if IsTargetFrame(frame) then
                QueueSnapshot(frame, "group_style")
            end
        end
    end)
end

SLASH_KCDMBUFFTEXTDIAG1 = "/kcdmtextdiag"
SlashCmdList.KCDMBUFFTEXTDIAG = function(msg)
    msg = (msg or ""):lower()

    if msg == "on" then
        enabled = true
        table.wipe(records)
        table.wipe(counts)
        WatchAll()
        print("|cff33ff99[KCDM]|r Text diagnostic ON. Reproduce Malevolence and use /kcdmtextdiag dump.")
        local viewer = _G[VIEWERS.BUFF]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if IsTargetFrame(frame) then
                    QueueSnapshot(frame, "diag_on")
                end
            end
        end
        return
    end

    if msg == "off" then
        enabled = false
        print("|cff33ff99[KCDM]|r Text diagnostic OFF.")
        return
    end

    if msg == "clear" then
        table.wipe(records)
        table.wipe(counts)
        print("|cff33ff99[KCDM]|r Text diagnostic cleared.")
        return
    end

    if msg == "dump" then
        print("|cff33ff99[KCDM]|r Text diagnostic summary:")
        for event, count in pairs(counts) do
            print(string.format("|cff33ff99[KCDM]|r %s=%d", event, count))
        end
        print(string.format("|cff33ff99[KCDM]|r showing last %d records", #records))
        for _, line in ipairs(records) do
            print("|cff33ff99[KCDM-TEXT]|r " .. line)
        end
        return
    end

    print("|cff33ff99[KCDM]|r /kcdmtextdiag on | off | clear | dump")
end
