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

local function Store()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.prices = s.prices or {}
  local realm = (GetRealmName and GetRealmName()) or "realm"
  if Secret(realm) then realm = "realm" end
  local faction = (UnitFactionGroup and UnitFactionGroup("player")) or ""
  if Secret(faction) then faction = "" end
  local key = realm .. "-" .. faction
  s.prices[key] = s.prices[key] or {}
  return s.prices[key]
end

---------------------------------------------------------------- remembering prices
-- one cheapest buyout per item per unit, in copper
function FA.NotePrice(id, unit)
  if not (id and unit) or Secret(id) or Secret(unit) then return end
  id, unit = tonumber(id), tonumber(unit)
  if not id or not unit or unit <= 0 then return end
  local p, now = Store(), time()
  local e = p[id]
  if e and now - (e.t or 0) < FRESH then
    if unit < e.p then e.p = unit end
    e.t = now
  else
    p[id] = { p = math.floor(unit + 0.5), t = now }
  end
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

-- Classic-style Auction House: the page of results on screen
local function ReadLegacyPage()
  if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
  local n = GetNumAuctionItems("list")
  if not n or Secret(n) then return end
  local cheapest = {}
  for i = 1, n do
    local r = { GetAuctionItemInfo("list", i) }
    local count, buyout, id = r[3], r[10], r[17]
    if id and count and buyout and not (Secret(id) or Secret(count) or Secret(buyout))
      and buyout > 0 and count > 0 then
      local unit = buyout / count
      if not cheapest[id] or unit < cheapest[id] then cheapest[id] = unit end
    end
  end
  for id, unit in pairs(cheapest) do FA.NotePrice(id, unit) end
end

-- Newer Auction House (C_AuctionHouse): browse list, commodity and item results
local function ReadBrowse()
  local AH = C_AuctionHouse
  if not (AH and AH.GetBrowseResults) then return end
  local ok, list = pcall(AH.GetBrowseResults)
  if not ok or type(list) ~= "table" then return end
  for _, r in ipairs(list) do
    local id = r.itemKey and r.itemKey.itemID
    if r.minPrice and r.minPrice > 0 then FA.NotePrice(id, r.minPrice) end
  end
end
local function ReadCommodity(id)
  local AH = C_AuctionHouse
  if not (id and AH and AH.GetCommoditySearchResultInfo) then return end
  local ok, r = pcall(AH.GetCommoditySearchResultInfo, id, 1)
  if ok and type(r) == "table" and r.unitPrice then FA.NotePrice(id, r.unitPrice) end
end
local function ReadItem(itemKey)
  local AH = C_AuctionHouse
  if not (type(itemKey) == "table" and AH and AH.GetItemSearchResultInfo) then return end
  local ok, r = pcall(AH.GetItemSearchResultInfo, itemKey, 1)
  if ok and type(r) == "table" and r.buyoutAmount and r.buyoutAmount > 0 then
    FA.NotePrice(itemKey.itemID, r.buyoutAmount / math.max(1, r.quantity or 1))
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

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a1)
  if e == "PLAYER_LOGIN" then Prune()
  elseif e == "AUCTION_ITEM_LIST_UPDATE" then ReadLegacyPage()
  elseif e == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then ReadBrowse()
  elseif e == "COMMODITY_SEARCH_RESULTS_UPDATED" then ReadCommodity(a1)
  elseif e == "ITEM_SEARCH_RESULTS_UPDATED" then ReadItem(a1)
  end
  if e ~= "PLAYER_LOGIN" then FA.PricesChanged() end
end)
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
  -- your own Auction House visit wins when it's newer than Auctionator's scan (same day: Auctionator)
  local e = Store()[id]
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
