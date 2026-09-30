-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Herbalism
-- Logs every herb you pick by zone, tracks skill-ups, suggests what to pick next,
-- keeps gathering goals, adds herb tooltips and reminds you when Find Herbs is off.
local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_Herbalism"
ns = ns or {}

local GREEN, YELLOW, RED, GRAY = "|cff40ff40", "|cffffff00", "|cffff4040", "|cff9d9d9d"
local RAW_CAP = 5000
local HERB_SKILL_LINE = 182
local HERB_SPELLS = { [2366] = true, [2368] = true, [3570] = true, [11993] = true }
local FIND_HERBS_ID = 2383

local db
local say = ForeverArtisan.Printer("Herbalism")
ns.say = say
ns.DB = function() return db end

---------------------------------------------------------------- API wrappers
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); return i and i.name
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local HERB_GATHERING = SpellName(2366) or "Herb Gathering"
local HERBALISM = "Herbalism"
local FIND_HERBS = SpellName(FIND_HERBS_ID) or "Find Herbs"

local function IsHerbSpell(id)
  return (id and HERB_SPELLS[id]) or (id and SpellName(id) == HERB_GATHERING) or false
end

local function ItemName(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local n = f and f(id)
  if n then return n end
  local h = ns.herbById[id]
  return (h and h.name) or ns.BONUS[id] or ("item:" .. id)
end
ns.ItemName = ItemName

local function Today() return date("%Y-%m-%d") end
ns.Today = Today

---------------------------------------------------------------- skill
-- Saved data is shared by every character on the account, so the skill cache is per character.
local function CharRec()
  local key = (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
  db.chars = db.chars or {}
  db.chars[key] = db.chars[key] or {}
  return db.chars[key]
end

local skillSource = "none"
local function IsHerbName(n) return n and (n == HERBALISM or n == "Herbalism") end

local function SkillLive()
  if GetProfessions and GetProfessionInfo then
    local ok, p1, p2 = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ p1, p2 }) do -- pairs: a profession you lack is nil, and ipairs would stop there
        if idx then
          local name, _, rank, maxr, _, _, line, mod = GetProfessionInfo(idx)
          if rank and (line == HERB_SKILL_LINE or IsHerbName(name)) then
            skillSource = "GetProfessionInfo"; return rank, mod, maxr
          end
        end
      end
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, HERB_SKILL_LINE)
    if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
      skillSource = "C_TradeSkillUI"; return info.skillLevel, info.skillModifier, info.maxSkillLevel
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod, maxr = GetSkillLineInfo(i)
      if not header and IsHerbName(name) and rank then
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
ns.SkillSource = function() return skillSource end

-- effective skill for colors (racial/gear bonuses count)
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
ns.Where = Where

local function ZoneRec(zone, sub, mapID)
  if not zone then zone, sub, mapID = Where() end
  local key = zone .. " / " .. sub
  local z = db.zones[key]
  if not z then
    z = { zone = zone, sub = sub, mapID = mapID, nodes = 0, items = {} }
    db.zones[key] = z
  end
  return z, key
end
ns.ZoneRec = ZoneRec

---------------------------------------------------------------- session
local session = { nodes = 0, herbs = 0, ups = 0, start = nil, startSkill = nil, last = nil }
ns.session = session

function ns.SessionInfo()
  local s = { nodes = session.nodes, herbs = session.herbs, ups = session.ups, last = session.last }
  if session.start then
    s.mins = (GetTime() - session.start) / 60
    if s.mins >= 1 then
      s.perHour = math.floor(session.herbs * 60 / s.mins + 0.5)
      s.nodesPerHour = math.floor(session.nodes * 60 / s.mins + 0.5)
    end
  end
  local r = Skill()
  if r and session.startSkill then s.gained = r - session.startSkill end
  return s
end

function ns.SkillInfo()
  local rank, mod, max = Skill()
  local info = { rank = rank, mod = mod, max = max, source = skillSource }
  if not rank then return info end
  session.startSkill = session.startSkill or rank
  -- nodes per skill point: this session first, else recent history
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

