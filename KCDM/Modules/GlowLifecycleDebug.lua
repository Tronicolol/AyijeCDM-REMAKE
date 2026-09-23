local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Glow then return end

local VIEWERS = CDM.CONST and CDM.CONST.VIEWERS
if not VIEWERS then return end

local enabled = false
local records = {}
local recordHead = 0
local recordCount = 0
local MAX_RECORDS = 320

local frameIDs = setmetatable({}, { __mode = "k" })
local nextFrameID = 0
local eventCounts = {}
local requestCounts = setmetatable({}, { __mode = "k" })
local requestRuns = setmetatable({}, { __mode = "k" })
local lastSample = setmetatable({}, { __mode = "k" })
local anomalies = 0

local driver = CreateFrame("Frame")
driver:Hide()
local sampleElapsed = 0

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function SafeNumber(value)
    if type(value) ~= "number" then return nil end
    if IsSecret(value) then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function SafeCallNumber(obj, methodName)
    if not obj then return nil end
    local method = obj[methodName]
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, obj)
    if not ok then return nil end
    return SafeNumber(value)
end

local function SafeShown(obj)
    if not obj or type(obj.IsShown) ~= "function" then return "?" end
    local ok, value = pcall(obj.IsShown, obj)
    if not ok or IsSecret(value) then return "?" end
    return value and "1" or "0"
end

local function SafeField(obj, key)
    if not obj then return nil end
    local ok, value = pcall(function()
        return obj[key]
    end)
    if not ok or IsSecret(value) then return nil end
    return value
end

local function FrameID(frame)
    if not frame then return "-" end
    local id = frameIDs[frame]
    if not id then
        nextFrameID = nextFrameID + 1
        id = nextFrameID
        frameIDs[frame] = id
    end
    return "F" .. id
end

local function Dim(value)
    value = SafeNumber(value)
    if not value then return "?" end
    return string.format("%.1f", value)
end

local function ObjectSize(obj)
    return SafeCallNumber(obj, "GetWidth"), SafeCallNumber(obj, "GetHeight")
end

local GLOW_KEY = "CDM_SpellAlert"
local CHILDREN = {
    { "px", "_PixelGlow" .. GLOW_KEY },
    { "ac", "_AutoCastGlow" .. GLOW_KEY },
    { "bt", "_ButtonGlow" },
    { "pr", "_ProcGlow" .. GLOW_KEY },
}

local function GlowChildren(host)
    if not host then return "-", false end

    local parts = {}
    local giant = false
    local hostW, hostH = ObjectSize(host)

    for _, def in ipairs(CHILDREN) do
        local child = SafeField(host, def[2])
        if child then
            local w, h = ObjectSize(child)
            parts[#parts + 1] = string.format(
                "%s:%sx%s/s%s",
                def[1], Dim(w), Dim(h), SafeShown(child)
            )

            if hostW and hostH and w and h
               and hostW > 0 and hostH > 0
               and (w > hostW * 2.25 or h > hostH * 2.25) then
                giant = true
            end
        end
    end

    return #parts > 0 and table.concat(parts, ",") or "-", giant
end

local function Snapshot(frame)
    if not frame then return "global", false end

    local fw, fh = ObjectSize(frame)
    local host = SafeField(frame, "cdmBuffGlowHost")
    local hw, hh = ObjectSize(host)
    local children, giantChild = GlowChildren(host)

    local giantHost = false
    if fw and fh and hw and hh and fw > 0 and fh > 0 then
        giantHost = hw > fw * 1.5 or hh > fh * 1.5
    end

    local cooldownID = SafeField(frame, "cooldownID")
    if SafeNumber(cooldownID) then
        cooldownID = tostring(cooldownID)
    else
        cooldownID = "?"
    end

    local producer = SafeField(frame, "cdmGlowProducer")
    if type(producer) ~= "string" then producer = "-" end

    local viewer = SafeField(frame, "cdmViewerName")
    if type(viewer) ~= "string" then viewer = "-" end

    local text = string.format(
        "%s cd=%s v=%s prod=%s f=%sx%s host=%sx%s/hs%s child=[%s]",
        FrameID(frame), cooldownID, viewer, producer,
        Dim(fw), Dim(fh), Dim(hw), Dim(hh), SafeShown(host), children
    )

    return text, giantHost or giantChild
end

local function Push(text)
    recordHead = (recordHead % MAX_RECORDS) + 1
    records[recordHead] = string.format("%.3f %s", GetTime(), text)
    if recordCount < MAX_RECORDS then
        recordCount = recordCount + 1
    end
end

local function CountEvent(event)
    eventCounts[event] = (eventCounts[event] or 0) + 1
end

local function CountRequest(frame, producer, on)
    local stats = requestCounts[frame]
    if not stats then
        stats = {}
        requestCounts[frame] = stats
    end
    local key = tostring(producer) .. (on and "+" or "-")
    stats[key] = (stats[key] or 0) + 1

    local runs = requestRuns[frame]
    if not runs then
        runs = {}
        requestRuns[frame] = runs
    end
    runs[key] = (runs[key] or 0) + 1
    return runs[key]
end

local function ResetOtherRequestRuns(frame, keepKey)
    local runs = requestRuns[frame]
    if not runs then return end
    for key in pairs(runs) do
        if key ~= keepKey then
            runs[key] = nil
        end
    end
