-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Camping
-- Your side of Forever's camps: the camp item each of your professions can place, the shared one-hour
-- cooldown after you place one, the Cooking campfire kits, and a reminder when you're at a fire and yours is ready.
-- It never maps other players' fires, and it never places anything for you.
local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_Camping"
ns = ns or {}

local GREEN, YELLOW, GRAY = "|cff40ff40", "|cffffff00", "|cff9d9d9d"
local COOLDOWN = 3600
local db
local say = ForeverArtisan.Printer("Camping")
ns.say = say
ns.DB = function() return db end

local function CharRec()
  local key = (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
  db.chars[key] = db.chars[key] or {}
  return db.chars[key]
end
ns.CharRec = CharRec

local function SpellName(id)
  if not id then return end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); return i and i.name
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

---------------------------------------------------------------- skills
-- skill line -> rank for every profession this character has (primary and secondary)
function ns.Skills()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ a, b, c, d, e, f }) do
        local name, _, rank, _, _, _, line = GetProfessionInfo(idx)
        if rank and line then out[line] = rank end
        if rank and name then out[name] = rank end
      end
    end
  end
  if next(out) == nil and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank = GetSkillLineInfo(i)
      if not header and name and rank then out[name] = rank end
    end
  end
  return out
end

local function SkillFor(skills, prof, line) return skills[line] or skills[prof] end

---------------------------------------------------------------- bags
-- camp items and kits in your bags: lower name -> { id, n, name }
function ns.BagItems()
  local found = {}
  local num = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local link = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  local info = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
  if not (num and link) then return found end
  for bag = 0, 4 do
    for slot = 1, (num(bag) or 0) do
      local l = link(bag, slot)
      local name = l and l:match("%[(.-)%]")
      local hit = name and (ns.CampItem(name) or ns.kitByName[name:lower()])
      if hit then
        local id = tonumber(l:match("item:(%d+)"))
        local n = 1
        local i = info and info(bag, slot)
        if type(i) == "table" then n = i.stackCount or 1 elseif type(i) == "number" then n = select(2, info(bag, slot)) or 1 end
        local key = name:lower()
        found[key] = found[key] or { id = id, n = 0, name = name, item = hit }
        found[key].n = found[key].n + n
      end
    end
  end
  return found
end

