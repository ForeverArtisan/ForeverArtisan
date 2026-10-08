-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: what materials cost, for the crafting plans' shopping lists.
-- Works with no other addon. Prices come from, in order:
--   1. Auctionator's last scan, when Auctionator is installed (read through its public API)
--   2. ForeverArtisan's own price memory: the cheapest buyout per item on Auction House pages
--      you looked at yourself (we only read what's on your screen; we never search or buy)
--   3. A vendor in your Trade Contacts, when that's cheaper than the Auction House
-- FA.SearchAH(name) only types a name into the Auction House search box. You press Search.
local FA = ForeverArtisan

local KEEP_DAYS = 30   -- older prices are forgotten
local FRESH = 30 * 60  -- a page seen within half an hour of the last one keeps the lower price
local MAX_ITEMS = 3000

local function Secret(v) return FA.IsSecret(v) end
local function GRAY_LINE(t) return (FA.GRAY or "|cff9d9d9d") .. t .. "|r" end

-- The goblin Auction Houses (Booty Bay, Gadgetzan, Everlook) have their own listings and take 15%.
local NEUTRAL = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }
function FA.AtNeutralAH()
  local z = GetMinimapZoneText and GetMinimapZoneText()
  if type(z) ~= "string" or Secret(z) then return false end
  return NEUTRAL[z] or false
end
FA.NEUTRAL_CUT = 0.15

-- One price memory per realm and Auction House: your faction's, or the goblin houses' ("Neutral").
local function HouseKey(neutral)
  local realm = (GetRealmName and GetRealmName()) or "realm"
  if Secret(realm) then realm = "realm" end
  local faction = (UnitFactionGroup and UnitFactionGroup("player")) or ""
  if Secret(faction) then faction = "" end
  return realm .. "-" .. (neutral and "Neutral" or faction)
end
local function Store(neutral)
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.prices = s.prices or {}
  local key = HouseKey(neutral)
  s.prices[key] = s.prices[key] or {}
  return s.prices[key]
end

---------------------------------------------------------------- remembering prices
-- one cheapest buyout per item per unit, in copper
function FA.NotePrice(id, unit)
  if not (id and unit) or Secret(id) or Secret(unit) then return end
  id, unit = tonumber(id), tonumber(unit)
  if not id or not unit or unit <= 0 then return end
  local p, now = Store(FA.AtNeutralAH()), time()
  local e = p[id]
  if e and now - (e.t or 0) < FRESH then
    if unit < e.p then e.p = unit end
    e.t = now
  else
    p[id] = { p = math.floor(unit + 0.5), t = now }
  end
end

---------------------------------------------------------------- price history (for Best crafts)
-- Per item and day: the lowest unit price and how many were listed, for the items your recipes
-- use or make. 14 days, so saved data stays small. Fed by the same pages as the price memory.
local HISTORY_DAYS = 14
local watched = {}
function FA.WatchItems(ids)
  for _, id in ipairs(ids or {}) do id = tonumber(id); if id then watched[id] = true end end
end
local function Day() return math.floor(time() / 86400) end
FA.Day = Day
local function History(neutral)
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.market = s.market or {}
  local key = HouseKey(neutral)
  s.market[key] = s.market[key] or {}
  return s.market[key]
end
function FA.NoteMarket(id, unit, qty)
  id, unit, qty = tonumber(id), tonumber(unit), tonumber(qty)
  if not id or not watched[id] or not unit or unit <= 0 then return end
  local h = History(FA.AtNeutralAH())
  h[id] = h[id] or {}
  local d = Day()
  local e = h[id][d]
  if not e then h[id][d] = { p = math.floor(unit + 0.5), q = qty }
  else
    if unit < e.p then e.p = math.floor(unit + 0.5) end
    if qty and (not e.q or qty > e.q) then e.q = qty end
  end
end
local function PruneHistory()
  local s = ForeverArtisanSettings
  if not (s and s.market) then return end
  local cut = Day() - HISTORY_DAYS
  for _, house in pairs(s.market) do
    for id, days in pairs(house) do
      for d in pairs(days) do if d < cut then days[d] = nil end end
      if next(days) == nil then house[id] = nil end
    end
  end
end

