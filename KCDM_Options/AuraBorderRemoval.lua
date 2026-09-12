local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
local L = Runtime.L
if not UI then return end

local HIDDEN_SECTION_HEIGHT = 60
local NESTED_TEXT_X = 64
local NESTED_CHECKBOX_X = 30
local pendingAuraBorderPicker = setmetatable({}, { __mode = "k" })

local function GetDirectAnchorY(object, parent)
    if not object or not object.GetNumPoints or not object.GetPoint then return nil end

    for i = 1, object:GetNumPoints() do
        local _, relativeTo, _, _, y = object:GetPoint(i)
        if relativeTo == parent then
            return y or 0
        end
    end

    return nil
end

local function ShiftDirectParentAnchors(object, parent, deltaY)
    if not object or not object.GetNumPoints or not object.GetPoint or not object.ClearAllPoints or not object.SetPoint then return end

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
            data.y = data.y + deltaY
            changed = true
        end
    end

    if not changed then return end

    object:ClearAllPoints()
    for _, data in ipairs(points) do
        object:SetPoint(data.point, data.relativeTo, data.relativePoint, data.x, data.y)
    end
end

local function SetDirectTopLeftX(object, parent, targetX)
    if not object or not object.GetNumPoints or not object.GetPoint or not object.ClearAllPoints or not object.SetPoint then return end

    local points = {}
    local changed = false

    for i = 1, object:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = object:GetPoint(i)
        local data = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x or 0,
            y = y or 0,
        }

        if point == "TOPLEFT" and relativeTo == parent then
            data.x = targetX
            changed = true
        end

        points[#points + 1] = data
    end

    if not changed then return end

    object:ClearAllPoints()
    for _, data in ipairs(points) do
        object:SetPoint(data.point, data.relativeTo, data.relativePoint, data.x, data.y)
    end
end

local function FindCheckboxRow(parent, label)
    if not parent or not parent.GetChildren or not label then return nil end

    for _, object in ipairs({ parent:GetChildren() }) do
        if object and object.label and object.label.GetText and object.label:GetText() == label then
            return object
        end
    end

    return nil
end

local function HasAuraOrReadyGlowControls(parent)
    if not parent then return false end

    return FindCheckboxRow(parent, L["Show Aura Overlay"]) ~= nil
        or FindCheckboxRow(parent, L["Glow When Ready"]) ~= nil
        or FindCheckboxRow(parent, L["Glow When CD Ready"]) ~= nil
end

local function NormalizeNestedLayout(parent)
    if not HasAuraOrReadyGlowControls(parent) then return end

    local nestedCheckboxLabels = {
        L["Desaturate when inactive"],
        L["Aura Glow"],
        L["Only When Usable"],
    }

    for _, label in ipairs(nestedCheckboxLabels) do
        if label then
            local row = FindCheckboxRow(parent, label)
            if row then
                SetDirectTopLeftX(row, parent, NESTED_CHECKBOX_X)
            end
        end
    end

    if parent.GetRegions then
        for _, region in ipairs({ parent:GetRegions() }) do
            if region and region.IsObjectType and region:IsObjectType("FontString") and region.GetText then
                if region:GetText() == L["Glow Color:"] then
                    SetDirectTopLeftX(region, parent, NESTED_TEXT_X)
                end
            end
        end
    end
end

local function FindBorderColorLabel(parent)
    if not parent or not parent.GetRegions then return nil end

    for _, region in ipairs({ parent:GetRegions() }) do
        if region and region.IsObjectType and region:IsObjectType("FontString") and region.GetText then
            if region:GetText() == L["Border Color:"] then
                return region
            end
        end
    end

    return nil
end

local function ReclaimHiddenAuraBorderGap(parent, data)
    if not parent or parent.cdmAuraBorderGapReclaimed then
        NormalizeNestedLayout(parent)
        return
    end
    if not data or not data.row then return end

    local rowY = GetDirectAnchorY(data.row, parent)
    local label = FindBorderColorLabel(parent)
    local labelY = GetDirectAnchorY(label, parent)
    if rowY == nil or labelY == nil then
        NormalizeNestedLayout(parent)
        return
    end

    data.row:Hide()
    if label then label:Hide() end
    if data.picker then data.picker:Hide() end

    local objects = {}
    for _, object in ipairs({ parent:GetChildren() }) do
        objects[#objects + 1] = object
    end
    for _, object in ipairs({ parent:GetRegions() }) do
        objects[#objects + 1] = object
    end

    for _, object in ipairs(objects) do
        if object ~= data.row and object ~= label and object ~= data.picker then
            local objectY = GetDirectAnchorY(object, parent)
            if objectY ~= nil and objectY < labelY then
                ShiftDirectParentAnchors(object, parent, HIDDEN_SECTION_HEIGHT)
            end
        end
    end

    local height = parent.GetHeight and parent:GetHeight() or nil
    if height and height > HIDDEN_SECTION_HEIGHT then
        parent:SetHeight(height - HIDDEN_SECTION_HEIGHT)
    end

    parent.cdmAuraBorderGapReclaimed = true
    NormalizeNestedLayout(parent)
end

local previousCreateModernCheckbox = UI.CreateModernCheckbox
UI.CreateModernCheckbox = function(parent, label, checked, onChange, ...)
    if label == L["Aura Border Color"] then
        local row = previousCreateModernCheckbox(parent, label, false, function() end, ...)
        row:Hide()
        pendingAuraBorderPicker[parent] = { row = row }
        return row
    end

    return previousCreateModernCheckbox(parent, label, checked, onChange, ...)
end

local previousCreateSimpleColorPicker = UI.CreateSimpleColorPicker
UI.CreateSimpleColorPicker = function(parent, color, onChange, ...)
    local picker = previousCreateSimpleColorPicker(parent, color, onChange, ...)
    local data = pendingAuraBorderPicker[parent]

    if data then
        pendingAuraBorderPicker[parent] = nil
        data.picker = picker
        picker:Hide()
    end

    C_Timer.After(0, function()
        if data then
            ReclaimHiddenAuraBorderGap(parent, data)
        else
            NormalizeNestedLayout(parent)
        end
    end)

    return picker
end
