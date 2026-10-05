-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Herbalism: Cultivation (Tauren racial, WoW Forever).
-- Cultivation grows a duplicate of a nearby herb that anyone can pick, Herbalism or not. One-hour cooldown,
-- each herb only once, and each herb has a player-level requirement (Forever beta, Sep 24).
-- We don't ship those levels: when a cast fails on level, we remember it for that herb; when it works, that too.
-- Everything here stays quiet unless this character knows the spell.
local _, ns = ...
if not ns or not ns.DB then return end

local GREEN, YELLOW, GRAY = "|cff40ff40", "|cffffff00", "|cff9d9d9d"
local CULTIVATION = "Cultivation"
local spellID          -- found from the spellbook by name; Forever's id isn't public
local say = ns.say

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); return i and i.name
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- the spell's id if this character knows it, else nil
local function FindSpell()
  if spellID then
    if IsPlayerSpell and not IsPlayerSpell(spellID) then return nil end
    return spellID
  end
  local id
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, i = pcall(C_Spell.GetSpellInfo, CULTIVATION)
    id = ok and type(i) == "table" and i.spellID or nil
  end
  if not id and GetSpellInfo then
    local ok, name, _, _, _, _, _, sid = pcall(GetSpellInfo, CULTIVATION)
    if ok and name then id = sid end
  end
  if id and IsPlayerSpell and not IsPlayerSpell(id) then return nil end
  spellID = id
  return id
end

function ns.KnowsCultivation() return FindSpell() ~= nil end

local function IsCultivation(id)
  if not id then return false end
  if spellID and id == spellID then return true end
  if SpellName(id) == CULTIVATION then spellID = id; return true end
  return false
end

local function DB()
  local db = ns.DB()
  if not db then return end
  db.cultivate = db.cultivate or {}
  db.cultivate.herbs = db.cultivate.herbs or {}
  if db.settings.cultivation == nil then db.settings.cultivation = true end
  return db
end
local function On() local db = DB(); return db and db.settings.cultivation and ns.KnowsCultivation() end

-- seconds until it's ready (0 = ready; the global cooldown doesn't count)
local function Left()
  local id = FindSpell()
  if not id then return end
  local start, dur
  if C_Spell and C_Spell.GetSpellCooldown then
    local i = C_Spell.GetSpellCooldown(id)
    if type(i) == "table" then start, dur = i.startTime, i.duration end
  elseif GetSpellCooldown then
    start, dur = GetSpellCooldown(id)
  end
  if ForeverArtisan.AnySecret(start, dur) then return nil end -- hidden in combat: unknown for now
  if not start or start == 0 or not dur or dur <= 1.5 then return 0 end
  return math.max(0, start + dur - GetTime())
end
ns.CultivationLeft = Left

local function Mins(s)
  if s >= 60 then return math.ceil(s / 60) .. " min" end
  return math.ceil(s) .. " sec"
end

---------------------------------------------------------------- per-herb level, learned from your own casts
local function HerbRec(name)
  local db = DB()
  if not db or not name or name == "" then return end
  local h = db.cultivate.herbs[name]
  if not h then h = {}; db.cultivate.herbs[name] = h end
  return h
end

-- true = your level is enough, false = too low, nil = not known yet. Second value: the level to show.
function ns.CultivationLevelOK(name)
  local db = DB()
  local h = db and name and db.cultivate.herbs[name]
  if not h then return nil end
  local lvl = UnitLevel("player") or 0
  if h.need then return lvl >= h.need, h.need end
  if h.ok and lvl >= h.ok then return true end
  if h.low and lvl <= h.low then return false, h.low + 1 end
  return nil
end

local castTarget        -- { name, t } while a Cultivation cast is in flight
local lastHerbTip       -- { name, t } the herb you last hovered: the cast's target when the game doesn't name it

function ns.NoteHerbHover(name) lastHerbTip = { name = name, t = GetTime() } end

local function TargetName(sent)
  if type(sent) == "string" and sent ~= "" then return sent end
  if lastHerbTip and GetTime() - lastHerbTip.t < 15 then return lastHerbTip.name end
end

local function LevelError(msg)
  local h = castTarget and HerbRec(castTarget.name)
  if not h then return end
  local lvl = UnitLevel("player") or 0
  local n = tonumber(msg:match("(%d+)"))
  if n and n > lvl then
    h.need = n
  else
    h.low = math.max(h.low or 0, lvl)
  end
  castTarget = nil
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- tooltip line for a herb out in the world
function ns.CultivationTip(tt, name)
  if not On() then return end
  if name then ns.NoteHerbHover(name) end
  local ok, need = ns.CultivationLevelOK(name)
  if ok == false then
    ForeverArtisan.TipLine(tt, GRAY .. ("Cultivation: needs level %d for this herb"):format(need) .. "|r")
    return
  end
  local left = Left()
  if left == 0 then
    ForeverArtisan.TipLine(tt, GREEN .. "Cultivation ready:|r cast it first to grow a duplicate")
  end
