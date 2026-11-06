-- Options window (/pb). Built from plain frames - no dropdown templates, which
-- change between client versions and can taint - so it works on any client.

local _, ns = ...

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local widgets = {}

local COLOR_MODES = {
    { "slot",    "Unique per member" },
    { "class",   "Class colour" },
    { "custom",  "Custom colour" },
    { "rainbow", "Rainbow" },
}
local OUTLINES = {
    { "THICKOUTLINE", "Thick outline" },
    { "OUTLINE",      "Thin outline" },
    { "",             "No outline" },
}
local SCOPES = {
    { "party", "My party / raid subgroup" },
    { "raid",  "Whole raid" },
}
local MARKER_MODES = {
    { "off",      "Off" },
    { "instance", "Dungeons & raids only" },
    { "always",   "Always" },
}

local function Changed()
    ns:Refresh()
end

-- Dim and lock a widget while "Names only" overrides its setting.
local function Lockable(w, key)
    local update = w.Update
    w.Update = function()
        update()
        local locked = ns.db.namesOnly and (key == "style" or key == "showName"
            or key == "hidePartyPlate" or key == "hideOthers")
        w:SetAlpha(locked and 0.35 or 1)
        w:EnableMouse(not locked)
    end
    return w
end

local function Tooltip(frame, text)
    if not text then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Header(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Check(parent, label, key, x, y, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        Changed()
    end)
    Tooltip(cb, tip)
    cb.Update = function() cb:SetChecked(ns.db[key]) end
    widgets[#widgets + 1] = cb
    return cb
end

-- Button that cycles through a list. Left click = next, right click = back.
local function Cycle(parent, label, key, values, x, y, tip)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x + 4, y)
    fs:SetText(label)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(210, 22)
    b:SetPoint("TOPLEFT", x, y - 14)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function index()
        for i, v in ipairs(values) do if v[1] == ns.db[key] then return i end end
        return 1
    end
    b:SetScript("OnClick", function(_, button)
        local i = index() + (button == "RightButton" and -1 or 1)
        if i > #values then i = 1 elseif i < 1 then i = #values end
        ns.db[key] = values[i][1]
        Changed()
    end)
    Tooltip(b, (tip and (tip .. "\n\n") or "") .. "|cff999999Left-click: next   Right-click: back|r")
    b.Update = function() b:SetText(values[index()][2]) end
    widgets[#widgets + 1] = b
    return b
end

local function Slider(parent, label, key, lo, hi, step, x, y)
    local s = CreateFrame("Slider", nil, parent, BACKDROP)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(200, 16)
    s:SetPoint("TOPLEFT", x + 4, y - 16)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if s.SetBackdrop then
        s:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
    end
    local fs = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        fs:SetText(label .. ": |cffffffff" .. v .. "|r")
        if self.updating or ns.db[key] == v then return end
        ns.db[key] = v
        Changed()
    end)
    s.Update = function()
        s.updating = true
        s:SetValue(ns.db[key])
        fs:SetText(label .. ": |cffffffff" .. ns.db[key] .. "|r")
        s.updating = nil
    end
    widgets[#widgets + 1] = s
    return s
end

local function PickColor(c)
    local r, g, b = c.r, c.g, c.b
    local function apply(nr, ng, nb)
        c.r, c.g, c.b = nr, ng, nb
        Changed()
    end
    local CPF = ColorPickerFrame
    if CPF.SetupColorPickerAndShow then
        CPF:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function() apply(CPF:GetColorRGB()) end,
            cancelFunc = function() apply(r, g, b) end,
        })
    else
        CPF.hasOpacity = false
        CPF.previousValues = { r, g, b }
        CPF.func = function() apply(CPF:GetColorRGB()) end
        CPF.cancelFunc = function() apply(r, g, b) end
        CPF:SetColorRGB(r, g, b)
        CPF:Hide()
        CPF:Show()
    end
end

