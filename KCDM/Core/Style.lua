local AddonName = "KCDM"
local CDM = _G[AddonName]
local BORDER = CDM.BORDER
local LSM = LibStub("LibSharedMedia-3.0", true)
local CDM_C = CDM.CONST

local IsSafeNumber = CDM.IsSafeNumber
local GetColorForSpellID = CDM.GetColorForSpellID
local GetBaseSpellID = CDM.GetBaseSpellID
local GetSpellIDCandidates = CDM.GetSpellIDCandidates

local math_floor = math.floor
local math_max = math.max
local math_abs = math.abs
local GetTime = GetTime
local canaccessvalue = canaccessvalue
local select = select
local ipairs = ipairs
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellCooldownDuration = C_Spell.GetSpellCooldownDuration
local GetSpellChargeDuration = C_Spell.GetSpellChargeDuration
local GetSpellCharges = C_Spell.GetSpellCharges
local GetInventoryItemCooldown = GetInventoryItemCooldown
local TruncateWhenZero = C_StringUtil.TruncateWhenZero
local GetConfigValue = CDM_C.GetConfigValue
local DesaturationCurve = CDM_C.DesaturationCurve
local RealTime = Enum.DurationTimeModifier.RealTime
local EvaluateColorValueFromBoolean = C_CurveUtil.EvaluateColorValueFromBoolean

local VIEWERS = CDM_C.VIEWERS
local VIEWERS_WITH_OVERRIDE = CDM_C.VIEWERS_WITH_OVERRIDE
local Pixel = CDM.Pixel
local Snap = Pixel.Snap
local FontSize = Pixel.FontSize
local SetPoint = Pixel.SetPoint
local DisableTextureSnap = Pixel.DisableTextureSnap

local VIEWER_DESC = {
    [VIEWERS.ESSENTIAL] = {
        sizeKey      = "sizeEssRow1",
        sizeKey2     = "sizeEssRow2",
        cdFontKey    = "cooldownFontSize",
        cdFontKey2   = "essRow2CooldownFontSize",
        cdColorKey   = "cooldownColor",
        chargeKey    = "chargeFontSize",
        chargeKey2   = "essRow2ChargeFontSize",
        chargeColorKey = "chargeColor",
        chargePosKey  = "chargePosition",
        chargeOXKey   = "chargeOffsetX",
        chargeOYKey   = "chargeOffsetY",
        chargeColorKey2 = "essRow2ChargeColor",
        chargePosKey2 = "essRow2ChargePosition",
        chargeOXKey2  = "essRow2ChargeOffsetX",
        chargeOYKey2  = "essRow2ChargeOffsetY",
        isCooldown   = true,
        hasOverride  = true,
        hookType     = "cooldown",
    },
    [VIEWERS.UTILITY] = {
        sizeKey      = "sizeUtility",
        cdFontKey    = "utilityCooldownFontSize",
        cdColorKey   = "cooldownColor",
        chargeKey    = "utilityChargeFontSize",
        chargeColorKey = "utilityChargeColor",
        chargePosKey  = "utilityChargePosition",
        chargeOXKey   = "utilityChargeOffsetX",
        chargeOYKey   = "utilityChargeOffsetY",
        isCooldown   = true,
        hasOverride  = true,
        hookType     = "cooldown",
        hasUtilVisibility = true,
    },
    [VIEWERS.BUFF] = {
        sizeKey      = "sizeBuff",
        cdFontKey    = "buffCooldownFontSize",
        cdColorKey   = "buffCooldownColor",
        isBuff       = true,
        hasCount     = true,
        hookType     = "buff",
    },
    [VIEWERS.BUFF_BAR] = {
        hookType     = "bar",
    },
}

function CDM.RegisterViewerDesc(name, desc)
    VIEWER_DESC[name] = desc
end

local function ResolveIconSize(desc, row)
    local d = CDM.defaults
    if desc.widthKey then
        return GetConfigValue(desc.widthKey, d[desc.widthKey]),
               GetConfigValue(desc.heightKey, d[desc.heightKey])
    end
    local key = (desc.sizeKey2 and row == 2) and desc.sizeKey2 or desc.sizeKey
    local size = GetConfigValue(key, d[key])
    return size.w, size.h
end

local function GetAspectPreservingTexCoord(frameW, frameH, zoomPadding)
    if not frameH or frameH <= 0 then return 0, 1, 0, 1 end
    local padding = zoomPadding or 0
    local texWidth = 1 - (padding * 2)

    local aspectRatio = frameW / frameH
    local xRatio = aspectRatio < 1 and aspectRatio or 1
    local yRatio = aspectRatio > 1 and 1 / aspectRatio or 1

    local left   = -0.5 * texWidth * xRatio + 0.5
    local right  =  0.5 * texWidth * xRatio + 0.5
    local top    = -0.5 * texWidth * yRatio + 0.5
    local bottom =  0.5 * texWidth * yRatio + 0.5

    return left, right, top, bottom
end

function CDM_C.ApplyIconTexCoord(texture, zoomAmount, frameW, frameH)
    if not texture or not texture.SetTexCoord then return end
    local padding = (type(zoomAmount) == "number") and zoomAmount or 0
    if frameW and frameH and frameW > 0 and frameH > 0 then
        local left, right, top, bottom = GetAspectPreservingTexCoord(frameW, frameH, padding)
        texture:SetTexCoord(left, right, top, bottom)
    elseif padding > 0 then
        texture:SetTexCoord(padding, 1 - padding, padding, 1 - padding)
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local styleCache = {}
local lastStyleCacheVersion = -1

function CDM_C.GetEffectiveZoomAmount()
    if not styleCache.zoomIcons then return 0 end
    local v = styleCache.zoomAmount
    return (type(v) == "number") and v or 0.08
