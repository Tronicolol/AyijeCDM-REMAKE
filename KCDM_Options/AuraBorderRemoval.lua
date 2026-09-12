local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
local L = Runtime.L
if not UI then return end

local pendingAuraBorderPicker = setmetatable({}, { __mode = "k" })

local previousCreateModernCheckbox = UI.CreateModernCheckbox
UI.CreateModernCheckbox = function(parent, label, checked, onChange, ...)
    if label == L["Aura Border Color"] then
        pendingAuraBorderPicker[parent] = true
        local row = previousCreateModernCheckbox(parent, label, false, function() end, ...)
        row:Hide()
        return row
    end

    return previousCreateModernCheckbox(parent, label, checked, onChange, ...)
end

local previousCreateSimpleColorPicker = UI.CreateSimpleColorPicker
UI.CreateSimpleColorPicker = function(parent, color, onChange, ...)
    local picker = previousCreateSimpleColorPicker(parent, color, onChange, ...)

    if pendingAuraBorderPicker[parent] then
        pendingAuraBorderPicker[parent] = nil
        picker:Hide()

        C_Timer.After(0, function()
            if not parent or not parent.GetRegions then return end
            for _, region in ipairs({ parent:GetRegions() }) do
                if region and region.IsObjectType and region:IsObjectType("FontString") and region.GetText then
                    local text = region:GetText()
                    if text == L["Border Color:"] then
                        region:Hide()
                    end
                end
            end
        end)
    end

    return picker
end
