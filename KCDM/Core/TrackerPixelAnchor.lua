local AddonName = "KCDM"
local CDM = _G[AddonName]
if not CDM or not CDM.Pixel then return end

local Pixel = CDM.Pixel
if Pixel._trackerVisualEdgeHooked then return end
Pixel._trackerVisualEdgeHooked = true

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

local function IsSupportedTrackerPlayerAnchor(frame, relativeTo)
    if not frame or not relativeTo or not frame.GetName or not relativeTo.GetName then
        return false
    end

    local frameName = frame:GetName()
    local relativeName = relativeTo:GetName()
    return TRACKER_CONTAINERS[frameName] == true and PLAYER_FRAME_NAMES[relativeName] == true
end

local function GetVisualEdgeCompensation(relativePoint)
    if Pixel.Update then
        Pixel.Update()
    end

    local pixel = Pixel.GetSize and Pixel.GetSize() or nil
    if not pixel or pixel <= 0 then
        return 0
    end

    if relativePoint == "TOPLEFT"
        or relativePoint == "TOPRIGHT"
        or relativePoint == "BOTTOMLEFT"
        or relativePoint == "BOTTOMRIGHT"
    then
        return -pixel
    end

    return 0
end

Pixel.SetPoint = function(frame, point, relativeTo, relativePoint, x, y)
    if not IsSupportedTrackerPlayerAnchor(frame, relativeTo) then
        return originalSetPoint(frame, point, relativeTo, relativePoint, x, y)
    end

    local compensatedY = (y or 0) + GetVisualEdgeCompensation(relativePoint)
    return originalSetPoint(frame, point, relativeTo, relativePoint, x, compensatedY)
end