end

local cdFont = _G["KCDM_CDFont"] or CreateFont("KCDM_CDFont")
local cdFontBuff = _G["KCDM_CDFont_Buff"] or CreateFont("KCDM_CDFont_Buff")
local BLIZZARD_ICON_OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local BLIZZARD_ICON_MASK_ATLAS = "UI-HUD-CoolDownManager-Mask"
local BLIZZARD_ICON_OVERLAY_TEXTURE_FILE_ID = 6707800
local DEFAULT_COOLDOWN_ICON_SWIPE_TEXTURE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"

local function CfgValue(db, defaults, key, fallback)
    if db and db[key] ~= nil then return db[key] end
    if defaults[key] ~= nil then return defaults[key] end
    return fallback
end

local function RefreshStyleCache()
    local targetVersion = CDM.styleCacheVersion or 0
    if lastStyleCacheVersion == targetVersion then return end
    lastStyleCacheVersion = targetVersion

    local db = CDM.db
    local defaults = CDM.defaults or {}

    styleCache.zoomIcons = CfgValue(db, defaults, "zoomIcons", false)
    styleCache.zoomAmount = CfgValue(db, defaults, "zoomAmount", 0.08)
    styleCache.hideIconOverlay = CfgValue(db, defaults, "hideIconOverlay", true)
    styleCache.hideIconOverlayTexture = CfgValue(db, defaults, "hideIconOverlayTexture", true)
    styleCache.swipeColor = CfgValue(db, defaults, "swipeColor", CDM_C.SWIPE_COLOR)
    styleCache.hideGCDSwipe = CfgValue(db, defaults, "hideGCDSwipe", false)
    styleCache.hideBuffSwipe = CfgValue(db, defaults, "hideBuffSwipe", false)
    styleCache.disableCooldownDesat = CfgValue(db, defaults, "disableCooldownDesat", false)
    styleCache.cooldownIconColor = CfgValue(db, defaults, "cooldownIconColor", CDM_C.WHITE)
    styleCache.textFont = CfgValue(db, defaults, "textFont", "Friz Quadrata TT")
    local rawOutline = CfgValue(db, defaults, "textFontOutline", "OUTLINE")
    styleCache.textFontOutline = CDM_C.ResolveOutlineFlags(rawOutline)

    styleCache.cooldownFontSize = CfgValue(db, defaults, "cooldownFontSize", 12)
    styleCache.cooldownColor = CfgValue(db, defaults, "cooldownColor", CDM_C.WHITE)
    styleCache.racialsCooldownFontSize = CfgValue(db, defaults, "racialsCooldownFontSize", 12)
    styleCache.defensivesCooldownFontSize = CfgValue(db, defaults, "defensivesCooldownFontSize", 12)
    styleCache.trinketsCooldownFontSize = CfgValue(db, defaults, "trinketsCooldownFontSize", 12)
    styleCache.externalsCooldownFontSize = CfgValue(db, defaults, "externalsCooldownFontSize", 15)
    styleCache.essRow2CooldownFontSize = CfgValue(db, defaults, "essRow2CooldownFontSize", 15)
    styleCache.utilityCooldownFontSize = CfgValue(db, defaults, "utilityCooldownFontSize", 15)

    styleCache.chargeFontSize = CfgValue(db, defaults, "chargeFontSize", 12)
    styleCache.utilityChargeFontSize = CfgValue(db, defaults, "utilityChargeFontSize", 12)
    styleCache.essRow2ChargeFontSize = CfgValue(db, defaults, "essRow2ChargeFontSize", 15)
    styleCache.racialsChargeFontSize = CfgValue(db, defaults, "racialsChargeFontSize", 15)
    styleCache.defensivesChargeFontSize = CfgValue(db, defaults, "defensivesChargeFontSize", 15)
    styleCache.chargeColor = CfgValue(db, defaults, "chargeColor", CDM_C.WHITE)
    styleCache.chargePosition = CfgValue(db, defaults, "chargePosition", "BOTTOMRIGHT")
    styleCache.chargeOffsetX = CfgValue(db, defaults, "chargeOffsetX", 0)
    styleCache.chargeOffsetY = CfgValue(db, defaults, "chargeOffsetY", 0)
    styleCache.utilityChargeColor = CfgValue(db, defaults, "utilityChargeColor", CDM_C.WHITE)
    styleCache.utilityChargePosition = CfgValue(db, defaults, "utilityChargePosition", "BOTTOMRIGHT")
    styleCache.utilityChargeOffsetX = CfgValue(db, defaults, "utilityChargeOffsetX", 0)
    styleCache.utilityChargeOffsetY = CfgValue(db, defaults, "utilityChargeOffsetY", 0)
    styleCache.essRow2ChargeColor = CfgValue(db, defaults, "essRow2ChargeColor", CDM_C.WHITE)
    styleCache.essRow2ChargePosition = CfgValue(db, defaults, "essRow2ChargePosition", "BOTTOMRIGHT")
    styleCache.essRow2ChargeOffsetX = CfgValue(db, defaults, "essRow2ChargeOffsetX", 0)
    styleCache.essRow2ChargeOffsetY = CfgValue(db, defaults, "essRow2ChargeOffsetY", 0)

    styleCache.countFontSize = CfgValue(db, defaults, "countFontSize", 12)
    styleCache.countColor = CfgValue(db, defaults, "countColor", CDM_C.WHITE)

    styleCache.buffCooldownFontSize = CfgValue(db, defaults, "buffCooldownFontSize", 12)
    styleCache.buffCooldownColor = CfgValue(db, defaults, "buffCooldownColor", CDM_C.WHITE)

    styleCache.countPositionMain = CfgValue(db, defaults, "countPositionMain", "TOP")
    styleCache.countOffsetXMain = CfgValue(db, defaults, "countOffsetXMain", 0)
    styleCache.countOffsetYMain = CfgValue(db, defaults, "countOffsetYMain", 0)
    styleCache.borderColor = CfgValue(db, defaults, "borderColor", CDM_C.WHITE)

    styleCache.hideDebuffBorder = CfgValue(db, defaults, "hideDebuffBorder", false)
    styleCache.hidePandemicIndicator = CfgValue(db, defaults, "hidePandemicIndicator", false)
    styleCache.hideCooldownBling = CfgValue(db, defaults, "hideCooldownBling", false)

    styleCache.pandemicGlowEnabled = CfgValue(db, defaults, "pandemicGlowEnabled", false) == true
    styleCache.pandemicGlowType = CfgValue(db, defaults, "pandemicGlowType", "button") or "button"
    styleCache.pandemicGlowColor = CfgValue(db, defaults, "pandemicGlowColor", CDM_C.WHITE)

    local pandemicCustomizationEnabled = CfgValue(db, defaults, "pandemicCustomizationEnabled", false) == true
    local pandemicStylingActive = styleCache.hidePandemicIndicator == true
        and pandemicCustomizationEnabled
        and not styleCache.pandemicGlowEnabled
    styleCache.pandemicBorderEnabled = pandemicStylingActive and (CfgValue(db, defaults, "pandemicBorderEnabled", false) == true) or false
    styleCache.pandemicBorderColorBuffBars = styleCache.pandemicBorderEnabled and (CfgValue(db, defaults, "pandemicBorderColorBuffBars", false) == true) or false
    styleCache.pandemicBorderColor   = CfgValue(db, defaults, "pandemicBorderColor", CDM_C.WHITE)

    styleCache.chargeShowEdge  = CfgValue(db, defaults, "chargeShowEdge", false) == true
    styleCache.chargeHideSwipe = CfgValue(db, defaults, "chargeHideSwipe", false) == true
    styleCache.chargeHideRechargeTimer = CfgValue(db, defaults, "chargeHideRechargeTimer", false) == true

    styleCache.buffBarWidth = CfgValue(db, defaults, "buffBarWidth", 0)
    styleCache.buffBarHeight = CfgValue(db, defaults, "buffBarHeight", 20)
    styleCache.buffBarSpacing = CfgValue(db, defaults, "buffBarSpacing", 2)
    styleCache.buffBarGrowDirection = CfgValue(db, defaults, "buffBarGrowDirection", "DOWN")
    styleCache.buffBarIconPosition = CfgValue(db, defaults, "buffBarIconPosition", "LEFT")
    styleCache.buffBarIconGap = CfgValue(db, defaults, "buffBarIconGap", 2)
    styleCache.buffBarShowName = CfgValue(db, defaults, "buffBarShowName", true)
    styleCache.buffBarNameMaxChars = CfgValue(db, defaults, "buffBarNameMaxChars", 0)
    styleCache.buffBarShowDuration = CfgValue(db, defaults, "buffBarShowDuration", true)
    styleCache.buffBarTexture = CfgValue(db, defaults, "buffBarTexture", "Blizzard")
    styleCache.buffBarColor = CfgValue(db, defaults, "buffBarColor", { r = 0.4, g = 0.6, b = 0.9, a = 1 })
    styleCache.buffBarBackgroundColor = CfgValue(db, defaults, "buffBarBackgroundColor", { r = 0.1, g = 0.1, b = 0.1, a = 0.8 })
    styleCache.buffBarFillDirection = CfgValue(db, defaults, "buffBarFillDirection", "LEFT_TO_RIGHT")
    styleCache.buffBarNameFontSize = CfgValue(db, defaults, "buffBarNameFontSize", 12)
    styleCache.buffBarNameColor = CfgValue(db, defaults, "buffBarNameColor", { r = 1, g = 1, b = 1, a = 1 })
    styleCache.buffBarNameOffsetX = CfgValue(db, defaults, "buffBarNameOffsetX", 4)
    styleCache.buffBarNameOffsetY = CfgValue(db, defaults, "buffBarNameOffsetY", 0)
    styleCache.buffBarDurationFontSize = CfgValue(db, defaults, "buffBarDurationFontSize", 12)
    styleCache.buffBarDurationColor = CfgValue(db, defaults, "buffBarDurationColor", { r = 1, g = 1, b = 1, a = 1 })
    styleCache.buffBarDurationPosition = CfgValue(db, defaults, "buffBarDurationPosition", "RIGHT")
    styleCache.buffBarDurationOffsetX = CfgValue(db, defaults, "buffBarDurationOffsetX", -4)
    styleCache.buffBarDurationOffsetY = CfgValue(db, defaults, "buffBarDurationOffsetY", 0)
    styleCache.buffBarShowApplications = CfgValue(db, defaults, "buffBarShowApplications", true)
    styleCache.buffBarApplicationsFontSize = CfgValue(db, defaults, "buffBarApplicationsFontSize", 15)
    styleCache.buffBarApplicationsColor = CfgValue(db, defaults, "buffBarApplicationsColor", { r = 1, g = 1, b = 1, a = 1 })
    styleCache.buffBarApplicationsPosition = CfgValue(db, defaults, "buffBarApplicationsPosition", "RIGHT")
    styleCache.buffBarApplicationsOffsetX = CfgValue(db, defaults, "buffBarApplicationsOffsetX", -4)
    styleCache.buffBarApplicationsOffsetY = CfgValue(db, defaults, "buffBarApplicationsOffsetY", 0)
    styleCache.buffBarShowIcon = CfgValue(db, defaults, "buffBarShowIcon", true)
    styleCache.buffBarIconWidth = CfgValue(db, defaults, "buffBarIconWidth", 0)
    styleCache.buffBarIconHeight = CfgValue(db, defaults, "buffBarIconHeight", 0)
    styleCache.buffBarIconZoom = CfgValue(db, defaults, "buffBarIconZoom", true)
    styleCache.buffBarIconZoomAmount = CfgValue(db, defaults, "buffBarIconZoomAmount", 0.08)
    styleCache.buffBarBorderEnabled = CfgValue(db, defaults, "buffBarBorderEnabled", true)
    styleCache.buffBarBorderColor = CfgValue(db, defaults, "buffBarBorderColor", CDM_C.WHITE)
    styleCache.buffBarBackgroundTexture = CfgValue(db, defaults, "buffBarBackgroundTexture", "Blizzard")
    styleCache.buffBarBackgroundInset = CfgValue(db, defaults, "buffBarBackgroundInset", 0)
    styleCache.buffBarUseClassColor = CfgValue(db, defaults, "buffBarUseClassColor", false)
    styleCache.buffBarUseCustomName = CfgValue(db, defaults, "buffBarUseCustomName", false)
    styleCache.buffBarCustomName = CfgValue(db, defaults, "buffBarCustomName", "")
    styleCache.buffBarHideDebuffBorder = CfgValue(db, defaults, "buffBarHideDebuffBorder", false)
    styleCache.buffBarShowPandemic = CfgValue(db, defaults, "buffBarShowPandemic", true)
    styleCache.buffBarShowPandemicGlow = CfgValue(db, defaults, "buffBarShowPandemicGlow", false)
    styleCache.buffBarPandemicGlowType = CfgValue(db, defaults, "buffBarPandemicGlowType", "button")
    styleCache.buffBarPandemicGlowColor = CfgValue(db, defaults, "buffBarPandemicGlowColor", CDM_C.WHITE)
    styleCache.buffBarPandemicBorderEnabled = CfgValue(db, defaults, "buffBarPandemicBorderEnabled", false)
    styleCache.buffBarPandemicBorderColor = CfgValue(db, defaults, "buffBarPandemicBorderColor", CDM_C.WHITE)
    styleCache.buffBarPandemicBorderColorBuffBars = CfgValue(db, defaults, "buffBarPandemicBorderColorBuffBars", false)
    styleCache.buffBarCooldownReverse = CfgValue(db, defaults, "buffBarCooldownReverse", true)
    styleCache.buffBarCooldownShowEdge = CfgValue(db, defaults, "buffBarCooldownShowEdge", false)
    styleCache.buffBarCooldownShowSwipe = CfgValue(db, defaults, "buffBarCooldownShowSwipe", true)
    styleCache.buffBarCooldownSwipeColor = CfgValue(db, defaults, "buffBarCooldownSwipeColor", CDM_C.SWIPE_COLOR)
    styleCache.buffBarCooldownSwipeAlpha = CfgValue(db, defaults, "buffBarCooldownSwipeAlpha", 1)
    styleCache.buffBarCooldownHideNumbers = CfgValue(db, defaults, "buffBarCooldownHideNumbers", false)
    styleCache.buffBarCooldownDesaturate = CfgValue(db, defaults, "buffBarCooldownDesaturate", false)
    styleCache.buffBarCooldownIconColor = CfgValue(db, defaults, "buffBarCooldownIconColor", CDM_C.WHITE)
    styleCache.buffBarCooldownIconAlpha = CfgValue(db, defaults, "buffBarCooldownIconAlpha", 1)
    styleCache.buffBarTimeFormat = CfgValue(db, defaults, "buffBarTimeFormat", "AUTO")
    styleCache.buffBarTimeDecimals = CfgValue(db, defaults, "buffBarTimeDecimals", 1)
    styleCache.buffBarTimeThreshold = CfgValue(db, defaults, "buffBarTimeThreshold", 5)
    styleCache.buffBarNamePosition = CfgValue(db, defaults, "buffBarNamePosition", "LEFT")
    styleCache.buffBarNameJustifyH = CfgValue(db, defaults, "buffBarNameJustifyH", "LEFT")
    styleCache.buffBarDurationJustifyH = CfgValue(db, defaults, "buffBarDurationJustifyH", "RIGHT")
    styleCache.buffBarApplicationsJustifyH = CfgValue(db, defaults, "buffBarApplicationsJustifyH", "CENTER")
    styleCache.buffBarTextureOrientation = CfgValue(db, defaults, "buffBarTextureOrientation", "HORIZONTAL")
    styleCache.buffBarBackgroundTextureOrientation = CfgValue(db, defaults, "buffBarBackgroundTextureOrientation", "HORIZONTAL")
    styleCache.buffBarSmooth = CfgValue(db, defaults, "buffBarSmooth", false)
    styleCache.buffBarSparkEnabled = CfgValue(db, defaults, "buffBarSparkEnabled", false)
    styleCache.buffBarSparkTexture = CfgValue(db, defaults, "buffBarSparkTexture", "Interface\\CastingBar\\UI-CastingBar-Spark")
    styleCache.buffBarSparkWidth = CfgValue(db, defaults, "buffBarSparkWidth", 10)
    styleCache.buffBarSparkHeight = CfgValue(db, defaults, "buffBarSparkHeight", 0)
    styleCache.buffBarSparkBlendMode = CfgValue(db, defaults, "buffBarSparkBlendMode", "ADD")
    styleCache.buffBarSparkColor = CfgValue(db, defaults, "buffBarSparkColor", CDM_C.WHITE)
    styleCache.buffBarSparkAlpha = CfgValue(db, defaults, "buffBarSparkAlpha", 1)
    styleCache.buffBarSparkOffsetX = CfgValue(db, defaults, "buffBarSparkOffsetX", 0)
    styleCache.buffBarSparkOffsetY = CfgValue(db, defaults, "buffBarSparkOffsetY", 0)
    styleCache.buffBarTextureColor = CfgValue(db, defaults, "buffBarTextureColor", CDM_C.WHITE)
    styleCache.buffBarTextureAlpha = CfgValue(db, defaults, "buffBarTextureAlpha", 1)
    styleCache.buffBarBackgroundTextureColor = CfgValue(db, defaults, "buffBarBackgroundTextureColor", CDM_C.WHITE)
    styleCache.buffBarBackgroundTextureAlpha = CfgValue(db, defaults, "buffBarBackgroundTextureAlpha", 1)
    styleCache.buffBarIconMask = CfgValue(db, defaults, "buffBarIconMask", false)
    styleCache.buffBarIconMaskShape = CfgValue(db, defaults, "buffBarIconMaskShape", "SQUARE")
    styleCache.buffBarIconBorderEnabled = CfgValue(db, defaults, "buffBarIconBorderEnabled", true)
    styleCache.buffBarIconBorderColor = CfgValue(db, defaults, "buffBarIconBorderColor", CDM_C.WHITE)
    styleCache.buffBarIconBorderSize = CfgValue(db, defaults, "buffBarIconBorderSize", 1)
    styleCache.buffBarIconBorderInset = CfgValue(db, defaults, "buffBarIconBorderInset", 0)
    styleCache.buffBarIconBorderTexture = CfgValue(db, defaults, "buffBarIconBorderTexture", "Blizzard Tooltip")
    styleCache.buffBarBarBorderEnabled = CfgValue(db, defaults, "buffBarBarBorderEnabled", true)
    styleCache.buffBarBarBorderColor = CfgValue(db, defaults, "buffBarBarBorderColor", CDM_C.WHITE)
    styleCache.buffBarBarBorderSize = CfgValue(db, defaults, "buffBarBarBorderSize", 1)
    styleCache.buffBarBarBorderInset = CfgValue(db, defaults, "buffBarBarBorderInset", 0)
    styleCache.buffBarBarBorderTexture = CfgValue(db, defaults, "buffBarBarBorderTexture", "Blizzard Tooltip")
    styleCache.buffBarBarBackgroundEnabled = CfgValue(db, defaults, "buffBarBarBackgroundEnabled", true)
    styleCache.buffBarBarBackgroundColor = CfgValue(db, defaults, "buffBarBarBackgroundColor", { r = 0, g = 0, b = 0, a = 0.4 })
    styleCache.buffBarBarBackgroundTexture = CfgValue(db, defaults, "buffBarBarBackgroundTexture", "Blizzard")
    styleCache.buffBarBarBackgroundInset = CfgValue(db, defaults, "buffBarBarBackgroundInset", 0)
    styleCache.buffBarBarPaddingLeft = CfgValue(db, defaults, "buffBarBarPaddingLeft", 0)
    styleCache.buffBarBarPaddingRight = CfgValue(db, defaults, "buffBarBarPaddingRight", 0)
    styleCache.buffBarBarPaddingTop = CfgValue(db, defaults, "buffBarBarPaddingTop", 0)
    styleCache.buffBarBarPaddingBottom = CfgValue(db, defaults, "buffBarBarPaddingBottom", 0)
    styleCache.buffBarTextContainerLevelOffset = CfgValue(db, defaults, "buffBarTextContainerLevelOffset", 6)
    styleCache.buffBarIconContainerLevelOffset = CfgValue(db, defaults, "buffBarIconContainerLevelOffset", 4)
    styleCache.buffBarCooldownContainerLevelOffset = CfgValue(db, defaults, "buffBarCooldownContainerLevelOffset", 5)

    styleCache.isBorderActive = CfgValue(db, defaults, "borderEnabled", true)
    styleCache.borderSize = CfgValue(db, defaults, "borderSize", 1)
    styleCache.borderInset = CfgValue(db, defaults, "borderInset", 0)
    styleCache.borderTexture = CfgValue(db, defaults, "borderTexture", "Blizzard Tooltip")
    styleCache.fontPath = LSM and LSM:Fetch("font", styleCache.textFont) or STANDARD_TEXT_FONT
