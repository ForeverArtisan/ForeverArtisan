-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Trade Contacts
-- Your own crafting address book. Every crafting vendor and profession trainer you talk to is
-- saved: what they sell or teach, prices, limited stock, requirements and where they stand.
-- It starts empty and only knows NPCs you've met. Finder.lua turns it into item tooltips and
-- search. Data lives in WTF\Account\<ACCOUNT>\SavedVariables\ForeverArtisan_Contacts.lua on
-- this computer and is shared by every character on the account. Nothing is sent anywhere.

local ADDON, ns = ...
ns = ns or {}

-- Newer clients (Forever beta) moved these to C_Item; keep the old names working inside this file.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo or function() end
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local PREFIX = ForeverArtisan.Prefix("Trade Contacts")
local DB_VERSION = 1

local f = CreateFrame("Frame")
local tip = CreateFrame("GameTooltip", "ForeverArtisanContactsScanTip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function say(msg)
  if ForeverArtisanContactsDB and ForeverArtisanContactsDB.quiet then return end
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

---------------------------------------------------------------- helpers

local isRelevant, isIgnored, classTrainer, wantedHere -- crafting filters, defined with the scout lists below

local function round1(n) return math.floor(n * 1000 + 0.5) / 10 end

local function where()
  local w = {
    zone = GetRealZoneText() or GetZoneText(),
    subzone = GetSubZoneText(),
  }
  if w.subzone == "" then w.subzone = nil end
  if C_Map and C_Map.GetBestMapForUnit then
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
      w.mapID = mapID
      local info = C_Map.GetMapInfo(mapID)
      if info then w.mapName = info.name end
      local pos = C_Map.GetPlayerMapPosition(mapID, "player")
      if pos then
        local x, y = pos:GetXY()
        if x and y and (x > 0 or y > 0) then
          w.x, w.y = round1(x), round1(y)
        end
      end
    end
  end
  return w
end

-- Forever can hand addons "secret" values for units (in combat, some nameplates): they can't be read,
-- compared or used as keys, so a unit with one is skipped.
local function Secret(v) return issecretvalue and v ~= nil and issecretvalue(v) end

local function npcIdFromGUID(guid)
  if not guid or Secret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- Reads the NPC's "<Title>" line from its tooltip, e.g. "Leatherworking Supplies".
local function npcTitle(unit)
  tip:ClearLines()
  tip:SetUnit(unit)
  for i = 2, math.min(tip:NumLines(), 3) do
    local fs = _G["ForeverArtisanContactsScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t and t:match("^<.+>$") then return t:sub(2, -2) end
    if t and not t:find(LEVEL or "Level") and not t:find("PvP") then
      -- Classic shows titles without brackets on some clients
      if i == 2 and not t:find("%d") then return t end
    end
  end
end

local function npcInfo(unit)
  unit = unit or "npc"
  if not UnitExists(unit) then return nil end
  local guid = UnitGUID(unit)
  local n = {
    name = UnitName(unit),
    npcId = npcIdFromGUID(guid),
    title = npcTitle(unit),
    level = UnitLevel(unit),
  }
  if n.level and n.level <= 0 then n.level = nil end
  local reaction = UnitReaction(unit, "player")
  if reaction and not Secret(reaction) then n.reaction = reaction end -- 4 neutral, 5+ friendly
  return n
end

-- Tooltip lines that start with "Requires" (level, skill, reputation, class...)
local function requiresFromTooltip()
  local req = {}
  for i = 2, tip:NumLines() do
    local fs = _G["ForeverArtisanContactsScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t and t:find("^Requires") then
      local dup = false
      for _, r in ipairs(req) do if r == t then dup = true end end
      if not dup then req[#req + 1] = t end
    end
  end
  return (#req > 0) and req or nil
end

local function itemIdFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

-- The game build (changes with every patch). Contacts remember the build they were last seen on,
-- so after an update the finder can say "seen before the last update" and, after two updates
-- without a sighting, stop offering them.
local CUR_BUILD = tostring(select(2, GetBuildInfo()) or "?")
ns.CurrentBuild = CUR_BUILD

local function stamp(entry)
  entry.lastSeen = time()
  entry.seenAt = entry.lastSeen
  entry.build = CUR_BUILD
  entry.firstSeen = entry.firstSeen or entry.lastSeen
  entry.seenBy = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
  entry.faction = UnitFactionGroup("player")
  entry.clientBuild = select(4, GetBuildInfo())
end

local function keyFor(n, w, kind)
  if n and n.npcId then return kind .. ":" .. n.npcId end
  return kind .. ":" .. ((n and n.name) or "?") .. "@" .. (w.zone or "?")
end

local function save(kind, n, w, extra)
  local key = keyFor(n, w, kind)
  local e = ForeverArtisanContactsDB.entries[key] or {}
  e.kind = kind
  -- drop the old location so nothing from a previous spot sticks (e.g. a subzone name)
  e.zone, e.subzone, e.mapID, e.mapName, e.x, e.y = nil, nil, nil, nil, nil, nil
  for k, v in pairs(n or {}) do e[k] = v end
  for k, v in pairs(w) do e[k] = v end
  for k, v in pairs(extra or {}) do e[k] = v end
  stamp(e)
  ForeverArtisanContactsDB.entries[key] = e
  if ns.OnContactsChanged then ns.OnContactsChanged() end
  return e
end

local function coordText(w)
  if w.x then return string.format("%.1f, %.1f", w.x, w.y) end
  return "no coords"
end

---------------------------------------------------------------- merchants

local function merchantItem(i)
  local name, price, qty, avail, extended
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(i)
    if info then
      name, price, qty, avail, extended = info.name, info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
    end
  else
    local _
    name, _, price, qty, avail, _, _, extended = GetMerchantItemInfo(i)
  end
  if not name then return nil end

  local link = GetMerchantItemLink(i)
  local it = {
    name = name,
    itemId = itemIdFromLink(link),
    priceCopper = price,
    stack = (qty and qty > 1) and qty or nil,
  }
  if avail and avail >= 0 then it.limited = avail end -- stock left right now

  if link then
    local _, _, quality, ilvl, minLevel, itemType, subType = GetItemInfo(link)
    it.quality, it.type, it.subType = quality, itemType, subType
    if minLevel and minLevel > 1 then it.levelReq = minLevel end
  end

  if extended and GetMerchantItemCostInfo then
    local ok, n = pcall(GetMerchantItemCostInfo, i)
    if ok and n and n > 0 then
      it.cost = {}
      for c = 1, n do
        local tex, value, costLink, currencyName = GetMerchantItemCostItem(i, c)
        it.cost[#it.cost + 1] = { amount = value, item = costLink and costLink:match("%[(.-)%]") or currencyName }
      end
    end
  end

  tip:ClearLines()
  local ok = pcall(tip.SetMerchantItem, tip, i)
  if ok then
    it.requires = requiresFromTooltip()
    -- Recipes/patterns: keep the whole tooltip (it shows what the recipe makes).
    local classID = link and GetItemInfoInstant and select(6, GetItemInfoInstant(link))
    if classID == 9 or (it.type == "Recipe") then
      local lines = {}
      for l = 1, tip:NumLines() do
        local fs = _G["ForeverArtisanContactsScanTipTextLeft" .. l]
        local t = fs and fs:GetText()
        if t and t ~= "" and t ~= " " then lines[#lines + 1] = t end
      end
      if #lines > 1 then it.tooltip = lines end
    end
  end
  return it
end

-- Limited-stock history: one entry per visit, so restock timers can be worked out.
local function recordStock(e, items)
  e.stockLog = e.stockLog or {}
  local now = time()
  for _, it in ipairs(items) do
    if it.limited then
      local k = tostring(it.itemId or it.name)
      local log = e.stockLog[k] or {}
      local last = log[#log]
      if not last or last.n ~= it.limited or (now - last.t) > 300 then
        log[#log + 1] = { t = now, n = it.limited }
        while #log > 60 do table.remove(log, 1) end
      end
      e.stockLog[k] = log
    end
  end
end

-- Item details load from the server a moment after the window opens, so we
-- scan several times while it's open and keep every slot we've managed to read.
local merchantKey, slots, scanToken = nil, {}, 0

-- Item classes that make a vendor worth keeping even when its title says "Armor Merchant":
-- reagents, recipes and the like. Gear-only vendors are dropped after their window is read.
local CRAFT_TYPES = { ["Trade Goods"] = true, ["Recipe"] = true, ["Reagent"] = true, ["Tradeskill"] = true }
local function isCraftItem(it)
  if not it then return false end
  if it.type and CRAFT_TYPES[it.type] then return true end
  local sub = it.subType
  if sub and (sub == "Trade Goods" or sub == "Parts" or sub == "Explosives" or sub == "Devices" or sub == "Herb"
    or sub == "Metal & Stone" or sub == "Leather" or sub == "Cloth" or sub == "Meat" or sub == "Elemental"
    or sub == "Enchanting" or sub == "Jewelcrafting" or sub == "Cooking" or sub == "Materials") then return true end
  return false
end

local function logMerchant(final)
  local n = npcInfo("npc")
  if not n then return end
  -- weapon/armor sellers etc. are usually gear-only, but the title is a guess: read the
  -- window anyway and keep the NPC only if it actually sells crafting goods
  local gearVendor = n.title and isIgnored(n.title) or false
  local w = where()
  local key = keyFor(n, w, "vendor")
  if key ~= merchantKey then merchantKey, slots = key, {} end

  local total = GetMerchantNumItems() or 0
  if total == 0 and next(slots) then return end -- window already closed; keep what we saved
  for i = 1, total do
    local it = merchantItem(i)
    if it and (it.type or not slots[i]) then slots[i] = it end
  end
  local items, got = {}, 0
  for i = 1, total do
    if slots[i] then got = got + 1; items[#items + 1] = slots[i] end
  end
  if gearVendor then
    -- keep only the crafting items; skip the NPC entirely if there are none (yet)
    local kept = {}
    for _, it in ipairs(items) do if isCraftItem(it) then kept[#kept + 1] = it end end
    if #kept == 0 then
      if final and got == total then merchantKey, slots = nil, {} end -- gear only: nothing to remember
      return got, total
    end
    items = kept
  end
  local e = save("vendor", n, w, {
    items = items,
    itemCount = total,
    partial = (got < total),
    craftOnly = gearVendor or nil, -- items list is filtered to crafting goods
    canRepair = CanMerchantRepair and CanMerchantRepair() or nil,
  })
  if final then
    recordStock(e, items)
    local count = (got < total) and string.format("%d of %d items - reopen to finish", got, total) or (got .. " items")
    if gearVendor then count = string.format("%d crafting item%s of %d", #items, #items == 1 and "" or "s", total) end
    say(string.format("saved %s%s - %s (%s)", n.name, e.title and (" <" .. e.title .. ">") or "", count, coordText(w)))
  end
  return got, total
end

local announced = true

local function finishMerchant()
  if announced then return end
  announced = true
  scanToken = scanToken + 1 -- cancel remaining passes
  pcall(logMerchant, true)
end

local function scanMerchant()
  scanToken = scanToken + 1
  announced = false
  local token = scanToken
  local got, total = logMerchant(false)
  if total and total > 0 and got == total then
    -- everything was already cached; one quick re-check for tooltips, then report
    C_Timer.After(0.4, function() if token == scanToken then finishMerchant() end end)
    return
  end
  local delays = { 0.4, 1.0, 2.0, 3.5 }
  for idx, d in ipairs(delays) do
    C_Timer.After(d, function()
      if token ~= scanToken then return end
      local ok, g, t = pcall(logMerchant, false)
      if idx == #delays or (ok and t and t > 0 and g == t) then finishMerchant() end
    end)
  end
end

---------------------------------------------------------------- trainers

local FILTERS = { "available", "unavailable", "used" }

local function logTrainer(announce)
  local n = npcInfo("npc")
  if not n then return end
  -- pet, riding and other non-crafting trainers: skip. Class trainers are kept.
  if n.title and isIgnored(n.title) and not classTrainer(n.title) then return 0 end
  local w = where()

  -- Show everything (even what you can't learn yet), then put your filters back.
  -- Some clients want true/false here, older ones want 1/0; try both, never error.
  local function setFilter(k, on)
    if not pcall(SetTrainerServiceTypeFilter, k, on and true or false) then
      pcall(SetTrainerServiceTypeFilter, k, on and 1 or 0)
    end
  end
  local saved = {}
  if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
    for _, k in ipairs(FILTERS) do
      local ok, v = pcall(GetTrainerServiceTypeFilter, k)
      saved[k] = ok and v and v ~= 0 or false
      setFilter(k, true)
    end
  end

  local skills, header = {}, nil
  for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
    local name, sub, category = GetTrainerServiceInfo(i)
    if category == "header" then
      header = name
    elseif name then
      -- Forever returns the status ("available" / "unavailable" / "used") here; Classic returned the rank
      local status = sub and ({ available = true, unavailable = true, used = true })[sub:lower()]
      local s = { name = name, rank = (sub and sub ~= "" and not status) and sub or nil,
                  status = status and sub:lower() or nil, group = header }
      if GetTrainerServiceCost then s.priceCopper = GetTrainerServiceCost(i) end
      if GetTrainerServiceLevelReq then
        local lv = GetTrainerServiceLevelReq(i)
        if lv and lv > 1 then s.levelReq = lv end
      end
      if GetTrainerServiceSkillReq then
        local skill, rank = GetTrainerServiceSkillReq(i)
        if skill and rank and rank > 0 then s.skillReq = skill .. " " .. rank end
      end
      skills[#skills + 1] = s
    end
  end

  for k, v in pairs(saved) do setFilter(k, v) end

  if #skills == 0 and not announce then return 0 end -- list not loaded yet; try again shortly
  local e = save("trainer", n, w, {
    skills = skills,
    trainerType = GetTrainerGreetingText and GetTrainerGreetingText() or nil,
  })
  if announce then
    say(string.format("saved trainer %s%s - %d skills (%s)", n.name, e.title and (" <" .. e.title .. ">") or "", #skills, coordText(w)))
  end
  return #skills
end

-- The skill list arrives a moment after the window opens: scan a few times, report once.
local trainerToken = 0
local function scanTrainer()
  trainerToken = trainerToken + 1
  local token, last = trainerToken, -1
  local delays = { 0.3, 1.0, 2.0, 3.5 }
  for idx, d in ipairs(delays) do
    C_Timer.After(d, function()
      if token ~= trainerToken then return end
      local final = (idx == #delays)
      local ok, count = pcall(logTrainer, false)
      count = ok and count or 0
      -- stop early once the list is loaded and stopped growing
      if count > 0 and count == last then final = true end
      last = count
      if final then
        trainerToken = trainerToken + 1
        local ok2, err = pcall(logTrainer, true)
        if not ok2 then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "|cffff5555error:|r " .. tostring(err)) end
      end
    end)
  end
end

---------------------------------------------------------------- services

local function logService(service, unit)
  local n = npcInfo(unit or "npc")
  if not n then return end
  local w = where()
  local e = save("service", n, w, { service = service })
  say(string.format("saved %s %s (%s)", service, n.name, coordText(w)))
end

-- Talk-only crafting NPCs (profession trainers before you click "train", recipe sellers).
-- Only NPCs with a crafting-related <Title> are logged here; innkeepers, bankers, guards etc. are skipped.
-- (Vendors are different: even an "Armor Merchant" is read and kept if it sells crafting goods.)
local function logGossip()
  if not UnitExists("npc") or UnitIsPlayer("npc") then return end
  local n = npcInfo("npc")
  if not n or not n.title or not isRelevant(n.title) then return end
  local w = where()
  local key = keyFor(n, w, "service")
  local isNew = not ForeverArtisanContactsDB.entries[key]
  save("service", n, w, { service = n.title:lower() })
  if isNew then say(string.format("saved %s <%s> (%s)", n.name, n.title, coordText(w))) end
end

---------------------------------------------------------------- professions
-- Opening a profession window saves every recipe: reagents, tools, what it makes,
-- and its color at your current skill (orange/yellow/green/gray). Colors are kept
-- per skill level, so logging at different levels maps out the skill-up ranges.

local COLOR = { optimal = "orange", medium = "yellow", easy = "green", trivial = "gray", difficult = "red" }

local function scanProfession(api)
  local profName, rank, maxRank
  local num
  if api == "craft" then
    if not GetNumCrafts then return end
    profName = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or (GetCraftName and GetCraftName())
    local _, r, m = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()
    rank, maxRank = r, m
    num = GetNumCrafts()
  else
    if not GetNumTradeSkills then return end
    profName, rank, maxRank = GetTradeSkillLine()
    num = GetNumTradeSkills()
  end
  if not profName or profName == "UNKNOWN" or not num or num == 0 then return 0 end

  ForeverArtisanContactsDB.professions = ForeverArtisanContactsDB.professions or {}
  local P = ForeverArtisanContactsDB.professions[profName] or { recipes = {} }
  P.rank, P.maxRank, P.lastSeen = rank, maxRank, time()
  P.seenBy = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
  P.clientBuild = select(4, GetBuildInfo())

  local count, header = 0, nil
  for i = 1, num do
    local name, kind
    if api == "craft" then
      local _
      name, _, kind = GetCraftInfo(i)
    else
      name, kind = GetTradeSkillInfo(i)
    end
    if kind == "header" then
      header = name
    elseif name then
      count = count + 1
      local r = P.recipes[name] or {}
      r.group = header
      r.colors = r.colors or {}
      if rank then r.colors[tostring(rank)] = COLOR[kind] or kind end
      local link = (api == "craft") and (GetCraftItemLink and GetCraftItemLink(i)) or (GetTradeSkillItemLink and GetTradeSkillItemLink(i))
      if link then
        r.itemId = itemIdFromLink(link)
        r.makes = link:match("%[(.-)%]")
      end
      if api ~= "craft" and GetTradeSkillNumMade then
        local lo, hi = GetTradeSkillNumMade(i)
        if lo and lo > 1 or (hi and hi > 1) then r.made = { lo, hi } end
      end
      local nR = (api == "craft") and GetCraftNumReagents(i) or GetTradeSkillNumReagents(i)
      local reagents = {}
      for j = 1, (nR or 0) do
        local rName, _, rCount
        if api == "craft" then rName, _, rCount = GetCraftReagentInfo(i, j)
        else rName, _, rCount = GetTradeSkillReagentInfo(i, j) end
        local rLink = (api == "craft") and (GetCraftReagentItemLink and GetCraftReagentItemLink(i, j))
          or (GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j))
        if rName then
          reagents[#reagents + 1] = { name = rName, count = rCount, itemId = itemIdFromLink(rLink) }
        end
      end
      if #reagents > 0 or not r.reagents then r.reagents = reagents end
      local tools = (api == "craft") and (GetCraftSpellFocus and { GetCraftSpellFocus(i) }) or (GetTradeSkillTools and { GetTradeSkillTools(i) })
      if tools and #tools > 0 then r.tools = tools end
      P.recipes[name] = r
    end
  end
  ForeverArtisanContactsDB.professions[profName] = P
  return count, profName, rank, maxRank
end

-- Modern profession window (C_TradeSkillUI), used by the Forever client.
local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

local function tryCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

local function itemName(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemNameByID then
    local n = tryCall(C_Item.GetItemNameByID, id)
    if n then return n end
  end
  return (GetItemInfo(id))
end

local function scanModern()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs) then return end
  local profName, rank, maxRank
  local D = { at = time(), tried = {} }
  ForeverArtisanContactsDB.diag.lastProfScan = D

  local function describe(tag, t)
    if type(t) ~= "table" then D.tried[#D.tried + 1] = tag .. "=" .. tostring(t); return end
    local parts = {}
    for k, v in pairs(t) do
      if type(v) ~= "table" and type(v) ~= "function" then parts[#parts + 1] = k .. ":" .. tostring(v) end
    end
    table.sort(parts)
    D.tried[#D.tried + 1] = tag .. "={" .. table.concat(parts, " ") .. "}"
  end
  local function useInfo(t)
    if profName or type(t) ~= "table" then return end
    local n = t.professionName or t.name or t.parentProfessionName
    if n and n ~= "" then
      profName = n
      rank = t.skillLevel or t.rank or rank
      maxRank = t.maxSkillLevel or t.maxRank or maxRank
    end
  end

  -- 1) modern profession info tables
  for _, fname in ipairs({ "GetChildProfessionInfo", "GetBaseProfessionInfo" }) do
    local t = tryCall(T[fname]); describe(fname, t); useInfo(t)
  end
  -- 2) the profession window itself
  if not profName and ProfessionsFrame and ProfessionsFrame.GetProfessionInfo then
    local t = tryCall(ProfessionsFrame.GetProfessionInfo, ProfessionsFrame); describe("ProfessionsFrame", t); useInfo(t)
  end
  -- 3) older-style calls
  if not profName then
    local a, b, c, d = tryCall(T.GetTradeSkillLine)
    D.tried[#D.tried + 1] = "C_TradeSkillUI.GetTradeSkillLine=" .. tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) .. "," .. tostring(d)
    if type(b) == "string" then profName, rank, maxRank = b, c, d
    elseif type(a) == "string" then profName, rank, maxRank = a, b, c end
  end
  if not profName and GetTradeSkillLine then
    local a, b, c = tryCall(GetTradeSkillLine)
    if type(a) == "string" and a ~= "UNKNOWN" then profName, rank, maxRank = a, b, c end
  end

  local ids = tryCall(T.GetAllRecipeIDs)
  D.numRecipeIDs = type(ids) == "table" and #ids or tostring(ids)
  -- 4) still no name: keep the recipes anyway under the first recipe's category
  if not profName and type(ids) == "table" and #ids > 0 then
    profName = "Unknown profession"
  end
  D.profName, D.rank, D.maxRank = profName, rank, maxRank
  if not profName or type(ids) ~= "table" or #ids == 0 then
    D.result = "nothing read"
    return 0, profName, rank, maxRank
  end
  D.result = "ok"

  ForeverArtisanContactsDB.professions = ForeverArtisanContactsDB.professions or {}
  local P = ForeverArtisanContactsDB.professions[profName] or { recipes = {} }
  P.rank, P.maxRank, P.lastSeen = rank, maxRank, time()
  P.seenBy = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
  P.clientBuild = select(4, GetBuildInfo())
  P.api = "C_TradeSkillUI"

  local count = 0
  for _, id in ipairs(ids) do
    local ri = tryCall(T.GetRecipeInfo, id)
    if type(ri) == "table" and ri.name then
      if not ForeverArtisanContactsDB.diag.recipeInfoKeys then
        local keys = {}
        for k in pairs(ri) do keys[#keys + 1] = k end
        table.sort(keys)
        ForeverArtisanContactsDB.diag.recipeInfoKeys = table.concat(keys, ",")
      end
      count = count + 1
      local r = P.recipes[ri.name] or {}
      r.recipeId = id
      r.learned = ri.learned
      if ri.categoryID and T.GetCategoryInfo then
        local cat = tryCall(T.GetCategoryInfo, ri.categoryID)
        if type(cat) == "table" then r.group = cat.name end
      end
      r.colors = r.colors or {}
      if rank and ri.learned ~= false and ri.relativeDifficulty ~= nil then
        r.colors[tostring(rank)] = DIFF[ri.relativeDifficulty] or tostring(ri.relativeDifficulty)
      end
      if ri.numSkillUps and ri.numSkillUps > 1 then r.skillUps = ri.numSkillUps end
      -- Forever exposes the skill at which a recipe turns gray: the end of its skill-up range.
      if ri.maxTrivialLevel and ri.maxTrivialLevel > 0 then r.grayAt = ri.maxTrivialLevel end
      if ri.canSkillUp ~= nil and ri.learned then r.canSkillUp = ri.canSkillUp end

      local reagents = {}
      local sch = T.GetRecipeSchematic and tryCall(T.GetRecipeSchematic, id, false)
      if type(sch) == "table" then
        if sch.outputItemID then r.itemId = sch.outputItemID; r.makes = itemName(sch.outputItemID) or r.makes end
        if (sch.quantityMax or 1) > 1 then r.made = { sch.quantityMin, sch.quantityMax } end
        for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
          local first = slot.reagents and slot.reagents[1]
          if first and first.itemID then
            reagents[#reagents + 1] = { name = itemName(first.itemID), count = slot.quantityRequired, itemId = first.itemID }
          end
        end
      elseif T.GetRecipeNumReagents then
        local link = tryCall(T.GetRecipeItemLink, id)
        if link then r.itemId = itemIdFromLink(link); r.makes = link:match("%[(.-)%]") end
        for j = 1, (tryCall(T.GetRecipeNumReagents, id) or 0) do
          local rName, _, rCount = tryCall(T.GetRecipeReagentInfo, id, j)
          local rLink = tryCall(T.GetRecipeReagentItemLink, id, j)
          if rName then reagents[#reagents + 1] = { name = rName, count = rCount, itemId = itemIdFromLink(rLink) } end
        end
      end
      if #reagents > 0 or not r.reagents then r.reagents = reagents end
      local tools = T.GetRecipeTools and { tryCall(T.GetRecipeTools, id) }
      if tools and #tools > 0 then r.tools = tools end
      P.recipes[ri.name] = r
    end
  end
  ForeverArtisanContactsDB.professions[profName] = P
  return count, profName, rank, maxRank
end

local profToken, profLastRank = 0, {}
local function scanProfessionSoon(api, announce)
  profToken = profToken + 1
  local token = profToken
  for idx, d in ipairs({ 0.3, 1.5 }) do
    C_Timer.After(d, function()
      if token ~= profToken then return end
      -- Old-style window first; if it finds nothing, use the modern profession API.
      local ok, count, name, rank, maxRank = pcall(scanProfession, api)
      if api == "trade" and (not ok or not count or count == 0) then
        ok, count, name, rank, maxRank = pcall(scanModern)
      end
      if not ok then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "|cffff5555error:|r " .. tostring(count)); return end
      if idx == 2 and count and count > 0 and (announce or profLastRank[name] ~= rank) then
        profLastRank[name] = rank
        say(string.format("logged %s (%s/%s) - %d recipes", name, tostring(rank), tostring(maxRank), count))
      elseif idx == 2 and announce and (not count or count == 0) then
        local D = ForeverArtisanContactsDB.diag.lastProfScan
        say("profession window seen, but no recipes read. " ..
          (D and ("(" .. tostring(D.profName) .. ", " .. tostring(D.numRecipeIDs) .. " recipe ids) ") or "") ..
          "Details saved for Claude - /reload when done.")
      end
    end)
  end
end

---------------------------------------------------------------- scout mode
-- Passively records friendly/neutral NPCs you pass (nameplates, mouseover, target):
-- name, title, and an approximate location. Nothing is clicked or automated -
-- it only reads what the game already shows you. /fa contacts todo lists the
-- crafting-relevant ones you haven't opened yet.

local RELEVANT = {
  "suppl", "goods", "trade", "trainer", "recipe", "cook", "chef", "baker", "fisher", "fishing",
  "import", "export", "sundries", "wares", "curios", "herbs", "ores", "fabric", "tackle",
  "herbal", "alchem", "blacksmith", "armorsmith", "weaponsmith", "leather", "tailor", "cloth",
  "engineer", "tinker", "enchant", "mining", "miner", "skinn", "first aid", "medic", "bandage",
  "reagent", "general", "provision", "quartermaster", "merchant", "vendor", "smith", "artisan",
  "journeyman", "expert", "master", "apprentice", "brewer", "butcher", "wine", "spirits", "food",
}
local IGNORE = { "guard", "grunt", "sentinel", "flight master", "wind rider", "gryphon", "bat handler",
  "battlemaster", "stable", "innkeeper", "banker", "auctioneer", "guild", "tabard", "portal",
  "armor merchant", "weapon dealer", "weapon merchant", "weapons merchant", "staff merchant",
  "mace", "sword", "axe merchant", "dagger", "robe merchant", "bowyer", "gunsmith", "shield", "mail armor", "plate armor",
  "cloth & leather armor", "bartender", "warrior trainer", "mage trainer", "priest trainer",
  "rogue trainer", "hunter trainer", "warlock trainer", "shaman trainer", "paladin trainer",
  "druid trainer", "pet trainer", "weapon master", "riding", "mechanostrider",
  "demon trainer", "horse merchant", "cockroach", "'s pet", "bag vendor", "shipmaster", "blade trader",
  "fireworks", "prizes", "apprentice weaponsmith", "apprentice armorer", "armorer" }

-- Class trainers aren't crafting, but they're part of the journey: saved and searchable,
-- listed under Trade > Class trainers, and kept out of the crafting lists.
local CLASSES = { "warrior", "mage", "priest", "rogue", "hunter", "warlock", "shaman", "paladin", "druid" }
classTrainer = function(title)
  if not title then return nil end
  local t = title:lower()
  for _, c in ipairs(CLASSES) do
    if t:find(c .. " trainer", 1, true) then return c end
  end
end
-- "Only not visited" lists your own class's trainers, not every class's
wantedHere = function(title)
  local c = classTrainer(title)
  if not c then return true end
  local mine = UnitClass and UnitClass("player")
  return mine ~= nil and mine:lower() == c
end

isIgnored = function(title)
  if not title then return false end
  local t = title:lower()
  for _, w in ipairs(IGNORE) do if t:find(w, 1, true) then return true end end
  return false
end

-- titles are a small fixed set, so remember each answer (search and scouting ask the same ones over and over)
local relCache = {}
isRelevant = function(title)
  if not title then return false end
  local hit = relCache[title]
  if hit ~= nil then return hit end
  local t = title:lower()
  hit = false
  if classTrainer(title) then hit = true
  else
    for _, w in ipairs(IGNORE) do if t:find(w, 1, true) then relCache[title] = false; return false end end
    for _, w in ipairs(RELEVANT) do if t:find(w, 1, true) then hit = true; break end end
  end
  relCache[title] = hit
  return hit
end

-- An NPC counts as done if the logger opened it (any kind: vendor, trainer, or a
-- talk-only service like Scooty), if it's already in the ForeverArtisan ledger
-- (ForeverArtisanKnown, e.g. vendors logged from screenshots), or if you skipped it.
local function openedIds()
  local ids, names = {}, {}
  for _, e in pairs(ForeverArtisanContactsDB.entries) do
    if e.npcId then ids[e.npcId] = true end
    if e.name then names[e.name:lower()] = true end
  end
  for n in pairs(ForeverArtisanKnown or {}) do names[n] = true end
  return setmetatable({}, { __index = function(_, id)
    if ids[id] then return true end
    local s = ForeverArtisanContactsDB.scouted and ForeverArtisanContactsDB.scouted[id]
    if s and (s.skip or (s.name and names[s.name:lower()])) then return true end
    return false
  end })
end

-- accuracy: 3 = within ~10 yards, 2 = within ~28 yards, 1 = in nameplate range
local function closeness(unit)
  local ok, near = pcall(CheckInteractDistance, unit, 3)
  if ok and near then return 3 end
  ok, near = pcall(CheckInteractDistance, unit, 4)
  if ok and near then return 2 end
  return 1
end

-- Passing by a saved contact (nameplate, mouseover, target) proves they still exist: refresh the
-- "last seen" stamp and, when you're standing next to them, their location. Stock and prices
-- only change when you open their window.
local TOUCH_KINDS = { "vendor", "trainer" }
local lastTouch = {} -- npc id -> GetTime(): nameplates repeat twice a second, a stamp every 30s is plenty
function ns.TouchContact(id, unit)
  local entries = ForeverArtisanContactsDB and ForeverArtisanContactsDB.entries
  if not entries then return end
  local now = GetTime()
  if lastTouch[id] and now - lastTouch[id] < 30 then return end
  lastTouch[id] = now
  local changed = false
  for _, kind in ipairs(TOUCH_KINDS) do
    local e = entries[kind .. ":" .. id]
    if e then
      e.seenAt = time()
      if e.build ~= CUR_BUILD then e.build = CUR_BUILD; changed = true end
      local ok, near = pcall(CheckInteractDistance, unit, 3) -- about 10 yards
      if ok and near then
        local w = where()
        if w.x and (w.zone ~= e.zone or math.abs((e.x or 0) - w.x) > 1 or math.abs((e.y or 0) - w.y) > 1) then
          e.zone, e.subzone, e.mapID, e.mapName, e.x, e.y = w.zone, w.subzone, w.mapID, w.mapName, w.x, w.y
          changed = true
        end
      end
    end
  end
  if changed and ns.OnContactsChanged then ns.OnContactsChanged() end
end

-- forget one contact (vendor and trainer records for that NPC)
function ns.Forget(key)
  local entries = ForeverArtisanContactsDB and ForeverArtisanContactsDB.entries
  local e = entries and entries[key]
  if not e then return end
  entries[key] = nil
  say("forgot " .. (e.name or key) .. ".")
  if ns.OnContactsChanged then ns.OnContactsChanged() end
end

local scoutNew = 0
local function scoutUnit(unit)
  if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then return end
  if UnitPlayerControlled and UnitPlayerControlled(unit) then return end
  local reaction = UnitReaction(unit, "player")
  if not reaction or Secret(reaction) or reaction < 4 then return end
  local ctype = UnitCreatureType and UnitCreatureType(unit)
  if Secret(ctype) or ctype == "Critter" then return end
  local guid = UnitGUID(unit)
  local id = npcIdFromGUID(guid)
  if not id then return end
  ns.TouchContact(id, unit)
  ForeverArtisanContactsDB.scouted = ForeverArtisanContactsDB.scouted or {}
  local s = ForeverArtisanContactsDB.scouted[id]
  -- already pinned down within ~10 yards in this zone: nothing to sharpen, skip the distance checks
  if s and s.acc and s.acc >= 3 and s.zone == (GetRealZoneText() or GetZoneText()) then
    s.lastSeen = time()
    return
  end
  local acc = closeness(unit)
  if s and s.acc and s.acc >= acc and s.zone == (GetRealZoneText() or GetZoneText()) then
    s.lastSeen = time()
    return
  end
  local n = npcInfo(unit)
  if not n then return end
  local w = where()
  if not w.x then return end
  local isNew = not s
  s = s or {}
  s.name, s.title, s.level, s.reaction = n.name, n.title, n.level, n.reaction
  s.zone, s.subzone, s.mapID, s.x, s.y, s.acc = w.zone, w.subzone, w.mapID, w.x, w.y, acc
  s.lastSeen = time()
  s.firstSeen = s.firstSeen or s.lastSeen
  s.relevant = isRelevant(n.title) or nil
  ForeverArtisanContactsDB.scouted[id] = s
  if isNew then scoutNew = scoutNew + 1 end
end

-- Re-check visible nameplates twice a second so positions sharpen as you get closer.
local scoutTicker
local plateTitle -- defined below; the ticker uses it to label plates already on screen
local function startScoutTicker()
  if scoutTicker or not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  scoutTicker = C_Timer.NewTicker(0.5, function()
    if ForeverArtisanContactsDB.scoutOff or InCombatLockdown() then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
      if unit then
        pcall(scoutUnit, unit)
        if plateTitle and not plate.mlDone then pcall(plateTitle, unit) end
      end
    end
  end)
end

-- Nameplates only show names, so while scouting we add the NPC's <Title> under
-- friendly nameplates (open world only; Blizzard locks nameplates in instances).
local labeled = {}
local titleOf = {} -- npc id -> title, or false for NPCs without one (most of a town): read the tooltip once
plateTitle = function(unit)
  if ForeverArtisanContactsDB.scoutOff or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
  if not UnitExists(unit) or UnitIsPlayer(unit) then return end
  local reaction = UnitReaction(unit, "player")
  if not reaction or Secret(reaction) or reaction < 4 then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
  local id = npcIdFromGUID(UnitGUID(unit))
  local s = id and ForeverArtisanContactsDB.scouted and ForeverArtisanContactsDB.scouted[id]
  local title = s and s.title
  if not title and id then
    if titleOf[id] == nil then local n = npcInfo(unit); titleOf[id] = (n and n.title) or false end
    title = titleOf[id] or nil
  elseif not title then
    local n = npcInfo(unit); title = n and n.title
  end
  plate.mlDone = true
  if not plate.mlTitle then
    -- our own small frame above the nameplate's art, so the health bar can't cover the text
    local holder = CreateFrame("Frame", nil, plate)
    holder:SetAllPoints(plate)
    if plate.GetFrameStrata then holder:SetFrameStrata(plate:GetFrameStrata()) end
    local base = (plate.UnitFrame and plate.UnitFrame.GetFrameLevel and plate.UnitFrame:GetFrameLevel())
      or (plate.GetFrameLevel and plate:GetFrameLevel()) or 1
    holder:SetFrameLevel(base + 10)
    plate.mlTitle = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plate.mlTitle:SetShadowOffset(1, -1)
    labeled[#labeled + 1] = plate.mlTitle
  end
  local fs = plate.mlTitle
  if not title then fs:Hide(); return end
  -- sit under the health bar (or under the name when the plate has no bar)
  local uf = plate.UnitFrame
  local anchor = uf and (uf.healthBar or uf.HealthBar or uf.name) or plate
  fs:ClearAllPoints()
  fs:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
  fs:SetText("<" .. title .. ">")
  if isRelevant(title) then fs:SetTextColor(1, 0.82, 0.3) else fs:SetTextColor(0.75, 0.75, 0.75) end
  fs:Show()
end

local function hidePlateTitle(unit)
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
  if plate then plate.mlDone = nil end
  if plate and plate.mlTitle then plate.mlTitle:Hide() end
end

local function hideAllPlateTitles()
  for _, fs in ipairs(labeled) do fs:Hide() end
end

local function distanceTo(s)
  local w = where()
  if not (w.x and s.x) or w.mapID ~= s.mapID then return nil end
  local dx, dy = s.x - w.x, s.y - w.y
  return math.sqrt(dx * dx + dy * dy)
end

local function todoList(all)
  local opened, list = openedIds(), {}
  local zone = GetRealZoneText() or GetZoneText()
  for id, s in pairs(ForeverArtisanContactsDB.scouted or {}) do
    if isRelevant(s.title) and wantedHere(s.title) and not opened[id] and (all or s.zone == zone) then
      list[#list + 1] = { id = id, s = s, d = distanceTo(s) or 1e9 }
    end
  end
  table.sort(list, function(a, b) return a.d < b.d end)
  return list
end

local SCOUT_CVARS = { "nameplateShowFriends", "nameplateShowFriendlyNPCs" }
local function setScoutPlates(on)
  ForeverArtisanContactsDB.savedCVars = ForeverArtisanContactsDB.savedCVars or {}
  for _, cv in ipairs(SCOUT_CVARS) do
    local ok, cur = pcall(GetCVar, cv)
    if ok and cur ~= nil then
      if on then
        if ForeverArtisanContactsDB.savedCVars[cv] == nil then ForeverArtisanContactsDB.savedCVars[cv] = cur end
        pcall(SetCVar, cv, "1")
      elseif ForeverArtisanContactsDB.savedCVars[cv] ~= nil then
        pcall(SetCVar, cv, ForeverArtisanContactsDB.savedCVars[cv])
        ForeverArtisanContactsDB.savedCVars[cv] = nil
      end
    end
  end
end

-- Scout mode (NPC names and titles in town) for the slash command and the window checkbox.
function ns.ScoutOn() return ForeverArtisanContactsDB and not ForeverArtisanContactsDB.scoutOff end
function ns.SetScout(on)
  if not ForeverArtisanContactsDB then return end
  if on then
    ForeverArtisanContactsDB.scoutOff = nil
    setScoutPlates(true)
    startScoutTicker()
  else
    setScoutPlates(false)
    ForeverArtisanContactsDB.scoutOff = true
    pcall(hideAllPlateTitles)
  end
end
function ns.IsRelevant(title) return isRelevant(title) end
function ns.IsIgnored(title) return isIgnored(title) end
function ns.ClassTrainer(title) return classTrainer(title) end
function ns.WantedHere(title) return wantedHere(title) end

-- What the "Show NPC names in town" checkbox does, for its hover tooltip (both checkboxes use this).
function ns.ScoutTip(tt)
  local total, rel = 0, 0
  for _, s in pairs((ForeverArtisanContactsDB and ForeverArtisanContactsDB.scouted) or {}) do
    total = total + 1; if isRelevant(s.title) then rel = rel + 1 end
  end
  tt:AddLine("Show NPC names in town")
  tt:AddLine("Shows friendly NPC names with their job under them, like <Leatherworking Trainer>.", 1, 1, 1, true)
  tt:AddLine(" ")
  tt:AddLine("Walk or ride through a town and every crafting vendor and trainer you pass is noted, " ..
    "even before you talk to them. Search shows them as \"seen, talk to save\" with a waypoint.", 1, 1, 1, true)
  tt:AddLine("Talk to one to save its full list and prices.", 1, 1, 1, true)
  tt:AddLine(" ")
  tt:AddLine("Turn it off and your own nameplate settings come back.", 0.6, 0.6, 0.6, true)
  tt:AddLine("Open world only: the game hides nameplates in dungeons.", 0.6, 0.6, 0.6, true)
  tt:AddLine(" ")
  tt:AddLine(total .. " NPCs seen so far, " .. rel .. " of them crafting-related.", 1, 0.82, 0)
end

-- Checkbox version of /fa contacts scout: same switch, plus one line in chat so people see it worked.
function ns.SetScoutFromUI(on)
  ns.SetScout(on)
  if on then say("names in town on. Ride through a town and crafting NPCs are noted as you pass.")
  else say("names in town off. Your nameplate settings are back.") end
end

---------------------------------------------------------------- events

-- Register safely: an event this client doesn't have is skipped instead of
-- breaking the whole addon (Forever uses the modern profession events).
local missingEvents = {}
for _, ev in ipairs({
  "ADDON_LOADED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRAINER_SHOW", "GOSSIP_SHOW",
  "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW",
  "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "PLAYER_LOGIN",
}) do
  if not pcall(f.RegisterEvent, f, ev) then missingEvents[#missingEvents + 1] = ev end
end

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    -- carry over data from the old Logger module (and its Matsledger predecessor)
    ForeverArtisan.Migrate("ForeverArtisanContactsDB", "ForeverArtisanLoggerDB")
    ForeverArtisan.Migrate("ForeverArtisanContactsDB", "MatsLedgerDB")
    ForeverArtisanContactsDB = ForeverArtisanContactsDB or {}
    ForeverArtisanContactsDB.version = DB_VERSION
    ForeverArtisanContactsDB.entries = ForeverArtisanContactsDB.entries or {}
    -- What this client supports, so the data can be interpreted (and the addon adapted).
    ForeverArtisanContactsDB.diag = ForeverArtisanContactsDB.diag or {}
    ForeverArtisanContactsDB.diag.missingEvents = table.concat(missingEvents, ",")
    ForeverArtisanContactsDB.diag.hasOldTradeSkillAPI = GetNumTradeSkills and true or false
    ForeverArtisanContactsDB.diag.hasCTradeSkillUI = (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) and true or false
    ForeverArtisanContactsDB.diag.hasRecipeSchematic = (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) and true or false
    ForeverArtisanContactsDB.diag.build = select(4, GetBuildInfo())
    -- every game build this account has run, oldest first (used for "before the last update")
    local db = ForeverArtisanContactsDB
    db.builds = db.builds or {}
    if db.builds[#db.builds] ~= CUR_BUILD then db.builds[#db.builds + 1] = CUR_BUILD end
    while #db.builds > 20 do table.remove(db.builds, 1) end
    for _, e in pairs(db.entries) do
      if not e.build then e.build = CUR_BUILD; e.seenAt = e.seenAt or e.lastSeen end
    end
    ForeverArtisanContactsDB.settings = ForeverArtisanContactsDB.settings or {}
    if ForeverArtisanContactsDB.settings.tooltips == nil then ForeverArtisanContactsDB.settings.tooltips = true end
    if ns.OnContactsChanged then ns.OnContactsChanged() end
    return
  end
  if not ForeverArtisanContactsDB then return end
  -- scout mode: quiet, cheap, never errors out loud
  if event == "PLAYER_LOGIN" then startScoutTicker(); return end
  if event == "NAME_PLATE_UNIT_REMOVED" then pcall(hidePlateTitle, arg1); return end
  if event == "NAME_PLATE_UNIT_ADDED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
    if ForeverArtisanContactsDB.scoutOff then return end
    local unit = (event == "NAME_PLATE_UNIT_ADDED" and arg1) or (event == "UPDATE_MOUSEOVER_UNIT" and "mouseover") or "target"
    if not InCombatLockdown() then pcall(scoutUnit, unit) end
    if event == "NAME_PLATE_UNIT_ADDED" and not InCombatLockdown() then pcall(plateTitle, unit) end
    return
  end
  if event:find("TRADE_SKILL") or event == "CRAFT_SHOW" then
    ForeverArtisanContactsDB.diag.events = ForeverArtisanContactsDB.diag.events or {}
    ForeverArtisanContactsDB.diag.events[event] = (ForeverArtisanContactsDB.diag.events[event] or 0) + 1
  end
  local ok, err = pcall(function()
    if event == "MERCHANT_SHOW" then scanMerchant()
    elseif event == "MERCHANT_CLOSED" then
      -- closed before the last pass: data is already saved, just report it
      finishMerchant()
    elseif event == "TRAINER_SHOW" then scanTrainer()
    elseif event == "GOSSIP_SHOW" then logGossip()
    -- full recipe dumps are research data for the website; only in dev mode (/fa contacts dev)
    elseif not ForeverArtisanContactsDB.dev then return
    elseif event == "TRADE_SKILL_SHOW" then scanProfessionSoon("trade", true)
    elseif event == "TRADE_SKILL_UPDATE" or event == "TRADE_SKILL_LIST_UPDATE" then
      local frame = ProfessionsFrame or TradeSkillFrame
      if frame and frame:IsShown() then scanProfessionSoon("trade", false) end
    elseif event == "CRAFT_SHOW" then scanProfessionSoon("craft", true)
    end
  end)
  if not ok then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "|cffff5555error:|r " .. tostring(err)) end
end)

---------------------------------------------------------------- slash commands

SLASH_FACONTACTS1 = "/facontacts"
SlashCmdList.FACONTACTS = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "help" then
    local v, t = 0, 0
    for _, e in pairs(ForeverArtisanContactsDB.entries) do
      if e.kind == "vendor" then v = v + 1 elseif e.kind == "trainer" then t = t + 1 end
    end
    say(("%d vendors and %d trainers saved on this account."):format(v, t))
    DEFAULT_CHAT_FRAME:AddMessage("  Talk to a crafting vendor or profession trainer and they're saved. Only NPCs you've met show up.")
    DEFAULT_CHAT_FRAME:AddMessage("  /fa contacts  - open the window (search, contacts)")
    DEFAULT_CHAT_FRAME:AddMessage("  /fa <item or vendor>  - search, e.g. /fa silk thread")
    DEFAULT_CHAT_FRAME:AddMessage("  /fa contacts tooltips  - 'Sold by' lines on item tooltips on/off")
    DEFAULT_CHAT_FRAME:AddMessage("  Search tab: 'Show NPC names in town' finds crafting NPCs as you pass; 'Only not visited' lists the ones to talk to, nearest first")
    DEFAULT_CHAT_FRAME:AddMessage("  /fa contacts forget <name>  - remove one contact (or right-click it twice on the Contacts tab)")
    DEFAULT_CHAT_FRAME:AddMessage("  /fa contacts note <text>  - add a note to the last contact  ·  /fa contacts quiet  - chat messages on/off")
    DEFAULT_CHAT_FRAME:AddMessage("  /fa contacts clear confirm  - forget everyone")
  elseif cmd == "tooltips" then
    local st = ForeverArtisanContactsDB.settings
    st.tooltips = not st.tooltips
    say("'Sold by' tooltip lines " .. (st.tooltips and "on." or "off."))
  elseif cmd == "forget" then
    local q = rest:lower()
    local hits = {}
    if q ~= "" then
      for k, e in pairs(ForeverArtisanContactsDB.entries) do
        if (e.kind == "vendor" or e.kind == "trainer") and e.name and e.name:lower() == q then hits[#hits + 1] = k end
      end
    end
    if #hits == 0 then say("no contact called '" .. rest .. "'. Use the exact name, or right-click it twice on the Contacts tab.") end
    for _, k in ipairs(hits) do ns.Forget(k) end
  elseif cmd == "dev" then
    ForeverArtisanContactsDB.dev = not ForeverArtisanContactsDB.dev or nil
    say("dev mode " .. (ForeverArtisanContactsDB.dev and "on: profession windows are saved in full for the website." or "off."))
  elseif cmd == "npc" then
    if not UnitExists("target") or UnitIsPlayer("target") then
      say("target an NPC first.")
    else
      logService(rest ~= "" and rest or "npc", "target")
    end
  elseif cmd == "note" then
    local last, lastKey
    for k, e in pairs(ForeverArtisanContactsDB.entries) do
      if not last or (e.lastSeen or 0) > (last.lastSeen or 0) then last, lastKey = e, k end
    end
    if last and rest ~= "" then
      last.notes = last.notes and (last.notes .. " | " .. rest) or rest
      say("note added to " .. (last.name or lastKey))
    else
      say("nothing to add a note to yet.")
    end
  elseif cmd == "scout" then
    if rest == "off" then
      ns.SetScout(false)
      say("scout mode off - nameplate settings restored.")
    else
      ns.SetScout(true)
      local total, rel = 0, 0
      for _, s in pairs(ForeverArtisanContactsDB.scouted or {}) do total = total + 1; if isRelevant(s.title) then rel = rel + 1 end end
      say("scout mode on - friendly NPC nameplates shown. Ride through town; NPCs log as you pass. (" ..
        total .. " seen so far, " .. rel .. " crafting-related). /fa contacts scout off to restore your settings.")
    end
  elseif cmd == "todo" then
    local list = todoList(rest == "all")
    -- explain the count so a zero is never a mystery
    local zone = GetRealZoneText() or GetZoneText()
    local opened = openedIds()
    local seen, rel, done = 0, 0, 0
    for id, s in pairs(ForeverArtisanContactsDB.scouted or {}) do
      if rest == "all" or s.zone == zone then
        seen = seen + 1
        if isRelevant(s.title) then rel = rel + 1; if opened[id] then done = done + 1 end end
      end
    end
    local plates = GetCVar and (GetCVar("nameplateShowFriendlyNPCs") or "?") or "?"
    say(string.format("%s: %d NPCs scouted, %d crafting-related, %d of those already opened. Friendly NPC nameplates: %s",
      rest == "all" and "Everywhere" or zone, seen, rel, done, plates == "1" and "on" or "OFF (type /fa contacts scout)"))
    if #list == 0 then
      say("nothing left to open" .. (rest == "all" and "" or " in this zone") .. ". Ride around with /fa contacts scout to find more.")
    else
      say(#list .. " crafting NPCs seen but not opened" .. (rest == "all" and "" or " here") .. ", nearest first:")
      for i = 1, math.min(#list, 15) do
        local s = list[i].s
        local where_ = (rest == "all") and (" - " .. (s.subzone or s.zone or "")) or ""
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s <%s> %.1f, %.1f%s", s.name, s.title or "?", s.x, s.y, where_))
      end
      if #list > 15 then DEFAULT_CHAT_FRAME:AddMessage("  ...and " .. (#list - 15) .. " more.") end
      if rest == "way" then
        if TomTom and TomTom.AddWaypoint then
          for _, it in ipairs(list) do
            local s = it.s
            if s.mapID then TomTom:AddWaypoint(s.mapID, s.x / 100, s.y / 100, { title = s.name .. " <" .. (s.title or "") .. ">", persistent = false }) end
          end
          say("TomTom waypoints added for all " .. #list .. ".")
        else
          say("TomTom isn't loaded, so no waypoints - use the coordinates above.")
        end
      end
    end
  elseif cmd == "skip" or cmd == "unskip" then
    local on = (cmd == "skip")
    local target
    if rest == "" and on then
      local list = todoList(false)
      target = list[1] and list[1].s
    else
      local q = rest:lower()
      local zone = GetRealZoneText() or GetZoneText()
      for _, s in pairs(ForeverArtisanContactsDB.scouted or {}) do
        if s.name and s.name:lower():find(q, 1, true) and (not target or (s.zone == zone and target.zone ~= zone)) then target = s end
      end
    end
    if target then
      target.skip = on or nil
      say((on and "skipped " or "back on the todo list: ") .. target.name .. " <" .. (target.title or "?") .. ">")
    else
      say(on and "nothing to skip - use /fa contacts skip <name>, or /fa contacts skip for the nearest todo NPC." or "no scouted NPC matches that name.")
    end
  elseif cmd == "prof" then
    say("scanning the open profession window...")
    scanProfessionSoon("trade", true)
    C_Timer.After(2, function()
      local D = ForeverArtisanContactsDB.diag.lastProfScan
      if D then
        say("debug: name=" .. tostring(D.profName) .. " skill=" .. tostring(D.rank) .. "/" .. tostring(D.maxRank) ..
          " recipeIds=" .. tostring(D.numRecipeIDs) .. " result=" .. tostring(D.result))
      else
        say("debug: the modern profession scan didn't run (old-style window?).")
      end
    end)
  elseif cmd == "quiet" then
    ForeverArtisanContactsDB.quiet = not ForeverArtisanContactsDB.quiet
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "chat messages " .. (ForeverArtisanContactsDB.quiet and "off" or "on"))
  elseif cmd == "clear" then
    if rest == "confirm" then
      ForeverArtisanContactsDB.entries = {}
      if ns.OnContactsChanged then ns.OnContactsChanged() end
      say("cleared.")
    else
      say("type /fa contacts clear confirm to erase everything.")
    end
  else
    say("unknown command. Type /fa contacts help.")
  end
end

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(f)