-- How much to trust an item's price: { level = "good" | "ok" | "shaky", age, listed, low, high }.
-- good: seen today or yesterday, 10+ listed, and the week's low and high within 3x of each other.
function FA.PriceConfidence(id, neutral)
  id = tonumber(id)
  local info = {}
  local h = id and History(neutral)[id]
  local today, last, q, lo, hi = Day()
  for d, e in pairs(h or {}) do
    if today - d <= 7 then
      lo = (not lo or e.p < lo) and e.p or lo
      hi = (not hi or e.p > hi) and e.p or hi
      if not last or d > last then last, q = d, e.q end
    end
  end
  if last then
    info.age, info.listed, info.low, info.high = today - last, q, lo, hi
    local swing = (lo and lo > 0) and (hi / lo) or 1
    if info.age <= 1 and (q or 0) >= 10 and swing <= 3 then info.level = "good"
    elseif info.age <= 3 and (q or 0) >= 3 then info.level = "ok"
    else info.level = "shaky" end
  else
    local ah, age
    if neutral then
      local e = id and Store(true)[id]
      if e then ah, age = e.p, math.floor((time() - (e.t or 0)) / 86400) end
    else
      ah, _, age = FA.AHPrice(id)
    end
    info.age = age
    info.level = (ah and age and age <= 1) and "ok" or "shaky"
  end
  return info
end

