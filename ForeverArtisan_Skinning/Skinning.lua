-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Skinning
-- Logs every mob you skin by zone (name, level, what it dropped), tracks skill-ups,
-- shows which mob levels to skin next, keeps goals, adds leather and mob tooltips,
-- and reminds you when your Skinning Knife is missing.
local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_Skinning"
ns = ns or {}

local GREEN, YELLOW, RED, GRAY = "|cff40ff40", "|cffffff00", "|cffff4040", "|cff9d9d9d"
local RAW_CAP = 5000
local SKINNING_SKILL_LINE = 393
local SKIN_SPELLS = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
-- Skinning Knife, plus skinners that also count as one
local KNIVES = { 7005, 15138, 19901 }

local db
local say = ForeverArtisan.Printer("Skinning")
ns.say = say
ns.DB = function() return db end

---------------------------------------------------------------- API wrappers
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); return i and i.name
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local SKINNING = SpellName(8613) or "Skinning"

local function IsSkinSpell(id)
  return (id and SKIN_SPELLS[id]) or (id and SpellName(id) == SKINNING) or false
end

local function ItemName(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local n = f and f(id)
  if n then return n end
  local l = ns.leatherById[id]
  return (l and l.name) or ns.EXTRAS[id] or ("item:" .. id)
end
ns.ItemName = ItemName

local function Today() return date("%Y-%m-%d") end

local CountAPI = (C_Item and C_Item.GetItemCount) or GetItemCount
function ns.HasKnife()
  if not CountAPI then return nil end
  for _, id in ipairs(KNIVES) do
    local ok, n = pcall(CountAPI, id)
    if ok and (n or 0) > 0 then return true end
  end
  return false
end

---------------------------------------------------------------- skill
-- Saved data is shared by every character on the account, so the skill cache is per character.
local function CharRec()
  local key = (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
  db.chars = db.chars or {}
  db.chars[key] = db.chars[key] or {}
  return db.chars[key]
end

local skillSource = "none"
local function IsSkinName(n) return n and (n == SKINNING or n == "Skinning") end

local function SkillLive()
  if GetProfessions and GetProfessionInfo then
    local ok, p1, p2 = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ p1, p2 }) do -- pairs: a profession you lack is nil, and ipairs would stop there
        if idx then
          local name, _, rank, maxr, _, _, line, mod = GetProfessionInfo(idx)
          if rank and (line == SKINNING_SKILL_LINE or IsSkinName(name)) then
            skillSource = "GetProfessionInfo"; return rank, mod, maxr
          end
        end
      end
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, SKINNING_SKILL_LINE)
    if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
      skillSource = "C_TradeSkillUI"; return info.skillLevel, info.skillModifier, info.maxSkillLevel
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod, maxr = GetSkillLineInfo(i)
      if not header and IsSkinName(name) and rank then
        skillSource = "GetSkillLineInfo"; return rank, mod, maxr
      end
    end
  end
  if db then
    local c = CharRec()
    -- the game's list loaded without this profession: not learned (or unlearned), so drop the old value
    if ForeverArtisan.ProfessionListLoaded and ForeverArtisan.ProfessionListLoaded() then c.skill = nil; return end
    if c.skill then skillSource = "chat"; return c.skill, nil, c.skillMax end
  end
end

local function Skill()
  local r, m, mx = SkillLive()
  if r and skillSource ~= "chat" and db then
    local c = CharRec()
    c.skill = r; if mx and mx > 0 then c.skillMax = mx end
  end
  return r, m, mx or (db and CharRec().skillMax)
end

-- has this character learned the profession?
function ns.Knows()
  return Skill() ~= nil
end
ns.Skill = Skill

local function EffSkill()
  local r, m = Skill()
  if not r then return end
  return r + (m or 0)
end
ns.EffSkill = EffSkill

---------------------------------------------------------------- where
local function Where()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local x, y
  if mapID then
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then x, y = pos:GetXY() end
  end
  local zone = GetRealZoneText() or GetZoneText() or "?"
  local sub = GetSubZoneText() or ""
  if sub == "" then sub = zone end
  return zone, sub, mapID, x and math.floor(x * 1000 + 0.5) / 10, y and math.floor(y * 1000 + 0.5) / 10
