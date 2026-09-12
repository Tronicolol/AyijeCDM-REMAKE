from pathlib import Path
import re


def load(path):
    return Path(path).read_text(encoding="utf-8")


def save(path, text):
    Path(path).write_text(text, encoding="utf-8")


def remove_between(text, start, end, label):
    start_index = text.find(start)
    if start_index < 0:
        raise RuntimeError(f"{label}: start marker not found")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise RuntimeError(f"{label}: end marker not found")
    return text[:start_index] + text[end_index:]


def assert_absent(text, tokens, label):
    leftovers = [token for token in tokens if token in text]
    if leftovers:
        raise RuntimeError(f"{label}: leftover tokens: {leftovers}")


# Bars: populate groups only from the visible Ungrouped list.
path = "KCDM_Options/Bars.lua"
text = load(path)
text = text.replace("    local pickerActiveGroupIndex = nil\n", "")
text = remove_between(
    text,
    "    local function GetViewerSpellListForSpec(specID)\n",
    "    local function MarkSafe(set, id)\n",
    "Bars picker data helpers",
)
text = re.sub(r"^\s*pickerActiveGroupIndex = nil\n", "", text, flags=re.MULTILINE)
text = remove_between(
    text,
    "    local function ShowSpellPickerPanel(groupIndex)\n",
    "    local headerPool, groupContainerPool, emptyRowPool =\n",
    "Bars picker panel",
)
text = re.sub(
    r"\n\s*if pickerActiveGroupIndex then\n"
    r"\s*if pickerActiveGroupIndex == groupIndex then\n"
    r"\s*pickerActiveGroupIndex = nil\n"
    r"\s*ClearRightPanel\(\)\n"
    r"\s*elseif pickerActiveGroupIndex > groupIndex then\n"
    r"\s*pickerActiveGroupIndex = pickerActiveGroupIndex - 1\n"
    r"\s*needReshow = true\n"
    r"\s*end\n"
    r"\s*end\n",
    "\n",
    text,
    count=1,
)
text = text.replace(
    "                if needReshow then\n"
    "                    if pickerActiveGroupIndex then\n"
    "                        ShowSpellPickerPanel(pickerActiveGroupIndex)\n"
    "                    elseif selectedSpellID then\n",
    "                if needReshow then\n"
    "                    if selectedSpellID then\n",
)
text = remove_between(
    text,
    "        if not btnRefs.spell then\n",
    "        leftChild:SetHeight(math.max(800, -yOff + 40))\n",
    "Bars Add Spell button",
)
assert_absent(
    text,
    [
        "pickerActiveGroupIndex",
        "ShowSpellPickerPanel",
        "GetAvailableSpellsForPicker",
        "GetViewerSpellListForSpec",
        'L["Add Spell"]',
    ],
    "Bars",
)
save(path, text)


# Buff Groups: remove native Add Icon picker but preserve Add Custom Buff and Ungrouped/cache display.
path = "KCDM_Options/BuffGroups.lua"
text = load(path)
text = text.replace("    local pickerActiveGroupIndex = nil\n", "")
text = re.sub(r"^\s*pickerActiveGroupIndex = nil\n", "", text, flags=re.MULTILINE)
text = remove_between(
    text,
    "    local function GetViewerSpellListForSpec(specID)\n",
    "    local function GetUngroupedBuffSpellsFromCache(specID)\n",
    "Buff Groups picker data helpers",
)
text = text.replace("    local ShowSpellPickerPanel\n", "")
text = remove_between(
    text,
    "    local function UpdateAddIconButtonState()\n",
    "    GetCustomBuffEntry = function(spellID)\n",
    "Buff Groups Add Icon picker",
)
text = re.sub(r"^\s*UpdateAddIconButtonState\(\)\n", "", text, flags=re.MULTILINE)
text = remove_between(
    text,
    "        if not btnRefs.icon then\n",
    "        if not btnRefs.customBuff then\n",
    "Buff Groups Add Icon button",
)
text = re.sub(
    r"\n\s*if pickerActiveGroupIndex then\n.*?\n\s*end\n(?=\s*local newExpanded = \{\})",
    "\n",
    text,
    count=1,
    flags=re.DOTALL,
)
text = text.replace(
    "                if needReshow then\n"
    "                    if pickerActiveGroupIndex then\n"
    "                        ShowSpellPickerPanel(pickerActiveGroupIndex)\n"
    "                    elseif selectedSpellID then\n",
    "                if needReshow then\n"
    "                    if selectedSpellID then\n",
)
assert_absent(
    text,
    [
        "pickerActiveGroupIndex",
        "ShowSpellPickerPanel",
        "GetAvailableSpellsForPicker",
        "GetViewerSpellListForSpec",
        "UpdateAddIconButtonState",
        'L["Add Icon"]',
    ],
    "BuffGroups",
)
if 'L["Add Custom Buff"]' not in text:
    raise RuntimeError("BuffGroups: Add Custom Buff was removed unexpectedly")
save(path, text)


# Racials runtime: remove party/raid-frame anchoring integrations completely.
path = "KCDM/Modules/Racials.lua"
text = load(path)
text = remove_between(
    text,
    "local function AnchorRacialsToPartyFrame(partyFrame, point, relativePoint, offsetX, offsetY)\n",
    "local racialsTrackerAcquireOpts = {\n",
    "Racials party-frame helpers",
)
position_start = "local racialsLastUsedPartyAnchor = false\n\nlocal function UpdateContainerPosition()\n"
position_end = "local racialsUpdatePending = false\n"
start_index = text.find(position_start)
if start_index < 0:
    raise RuntimeError("Racials position block: start marker not found")
