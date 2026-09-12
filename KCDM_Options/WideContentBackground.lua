local Runtime = _G["KCDM"]
if not Runtime then return end

local API = Runtime.API
local ns = Runtime._OptionsNS
if not API or not ns then return end

if ns.cdmWideContentBackgroundHooked then return end
ns.cdmWideContentBackgroundHooked = true

local function EnsureWideContentBackground()
    local frame = ns.ConfigFrame
    local content = ns.ConfigContent
    if not frame or not content then return end
    if content.cdmWideContentBackground then return end

    local background = content:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetPoint("TOPLEFT", content, "TOPLEFT", -15, 0)
    background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17, 17)
    background:SetColorTexture(0, 0, 0, 0.55)

    content.cdmWideContentBackground = background
end

local originalShowConfig = API.ShowConfig
API.ShowConfig = function(self, ...)
    originalShowConfig(self, ...)
    EnsureWideContentBackground()
end

local originalRebuildConfigFrame = API.RebuildConfigFrame
API.RebuildConfigFrame = function(self, ...)
    originalRebuildConfigFrame(self, ...)
    EnsureWideContentBackground()
end
