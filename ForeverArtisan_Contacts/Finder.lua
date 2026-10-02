-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Trade Contacts - finder. Turns your saved contacts into answers:
-- "Sold by" lines on item tooltips, search, and waypoints. Only NPCs you've met.
local ADDON, ns = ...
local FA = ForeverArtisan
local GOLD, GREY = FA.GOLD, FA.GRAY
local PREFIX = FA.Prefix("Trade Contacts")
local MAX_TIP_LINES = 3

local npcs, byId, byName = {}, {}, {}
local dirty = true

local function DB() return ForeverArtisanContactsDB end
local function Settings() return (DB() and DB().settings) or {} end

---------------------------------------------------------------- saved contacts -> lookup tables

-- "Requires Tailoring (125)" -> "Tailoring (125)"
local function skillReq(requires)
  for _, r in ipairs(requires or {}) do
    local rest = r:match("^Requires (.+)$")
    if rest and not rest:find("^Level") and rest:find("%(%d+%)") then return rest end
  end
end

-- How many game updates since this contact was last seen: 0 = current, 1 = before the last
-- update (shown, marked), 2+ = not seen through two updates (hidden from tooltips and search).
local function UpdatesSince(e)
  local builds = DB() and DB().builds
  if not builds or #builds == 0 or not e.build then return 0 end
  for i = #builds, 1, -1 do
    if builds[i] == e.build then return #builds - i end
  end
  return #builds -- older than anything we remember
end
ns.HIDE_AFTER = 2

local STATUS_WORD = { available = true, unavailable = true, used = true }