local function Prune()
  local p, now, n = Store(), time(), 0
  for id, e in pairs(p) do
    if now - (e.t or 0) > KEEP_DAYS * 86400 then p[id] = nil else n = n + 1 end
  end
  if n > MAX_ITEMS then
    local list = {}
    for id, e in pairs(p) do list[#list + 1] = { id = id, t = e.t or 0 } end
    table.sort(list, function(a, b) return a.t < b.t end)
    for i = 1, n - MAX_ITEMS do p[list[i].id] = nil end
  end
end

---------------------------------------------------------------- listen test (/fa ahtest)
-- Hidden check: which Auction House results ForeverArtisan can hear while you, or another addon
-- (Auctionator's full scan), search. It only reads results the game already handed out; it never
-- starts a search. Kept in memory for this session only.
local T
local function TestReset()
  T = { ev = {}, ids = {}, nIds = 0, withQty = 0, biggest = 0, replicate = 0, replicateRead = 0, slowMs = 0 }
  FA.AHTest = T
end
TestReset()
local function Heard(id, qty)
  if not id or Secret(id) or T.ids[id] then return end
  T.ids[id] = true
  T.nIds = T.nIds + 1
  if qty and not Secret(qty) and qty > 0 then T.withQty = T.withQty + 1 end
end
local Clock = debugprofilestop or function() return 0 end

-- Classic-style Auction House: the page of results on screen
local function ReadLegacyPage()
  if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
  local n = GetNumAuctionItems("list")
  if not n or Secret(n) then return end
  if n > T.biggest then T.biggest = n end
  local cheapest, listed = {}, {}
  for i = 1, n do
    local r = { GetAuctionItemInfo("list", i) }
    local count, buyout, id = r[3], r[10], r[17]
    if id and count and buyout and not (Secret(id) or Secret(count) or Secret(buyout))
      and buyout > 0 and count > 0 then
      local unit = buyout / count
      if not cheapest[id] or unit < cheapest[id] then cheapest[id] = unit end
      listed[id] = (listed[id] or 0) + count
      Heard(id, count)
    end
  end
  for id, unit in pairs(cheapest) do FA.NotePrice(id, unit); FA.NoteMarket(id, unit, listed[id]) end
end

-- Newer Auction House (C_AuctionHouse): browse list, commodity and item results
local function ReadBrowse()
  local AH = C_AuctionHouse
  if not (AH and AH.GetBrowseResults) then return end
  local ok, list = pcall(AH.GetBrowseResults)
  if not ok or type(list) ~= "table" then return end
  if #list > T.biggest then T.biggest = #list end
  for _, r in ipairs(list) do
    local id = r.itemKey and r.itemKey.itemID
    if r.minPrice and r.minPrice > 0 and not Secret(r.minPrice) then
      FA.NotePrice(id, r.minPrice)
      FA.NoteMarket(id, r.minPrice, not Secret(r.totalQuantity) and r.totalQuantity or nil)
    end
    Heard(id, r.totalQuantity)
  end
end
local function ReadCommodity(id)
  local AH = C_AuctionHouse
  if not (id and AH and AH.GetCommoditySearchResultInfo) then return end
  local ok, r = pcall(AH.GetCommoditySearchResultInfo, id, 1)
  if ok and type(r) == "table" and r.unitPrice then FA.NotePrice(id, r.unitPrice); FA.NoteMarket(id, r.unitPrice); Heard(id, r.quantity) end
end
-- A full scan on the newer Auction House arrives as a "replicate" list. The test only counts it,
-- a slice at a time so a big scan never stalls the game.
local function ReadReplicate()
  local AH = C_AuctionHouse
  if not (AH and AH.GetNumReplicateItems and AH.GetReplicateItemInfo) then return end
  local ok, n = pcall(AH.GetNumReplicateItems)
  if not ok or not n or Secret(n) then return end
  if n > T.replicate then T.replicate = n end
  local i = 0
  local function slice()
    local stop = math.min(n, i + 1000)
    for k = i, stop - 1 do
      local ok2, _, _, count, _, _, _, _, _, _, _, _, _, _, _, _, _, id = pcall(AH.GetReplicateItemInfo, k)
      if ok2 then T.replicateRead = T.replicateRead + 1; Heard(id, count) end
    end
    i = stop
    if i < n then
      if C_Timer and C_Timer.After then C_Timer.After(0, slice) end
    end
  end
  slice()
end
local function ReadItem(itemKey)
  local AH = C_AuctionHouse
  if not (type(itemKey) == "table" and AH and AH.GetItemSearchResultInfo) then return end
  local ok, r = pcall(AH.GetItemSearchResultInfo, itemKey, 1)
  if ok and type(r) == "table" and r.buyoutAmount and r.buyoutAmount > 0 then
    FA.NotePrice(itemKey.itemID, r.buyoutAmount / math.max(1, r.quantity or 1))
    FA.NoteMarket(itemKey.itemID, r.buyoutAmount / math.max(1, r.quantity or 1))
  end
end

-- open crafting windows refresh their shopping lists, at most once a second while you browse
FA.PriceWatchers = FA.PriceWatchers or {}
local queued = false
function FA.PricesChanged()
  if queued then return end
  queued = true
  local function run()
    queued = false
    for _, fn in ipairs(FA.PriceWatchers) do pcall(fn) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(1, run) else run() end
end

-- Item details (stack size, vendor price, name) can arrive a moment after a list first draws.
-- Ask the game for the ones still missing, and redraw once they're in, so numbers don't change
-- the next time you happen to click something.
local waiting = {}
local function ItemLoaded(id)
  local Info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not (Info and id) then return true end
  local ok, name = pcall(Info, id)
  return ok and name ~= nil
end
function FA.WaitForItem(id)
  id = tonumber(id)
  if not id or waiting[id] or ItemLoaded(id) then return end
  waiting[id] = true
  local Req = C_Item and C_Item.RequestLoadItemDataByID
  if Req then pcall(Req, id) end
end
local itemEv = CreateFrame("Frame")
pcall(itemEv.RegisterEvent, itemEv, "GET_ITEM_INFO_RECEIVED")
function FA.OnItemInfo(id)
  id = tonumber(id)
  if id and waiting[id] then waiting[id] = nil; FA.PricesChanged() end
end
itemEv:SetScript("OnEvent", function(_, _, id) FA.OnItemInfo(id) end)
FA.GuardEvents(itemEv)

local ev = CreateFrame("Frame")
local REG = {}
for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
  "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
  "REPLICATE_ITEM_LIST_UPDATE" }) do
  REG[e] = pcall(ev.RegisterEvent, ev, e) and true or false
end
ev:SetScript("OnEvent", function(_, e, a1)
  if e ~= "PLAYER_LOGIN" then T.ev[e] = (T.ev[e] or 0) + 1 end
  local t0 = Clock()
  if e == "PLAYER_LOGIN" then Prune(); PruneHistory()
  elseif e == "REPLICATE_ITEM_LIST_UPDATE" then ReadReplicate(); return
  elseif e == "AUCTION_ITEM_LIST_UPDATE" then ReadLegacyPage()
  elseif e == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or e == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then ReadBrowse()
  elseif e == "COMMODITY_SEARCH_RESULTS_UPDATED" then ReadCommodity(a1)
  elseif e == "ITEM_SEARCH_RESULTS_UPDATED" then ReadItem(a1)
  end
  local ms = Clock() - t0
  if ms > T.slowMs then T.slowMs = ms end
  if e ~= "PLAYER_LOGIN" then FA.PricesChanged() end
end)

