local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
if not ns then return end

if ns.cdmRemovedControlsInstalled then return end
ns.cdmRemovedControlsInstalled = true

local REMOVED_RACIAL_KEYS = {
    racialsUsePartyFrame = true,
    racialsPartyFrameSide = true,
    racialsPartyFrameOffsetX = true,
    racialsPartyFrameOffsetY = true,
    racialsRaidFrameAnchorPoint = true,
    racialsRaidFrameRelativePoint = true,
    racialsRaidFrameOffsetX = true,
    racialsRaidFrameOffsetY = true,
}

local function RemoveRacialConfigKeys()
    local categories = ns.ConfigKeys and ns.ConfigKeys.categories
    local racialCategory = categories and categories.racials
    local keys = racialCategory and racialCategory.keys

    if type(keys) == "table" then
        for i = #keys, 1, -1 do
            if REMOVED_RACIAL_KEYS[keys[i]] then
                table.remove(keys, i)
            end
        end
    end

    if type(CDM.defaults) == "table" then
        for key in pairs(REMOVED_RACIAL_KEYS) do
            CDM.defaults[key] = nil
        end
    end

    if type(CDM.db) == "table" then
        for key in pairs(REMOVED_RACIAL_KEYS) do
            rawset(CDM.db, key, nil)
        end
    end
end

local function GetFrameText(frame)
    if not frame then return nil end

    if frame.GetText then
        local ok, text = pcall(frame.GetText, frame)
        if ok and type(text) == "string" then
            return text
        end
    end

    if frame.Text and frame.Text.GetText then
        return frame.Text:GetText()
    end

    return nil
end

local function FindButtonByText(root, wantedText)
    if not root or not root.GetChildren then return nil end

    for _, child in ipairs({ root:GetChildren() }) do
        if GetFrameText(child) == wantedText then
            return child
        end

        local found = FindButtonByText(child, wantedText)
        if found then return found end
    end

    return nil
end

local function FindFontStringByText(root, wantedText)
    if not root then return nil end

    if root.GetRegions then
        for _, region in ipairs({ root:GetRegions() }) do
            if region and region.IsObjectType and region:IsObjectType("FontString")
                and region.GetText and region:GetText() == wantedText
            then
                return region
            end
        end
    end

    if root.GetChildren then
        for _, child in ipairs({ root:GetChildren() }) do
            local found = FindFontStringByText(child, wantedText)
            if found then return found end
        end
    end

    return nil
end

local function DisableButton(button)
    if not button then return end

    if button.SetScript then
        button:SetScript("OnClick", nil)
    end
    if button.EnableMouse then
        button:EnableMouse(false)
    end
    if button.Hide then
        button:Hide()
    end
end

local function HideObject(object)
    if not object then return end

    if object.checkbox and object.checkbox.SetScript then
        object.checkbox:SetScript("OnClick", nil)
    end
    if object.SetScript then
        object:SetScript("OnClick", nil)
    end
    if object.EnableMouse then
        object:EnableMouse(false)
    end
    if object.Hide then
        object:Hide()
    end
end

local function RemoveBarAddSpell(page)
    DisableButton(FindButtonByText(page, L["Add Spell"]))
end

local function RemoveBuffGroupAddIcon(page)
    DisableButton(FindButtonByText(page, L["Add Icon"]))
end

local function RemoveRacialsPartyAnchorControls(page)
    local content = _G["KCDM_RacialsScrollFrame"]
    content = content and content:GetScrollChild() or nil
    if not content then return end

    local partyHeader = FindFontStringByText(content, L["Party Frame Anchoring"])
    if partyHeader then
        partyHeader.cdmSectionHeader = nil
        HideObject(partyHeader)
    end

    local fields = {
        "racialsUsePartyFrameCheckbox",
        "racialsPartyFrameSideLabel",
        "racialsPartyFrameSideDropdown",
        "racialsPartyFrameOffsetXSlider",
        "racialsPartyFrameOffsetYSlider",
        "racialsRaidFrameSubHeader",
        "racialsRaidFrameAnchorPointLabel",
        "racialsRaidFrameAnchorPointDropdown",
        "racialsRaidFrameRelativePointLabel",
        "racialsRaidFrameRelativePointDropdown",
        "racialsRaidFrameOffsetXSlider",
        "racialsRaidFrameOffsetYSlider",
    }

    for _, field in ipairs(fields) do
        HideObject(page[field])
    end

    local positionHeader = FindFontStringByText(content, L["Position"])
    if positionHeader and page.racialsIconHeightSlider then
        positionHeader:ClearAllPoints()
        positionHeader:SetPoint("TOPLEFT", page.racialsIconHeightSlider, "BOTTOMLEFT", 0, -30)
    end
end

local function WrapTab(tabId, afterCreate)
    local tab = ns.ConfigTabs and ns.ConfigTabs[tabId]
    if not tab or type(tab.createFunc) ~= "function" or tab.cdmRemovedControlsWrapped then return end

    tab.cdmRemovedControlsWrapped = true
    local originalCreate = tab.createFunc
    tab.createFunc = function(page, ...)
        originalCreate(page, ...)
        afterCreate(page)
    end
end

RemoveRacialConfigKeys()
WrapTab("bars", RemoveBarAddSpell)
WrapTab("buffgroups", RemoveBuffGroupAddIcon)
WrapTab("racials", RemoveRacialsPartyAnchorControls)