local function Rebuild()
  wipe(npcs); wipe(byId); wipe(byName)
  local entries = DB() and DB().entries or {}
  -- A crafting NPC you talked to whose trainer or shop window never opened (a trainer who
  -- won't train you yet only shows chat) is still a contact: "visited, no list yet".
  local full = {}
  for _, e in pairs(entries) do
    if e.kind == "vendor" or e.kind == "trainer" then
      if e.npcId then full[e.npcId] = true end
      if e.name then full[e.name] = true end
    end
  end
  for key, e in pairs(entries) do
    local chatOnly = e.kind == "service" and e.name and e.title and ns.IsRelevant and ns.IsRelevant(e.title)
      and not full[e.npcId or false] and not full[e.name]
    if ((e.kind == "vendor" or e.kind == "trainer") and e.name) or chatOnly then
      local npc = { id = e.npcId, n = e.name, t = e.title, k = e.kind, z = e.zone, s = e.subzone, m = e.mapID, x = e.x, y = e.y,
                    seen = e.seenAt or e.lastSeen, visited = e.lastSeen, age = UpdatesSince(e), key = key, items = {} }
      if e.kind == "vendor" then
        for _, it in ipairs(e.items or {}) do
          if it.name then
            npc.items[#npc.items + 1] = { n = it.name, id = it.itemId, p = it.priceCopper, lv = it.levelReq,
              sk = skillReq(it.requires), lim = it.limited, stack = it.stack }
          end
        end
      else
        for _, sk in ipairs(e.skills or {}) do
          if sk.name then
            -- older saves hold the status in rank ("Camp Tent (unavailable)"); keep real ranks only
            local rank = sk.rank and not STATUS_WORD[sk.rank:lower()] and sk.rank or nil
            npc.items[#npc.items + 1] = { n = sk.name .. (rank and (" (" .. rank .. ")") or ""), p = sk.priceCopper,
              sk = sk.skillReq, lv = sk.levelReq, train = true }
          end
        end
      end
      npcs[#npcs + 1] = npc
      -- contacts not seen through two game updates stay in the list but stop answering questions
      if npc.age < ns.HIDE_AFTER then
      for _, it in ipairs(npc.items) do
        local hit = { npc = npc, item = it }
        if it.id then byId[it.id] = byId[it.id] or {}; table.insert(byId[it.id], hit) end
        local key = it.n:lower()
        byName[key] = byName[key] or {}; table.insert(byName[key], hit)
      end
      end
    end
  end
  table.sort(npcs, function(a, b) return (a.n or "") < (b.n or "") end)
  dirty = false
end

local function Ensure() if dirty then Rebuild() end end

function ns.OnContactsChanged()
  dirty = true
  if ns.OnChange then ns.OnChange() end
end

function ns.Contacts() Ensure(); return npcs end

---------------------------------------------------------------- helpers

local function money(it)
  if it.p and it.p > 0 then
    if GetCoinTextureString then return GetCoinTextureString(it.p) end
    local g, s, c = math.floor(it.p / 10000), math.floor(it.p / 100) % 100, it.p % 100
    return (g > 0 and g .. "g " or "") .. (s > 0 and s .. "s " or "") .. (c > 0 and c .. "c" or "")
  end
  if it.p == 0 then return "free" end
  return "?"
end
ns.Money = money

local function where(npc) return npc.s or npc.z or "?" end
ns.Where = where

local function playerPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local m = C_Map.GetBestMapForUnit("player")
  if not m then return end
  local pos = C_Map.GetPlayerMapPosition(m, "player")
  if not pos then return m end
  local x, y = pos:GetXY()
  return m, x * 100, y * 100
end

-- Map position (0-100) -> continent and world position in yards, so NPCs in different
-- zones can be compared. Nil when the client can't convert (then only same-map distance works).
local function worldPos(m, x, y)
  if not (m and x and y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x / 100, y / 100))
  if not ok or not cont or not pos then return end
  local wx, wy = pos.x, pos.y
  if pos.GetXY then wx, wy = pos:GetXY() end
  if wx and wy then return cont, wx, wy end
end

-- Nearest first: across zones on your continent when the game can convert map positions,
-- otherwise on your current map. Then other continents, by town. NPCs within about the same
-- distance (same 50-yard band) put the ones you've met ahead of seen-only ones.
local function sortHits(hits)
  local m, px, py = playerPos()
  local pc, pwx, pwy = worldPos(m, px, py)
  for _, h in ipairs(hits) do
    local npc = h.npc
    h.dist = 1e9
    if pc and npc.x then
      if npc.wc == nil and npc.m then npc.wc, npc.wx, npc.wy = worldPos(npc.m, npc.x, npc.y); npc.wc = npc.wc or false end
      if npc.wc and npc.wc == pc then
        local dx, dy = npc.wx - pwx, npc.wy - pwy
        h.dist = math.sqrt(dx * dx + dy * dy)
      end
    elseif m and px and npc.m == m and npc.x then
      local dx, dy = npc.x - px, npc.y - py
      h.dist = math.sqrt(dx * dx + dy * dy) * 10 -- map percent, roughly yards-scaled for the band below
    end
    h.band = math.floor(h.dist / 50)
  end
  table.sort(hits, function(a, b)
    if a.band ~= b.band then return a.band < b.band end
    if (a.seen or false) ~= (b.seen or false) then return not a.seen end
    if (a.npc.age or 0) ~= (b.npc.age or 0) then return (a.npc.age or 0) < (b.npc.age or 0) end
    if a.dist ~= b.dist then return a.dist < b.dist end
    if where(a.npc) ~= where(b.npc) then return where(a.npc) < where(b.npc) end
    local an, bn = a.item and a.item.n or "", b.item and b.item.n or ""
    if an ~= bn then return an < bn end
    return a.npc.n < b.npc.n
  end)
  return hits
end

function ns.SetWaypoint(npc)
  if not (npc.m and npc.x and npc.y) then
    print(PREFIX .. "no coordinates saved for " .. npc.n .. ".")
    return
  end
  local title = npc.n .. " (" .. where(npc) .. ")"
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(npc.m, npc.x / 100, npc.y / 100, { title = title, persistent = false, crazy = true })
    print(PREFIX .. "waypoint set: " .. title)
    return
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(npc.m, npc.x / 100, npc.y / 100))
    if ok then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
      print(PREFIX .. "map pin set: " .. title)
      return
    end
  end
  print(PREFIX .. string.format("%s is at %.1f, %.1f in %s.", title, npc.x, npc.y, npc.z or "?"))
