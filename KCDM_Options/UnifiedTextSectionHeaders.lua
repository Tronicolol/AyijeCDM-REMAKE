local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
local Shared = ns and ns.GroupEditorShared
local L = Runtime.L
if not ns or not UI or not Shared or type(Shared.BuildTextOverrideWidgets) ~= "function" then return end

if ns.cdmUnifiedTextSectionHeadersHooked then return end
ns.cdmUnifiedTextSectionHeadersHooked = true

local originalBuildTextOverrideWidgets = Shared.BuildTextOverrideWidgets
local SECTION_SPACE = 28

local function CaptureObjects(parent)
    local objects = {}

    local children = { parent:GetChildren() }
    for _, object in ipairs(children) do
        objects[object] = true
    end

    local regions = { parent:GetRegions() }
    for _, object in ipairs(regions) do
        objects[object] = true
    end

    return objects
end

local function GetNewObjects(parent, before)
    local objects = {}

    local children = { parent:GetChildren() }
    for _, object in ipairs(children) do
        if not before[object] then
            objects[#objects + 1] = object
        end
    end

    local regions = { parent:GetRegions() }
    for _, object in ipairs(regions) do
        if not before[object] then
            objects[#objects + 1] = object
        end
    end

    return objects
end

local function GetDirectAnchorY(object, parent)
    if not object.GetNumPoints or not object.GetPoint then return nil end

    for i = 1, object:GetNumPoints() do
        local _, relativeTo, _, _, y = object:GetPoint(i)
        if relativeTo == parent then
            return y or 0
        end
    end

    return nil
end

local function ShiftDirectParentAnchors(object, parent, delta)
    if not object.GetNumPoints or not object.GetPoint or not object.ClearAllPoints or not object.SetPoint then return end

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

    local changed = false
    for _, data in ipairs(points) do
        if data.relativeTo == parent then
            data.y = data.y + delta
            changed = true
        end
    end

    if not changed then return end

    object:ClearAllPoints()
    for _, data in ipairs(points) do
        object:SetPoint(data.point, data.relativeTo, data.relativePoint, data.x, data.y)
    end
end

local function FindCheckboxRow(objects, label)
    for _, object in ipairs(objects) do
        if object.label and object.label.GetText and object.label:GetText() == label then
            return object
        end
    end
    return nil
end

local function CreateSectionTitle(parent, text, y)
    local title = parent:CreateFontString(nil, "ARTWORK", "KCDM_Font14")
    title:SetPoint("TOPLEFT", 0, y)
    title:SetText(text)
    title:SetTextColor(0.64, 0.78, 0.92, 1)
    return title
end

Shared.BuildTextOverrideWidgets = function(rc, yOff, cfg)
    local before = CaptureObjects(rc)
    local resultY = originalBuildTextOverrideWidgets(rc, yOff, cfg)

    local existingOv = cfg and cfg.existingOv
    if not existingOv or existingOv.textOverride ~= true then
        return resultY
    end

    local objects = GetNewObjects(rc, before)
    local cooldownRow = FindCheckboxRow(objects, L["Hide Cooldown Timer"])
    local chargesRow = FindCheckboxRow(objects, L["Hide Charges"])
    if not cooldownRow or not chargesRow then
        return resultY
    end

    local cooldownY = GetDirectAnchorY(cooldownRow, rc)
    local chargesY = GetDirectAnchorY(chargesRow, rc)
    if cooldownY == nil or chargesY == nil then
        return resultY
    end

    local originalY = {}
    for _, object in ipairs(objects) do
        originalY[object] = GetDirectAnchorY(object, rc)
    end

    for _, object in ipairs(objects) do
        local objectY = originalY[object]
        if objectY ~= nil then
            local shift = 0
            if objectY <= cooldownY then
                shift = shift - SECTION_SPACE
            end
            if objectY <= chargesY then
                shift = shift - SECTION_SPACE
            end
            if shift ~= 0 then
                ShiftDirectParentAnchors(object, rc, shift)
            end
        end
    end

    CreateSectionTitle(rc, L["Cooldown Timer"] or "Cooldown Timer", cooldownY - 3)
    CreateSectionTitle(rc, L["Charges"] or "Charges", chargesY - SECTION_SPACE - 3)

    return resultY - (SECTION_SPACE * 2)
end
