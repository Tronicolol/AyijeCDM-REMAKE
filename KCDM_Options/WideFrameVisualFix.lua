local Runtime = _G["KCDM"]
if not Runtime then return end

local API = Runtime.API
local ns = Runtime._OptionsNS
if not API or not ns then return end

if ns.cdmWideFrameVisualFixHooked then return end
ns.cdmWideFrameVisualFixHooked = true

local INNER_ATLAS = "Options_InnerFrame"
local SIDEBAR_EXTRA_WIDTH = 25

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

    local texture = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
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

local originalShowConfig = API.ShowConfig
API.ShowConfig = function(self, ...)
    originalShowConfig(self, ...)
    EnsureWideFrameVisuals()
end

local originalRebuildConfigFrame = API.RebuildConfigFrame
API.RebuildConfigFrame = function(self, ...)
    originalRebuildConfigFrame(self, ...)
    EnsureWideFrameVisuals()
end
