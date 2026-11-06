-- Headless tests for PartyBeacon. Stubs just enough of the WoW API.
--   node tests/run.js tests/test.lua

unpack = table.unpack
tinsert = table.insert
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local pass, fail = 0, 0
local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- ---------------------------------------------------------------- frames
local Frame = {}
local function newObj(kind, parent)
    local o = setmetatable({ kind = kind, parent = parent, shown = true, alpha = 1,
                             scripts = {}, events = {}, w = 0, h = 0 }, Frame)
    return o
end
Frame.__index = function(t, k)
    local v = rawget(Frame, k)
    if v ~= nil then return v end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
end
function Frame:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:GetSize() return self.w, self.h end
function Frame:SetScript(n, f) self.scripts[n] = f end
function Frame:GetScript(n) return self.scripts[n] end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:GetFrameLevel() return 1 end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:SetTextColor(r, g, b) self.color = { r, g, b } end
function Frame:SetVertexColor(r, g, b) self.vcolor = { r, g, b } end
function Frame:SetTexture(t) self.texture = t end
function Frame:SetTexCoord(...) self.coords = { ... } end
function Frame:SetChecked(c) self.checked = c end
function Frame:GetChecked() return self.checked end
function Frame:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
function Frame:SetFont(f, s, o) self.font = { f, s, o }; return true end
function Frame:IsForbidden() return self.forbidden or false end
function Frame:CreateFontString() return newObj("FontString", self) end
function Frame:CreateTexture() return newObj("Texture", self) end
function Frame:CreateAnimationGroup()
    local g = newObj("AnimationGroup", self)
    g.playing = false
    function g:CreateAnimation() return newObj("Animation", g) end
    function g:Play() self.playing = true end
    function g:Stop() self.playing = false end
    function g:IsPlaying() return self.playing end
    return g
end
function Frame:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end end

local allFrames = {}
function CreateFrame(kind, name, parent)
    local f = newObj(kind, parent)
    if kind ~= "Frame" or parent then f.shown = true end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end
UIParent = newObj("Frame")
GameTooltip = newObj("GameTooltip")
ColorPickerFrame = newObj("Frame")
UISpecialFrames = {}
SlashCmdList = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
BackdropTemplateMixin = {}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flush() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end

local now = 100
function GetTime() return now end

-- ---------------------------------------------------------------- world
local units = {}        -- token -> info
local alias = {}        -- nameplateN -> party token etc.
local function U(token)
    token = alias[token] or token
    return units[token]
end
local function setUnit(token, info) units[token] = info end

setUnit("player", { guid = "P-0", name = "Me", class = "HUNTER", player = true, friend = true })

local group = { kind = nil }   -- nil | "party" | "raid"
function IsInGroup() return group.kind ~= nil end
function IsInRaid() return group.kind == "raid" end
function GetNumGroupMembers() return group.n or 0 end
function GetRaidRosterInfo(i) local u = units["raid" .. i]; return u and u.name, 0, u and u.sub end
function UnitIsGroupLeader() return group.leader or false end
function UnitIsGroupAssistant() return false end

function UnitExists(t) return U(t) ~= nil end
function UnitGUID(t) local u = U(t); if u and u.secret then return SECRET end; return u and u.guid end
function UnitName(t) local u = U(t); if u and u.nameError then error("boom") end; if u and u.secret then return SECRET end; return u and u.name end
function UnitClass(t) local u = U(t); return u and u.class, u and u.class end
function UnitIsPlayer(t) local u = U(t); return u and u.player or false end
function UnitIsUnit(a, b) local x, y = U(a), U(b); return x ~= nil and y ~= nil and x.guid == y.guid end
function UnitIsFriend(_, t) local u = U(t); if u and u.secret then return SECRET end; return u and u.friend or false end
function UnitCanAttack(_, t) local u = U(t); return u and not u.friend or false end

local icons = {}        -- guid -> icon
function GetRaidTargetIndex(t) local u = U(t); return u and icons[u.guid] end
local setRaidCalls = 0
function SetRaidTarget(t, i)
    setRaidCalls = setRaidCalls + 1
    local u = U(t)
    for g, v in pairs(icons) do if v == i and i ~= 0 then icons[g] = nil end end
    icons[u.guid] = (i ~= 0) and i or nil
end

local instance = { false, "none" }
function IsInInstance() return instance[1], instance[2] end

local combat = false
function InCombatLockdown() return combat end

