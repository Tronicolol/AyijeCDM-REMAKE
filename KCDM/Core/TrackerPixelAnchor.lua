local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Pixel then return end

local Pixel = CDM.Pixel
if Pixel._trackerPhysicalPhaseHooked then return end
Pixel._trackerPhysicalPhaseHooked = true

local math_floor = math.floor
local originalSetPoint = Pixel.SetPoint

local TRACKER_CONTAINERS = {
    CDM_RacialsContainer = true,
    CDM_DefensivesContainer = true,
    CDM_TrinketsContainer = true,
}

local PLAYER_FRAME_NAMES = {
    ElvUF_Player = true,
    SUFUnitplayer = true,
    UUF_Player = true,
    EllesmereUIUnitFrames_Player = true,
    MSUF_player = true,
    EQOLUFPlayerFrame = true,
    oUF_Player = true,
    PlayerFrame = true,
}

local function HasHorizontalEdge(point)
    return point and (point:find("LEFT", 1, true) or point:find("RIGHT", 1, true))
end

local function HasVerticalEdge(point)
    return point and (point:find("TOP", 1, true) or point:find("BOTTOM", 1, true))
end

local function GetRequiredAnchorPhase(point, dimension, pixel, horizontal)
    local isEdge = horizontal and HasHorizontalEdge(point) or (not horizontal and HasVerticalEdge(point))
    if isEdge then return 0 end

    local dimensionPixels = math_floor((dimension or 0) / pixel + 0.5 + 0.001)
    return dimensionPixels % 2 == 1 and pixel * 0.5 or 0
end

local function GetRelativeAnchorCoordinate(frame, point, horizontal)
    if not frame then return nil end

    if horizontal then
        local left = frame:GetLeft()
        local right = frame:GetRight()
        if not left or not right then return nil end
        if point and point:find("LEFT", 1, true) then return left end
        if point and point:find("RIGHT", 1, true) then return right end
        return (left + right) * 0.5
    end

    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    if not top or not bottom then return nil end
    if point and point:find("TOP", 1, true) then return top end
    if point and point:find("BOTTOM", 1, true) then return bottom end
    return (top + bottom) * 0.5
end

local function SnapAbsoluteToPhase(value, phase, pixel, direction)
    local scaled = (value - phase) / pixel
    local lower = math_floor(scaled)
    local fraction = scaled - lower
    local epsilon = 0.001
    local snapped

    if fraction < 0.5 - epsilon then
        snapped = lower
    elseif fraction > 0.5 + epsilon then
        snapped = lower + 1
    elseif direction and direction < 0 then
        snapped = lower
    else
        snapped = lower + 1
    end

    return phase + snapped * pixel
end

local function SnapOffset(relativeTo, point, relativePoint, offset, dimension, horizontal, pixel)
    local reference = GetRelativeAnchorCoordinate(relativeTo, relativePoint, horizontal)
    if not reference then
        return nil
    end

    local phase = GetRequiredAnchorPhase(point, dimension, pixel, horizontal)
    local desired = reference + (offset or 0)
    local direction = offset and offset ~= 0 and (offset > 0 and 1 or -1) or nil
    local snapped = SnapAbsoluteToPhase(desired, phase, pixel, direction)

    return snapped - reference
end

local function IsSupportedTrackerPlayerAnchor(frame, relativeTo)
    if not frame or not relativeTo or not frame.GetName or not relativeTo.GetName then
        return false
    end

    local frameName = frame:GetName()
    local relativeName = relativeTo:GetName()
    return TRACKER_CONTAINERS[frameName] == true and PLAYER_FRAME_NAMES[relativeName] == true
end

Pixel.SetPoint = function(frame, point, relativeTo, relativePoint, x, y)
    if not IsSupportedTrackerPlayerAnchor(frame, relativeTo) then
        return originalSetPoint(frame, point, relativeTo, relativePoint, x, y)
    end

    if Pixel.Update then
        Pixel.Update()
    end

    local pixel = Pixel.GetSize and Pixel.GetSize() or nil
    if not pixel or pixel <= 0 then
        return originalSetPoint(frame, point, relativeTo, relativePoint, x, y)
    end

    local width = frame.GetWidth and frame:GetWidth() or 0
    local height = frame.GetHeight and frame:GetHeight() or 0
    local resolvedX = SnapOffset(relativeTo, point, relativePoint, x or 0, width, true, pixel)
    local resolvedY = SnapOffset(relativeTo, point, relativePoint, y or 0, height, false, pixel)

    if resolvedX == nil or resolvedY == nil then
        return originalSetPoint(frame, point, relativeTo, relativePoint, x, y)
    end

    -- These offsets may intentionally contain fractional UI units. Reapplying
    -- Pixel.Snap to them would undo the absolute physical-pixel correction.
    frame:SetPoint(point, relativeTo, relativePoint, resolvedX, resolvedY)
end