local function Swatch(parent, label, key, x, y)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b:SetPoint("TOPLEFT", x + 4, y)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(1, 1, 1, 1)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
    fs:SetText(label)
    b:SetScript("OnClick", function() PickColor(ns.db[key]) end)
    Tooltip(b, "Click to pick the colour used when the mode is set to \"Custom colour\".")
    b.Update = function()
        local c = ns.db[key]
        fill:SetColorTexture(c.r, c.g, c.b, 1)
    end
    widgets[#widgets + 1] = b
    return b
end

-- One raid-icon button per party slot; click cycles icons (and "none").
local function IconPicker(parent, slot, x, y)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(28, 28)
    b:SetPoint("TOPLEFT", x, y)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 3, -3)
    tex:SetPoint("BOTTOMRIGHT", -3, 3)
    tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    local none = b:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    none:SetPoint("CENTER")
    none:SetText("-")
    local num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    num:SetPoint("TOP", b, "BOTTOM", 0, -1)
    num:SetText("P" .. slot)
    b:SetScript("OnClick", function(_, button)
        local v = (ns.db.icons[slot] or 0) + (button == "RightButton" and -1 or 1)
        if v > 8 then v = 0 elseif v < 0 then v = 8 end
        ns.db.icons[slot] = v
        Changed()
    end)
    b:SetScript("OnEnter", function(self)
        local v = ns.db.icons[slot] or 0
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Party member " .. slot .. ": " .. (v > 0 and ns.ICON_NAMES[v] or "no icon"), 1, 1, 1)
        GameTooltip:AddLine("Used for shared world markers and the \"Raid icon\" beacon style.", nil, nil, nil, true)
        GameTooltip:AddLine("Left-click: next   Right-click: back", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.Update = function()
        local v = ns.db.icons[slot] or 0
        if v > 0 then
            tex:SetTexCoord(ns.RaidIconCoords(v))
            tex:Show(); none:Hide()
        else
            tex:Hide(); none:Show()
        end
    end
    widgets[#widgets + 1] = b
    return b
end

-- ---------------------------------------------------------------------------

function ns:CreateOptions()
    if self.options then return end
    local f = CreateFrame("Frame", "PartyBeaconOptions", UIParent, BACKDROP)
    self.options = f
    f:SetSize(560, 640)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
    end
    f:Hide()
    tinsert(UISpecialFrames, "PartyBeaconOptions")   -- Escape closes it

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("|cff33ffccParty|rBeacon")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local L, R = 22, 290

    Check(f, "|cffffffffEnabled|r", "enabled", L, -52,
        "Master switch. Highlights only show while you're in a group (or in test mode).")
    Check(f, "|cffffffffNames only|r", "namesOnly", L + 112, -52,
        "Just a big coloured name over party members: no beacon, no health bars, and every other "
        .. "nameplate hidden. Your other settings are kept and come back when you turn this off.")

    local test = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    test:SetSize(210, 24)
    test:SetPoint("TOPLEFT", R, -52)
    test:SetScript("OnClick", function() ns:SetTestMode(not ns.testMode) end)
    Tooltip(test, "Shows the highlight on your current target so you can try styles while solo. "
        .. "Target any friendly player or NPC outdoors.")
    test.Update = function() test:SetText(ns.testMode and "Stop test" or "Test on my target") end
    widgets[#widgets + 1] = test

    -- left column: beacon + name ---------------------------------------
    Header(f, "Over their head", L, -90)
    local styleValues = {}
    for _, k in ipairs(ns.STYLE_ORDER) do styleValues[#styleValues + 1] = { k, ns.STYLES[k].label } end
    Lockable(Cycle(f, "Beacon style", "style", styleValues, L, -116,
        "Raid icon style is drawn locally - only you see it, nobody's real marker changes."), "style")
    Cycle(f, "Beacon colour", "colorMode", COLOR_MODES, L, -158)
    Swatch(f, "Custom beacon colour", "color", L, -200)
    Slider(f, "Beacon size", "size", 16, 128, 2, L, -226)
    Slider(f, "Lift above name", "offset", 0, 60, 2, L, -266)
    Check(f, "Bob up and down", "bob", L, -306)
    Check(f, "Glow behind beacon", "glow", L, -330)
    Check(f, "Pulse the glow", "pulse", L, -354)

    Header(f, "Name tag", L, -390)
    Lockable(Check(f, "Show big coloured name", "showName", L, -414,
        "A large name in a colour that stands out, drawn above their head."), "showName")
    Cycle(f, "Name colour", "nameColorMode", COLOR_MODES, L, -442)
    Swatch(f, "Custom name colour", "nameColor", L, -484)
    Slider(f, "Name size", "nameSize", 8, 32, 1, L, -510)
    Cycle(f, "Name outline", "nameOutline", OUTLINES, L, -548)

    -- right column: nameplates + world markers --------------------------
    Header(f, "Nameplates", R, -90)
    Check(f, "Turn on friendly nameplates", "autoPlates", R, -114,
        "Beacons ride on nameplates, so friendly ones need to be on. Turned on while grouped "
        .. "and put back the way you had it when you leave group or log out.")
    Lockable(Check(f, "Hide other friendly plates", "hideOthers", R, -138,
        "Hides nameplates of other players and friendly NPCs, so only your party stands out. "
        .. "Your current target is never hidden."), "hideOthers")
    Lockable(Check(f, "Hide party bars (beacon only)", "hidePartyPlate", R, -162,
        "Hides Blizzard's health bar/name on party members, leaving just the beacon and name tag."), "hidePartyPlate")
    Check(f, "Click through friendly plates", "clickThrough", R, -186,
        "Friendly nameplates won't catch your mouse clicks.")
    Check(f, "Max nameplate range", "farPlates", R, -210,
        "Raises nameplate distance to the client maximum so beacons show from further away.")
    Cycle(f, "Who to highlight in a raid", "scope", SCOPES, R, -240)
    local gn = Check(f, "Hide game's player names", "hideGameNames", R, -282,
        "Names only mode: hides the game's own floating names for friendly players while you're "
        .. "grouped, so party members don't get two names. Other friendly players' names hide too. "
        .. "Put back when you leave group or log out.")
    local gnUpdate = gn.Update
    gn.Update = function()
        gnUpdate()
        gn:SetAlpha(ns.db.namesOnly and 1 or 0.35)
        gn:EnableMouse(ns.db.namesOnly and true or false)
    end

    Header(f, "Shared world markers", R, -320)
    local note = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", R, -344)
    note:SetWidth(240)
    note:SetJustifyH("LEFT")
    note:SetText("Inside dungeons and raids the game blocks addons from friendly nameplates, "
        .. "so beacons can't show there. This puts real raid icons on party members instead. "
        .. "|cffffaa00Everyone in the group sees them.|r It never takes an icon that's "
        .. "already in use and only clears icons it placed.")
    Cycle(f, "Place markers", "worldIcons", MARKER_MODES, R, -430)
    local iconLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    iconLabel:SetPoint("TOPLEFT", R + 4, -474)
    iconLabel:SetText("Icon for each party member")
    for i = 1, 4 do IconPicker(f, i, R + 4 + (i - 1) * 40, -490) end

    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(120, 22)
    reset:SetPoint("BOTTOMRIGHT", -24, 20)
    reset:SetText("Defaults")
    reset:SetScript("OnClick", function() SlashCmdList.PARTYBEACON("reset") end)

    local ver = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ver:SetPoint("BOTTOMLEFT", 24, 26)
    ver:SetText("v" .. ns.version .. "  -  /pb help for commands")

    f:SetScript("OnShow", function() ns:UpdateOptions() end)

    self:RegisterSettingsPanel()
end

function ns:UpdateOptions()
    if not (self.options and self.options:IsShown()) then return end
    for _, w in ipairs(widgets) do w.Update() end
end

function ns:ToggleOptions()
    if not self.options then self:CreateOptions() end
    if self.options:IsShown() then self.options:Hide() else self.options:Show() end
end

-- A stub entry in the game's AddOns options list that opens the window.
function ns:RegisterSettingsPanel()
    local p = CreateFrame("Frame")
    p.name = "PartyBeacon"
    local t = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("PartyBeacon")
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(200, 26)
    b:SetPoint("TOPLEFT", 16, -50)
    b:SetText("Open PartyBeacon options")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        ns.options:Show()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(p, "PartyBeacon")
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
    end
end