end

-- one short freshness note, or nil when the contact is current
function ns.AgeNote(npc)
  local when = npc.seen and (" " .. date("%b %d", npc.seen)) or ""
  if npc.age >= ns.HIDE_AFTER then
    return "Not seen through " .. npc.age .. " game updates" .. (when ~= "" and (" (last seen" .. when .. ")") or "")
      .. ". Hidden from tooltips and search until you see them again."
  elseif npc.age == 1 then
    return "Last seen" .. when .. " before the last game update. May have moved or changed."
  end
end

-- tooltip text for one contact (+ item)
function ns.DetailText(npc, it)
  local lines = {}
  lines[#lines + 1] = string.format("%s, %s  (%.1f, %.1f)", where(npc), npc.z or "", npc.x or 0, npc.y or 0)
  if it then
    lines[#lines + 1] = it.n .. "  " .. money(it)
    if it.sk then lines[#lines + 1] = "Requires " .. it.sk end
    if it.lv then lines[#lines + 1] = "Requires level " .. it.lv end
    if it.lim then lines[#lines + 1] = "|cffff8040Limited stock|r (" .. it.lim .. " when you last looked)" end
  end
  -- a class trainer's spells: the next ones for your level first, with level and cost
  if not it and npc.k == "trainer" and ns.ClassTrainer and ns.ClassTrainer(npc.t) and #npc.items > 0 then
    local me = (UnitLevel and UnitLevel("player")) or 1
    local list = {}
    for _, sp in ipairs(npc.items) do list[#list + 1] = sp end
    table.sort(list, function(a, b)
      local la, lb = a.lv or 1, b.lv or 1
      local na, nb = la >= me, lb >= me -- coming up before already behind you
      if na ~= nb then return na end
      if la ~= lb then return (na and la < lb) or (not na and la > lb) end
      return a.n < b.n
    end)
    lines[#lines + 1] = GOLD .. ("Teaches %d spell%s, the next ones for your level first:"):format(#list, #list == 1 and "" or "s") .. "|r"
    for i = 1, math.min(10, #list) do
      local sp = list[i]
      lines[#lines + 1] = ("  level %d  %s  %s"):format(sp.lv or 1, sp.n, money(sp))
    end
    if #list > 10 then lines[#lines + 1] = GREY .. "  ...and " .. (#list - 10) .. " more. Search a spell name to find it.|r" end
  end
  -- a profession trainer: how many recipes, and the first few by the skill they need
  if not it and npc.k == "trainer" and not (ns.ClassTrainer and ns.ClassTrainer(npc.t)) then
    if #npc.items == 0 then
      lines[#lines + 1] = GREY .. "No recipes saved yet. Open their training window again to read it.|r"
    else
      local list = {}
      for _, sp in ipairs(npc.items) do list[#list + 1] = sp end
      local function need(x) return tonumber(x.sk and x.sk:match("(%d+)%s*$")) or 0 end
      table.sort(list, function(a, b) if need(a) ~= need(b) then return need(a) < need(b) end return a.n < b.n end)
      lines[#lines + 1] = GOLD .. ("Teaches %d recipe%s:"):format(#list, #list == 1 and "" or "s") .. "|r"
      for i = 1, math.min(8, #list) do
        local sp = list[i]
        lines[#lines + 1] = ("  %s%s  %s"):format(sp.n, sp.sk and (GREY .. "  needs " .. sp.sk .. "|r") or "", money(sp))
      end
      if #list > 8 then lines[#lines + 1] = GREY .. "  ...and " .. (#list - 8) .. " more. Search a recipe name to find it.|r" end
    end
  end
  local note = ns.AgeNote(npc)
  if note then
    lines[#lines + 1] = "|cffff9020" .. note .. "|r"
  else
    if npc.seen then lines[#lines + 1] = GREY .. "Last seen " .. date("%b %d", npc.seen) .. "|r" end
    if npc.visited and npc.visited ~= npc.seen then lines[#lines + 1] = GREY .. (npc.k == "trainer" and "List checked " or "Stock checked ") .. date("%b %d", npc.visited) .. "|r" end
  end
  lines[#lines + 1] = "|cff80c0ffClick for a waypoint|r"
  return table.concat(lines, "\n")
end

---------------------------------------------------------------- lookups

local function hitsForLink(link, name)
  Ensure()
  -- match by item ID and by name, without duplicates
  local id = link and tonumber(link:match("item:(%d+)"))
  name = name or (link and link:match("%[(.-)%]"))
  local out, seen = {}, {}
  for _, list in ipairs({ id and byId[id] or {}, name and byName[name:lower()] or {} }) do
    for _, h in ipairs(list) do
      if not seen[h] then seen[h] = true; out[#out + 1] = h end
    end
  end
  return out
end

-- "alchemy" should find an <Alchemist>, "leatherworking" a <Leatherworker>, "herbalism" an <Herbalist>
local function stem(q)
  local s = q:gsub("ing$", ""):gsub("ism$", "is"):gsub("y$", "")
  if #s >= 5 and s ~= q then return s end
end

-- "Apprentice Leatherworking" or "Leatherworking (Apprentice)": a rank, not a recipe
local RANK_WORD = { apprentice = true, journeyman = true, expert = true, artisan = true, master = true }
local function rankWord(name)
  local w = name:match("^(%a+) ") or name:match("%((%a+)%)$")
  if w and RANK_WORD[w:lower()] then return w end
end

-- NPCs you've passed (scout mode) but never talked to; has(text) filters, nil = all
local function seenHits(known, has)
  local out = {}
  for id, s in pairs(DB() and DB().scouted or {}) do
    -- relevance by today's rules (the flag saved when scouting can be out of date)
    local relevant = s.relevant
    if ns.IsRelevant then relevant = ns.IsRelevant(s.title) end
    -- the "not visited" list (no search text) only names your own class's trainer
    if relevant and not has and ns.WantedHere and not ns.WantedHere(s.title) then relevant = false end
    if s.name and s.title and relevant and not known[id] and not known[s.name]
      and (not has or has(s.name) or has(s.title)) then
      out[#out + 1] = { seen = true, npc = { n = s.name, t = s.title, z = s.zone, s = s.subzone, m = s.mapID,
        x = s.x, y = s.y, age = 0, seen = s.lastSeen, seenOnly = true, items = {} } }
    end
  end
  return out
end

local function knownSet()
  local known = {}
  for _, npc in ipairs(npcs) do
    if npc.id then known[npc.id] = true end
    known[npc.n] = true
  end
  return known
end

-- search item names, vendor names/titles/towns, and required professions ("tailoring").
-- A trainer's recipes that only match by profession collapse into one row ("trains 33").
-- NPCs you've passed but never talked to (scout mode) show too, marked as seen only.
local function search(q)
  Ensure()
  q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local hits = {}
  if q == "" then return hits end
  local st = stem(q)
  local function has(text)
    if not text then return false end
    text = text:lower()
    return text:find(q, 1, true) ~= nil or (st ~= nil and text:find(st, 1, true) ~= nil)
  end
  local known = knownSet()
  for _, npc in ipairs(npcs) do
    if npc.age >= ns.HIDE_AFTER then -- hidden: not seen through two updates
    else
    local npcHit
    if has(npc.n) or has(npc.t) or has(npc.s) or has(npc.z) then
      npcHit = { npc = npc }
      table.insert(hits, npcHit)
    end
    local trains, ranks = 0, {}
    for _, it in ipairs(npc.items) do
      if has(it.n) then
        if it.train and rankWord(it.n) then ranks[#ranks + 1] = it.n
        else table.insert(hits, { npc = npc, item = it }) end
      elseif it.sk and has(it.sk) then
        if it.train then trains = trains + 1 else table.insert(hits, { npc = npc, item = it }) end
      end
    end
    if trains > 0 or #ranks > 0 then
      if not npcHit then npcHit = { npc = npc }; table.insert(hits, npcHit) end
      npcHit.trains = trains > 0 and trains or nil
      npcHit.ranks = #ranks > 0 and ranks or nil
    end
    end
  end
  for _, h in ipairs(seenHits(known, has)) do hits[#hits + 1] = h end
  return sortHits(hits)
end

-- every crafting NPC you've passed but not talked to, nearest first ("Only not visited")
local function unvisited()
  Ensure()
  return sortHits(seenHits(knownSet(), nil))
end
ns.Unvisited = unvisited
ns.SortHits = sortHits
ns.RankWord = rankWord

---------------------------------------------------------------- tooltips

local function addToTooltip(tt)
  if not tt or tt.faContactsDone or Settings().tooltips == false then return end
  local name, link = tt:GetItem()
  local hits = hitsForLink(link, name)
  local list = {}
  for i, h in ipairs(hits or {}) do if not h.item.train then list[#list + 1] = h end end
  if #list == 0 then
    -- nobody you've met sells it: for known vendor-only reagents, say what kind of vendor does
    local FA = ForeverArtisan
    local hint = FA and FA.VendorHint and FA.VendorHint(name or link)
    if not hint then return end
    tt.faContactsDone = true
    tt:AddLine(GOLD .. "Sold by|r")
    tt:AddLine(GREY .. "  " .. hint .. " - none in your Trade Contacts yet|r")
    tt:Show()
    return
  end
  tt.faContactsDone = true
  sortHits(list)
  tt:AddLine(GOLD .. "Sold by|r")
  for i = 1, math.min(#list, MAX_TIP_LINES) do
    local h = list[i]
    local old = h.npc.age > 0
    local left = "  " .. (old and GREY or "") .. h.npc.n .. (old and "|r" or "") .. GREY .. " - " .. where(h.npc) .. "|r"
    if h.item.lim then left = left .. " |cffff8040(limited)|r" end
    if old then left = left .. GREY .. " (before update)|r" end
    local c = old and 0.6 or 1
    tt:AddDoubleLine(left, money(h.item), c, c, c, c, c, c)
  end
  if #list > MAX_TIP_LINES then
    tt:AddLine(GREY .. "  +" .. (#list - MAX_TIP_LINES) .. " more: /fa " .. (name or "") .. "|r")
  end
  tt:Show()
end

local function clearFlag(tt) tt.faContactsDone = nil end

local function HookTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
      if tt == GameTooltip or tt == ItemRefTooltip then pcall(addToTooltip, tt) end
    end)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      tt:HookScript("OnTooltipSetItem", function(self) pcall(addToTooltip, self) end)
    end
  end
  GameTooltip:HookScript("OnTooltipCleared", clearFlag)
  ItemRefTooltip:HookScript("OnTooltipCleared", clearFlag)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() HookTooltips() end)

---------------------------------------------------------------- search entry points

ns.Search = search
ns.HitsForLink = hitsForLink

-- other modules (Cooking, First Aid, the /fa hub) use this; it only exists while Trade Contacts is on
FA.Vendors = {
  search = search,
  hitsForLink = hitsForLink,
  open = function(q) if ns.OpenSearch then ns.OpenSearch(q) end end,
  waypoint = function(npc) if npc then ns.SetWaypoint(npc) end end,
  scoutOn = function() return ns.ScoutOn and ns.ScoutOn() end,
  setScout = function(on) if ns.SetScoutFromUI then ns.SetScoutFromUI(on) end end,
  scoutTip = function(tt) if ns.ScoutTip then ns.ScoutTip(tt) end end,
  -- closest trainer you've met or passed for a profession ("Enchanting"), or nil
  nearestTrainer = function(trade)
    local h = ns.NearestTrainerHits and ns.NearestTrainerHits(trade)[1]
    return h and h.npc or nil
  end,
}

SLASH_FASEARCH1 = "/fasearch"
SlashCmdList.FASEARCH = function(msg)
  if ns.OpenSearch then ns.OpenSearch(strtrim(msg or "")) end
end