-- /fa ahtest: what ForeverArtisan heard this session. /fa ahtest reset starts over.
function FA.AHTestReport(arg)
  local say = function(t) print("|cffffd200ForeverArtisan|r " .. t) end
  if arg == "reset" then TestReset(); say("AH listen test reset. Open the Auction House and scan."); return end
  local ev = {}
  for e, n in pairs(T.ev) do ev[#ev + 1] = e .. " x" .. n end
  table.sort(ev)
  say("AH listen test (this session, cleared by /reload):")
  print("  Events heard: " .. (#ev > 0 and table.concat(ev, ", ") or "none"))
  print(("  Different items heard: %d (%d with a listed count)"):format(T.nIds, T.withQty))
  print(("  Biggest result list: %d  ·  full-scan list: %d (read %d)"):format(T.biggest, T.replicate, T.replicateRead))
  print(("  Slowest read: %d ms"):format(math.floor(T.slowMs + 0.5)))
  -- what this client offers, and what a full scan left behind (still readable until the AH closes)
  local AH = C_AuctionHouse
  local has = {}
  if AH then has[#has + 1] = "C_AuctionHouse" end
  if AH and AH.ReplicateItems then has[#has + 1] = "ReplicateItems" end
  if AH and AH.GetNumReplicateItems then has[#has + 1] = "GetNumReplicateItems" end
  if QueryAuctionItems then has[#has + 1] = "QueryAuctionItems" end
  if GetNumAuctionItems then has[#has + 1] = "GetNumAuctionItems" end
  print("  Game AH functions: " .. (#has > 0 and table.concat(has, ", ") or "none"))
  local off = {}
  for e, okReg in pairs(REG) do if not okReg then off[#off + 1] = e end end
  table.sort(off)
  print("  Events the game refused: " .. (#off > 0 and table.concat(off, ", ") or "none"))
  if AH and AH.GetNumReplicateItems then
    local ok, n = pcall(AH.GetNumReplicateItems)
    print("  Full-scan list available right now: " .. (ok and not Secret(n) and tostring(n) or "not readable"))
  end
  if GetNumAuctionItems then
    local ok, n = pcall(GetNumAuctionItems, "list")
    print("  Classic result list right now: " .. (ok and not Secret(n) and tostring(n) or "not readable"))
  end
  local sv = _G.AUCTIONATOR_SAVEDVARS
  local last = type(sv) == "table" and tonumber(sv.TimeOfLastBrowseScan)
  if type(_G.Auctionator) == "table" then
    print("  Auctionator: installed" .. (last and time and ("; last full scan %d min ago"):format(math.floor((time() - last) / 60)) or ""))
  else
    print("  Auctionator: not installed")
  end
end
FA.GuardEvents(ev)

---------------------------------------------------------------- looking prices up
local function FromAuctionator(id)
  local A = _G.Auctionator
  local api = type(A) == "table" and A.API and A.API.v1
  if not (api and api.GetAuctionPriceByItemID) then return end
  local ok, price = pcall(api.GetAuctionPriceByItemID, "ForeverArtisan", id)
  if not ok or type(price) ~= "number" or price <= 0 then return end
  local age
  if api.GetAuctionAgeByItemID then
    local ok2, days = pcall(api.GetAuctionAgeByItemID, "ForeverArtisan", id)
    if ok2 and type(days) == "number" then age = days end
  end
  return price, age
end

-- cheapest vendor in your Trade Contacts, per unit
local function Vendor(id, name)
  local V = FA.Vendors
  if not (V and V.hitsForLink) then return end
  local ok, hits = pcall(V.hitsForLink, id and ("item:" .. id) or nil, name)
  if not ok or type(hits) ~= "table" then return end
  local best, who
  for _, h in ipairs(hits) do
    local it = h.item
    if it and it.p and it.p > 0 and (not id or not it.id or it.id == id) then
      local unit = it.p / (it.stack or 1)
      if not best or unit < best then best, who = unit, h.npc and h.npc.n end
    end
  end
  return best, who
end

-- the cheapest vendor you've met for an item, as a Trade Contacts entry with a place to go, or nil
function FA.VendorNPC(id, name)
  local V = FA.Vendors
  if not (V and V.hitsForLink) or not (id or name) then return end
  local ok, hits = pcall(V.hitsForLink, id and ("item:" .. id) or nil, name)
  if not ok or type(hits) ~= "table" then return end
  local best, bestUnit
  for _, h in ipairs(hits) do
    local it = h.item
    if h.npc and h.npc.m and not (it and it.train) and (not id or not (it and it.id) or it.id == id) then
      local unit = (it and it.p and it.p > 0) and (it.p / (it.stack or 1)) or math.huge
      if not best or unit < bestUnit then best, bestUnit = h.npc, unit end
    end
  end
  return best
end

-- price per unit in copper, where it came from, how many days old (nil for vendors), vendor name
-- Auction House price only (Auctionator or your own visits), no vendors: what it sells for there.
-- price per unit, where it came from, how many days old
function FA.AHPrice(id)
  id = tonumber(id)
  if not id then return end
  local ah, age = FromAuctionator(id)
  local src = ah and "Auctionator" or nil
  local e = Store()[id]
  -- Auctionator keeps one price list for every house on the realm, so a scan at Booty Bay, Gadgetzan or
  -- Everlook replaces your faction's prices. When a goblin house saw this item after your own house
  -- did, Auctionator's price is the goblin one: use what your own house last showed instead.
  local n = Store(true)[id]
  if ah and n and (n.t or 0) > ((e and e.t) or 0) then
    if not e then return end
    ah, age, src = nil, nil, nil
  end
  -- your own Auction House visit wins when it's newer than Auctionator's scan (same day: Auctionator)
  if e then
    local mine = math.floor((time() - (e.t or 0)) / 86400)
    if not ah or (age and mine < age) then ah, age, src = e.p, mine, "your Auction House visits" end
  end
  return ah, src, age
end

function FA.ItemPrice(id, name)
  if not id and not name then return end
  local ah, src, age
  if id then ah, src, age = FA.AHPrice(id) end
  local v, who = Vendor(id, name)
  if v and (not ah or v <= ah) then return v, "vendor", nil, who end
  return ah, src, age
end

---------------------------------------------------------------- showing prices
-- One line for item tooltips: the cheapest buyout you've seen at the Auction House.
-- Nil when Auctionator is installed (it shows its own), when there's no price, or when turned off
-- (/fa prices off). Vendors aren't repeated here: Trade Contacts already adds "Sold by" lines.
function FA.PriceTipsOn() return not (ForeverArtisanSettings and ForeverArtisanSettings.priceTips == false) end
function FA.TooltipPrice(id)
  id = tonumber(id)
  if not id or not FA.PriceTipsOn() then return end
  if FromAuctionator(id) or (type(_G.Auctionator) == "table" and _G.Auctionator.API) then return end
  local e = Store()[id]
  if not (e and e.p) then return end
  local days = math.floor((time() - (e.t or 0)) / 86400)
  return ("Auction House: %s each (seen %s)"):format(FA.Money(e.p), FA.AgeText(days))
end

function FA.Money(copper)
  if not copper then return "" end
  copper = math.floor(copper + 0.5)
  if copper < 0 then return "-" .. FA.Money(-copper) end
  if GetCoinTextureString then return GetCoinTextureString(copper) end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return ("%dg %ds"):format(g, s) end
  if s > 0 then return c > 0 and ("%ds %dc"):format(s, c) or ("%ds"):format(s) end
  return ("%dc"):format(c)
end

function FA.AgeText(days)
  if not days then return "" end
  if days < 1 then return "today" end
  if days < 2 then return "yesterday" end
  return ("%d days old"):format(days)
end

-- one line for a tooltip: "AH price: 12s each (Auctionator, 2 days old)"
function FA.PriceLine(id, name)
  local p, src, age, who = FA.ItemPrice(id, name)
  if not p then
    return "No price yet. Search it at the Auction House (click the row there) and it's remembered."
  end
  if src == "vendor" then return "Vendor price: " .. FA.Money(p) .. " each" .. (who and (" at " .. who) or "") end
  return ("Auction House: %s each (%s, %s)"):format(FA.Money(p), src, FA.AgeText(age))
end

-- The price line for a shopping list row's tooltip. Skipped when the item tooltip above it already
-- shows the same price (ForeverArtisan's own line, or Auctionator's).
function FA.RowPriceLine(id, name)
  local p, src = FA.ItemPrice(id, name)
  if p and src == "Auctionator" and type(_G.Auctionator) == "table" then return nil end
  if p and src == "your Auction House visits" and id and FA.TooltipPrice(id) then return nil end
  return FA.PriceLine(id, name)
end

---------------------------------------------------------------- what a craft is worth
-- what a vendor pays you for one (the game's sell price), or nil
local function VendorSell(id)
  if not id then return end
  local Info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not Info then return end
  local ok, r = pcall(function() return { Info(id) } end)
  local p = ok and r and r[11]
  if type(p) == "number" and p > 0 and not Secret(p) then return p end
end
FA.VendorSell = VendorSell

-- Tooltip lines for a recipe: what one craft's materials cost, what it sells for, and the difference.
-- Empty when nothing is known. Sale prices are before the Auction House cut.
FA.AH_CUT = 0.05

---------------------------------------------------------------- your Auction House or a goblin one
-- Booty Bay, Gadgetzan and Everlook share one set of listings and keep 15% of a sale; your faction's
-- house keeps 5%. Compare what one craft brings at each, after the cut. A house "wins" only when it
-- pays at least 25% and 50c more a craft, from a price no older than 3 days that isn't shaky. The goblin
-- house is suggested from anywhere; your own only while you stand at a goblin one.
FA.HOUSE_BETTER, FA.HOUSE_MIN, FA.HOUSE_FRESH = 1.25, 50, 3
-- Mailing it to a banker at the other house: 30c a mail slot, and a whole stack fits in one slot
FA.POSTAGE = 30
local function StackSize(id)
  local Info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not Info then return 1 end
  local ok, r = pcall(function() return { Info(id) } end)
  local n = ok and r and not Secret(r[8]) and tonumber(r[8])
  return (n and n > 0) and n or 1
end
function FA.Postage(id, makes)
  return math.ceil(FA.POSTAGE * (makes or 1) / StackSize(id))
end

function FA.HouseCompare(id, makes)
  id, makes = tonumber(id), makes or 1
  if not id then return end
  local home, _, hAge = FA.AHPrice(id)
  local g = Store(true)[id]
  if not (home and g and g.p) then return end
  local gAge = math.floor((time() - (g.t or 0)) / 86400)
  if gAge > 7 then return end
  local hc, gc = FA.PriceConfidence(id), FA.PriceConfidence(id, true)
  local c = {
    home = home, homeNet = math.floor(home * makes * (1 - FA.AH_CUT)), homeAge = hAge, homeListed = hc.listed, homeLevel = hc.level,
    gob = g.p, gobNet = math.floor(g.p * makes * (1 - FA.NEUTRAL_CUT)), gobAge = gAge, gobListed = gc.listed, gobLevel = gc.level,
  }
  -- the house you're not standing at needs a mail to your banker there
  c.postage = FA.Postage(id, makes)
  c.away = FA.AtNeutralAH() and "home" or "goblin"
  if c.away == "goblin" then c.gobNet = c.gobNet - c.postage else c.homeNet = c.homeNet - c.postage end
  local function wins(a, b, level, age)
    return a >= b * FA.HOUSE_BETTER and a - b >= FA.HOUSE_MIN and level ~= "shaky" and (age or 99) <= FA.HOUSE_FRESH
  end
  -- standing at a goblin house, only say so when your own pays more: you're already where the goblin price is
  if c.away == "goblin" and wins(c.gobNet, c.homeNet, c.gobLevel, c.gobAge) then
    c.better, c.diff = "goblin", c.gobNet - c.homeNet
  elseif c.away == "home" and wins(c.homeNet, c.gobNet, c.homeLevel, c.homeAge) then
    c.better, c.diff = "home", c.homeNet - c.gobNet
  end
  return c
end

-- short tag for a Best crafts row: "better at goblin AH: +16s", or nil when neither house clearly wins
function FA.HouseTag(c)
  if not (c and c.better) then return end
  return (c.better == "goblin" and "better at goblin AH: +" or "better at your AH: +") .. FA.Money(c.diff)
end

-- "Where to sell" tooltip lines: both houses after their cuts, and which pays more
function FA.HouseLines(id, makes)
  local c = FA.HouseCompare(id, makes)
  if not c then return {} end
  local function line(name, each, net, cut, age, listed, mailed)
    local bits = { FA.AgeText(age) }
    if listed then bits[#bits + 1] = listed .. " listed" end
    return ("%s: %s each, about %s a craft after its %d%% cut%s"):format(name, FA.Money(each), FA.Money(net), cut,
      mailed and " and postage" or "") .. FA.GRAY .. " (" .. table.concat(bits, ", ") .. ")|r"
  end
  local lines = { FA.GOLD .. "Where to sell|r",
    line("Your Auction House", c.home, c.homeNet, math.floor(FA.AH_CUT * 100 + 0.5), c.homeAge, c.homeListed, c.away == "home"),
    line("Goblin Auction House", c.gob, c.gobNet, math.floor(FA.NEUTRAL_CUT * 100 + 0.5), c.gobAge, c.gobListed, c.away == "goblin") }
  if c.better == "goblin" then
    lines[#lines + 1] = FA.GREEN .. "The goblin Auction House pays about " .. FA.Money(c.diff) .. " more a craft|r"
      .. FA.GRAY .. " (Booty Bay, Gadgetzan, Everlook)|r"
  elseif c.better == "home" then
    lines[#lines + 1] = FA.GREEN .. "Your own Auction House pays about " .. FA.Money(c.diff) .. " more a craft|r"
  end
  lines[#lines + 1] = FA.GRAY .. ("Postage to a banker there: %s a craft (30c a mail slot, a full stack fits in one)."):format(FA.Money(c.postage)) .. "|r"
  return lines
end

function FA.CraftValueLines(r)
  local lines = {}
  if not r then return lines end
  local makes = r.makes or 1
  local cost = FA.CraftMoney and FA.CraftMoney(r)
  local ah, src, age = FA.AHPrice(r.itemId)
  local vend = VendorSell(r.itemId)
  if not (cost or ah or vend) then return lines end
  lines[#lines + 1] = FA.GOLD .. "What it's worth|r"
  if cost then lines[#lines + 1] = "Materials: about " .. FA.Money(cost) .. " a craft" end
  if ah then
    lines[#lines + 1] = ("Auction House: about %s each%s (%s, %s)"):format(FA.Money(ah),
      makes > 1 and (", makes " .. makes) or "", src, FA.AgeText(age))
  end
  if vend then lines[#lines + 1] = "Vendors pay " .. FA.Money(vend) .. " each" end
  if cost then
    -- the Auction House keeps 5% of a sale (your faction's house), so profit is what you'd actually get
    local best, where = nil, nil
    if ah then best, where = math.floor(ah * makes * (1 - FA.AH_CUT)), "at the Auction House, after its 5% cut" end
    if vend and (not best or vend * makes > best) then best, where = vend * makes, "to a vendor" end
    if best then
      local d = best - cost
      if d >= 0 then
        lines[#lines + 1] = FA.GREEN .. "Profit: about " .. FA.Money(d) .. " a craft|r" .. FA.GRAY .. " (" .. where .. ")|r"
      else
        lines[#lines + 1] = FA.GRAY .. "Costs about " .. FA.Money(-d) .. " more than it sells for (" .. where .. ")|r"
      end
    end
  end
  local house = FA.HouseLines(r.itemId, makes)
  if #house > 0 then
    lines[#lines + 1] = " "
    for _, l in ipairs(house) do lines[#lines + 1] = l end
  end
  return lines
end

---------------------------------------------------------------- shopping list totals
-- give each thing on a shopping list its price (things you craft yourself along the way don't need one)
function FA.PriceShopping(shopping)
  for _, e in ipairs(shopping or {}) do
    if not e.craft and not e.train then e.price, e.priceSrc, e.priceAge = FA.ItemPrice(e.id, e.name) end
  end
end

-- What the shopping list still costs to buy: total copper, how many missing things have no price,
-- the oldest Auction House price used (days) and how many different things you still need to buy.
-- Things you craft yourself along the way aren't counted (their materials are).
function FA.ShopCost(shopping)
  local total, unpriced, oldest, buying = 0, 0, nil, 0
  for _, e in ipairs(shopping or {}) do
    local buy = (e.need or 0) - (e.have or 0)
    if buy > 0 and not e.craft then
      buying = buying + 1
      if e.price then
        total = total + e.price * buy
        if e.priceAge and (not oldest or e.priceAge > oldest) then oldest = e.priceAge end
      else
        unpriced = unpriced + 1
      end
    end
  end
  return total, unpriced, oldest, buying
end

-- "To buy what's missing: about 4g 20s (Auction House prices up to 2 days old). 3 items have no price yet."
function FA.ShopCostText(shopping)
  local total, unpriced, oldest, buying = FA.ShopCost(shopping)
  if buying == 0 then return nil end
  if unpriced == buying then
    return "No prices yet. Open the Auction House and click a shopping list item to search it."
  end
  local t = "To buy what's missing: about " .. FA.Money(total)
  if oldest then
    local a = (oldest < 1 and "from today") or (oldest < 2 and "from yesterday") or ("up to %d days old"):format(oldest)
    t = t .. " (Auction House prices " .. a .. ")"
  end
  if unpriced > 0 then t = t .. (". %d item%s with no price yet"):format(unpriced, unpriced == 1 and "" or "s") end
  return t .. "."
end

---------------------------------------------------------------- Best crafts
-- Rank a module's learned recipes. mode: "profit" (most profit per craft after the Auction House
-- cut), "level" (cheapest per skill point, recipes that still give skill-ups) or "both" (skill-ups
-- that also make money). chanceOf(r) is the module's skill-up chance for the recipe right now.
-- Rows: { r, cost, sale, vend, chance, profit, perPoint, conf }
-- recipes Best crafts leaves out: Basic Campfire makes a kit, but it needs Flint and Tinder and has a
-- cooldown, so it's no way to earn or level
local BEST_SKIP = { ["Basic Campfire"] = true }

function FA.BestCrafts(recipes, chanceOf, mode)
  local out, makes, memo = {}, {}, {}
  for _, r in pairs(recipes or {}) do if r.learned and r.itemId then makes[r.itemId] = r end end
  for _, r in pairs(recipes or {}) do
    if r.learned and r.itemId and not BEST_SKIP[r.name] then
      FA.WaitForItem(r.itemId)
      for _, g in ipairs(r.reagents or {}) do FA.WaitForItem(g.id) end
      local n = r.makes or 1
      -- materials at what they cost to buy; one with no price counts at what it costs you to make
      local cost = FA.CraftMoney and (FA.CraftMoney(r) or FA.CraftMoney(r, makes, memo))
      local ah = FA.AHPrice(r.itemId)
      local vend = VendorSell(r.itemId)
      local best = math.max(ah and math.floor(ah * (1 - FA.AH_CUT)) or 0, vend or 0) * n
      local ch = (chanceOf and chanceOf(r)) or 0
      local row = { r = r, cost = cost, sale = ah, vend = vend, chance = ch }
      if cost and best > 0 then row.profit = best - cost end
      if cost and ch > 0 then row.perPoint = (cost - best) / ch end
      local keep = (mode == "level" and row.perPoint) or (mode == "both" and row.perPoint and (row.profit or 0) > 0)
        or ((mode == "profit" or not mode) and row.profit)
      if keep then
        row.conf = FA.PriceConfidence(r.itemId)
        out[#out + 1] = row
      end
    end
  end
  table.sort(out, function(a, b)
    if mode == "level" then
      if a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
    elseif a.profit ~= b.profit then return a.profit > b.profit end
    return (a.r.name or "") < (b.r.name or "")
  end)
  return out
end

-- Where Best crafts' prices come from, for the line at the top of the tab.
function FA.PriceSourceLines()
  local n = 0
  for _ in pairs(Store()) do n = n + 1 end
  local A = _G.Auctionator
  if type(A) == "table" and A.API then
    local sv = _G.AUCTIONATOR_SAVEDVARS
    local last = type(sv) == "table" and tonumber(sv.TimeOfLastBrowseScan)
    local when = last and FA.AgeText(math.floor((time() - last) / 86400)) or "not yet"
    return { GRAY_LINE("Prices: Auctionator, full scan " .. when) }
  end
  return { GRAY_LINE(("Prices from your own Auction House visits · %d items, some may be old"):format(n)),
    GRAY_LINE("Works best with Auctionator: one scan prices the whole Auction House.") }
end

---------------------------------------------------------------- Auction House search box
-- Types the name in. Never presses Search: you do.
function FA.AuctionHouseOpen()
  return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown()) or false
end
function FA.SearchAH(name)
  if not name or name == "" then return false end
  local box
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    box = AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchBox
  elseif AuctionFrame and AuctionFrame:IsShown() then
    box = BrowseName
  end
  if not (box and box.SetText) then return false end
  box:SetText(name)
  if box.SetFocus then box:SetFocus() end
  return true
end
