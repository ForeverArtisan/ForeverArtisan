-- ForeverArtisan: one search for everything (0.9.52). The box above the /fa panel's tabs.
-- Type a word, get one list grouped by kind; click a row to go to the right place.
-- Kerry, Nov 18: "one search box for everything at the top of the /fa panel, so you don't have to
-- know where to look". Plan: claude/addons/ForeverArtisan/PLAN-search.md.
--
--   FA.SearchAll(q, expanded) -> { { key, title, rows = { row, ... }, more = n }, ... }
--
-- Rows carry what the panel needs to draw and click them:
--   icon, left, right, id (item id, for the tooltip), tip (text) and one action:
--   craft = Market row (opens its price chart), recipe = { r, prof } (opens that profession on it),
--   item = { id, name } (at the Auction House: searches it), npc = contact (waypoint)
--
-- Only what ForeverArtisan already knows: your recipes, Auction House prices you've seen (or
-- Auctionator's), your Trade Contacts and Questie when installed. Nothing new is collected.

local FA = ForeverArtisan
local GRAY, GREEN, RED, YELLOW = "|cff9d9d9d", "|cff40ff40", "|cffff4040", "|cffffd100"

FA.SEARCH_GROUP_ROWS = 6   -- rows per group before a "N more" row
FA.SEARCH_MIN = 2          -- letters before searching

---------------------------------------------------------------- item names (for the price index)
-- id -> lower-case name, filled as the game hands names out; an item it hasn't loaded yet is asked
-- for once and joins the index when it arrives (FA.WaitForItem -> FA.PricesChanged)
local names, asked = {}, {}
local function ItemName(id)
  local n = names[id]
  if n then return n end
  local nm
  if C_Item and C_Item.GetItemNameByID then local ok, v = pcall(C_Item.GetItemNameByID, id); if ok then nm = v end end
  if not nm and GetItemInfo then local ok, v = pcall(GetItemInfo, id); if ok then nm = v end end
  if not nm and FA.QuestieItemName then nm = FA.QuestieItemName(id) end
  if type(nm) ~= "string" or nm == "" or (FA.IsSecret and FA.IsSecret(nm)) then
    if not asked[id] and FA.WaitForItem then asked[id] = true; pcall(FA.WaitForItem, id) end
    return nil
  end
  names[id] = { name = nm, low = nm:lower() }
  return names[id]
end
FA.SearchItemName = ItemName

local function Has(text, q)
  return type(text) == "string" and text:lower():find(q, 1, true) ~= nil
end

local function Ago(days)
  if not days then return "" end
  return GRAY .. "  ·  " .. (FA.AgeText and FA.AgeText(days) or (days .. "d")) .. "|r"
end

---------------------------------------------------------------- groups
-- Crafts you know, ranked like the Market tab (profit after the Auction House cut)
local function Crafts(q)
  local out = {}
  if not FA.MarketRows then return out end
  local ok, rows = pcall(FA.MarketRows, ForeverArtisanSettings and ForeverArtisanSettings.marketSort)
  for _, row in ipairs(ok and rows or {}) do
    local rec = row.r
    if rec and Has(rec.name, q) then
      local money = row.profit >= 0 and (GREEN .. "+" .. FA.Money(row.profit) .. "|r") or (RED .. FA.Money(row.profit) .. "|r")
      out[#out + 1] = { icon = FA.UI and FA.UI.Icon(rec.itemId), id = rec.itemId, craft = row,
        left = ((row.prof.color and row.prof.color(rec)) or "") .. rec.name .. "|r" .. GRAY .. "  " .. row.prof.name .. "|r",
        right = money .. GRAY .. " a craft|r",
        hint = "Click for its price chart and trend" }
    end
  end
  return out
end

