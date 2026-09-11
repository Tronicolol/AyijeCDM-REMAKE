local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
local Shared = ns and ns.GroupEditorShared
local L = Runtime.L

if not UI or not Shared or type(Shared.BuildTextOverrideWidgets) ~= "function" then return end
if Shared._blizzardProcSuppressionWrapped then return end

local originalBuildTextOverrideWidgets = Shared.BuildTextOverrideWidgets
Shared._blizzardProcSuppressionWrapped = true

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
        local hideBlizzardProcGlow = existingOv and existingOv.hideBlizzardProcGlow or false

        local checkbox = UI.CreateModernCheckbox(
            rc,
            L["Hide Blizzard Proc Glow"],
            hideBlizzardProcGlow,
            function(checked)
                local ov = cfg.ensureOv and cfg.ensureOv()
                if not ov then return end

                ov.hideBlizzardProcGlow = checked or nil

                if cfg.save then
                    cfg.save()
                end

                if checked and Runtime.Glow and Runtime.Glow.RefreshBlizzardProcSuppression then
                    Runtime.Glow:RefreshBlizzardProcSuppression()
                end

                if cfg.onToggle then
                    cfg.onToggle()
                end
            end
        )
        checkbox:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 36
    end

    return originalBuildTextOverrideWidgets(rc, yOff, cfg)
end