end

local function ZoneRec(zone, sub, mapID)
  if not zone then zone, sub, mapID = Where() end
  local key = zone .. " / " .. sub
  local z = db.zones[key]
  if not z then
    z = { zone = zone, sub = sub, mapID = mapID, nodes = 0, items = {}, mobs = {} }
    db.zones[key] = z
  end
  z.mobs = z.mobs or {}
  return z, key
end
ns.ZoneRec = ZoneRec

---------------------------------------------------------------- session
local session = { nodes = 0, items = 0, ups = 0, start = nil, startSkill = nil, last = nil }
ns.session = session

function ns.SessionInfo()
  local s = { nodes = session.nodes, items = session.items, ups = session.ups, last = session.last }
  if session.start then
    s.mins = (GetTime() - session.start) / 60
    if s.mins >= 1 then s.perHour = math.floor(session.items * 60 / s.mins + 0.5) end
  end
  return s
end

function ns.SkillInfo()
  local rank, mod, max = Skill()
  local info = { rank = rank, mod = mod, max = max, source = skillSource }
  if not rank then return info end
  session.startSkill = session.startSkill or rank
  local npp
  if session.ups > 0 then npp = session.nodes / session.ups end
  if not npp then
    local log, n, c = db.skillLog, 0, 0
    for i = #log, math.max(1, #log - 9), -1 do
      if (log[i].c or 0) > 0 then n, c = n + 1, c + log[i].c end
    end
    if n > 0 then npp = c / n end
  end
  info.npp = npp
  if max and max > rank then
    info.toCap = max - rank
    if npp then info.nodesToCap = math.ceil(info.toCap * npp) end
  end
  info.capped = max and rank >= max and max < 300
  info.sinceUp = db.sinceUp or 0
  return info
end

---------------------------------------------------------------- where things are
-- One place format everywhere: "Subzone (Zone)", or just the zone when they match.
function ns.Place(z)
  if not z then return "?" end
  if not z.sub or z.sub == z.zone then return z.zone or "?" end
  return z.sub .. " (" .. z.zone .. ")"
end