---------------------------------------------------------------- your camp items
-- one row per profession you have: what you can place now and what's next
function ns.Rows()
  local skills, bags, rows = ns.Skills(), ns.BagItems(), {}
  for _, p in ipairs(ns.CAMP) do
    local prof, line, icon, names = p[1], p[2], p[3], p[4]
    local skill = SkillFor(skills, prof, line)
    if skill then
      -- tier 1 comes with the skill; tiers 2 and 3 also need a Blueprint, so they only count once one is in your bags
      local tier = skill >= ns.TIERS[1] and 1 or 0
      local r = { prof = prof, icon = icon, skill = skill }
      for t = #names, 1, -1 do
        for _, b in pairs(bags) do
          if b.item and b.item.prof == prof and b.item.tier == t then r.have, r.haveN = b.name, b.n; break end
        end
        if r.have then tier = math.max(tier, t); break end
      end
      r.tier = tier
      if tier > 0 then r.now = names[tier] end
      if tier < #ns.TIERS then
        r.next, r.nextAt = names[tier + 1], ns.TIERS[tier + 1]
        r.blueprint = tier + 1 >= 2
        r.skillOK = skill >= r.nextAt
      end
      rows[#rows + 1] = r
    end
  end
  return rows
end

-- the kits with your Cooking skill: "use" / "learn" / "low"
function ns.KitRows()
  local skills, bags, out = ns.Skills(), ns.BagItems(), {}
  local cook = SkillFor(skills, "Cooking", ns.COOKING_LINE)
  for _, k in ipairs(ns.KITS) do
    local st = "low"
    if cook and cook >= k.use then st = "use" elseif cook and cook >= k.learn then st = "learn" end
    local b = bags[k.name:lower()]
    out[#out + 1] = { kit = k, state = st, cook = cook, have = b and b.n or 0 }
  end
  return out, cook
end

-- "Fishing Rack at 140", "Fishing Rack: needs a Blueprint" once your skill is there
function ns.NextText(r)
  if not r.next then return end
  if r.skillOK and r.blueprint then return r.next .. ": needs a Blueprint" end
  return ("%s at %d%s"):format(r.next, r.nextAt, r.blueprint and " + Blueprint" or "")
end

---------------------------------------------------------------- cooldown
-- seconds until you can place a camp item again (0 = ready). The item's own cooldown wins when one is in
-- your bags; otherwise the time we saved when you placed one.
function ns.Left()
  local getcd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if getcd then
    for _, b in pairs(ns.BagItems()) do
      if b.item and b.item.prof and b.id then
        local start, dur = getcd(b.id)
        if start and start > 0 and dur and dur > 1.5 then return math.max(0, start + dur - GetTime()) end
        if start == 0 then return 0 end
      end
    end
  end
  local c = CharRec()
  if c.readyAt and c.readyAt > time() then return c.readyAt - time() end
  return 0
end

local function Mins(s)
  if s >= 60 then return math.ceil(s / 60) .. " min" end
  return math.ceil(s) .. " sec"
end
ns.Mins = Mins

function ns.Status()
  local left = ns.Left()
  local c = CharRec()
  if left <= 0 then return GREEN .. "Camp items: ready|r" end
  return YELLOW .. "Camp items: ready in " .. Mins(left) .. "|r" .. (c.lastItem and (GRAY .. "  (placed " .. c.lastItem .. ")|r") or "")
end

local wake = 0
local function ScheduleReady(prev)
  local left = ns.Left()
  if left <= 0 or not C_Timer then return end
  if prev and left >= prev then return end -- the clock didn't move: don't spin
  wake = wake + 1
  local mine = wake
  C_Timer.After(left + 1, function()
    if mine ~= wake then return end
    if ns.Left() <= 0 then
      if db.settings.readyMsg then say(GREEN .. "Camp items are ready again.|r") end
      if ns.OnChange then ns.OnChange() end
    else
      ScheduleReady(left)
    end
  end)
end

function ns.Placed(name)
  local it = ns.CampItem(name)
  if not it then return end
  local c = CharRec()
  c.readyAt, c.lastItem, c.lastAt = time() + COOLDOWN, it.name, time()
  c.placed = (c.placed or 0) + 1
  if C_Timer then C_Timer.After(1, function() ScheduleReady() end) end
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- at a fire
-- the buff the game gives near a campfire ("Campfire Nearby" in the beta)
local function NearFire()
  for i = 1, 40 do
    local name
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not a then break end
      name = a.name
    elseif UnitBuff then
      name = UnitBuff("player", i)
      if not name then break end
    else
      break
    end
    if name and name:lower():find("campfire", 1, true) then return true end
  end
  return false
end
ns.NearFire = NearFire

local atFire, lastNudge = false, -10000
local function CheckFire()
  local now = NearFire()
  if now and not atFire and db.settings.reminder and ns.Left() <= 0 and GetTime() - lastNudge > 600 then
    local mine
    for _, b in pairs(ns.BagItems()) do
      if b.item and b.item.prof then
        if not mine or b.item.tier > mine.item.tier then mine = b end
      end
    end
    if mine then
      lastNudge = GetTime()
      say(YELLOW .. ("Your %s is ready. Place it at this fire."):format(mine.name) .. "|r")
    end
  end
  if now ~= atFire then
    atFire = now
    if ns.OnChange then ns.OnChange() end
  end
end
ns.CheckFire = CheckFire
function ns.AtFire() return atFire end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA",
  "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
  if e == "ADDON_LOADED" and a1 == ADDON then
    ForeverArtisanCampingDB = ForeverArtisanCampingDB or {}
    db = ForeverArtisanCampingDB
    db.version = ForeverArtisan.Version()
    db.settings = db.settings or {}
    if db.settings.reminder == nil then db.settings.reminder = true end
    if db.settings.readyMsg == nil then db.settings.readyMsg = true end
    db.chars = db.chars or {}
    return
  end
  if not db then return end
  if e == "PLAYER_ENTERING_WORLD" then
    ScheduleReady()
    CheckFire()
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    -- (unit, castGUID, spellID): placing a camp item is a cast named after the item
    ns.Placed(SpellName(a3))
  elseif e == "UNIT_AURA" and a1 == "player" then
    CheckFire()
  elseif e == "BAG_UPDATE_DELAYED" or e == "SKILL_LINES_CHANGED" then
    if ns.OnChange then ns.OnChange() end
  end
end)

---------------------------------------------------------------- slash
SLASH_FACAMP1 = "/facamp"
SlashCmdList.FACAMP = function(msg)
  if not db then return end
  local cmd = ((msg or ""):match("^(%S*)") or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "status" then
    say(ns.Status())
    for _, r in ipairs(ns.Rows()) do
      say(("  %s %d: %s%s"):format(r.prof, r.skill, r.now or (GRAY .. "nothing yet|r"),
        r.next and (GRAY .. "  (next: " .. ns.NextText(r) .. ")|r") or ""))
    end
  elseif cmd == "reminder" then
    db.settings.reminder = not db.settings.reminder
    say("Campfire reminder " .. (db.settings.reminder and "on." or "off."))
  elseif cmd == "ready" then
    db.settings.readyMsg = not db.settings.readyMsg
    say("Ready-again message " .. (db.settings.readyMsg and "on." or "off."))
  else
    say("Commands: /fa camp (window), status, reminder, ready")
  end
end
