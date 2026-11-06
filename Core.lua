-- PartyBeacon: makes your party members easy to pick out in a crowd.
--
-- What it can do, and why it works the way it does:
--   * Beacons + coloured names are drawn on top of party members' NAMEPLATES.
--     Nameplates are the only hook the game gives addons onto a character in
--     the 3D world, so friendly nameplates have to be on (the addon turns them
--     on for you while you're grouped and puts the setting back afterwards).
--   * Inside dungeons/raids the game locks friendly nameplates away from
--     addons, so beacons can't be drawn there. The optional "world markers"
--     mode covers that by putting real raid-target icons (star, circle...) over
--     party members' heads. Those are SHARED: the whole group sees them.

local ADDON, ns = ...
_G.PartyBeacon = ns

ns.version = "1.0.1"

local DEFAULTS = {
    enabled        = true,

    -- beacon over the head
    style          = "arrow",    -- arrow | chevron | diamond | beam | mark | hunter | none
    colorMode      = "slot",     -- slot | class | custom | rainbow
    color          = { r = 0.20, g = 1.00, b = 0.40 },
    size           = 44,
    offset         = 0,          -- extra gap between name and beacon
    bob            = true,
    pulse          = true,
    glow           = true,

    -- big coloured name
    showName       = true,
    nameColorMode  = "slot",     -- slot | class | custom | rainbow
    nameColor      = { r = 0.25, g = 0.95, b = 1.00 },
    nameSize       = 16,
    nameOutline    = "THICKOUTLINE",

    -- nameplate handling
    autoPlates     = true,       -- turn friendly nameplates on while grouped
    hideOthers     = true,       -- hide every other friendly nameplate
    hidePartyPlate = false,      -- hide Blizzard's bar for party (beacon/name only)
    clickThrough   = true,       -- friendly plates don't eat mouse clicks
    farPlates      = false,      -- push nameplate range to the client maximum
    scope          = "party",    -- party (your group / raid subgroup) | raid

    -- shared raid-target icons (the only thing that works inside instances)
    worldIcons     = "off",      -- off | instance | always
    icons          = { 1, 2, 3, 4 },  -- party1..party4: star, circle, diamond, triangle
}
ns.DEFAULTS = DEFAULTS

-- Bright colours that read well against any zone, one per group slot.
ns.SLOT_COLORS = {
    { 0.00, 1.00, 1.00 },  -- cyan
    { 1.00, 0.25, 0.90 },  -- magenta
    { 0.45, 1.00, 0.10 },  -- lime
    { 1.00, 0.60, 0.00 },  -- orange
    { 1.00, 1.00, 0.20 },  -- yellow
    { 0.55, 0.60, 1.00 },  -- periwinkle
    { 1.00, 0.35, 0.35 },  -- coral
    { 0.30, 1.00, 0.70 },  -- mint
}

ns.ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccPartyBeacon|r: " .. tostring(msg))
end
ns.Print = Print

-- WoW Forever runs on the modern engine, where some unit info can come back
-- as a "secret value" that addons may not compare, test or use as a table
-- key. Safe() turns those into nil so we just skip that unit.
local issecret = issecretvalue or function() return false end
ns.issecret = issecret
local function Safe(v)
    if v ~= nil and issecret(v) then return nil end
    return v
end
ns.Safe = Safe

-- Errors are caught, printed once, and kept in SavedVariables (last 10) so a
-- problem on a client we can't test on is visible instead of silent.
local seenErrors = {}
function ns:RecordError(where, err)
    local msg = tostring(where) .. ": " .. tostring(err)
    if self.db then
        local list = self.db.errors
        list[#list + 1] = date and (date("%Y-%m-%d %H:%M:%S") .. " " .. msg) or msg
        while #list > 10 do table.remove(list, 1) end
    end
    if not seenErrors[msg] then
        seenErrors[msg] = true
        Print("|cffff5555error|r " .. msg .. "  (|cffffff00/pb debug|r for details)")
    end
end

function ns:Try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then self:RecordError(where, err) end
    return ok
end

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function HSV(h)
    -- full-saturation hue (0..1) -> r, g, b
    local i = math.floor(h * 6) % 6
    local f = h * 6 - math.floor(h * 6)
    local q, t = 1 - f, f
    if i == 0 then return 1, t, 0
    elseif i == 1 then return q, 1, 0
    elseif i == 2 then return 0, 1, t
    elseif i == 3 then return 0, q, 1
    elseif i == 4 then return t, 0, 1
    else return 1, 0, q end
end

-- mode: slot | class | custom | rainbow
function ns:ColorFor(mode, unit, slot, custom, now)
    if mode == "class" and unit then
        local _, cls = UnitClass(unit)
        cls = Safe(cls)
        local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
        local c = cls and colors and colors[cls]
        if c and Safe(UnitIsPlayer(unit)) then return c.r, c.g, c.b end
        mode = "slot"   -- NPCs (test mode) have no class colour
    end
    if mode == "custom" and custom then
        return custom.r, custom.g, custom.b
    elseif mode == "rainbow" then
        return HSV(((now or GetTime()) * 0.25 + (slot or 1) * 0.17) % 1)
    end
    local list = ns.SLOT_COLORS
    local c = list[((slot or 1) - 1) % #list + 1]
    return c[1], c[2], c[3]
end

-- ---------------------------------------------------------------------------
-- group roster: guid -> { slot, unit }
-- ---------------------------------------------------------------------------
ns.members = {}

function ns:RebuildRoster()
    local members = self.members
    for k in pairs(members) do members[k] = nil end

    if IsInRaid() then
        local n = GetNumGroupMembers()
        local mySub
        for i = 1, n do
            if Safe(UnitIsUnit("raid" .. i, "player")) then
                local _, _, sub = GetRaidRosterInfo(i)
                mySub = sub
            end
        end
        local slot = 0
        for i = 1, n do
            local unit = "raid" .. i
            local _, _, sub = GetRaidRosterInfo(i)
            if UnitExists(unit) and not Safe(UnitIsUnit(unit, "player"))
               and (self.db.scope == "raid" or sub == mySub) then
                local guid = Safe(UnitGUID(unit))
                if guid then
                    slot = slot + 1
                    members[guid] = { slot = slot, unit = unit }
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            local guid = UnitExists(unit) and Safe(UnitGUID(unit))
            if guid then members[guid] = { slot = i, unit = unit } end
        end
    end
end

function ns:IsActive()
    return self.db.enabled and (IsInGroup() or self.testMode) and true or false
end

-- Which slot (colour / icon index) a nameplate unit should be highlighted
-- with, or nil if it shouldn't be.
function ns:HighlightSlot(unit)
    if not self:IsActive() or Safe(UnitIsUnit(unit, "player")) then return nil end
    local guid = Safe(UnitGUID(unit))
    local m = guid and self.members[guid]
    if m then return m.slot end
    if self.testMode and Safe(UnitIsUnit(unit, "target")) then return 1 end
    return nil
end

function ns:ShouldHideOther(unit)
    if not (self:IsActive() and self.db.hideOthers) then return false end
    if Safe(UnitIsUnit(unit, "target")) then return false end   -- never hide what you've clicked
    -- if the game won't tell us, leave the plate alone
    return Safe(UnitIsFriend("player", unit)) and not Safe(UnitCanAttack("player", unit)) and true or false
end

-- ---------------------------------------------------------------------------
-- CVars / nameplate settings. Originals are remembered in SavedVariables so
-- they're restored even after a /reload or crash while the addon was active.
-- Nameplate CVars can't be changed in combat, so changes wait for it to end.
-- ---------------------------------------------------------------------------
local function WantCVar(name, value)
    local restore = ns.db.cvarRestore
    local cur = GetCVar(name)
    if cur == nil then
        -- this client doesn't have that setting: never touch it
        restore[name] = nil
        return
    end
    if value ~= nil then
        if restore[name] == nil then restore[name] = cur or "" end
        if cur ~= value then pcall(SetCVar, name, value) end
    elseif restore[name] ~= nil then
        local orig = restore[name]
        restore[name] = nil
        if cur ~= orig then pcall(SetCVar, name, orig) end
    end
end

function ns:ApplySettings()
    if InCombatLockdown() then
        self.pendingSettings = true
        return
    end
    self.pendingSettings = nil
    local active = self:IsActive()
    local db = self.db

    local plates = (active and db.autoPlates) and "1" or nil
    -- Friendly player plates: WoW Forever / modern engine name, then the
    -- Classic name. Whichever this client doesn't have is skipped.
    WantCVar("nameplateShowFriendlyPlayers", plates)
    WantCVar("nameplateShowFriends", plates)
    -- Without "always show", the modern engine only shows plates in combat.
    WantCVar("nameplateShowAll", plates)
    -- Test mode lets you preview on a friendly NPC, so show NPC plates then.
    local npcs = (active and db.autoPlates and self.testMode) and "1" or nil
    WantCVar("nameplateShowFriendlyNpcs", npcs)
    WantCVar("nameplateShowFriendlyNPCs", npcs)
    WantCVar("nameplateMaxDistance", (active and db.farPlates) and "41" or nil)

    local NP = C_NamePlate
    if NP and NP.SetNamePlateFriendlyClickThrough then
        if active and db.clickThrough then
            if db.clickRestore == nil then
                db.clickRestore = NP.GetNamePlateFriendlyClickThrough
                    and NP.GetNamePlateFriendlyClickThrough() and true or false
            end
            pcall(NP.SetNamePlateFriendlyClickThrough, true)
        elseif db.clickRestore ~= nil then
            pcall(NP.SetNamePlateFriendlyClickThrough, db.clickRestore)
            db.clickRestore = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Shared world markers (raid-target icons). Rules, so it never fights the
-- tank's kill marks:
--   * only placed on someone who has no icon yet,
--   * only if that icon isn't already on something we can see,
--   * placed once - if someone moves or clears it, we leave it alone,
--   * we only ever clear icons we placed ourselves.
-- ---------------------------------------------------------------------------
ns.iconsSet = {}   -- guid -> icon index we placed

local function UnitForGUID(guid)
    local m = ns.members[guid]
    if m and UnitGUID(m.unit) == guid then return m.unit end
    local prefix, n = "party", 4
    if IsInRaid() then prefix, n = "raid", GetNumGroupMembers() end
    for i = 1, n do
        local u = prefix .. i
        if UnitGUID(u) == guid then return u end
    end
end

local function IconInUse(icon)
    local check = { "player", "target", "mouseover", "focus" }
    for i = 1, 4 do
        check[#check + 1] = "party" .. i
        check[#check + 1] = "party" .. i .. "target"
    end
    for unit in pairs(ns.unitPlate) do check[#check + 1] = unit end
    for _, u in ipairs(check) do
        if UnitExists(u) and Safe(GetRaidTargetIndex(u)) == icon then return true end
    end
    return false
end

function ns:WorldIconsWanted()
    local db = self.db
    if not (db.enabled and IsInGroup()) or db.worldIcons == "off" then return false end
    if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return false   -- raids need lead/assist to mark
    end
    if db.worldIcons == "instance" then
        local inInstance, kind = IsInInstance()
        return inInstance and kind ~= "none" and true or false
    end
    return true
end

function ns:ClearWorldIcons()
    for guid, icon in pairs(self.iconsSet) do
        local u = UnitForGUID(guid)
        if u and Safe(GetRaidTargetIndex(u)) == icon then pcall(SetRaidTarget, u, 0) end
        self.iconsSet[guid] = nil
    end
end

function ns:UpdateWorldIcons()
    if not self:WorldIconsWanted() then
        self:ClearWorldIcons()
        return
    end
    -- forget members who left
    for guid in pairs(self.iconsSet) do
        if not self.members[guid] then self.iconsSet[guid] = nil end
    end
    for guid, m in pairs(self.members) do
        local icon = self.db.icons[m.slot]
        if icon and icon > 0 and not self.iconsSet[guid]
           and not Safe(GetRaidTargetIndex(m.unit)) and not IconInUse(icon) then
            if pcall(SetRaidTarget, m.unit, icon) then self.iconsSet[guid] = icon end
        end
    end
end

-- ---------------------------------------------------------------------------
-- refresh everything after any change
-- ---------------------------------------------------------------------------
function ns:Refresh()
    -- each step on its own, so one failure can't block the rest
    self:Try("roster", self.RebuildRoster, self)
    self:Try("settings", self.ApplySettings, self)
    self:Try("plates", self.RefreshPlates, self)
    self:Try("markers", self.UpdateWorldIcons, self)
    if self.UpdateOptions then self:Try("options", self.UpdateOptions, self) end
end

-- In test mode, say why nothing appeared when the target has no plate.
local lastHint
function ns:CheckTestTarget()
    if not (self.testMode and UnitExists("target")) then return end
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if plate and not (plate.IsForbidden and plate:IsForbidden()) then return end
    local inInstance, kind = IsInInstance()
    local hint
    if plate or (inInstance and kind ~= "none" and Safe(UnitIsFriend("player", "target"))) then
        hint = "can't draw on that target: the game blocks addons from friendly nameplates inside instances."
    else
        hint = "your target has no nameplate showing, so there's nothing to attach the beacon to. "
            .. "Make sure nameplates are on (Options > Nameplates), the target is close and on screen, "
            .. "and you're out of combat if the settings just changed. |cffffff00/pb debug|r shows the details."
    end
    if hint ~= lastHint then
        lastHint = hint
        Print(hint)
    end
end

function ns:Debug()
    local db = self.db
    local d = {}
    local function add(k, v) d[#d + 1] = k .. "=" .. tostring(v) end
    local ver, build, _, toc = GetBuildInfo()
    add("client", tostring(ver) .. "." .. tostring(build) .. " toc " .. tostring(toc))
    add("project", WOW_PROJECT_ID)
    add("enabled", db.enabled)
    add("active", self:IsActive())
    add("test", self.testMode or false)
    add("inGroup", IsInGroup())
    local n, p = 0, 0
    for _ in pairs(self.members) do n = n + 1 end
    for _ in pairs(self.unitPlate) do p = p + 1 end
    add("members", n)
    add("platesTracked", p)
    for _, cv in ipairs({ "nameplateShowFriendlyPlayers", "nameplateShowFriends", "nameplateShowAll",
                          "nameplateShowEnemies", "nameplateShowFriendlyNpcs", "nameplateMaxDistance",
                          "nameplateShowOnlyNameForFriendlyPlayerUnits" }) do
        add(cv, GetCVar(cv))
    end
    local tp = UnitExists("target") and C_NamePlate.GetNamePlateForUnit("target")
    add("targetPlate", UnitExists("target") and (tp and (tp.IsForbidden and tp:IsForbidden() and "forbidden" or "yes") or "none") or "no target")
    add("combat", InCombatLockdown())
    add("pendingSettings", self.pendingSettings or false)
    db.lastDebug = d
    Print("debug (also saved for support on /reload):")
    for _, line in ipairs(d) do DEFAULT_CHAT_FRAME:AddMessage("   " .. line) end
    if #db.errors > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("   last error: " .. db.errors[#db.errors])
    end
end

local refreshQueued
function ns:QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = nil
        ns:Refresh()
    end)
end

function ns:SetEnabled(on)
    self.db.enabled = on and true or false
    if not on then self.testMode = nil end
    self:Refresh()
    Print(on and "|cff33ff33on|r" or "|cffff4444off|r")
end

function ns:Toggle() self:SetEnabled(not self.db.enabled) end
function PartyBeacon_Toggle() ns:Toggle() end   -- key binding

function ns:SetTestMode(on)
    self.testMode = on and true or nil
    if on and not self.db.enabled then self.db.enabled = true end
    self:Refresh()
    if on then
        Print("test mode |cff33ff33on|r - your current target is shown as a party member. "
            .. "Target a friendly player or NPC outdoors to see it. |cffffff00/pb test|r again to stop.")
        lastHint = nil
        C_Timer.After(0.5, function() ns:Try("test", ns.CheckTestTarget, ns) end)
    else
        Print("test mode off")
    end
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.eventFrame = ev

local function OnEvent(event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        PartyBeaconDB = CopyDefaults(PartyBeaconDB or {}, DEFAULTS)
        PartyBeaconDB.cvarRestore = PartyBeaconDB.cvarRestore or {}
        PartyBeaconDB.errors = PartyBeaconDB.errors or {}
        ns.db = PartyBeaconDB
        ev:UnregisterEvent("ADDON_LOADED")
        if ns.CreateOptions then ns:Try("options window", ns.CreateOptions, ns) end
    elseif event == "PLAYER_LOGIN" then
        ns:Try("scan", ns.ScanPlates, ns)
        ns:Refresh()
        Print("v" .. ns.version .. " loaded - |cffffff00/pb|r for options, |cffffff00/pb test|r to preview on your target.")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ns:OnPlateAdded(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        ns:OnPlateRemoved(arg1)
    elseif event == "PLAYER_TARGET_CHANGED" then
        ns:RefreshPlates()
        if ns.testMode then
            C_Timer.After(0.3, function() ns:Try("test", ns.CheckTestTarget, ns) end)
        end
    elseif event == "UNIT_NAME_UPDATE" then
        if ns.unitPlate[arg1] then ns:UpdatePlate(arg1) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.pendingSettings then ns:ApplySettings() end
    elseif event == "PLAYER_LOGOUT" then
        -- leave the game's settings exactly as we found them
        local was = ns.db.enabled
        ns.db.enabled = false
        ns.testMode = nil
        if not InCombatLockdown() then ns:ApplySettings() end
        ns.db.enabled = was
    else
        -- GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA
        ns:QueueRefresh()
    end
end

ev:SetScript("OnEvent", function(_, event, arg1)
    local ok, err = pcall(OnEvent, event, arg1)
    if not ok then ns:RecordError(event, err) end
end)

for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
    "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_NAME_UPDATE",
    "PLAYER_REGEN_ENABLED",
}) do
    ev:RegisterEvent(e)
end

-- ---------------------------------------------------------------------------
-- slash commands
-- ---------------------------------------------------------------------------
local STYLES = { arrow = 1, chevron = 1, diamond = 1, beam = 1, mark = 1, hunter = 1, none = 1 }
local COLORS = { slot = 1, class = 1, custom = 1, rainbow = 1 }

local function Help()
    Print("commands:")
    local lines = {
        "/pb - open the options window",
        "/pb on | off | toggle",
        "/pb test - preview on your current target (works solo)",
        "/pb style arrow|chevron|diamond|beam|mark|hunter|none",
        "/pb color slot|class|custom|rainbow  (beacon colour)",
        "/pb name slot|class|custom|rainbow|off  (name colour)",
        "/pb size <16-128>   /pb namesize <8-32>",
        "/pb others on|off  (hide other friendly nameplates)",
        "/pb markers off|instance|always  (shared raid icons)",
        "/pb status   /pb debug   /pb reset",
    }
    for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   |cffffff00" .. l .. "|r") end
end

local function Status()
    local db = ns.db
    local n = 0
    for _ in pairs(ns.members) do n = n + 1 end
    Print(string.format("%s, %d member(s) tracked, style %s, beacon colour %s, name %s, markers %s%s",
        db.enabled and "on" or "off", n, db.style, db.colorMode,
        db.showName and db.nameColorMode or "off", db.worldIcons,
        ns.testMode and ", TEST MODE" or ""))
    local inInstance, kind = IsInInstance()
    if inInstance and kind ~= "none" then
        Print("you're in an instance: the game hides friendly nameplates from addons here, "
            .. "so beacons can't show. Use |cffffff00/pb markers instance|r for shared icons.")
    end
end

SLASH_PARTYBEACON1 = "/pb"
SLASH_PARTYBEACON2 = "/partybeacon"
SlashCmdList.PARTYBEACON = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    local db = ns.db
    if cmd == "" or cmd == "options" or cmd == "config" then
        if ns.ToggleOptions then ns:ToggleOptions() else Help() end
    elseif cmd == "on" then ns:SetEnabled(true)
    elseif cmd == "off" then ns:SetEnabled(false)
    elseif cmd == "toggle" then ns:Toggle()
    elseif cmd == "test" then ns:SetTestMode(not ns.testMode)
    elseif cmd == "style" and STYLES[arg] then db.style = arg; ns:Refresh(); Print("style: " .. arg)
    elseif cmd == "color" and COLORS[arg] then db.colorMode = arg; ns:Refresh(); Print("beacon colour: " .. arg)
    elseif cmd == "name" and arg == "off" then db.showName = false; ns:Refresh(); Print("names off")
    elseif cmd == "name" and COLORS[arg] then
        db.showName = true; db.nameColorMode = arg; ns:Refresh(); Print("name colour: " .. arg)
    elseif cmd == "size" and tonumber(arg) then
        db.size = math.max(16, math.min(128, tonumber(arg))); ns:Refresh(); Print("size: " .. db.size)
    elseif cmd == "namesize" and tonumber(arg) then
        db.nameSize = math.max(8, math.min(32, tonumber(arg))); ns:Refresh(); Print("name size: " .. db.nameSize)
    elseif cmd == "others" and (arg == "on" or arg == "off") then
        db.hideOthers = (arg == "on"); ns:Refresh()
        Print("other friendly nameplates " .. (db.hideOthers and "hidden" or "shown"))
    elseif cmd == "markers" and (arg == "off" or arg == "instance" or arg == "always") then
        db.worldIcons = arg; ns:Refresh(); Print("shared world markers: " .. arg)
    elseif cmd == "status" then Status()
    elseif cmd == "debug" then ns:Debug()
    elseif cmd == "reset" then
        local restore, click, errors = db.cvarRestore, db.clickRestore, db.errors
        for k in pairs(db) do db[k] = nil end
        CopyDefaults(db, DEFAULTS)
        db.cvarRestore, db.clickRestore, db.errors = restore, click, errors
        ns:Refresh()
        Print("settings reset to defaults")
    else
        Help()
    end
end

BINDING_HEADER_PARTYBEACON = "PartyBeacon"
BINDING_NAME_PARTYBEACON_TOGGLE = "Toggle party highlights"
