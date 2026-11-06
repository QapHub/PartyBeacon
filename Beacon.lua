-- Draws the beacon + big coloured name above party members' nameplates, and
-- hides the other friendly nameplates so party members are the only thing
-- floating over people's heads.

local _, ns = ...

local MEDIA = "Interface\\AddOns\\PartyBeacon\\Media\\"
ns.MEDIA = MEDIA

local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- w/h are multiples of the size setting.
ns.STYLES = {
    arrow   = { label = "Arrow",          tex = MEDIA .. "arrow",   w = 1,    h = 1,    tint = true },
    chevron = { label = "Chevrons",       tex = MEDIA .. "chevron", w = 1,    h = 1,    tint = true },
    diamond = { label = "Gem",            tex = MEDIA .. "diamond", w = 0.8,  h = 1,    tint = true },
    beam    = { label = "Light pillar",   tex = MEDIA .. "beam",    w = 0.55, h = 3.2,  tint = true, noBob = true, additive = true },
    mark    = { label = "Raid icon (only you see it)", tex = RAID_ICONS, w = 0.75, h = 0.75, raidIcon = true },
    hunter  = { label = "Hunter's Mark",  tex = "Interface\\Icons\\Ability_Hunter_SniperShot", w = 0.75, h = 0.75,
                coords = { 0.08, 0.92, 0.08, 0.92 } },
    none    = { label = "None (name only)" },
}
ns.STYLE_ORDER = { "arrow", "chevron", "diamond", "beam", "mark", "hunter", "none" }

local unitPlate = {}                         -- nameplate unit -> plate
local overlays  = setmetatable({}, { __mode = "k" })   -- plate -> overlay
local hidden    = setmetatable({}, { __mode = "k" })   -- plates whose bar we hid
ns.unitPlate = unitPlate

local function RaidIconCoords(i)
    i = (i or 1) - 1
    local col, row = i % 4, math.floor(i / 4)
    return col / 4, (col + 1) / 4, row / 4, (row + 1) / 4
end
ns.RaidIconCoords = RaidIconCoords

-- ---------------------------------------------------------------------------
-- overlay frame
-- ---------------------------------------------------------------------------
local function CreateOverlay(plate)
    local o = CreateFrame("Frame", nil, plate)
    o:SetSize(1, 1)
    o:SetPoint("BOTTOM", plate, "TOP", 0, 2)
    o:SetFrameLevel((plate:GetFrameLevel() or 0) + 10)

    o.name = o:CreateFontString(nil, "OVERLAY")
    o.name:SetPoint("BOTTOM", o, "BOTTOM", 0, 0)

    o.holder = CreateFrame("Frame", nil, o)
    o.holder:SetSize(1, 1)

    o.glow = o.holder:CreateTexture(nil, "BACKGROUND")
    o.glow:SetTexture(MEDIA .. "glow")
    o.glow:SetBlendMode("ADD")

    o.icon = o.holder:CreateTexture(nil, "ARTWORK")
    o.icon:SetPoint("BOTTOM", o.holder, "BOTTOM", 0, 0)
    o.glow:SetPoint("CENTER", o.icon, "CENTER", 0, 0)

    o.bob = o.holder:CreateAnimationGroup()
    local t = o.bob:CreateAnimation("Translation")
    t:SetOffset(0, 8)
    t:SetDuration(0.55)
    t:SetSmoothing("IN_OUT")
    o.bob:SetLooping("BOUNCE")

    o.pulse = o.glow:CreateAnimationGroup()
    local a = o.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.3)
    a:SetDuration(0.8)
    a:SetSmoothing("IN_OUT")
    o.pulse:SetLooping("BOUNCE")

    overlays[plate] = o
    return o
end

local function SetFont(fs, size, outline)
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, outline)
end

local function Play(group, on)
    if on then
        if not group:IsPlaying() then group:Play() end
    elseif group:IsPlaying() then
        group:Stop()
    end
end

