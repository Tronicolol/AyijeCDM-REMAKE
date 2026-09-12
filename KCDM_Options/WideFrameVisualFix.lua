local Runtime = _G["KCDM"]
if not Runtime then return end

local API = Runtime.API
local ns = Runtime._OptionsNS
if not API or not ns then return end

if ns.cdmWideFrameVisualFixHooked then return end
ns.cdmWideFrameVisualFixHooked = true

local INNER_ATLAS = "Options_InnerFrame"
local SIDEBAR_EXTRA_WIDTH = 25
local TRACKED_SCROLL_FRAMES = {
    "KCDM_GlowScrollFrame",
    "KCDM_RacialsScrollFrame",
    "KCDM_DefensivesScrollFrame",
    "KCDM_TrinketsScrollFrame",
    "KCDM_ResourcesScrollFrame",
    "KCDM_BarsScrollFrame",
    "KCDM_CastBarScrollFrame",
    "KCDM_BuffGroupsLeftScroll",
}

local function FindInnerFrameTexture(root)
    if not root then return nil end

    for _, region in ipairs({ root:GetRegions() }) do
        if region and region.GetAtlas then
            local ok, atlas = pcall(region.GetAtlas, region)
            if ok and atlas == INNER_ATLAS then
                return region
            end
        end
    end

    for _, child in ipairs({ root:GetChildren() }) do
        local found = FindInnerFrameTexture(child)
        if found then
            return found
        end
    end

    return nil
end

local function CreateCroppedSidebarAtlas(frame, sidebar)
    if not C_Texture or not C_Texture.GetAtlasInfo then return nil end

    local info = C_Texture.GetAtlasInfo(INNER_ATLAS)
    if not info or not info.file or not info.width or info.width <= 0 then
        return nil
    end

    local width = sidebar:GetWidth() + SIDEBAR_EXTRA_WIDTH
    local ratio = math.min(1, width / info.width)
    local left = info.leftTexCoord or 0
    local right = info.rightTexCoord or 1
    local top = info.topTexCoord or 0
    local bottom = info.bottomTexCoord or 1
    local croppedRight = left + ((right - left) * ratio)

    local texture = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    texture:SetTexture(info.file)
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, -64)
    texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 17, 17)
    texture:SetWidth(width)
    texture:SetTexCoord(left, croppedRight, top, bottom)

    return texture
end

local function EnsureWideFrameVisuals()
    local frame = ns.ConfigFrame
    local sidebar = ns.ConfigSidebar
    if not frame or not sidebar or frame.cdmWideFrameVisualApplied then return end

    frame.cdmWideFrameVisualApplied = true

    local originalInner = FindInnerFrameTexture(frame)
    if originalInner then
        originalInner:Hide()
    end

    frame.cdmSidebarInnerAtlas = CreateCroppedSidebarAtlas(frame, sidebar)
end

local function CaptureScrollPositions()
    local positions = {}

    for _, frameName in ipairs(TRACKED_SCROLL_FRAMES) do
        local scrollFrame = _G[frameName]
        if scrollFrame and scrollFrame.GetVerticalScroll then
            positions[frameName] = scrollFrame:GetVerticalScroll()
        end
    end

    return positions
end

local function RestoreScrollPositions(positions)
    if not positions then return end

    for frameName, offset in pairs(positions) do
        local scrollFrame = _G[frameName]
        if scrollFrame and scrollFrame.SetVerticalScroll then
            scrollFrame:SetVerticalScroll(offset)
        end
    end
end

local function PatchSidebarNavigation()
    local sidebar = ns.ConfigSidebar
    if not sidebar then return end

    for _, child in ipairs({ sidebar:GetChildren() }) do
        if child
            and child.Text
            and child.Texture
            and child.GetScript
            and not child.cdmScrollStatePatched then
            local originalOnClick = child:GetScript("OnClick")
            if type(originalOnClick) == "function" then
                child.cdmScrollStatePatched = true
                child:SetScript("OnClick", function(self, ...)
                    local positions = CaptureScrollPositions()
                    originalOnClick(self, ...)
                    RestoreScrollPositions(positions)
                end)
            end
        end
    end
end

local originalShowConfig = API.ShowConfig
API.ShowConfig = function(self, ...)
    originalShowConfig(self, ...)
    EnsureWideFrameVisuals()
    PatchSidebarNavigation()
end

local originalRebuildConfigFrame = API.RebuildConfigFrame
API.RebuildConfigFrame = function(self, ...)
    originalRebuildConfigFrame(self, ...)
    EnsureWideFrameVisuals()
    PatchSidebarNavigation()
end