-- your top spots, best first: "Thendal Grove (Zephras Isle), Windshear Crag (Stonetalon)  +3 more"
local function ZoneNames(list, limit)
  if #list == 0 then return nil end
  limit = limit or 2
  local names = {}
  for i = 1, math.min(limit, #list) do names[i] = ns.Place(list[i].z) end
  local extra = #list - limit
  return table.concat(names, ", ") .. (extra > 0 and ("  +" .. extra .. " more") or "")
end

-- zones where an item came off a corpse
function ns.ZoneText(id, limit)
  local out = {}
  for _, z in pairs(db.zones) do
    local it = z.items[id]
    if it and it.hauls > 0 then out[#out + 1] = { z = z, n = it.hauls } end
  end
  table.sort(out, function(a, b) return a.n > b.n end)
  return ZoneNames(out, limit)
end

-- Skin next: color bands of mob levels, plus mobs you've skinned that are in them now
function ns.PickNext()
  local skill = EffSkill()
  local bands = ns.LevelBands(skill)
  local mobs = {}
  for _, z in pairs(db.zones) do
    for name, m in pairs(z.mobs or {}) do
      local lvl = m.maxL or m.minL
      local c = ns.SkinColor(ns.ReqForLevel(lvl), skill)
      if c == "orange" or c == "yellow" or c == "green" then
        mobs[#mobs + 1] = { name = name, lvl = lvl, minL = m.minL, maxL = m.maxL, n = m.n, color = c, zone = z.zone, sub = z.sub }
      end
    end
  end
  local rankOf = { orange = 1, yellow = 2, green = 3 }
  table.sort(mobs, function(a, b)
    if rankOf[a.color] ~= rankOf[b.color] then return rankOf[a.color] < rankOf[b.color] end
    return (a.lvl or 0) > (b.lvl or 0)
  end)
  return bands, mobs, skill
end

---------------------------------------------------------------- goals
local function Have(id) return (db.goalGot and db.goalGot[id]) or 0 end

local function ItemIdByName(name)
  name = name:lower()
  for id, l in pairs(ns.leatherById) do if l.name:lower() == name then return id, l.name end end
  for id, n in pairs(ns.EXTRAS) do if n:lower() == name then return id, n end end
  for _, z in pairs(db.zones) do
    for id, it in pairs(z.items) do
      if it.name and it.name:lower() == name then return id, it.name end
    end
  end
end

function ns.AddGoal(id, want, name)
  if not id then return end
  want = math.max(1, math.min(9999, tonumber(want) or 20))
  for _, g in ipairs(db.goals) do
    if g.id == id then
      g.want = want; g.met = nil
      say(("Goal updated: %d %s."):format(want, g.name or ItemName(id)))
      if ns.OnChange then ns.OnChange() end
      return
    end
  end
  db.goals[#db.goals + 1] = { id = id, want = want, name = name or ItemName(id) }
  say(("Goal added: %d %s."):format(want, name or ItemName(id)))
  if ns.OnChange then ns.OnChange() end
end

function ns.AddGoalByName(name, want)
  local id, real = ItemIdByName(name)
  if not id then say("I don't know that item. Check the spelling, or skin one first.") return end
  ns.AddGoal(id, want, real)
end

-- change a goal's amount from the number box on the Progress tab
function ns.SetGoalWant(i, n)
  local g = db.goals[i]
  n = math.max(1, math.min(9999, math.floor(tonumber(n) or 0)))
  if not g or g.want == n then return end
  g.want = n; g.met = nil
  if ns.OnChange then ns.OnChange() end
end

function ns.RemoveGoal(i)
  table.remove(db.goals, i)
  if ns.OnChange then ns.OnChange() end
end

function ns.ResetGoalProgress(quiet)
  db.goalGot = {}
  for _, g in ipairs(db.goals) do g.met = nil end
  if not quiet then say("Goal progress reset to 0.") end
  if ns.OnChange then ns.OnChange() end
end

function ns.GoalRows()
  local rows = {}
  for i, g in ipairs(db.goals) do
    rows[#rows + 1] = { i = i, id = g.id, name = g.name or ItemName(g.id), want = g.want, have = Have(g.id),
      where = ns.ZoneText(g.id) }
  end
  return rows
end

local function CheckGoals()
  for _, g in ipairs(db.goals) do
    local have = Have(g.id)
    if have >= g.want and not g.met then
      g.met = true
      say(GREEN .. ("Goal done: %d %s.|r"):format(g.want, g.name or ItemName(g.id)))
      pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
    elseif have < g.want then
      g.met = nil
    end
  end
end

---------------------------------------------------------------- skinning log
local pending        -- { mob = name, level = n, t = GetTime(), ok = bool }
local lastLootAt = -100

local function LogSkin()
  local now = GetTime()
  if now - lastLootAt < 1 then return end
  if not (pending and pending.ok and now - pending.t < 6) then return end
  lastLootAt = now
  local zone, sub, mapID, x, y = Where()
  local z = ZoneRec(zone, sub, mapID)
  local rank = Skill()
  local entry = { d = Today(), t = time(), zone = zone, sub = sub, mapID = mapID, x = x, y = y,
                  mob = pending.mob, level = pending.level, skill = rank, items = {} }
  local mobName, mobLevel = pending.mob, pending.level
  pending = nil
  local got = {}
  for i = 1, (GetNumLootItems() or 0) do
    local link = GetLootSlotLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      local _, name, qty, _, quality = GetLootSlotInfo(i)
      qty = qty or 1
      entry.items[#entry.items + 1] = { id = id, n = qty }
      local it = z.items[id]
      if not it then it = { name = name, q = quality, n = 0, hauls = 0 }; z.items[id] = it end
      it.n = it.n + qty
      it.hauls = it.hauls + 1
      it.name = name or it.name
      it.lastSeen = Today()
      if rank then it.minSkill = math.min(it.minSkill or rank, rank) end
      if mobLevel then
        it.minL = math.min(it.minL or mobLevel, mobLevel)
        it.maxL = math.max(it.maxL or mobLevel, mobLevel)
      end
      db.goalGot[id] = (db.goalGot[id] or 0) + qty
      session.items = session.items + qty
      got[#got + 1] = (qty > 1 and (qty .. "x ") or "") .. (link or name or ItemName(id))
    end
  end
  if #entry.items == 0 then return end
  z.nodes = z.nodes + 1
  if mobName then
    local m = z.mobs[mobName] or { n = 0 }
    m.n = m.n + 1
    if mobLevel then
      m.minL = math.min(m.minL or mobLevel, mobLevel)
      m.maxL = math.max(m.maxL or mobLevel, mobLevel)
    end
    z.mobs[mobName] = m
  end
  z.lastSeen = Today()
  db.raw[#db.raw + 1] = entry
  -- trim the oldest 10% at once instead of shifting the whole log on every pick
  if #db.raw > RAW_CAP then
    local n, drop = #db.raw, math.floor(RAW_CAP / 10)
    for i = 1, n - drop do db.raw[i] = db.raw[i + drop] end
    for i = n - drop + 1, n do db.raw[i] = nil end
  end
  db.sinceUp = (db.sinceUp or 0) + 1
  session.nodes = session.nodes + 1
  session.start = session.start or GetTime()
  session.startSkill = session.startSkill or rank
  session.last = got[1] .. (mobName and (GRAY .. "  from " .. mobName .. (mobLevel and (" (" .. mobLevel .. ")") or "") .. "|r") or "")
  if db.settings.verbose then say("Skinned " .. table.concat(got, ", ")) end
  CheckGoals()
  if ns.OnChange then ns.OnChange() end
end

function ns.ResetLog()
  db.zones, db.raw = {}, {}
  say("Skinning log cleared.")
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- knife reminder
local lastKnifeWarn = 0
local function CheckReminders(force)
  if not db.settings.reminder then return end
  if not ns.Knows() then return end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
  if ns.HasKnife() == false and (force or GetTime() - lastKnifeWarn > 300) then
    lastKnifeWarn = GetTime()
    say(YELLOW .. "No Skinning Knife in your bags.|r You'll need one to skin.")
  end
end
ns.CheckReminders = CheckReminders

---------------------------------------------------------------- tooltips
local function LeatherLines(tt, id)
  local l = ns.leatherById[id]
  local extra = ns.EXTRAS[id]
  if not l and not extra then return end
  tt:AddLine(" ")
  if l then
    ForeverArtisan.TipLine(tt, ("|cffd4a94eSkinning|r  %susually from mobs level %d-%d|r"):format(GRAY, l.lo, l.hi))
  else
    ForeverArtisan.TipLine(tt, "|cffd4a94eSkinning: from certain mobs|r")
  end
  local where = ns.ZoneText(id)
  tt:AddLine(where and ("Skinned in: " .. where) or (GRAY .. "Not in your skinning log yet.|r"), 0.9, 0.9, 0.9, true)
end

local function ItemTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.faSkinDone then return end
  local _, link = tt:GetItem()
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return end
  tt.faSkinDone = true
  LeatherLines(tt, id)
  tt:Show()
end

-- mouse over a beast: show the skill it needs and your color for it
local SKINNABLE_TYPES = { Beast = true, Dragonkin = true }
local function UnitTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.faSkinDone then return end
  local _, unit = tt:GetUnit()
  if not unit or UnitIsPlayer(unit) then return end
  local ctype = UnitCreatureType and UnitCreatureType(unit)
  if not (ctype and SKINNABLE_TYPES[ctype]) then return end
  local lvl = UnitLevel(unit)
  if not lvl or lvl < 1 then return end
  tt.faSkinDone = true
  local req = ns.ReqForLevel(lvl)
  local skill = EffSkill()
  local c = ns.SkinColor(req, skill)
  ForeverArtisan.TipLine(tt, ("|cffd4a94eSkinning %d|r%s"):format(req,
    skill and ("  " .. ns.COLOR_CODE[c] .. ns.COLOR_WORD[c] .. "|r") or ""))
  tt:Show()
end

local function HookTooltips()
  local function clear(self) self.faSkinDone = nil end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
      if tt == GameTooltip or tt == ItemRefTooltip then pcall(ItemTip, tt) end
    end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
      if tt == GameTooltip then pcall(UnitTip, tt) end
    end)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      tt:HookScript("OnTooltipSetItem", function(self) pcall(ItemTip, self) end)
    end
    GameTooltip:HookScript("OnTooltipSetUnit", function(self) pcall(UnitTip, self) end)
  end
  GameTooltip:HookScript("OnTooltipCleared", clear)
  ItemRefTooltip:HookScript("OnTooltipCleared", clear)
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_UNGHOST", "PLAYER_ALIVE",
  "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "LOOT_OPENED", "CHAT_MSG_SKILL", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
  if e == "ADDON_LOADED" and a1 == ADDON then
    ForeverArtisanSkinningDB = ForeverArtisanSkinningDB or {}
    db = ForeverArtisanSkinningDB
    db.version = ForeverArtisan.Version()
    db.settings = db.settings or {}
    local s = db.settings
    if s.reminder == nil then s.reminder = true end
    if s.verbose == nil then s.verbose = false end
    if s.tooltips == nil then s.tooltips = true end
    db.zones = db.zones or {}
    db.raw = db.raw or {}
    db.goals = db.goals or {}
    db.goalGot = db.goalGot or {}
    db.skillLog = db.skillLog or {}
    db.skill, db.skillMax = nil, nil
    return
  end
  if not db then return end
  if e == "PLAYER_LOGIN" then
    HookTooltips()
  elseif e == "PLAYER_ENTERING_WORLD" then
    if a1 then ns.ResetGoalProgress(true) end
    Skill()
    if C_Timer then C_Timer.After(5, function() CheckReminders(true) end) end
  elseif e == "PLAYER_UNGHOST" or e == "PLAYER_ALIVE" then
    if C_Timer then C_Timer.After(3, function() CheckReminders(true) end) end
  elseif e == "BAG_UPDATE_DELAYED" then
    if ns.OnChange then ns.OnChange() end
  elseif e == "UNIT_SPELLCAST_SENT" and a1 == "player" then
    -- (unit, target, castGUID, spellID); the corpse is usually your target
    if IsSkinSpell(a4) then
      local lvl
      local Hidden = ForeverArtisan.AnySecret -- Forever can hide unit names and levels from addons
      for _, u in ipairs({ "target", "mouseover" }) do
        local un = UnitExists(u) and UnitIsDead(u) and UnitName(u)
        if not lvl and un and not Hidden(un) and (not a2 or a2 == "" or un == a2) then
          lvl = UnitLevel(u)
          if Hidden(lvl) or (lvl and lvl < 1) then lvl = nil end
        end
      end
      local tn = UnitExists("target") and UnitName("target")
      if Hidden(tn) then tn = nil end
      pending = { mob = (a2 ~= "" and a2) or tn or nil, level = lvl, t = GetTime(), ok = false }
    end
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    if IsSkinSpell(a3) then
      pending = pending or {}
      pending.ok, pending.t = true, GetTime()
    end
  elseif (e == "UNIT_SPELLCAST_FAILED" or e == "UNIT_SPELLCAST_INTERRUPTED") and a1 == "player" then
    if IsSkinSpell(a3) and pending and not pending.ok then pending = nil end
  elseif e == "LOOT_OPENED" then
    LogSkin()
  elseif e == "CHAT_MSG_SKILL" then
    if type(a1) == "string" and (a1:find(SKINNING, 1, true) or a1:find("Skinning", 1, true)) then
      local n = tonumber(a1:match("(%d+)%.?%s*$")) or tonumber(a1:match("(%d+)"))
      if n then
        CharRec().skill = n
        session.ups = session.ups + 1
        session.startSkill = session.startSkill or (n - 1)
        db.skillLog[#db.skillLog + 1] = { s = n, c = db.sinceUp or 0, d = Today(), t = time() }
        if #db.skillLog > 500 then table.remove(db.skillLog, 1) end
        db.sinceUp = 0
        if ns.OnChange then ns.OnChange() end
      end
    end
  elseif e == "SKILL_LINES_CHANGED" then
    Skill()
  end
end)

---------------------------------------------------------------- slash
local function Range(a, b) return (a and b and a ~= b) and (a .. "-" .. b) or tostring(a or b or "?") end

local function ZoneReport(z)
  local list = {}
  for id, it in pairs(z.items) do list[#list + 1] = { id = id, it = it } end
  table.sort(list, function(a, b) return a.it.n > b.it.n end)
  say(("%s: %d skinned"):format(ns.Place(z), z.nodes))
  for name, m in pairs(z.mobs or {}) do say(("  %s%s|r (level %s): %d"):format(GRAY, name, Range(m.minL, m.maxL), m.n)) end
  for _, e in ipairs(list) do
    say(("  %s  x%d"):format(e.it.name or ItemName(e.id), e.it.n))
  end
end

SLASH_FASKIN1 = "/faskin"
SlashCmdList.FASKIN = function(msg)
  if not db then return end
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "next" then
    local bands, mobs, skill = ns.PickNext()
    if not skill then say("You haven't learned Skinning on this character.") return end
    say(("Skill %d. You can skin mobs up to level %d."):format(skill, ns.MaxLevelFor(skill)))
    for _, c in ipairs({ "orange", "yellow", "green" }) do
      local b = bands[c]
      if b then say(("  %s%s|r: levels %s"):format(ns.COLOR_CODE[c], ns.COLOR_WORD[c], Range(b[1], b[2]))) end
    end
    for i = 1, math.min(5, #mobs) do
      local m = mobs[i]
      say(("  %s%s|r (%s) in %s"):format(ns.COLOR_CODE[m.color], m.name, Range(m.minL, m.maxL), ns.Place(m)))
    end
  elseif cmd == "zone" then
    ZoneReport((ZoneRec()))
  elseif cmd == "zones" then
    local any = false
    for _, z in pairs(db.zones) do
      if z.nodes > 0 then any = true; say(("%s: %d skinned"):format(ns.Place(z), z.nodes)) end
    end
    if not any then say("Nothing logged yet. Go skin something!") end
  elseif cmd == "goal" then
    local n, name = rest:match("^(%d+)%s+(.+)$")
    if n then ns.AddGoalByName(name, tonumber(n)) else say("Usage: /fa skin goal 20 Light Leather") end
  elseif cmd == "goals" and rest:lower() == "reset" then
    ns.ResetGoalProgress()
  elseif cmd == "session" then
    local s = ns.SessionInfo()
    say(("This session: %d skinned, %d items, %d skill-ups%s"):format(s.nodes, s.items, s.ups,
      s.perHour and (", " .. s.perHour .. " items/hour") or ""))
  elseif cmd == "reminder" then
    db.settings.reminder = not db.settings.reminder
    say("Skinning Knife reminder " .. (db.settings.reminder and "on." or "off."))
  elseif cmd == "tooltips" then
    db.settings.tooltips = not db.settings.tooltips
    say("Skinning tooltip lines " .. (db.settings.tooltips and "on." or "off."))
  elseif cmd == "verbose" then
    db.settings.verbose = not db.settings.verbose
    say("Skinning messages " .. (db.settings.verbose and "on." or "off."))
  elseif cmd == "reset" and rest:lower() == "confirm" then
    ns.ResetLog()
  elseif not ns.Knows() then
    say("You haven't learned Skinning on this character. Its reminders stay quiet until you do.")
  else
    local i = ns.SkillInfo()
    say(("Skill: %s%s  ·  Skinning Knife: %s"):format(
      i.rank and (i.rank .. (i.max and ("/" .. i.max) or "")) or "?",
      (i.mod and i.mod > 0) and (" (+" .. i.mod .. ")") or "",
      ({ [true] = "yes", [false] = "missing" })[ns.HasKnife()] or "?"))
    say("Commands: /fa skin (window), next, zone, zones, goal <amount> <item>, goals reset, session, reminder, tooltips, verbose, reset confirm")
  end
end

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(ev)