end_index = text.find(position_end, start_index)
if end_index < 0:
    raise RuntimeError("Racials position block: end marker not found")
replacement = (
    "local function UpdateContainerPosition()\n"
    "    if not racialsContainer then return end\n\n"
    "    local anchorPoint = CDM.db and CDM.db.racialsAnchorPoint or \"TOPLEFT\"\n"
    "    local offsetX = CDM.db and CDM.db.racialsOffsetX or 0\n"
    "    local offsetY = CDM.db and CDM.db.racialsOffsetY or 0\n"
    "    CDM.AnchorToPlayerFrame(racialsContainer, anchorPoint, offsetX, offsetY, \"Racials\")\n"
    "end\n\n"
)
text = text[:start_index] + replacement + text[end_index:]
assert_absent(
    text,
    [
        "racialsUsePartyFrame",
        "racialsPartyFrame",
        "racialsRaidFrame",
        "ResolvePartyAnchorFrame",
        "DandersFrames",
        "Grid2Layout",
        "CompactPartyFrameMember",
        "CellPartyFrameMember",
        "ElvUF_PartyGroup1UnitButton",
    ],
    "Racials runtime",
)
save(path, text)


# Racials options: remove the complete party/raid anchoring section.
path = "KCDM_Options/Racials.lua"
text = load(path)
party_start = '    local partyHeader = UI.CreateHeader(scrollChild, L["Party Frame Anchoring"])\n'
position_line = '    local positionHeader = UI.CreateHeader(scrollChild, L["Position"], page.racialsUsePartyFrameCheckbox, -15)\n'
start_index = text.find(party_start)
if start_index < 0:
    raise RuntimeError("Racials options party block: start marker not found")
position_index = text.find(position_line, start_index)
if position_index < 0:
    raise RuntimeError("Racials options Position marker not found")
text = (
    text[:start_index]
    + '    local positionHeader = UI.CreateHeader(scrollChild, L["Position"], page.racialsIconHeightSlider, -30)\n'
    + text[position_index + len(position_line):]
)
text = remove_between(
    text,
    "    UpdateControls = function()\n",
    "    setControlsEnabled = UI.SetupModuleToggle(scrollChild, page.controls.racialsEnabled)\n",
    "Racials options UpdateControls",
)
text = text.replace(
    '    local cooldownHeader = UI.CreateHeader(scrollChild, L["Cooldown"])\n',
    '    local cooldownHeader = UI.CreateHeader(scrollChild, L["Cooldown"], page.racialsOffsetYSlider, -30)\n',
    1,
)
assert_absent(
    text,
    [
        "racialsUsePartyFrame",
        "racialsPartyFrame",
        "racialsRaidFrame",
        'L["Party Frame Anchoring"]',
        'L["Anchor to Party Frame"]',
        "UpdateControls",
    ],
    "Racials options",
)
save(path, text)


# Remove deleted Racials settings from defaults and profile categories.
path = "KCDM/Config/Defaults.lua"
text = load(path)
text = remove_between(
    text,
    "    -- Party frame anchoring settings\n",
    "    -- Per-bar resource settings (schema v9)\n",
    "Racials party defaults",
)
assert_absent(text, ["racialsUsePartyFrame", "racialsPartyFrame", "racialsRaidFrame"], "Defaults")
save(path, text)

path = "KCDM_Options/ConfigKeys.lua"
text = load(path)
for key in (
    "racialsUsePartyFrame",
    "racialsPartyFrameSide",
    "racialsPartyFrameOffsetX",
    "racialsPartyFrameOffsetY",
    "racialsRaidFrameAnchorPoint",
    "racialsRaidFrameRelativePoint",
    "racialsRaidFrameOffsetX",
    "racialsRaidFrameOffsetY",
):
    text, count = re.subn(rf'^\s*"{re.escape(key)}",\n', "", text, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"ConfigKeys {key}: expected 1 removal, got {count}")
assert_absent(text, ["racialsUsePartyFrame", "racialsPartyFrame", "racialsRaidFrame"], "ConfigKeys")
save(path, text)


# Direct source cleanup replaces the temporary UI-removal shim.
removed_controls = Path("KCDM_Options/RemovedControls.lua")
if removed_controls.exists():
    removed_controls.unlink()

path = "KCDM_Options/embeds.xml"
text = load(path)
text = text.replace('    <Script file="RemovedControls.lua"/>\n', "")
save(path, text)


# Keep only a historical migration that strips old saved party-anchor values.
old_migration = Path("KCDM/Modules/RacialsPartyAnchorRemoval.lua")
new_migration = Path("KCDM/Modules/RacialsPartyAnchorMigration.lua")
if old_migration.exists():
    if new_migration.exists():
        raise RuntimeError("Both old and new Racials migration files exist")
    old_migration.rename(new_migration)

path = "KCDM/Modules/embeds.xml"
text = load(path)
text = text.replace(
    '    <Script file="RacialsPartyAnchorRemoval.lua"/>',
    '    <Script file="RacialsPartyAnchorMigration.lua"/>',
)
if 'RacialsPartyAnchorMigration.lua' not in text:
    raise RuntimeError("Racials migration include missing")
save(path, text)

print("Source cleanup completed successfully")
