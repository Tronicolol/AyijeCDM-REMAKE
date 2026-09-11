local Runtime = _G["KCDM"]
if not Runtime then return end

local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns and ns.ConfigUI
local L = Runtime.L
if not ns or not UI or not API then return end

local BAR_KEY = "Whirlwind"
local CLASS_KEY = "WARRIOR"
local FURY_SPEC_ID = 72

if ns.BAR_DISPLAY_NAMES then
    ns.BAR_DISPLAY_NAMES[BAR_KEY] = L["Whirlwind"] or "Whirlwind"
end

-- Resources_Conditions defines this before this file is loaded. Wrap it so the
-- Whirlwind resource is shown as active only for Fury without adding it to the
-- core power map (the runtime bar is intentionally managed by its own tracker).
if ns.IsBarActiveForSpec and not ns.cdmWhirlwindActiveSpecHooked then
    ns.cdmWhirlwindActiveSpecHooked = true
    local originalIsBarActiveForSpec = ns.IsBarActiveForSpec

    ns.IsBarActiveForSpec = function(barKey, specID)
        if barKey == BAR_KEY then
            return specID == FURY_SPEC_ID
        end
        return originalIsBarActiveForSpec(barKey, specID)
    end
end

-- Mark the exact moment Resources.lua asks for Whirlwind's Bar Spacing value.
-- The generic Resources UI normally shows Bar Spacing for bar-to-bar anchors;
-- for Whirlwind we replace that single control with X/Y offsets instead.
if CDM.GetBarSettingForClass and not ns.cdmWhirlwindBarSettingContextHooked then
    ns.cdmWhirlwindBarSettingContextHooked = true
    local originalGetBarSettingForClass = CDM.GetBarSettingForClass

    CDM.GetBarSettingForClass = function(self, classKey, barKey, settingKey)
        if settingKey == "barSpacing" then
            ns.cdmWhirlwindSpacingContext = classKey == CLASS_KEY and barKey == BAR_KEY
        end
        return originalGetBarSettingForClass(self, classKey, barKey, settingKey)
    end
end

if UI.CreateModernSlider and not ns.cdmWhirlwindOffsetSliderHooked then
    ns.cdmWhirlwindOffsetSliderHooked = true
    local originalCreateModernSlider = UI.CreateModernSlider
    local barSpacingLabel = L["Bar Spacing"]

    UI.CreateModernSlider = function(parent, label, minVal, maxVal, currentVal, onValueChanged, labelWidth, sliderWidth)
        if label == barSpacingLabel and ns.cdmWhirlwindSpacingContext then
            ns.cdmWhirlwindSpacingContext = false

            local row = CreateFrame("Frame", nil, parent)
            row:SetSize(390, 40)

            local xSlider = originalCreateModernSlider(
                row,
                L["X Offset"],
                -600,
                600,
                CDM:GetBarSettingForClass(CLASS_KEY, BAR_KEY, "offsetX") or 0,
                function(value)
                    CDM:SetBarSettingForClass(CLASS_KEY, BAR_KEY, "offsetX", UI.RoundToInt(value))
                    API:Refresh("RESOURCES")
                end,
                55,
                120
            )
            xSlider:SetPoint("LEFT", row, "LEFT", 0, 0)

            local ySlider = originalCreateModernSlider(
                row,
                L["Y Offset"],
                -600,
                600,
                CDM:GetBarSettingForClass(CLASS_KEY, BAR_KEY, "offsetY") or 0,
                function(value)
                    CDM:SetBarSettingForClass(CLASS_KEY, BAR_KEY, "offsetY", UI.RoundToInt(value))
                    API:Refresh("RESOURCES")
                end,
                55,
                120
            )
            ySlider:SetPoint("LEFT", xSlider, "RIGHT", 16, 0)

            row.xSlider = xSlider
            row.ySlider = ySlider
            return row
        end

        ns.cdmWhirlwindSpacingContext = false
        return originalCreateModernSlider(parent, label, minVal, maxVal, currentVal, onValueChanged, labelWidth, sliderWidth)
    end
end
