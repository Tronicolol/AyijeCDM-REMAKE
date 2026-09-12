local Runtime = _G["KCDM"]
if not Runtime then return end

local API = Runtime.API
local ns = Runtime._OptionsNS
if not API or not ns then return end

local function ApplyItemsLabel()
    local tabs = ns.ConfigTabs
    if tabs and tabs.racials then
        tabs.racials.label = "Items"
    end
end

local function FindNavButton(label)
    local sidebar = ns.ConfigSidebar
    if not sidebar or not label then return nil end

    local children = { sidebar:GetChildren() }
    for _, child in ipairs(children) do
        local text = child.Text
        if text and text.GetText and text:GetText() == label then
            return child
        end
    end

    return nil
end

local function CapturePoint(frame)
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    if not point then return nil end

    return {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x or 0,
        y = y or 0,
    }
end

local function ApplyPoint(frame, anchor)
    if not frame or not anchor then return end

    frame:ClearAllPoints()
    frame:SetPoint(
        anchor.point,
        anchor.relativeTo,
        anchor.relativePoint,
        anchor.x,
        anchor.y
    )
end

local function ReorderFeatureButtons()
    ApplyItemsLabel()

    local tabs = ns.ConfigTabs
    if not tabs then return end

    local defensivesLabel = tabs.defensives and tabs.defensives.label
    local itemsLabel = tabs.racials and tabs.racials.label
    local resourcesLabel = tabs.resources and tabs.resources.label

    local defensivesButton = FindNavButton(defensivesLabel)
    local itemsButton = FindNavButton(itemsLabel)
    local resourcesButton = FindNavButton(resourcesLabel)
    if not defensivesButton or not itemsButton or not resourcesButton then return end

    local positions = {
        CapturePoint(defensivesButton),
        CapturePoint(itemsButton),
        CapturePoint(resourcesButton),
    }

    if not positions[1] or not positions[2] or not positions[3] then return end

    table.sort(positions, function(a, b)
        return a.y > b.y
    end)

    ApplyPoint(defensivesButton, positions[1])
    ApplyPoint(itemsButton, positions[2])
    ApplyPoint(resourcesButton, positions[3])
end

ApplyItemsLabel()

hooksecurefunc(API, "ShowConfig", function()
    C_Timer.After(0, ReorderFeatureButtons)
end)

hooksecurefunc(API, "RebuildConfigFrame", function()
    C_Timer.After(0, ReorderFeatureButtons)
end)

C_Timer.After(0, ReorderFeatureButtons)