end

-- one line for the Herbalism window: "Cultivation: ready" / "Cultivation: 23 min"
function ns.CultivationStatus()
  if not On() then return end
  local left = Left()
  if not left then return end -- hidden in combat
  if left == 0 then return GREEN .. "Cultivation: ready|r" end
  return GRAY .. "Cultivation: " .. Mins(left) .. "|r"
end

---------------------------------------------------------------- reminders
local nudged = false     -- one nudge per ready period
local wake = 0           -- newest timer wins

local function ScheduleReady(prev)
  local left = Left()
  if not left or left <= 0 or not C_Timer then return end
  if prev and left >= prev then return end -- the clock didn't move: don't spin
  wake = wake + 1
  local mine = wake
  C_Timer.After(left + 1, function()
    if mine ~= wake or not On() then return end
    if Left() == 0 then
      nudged = false
      say(GREEN .. "Cultivation is ready again.|r")
      if ns.OnChange then ns.OnChange() end
    else
      ScheduleReady(left)
    end
  end)
end

-- you started picking a herb while Cultivation was ready: say it once
function ns.CultivationNudge(herb)
  if nudged or not On() or Left() ~= 0 then return end
  if ns.CultivationLevelOK(herb) == false then return end
  nudged = true
  say(YELLOW .. "Cultivation is ready.|r Cast it on a herb before you pick it to grow a free duplicate.")
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "UI_ERROR_MESSAGE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do
  if not (ev.RegisterUnitEvent and pcall(ev.RegisterUnitEvent, ev, e, "player")) then pcall(ev.RegisterEvent, ev, e) end
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
  if not ns.DB() then return end
  -- casts in combat carry hidden ("secret") details on Forever; nobody cultivates mid-fight
  if InCombatLockdown() then return end
  if e == "PLAYER_ENTERING_WORLD" or e == "SPELLS_CHANGED" then
    if e == "SPELLS_CHANGED" and not spellID then FindSpell() end
    if e == "PLAYER_ENTERING_WORLD" and On() then ScheduleReady() end
  elseif e == "UNIT_SPELLCAST_SENT" and a1 == "player" then
    -- (unit, target, castGUID, spellID)
    if IsCultivation(a4) then
      castTarget = { name = TargetName(a2), t = GetTime() }
    elseif ns.IsHerbSpell and ns.IsHerbSpell(a4) then
      ns.CultivationNudge(a2)
    end
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    -- (unit, castGUID, spellID)
    if IsCultivation(a3) then
      local h = castTarget and HerbRec(castTarget.name)
      if h then
        local lvl = UnitLevel("player") or 0
        h.ok = math.min(h.ok or lvl, lvl)
        h.n = (h.n or 0) + 1
        if h.low and h.low >= lvl then h.low = nil end
      end
      local db = DB(); db.cultivate.casts = (db.cultivate.casts or 0) + 1
      castTarget = nil
      nudged = false
      if C_Timer then C_Timer.After(1, function() ScheduleReady() end) end
      if ns.OnChange then ns.OnChange() end
    end
  elseif e == "UI_ERROR_MESSAGE" then
    -- a failed cast's reason; the target is kept from UNIT_SPELLCAST_SENT for two seconds
    local msg = type(a2) == "string" and a2 or a1
    if castTarget and type(msg) == "string" and GetTime() - castTarget.t < 2 and msg:lower():find("level") then
      LevelError(msg)
    end
  end
end)

---------------------------------------------------------------- /fa herb cultivation
function ns.CultivationReport(rest)
  local db = DB()
  rest = (rest or ""):lower()
  if rest == "on" or rest == "off" then
    db.settings.cultivation = (rest == "on")
    say("Cultivation reminders " .. rest .. ".")
    if ns.OnChange then ns.OnChange() end
    return
  end
  if not ns.KnowsCultivation() then
    say("This character doesn't know Cultivation. It's a Tauren racial.")
    return
  end
  local left = Left()
  say(("Cultivation: %s  ·  reminders %s  ·  cast %d times"):format(left == 0 and "ready" or (left and ("ready in " .. Mins(left))) or "unknown in combat",
    db.settings.cultivation and "on" or "off", db.cultivate.casts or 0))
  local names = {}
  for name in pairs(db.cultivate.herbs) do names[#names + 1] = name end
  table.sort(names)
  if #names == 0 then
    say(GRAY .. "No herbs tried yet. Each herb has a level requirement; I learn it from your casts.|r")
    return
  end
  for _, name in ipairs(names) do
    local h = db.cultivate.herbs[name]
    local bits = {}
    if h.need then bits[#bits + 1] = "needs level " .. h.need end
    if h.ok then bits[#bits + 1] = "worked at " .. h.ok end
    if h.low and not h.need then bits[#bits + 1] = "too low at " .. h.low end
    say(("  %s: %s"):format(name, table.concat(bits, ", ")))
  end
end

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(ev)