---------------------------------------------------------------- pick next / guide
-- zones where you've logged a herb, best first
function ns.ZonesFor(id)
  local out = {}
  for _, z in pairs(db.zones) do
    local it = z.items[id]
    if it and it.hauls > 0 then out[#out + 1] = { z = z, n = it.hauls } end
  end
  table.sort(out, function(a, b) return a.n > b.n end)
  return out
end

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

function ns.ZoneText(id, limit)
  return ZoneNames(ns.ZonesFor(id), limit)
end

-- herbs that still give skill-ups (orange/yellow first), plus the next few to unlock
function ns.PickNext()
  local skill = EffSkill()
  local now, soon = {}, {}
  for _, h in ipairs(ns.HERBS) do
    local c = ns.HerbColor(h[3], skill)
    local rec = { id = h[1], name = h[2], req = h[3], color = c, where = ns.ZoneText(h[1]) }
    if c == "orange" or c == "yellow" or c == "green" then
      now[#now + 1] = rec
    elseif c == "red" and #soon < 3 then
      soon[#soon + 1] = rec
    end
  end
  local rankOf = { orange = 1, yellow = 2, green = 3 }
  table.sort(now, function(a, b)
    if rankOf[a.color] ~= rankOf[b.color] then return rankOf[a.color] < rankOf[b.color] end
    return a.req > b.req
  end)
  return now, soon, skill
end

---------------------------------------------------------------- goals
-- progress counts herbs picked since you logged in (kept through /reload)
local function Have(id) return (db.goalGot and db.goalGot[id]) or 0 end

local function ItemIdByName(name)
  name = name:lower()
  local h = ns.herbByName[name]
  if h then return h.id, h.name end
  for id, n in pairs(ns.BONUS) do if n:lower() == name then return id, n end end
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
  if not id then say("I don't know that herb. Check the spelling, or pick one first.") return end
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

---------------------------------------------------------------- gather log
local pending        -- { node = name, t = GetTime(), ok = bool }
local lastLootAt = -100

local function LogGather()
  local now = GetTime()
  if now - lastLootAt < 1 then return end
  if not (pending and pending.ok and now - pending.t < 6) then return end
  lastLootAt = now
  local zone, sub, mapID, x, y = Where()
  local z = ZoneRec(zone, sub, mapID)
  local rank = Skill()
  local entry = { d = Today(), t = time(), zone = zone, sub = sub, mapID = mapID, x = x, y = y,
                  node = pending.node, skill = rank, items = {} }
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
      db.goalGot[id] = (db.goalGot[id] or 0) + qty
      session.herbs = session.herbs + qty
      got[#got + 1] = (qty > 1 and (qty .. "x ") or "") .. (link or name or ItemName(id))
    end
  end
  if #entry.items == 0 then return end
  z.nodes = z.nodes + 1
  z.lastSeen = Today()
  db.raw[#db.raw + 1] = entry
  if #db.raw > RAW_CAP then table.remove(db.raw, 1) end
  db.sinceUp = (db.sinceUp or 0) + 1
  session.nodes = session.nodes + 1
  session.start = session.start or GetTime()
  session.startSkill = session.startSkill or rank
  session.last = got[1]
  if db.settings.verbose then say("Picked " .. table.concat(got, ", ")) end
  CheckGoals()
  if ns.OnChange then ns.OnChange() end
end

function ns.ResetLog()
  db.zones, db.raw = {}, {}
  say("Gather log cleared.")
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- Find Herbs reminder
local function KnowsFindHerbs()
  if IsPlayerSpell then return IsPlayerSpell(FIND_HERBS_ID) end
  if IsSpellKnown then return IsSpellKnown(FIND_HERBS_ID) end
  return false
end

-- true = on, false = off, nil = unknown / not learned
function ns.FindHerbsOn()
  if not KnowsFindHerbs() then return nil end
  if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
    for i = 1, (C_Minimap.GetNumTrackingTypes() or 0) do
      local a, _, c = C_Minimap.GetTrackingInfo(i)
      if type(a) == "table" then
        if a.spellID == FIND_HERBS_ID or a.name == FIND_HERBS then return a.active and true or false end
      elseif a == FIND_HERBS then
        return c and true or false
      end
    end
  end
  if GetNumTrackingTypes and GetTrackingInfo then
    for i = 1, (GetNumTrackingTypes() or 0) do
      local name, _, active = GetTrackingInfo(i)
      if name == FIND_HERBS then return active and true or false end
    end
  end
  if GetTrackingTexture then
    local tex = GetTrackingTexture()
    if not tex then return false end
    return tex == 133939 or (type(tex) == "string" and tex:lower():find("flower_02") ~= nil)
  end
end

local lastWarn = 0
local function CheckFindHerbs(force)
  if not db.settings.reminder then return end
  if not ns.Knows() then return end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
  if ns.FindHerbsOn() == false and (force or GetTime() - lastWarn > 60) then
    lastWarn = GetTime()
    say(YELLOW .. "Find Herbs is off.|r Turn it on from the tracking button on your minimap.")
  end
end
ns.CheckFindHerbs = CheckFindHerbs

---------------------------------------------------------------- tooltips
local function HerbLines(tt, id)
  local h = ns.herbById[id]
  local bonus = ns.BONUS[id]
  if not h and not bonus then return end
  tt:AddLine(" ")
  if h then
    local skill = EffSkill()
    local c = ns.HerbColor(h.req, skill)
    tt:AddLine(("|cffd4a94eHerbalism %d|r%s"):format(h.req,
      skill and ("  " .. ns.COLOR_CODE[c] .. ns.COLOR_WORD[c] .. "|r") or ""))
  else
    tt:AddLine("|cffd4a94eHerbalism bonus herb|r")
  end
  local where = ns.ZoneText(id)
  tt:AddLine(where and ("Picked in: " .. where) or (GRAY .. "Not in your gather log yet.|r"), 0.9, 0.9, 0.9, true)
end

local function ItemTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.faHerbDone then return end
  local _, link = tt:GetItem()
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return end
  tt.faHerbDone = true
  HerbLines(tt, id)
  tt:Show()
end

-- mouse over a herb out in the world: show your color for it
local function ObjectTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.faHerbDone then return end
  local first = _G[tt:GetName() .. "TextLeft1"]
  local name = first and first:GetText()
  local h = name and ns.herbByName[name:lower()]
  if not h then return end
  tt.faHerbDone = true
  local skill = EffSkill()
  local c = ns.HerbColor(h.req, skill)
  if skill then tt:AddLine(ns.COLOR_CODE[c] .. ns.COLOR_WORD[c] .. "|r  " .. GRAY .. "(you: " .. skill .. ")|r") end
  tt:Show()
end

local function HookTooltips()
  local function clear(self) self.faHerbDone = nil end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
      if tt == GameTooltip or tt == ItemRefTooltip then pcall(ItemTip, tt) end
    end)
    if Enum.TooltipDataType.Object then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tt)
        if tt == GameTooltip then pcall(ObjectTip, tt) end
      end)
    end
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      tt:HookScript("OnTooltipSetItem", function(self) pcall(ItemTip, self) end)
    end
  end
  GameTooltip:HookScript("OnShow", function(self)
    if not self:GetItem() then pcall(ObjectTip, self) end
  end)
  GameTooltip:HookScript("OnTooltipCleared", clear)
  ItemRefTooltip:HookScript("OnTooltipCleared", clear)
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_UNGHOST", "PLAYER_ALIVE",
  "MINIMAP_UPDATE_TRACKING", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "LOOT_OPENED", "CHAT_MSG_SKILL", "SKILL_LINES_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
  if e == "ADDON_LOADED" and a1 == ADDON then
    ForeverArtisan.Migrate("ForeverArtisanHerbalismDB", "ForeverArtisanHerbDB")
    ForeverArtisanHerbalismDB = ForeverArtisanHerbalismDB or {}
    db = ForeverArtisanHerbalismDB
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
    -- a real login starts goal progress over; /reload and zoning keep it
    if a1 then ns.ResetGoalProgress(true) end
    Skill()
    if C_Timer then C_Timer.After(5, function() CheckFindHerbs(true) end) end
  elseif e == "PLAYER_UNGHOST" or e == "PLAYER_ALIVE" then
    if C_Timer then C_Timer.After(3, function() CheckFindHerbs(true) end) end
  elseif e == "MINIMAP_UPDATE_TRACKING" then
    if ns.OnChange then ns.OnChange() end
  elseif e == "UNIT_SPELLCAST_SENT" and a1 == "player" then
    -- (unit, target, castGUID, spellID)
    if IsHerbSpell(a4) then pending = { node = a2, t = GetTime(), ok = false } end
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    -- (unit, castGUID, spellID)
    if IsHerbSpell(a3) then
      pending = pending or {}
      pending.ok, pending.t = true, GetTime()
    end
  elseif (e == "UNIT_SPELLCAST_FAILED" or e == "UNIT_SPELLCAST_INTERRUPTED") and a1 == "player" then
    if IsHerbSpell(a3) and pending and not pending.ok then pending = nil end
  elseif e == "LOOT_OPENED" then
    LogGather()
  elseif e == "CHAT_MSG_SKILL" then
    if type(a1) == "string" and (a1:find(HERBALISM, 1, true) or a1:find("Herbalism", 1, true)) then
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
local function ZoneReport(z)
  local list = {}
  for id, it in pairs(z.items) do list[#list + 1] = { id = id, it = it } end
  table.sort(list, function(a, b) return a.it.n > b.it.n end)
  say(("%s: %d nodes"):format(ns.Place(z), z.nodes))
  for _, e in ipairs(list) do
    say(("  %s  x%d  (%d nodes%s)"):format(e.it.name or ItemName(e.id), e.it.n, e.it.hauls,
      e.it.minSkill and (", first at skill " .. e.it.minSkill) or ""))
  end
end

SLASH_FAHERB1 = "/faherb"
SlashCmdList.FAHERB = function(msg)
  if not db then return end
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "next" then
    local now, soon, skill = ns.PickNext()
    if not skill then say("You haven't learned Herbalism on this character.") return end
    say(("Skill %d. Herbs that still give skill-ups:"):format(skill))
    for i = 1, math.min(6, #now) do
      local h = now[i]
      say(("  %s%s|r (%d)  %s"):format(ns.COLOR_CODE[h.color], h.name, h.req, h.where or (GRAY .. "not logged yet|r")))
    end
    for _, h in ipairs(soon) do say(("  %sunlocks at %d:|r %s"):format(GRAY, h.req, h.name)) end
  elseif cmd == "zone" then
    ZoneReport((ZoneRec()))
  elseif cmd == "zones" then
    local any = false
    for _, z in pairs(db.zones) do
      if z.nodes > 0 then any = true; say(("%s: %d nodes"):format(ns.Place(z), z.nodes)) end
    end
    if not any then say("Nothing logged yet. Go pick something!") end
  elseif cmd == "goal" then
    local n, name = rest:match("^(%d+)%s+(.+)$")
    if n then ns.AddGoalByName(name, tonumber(n)) else say("Usage: /fa herb goal 20 Peacebloom") end
  elseif cmd == "goals" and rest:lower() == "reset" then
    ns.ResetGoalProgress()
  elseif cmd == "session" then
    local s = ns.SessionInfo()
    say(("This session: %d nodes, %d herbs, %d skill-ups%s"):format(s.nodes, s.herbs, s.ups,
      s.perHour and (", " .. s.perHour .. " herbs/hour") or ""))
  elseif cmd == "reminder" then
    db.settings.reminder = not db.settings.reminder
    say("Find Herbs reminder " .. (db.settings.reminder and "on." or "off."))
  elseif cmd == "tooltips" then
    db.settings.tooltips = not db.settings.tooltips
    say("Herb tooltip lines " .. (db.settings.tooltips and "on." or "off."))
  elseif cmd == "verbose" then
    db.settings.verbose = not db.settings.verbose
    say("Pick messages " .. (db.settings.verbose and "on." or "off."))
  elseif cmd == "reset" and rest:lower() == "confirm" then
    ns.ResetLog()
  elseif not ns.Knows() then
    say("You haven't learned Herbalism on this character. Its reminders stay quiet until you do.")
  else
    local i = ns.SkillInfo()
    say(("Skill: %s%s  ·  Find Herbs: %s"):format(i.rank and (i.rank .. (i.max and ("/" .. i.max) or "")) or "?",
      (i.mod and i.mod > 0) and (" (+" .. i.mod .. ")") or "",
      ({ [true] = "on", [false] = "off" })[ns.FindHerbsOn()] or "n/a"))
    say("Commands: /fa herb (window), next, zone, zones, goal <amount> <herb>, goals reset, session, reminder, tooltips, verbose, reset confirm")
  end
end