local function Configure(o, unit, slot)
    local db = ns.db
    o.unit, o.slot = unit, slot
    o.rainbowName = db.showName and db.nameColorMode == "rainbow"
    o.rainbowBeacon = db.colorMode == "rainbow"

    -- name
    if db.showName then
        SetFont(o.name, db.nameSize, db.nameOutline)
        local name = UnitName(unit)
        -- a hidden ("secret") name can still be displayed, just not tested
        if not ns.issecret(name) and name == nil then name = "" end
        o.name:SetText(name)
        o.name:SetTextColor(ns:ColorFor(db.nameColorMode, unit, slot, db.nameColor))
        o.name:Show()
    else
        o.name:Hide()
    end

    -- beacon
    local st = ns.STYLES[db.style]
    o.holder:ClearAllPoints()
    if db.showName then
        o.holder:SetPoint("BOTTOM", o.name, "TOP", 0, 2 + db.offset)
    else
        o.holder:SetPoint("BOTTOM", o, "BOTTOM", 0, db.offset)
    end

    if st and st.tex then
        local w, h = db.size * st.w, db.size * st.h
        o.holder:SetSize(w, h)
        o.icon:SetTexture(st.tex)
        o.icon:SetSize(w, h)
        o.icon:SetBlendMode(st.additive and "ADD" or "BLEND")
        if st.raidIcon then
            o.icon:SetTexCoord(RaidIconCoords(db.icons[slot] or ((slot - 1) % 8 + 1)))
        elseif st.coords then
            o.icon:SetTexCoord(unpack(st.coords))
        else
            o.icon:SetTexCoord(0, 1, 0, 1)
        end
        local r, g, b = ns:ColorFor(db.colorMode, unit, slot, db.color)
        if st.tint then o.icon:SetVertexColor(r, g, b) else o.icon:SetVertexColor(1, 1, 1) end

        if db.glow and not st.additive then
            local gs = math.max(w, h) * 1.9
            o.glow:SetSize(gs, gs)
            o.glow:SetVertexColor(r, g, b)
            o.glow:Show()
        else
            o.glow:Hide()
        end
        o.holder:Show()
        Play(o.bob, db.bob and not st.noBob)
        Play(o.pulse, db.pulse and o.glow:IsShown())
    else
        o.holder:Hide()
        Play(o.bob, false)
        Play(o.pulse, false)
    end
    o:Show()
end

local function StopOverlay(o)
    o:Hide()
    o.unit = nil
    Play(o.bob, false)
    Play(o.pulse, false)
end

local function SetBarHidden(plate, hide)
    local uf = plate.UnitFrame
    if not uf then return end
    if hide then
        hidden[plate] = true
        uf:SetAlpha(0)
    elseif hidden[plate] then
        hidden[plate] = nil
        uf:SetAlpha(1)
    end
end

-- ---------------------------------------------------------------------------
-- nameplate tracking
-- ---------------------------------------------------------------------------
local function GetPlate(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    -- friendly plates inside instances are forbidden to addons
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return nil end
    return plate
end

function ns:OnPlateAdded(unit)
    local plate = GetPlate(unit)
    if not plate then return end
    unitPlate[unit] = plate
    self:UpdatePlate(unit)
end

function ns:OnPlateRemoved(unit)
    local plate = unitPlate[unit]
    unitPlate[unit] = nil
    if plate then
        local o = overlays[plate]
        if o then StopOverlay(o) end
        SetBarHidden(plate, false)   -- plates are recycled: hand it back clean
    end
end

function ns:UpdatePlate(unit)
    local plate = unitPlate[unit]
    if not plate then return end
    local slot = self:HighlightSlot(unit)
    if slot then
        Configure(overlays[plate] or CreateOverlay(plate), unit, slot)
        SetBarHidden(plate, self.db.hidePartyPlate)
    else
        local o = overlays[plate]
        if o then StopOverlay(o) end
        SetBarHidden(plate, self:ShouldHideOther(unit))
    end
end

function ns:RefreshPlates()
    if not self.db then return end
    for unit in pairs(unitPlate) do self:Try("plate", self.UpdatePlate, self, unit) end
end

-- pick up plates that already exist (after /reload)
function ns:ScanPlates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then self:OnPlateAdded(unit) end
    end
end

-- ---------------------------------------------------------------------------
-- rainbow colour cycling (only runs while a rainbow overlay is visible)
-- ---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.05 then return end
    elapsed = 0
    local db = ns.db
    if not db then return end
    local now = GetTime()
    for _, o in pairs(overlays) do
        if o.unit and o:IsShown() then
            if o.rainbowName then
                o.name:SetTextColor(ns:ColorFor("rainbow", o.unit, o.slot, nil, now))
            end
            if o.rainbowBeacon then
                local r, g, b = ns:ColorFor("rainbow", o.unit, o.slot, nil, now)
                local st = ns.STYLES[db.style]
                if st and st.tint then o.icon:SetVertexColor(r, g, b) end
                o.glow:SetVertexColor(r, g, b)
            end
        end
    end
end)