-- WoW Forever's real CVar names (read from its Wow.exe): there is NO
-- nameplateShowFriendlyPlayers, and plates only show in combat unless ShowAll is on.
local cvars = { nameplateShowFriendlyPlayers = "0", nameplateShowAll = "0",
                nameplateShowFriendlyNpcs = "0", nameplateShowEnemies = "1",
                nameplateMaxDistance = "20" }
local unknownSets = 0
function GetCVar(n) return cvars[n] end
function SetCVar(n, v)
    if combat then error("protected in combat") end
    if cvars[n] == nil then unknownSets = unknownSets + 1; return false end
    cvars[n] = tostring(v)
end
function GetBuildInfo() return "1.60.1", "70790", "", 16001 end
WOW_PROJECT_ID = 99

-- secret values: an opaque object that errors if compared/indexed
local SECRET = setmetatable({}, {
    __index = function() error("attempt to index a secret value") end,
    __eq = function() error("attempt to compare a secret value") end,
    __tostring = function() return "<secret>" end,
})
function issecretvalue(v) return rawequal(v, SECRET) end

RAID_CLASS_COLORS = {
    MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PRIEST = { r = 1, g = 1, b = 1 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}

local plates = {}       -- nameplate token -> plate
local clickThrough = false
C_NamePlate = {
    GetNamePlateForUnit = function(t) return plates[t] end,
    SetNamePlateFriendlyClickThrough = function(v) clickThrough = v end,
    GetNamePlateFriendlyClickThrough = function() return clickThrough end,
}

-- ---------------------------------------------------------------- load
local ns = {}
for _, f in ipairs({ "Core.lua", "Beacon.lua", "Options.lua" }) do
    local chunk = assert(loadfile(f))
    chunk("PartyBeacon", ns)
end
local ev = ns.eventFrame
local function fire(e, ...) ev.scripts.OnEvent(ev, e, ...) end

local function addPlate(token, unitToken, forbidden)
    alias[token] = unitToken
    local p = newObj("Frame")
    p.UnitFrame = newObj("Frame", p)
    p.forbidden = forbidden
    plates[token] = p
    fire("NAME_PLATE_UNIT_ADDED", token)
    return p
end
local function removePlate(token)
    fire("NAME_PLATE_UNIT_REMOVED", token)
    plates[token] = nil
    alias[token] = nil
end
local function overlayOf(p)
    for _, f in ipairs(allFrames) do if f.parent == p and f.name and f.holder then return f end end
end

-- ================================================================ tests
fire("ADDON_LOADED", "PartyBeacon")
ok(ns.db and ns.db.style == "arrow", "defaults applied")
ok(PartyBeaconOptions ~= nil, "options frame built")
fire("PLAYER_LOGIN")
ok(cvars.nameplateShowFriendlyPlayers == "0", "solo: friendly plates untouched")
ok(not ns:IsActive(), "solo: inactive")

-- join a party
setUnit("party1", { guid = "P-1", name = "Jaina", class = "MAGE", player = true, friend = true })
setUnit("party2", { guid = "P-2", name = "Anduin", class = "PRIEST", player = true, friend = true })
group.kind = "party"
fire("GROUP_ROSTER_UPDATE"); flush()
ok(ns:IsActive(), "party: active")
ok(cvars.nameplateShowFriendlyPlayers == "1", "party: friendly plates turned on")
ok(ns.db.cvarRestore.nameplateShowFriendlyPlayers == "0", "party: original value remembered")
ok(cvars.nameplateShowAll == "1", "forever: always-show turned on so plates appear out of combat")
ok(cvars.nameplateShowFriendlyNpcs == "0", "forever: friendly NPC plates left off outside test mode")
ok(unknownSets == 0 and ns.db.cvarRestore.nameplateShowFriends == nil, "forever: never touches CVars the client lacks")
local loaded = false
for _, m in ipairs(chat) do if m:find("loaded") then loaded = true end end
ok(loaded, "login message printed")
ok(clickThrough == true, "party: click-through on")
ok(cvars.nameplateMaxDistance == "20", "far plates off by default")

local p1 = addPlate("nameplate1", "party1")
local o1 = overlayOf(p1)
ok(o1 and o1.shown, "party member gets an overlay")
ok(o1 and o1.name.text == "Jaina", "name tag text")
local c = ns.SLOT_COLORS[1]
ok(o1 and near(o1.name.color[1], c[1]) and near(o1.name.color[2], c[2]), "name uses slot colour")
ok(o1 and o1.icon.texture:find("arrow"), "arrow texture")
ok(o1 and o1.bob.playing and o1.pulse.playing, "bob + pulse running")
ok(p1.UnitFrame.alpha == 1, "party plate bar kept by default")

setUnit("stranger", { guid = "P-9", name = "Rando", class = "WARRIOR", player = true, friend = true })
local p2 = addPlate("nameplate2", "stranger")
ok(p2.UnitFrame.alpha == 0, "other friendly plate hidden")
ok(not overlayOf(p2), "stranger gets no overlay")

setUnit("boar", { guid = "C-1", name = "Boar", friend = false })
local p3 = addPlate("nameplate3", "boar")
ok(p3.UnitFrame.alpha == 1, "enemy plate never hidden")

-- targeting the stranger shows their plate again
alias.target = "stranger"
fire("PLAYER_TARGET_CHANGED")
ok(p2.UnitFrame.alpha == 1, "targeted friendly plate shown")
alias.target = nil
fire("PLAYER_TARGET_CHANGED")
ok(p2.UnitFrame.alpha == 0, "re-hidden after target cleared")

-- recycled plate is handed back clean
removePlate("nameplate2")
ok(p2.UnitFrame.alpha == 1, "removed plate alpha restored")

-- forbidden plate (instance) is ignored
local pf = addPlate("nameplate4", "party2", true)
ok(not overlayOf(pf) and ns.unitPlate.nameplate4 == nil, "forbidden plate ignored")
removePlate("nameplate4")

-- class colour + style options
ns.db.nameColorMode = "class"; ns.db.colorMode = "custom"; ns.db.style = "beam"
ns:Refresh()
ok(near(o1.name.color[1], 0.25) and near(o1.name.color[3], 0.92), "class-coloured name")
ok(near(o1.icon.vcolor[1], ns.db.color.r), "custom beacon colour")
ok(o1.icon.texture:find("beam") and not o1.bob.playing, "beam style does not bob")
ns.db.style = "mark"; ns:Refresh()
ok(o1.icon.coords and near(o1.icon.coords[1], 0) and near(o1.icon.coords[2], 0.25), "mark style = star for P1")
ns.db.icons[1] = 6; ns:Refresh()
ok(near(o1.icon.coords[1], 0.25) and near(o1.icon.coords[3], 0.25), "mark style follows icon choice (square)")
ns.db.style = "none"; ns:Refresh()
ok(not o1.holder.shown and o1.name.shown, "none style = name only")
ns.db.showName = false; ns:Refresh()
ok(not o1.name.shown, "name can be turned off")
ns.db.showName = true; ns.db.style = "arrow"; ns.db.icons[1] = 1

-- rainbow cycling runs
ns.db.nameColorMode = "rainbow"; ns:Refresh()
local before = o1.name.color[1] .. "," .. o1.name.color[2]
now = now + 1.3
local drivers = {}
for _, f in ipairs(allFrames) do if f.scripts.OnUpdate then drivers[#drivers + 1] = f end end
for _, d in ipairs(drivers) do d.scripts.OnUpdate(d, 0.1) end
ok(o1.name.color[1] .. "," .. o1.name.color[2] ~= before, "rainbow name changes over time")
ns.db.nameColorMode = "slot"

-- hide party bar option
ns.db.hidePartyPlate = true; ns:Refresh()
ok(p1.UnitFrame.alpha == 0, "party bar hidden when asked")
ns.db.hidePartyPlate = false; ns:Refresh()
ok(p1.UnitFrame.alpha == 1, "party bar back")

-- far plates
ns.db.farPlates = true; ns:Refresh()
ok(cvars.nameplateMaxDistance == "41", "far plates raised")
ns.db.farPlates = false; ns:Refresh()
ok(cvars.nameplateMaxDistance == "20", "far plates restored")

-- secret (hidden) unit info: no error, plate left alone
local errsBefore = #ns.db.errors
setUnit("hidden", { guid = "P-8", name = "Hidden", player = true, friend = true, secret = true })
local ps = addPlate("nameplate6", "hidden")
ok(#ns.db.errors == errsBefore, "secret unit: no errors")
ok(not overlayOf(ps) and ps.UnitFrame.alpha == 1, "secret unit: not highlighted, not hidden")
removePlate("nameplate6")

-- one broken unit can't stop the others
setUnit("party2", { guid = "P-2", name = "Anduin", class = "PRIEST", player = true, friend = true, nameError = true })
local pb = addPlate("nameplate7", "party2")
ok(#ns.db.errors == errsBefore + 1, "error recorded in SavedVariables")
ok(chat[#chat]:find("error"), "error printed to chat")
units.party2.nameError = nil
ns:Refresh()
ok(o1.shown and o1.name.text == "Jaina", "other plates still work after an error")
ok(overlayOf(pb) and overlayOf(pb).name.text == "Anduin", "broken unit recovers on next refresh")
removePlate("nameplate7")

-- /pb debug
SlashCmdList.PARTYBEACON("debug")
local dbg = table.concat(ns.db.lastDebug, " ")
ok(dbg:find("nameplateShowFriendlyPlayers=1") and dbg:find("toc 16001"), "/pb debug reports CVars and client")

-- ---------------------------------------------------- world markers
ns.db.worldIcons = "instance"; ns:Refresh()
ok(next(icons) == nil, "markers: none outside instance in instance mode")
instance = { true, "party" }
setUnit("party3", { guid = "P-3", name = "Thrall", class = "WARRIOR", player = true, friend = true })
icons["P-3"] = 8                         -- tank already marked as skull
setUnit("mob", { guid = "C-2", name = "Ogre", friend = false })
icons["C-2"] = 2                         -- circle is on a mob
alias.target = "mob"
fire("ZONE_CHANGED_NEW_AREA"); flush()
ok(icons["P-1"] == 1, "markers: party1 gets star")
ok(icons["P-2"] == nil and icons["C-2"] == 2, "markers: circle already on a mob is not stolen")
ok(icons["P-3"] == 8, "markers: existing icon left alone")

-- tank moves the star onto a mob: we must not put it back
setUnit("mob2", { guid = "C-3", name = "Ogre 2", friend = false })
SetRaidTarget("mob2", 1)
local calls = setRaidCalls
fire("GROUP_ROSTER_UPDATE"); flush()
ok(icons["C-3"] == 1 and icons["P-1"] == nil, "markers: never re-asserts a moved icon")
ok(setRaidCalls == calls, "markers: no SetRaidTarget spam")

-- leaving the instance clears only ours (star moved, so nothing of ours left)
instance = { false, "none" }
fire("ZONE_CHANGED_NEW_AREA"); flush()
ok(icons["C-3"] == 1 and icons["P-3"] == 8, "markers: others' icons untouched on clear")

-- placed icon is cleared on leaving
alias.target = nil
instance = { true, "party" }
icons["C-2"] = nil
fire("ZONE_CHANGED_NEW_AREA"); flush()
ok(icons["P-2"] == 2, "markers: circle placed once free")
instance = { false, "none" }
fire("ZONE_CHANGED_NEW_AREA"); flush()
ok(icons["P-2"] == nil, "markers: our icon cleared after leaving instance")
ns.db.worldIcons = "off"

-- raid without assist: no marking
group.kind = "raid"; group.n = 3
setUnit("raid1", { guid = "P-0", name = "Me", sub = 1, player = true, friend = true })
setUnit("raid2", { guid = "P-1", name = "Jaina", sub = 1, class = "MAGE", player = true, friend = true })
setUnit("raid3", { guid = "P-7", name = "Faraway", sub = 2, class = "MAGE", player = true, friend = true })
ns.db.worldIcons = "always"
ns:Refresh()
ok(not ns:WorldIconsWanted(), "raid: no markers without lead/assist")
ok(ns.members["P-1"] and not ns.members["P-7"], "raid: only my subgroup by default")
ns.db.scope = "raid"; ns:Refresh()
ok(ns.members["P-7"] ~= nil, "raid: whole raid when chosen")
ns.db.scope = "party"; ns.db.worldIcons = "off"
group.kind = "party"; group.n = nil

-- ---------------------------------------------------- combat-safe CVars
combat = true
group.kind = nil
fire("GROUP_ROSTER_UPDATE"); flush()
ok(cvars.nameplateShowFriendlyPlayers == "1", "combat: CVar change deferred")
ok(not o1.shown, "left group: overlay hidden immediately")
combat = false
fire("PLAYER_REGEN_ENABLED")
ok(cvars.nameplateShowFriendlyPlayers == "0", "after combat: friendly plates restored")
ok(clickThrough == false, "after combat: click-through restored")
ok(ns.db.cvarRestore.nameplateShowFriendlyPlayers == nil, "restore record cleared")

-- ---------------------------------------------------- test mode (solo)
setUnit("npc", { guid = "C-9", name = "Guard", friend = true })
local p5 = addPlate("nameplate5", "npc")
ok(p5.UnitFrame.alpha == 1, "solo: nothing hidden")
alias.target = "npc"
ns:SetTestMode(true)
local o5 = overlayOf(p5)
ok(o5 and o5.shown and o5.name.text == "Guard", "test mode highlights target")
ok(cvars.nameplateShowFriendlyPlayers == "1", "test mode turns plates on")
ok(cvars.nameplateShowFriendlyNpcs == "1" and cvars.nameplateShowAll == "1", "test mode shows friendly NPC plates")
-- target with no nameplate -> explain why
setUnit("faraway", { guid = "C-8", name = "Far Guard", friend = true })
alias.target = "faraway"
fire("PLAYER_TARGET_CHANGED"); flush()
ok(chat[#chat]:find("no nameplate"), "test mode explains a target without a plate")
alias.target = "npc"
fire("PLAYER_TARGET_CHANGED"); flush()
ns:SetTestMode(false)
ok(not o5.shown and cvars.nameplateShowFriendlyPlayers == "0", "test mode off cleans up")

-- ---------------------------------------------------- options window
ns:ToggleOptions()
ok(PartyBeaconOptions.shown, "options open")
-- find the style cycle button by its label text
local styleBtn
for _, f in ipairs(allFrames) do if f.text == "Arrow" and f.scripts.OnClick then styleBtn = f end end
ok(styleBtn ~= nil, "style button shows current style")
if styleBtn then
    styleBtn:Click("LeftButton")
    ok(ns.db.style == "chevron" and styleBtn.text == "Chevrons", "style cycles forward")
    styleBtn:Click("RightButton"); styleBtn:Click("RightButton")
    ok(ns.db.style == "none", "style cycles backward with wrap")
end
ns:ToggleOptions()
ok(not PartyBeaconOptions.shown, "options close")

-- ---------------------------------------------------- slash commands
SlashCmdList.PARTYBEACON("style beam"); ok(ns.db.style == "beam", "/pb style")
SlashCmdList.PARTYBEACON("name rainbow"); ok(ns.db.nameColorMode == "rainbow", "/pb name")
SlashCmdList.PARTYBEACON("name off"); ok(ns.db.showName == false, "/pb name off")
SlashCmdList.PARTYBEACON("size 500"); ok(ns.db.size == 128, "/pb size clamps")
SlashCmdList.PARTYBEACON("markers instance"); ok(ns.db.worldIcons == "instance", "/pb markers")
SlashCmdList.PARTYBEACON("off"); ok(ns.db.enabled == false, "/pb off")
ns.db.cvarRestore.fake = "x"
SlashCmdList.PARTYBEACON("reset")
ok(ns.db.style == "arrow" and ns.db.enabled and ns.db.cvarRestore.fake == "x", "/pb reset keeps restore data")
ns.db.cvarRestore.fake = nil
SlashCmdList.PARTYBEACON("bogus"); ok(chat[#chat]:find("/pb status"), "unknown -> help")

-- ---------------------------------------------------- logout restores
group.kind = "party"
fire("GROUP_ROSTER_UPDATE"); flush()
ok(cvars.nameplateShowFriendlyPlayers == "1", "regrouped: plates on")
fire("PLAYER_LOGOUT")
ok(cvars.nameplateShowFriendlyPlayers == "0", "logout: plates restored")
ok(ns.db.enabled == true, "logout: enabled setting preserved")

ok(cvars.nameplateShowAll == "0" and cvars.nameplateShowFriendlyNpcs == "0", "logout: all CVars back to original")

-- ---------------------------------------------------- Classic-style client
cvars = { nameplateShowFriends = "0", nameplateShowAll = "1", nameplateMaxDistance = "20" }
unknownSets = 0
fire("GROUP_ROSTER_UPDATE"); flush()
ok(cvars.nameplateShowFriends == "1" and unknownSets == 0, "classic client: uses nameplateShowFriends")
group.kind = nil
fire("GROUP_ROSTER_UPDATE"); flush()
ok(cvars.nameplateShowFriends == "0", "classic client: restored")

print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then error("tests failed") end
