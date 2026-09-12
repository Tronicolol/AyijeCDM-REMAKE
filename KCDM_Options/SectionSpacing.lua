local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
if not ns or not UI or type(UI.CreateHeader) ~= "function" then return end

if ns.cdmSectionSpacingInstalled then return end
ns.cdmSectionSpacingInstalled = true

local MIN_ANCHORED_GAP = 30
local EXTRA_ABSOLUTE_GAP = 15
local pendingParents = setmetatable({}, { __mode = "k" })

local function CapturePoints(object)
    if not object or not object.GetNumPoints or not object.GetPoint then return nil end

    local points = {}
    for i = 1, object:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = object:GetPoint(i)
        points[#points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x or 0,
            y = y or 0,
        }
    end
    return points
end

local function RestorePoints(object, points)
    if not object or not points or not object.ClearAllPoints or not object.SetPoint then return end

    object:ClearAllPoints()
    for _, data in ipairs(points) do
        object:SetPoint(data.point, data.relativeTo, data.relativePoint, data.x, data.y)
    end
end

local function ShiftAllPoints(object, deltaY)
    if not deltaY or deltaY == 0 then return end

    local points = CapturePoints(object)
    if not points then return end

    for _, data in ipairs(points) do
        data.y = data.y + deltaY
    end
    RestorePoints(object, points)
end

local function ShiftDirectParentPoints(object, parent, deltaY)
    if not deltaY or deltaY == 0 then return end

    local points = CapturePoints(object)
    if not points then return end

    local changed = false
    for _, data in ipairs(points) do
        if data.relativeTo == parent then
            data.y = data.y + deltaY
            changed = true
        end
    end

    if changed then
        RestorePoints(object, points)
    end
end

local function GetPrimaryPoint(object)
    if not object or not object.GetNumPoints or not object.GetPoint then return nil end
    if object:GetNumPoints() < 1 then return nil end

    local point, relativeTo, relativePoint, x, y = object:GetPoint(1)
    return {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x or 0,
        y = y or 0,
    }
end

local function GetTopSafe(object)
    if not object or not object.GetTop then return nil end
    local ok, value = pcall(object.GetTop, object)
    if not ok then return nil end
    return value
end

local function CollectDirectObjects(parent)
    local objects = {}

    if parent.GetChildren then
        for _, child in ipairs({ parent:GetChildren() }) do
            objects[#objects + 1] = child
        end
    end

    if parent.GetRegions then
        for _, region in ipairs({ parent:GetRegions() }) do
            objects[#objects + 1] = region
        end
    end

    return objects
end

local function ApplySpacing(parent)
    pendingParents[parent] = nil
    if not parent or not parent.GetRegions then return end

    local headers = {}
    for _, region in ipairs({ parent:GetRegions() }) do
        if region and region.cdmSectionHeader then
            headers[#headers + 1] = region
        end
    end

    if #headers == 0 then return end

    table.sort(headers, function(a, b)
        local aTop = GetTopSafe(a)
        local bTop = GetTopSafe(b)
        if aTop and bTop and aTop ~= bTop then
            return aTop > bTop
        end

        local aPoint = GetPrimaryPoint(a)
        local bPoint = GetPrimaryPoint(b)
        return (aPoint and aPoint.y or 0) > (bPoint and bPoint.y or 0)
    end)

    if not headers[1].cdmSectionGapApplied then
        headers[1].cdmSectionGapApplied = true
    end

    for index = 2, #headers do
        local header = headers[index]
        if not header.cdmSectionGapApplied then
            local point = GetPrimaryPoint(header)
            local deltaY = 0

            if point and point.relativeTo and point.relativeTo ~= parent and point.y < 0 then
                if point.y > -MIN_ANCHORED_GAP then
                    deltaY = -MIN_ANCHORED_GAP - point.y
                end

                if deltaY ~= 0 then
                    ShiftAllPoints(header, deltaY)
                end
            else
                deltaY = -EXTRA_ABSOLUTE_GAP
                local headerTop = GetTopSafe(header)

                if headerTop then
                    for _, object in ipairs(CollectDirectObjects(parent)) do
                        if object ~= header then
                            local objectTop = GetTopSafe(object)
                            if objectTop and objectTop <= headerTop + 0.5 then
                                ShiftDirectParentPoints(object, parent, deltaY)
                            end
                        end
                    end
                end

                ShiftAllPoints(header, deltaY)
            end

            header.cdmSectionGapApplied = true
        end
    end
end

local function ScheduleSpacing(parent)
    if not parent or pendingParents[parent] then return end
    pendingParents[parent] = true

    C_Timer.After(0, function()
        ApplySpacing(parent)
    end)
end

local originalCreateHeader = UI.CreateHeader
UI.CreateHeader = function(parent, text, anchorFrame, yOffset)
    local header = originalCreateHeader(parent, text, anchorFrame, yOffset)
    header.cdmSectionHeader = true
    ScheduleSpacing(parent)
    return header
end
