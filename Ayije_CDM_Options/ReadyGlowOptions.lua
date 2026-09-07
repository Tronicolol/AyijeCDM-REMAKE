local Runtime = _G["Ayije_CDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
local Shared = ns and ns.GroupEditorShared
local L = Runtime.L

if not UI or not Shared or type(Shared.BuildTextOverrideWidgets) ~= "function" then return end
if Shared._readyGlowResourceAwareWrapped then return end

local originalBuildTextOverrideWidgets = Shared.BuildTextOverrideWidgets
Shared._readyGlowResourceAwareWrapped = true

local function IsCooldownSpellTextConfig(cfg)
    local fields = cfg and cfg.fields
    return cfg and cfg.showHeader == true
        and fields
        and fields.chargeSize == "chargeFontSize"
        and fields.chargeColor == "chargeColor"
end

Shared.BuildTextOverrideWidgets = function(rc, yOff, cfg)
    if IsCooldownSpellTextConfig(cfg) then
        local existingOv = cfg.existingOv
        local readyGlowEnabled = existingOv and existingOv.readyGlowEnabled or false

        if readyGlowEnabled then
            local readyGlowResourceAware = existingOv.readyGlowResourceAware or false
            local checkbox = UI.CreateModernCheckbox(
                rc,
                L["Only When Usable"],
                readyGlowResourceAware,
                function(checked)
                    local ov = cfg.ensureOv and cfg.ensureOv()
                    if not ov then return end

                    ov.readyGlowResourceAware = checked or nil

                    if cfg.save then
                        cfg.save()
                    end

                    if cfg.onToggle then
                        cfg.onToggle()
                    end
                end
            )
            checkbox:SetPoint("TOPLEFT", 20, yOff)
            yOff = yOff - 36
        end
    end

    return originalBuildTextOverrideWidgets(rc, yOff, cfg)
end
