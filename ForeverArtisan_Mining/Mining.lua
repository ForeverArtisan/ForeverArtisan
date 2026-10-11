-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Mining
-- Logs every node you mine by zone, tracks skill-ups, suggests what to mine next,
-- keeps goals, adds ore tooltips, and reminds you about Find Minerals and your Mining Pick.
local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_Mining"
ns = ns or {}

local GREEN, YELLOW, RED, GRAY = "|cff40ff40", "|cffffff00", "|cffff4040", "|cff9d9d9d"
local RAW_CAP = 5000
local MINING_SKILL_LINE = 186
local MINE_SPELLS = { [2575] = true, [2576] = true, [3564] = true, [10248] = true }
local FIND_MINERALS_ID = 2580
-- the Mining Pick, plus the weapons that also work as one
local PICKS = { 2901, 756, 778, 1819, 1893, 1959, 9465 }

local db
local say = ForeverArtisan.Printer("Mining")
ns.say = say
ns.DB = function() return db end

---------------------------------------------------------------- API wrappers
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); return i and i.name
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local MINING = SpellName(2575) or "Mining"
local FIND_MINERALS = SpellName(FIND_MINERALS_ID) or "Find Minerals"

local function IsMineSpell(id)
  return (id and MINE_SPELLS[id]) or (id and SpellName(id) == MINING) or false
end

local function ItemName(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local n = f and f(id)
  if n then return n end
  local o = ns.ORES[id]
  return (o and o.name) or ns.EXTRAS[id] or ("item:" .. id)
end
ns.ItemName = ItemName

local function Today() return date("%Y-%m-%d") end
ns.Today = Today

local CountAPI = (C_Item and C_Item.GetItemCount) or GetItemCount
function ns.HasPick()
  if not CountAPI then return nil end
  for _, id in ipairs(PICKS) do
    local ok, n = pcall(CountAPI, id)
    if ok and (n or 0) > 0 then return true end
  end
  return false
end

---------------------------------------------------------------- skill
-- Saved data is shared by every character on the account, so the skill cache is per character.
local function CharRec()
  db.chars = db.chars or {}
  local key = ForeverArtisan.CharKey(db.chars)
  db.chars[key] = db.chars[key] or {}
  return db.chars[key]
end

local skillSource = "none"
local function IsMiningName(n) return n and (n == MINING or n == "Mining") end

local function SkillLive()
  if GetProfessions and GetProfessionInfo then
    local ok, p1, p2 = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ p1, p2 }) do -- pairs: a profession you lack is nil, and ipairs would stop there
        if idx then
          local name, _, rank, maxr, _, _, line, mod = GetProfessionInfo(idx)
          if rank and (line == MINING_SKILL_LINE or IsMiningName(name)) then
            skillSource = "GetProfessionInfo"; return rank, mod, maxr
          end
        end
      end
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, MINING_SKILL_LINE)
    if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
      skillSource = "C_TradeSkillUI"; return info.skillLevel, info.skillModifier, info.maxSkillLevel
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod, maxr = GetSkillLineInfo(i)
      if not header and IsMiningName(name) and rank then
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
    z = { zone = zone, sub = sub, mapID = mapID, nodes = 0, items = {}, veins = {} }
    db.zones[key] = z
  end
  z.veins = z.veins or {}
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
    if s.mins >= 1 then
      s.perHour = math.floor(session.items * 60 / s.mins + 0.5)
      s.nodesPerHour = math.floor(session.nodes * 60 / s.mins + 0.5)
    end
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