end

CDM.RefreshStyleCache = RefreshStyleCache

local function SafeEquals(v, expected)
    return (type(v) ~= "number" or canaccessvalue(v)) and v == expected
end

local function ApplyOverlayVisibility(hideAtlas, hideTexture, ...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            if SafeEquals(region:GetAtlas(), BLIZZARD_ICON_OVERLAY_ATLAS) then
                if hideAtlas then
                    region:SetAlpha(0)
                    region:Hide()
                else
                    region:SetAlpha(1)
                    region:Show()
                end
            elseif SafeEquals(region:GetTexture(), BLIZZARD_ICON_OVERLAY_TEXTURE_FILE_ID) then
                if hideTexture then
                    region:SetAlpha(0)
                    region:Hide()
                else
                    region:SetAlpha(1)
                    region:Show()
                end
            end
        end
    end
end

local function StyleCooldownFontStringsInRegions(fontPath, fontSize, fontOutline, color, init, ...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if region and region.IsObjectType and region:IsObjectType("FontString") then
            StyleCooldownTextElement(region, fontPath, fontSize, fontOutline, color, init)
        end
    end
end

local function GetEffectiveCooldownSpellID(frame)
    if not frame then return nil end
    local info = frame.cooldownInfo
    if not info then return nil end
    local id = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
    return IsSafeNumber(id) and id or nil
end

local function GetCastSpellID(frame)
    if not frame then return nil end
    local info = frame.cooldownInfo
    if not info then return nil end
    local id = info.overrideSpellID or info.spellID
    return IsSafeNumber(id) and id or nil
end
CDM.GetCastSpellID = GetCastSpellID

local function GetEquippedItemSlot(frame)
    if not frame or type(frame.GetEquipSlot) ~= "function" then return nil end
    local ok, equipSlot = pcall(frame.GetEquipSlot, frame)
    if not ok or not IsSafeNumber(equipSlot) or equipSlot <= 0 then return nil end
    return equipSlot
end

local function IsEquippedItemCooldownFrame(frame)
    return GetEquippedItemSlot(frame) ~= nil
end

local function IsNativeAuraActive(frame)
    return frame and frame.cooldownUseAuraDisplayTime == true or false
end

local function GetEquippedItemRealCooldown(frame)
    local equipSlot = GetEquippedItemSlot(frame)
    if not equipSlot or not GetInventoryItemCooldown then
        return false, nil, nil, nil
    end

    local actualState = frame.isOnActualCooldown
    if actualState ~= nil and canaccessvalue(actualState) and actualState ~= true then
        return false, nil, nil, nil
    end

    local startTime, duration, enable = GetInventoryItemCooldown("player", equipSlot)
    local active = enable == 1
        and type(startTime) == "number" and startTime > 0
        and type(duration) == "number" and duration > CDM_C.ITEM_COOLDOWN_GCD_MIN

    if actualState ~= nil and canaccessvalue(actualState) then
        active = active and actualState == true
    end

    return active, startTime, duration, enable
end

local function HasChargeSource(frame)
    return frame.HasVisualDataSource_Charges and frame:HasVisualDataSource_Charges() or false
end

local function FindAuraOverlayEntry(frame)
    local map = CDM._auraOverlayEnabled
    if not map then return nil end
    local cdID = frame and frame.cooldownID
    if cdID and map[cdID] then return map[cdID] end
    return nil
end

local function QueueEquippedItemNativeRefresh(frame)
    if not frame or frame.cdmEquippedItemNativeRefreshPending then return end
    if type(frame.RefreshData) ~= "function" then return end

    frame.cdmEquippedItemNativeRefreshPending = true
    C_Timer.After(0, function()
        frame.cdmEquippedItemNativeRefreshPending = nil
        if not frame.cooldownID then return end
        local entry = FindAuraOverlayEntry(frame)
        if not entry or entry.auraOverlay ~= true then return end

        pcall(frame.RefreshData, frame)
    end)
end

local function ApplyPandemicCDMStyle(frame)
    if frame.cdmPandemicActive then return end

    if styleCache.pandemicGlowEnabled then
        frame.cdmPandemicActive = true
        if frame.PandemicIcon then frame.PandemicIcon:Hide() end
        CDM.Glow:ShowPandemicGlow(frame, styleCache.pandemicGlowType, styleCache.pandemicGlowColor)
        return
    end

    if not styleCache.pandemicBorderEnabled then return end
    frame.cdmPandemicActive = true
    BORDER:ApplyPandemicBorderColor(frame, styleCache.pandemicBorderColor, styleCache.pandemicBorderColorBuffBars)
end

local function ClearPandemicCDMStyle(frame)
    if not frame.cdmPandemicActive then return end
    frame.cdmPandemicActive = false

    CDM.Glow:HidePandemicGlow(frame)
    BORDER:ClearPandemicBorderColor(frame)
end

local function ClearReadyGlow(frame)
    CDM.Glow:RequestBuffGlow(frame, "ready", false)
end

local function ApplyReadyGlow(frame, entry)
    if frame.cdmGlowProducer == "ready"
       and frame.cdmBuffGlowOverrideColor == entry.readyGlowColor then
        local host = frame.cdmBuffGlowHost
        if host and host:IsShown() and host:GetWidth() >= 1 and host.cdmGlowActive then
            return
        end
    end
    CDM.Glow:RequestBuffGlow(frame, "ready", true, entry.readyGlowColor, nil)
end

local function GetReadyGlowDecision(frame, entry, spellID, isReady)
    if not entry or not entry.readyGlowEnabled then
        return true, false
    end
    if frame.cdmLastAuraActive then
        return true, false
    end
    if entry.auraOverlay and entry.auraDesaturateInactive then
        return true, false
    end
    if not spellID then
        return false, false
    end
    return true, isReady
end

local function SyncReadyGlow(frame, entry, spellID, isReady)
    local decisionKnown, shouldShowReadyGlow = GetReadyGlowDecision(frame, entry, spellID, isReady)
    if not decisionKnown then
        return
    end
    if shouldShowReadyGlow then
        ApplyReadyGlow(frame, entry)
    else
        ClearReadyGlow(frame)
    end
end

CDM.SyncReadyGlowForFrame = SyncReadyGlow

local function EnsureCooldownTintOverlay(frame)
    if not frame or not frame.Icon then return nil end

    local tint = frame.cdmCooldownTintOverlay
    if not tint then
        tint = frame:CreateTexture(nil, "ARTWORK", nil, 5)
        tint:SetAllPoints(frame.Icon)
        tint:SetTexture(CDM_C.TEX_WHITE8X8 or "Interface\\Buttons\\WHITE8X8")
        tint:SetBlendMode("MOD")
        tint:Hide()
        frame.cdmCooldownTintOverlay = tint
    end

    return tint
end

local function ApplyCooldownIconAppearance(frame, entry, auraActive, sid, fallbackCooldownState)
    local icon = frame and frame.Icon
    if not icon then return end

    local onCooldown = false
    if entry and entry.auraOverlay and auraActive then
        onCooldown = false
    elseif IsEquippedItemCooldownFrame(frame) then
        onCooldown = GetEquippedItemRealCooldown(frame) == true
    elseif sid then
        local chargeInfo = GetSpellCharges(sid)
        local maxCharges = chargeInfo and chargeInfo.maxCharges
        local isChargeSpell = IsSafeNumber(maxCharges) and maxCharges > 1

        if isChargeSpell then
            local currentCharges = chargeInfo.currentCharges
            if IsSafeNumber(currentCharges) then
                onCooldown = currentCharges <= 0
            else
                onCooldown = CDM.IsOnRealCooldown(sid, true) == true
            end
        else
            onCooldown = CDM.IsOnRealCooldown(sid, false) == true
        end
    elseif fallbackCooldownState ~= nil and canaccessvalue(fallbackCooldownState) then
        onCooldown = fallbackCooldownState == true
    end

    local tint = EnsureCooldownTintOverlay(frame)
    if not tint then return end

    if not onCooldown then
        tint:Hide()
        return
    end

    local color = styleCache.cooldownIconColor or CDM_C.WHITE
    local r, g, b = color.r or 1, color.g or 1, color.b or 1

    tint:SetVertexColor(r, g, b, 1)
    tint:SetAlpha(1)
    tint:Show()
end

CDM.ApplyCooldownIconAppearance = ApplyCooldownIconAppearance

local function ApplyIconDesat(frame, entry, auraActive, sid, blizzDesat)
    local desat = 0
    if entry and entry.auraOverlay and auraActive then
        desat = 0
    elseif entry and entry.auraOverlay and entry.auraDesaturateInactive then
        desat = 1
    elseif IsEquippedItemCooldownFrame(frame) then
        if not styleCache.disableCooldownDesat and GetEquippedItemRealCooldown(frame) == true then
            desat = 1
        end
    elseif sid and not HasChargeSource(frame) then
        if not styleCache.disableCooldownDesat then
            local realDur = GetSpellCooldownDuration(sid, true)
            desat = (realDur and realDur:EvaluateRemainingDuration(DesaturationCurve, RealTime)) or 0
        end
    else
        local boolDesat = blizzDesat
        if boolDesat == nil then boolDesat = frame.cooldownDesaturated end
        if boolDesat ~= nil and not styleCache.disableCooldownDesat then
            desat = EvaluateColorValueFromBoolean(boolDesat, 1, 0)
        end
    end
    frame.cdmInternalWrite = true
    frame.Icon:SetDesaturation(desat)
    ApplyCooldownIconAppearance(frame, entry, auraActive, sid, blizzDesat)
    frame.cdmInternalWrite = false
end

local function ApplyBaseSwipeStyle(cd, frame)
    local sc = styleCache.swipeColor or CDM_C.SWIPE_COLOR
    cd:SetSwipeColor(sc.r, sc.g, sc.b, sc.a)

    local ver = CDM.styleCacheVersion or 0
    if frame.cdmLastCooldownStyleVer ~= ver then
        if styleCache.zoomIcons then
            cd:SetSwipeTexture(CDM_C.TEX_WHITE8X8)
        else
            cd:SetSwipeTexture(DEFAULT_COOLDOWN_ICON_SWIPE_TEXTURE)
        end
        frame.cdmLastCooldownStyleVer = ver
    end
end

local function ApplyCooldownWidget(frame, entry, auraActive, sid)
    local cd = frame.Cooldown
    local isEquippedItem = IsEquippedItemCooldownFrame(frame)
    frame.cdmInternalWrite = true

    local hideCountdown = false

    if isEquippedItem and entry and entry.auraOverlay then
        if frame.cdmEquippedItemNativeOverlay ~= true then
            frame.cdmEquippedItemNativeOverlay = true
            QueueEquippedItemNativeRefresh(frame)
        end
        cd:SetHideCountdownNumbers(false)
        frame.cdmInternalWrite = false
        return
    end

    if isEquippedItem then
        frame.cdmEquippedItemNativeOverlay = nil
    end

    if entry and entry.auraOverlay and auraActive then
        cd:SetReverse(true)
        cd:SetAlpha(1)
        cd:SetDrawEdge(false)
        cd:SetUseAuraDisplayTime(true)
        cd:SetDrawSwipe(true)
        frame.cdmCooldownOverlayStyleApplied = true
    elseif entry and entry.auraOverlay and not auraActive and entry.auraDesaturateInactive then
        cd:SetReverse(false)
        cd:SetAlpha(1)
        cd:SetDrawEdge(false)
        cd:SetDrawSwipe(false)
        frame.cdmCooldownOverlayStyleApplied = true
    else
        local transitioningOut = frame.cdmCooldownOverlayStyleApplied
        if transitioningOut then
            cd:SetReverse(false)
            cd:SetAlpha(1)
            frame.cdmCooldownOverlayStyleApplied = nil
        end
        if isEquippedItem then
            cd:SetReverse(false)
            cd:SetUseAuraDisplayTime(false)
            cd:SetDrawEdge(false)
            local active, startTime, duration = GetEquippedItemRealCooldown(frame)
            if active then
                if not frame.cdmEquippedItemDurationObj then
                    frame.cdmEquippedItemDurationObj = C_DurationUtil.CreateDuration()
                end
                frame.cdmEquippedItemDurationObj:SetTimeFromStart(startTime, duration)
                cd:SetCooldownFromDurationObject(frame.cdmEquippedItemDurationObj)
                cd:SetDrawSwipe(true)
            else
                cd:Clear()
            end
        elseif HasChargeSource(frame) then
            local chargeDur = sid and GetSpellChargeDuration(sid)
            if chargeDur then
                cd:SetUseAuraDisplayTime(false)
                cd:SetCooldownFromDurationObject(chargeDur)
            else
                cd:Clear()
            end
            cd:SetDrawSwipe(not styleCache.chargeHideSwipe)
            cd:SetDrawEdge(styleCache.chargeShowEdge and true or false)
            hideCountdown = styleCache.chargeHideRechargeTimer
        else
            cd:SetDrawEdge(false)
            cd:SetUseAuraDisplayTime(false)
            local cdDur = sid and GetSpellCooldownDuration(sid, styleCache.hideGCDSwipe)
            if cdDur then
                cd:SetCooldownFromDurationObject(cdDur)
            else
                cd:Clear()
            end
            if transitioningOut then
                cd:SetDrawSwipe(true)
            end
        end
    end

    cd:SetHideCountdownNumbers(hideCountdown)

    frame.cdmInternalWrite = false
end

local function ApplyGlows(frame, entry, auraActive)
    if entry and entry.auraOverlay and auraActive and entry.auraGlowEnabled then
        CDM.Glow:RequestBuffGlow(frame, "aura", true, entry.auraGlowColor, nil)
    else
        CDM.Glow:RequestBuffGlow(frame, "aura", false)
    end

    if entry and entry.auraOverlay and auraActive and entry.auraBorderEnabled then
        BORDER:ApplyBorderColorOverride(frame, entry.auraBorderColor or CDM_C.WHITE)
        frame.cdmAuraBorderActive = true
    elseif frame.cdmAuraBorderActive then
        BORDER:RestoreToCurrentBorderColor(frame)
        frame.cdmAuraBorderActive = false
    end

    local director = CDM.GlowDirector
    if director and director.RefreshFrame then
        director:RefreshFrame(frame)
    end
end

function CDM:RefreshFrameVisuals(frame, skipDesat)
    if not frame then return end
    if not VIEWERS_WITH_OVERRIDE[frame.cdmViewerName] then return end
    local entry = FindAuraOverlayEntry(frame)
    local nativeAuraActive = IsNativeAuraActive(frame)
    local auraActive = entry and entry.auraOverlay == true and nativeAuraActive or false
    local sid = GetCastSpellID(frame)
    frame.cdmLastAuraActive = auraActive
    if not skipDesat then
        ApplyIconDesat(frame, entry, auraActive, sid)
    end
    ApplyCooldownWidget(frame, entry, auraActive, sid)
    ApplyGlows(frame, entry, auraActive)
end

function CDM:ApplyBuffVisualState(frame)
    if not frame then return end

    if styleCache.hideDebuffBorder and frame.DebuffBorder then
        frame.DebuffBorder:Hide()
    end
end

function CDM:ProcessBuffViewerOverrides(frame)
    if not frame then return end
    if frame.cdmIsProcessingBuffOverride then return end

    frame.cdmIsProcessingBuffOverride = true
    self:ApplyBuffVisualState(frame)
    frame.cdmIsProcessingBuffOverride = false
end

local function ApplyBuffCooldownStyle(frame)
    local cd = frame.Cooldown
    ApplyBaseSwipeStyle(cd, frame)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(not styleCache.hideBuffSwipe)
end

local function EnsureFrameHooks(frame, hookType)
    if not frame then return end

    if hookType == "buff" then
        ApplyBuffCooldownStyle(frame)

        local cd = frame.Cooldown
        if not frame.cdmBuffSwipeHooked then
            frame.cdmBuffSwipeHooked = true
            hooksecurefunc(cd, "SetCooldown", function()
                ApplyBaseSwipeStyle(cd, frame)
            end)
        end
    end

    if (hookType == "buff" or hookType == "bar") and frame.DebuffBorder and not frame.cdmDebuffBorderHooked then
        frame.cdmDebuffBorderHooked = true
        hooksecurefunc(frame.DebuffBorder, "Show", function(self)
            if styleCache.hideDebuffBorder and not frame.cdmIsProcessingBuffOverride then
                self:Hide()
            end
        end)
    end

    if (hookType == "cooldown" or hookType == "bar") and frame.CooldownFlash and not frame.cdmCooldownFlashHooked then
        frame.cdmCooldownFlashHooked = true
        hooksecurefunc(frame.CooldownFlash, "Show", function(self)
            if styleCache.hideCooldownBling then
                self:Hide()
                if self.FlashAnim then
                    self.FlashAnim:Stop()
                end
            end
        end)
    end

    if hookType == "cooldown" and type(frame.RefreshData) == "function" and not frame.cdmRefreshDataVisualHooked then
        frame.cdmRefreshDataVisualHooked = true
        hooksecurefunc(frame, "RefreshData", function(self)
            if self.cdmRefreshDataVisualPending then return end
            self.cdmRefreshDataVisualPending = true
            C_Timer.After(0, function()
                self.cdmRefreshDataVisualPending = nil
                if not self.cooldownID then return end
                if not VIEWERS_WITH_OVERRIDE[self.cdmViewerName] then return end
                CDM:RefreshFrameVisuals(self)
            end)
        end)
    end

    if frame.ShowPandemicStateFrame and not frame.cdmPandemicHooked then
        frame.cdmPandemicHooked = true
        hooksecurefunc(frame, "ShowPandemicStateFrame", function(self)
            self.cdmPandemicShown = true
            if (styleCache.pandemicGlowEnabled or styleCache.hidePandemicIndicator)
               and self.PandemicIcon and not self.cdmIsProcessingBuffOverride then
                self.PandemicIcon:Hide()
            end
            ApplyPandemicCDMStyle(self)
        end)
        hooksecurefunc(frame, "HidePandemicStateFrame", function(self)
            self.cdmPandemicShown = nil
            ClearPandemicCDMStyle(self)
        end)
    end
end

-- Remaining file content unchanged from current branch; full replacement intentionally omitted here would be invalid.