end

local function Record(event, frame, a, b, c, d, e, f)
    if not enabled then return end
    CountEvent(event)

    local snap, giant = Snapshot(frame)
    if giant then
        anomalies = anomalies + 1
        Push("ANOMALY " .. event .. " " .. snap)
    end

    if event == "REQUEST" then
        local key = tostring(a) .. (b and "+" or "-")
        ResetOtherRequestRuns(frame, key)
        local run = CountRequest(frame, a, b == true)
        if run == 1 or run % 20 == 0 then
            Push(string.format("REQUEST %s=%s src=%s run=%d %s",
                tostring(a), b and "ON" or "OFF", tostring(c or "-"), run, snap))
        end
        return
    end

    if event == "READY_COMPUTE" then
        Push(string.format(
            "READY_COMPUTE cd=%s spell=%s ready=%s reason=%s resource=%s trigger=%s %s",
            tostring(a or "-"),
            tostring(b or "-"),
            c and "1" or "0",
            tostring(d or "-"),
            e and "1" or "0",
            tostring(f or "-"),
            snap
        ))
        return
    end

    if event == "READY_DECISION" then
        Push(string.format(
            "READY_DECISION spell=%s input=%s reason=%s show=%s resource=%s %s",
            tostring(a or "-"),
            b and "1" or "0",
            tostring(c or "-"),
            d and "1" or "0",
            e and "1" or "0",
            snap
        ))
        return
    end

    if event == "SIZE" then
        Push(string.format("SIZE arg=%sx%s %s", Dim(a), Dim(b), snap))
        return
    end

    if event == "APPLY" then
        Push(string.format("APPLY type=%s same=%s force=%s %s",
            tostring(b or "-"), tostring(c), tostring(d), snap))
        return
    end

    if event == "LCG_START" then
        Push(string.format("LCG_START type=%s %s", tostring(b or "-"), snap))
        return
    end

    if event == "HARD_STOP" then
        Push("HARD_STOP " .. snap)
        return
    end

    if event == "LAYOUT_BEGIN" or event == "LAYOUT_FINISH_ATTEMPT" then
        Push(string.format("%s a=%s b=%s", event, tostring(a or "-"), tostring(b or "-")))
        return
    end

    Push(event .. " " .. snap)
end

CDM.GlowLifecycleTrace = Record

local function SampleFrame(frame)
    if not frame then return end
    local snap, giant = Snapshot(frame)
    if lastSample[frame] ~= snap then
        lastSample[frame] = snap
        CountEvent("SAMPLE_CHANGE")
        Push("SAMPLE_CHANGE " .. snap)
    end
    if giant then
        anomalies = anomalies + 1
        Push("ANOMALY SAMPLE " .. snap)
    end
end

driver:SetScript("OnUpdate", function(_, elapsed)
    if not enabled then
        driver:Hide()
        return
    end

    sampleElapsed = sampleElapsed + elapsed
    if sampleElapsed < 0.10 then return end
    sampleElapsed = 0

    if CDM.ForEachActiveFrame then
        CDM:ForEachActiveFrame({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }, SampleFrame)
    end
end)

local function Reset()
    wipe(records)
    recordHead = 0
    recordCount = 0
    wipe(eventCounts)
    wipe(requestCounts)
    wipe(requestRuns)
    wipe(lastSample)
    anomalies = 0
    sampleElapsed = 0
end

local function Dump()
    CDM.Print("Glow diagnostic: events summary")
    local keys = {}
    for key in pairs(eventCounts) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        CDM.Print(string.format("[GLOW-DIAG] %s=%d", key, eventCounts[key]))
    end
    CDM.Print(string.format("[GLOW-DIAG] anomalies=%d", anomalies))

    for frame, stats in pairs(requestCounts) do
        local parts = {}
        for key, count in pairs(stats) do
            parts[#parts + 1] = key .. "=" .. count
        end
        table.sort(parts)
        if #parts > 0 then
            CDM.Print(string.format("[GLOW-DIAG] %s requests %s", FrameID(frame), table.concat(parts, " ")))
        end
    end

    local show = math.min(recordCount, 70)
    CDM.Print(string.format("Glow diagnostic: showing last %d/%d records", show, recordCount))
    if show == 0 then return end

    local start = recordHead - show + 1
    while start <= 0 do start = start + MAX_RECORDS end
    for i = 0, show - 1 do
        local index = ((start + i - 1) % MAX_RECORDS) + 1
        local line = records[index]
        if line then
            print("|cff66ffcc[KCDM-GLOW]|r " .. line)
        end
    end
end

SLASH_KCDMGLOWDIAG1 = "/kcdmglowdiag"
SlashCmdList.KCDMGLOWDIAG = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "on" or msg == "start" then
        Reset()
        enabled = true
        driver:Show()
        CDM.Print("Glow diagnostic ON. Reproduce el problema y usa /kcdmglowdiag dump.")
        return
    end

    if msg == "off" or msg == "stop" then
        enabled = false
        driver:Hide()
        CDM.Print("Glow diagnostic OFF.")
        return
    end

    if msg == "reset" then
        Reset()
        CDM.Print("Glow diagnostic reset.")
        return
    end

    if msg == "dump" or msg == "" then
        Dump()
        return
    end

    CDM.Print("Uso: /kcdmglowdiag on | dump | reset | off")
end
