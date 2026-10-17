-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: recipe watch. While you look at the Auction House (or Auctionator scans it),
-- recipe items for a profession you have, that you don't know yet, are noted with their cheapest price.
-- One chat line after the scan names the new ones, and the /fa Market tab lists them (hover).
-- It only reads what the Auction House already showed you; it never searches or buys.
--   FA.NoteRecipeListing(id, name, unitPrice)   Prices.lua calls this for each item on a page
--   FA.RecipeWatchList()                        { { id, name, prof, price, at }, ... } cheapest first
--   FA.RecipeWatchLines()                       the Market tab line and its tooltip lines
local FA = ForeverArtisan
local GOLD, GRAY = "|cffd4a94e", "|cff9d9d9d"
local PREFIX = FA.Prefix and FA.Prefix() or "ForeverArtisan: "

local PREFIXES = { "Recipe: ", "Pattern: ", "Plans: ", "Schematic: ", "Formula: ", "Manual: ", "Blueprint: " }
-- the game's recipe item subclasses (item class 9)
local SUBCLASS = { [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering", [4] = "Blacksmithing",
  [5] = "Cooking", [6] = "Alchemy", [7] = "First Aid", [8] = "Enchanting" }
local KEEP = 3 * 86400 -- a listing older than this is dropped (it has likely sold)

local function Settings()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  return ForeverArtisanSettings
end
local function Store()
  local s = Settings()
  s.recipeWatch = s.recipeWatch or {}
  return s.recipeWatch
end
-- held back until 0.9.26 (with your alts' recipes): the code ships, but stays off and out of sight
FA.RECIPE_WATCH_READY = false
function FA.RecipeWatchOn() return FA.RECIPE_WATCH_READY and not Settings().recipeWatchOff end

local function Strip(name)
  for _, p in ipairs(PREFIXES) do
    if name:sub(1, #p) == p then return name:sub(#p + 1) end
  end
end

local tradesCache, tradesAt = nil, -100
local function Trades()
  local now = GetTime and GetTime() or 0
  if not tradesCache or now - tradesAt > 30 then
    tradesCache, tradesAt = (FA.LearnedTrades and FA.LearnedTrades() or {}), now
  end
  return tradesCache
end

-- Another way to get it: a trainer or vendor you've met (Trade Contacts, with the price you saw), or a
-- vendor for your faction from Questie (no price). { price or nil, kind = "trainer"|"vendor", npc, questie }
function FA.RecipeNpcSource(e)
  local base = Strip(e.name) or e.name
  local best
  local function cand(price, kind, npc)
    if not npc then return end
    if not best or (price and (not best.price or price < best.price)) then best = { price = price, kind = kind, npc = npc } end
  end
  local V = FA.Vendors
  if V and V.hitsForLink then
    local ok, hits = pcall(V.hitsForLink, "item:" .. e.id, e.name)
    for _, h in ipairs(ok and hits or {}) do
      if h.item and not h.item.train then cand(h.item.p, "vendor", h.npc) end
    end
    ok, hits = pcall(V.hitsForLink, nil, base)
    for _, h in ipairs(ok and hits or {}) do
      if h.item and h.item.train then cand(h.item.p, "trainer", h.npc) end
    end
  end
  if not best and FA.QuestieRecipeSources then
    local ok, lines, npc = pcall(FA.QuestieRecipeSources, base)
    if ok and lines and npc and tostring(lines[1]):find("^Sold by") then best = { kind = "vendor", npc = npc, questie = true } end
  end
  return best
end

-- "trainer 4s" / "vendor ?" for a line, and true when it's cheaper than the Auction House
function FA.RecipeNpcText(e)
  local src = FA.RecipeNpcSource(e)
  if not src then return nil end
  return src.kind .. " " .. (src.price and FA.Money(src.price) or "?"), src.price and src.price < e.price, src
end

local fresh, announced, flushAt = {}, {}, nil

local function Flush()
  flushAt = nil
  -- chat only names recipes you can learn now; the others wait in the Market list (and get a line
  -- on a later scan, once your skill is high enough)
  local list, tr = {}, Trades()
  for id in pairs(fresh) do
    local e = Store()[id]
    if e and not announced[id] then
      local req = FA.RecipeWatchReq and FA.RecipeWatchReq(e)
      local have = tr[e.prof:lower()] and tr[e.prof:lower()].rank
      if not (req and have and have < req) then announced[id] = true; list[#list + 1] = e end
    end
  end
  wipe(fresh)
  if #list == 0 or not FA.RecipeWatchOn() then return end
  table.sort(list, function(a, b) return a.price < b.price end)
  local parts = {}
  for i = 1, math.min(3, #list) do
    local npcText, cheaper = FA.RecipeNpcText(list[i])
    parts[i] = list[i].name .. " " .. FA.Money(list[i].price)
      .. (npcText and (cheaper and (" (cheaper: " .. npcText .. ")") or (" (" .. npcText .. ")")) or "")
  end
  print(PREFIX .. ("%d recipe%s you don't know %s on the Auction House: %s%s. %sThe full list: /fa > Market, click the gold line at the top.|r"):format(
    #list, #list == 1 and "" or "s", #list == 1 and "is" or "are", table.concat(parts, ", "),
    #list > 3 and (" and " .. (#list - 3) .. " more") or "", GRAY))
end

function FA.NoteRecipeListing(id, name, unit)
  if not (id and name and unit and unit > 0) or not FA.RecipeWatchOn() then return end
  local base = Strip(name)
  if not base then return end
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local prof
  if f then
    local _, _, _, _, _, classID, subID = f(id)
    if classID and classID ~= 9 then return end
    prof = SUBCLASS[subID]
  end
  if not prof or not Trades()[prof:lower()] then return end -- a profession this character has
  local knows = FA.MarketKnows and FA.MarketKnows(prof, base)
  local w = Store()
  if knows then w[id] = nil; return end
  local e = w[id]
  local now = time()
  if not e or unit < e.price or now - (e.at or 0) > 600 then
    w[id] = { id = id, name = name, prof = prof, price = unit, at = now }
  else
    e.at = now
  end
  fresh[id] = true
  if not flushAt then
    flushAt = true
    if C_Timer then C_Timer.After(3, Flush) else Flush() end
  end
end

function FA.RecipeWatchList()
  local w, out, now = Store(), {}, time()
  for id, e in pairs(w) do
    local knows = FA.MarketKnows and FA.MarketKnows(e.prof, Strip(e.name) or e.name)
    if now - (e.at or 0) > KEEP or knows then w[id] = nil
    elseif Trades()[e.prof:lower()] then out[#out + 1] = e end
  end
  -- ones you could learn now first (your skill is high enough), then by price
  local tr = Trades()
  for _, e in ipairs(out) do
    local req, have = FA.RecipeWatchReq(e), tr[e.prof:lower()] and tr[e.prof:lower()].rank
    e.ready = not (req and have and have < req)
  end
  table.sort(out, function(a, b)
    if a.ready ~= b.ready then return a.ready end
    return a.price < b.price
  end)
  return out
end

-- the skill a recipe needs, from its tooltip ("Requires First Aid (210)"); nil until the game has the item
local scan
local function ReqSkill(e)
  if e.req then return e.req end
  if not (CreateFrame and e.prof) then return nil end
  scan = scan or CreateFrame("GameTooltip", "ForeverArtisanRecipeWatchTip", nil, "GameTooltipTemplate")
  scan:SetOwner(WorldFrame, "ANCHOR_NONE")
  scan:ClearLines()
  if not pcall(scan.SetItemByID, scan, e.id) then return nil end
  for i = 2, scan:NumLines() do
    local fs = _G["ForeverArtisanRecipeWatchTipTextLeft" .. i]
    local t = fs and fs:GetText()
    local n = t and tonumber(t:match("^Requires " .. e.prof .. " %((%d+)%)"))
    if n then e.req = n; return n end
  end
end
FA.RecipeWatchReq = ReqSkill

local function Ago(secs)
  if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. "m ago" end
  if secs < 86400 then return math.floor(secs / 3600) .. "h ago" end
  return math.floor(secs / 86400) .. "d ago"
end

-- Market tab: "3 recipes for you on the AH" and a tooltip with each one, its price and when you saw it
function FA.RecipeWatchLines()
  if not FA.RECIPE_WATCH_READY then return nil end
  local list, now = FA.RecipeWatchList(), time()
  if #list == 0 then return nil end
  local ready, newest = 0, 0
  for _, e in ipairs(list) do
    if e.ready then ready = ready + 1 end
    if (e.at or 0) > newest then newest = e.at end
  end
  local tip = { "Recipes you don't know, on the Auction House",
    ("%d recipe%s, %d you can learn now. Last seen %s."):format(#list, #list == 1 and "" or "s", ready, Ago(now - newest)),
    "|cff80c0ffClick to see the list.|r" }
  tip[#tip + 1] = GRAY .. "From the Auction House pages you looked at (or Auctionator's scan). It may have sold since. /fa recipewatch off turns this off.|r"
  return GOLD .. #list .. " recipe" .. (#list == 1 and "" or "s") .. " for you on the AH  >|r", tip
end

FA._RecipeWatchFlush = Flush -- for the tests
FA._RecipeWatchReset = function() wipe(fresh); wipe(announced); flushAt = nil; tradesCache = nil end