-- zones where you've mined a node type
function ns.NodeZoneText(nodeName, limit)
  local out = {}
  for _, z in pairs(db.zones) do
    local n = z.veins and z.veins[nodeName]
    if n and n > 0 then out[#out + 1] = { z = z, n = n } end
  end
  table.sort(out, function(a, b) return a.n > b.n end)
  return ZoneNames(out, limit)
end

-- zones where an item came out of a node
function ns.ZoneText(id, limit)
  local out = {}
  for _, z in pairs(db.zones) do
    local it = z.items[id]
    if it and it.hauls > 0 then out[#out + 1] = { z = z, n = it.hauls } end
  end
  table.sort(out, function(a, b) return a.n > b.n end)
  return ZoneNames(out, limit)
end

-- nodes that still give skill-ups (orange/yellow first), plus the next few to unlock
function ns.PickNext()
  local skill = EffSkill()
  local now, soon = {}, {}
  for _, n in ipairs(ns.NODES) do
    local c = ns.NodeColor(n[3], skill)
    local rec = { id = n[1], name = n[2], req = n[3], color = c, where = ns.NodeZoneText(n[2]) }
    -- nodes you haven't logged: the zones GatherMate2 knows, when it's installed
    if not rec.where and c ~= "gray" and ForeverArtisan.GatherZoneText then rec.gm = ForeverArtisan.GatherZoneText("mine", n[2], 1) end
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
local function Have(id) return (db.goalGot and db.goalGot[id]) or 0 end

local function ItemIdByName(name)
  name = name:lower()
  for id, o in pairs(ns.ORES) do if o.name and o.name:lower() == name then return id, o.name end end
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
  if not id then say("I don't know that item. Check the spelling, or mine one first.") return end
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

---------------------------------------------------------------- mining log
local pending        -- { node = name, t = GetTime(), ok = bool }
local lastLootAt = -100

-- Backup for when the cast events don't reach us (Forever hides some event values from addons):
-- loot with ore or stone in it, from a world object rather than a mob, is a node you just mined.
local STONES = { [2835] = true, [2836] = true, [2838] = true, [7912] = true, [12365] = true }
local function LootLooksMined()
  local found, node = false, nil
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local link = GetLootSlotLink(i)
    local id = link and not ForeverArtisan.IsSecret(link) and tonumber(link:match("item:(%d+)"))
    if id and (ns.ORES[id] or STONES[id]) then
      local guid
      if GetLootSourceInfo then
        local ok, g = pcall(GetLootSourceInfo, i)
        if ok and type(g) == "string" and not ForeverArtisan.IsSecret(g) then guid = g end
      end
      if guid and not guid:find("^GameObject") then return false end -- ore off a mob or from a bag
      found = true
      if ns.ORES[id] then node = node or ns.ORES[id].node end
    end
  end
  return found, node
end

local lastEntry, lastZ, lastEntryAt = nil, nil, -100

local function LogMine(chatItems)
  local now = GetTime()
  if now - lastLootAt < 1 then return end
  if not (pending and pending.ok and now - pending.t < 6) then
    if chatItems then return end
    local mined, node = LootLooksMined()
    if not mined then return end
    pending = { node = node, ok = true, t = now }
  end
  lastLootAt = now
  local zone, sub, mapID, x, y = Where()
  local z = ZoneRec(zone, sub, mapID)
  local rank = Skill()
  local node = ns.NormalizeNode(pending.node)
  local entry = { d = Today(), t = time(), zone = zone, sub = sub, mapID = mapID, x = x, y = y,
                  node = pending.node, skill = rank, items = {} }
  pending = nil
  local got = {}
  local list = chatItems
  if not list then
    list = {}
    for i = 1, (GetNumLootItems() or 0) do
      local link = GetLootSlotLink(i)
      local id = link and tonumber(link:match("item:(%d+)"))
      if id then
        local _, name, qty, _, quality = GetLootSlotInfo(i)
        list[#list + 1] = { id = id, name = name, qty = qty, quality = quality, link = link }
      end
    end
  end
  for _, li in ipairs(list) do
    local id, name, qty, quality, link = li.id, li.name, li.qty or 1, li.quality, li.link
    do
      entry.items[#entry.items + 1] = { id = id, n = qty }
      local it = z.items[id]
      if not it then it = { name = name, q = quality, n = 0, hauls = 0 }; z.items[id] = it end
      it.n = it.n + qty
      it.hauls = it.hauls + 1
      it.name = name or it.name
      it.lastSeen = Today()
      if rank then it.minSkill = math.min(it.minSkill or rank, rank) end
      db.goalGot[id] = (db.goalGot[id] or 0) + qty
      session.items = session.items + qty
      got[#got + 1] = (qty > 1 and (qty .. "x ") or "") .. (link or name or ItemName(id))
    end
  end
  if #entry.items == 0 then return end
  z.nodes = z.nodes + 1
  if node then z.veins[node] = (z.veins[node] or 0) + 1 end
  z.lastSeen = Today()
  db.raw[#db.raw + 1] = entry
  if chatItems then lastEntry, lastZ, lastEntryAt = entry, z, now else lastEntry = nil end
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
  session.last = got[1]
  if db.settings.verbose then say("Mined " .. table.concat(got, ", ")) end
  CheckGoals()
  if ns.OnChange then ns.OnChange() end
end

function ns.ResetLog()
  db.zones, db.raw = {}, {}
  say("Mining log cleared.")
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- Find Minerals + pick reminders
local function KnowsFind()
  if IsPlayerSpell then return IsPlayerSpell(FIND_MINERALS_ID) end
  if IsSpellKnown then return IsSpellKnown(FIND_MINERALS_ID) end
  return false
end

-- true = on, false = off, nil = unknown / not learned
function ns.FindOn()
  if not KnowsFind() then return nil end
  if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
    for i = 1, (C_Minimap.GetNumTrackingTypes() or 0) do
      local a, _, c = C_Minimap.GetTrackingInfo(i)
      if type(a) == "table" then
        if a.spellID == FIND_MINERALS_ID or a.name == FIND_MINERALS then return a.active and true or false end
      elseif a == FIND_MINERALS then
        return c and true or false
      end
    end
  end
  if GetNumTrackingTypes and GetTrackingInfo then
    for i = 1, (GetNumTrackingTypes() or 0) do
      local name, _, active = GetTrackingInfo(i)
      if name == FIND_MINERALS then return active and true or false end
    end
  end
  if GetTrackingTexture then
    local tex = GetTrackingTexture()
    if not tex then return false end
    return tex == 136025 or (type(tex) == "string" and tex:lower():find("earthquake") ~= nil)
  end
end

local lastWarn, lastPickWarn = 0, 0
local function CheckReminders(force)
  if not db.settings.reminder then return end
  if not ns.Knows() then return end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
  if ns.FindOn() == false and (force or GetTime() - lastWarn > 60) then
    lastWarn = GetTime()
    say(YELLOW .. "Find Minerals is off.|r Turn it on from the tracking button on your minimap.")
  end
  if ns.HasPick() == false and (force or GetTime() - lastPickWarn > 300) then
    lastPickWarn = GetTime()
    say(YELLOW .. "No Mining Pick in your bags.|r You'll need one to mine.")
  end
end
ns.CheckReminders = CheckReminders

---------------------------------------------------------------- tooltips
local function OreLines(tt, id)
  local o = ns.ORES[id]
  local extra = ns.EXTRAS[id]
  if not o and not extra then return end
  tt:AddLine(" ")
  if o then
    local skill = EffSkill()
    local c = ns.NodeColor(o.req, skill)
    ForeverArtisan.TipLine(tt, ("|cffd4a94eMining %d|r  %s%s"):format(o.req, GRAY .. o.node .. "|r",
      skill and ("  " .. ns.COLOR_CODE[c] .. ns.COLOR_WORD[c] .. "|r") or ""))
  else
    ForeverArtisan.TipLine(tt, "|cffd4a94eMining: comes from ore nodes|r")
  end
  local where = ns.ZoneText(id)
  tt:AddLine(where and ("Mined in: " .. where) or (GRAY .. "Not in your mining log yet.|r"), 0.9, 0.9, 0.9, true)
end

local function ItemTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.faMineDone then return end
  local _, link = tt:GetItem()
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return end
  tt.faMineDone = true
  OreLines(tt, id)
  tt:Show()
end

-- mouse over a node out in the world: show your color for it
local function ObjectTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.faMineDone then return end
  local first = _G[tt:GetName() .. "TextLeft1"]
  local name = first and first:GetText()
  local base = name and ns.NormalizeNode(name)
  local n = base and ns.nodeByName[base:lower()]
  if not n then return end
  tt.faMineDone = true
  local skill = EffSkill()
  local c = ns.NodeColor(n.req, skill)
  if skill then ForeverArtisan.TipLine(tt, ns.COLOR_CODE[c] .. ns.COLOR_WORD[c] .. "|r  " .. GRAY .. "(you: " .. skill .. ")|r") end
  tt:Show()
end

local function HookTooltips()
  local function clear(self) self.faMineDone = nil end
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
  "UNIT_SPELLCAST_INTERRUPTED", "LOOT_OPENED", "CHAT_MSG_LOOT", "CHAT_MSG_SKILL", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

-- auto loot on Forever can skip the loot window: count the node from the "You receive loot" line
-- instead, right after a successful cast. More lines in the next moment are the same node (ore + stone).
local function OnChatLoot(msg, guid)
  local li = ForeverArtisan.ParseSelfLoot(msg, guid)
  if not li then return end
  local now = GetTime()
  if pending and pending.ok and now - pending.t < 6 then
    LogMine({ li })
  elseif lastEntry and now - lastEntryAt < 2 then
    lastEntryAt = now
    lastEntry.items[#lastEntry.items + 1] = { id = li.id, n = li.qty }
    local it = lastZ.items[li.id]
    if not it then it = { name = li.name, n = 0, hauls = 0 }; lastZ.items[li.id] = it end
    it.n, it.hauls, it.name, it.lastSeen = it.n + li.qty, it.hauls + 1, li.name or it.name, Today()
    db.goalGot[li.id] = (db.goalGot[li.id] or 0) + li.qty
    session.items = session.items + li.qty
    CheckGoals()
    if ns.OnChange then ns.OnChange() end
  end
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4, ...)
  if e == "ADDON_LOADED" and a1 == ADDON then
    ForeverArtisanMiningDB = ForeverArtisanMiningDB or {}
    db = ForeverArtisanMiningDB
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
  elseif e == "MINIMAP_UPDATE_TRACKING" or e == "BAG_UPDATE_DELAYED" then
    if ns.OnChange then ns.OnChange() end
  elseif e == "UNIT_SPELLCAST_SENT" and a1 == "player" then
    if IsMineSpell(a4) then pending = { node = a2, t = GetTime(), ok = false } end
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    if IsMineSpell(a3) then
      pending = pending or {}
      pending.ok, pending.t = true, GetTime()
    end
  elseif (e == "UNIT_SPELLCAST_FAILED" or e == "UNIT_SPELLCAST_INTERRUPTED") and a1 == "player" then
    if IsMineSpell(a3) and pending and not pending.ok then pending = nil end
  elseif e == "LOOT_OPENED" then
    LogMine()
  elseif e == "CHAT_MSG_LOOT" then
    OnChatLoot(a1, (select(8, ...)))
  elseif e == "CHAT_MSG_SKILL" then
    if type(a1) == "string" and (a1:find(MINING, 1, true) or a1:find("Mining", 1, true)) then
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
  say(("%s: %d node%s"):format(ns.Place(z), z.nodes, z.nodes == 1 and "" or "s"))
  for vein, n in pairs(z.veins or {}) do say(("  %s%s|r: %d mined"):format(GRAY, vein, n)) end
  for _, e in ipairs(list) do
    say(("  %s  x%d%s"):format(e.it.name or ItemName(e.id), e.it.n,
      e.it.minSkill and (GRAY .. "  (first at skill " .. e.it.minSkill .. ")|r") or ""))
  end
end

---------------------------------------------------------------- /fa mine debug
-- Prints what the game hands us around a mined node, straight from the events (not through the
-- hidden-value guard), so we can see which values Forever hides. Off by default; nothing is saved.
local dbgFrame
local function Show(v)
  if v == nil then return "nil" end
  if issecretvalue and issecretvalue(v) then return "HIDDEN" end
  return tostring(v)
end
local function DebugEvent(_, e, ...)
  local ok, err = pcall(function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = Show((select(i, ...))) end
    say("|cff9d9d9d[debug]|r " .. e .. " (" .. table.concat(parts, ", ") .. ")")
    if e == "LOOT_OPENED" then
      local n = GetNumLootItems and GetNumLootItems() or 0
      say("|cff9d9d9d[debug]|r loot slots: " .. Show(n) .. "   hidden-value skips so far: " .. tostring(ForeverArtisan.secretSkips or 0))
      for i = 1, (type(n) == "number" and n or 0) do
        local link = GetLootSlotLink(i)
        local g = GetLootSourceInfo and select(2, pcall(GetLootSourceInfo, i))
        local _, name, qty = GetLootSlotInfo(i)
        say(("|cff9d9d9d[debug]|r   slot %d: link=%s name=%s qty=%s source=%s"):format(i,
          (link and not (issecretvalue and issecretvalue(link))) and link:gsub("|", "||"):sub(1, 60) or Show(link),
          Show(name), Show(qty), Show(g)))
      end
    end
  end, ...)
  if not ok then say("|cff9d9d9d[debug]|r error: " .. Show(err)) end
end
function ns.ToggleDebug()
  if not dbgFrame then
    dbgFrame = CreateFrame("Frame")
    dbgFrame:SetScript("OnEvent", DebugEvent)
  end
  if dbgFrame.on then
    dbgFrame:UnregisterAllEvents(); dbgFrame.on = nil
    say("debug off.")
  else
    for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "LOOT_OPENED", "CHAT_MSG_SKILL", "CHAT_MSG_LOOT" }) do
      pcall(dbgFrame.RegisterEvent, dbgFrame, e)
    end
    dbgFrame.on = true
    say("debug on. Mine one node, then send a screenshot of chat. /fa mine debug again to turn it off.")
  end
end

SLASH_FAMINING1 = "/famining"
SlashCmdList.FAMINING = function(msg)
  if not db then return end
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "debug" then
    ns.ToggleDebug()
  elseif cmd == "next" then
    local now, soon, skill = ns.PickNext()
    if not skill then say("You haven't learned Mining on this character.") return end
    say(("Skill %d. Nodes that still give skill-ups:"):format(skill))
    for i = 1, math.min(6, #now) do
      local n = now[i]
      say(("  %s%s|r (%d)  %s"):format(ns.COLOR_CODE[n.color], n.name, n.req, n.where
        or (n.gm and (n.gm .. GRAY .. " (GatherMate2)|r")) or (GRAY .. "not logged yet|r")))
    end
    for _, n in ipairs(soon) do say(("  %sunlocks at %d:|r %s"):format(GRAY, n.req, n.name)) end
  elseif cmd == "zone" then
    ZoneReport((ZoneRec()))
  elseif cmd == "zones" then
    local any = false
    for _, z in pairs(db.zones) do
      if z.nodes > 0 then any = true; say(("%s: %d nodes"):format(ns.Place(z), z.nodes)) end
    end
    if not any then say("Nothing logged yet. Go mine something!") end
  elseif cmd == "goal" then
    local n, name = rest:match("^(%d+)%s+(.+)$")
    if n then ns.AddGoalByName(name, tonumber(n)) else say("Usage: /fa mine goal 20 Copper Ore") end
  elseif cmd == "goals" and rest:lower() == "reset" then
    ns.ResetGoalProgress()
  elseif cmd == "session" then
    local s = ns.SessionInfo()
    say(("This session: %d nodes, %d items, %d skill-ups%s"):format(s.nodes, s.items, s.ups,
      s.perHour and (", " .. s.perHour .. " items/hour") or ""))
  elseif cmd == "reminder" then
    db.settings.reminder = not db.settings.reminder
    say("Find Minerals and Mining Pick reminders " .. (db.settings.reminder and "on." or "off."))
  elseif cmd == "tooltips" then
    db.settings.tooltips = not db.settings.tooltips
    say("Ore tooltip lines " .. (db.settings.tooltips and "on." or "off."))
  elseif cmd == "verbose" then
    db.settings.verbose = not db.settings.verbose
    say("Mining messages " .. (db.settings.verbose and "on." or "off."))
  elseif cmd == "reset" and rest:lower() == "confirm" then
    ns.ResetLog()
  elseif not ns.Knows() then
    say("You haven't learned Mining on this character. Its reminders stay quiet until you do.")
  else
    local i = ns.SkillInfo()
    say(("Skill: %s%s  ·  Find Minerals: %s  ·  Mining Pick: %s"):format(
      i.rank and (i.rank .. (i.max and ("/" .. i.max) or "")) or "?",
      (i.mod and i.mod > 0) and (" (+" .. i.mod .. ")") or "",
      ({ [true] = "on", [false] = "off" })[ns.FindOn()] or "n/a",
      ({ [true] = "yes", [false] = "missing" })[ns.HasPick()] or "?"))
    say("Commands: /fa mine (window), next, zone, zones, goal <amount> <item>, goals reset, session, reminder, tooltips, verbose, reset confirm")
  end
end

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(ev)
