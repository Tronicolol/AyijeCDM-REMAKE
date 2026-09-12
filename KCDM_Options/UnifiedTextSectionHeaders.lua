local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
local Shared = ns and ns.GroupEditorShared
local L = Runtime.L
local CDM_C = Runtime.CONST or {}
if not ns or not UI or not Shared or type(Shared.BuildTextOverrideWidgets) ~= "function" then return end

if ns.cdmUnifiedTextSectionHeadersHooked then return end
ns.cdmUnifiedTextSectionHeadersHooked = true

local originalBuildTextOverrideWidgets = Shared.BuildTextOverrideWidgets
local MAIN_HEADER_SPACE = 34
local SECTION_SPACE = 42
local SECTION_TITLE_OFFSET = 9

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

local function HasText(objects, text)
    for _, object in ipairs(objects) do
        if object.GetText and object:GetText() == text then
            return true
        end
    end
    return false
end

local function CreateMainTitle(parent, y)
    local title = parent:CreateFontString(nil, "ARTWORK", "KCDM_Font18")
    title:SetPoint("TOPLEFT", 0, y)
    title:SetText(L["Text Overrides"] or "Text Overrides")

    local gold = CDM_C.GOLD or { r = 1, g = 0.82, b = 0 }
    title:SetTextColor(gold.r or 1, gold.g or 0.82, gold.b or 0, 1)
    return title
end

local function CreateSectionTitle(parent, text, y)
    local title = parent:CreateFontString(nil, "ARTWORK", "KCDM_Font18")
    title:SetPoint("TOPLEFT", 0, y)
    title:SetText(text)
    title:SetTextColor(0.46, 0.72, 0.96, 1)
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
    local overrideRow = FindCheckboxRow(objects, L["Override Text Settings"])
    local cooldownRow = FindCheckboxRow(objects, L["Hide Cooldown Timer"])
    local chargesRow = FindCheckboxRow(objects, L["Hide Charges"])
    if not overrideRow or not cooldownRow or not chargesRow then
        return resultY
    end

    local overrideY = GetDirectAnchorY(overrideRow, rc)
    local cooldownY = GetDirectAnchorY(cooldownRow, rc)
    local chargesY = GetDirectAnchorY(chargesRow, rc)
    if overrideY == nil or cooldownY == nil or chargesY == nil then
        return resultY
    end

    local originalY = {}
    for _, object in ipairs(objects) do
        originalY[object] = GetDirectAnchorY(object, rc)
    end

    local hasMainTitle = HasText(objects, L["Text Overrides"] or "Text Overrides")
    local mainShift = hasMainTitle and 0 or -MAIN_HEADER_SPACE

    for _, object in ipairs(objects) do
        local objectY = originalY[object]
        if objectY ~= nil then
            local shift = 0

            if not hasMainTitle and objectY <= overrideY then
                shift = shift - MAIN_HEADER_SPACE
            end
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

    if not hasMainTitle then
        CreateMainTitle(rc, overrideY - 2)
    end

    CreateSectionTitle(
        rc,
        L["Cooldown Timer"] or "Cooldown Timer",
        cooldownY + mainShift - SECTION_TITLE_OFFSET
    )

    CreateSectionTitle(
        rc,
        L["Charges"] or "Charges",
        chargesY + mainShift - SECTION_SPACE - SECTION_TITLE_OFFSET
    )

    local extraHeight = SECTION_SPACE * 2
    if not hasMainTitle then
        extraHeight = extraHeight + MAIN_HEADER_SPACE
    end

    return resultY - extraHeight
end
