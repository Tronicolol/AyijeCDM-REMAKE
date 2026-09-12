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
local MAIN_TITLE_SPACE = 34
local SECTION_SPACE = 42
local SECTION_TITLE_GAP = 30

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

local function FindTextRegion(objects, text)
    for _, object in ipairs(objects) do
        if object.GetText and object:GetText() == text then
            return object
        end
    end
    return nil
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
    local objects = GetNewObjects(rc, before)

    local overrideRow = FindCheckboxRow(objects, L["Override Text Settings"])
    if not overrideRow then
        return resultY
    end

    local overrideY = GetDirectAnchorY(overrideRow, rc)
    if overrideY == nil then
        return resultY
    end

    local mainText = L["Text Overrides"] or "Text Overrides"
    local mainTitle = FindTextRegion(objects, mainText)
    local mainTitleY = mainTitle and GetDirectAnchorY(mainTitle, rc) or nil
    local reclaim = 0
    if mainTitleY ~= nil and mainTitleY > overrideY then
        reclaim = math.max(0, mainTitleY - overrideY)
    end

    local cooldownRow = FindCheckboxRow(objects, L["Hide Cooldown Timer"])
    local chargesRow = FindCheckboxRow(objects, L["Hide Charges"])
    local cooldownY = cooldownRow and GetDirectAnchorY(cooldownRow, rc) or nil
    local chargesY = chargesRow and GetDirectAnchorY(chargesRow, rc) or nil
    local expanded = cooldownY ~= nil and chargesY ~= nil

    local originalY = {}
    for _, object in ipairs(objects) do
        originalY[object] = GetDirectAnchorY(object, rc)
    end

    for _, object in ipairs(objects) do
        if object ~= mainTitle then
            local objectY = originalY[object]
            if objectY ~= nil then
                local shift = 0

                if reclaim > 0 and objectY <= overrideY then
                    shift = shift + reclaim
                end

                if expanded and objectY <= cooldownY then
                    shift = shift - MAIN_TITLE_SPACE - SECTION_SPACE
                end

                if expanded and objectY <= chargesY then
                    shift = shift - SECTION_SPACE
                end

                if shift ~= 0 then
                    ShiftDirectParentAnchors(object, rc, shift)
                end
            end
        end
    end

    local finalOverrideY = overrideY + reclaim
    local mainTitleTargetY = finalOverrideY - MAIN_TITLE_SPACE

    if mainTitle then
        mainTitle:ClearAllPoints()
        mainTitle:SetPoint("TOPLEFT", 0, mainTitleTargetY)
    else
        mainTitle = CreateMainTitle(rc, mainTitleTargetY)
    end

    if not expanded then
        return resultY + reclaim - MAIN_TITLE_SPACE
    end

    local finalCooldownY = cooldownY + reclaim - MAIN_TITLE_SPACE - SECTION_SPACE
    local finalChargesY = chargesY + reclaim - MAIN_TITLE_SPACE - (SECTION_SPACE * 2)

    CreateSectionTitle(
        rc,
        L["Cooldown Timer"] or "Cooldown Timer",
        finalCooldownY + SECTION_TITLE_GAP
    )

    CreateSectionTitle(
        rc,
        L["Charges"] or "Charges",
        finalChargesY + SECTION_TITLE_GAP
    )

    return resultY + reclaim - MAIN_TITLE_SPACE - (SECTION_SPACE * 2)
end
