local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
local Shared = ns and ns.GroupEditorShared
if not ns or not UI then return end

if ns.cdmResponsiveOptionsHooked then return end
ns.cdmResponsiveOptionsHooked = true

local function FitScrollChild(scrollFrame, scrollChild, minWidth, rightPadding)
    if not scrollFrame or not scrollChild then return end

    minWidth = minWidth or 0
    rightPadding = rightPadding or 18

    local function ApplyWidth(width)
        width = tonumber(width) or scrollFrame:GetWidth() or 0
        if width <= 1 then return end
        scrollChild:SetWidth(math.max(minWidth, width - rightPadding))
    end

    scrollFrame:HookScript("OnSizeChanged", function(_, width)
        ApplyWidth(width)
    end)

    C_Timer.After(0, function()
        ApplyWidth(scrollFrame:GetWidth())
    end)
end

if type(UI.CreateScrollableTab) == "function" then
    local originalCreateScrollableTab = UI.CreateScrollableTab
    UI.CreateScrollableTab = function(page, frameName, contentHeight, contentWidth)
        local contentContainer, scrollFrame = originalCreateScrollableTab(page, frameName, contentHeight, contentWidth)
        local scrollChild = scrollFrame and scrollFrame:GetScrollChild()
        FitScrollChild(scrollFrame, scrollChild, contentWidth or 460, 18)
        return contentContainer, scrollFrame
    end
end

if type(UI.MakeSubPageScroll) == "function" then
    local originalMakeSubPageScroll = UI.MakeSubPageScroll
    UI.MakeSubPageScroll = function(subPage, frameName)
        local rc, sc = originalMakeSubPageScroll(subPage, frameName)
        local sf = sc and sc:GetParent()
        FitScrollChild(sf, sc, 540, 18)
        return rc, sc
    end
end

if type(UI.CreateModernSlider) == "function" then
    local originalCreateModernSlider = UI.CreateModernSlider
    UI.CreateModernSlider = function(parent, label, minVal, maxVal, currentVal, onValueChanged, labelWidth, sliderWidth)
        local effectiveLabelWidth = labelWidth or 200
        local effectiveSliderWidth = sliderWidth or 320
        return originalCreateModernSlider(
            parent,
            label,
            minVal,
            maxVal,
            currentVal,
            onValueChanged,
            effectiveLabelWidth,
            effectiveSliderWidth
        )
    end
end

if type(UI.CreateModernSliderPrecise) == "function" then
    local originalCreateModernSliderPrecise = UI.CreateModernSliderPrecise
    UI.CreateModernSliderPrecise = function(parent, label, minVal, maxVal, currentVal, step, decimals, onValueChanged)
        local panel = originalCreateModernSliderPrecise(parent, label, minVal, maxVal, currentVal, step, decimals, onValueChanged)
        if panel then
            panel:SetWidth(524)
            if panel.Label then
                panel.Label:SetWidth(200)
            end
            if panel.Slider then
                panel.Slider:SetWidth(320)
            end
        end
        return panel
    end
end

if type(UI.CreateModernCheckbox) == "function" then
    local originalCreateModernCheckbox = UI.CreateModernCheckbox
    UI.CreateModernCheckbox = function(parent, label, initialValue, onChange, ...)
        local frame = originalCreateModernCheckbox(parent, label, initialValue, onChange, ...)
        if frame and frame.SetWidth then
            frame:SetWidth(520)
        end
        return frame
    end
end

if Shared and type(Shared.CreateRightPanelManager) == "function" then
    local originalCreateRightPanelManager = Shared.CreateRightPanelManager
    Shared.CreateRightPanelManager = function(rightPanel, placeholder, destroyFrame)
        local manager = originalCreateRightPanelManager(rightPanel, placeholder, destroyFrame)
        if not manager or type(manager.CreateScrollContent) ~= "function" then
            return manager
        end

        local originalCreateScrollContent = manager.CreateScrollContent
        manager.CreateScrollContent = function(minHeight)
            local sf, rc = originalCreateScrollContent(minHeight)
            local sc = sf and sf:GetScrollChild()
            FitScrollChild(sf, sc, 400, 18)
            if sf and rc then
                local function ResizeContent(width)
                    width = tonumber(width) or sf:GetWidth() or 0
                    if width > 1 then
                        rc:SetWidth(math.max(400, width - 18))
                    end
                end
                sf:HookScript("OnSizeChanged", function(_, width)
                    ResizeContent(width)
                end)
                C_Timer.After(0, function()
                    ResizeContent(sf:GetWidth())
                end)
            end
            return sf, rc
        end

        return manager
    end
end
