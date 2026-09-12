local Runtime = _G["KCDM"]
if not Runtime then return end

local ns = Runtime._OptionsNS
local UI = ns and ns.ConfigUI
local Shared = ns and ns.GroupEditorShared
local L = Runtime.L

if not UI or not Shared or type(Shared.BuildTextOverrideWidgets) ~= "function" then return end
if Shared._perSpellGlowTypeWrapped then return end

local originalBuildTextOverrideWidgets = Shared.BuildTextOverrideWidgets
Shared._perSpellGlowTypeWrapped = true

local NESTED_INDENT = 20

local GLOW_TYPE_OPTIONS = {
    { value = "pixel", label = L["Pixel Glow"] },
    { value = "autocast", label = L["Autocast Glow"] },
    { value = "button", label = L["Button Glow"] },
    { value = "proc", label = L["Proc Glow"] },
}

local function IsCooldownSpellTextConfig(cfg)
    local fields = cfg and cfg.fields
    return cfg and cfg.showHeader == true
        and fields
        and fields.chargeSize == "chargeFontSize"
        and fields.chargeColor == "chargeColor"
end

local function GetGlobalGlowType()
    local db = Runtime.db or {}
    local defaults = Runtime.defaults or {}
    local glowType = db.glowType
    if glowType == nil then glowType = defaults.glowType end
    if glowType ~= "pixel" and glowType ~= "autocast" and glowType ~= "button" and glowType ~= "proc" then
        glowType = "proc"
    end
    return glowType
end

local function BuildSpellGlowTypeOptions()
    local globalType = GetGlobalGlowType()
    local globalLabel = UI.GetOptionLabel(GLOW_TYPE_OPTIONS, globalType, L["Proc Glow"])

    return {
        { value = "global", label = L["Global"] .. " (" .. globalLabel .. ")" },
        GLOW_TYPE_OPTIONS[1],
        GLOW_TYPE_OPTIONS[2],
        GLOW_TYPE_OPTIONS[3],
        GLOW_TYPE_OPTIONS[4],
    }
end

Shared.BuildTextOverrideWidgets = function(rc, yOff, cfg)
    if IsCooldownSpellTextConfig(cfg) then
        local existingOv = cfg.existingOv
        local selectedValue = existingOv and existingOv.glowTypeOverride or "global"
        local options = BuildSpellGlowTypeOptions()

        local label = rc:CreateFontString(nil, "ARTWORK", "KCDM_Font14")
        label:SetText(L["Glow Type"])
        label:SetPoint("TOPLEFT", NESTED_INDENT, yOff)
        yOff = yOff - 24

        local dropdown
        if cfg.createDropdown then
            dropdown = cfg.createDropdown(rc)
        else
            dropdown = CreateFrame("DropdownButton", nil, rc, "WowStyle1DropdownTemplate")
        end
        dropdown:SetPoint("TOPLEFT", NESTED_INDENT, yOff)
        dropdown:SetWidth(200)
        dropdown:SetDefaultText(UI.GetOptionLabel(options, selectedValue, options[1].label))

        UI.SetupValueDropdown(
            dropdown,
            options,
            function()
                local ov = cfg.existingOv
                return ov and ov.glowTypeOverride or "global"
            end,
            function(value, optionLabel)
                local ov = cfg.ensureOv and cfg.ensureOv()
                if not ov then return end

                ov.glowTypeOverride = value ~= "global" and value or nil
                dropdown:SetDefaultText(optionLabel)

                if cfg.save then
                    cfg.save()
                end

                if Runtime.Glow and Runtime.Glow.RefreshSpellGlowTypeOverrides then
                    Runtime.Glow:RefreshSpellGlowTypeOverrides()
                end

                if cfg.onToggle then
                    cfg.onToggle()
                end
            end
        )

        yOff = yOff - 48
    end

    return originalBuildTextOverrideWidgets(rc, yOff, cfg)
end