-- Items with an Auction House price (your visits, your scans, Auctionator)
local function Items(q)
  local out = {}
  if not FA.PricedItemIds then return out end
  for _, id in ipairs(FA.PricedItemIds()) do
    local n = ItemName(id)
    if n and n.low:find(q, 1, true) then
      local p, _, age = FA.AHPrice(id)
      local t = FA.PriceTrend and FA.PriceTrend(id)
      local arrow = (t and t.dir == "up" and " |TInterface\\Buttons\\Arrow-Up-Up:12|t") or (t and t.dir == "down" and " |TInterface\\Buttons\\Arrow-Down-Up:12|t") or ""
      out[#out + 1] = { icon = FA.UI and FA.UI.Icon(id), id = id, item = { id = id, name = n.name }, sortName = n.low,
        left = n.name,
        right = (p and (YELLOW .. FA.Money(p) .. "|r") or (GRAY .. "no price|r")) .. arrow .. Ago(age),
        hint = "At the Auction House: click to search it" }
    end
  end
  -- the closest names first: starts with the words, then shorter names
  table.sort(out, function(a, b)
    local sa, sb = a.sortName:sub(1, #q) == q, b.sortName:sub(1, #q) == q
    if sa ~= sb then return sa end
    if #a.sortName ~= #b.sortName then return #a.sortName < #b.sortName end
    return a.sortName < b.sortName
  end)
  return out
end

-- Recipes in your profession windows (learned or not)
local function Recipes(q)
  local out = {}
  for _, p in ipairs(FA.MarketProviders and FA.MarketProviders() or {}) do
    local ok, recs = pcall(p.recipes)
    for _, r in pairs(ok and recs or {}) do
      if type(r) == "table" and Has(r.name, q) then
        out[#out + 1] = { icon = FA.UI and FA.UI.Icon(r.itemId), id = r.itemId, recipe = { r = r, prof = p }, sortName = r.name:lower(),
          left = ((p.color and p.color(r)) or "") .. r.name .. "|r" .. GRAY .. "  " .. p.name .. "|r",
          right = r.learned and (GREEN .. "known|r") or (GRAY .. "not learned|r"),
          hint = "Click to open " .. p.name .. " on it" }
      end
    end
  end
  table.sort(out, function(a, b) return a.sortName < b.sortName end)
  return out
end

-- Trade Contacts: vendors, trainers, what they sell and teach, towns (and Questie's, when installed).
-- Recipes a trainer teaches (and the trainers themselves) get their own group, so a row like
-- "Goblin Deviled Clams  learn at Cooking 125 ... 3s" reads as training, not an item for sale
-- (Kerry, Nov 22). One Trade Contacts search per query feeds both groups.
local lastQ, lastRows
local function ContactRows(q)
  if q == lastQ and lastRows then return lastRows end
  local out = {}
  if FA.ContactsSearch then
    local ok, rows = pcall(FA.ContactsSearch, q)
    for _, d in ipairs(ok and rows or {}) do
      if d.npc or d.id then
        local teach = d.train or d.trainer
        out[#out + 1] = { icon = d.icon, id = d.id, npc = d.npc, left = d.left, teach = teach, place = d.place,
          right = (d.right or "") .. ((d.tail and d.tail ~= "") and ("  " .. d.tail) or ""),
          tipFn = d.tipFn, tip = d.tip,
          item = (d.id and not d.train) and { id = d.id, name = (d.left or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("  .*$", "") } or nil,
          hint = d.npc and (teach and "Click for a waypoint to the trainer" or "Click for a waypoint") or nil }
      end
    end
  end
  lastQ, lastRows = q, out
  return out
end
local function Trainers(q)
  local out = {}
  for _, d in ipairs(ContactRows(q)) do if d.teach then out[#out + 1] = d end end
  return out
end
local function Contacts(q)
  local out = {}
  for _, d in ipairs(ContactRows(q)) do if not d.teach and not d.place then out[#out + 1] = d end end
  return out
end
-- innkeepers, flight masters, banks, auctioneers, stable masters (Questie's), nearest first
local function Places(q)
  local out = {}
  for _, d in ipairs(ContactRows(q)) do if d.place then out[#out + 1] = d end end
  return out
end

local GROUPS = {
  { key = "crafts", title = "Crafts you know", fn = Crafts },
  { key = "items", title = "Auction House prices", fn = Items },
  { key = "recipes", title = "Recipes", fn = Recipes },
  { key = "places", title = "Nearest innkeepers, flights and banks", fn = Places },
  { key = "trainers", title = "Learn from a trainer", fn = Trainers },
  { key = "contacts", title = "Vendors", fn = Contacts },
}

function FA.SearchAll(q, expanded)
  q = type(q) == "string" and q:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
  if #q < FA.SEARCH_MIN then return {} end
  local out = {}
  lastQ, lastRows = nil, nil -- contacts can change between searches: ask once per search
  for _, g in ipairs(GROUPS) do
    local ok, rows = pcall(g.fn, q)
    rows = ok and rows or {}
    if #rows > 0 then
      local cap = (expanded and expanded[g.key]) and #rows or FA.SEARCH_GROUP_ROWS
      local shown = {}
      for i = 1, math.min(cap, #rows) do shown[i] = rows[i] end
      out[#out + 1] = { key = g.key, title = g.title, rows = shown, total = #rows, more = #rows - #shown }
    end
  end
  return out
end
