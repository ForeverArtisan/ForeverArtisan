-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: disenchanting (BETA).
-- What a green, blue or purple item disenchants into, what that's worth at the Auction House, and a log of
-- your own disenchants that checks the rules against what Forever really gives.
-- No item list: the result follows from the item's quality, item level and armor/weapon (the game's rules,
-- one table of item-level bands below), so it works for every item, Forever's new ones too.
--   FA.DisenchantInfo(item)            { { id, min, max, chance, kind }, ... }, band key; nil if it can't be disenchanted
--   FA.DisenchantValue(item)           expected copper after the AH cut, missing (names with no price yet)
--   FA.DisenchantTipLines(tt, item)    adds the lines to a tooltip
--   FA.DisenchantRowLines(tt, itemId, makes, cost)   one line for a Market row's hover
--   FA.DisenchantLogSummary()          /fa disenchant log
local FA = ForeverArtisan
local GOLD, GRAY, GREEN, RED = FA.GOLD or "|cffd4a94e", FA.GRAY or "|cff9d9d9d", FA.GREEN or "|cff40ff40", FA.RED or "|cffff4040"
local BETA = "|cffff9020BETA|r"
local PREFIX = FA.Prefix and FA.Prefix() or "ForeverArtisan: "
local AH_CUT = 0.95
local DE_SPELL = 13262
-- newer clients moved these into C_Item / C_Spell (Forever has no global GetItemInfo)
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local LOG_MAX = 400

---------------------------------------------------------------- the rules (Classic tables)

local DUST = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local ESS = {
  lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134, gmystic = 11135,
  lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203,
}
local SHARD = {
  sglim = 10978, lglim = 11084, sglow = 11138, lglow = 11139, srad = 11177, lrad = 11178,
  sbril = 14343, lbril = 14344, nexus = 20725,
}
local KIND = {}
for _, id in pairs(DUST) do KIND[id] = "dust" end
for _, id in pairs(ESS) do KIND[id] = "essence" end
for _, id in pairs(SHARD) do KIND[id] = "shard" end
KIND[SHARD.nexus] = "crystal"
-- lesser <-> greater: 3 lesser make 1 greater, and a greater splits into 3 lesser (free, no skill needed)
local GREATER = { [ESS.lmagic] = ESS.gmagic, [ESS.lastral] = ESS.gastral, [ESS.lmystic] = ESS.gmystic,
  [ESS.lnether] = ESS.gnether, [ESS.leternal] = ESS.geternal }
local LESSER = {}
for l, g in pairs(GREATER) do LESSER[g] = l end

-- Uncommon (green): up to item level `to`: dust {id, min, max}, essence {id, min, max}, shard id or nil,
-- and the chances for armor and for weapons (dust, essence, shard). Shards from greens are always 1.
local GREEN_BANDS = {
  { to = 15, d = { DUST.strange, 1, 2 }, e = { ESS.lmagic, 1, 2 }, armor = { 80, 20, 0 }, weapon = { 20, 80, 0 } },
  { to = 20, d = { DUST.strange, 2, 3 }, e = { ESS.gmagic, 1, 2 }, s = SHARD.sglim, armor = { 75, 20, 5 }, weapon = { 20, 75, 5 } },
  { to = 25, d = { DUST.strange, 4, 6 }, e = { ESS.lastral, 1, 2 }, s = SHARD.sglim, armor = { 75, 15, 10 }, weapon = { 15, 75, 10 } },
  { to = 30, d = { DUST.soul, 1, 2 }, e = { ESS.gastral, 1, 2 }, s = SHARD.lglim, armor = { 75, 20, 5 }, weapon = { 20, 75, 5 } },
  { to = 35, d = { DUST.soul, 2, 5 }, e = { ESS.lmystic, 1, 2 }, s = SHARD.sglow, armor = { 75, 20, 5 }, weapon = { 20, 75, 5 } },
  { to = 40, d = { DUST.vision, 1, 2 }, e = { ESS.gmystic, 1, 2 }, s = SHARD.lglow, armor = { 75, 20, 5 }, weapon = { 20, 75, 5 } },
  { to = 45, d = { DUST.vision, 2, 5 }, e = { ESS.lnether, 1, 2 }, s = SHARD.srad, armor = { 75, 20, 5 }, weapon = { 20, 75, 5 } },
  { to = 50, d = { DUST.dream, 1, 2 }, e = { ESS.gnether, 1, 2 }, s = SHARD.lrad, armor = { 75, 20, 5 }, weapon = { 20, 75, 5 } },
  { to = 55, d = { DUST.dream, 2, 5 }, e = { ESS.leternal, 1, 2 }, s = SHARD.sbril, armor = { 75, 20, 5 }, weapon = { 22, 75, 3 } },
  { to = 60, d = { DUST.illusion, 1, 2 }, e = { ESS.geternal, 1, 2 }, s = SHARD.lbril, armor = { 75, 20, 5 }, weapon = { 22, 75, 3 } },
  { to = 999, d = { DUST.illusion, 2, 5 }, e = { ESS.geternal, 2, 3 }, s = SHARD.lbril, armor = { 75, 20, 5 }, weapon = { 22, 75, 3 } },
}
-- Rare (blue): one shard; the top band rarely gives a Nexus Crystal instead
local BLUE_BANDS = {
  { to = 25, r = { { SHARD.sglim, 1, 1, 100 } } },
  { to = 30, r = { { SHARD.lglim, 1, 1, 100 } } },
  { to = 35, r = { { SHARD.sglow, 1, 1, 100 } } },
  { to = 40, r = { { SHARD.lglow, 1, 1, 100 } } },
  { to = 45, r = { { SHARD.srad, 1, 1, 100 } } },
  { to = 50, r = { { SHARD.lrad, 1, 1, 100 } } },
  { to = 55, r = { { SHARD.sbril, 1, 1, 100 } } },
  { to = 999, r = { { SHARD.lbril, 1, 1, 99.5 }, { SHARD.nexus, 1, 1, 0.5 } } },
}
-- Epic (purple)
local PURPLE_BANDS = {
  { to = 45, r = { { SHARD.srad, 2, 4, 100 } } },
  { to = 50, r = { { SHARD.lrad, 2, 4, 100 } } },
  { to = 55, r = { { SHARD.sbril, 2, 4, 100 } } },
  { to = 60, r = { { SHARD.nexus, 1, 1, 100 } } },
  { to = 999, r = { { SHARD.nexus, 1, 2, 100 } } },
}

-- worn slots that can't be disenchanted (shirts, tabards) and anything that isn't worn
local NO_DE_SLOT = { [""] = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true,
  INVTYPE_AMMO = true, INVTYPE_NON_EQUIP = true }

local function itemIdOf(item)
  if type(item) == "number" then return item end
  if type(item) == "string" then return tonumber(item:match("item:(%d+)")) or tonumber(item) end
end

local function band(list, ilvl)
  for i, b in ipairs(list) do if ilvl <= b.to then return b, i end end
end

-- quality, item level, weapon?, or nil (not cached yet, or not something you can disenchant)
local function facts(item)
  if not (GetItemInfo and item) then return nil end
  local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID = GetItemInfo(item)
  if not quality then return nil end
  if not classID then
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if f then classID = select(6, f(item)) end
  end
  if quality < 2 or quality > 4 or not ilvl then return nil end
  if classID ~= 2 and classID ~= 4 then return nil end
  if NO_DE_SLOT[equipLoc or ""] then return nil end
  return quality, ilvl, classID == 2
end

function FA.DisenchantInfo(item)
  local quality, ilvl, weapon = facts(item)
  if not quality then return nil end
  local out, key = {}, nil
  if quality == 2 then
    local b, i = band(GREEN_BANDS, ilvl)
    local c = weapon and b.weapon or b.armor
    if c[1] > 0 then out[#out + 1] = { id = b.d[1], min = b.d[2], max = b.d[3], chance = c[1] } end
    if c[2] > 0 then out[#out + 1] = { id = b.e[1], min = b.e[2], max = b.e[3], chance = c[2] } end
    if b.s and c[3] > 0 then out[#out + 1] = { id = b.s, min = 1, max = 1, chance = c[3] } end
    key = "2:" .. i .. (weapon and ":w" or ":a")
  else
    local b, i = band(quality == 3 and BLUE_BANDS or PURPLE_BANDS, ilvl)
    for _, r in ipairs(b.r) do out[#out + 1] = { id = r[1], min = r[2], max = r[3], chance = r[4] } end
    key = quality .. ":" .. i
  end
  -- most likely first
  table.sort(out, function(a, b) return a.chance > b.chance end)
  for _, r in ipairs(out) do r.kind = KIND[r.id] end
  return out, key, quality, ilvl, weapon
end

---------------------------------------------------------------- prices

local function ahPrice(id)
  local p
  if FA.AHPrice then
    local ok, v = pcall(FA.AHPrice, id)
    if ok then p = v end
  end
  if not (p and p > 0) then
    local A = type(rawget(_G, "Auctionator")) == "table" and _G.Auctionator.API and _G.Auctionator.API.v1
    if A and A.GetAuctionPriceByItemID then
      local ok, v = pcall(A.GetAuctionPriceByItemID, "ForeverArtisan", id)
      if ok then p = v end
    end
  end
  return (type(p) == "number" and p > 0) and p or nil
end

-- What one of these sells for after the cut, counting the essence trade: a greater is worth 3 lessers when
-- those sell for more, and a lesser is worth a third of a greater. Returns value, and the better form's id.
local function sellValue(id)
  local own = ahPrice(id)
  local g, l = GREATER[id], LESSER[id]
  if g then
    local gp = ahPrice(g)
    if gp and (not own or gp / 3 > own) then return gp / 3 * AH_CUT, g end
  elseif l then
    local lp = ahPrice(l)
    if lp and (not own or lp * 3 > own) then return lp * 3 * AH_CUT, l end
  end
  return own and own * AH_CUT or nil, id
end
FA.DisenchantMatValue = sellValue

local function nameOf(id)
  local n = GetItemInfo and GetItemInfo(id)
  if not n and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return n or ("item " .. id)
end

-- expected copper per disenchant after the cut, and the names of results with no price yet
function FA.DisenchantValue(item)
  local res = FA.DisenchantInfo(item)
  if not res then return nil end
  local total, missing = 0, {}
  for _, r in ipairs(res) do
    local v = sellValue(r.id)
    if v then total = total + v * (r.min + r.max) / 2 * r.chance / 100
    elseif r.chance >= 1 then missing[#missing + 1] = nameOf(r.id) end
  end
  return math.floor(total + 0.5), missing, res
end

---------------------------------------------------------------- who sees it

local function settings()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  return ForeverArtisanSettings
end

-- on for everyone (greens usually go to an alt or a friend who enchants, so the one deciding often has no
-- Enchanting); /fa disenchant off hides it
function FA.DisenchantTipsOn()
  return settings().deTips ~= false
end

---------------------------------------------------------------- your log

local function log()
  local s = settings()
  s.deLog = s.deLog or { list = {}, byKey = {} }
  return s.deLog
end

-- does what came out fit the rules? (every item one of the listed results, the count in range)
local function fits(res, out)
  local allowed = {}
  for _, r in ipairs(res) do allowed[r.id] = r end
  local any = false
  for id, n in pairs(out) do
    any = true
    local r = allowed[id]
    if not r or n < r.min or n > r.max then return false end
  end
  return any
end

local function record(link, out)
  local res, key, quality, ilvl, weapon = FA.DisenchantInfo(link)
  local L = log()
  local e = { t = time(), link = link, q = quality, il = ilvl, w = weapon or nil, out = out, ok = res and fits(res, out) or false }
  table.insert(L.list, e)
  while #L.list > LOG_MAX do table.remove(L.list, 1) end
  if key then
    local k = L.byKey[key] or { n = 0, kinds = {} }
    k.n = k.n + 1
    for id in pairs(out) do
      local kind = KIND[id] or "other"
      k.kinds[kind] = (k.kinds[kind] or 0) + 1
    end
    L.byKey[key] = k
  end
  if not e.ok then
    -- say it once per item level band, so a different Forever table gets noticed
    L.told = L.told or {}
    local tk = (key or "?") .. ":" .. tostring(next(out))
    if not L.told[tk] then
      L.told[tk] = true
      local got = {}
      for id, n in pairs(out) do got[#got + 1] = n .. "x " .. nameOf(id) end
      print(PREFIX .. "that disenchant didn't match the usual table: " .. (link or "?") .. " (item level " .. tostring(ilvl)
        .. ") gave " .. table.concat(got, ", ") .. ". Saved; /fa disenchant log lists them.")
    end
  end
end

---------------------------------------------------------------- tooltips

local function pct(c)
  if c >= 1 then return math.floor(c + 0.5) .. "%" end
  return c .. "%"
end

local function money(c) return FA.Money and FA.Money(math.floor(c + 0.5)) or (tostring(math.floor(c + 0.5)) .. "c") end

local KIND_WORDS = { dust = "dust", essence = "essence", shard = "shard", crystal = "crystal", other = "other" }

function FA.DisenchantTipLines(tt, item)
  local value, missing, res = FA.DisenchantValue(item)
  if not res then return false end
  local _, key = FA.DisenchantInfo(item)
  local priced = value > 0
  tt:AddDoubleLine(GOLD .. "Disenchant|r " .. BETA,
    priced and ("~" .. money(value) .. (#missing > 0 and "+" or "")) or (GRAY .. "no prices yet|r"), 1, 1, 1, 1, 1, 1)
  for _, r in ipairs(res) do
    local v, form = sellValue(r.id)
    local qty = (r.min == r.max) and tostring(r.min) or (r.min .. "-" .. r.max)
    tt:AddDoubleLine("  " .. pct(r.chance) .. "  " .. qty .. "x " .. nameOf(r.id),
      v and (money(v) .. " each") or (GRAY .. "no price|r"), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    -- essences: which form to sell
    if v and form ~= r.id then
      local lesser = GREATER[r.id] ~= nil -- a lesser that's worth more combined
      local own = ahPrice(r.id)
      local gain = own and (v - own * AH_CUT) or nil
      local words = lesser and "combine 3 into a " .. nameOf(form) .. " to sell" or "split into 3 " .. nameOf(form) .. " to sell"
      tt:AddLine("    " .. GREEN .. words .. (gain and gain > 0 and (": +" .. money(gain) .. (lesser and " each" or " a greater")) or "") .. "|r", 1, 1, 1, true)
    end
  end
  -- worth more as mats, or as the item?
  local id = itemIdOf(item)
  if priced and id then
    local ah = ahPrice(id)
    local vendor = GetItemInfo and select(11, GetItemInfo(item))
    local sale = math.max(ah and ah * AH_CUT or 0, vendor or 0)
    if sale > 0 then
      if value > sale * 1.1 then
        tt:AddLine("  " .. GREEN .. "Worth more disenchanted (" .. money(value - sale) .. " more than selling it)|r", 1, 1, 1, true)
      elseif sale > value * 1.1 then
        tt:AddLine("  " .. GRAY .. "Worth more sold as it is (" .. money(sale) .. ")|r", 1, 1, 1, true)
      end
    end
  end
  if #missing > 0 then
    tt:AddLine("  " .. GRAY .. "No price yet for " .. table.concat(missing, ", ") .. ".|r", 1, 1, 1, true)
  end
  -- what you got from ones like it
  local k = key and log().byKey[key]
  if k and k.n > 0 then
    local parts = {}
    for _, kind in ipairs({ "dust", "essence", "shard", "crystal", "other" }) do
      local c = k.kinds[kind] or 0
      if c > 0 then parts[#parts + 1] = c .. " " .. KIND_WORDS[kind] .. ((c > 1 and (kind == "shard" or kind == "crystal")) and "s" or "") end
    end
    tt:AddLine("  " .. GRAY .. "Your disenchants like this: " .. k.n .. " (" .. table.concat(parts, ", ") .. ")|r", 1, 1, 1, true)
  end
  return true
end

-- a Market row: what one craft would bring disenchanted, against its materials
function FA.DisenchantRowLines(tt, itemId, makes, cost)
  local value = itemId and FA.DisenchantValue(itemId)
  if not value or value <= 0 then return end
  local each = value * (makes or 1)
  local profit = each - (cost or 0)
  tt:AddDoubleLine("Disenchanted instead " .. BETA, money(each) .. " (" .. (profit >= 0 and (GREEN .. "+" .. money(profit)) or (RED .. "-" .. money(-profit))) .. "|r)",
    1, 1, 1, 1, 1, 1)
end

local hooked
local function hookTooltips()
  if hooked then return end
  hooked = true
  local function add(tt)
    if not (tt and tt.GetItem) or tt.__faDE or not FA.DisenchantTipsOn() then return end
    local _, link = tt:GetItem()
    if not link then return end
    tt.__faDE = true
    local ok, err = pcall(FA.DisenchantTipLines, tt, link)
    -- beta: say it once instead of failing quietly
    if not ok and not FA._deTipErr then
      FA._deTipErr = true
      print(PREFIX .. "disenchant tooltip error (please send this to the Discord): " .. tostring(err))
    end
  end
  local function clear(tt) tt.__faDE = nil end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
      if tt == GameTooltip or tt == ItemRefTooltip then add(tt) end
    end)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      if tt and tt.HookScript then pcall(tt.HookScript, tt, "OnTooltipSetItem", add) end
    end
  end
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and tt.HookScript then pcall(tt.HookScript, tt, "OnTooltipCleared", clear); pcall(tt.HookScript, tt, "OnHide", clear) end
  end
end

---------------------------------------------------------------- catching your disenchants

local DE_NAME = SpellName(DE_SPELL)
local function isDE(spellID)
  if spellID == DE_SPELL then return true end
  return (DE_NAME ~= nil and spellID ~= nil and SpellName(spellID) == DE_NAME) or false
end

local CB = C_Container or {}
local NumSlots = CB.GetContainerNumSlots or GetContainerNumSlots
-- link and locked for a bag slot, on both the old and new APIs
local function slotInfo(bag, slot)
  if CB.GetContainerItemInfo then
    local i = CB.GetContainerItemInfo(bag, slot)
    if i then return i.hyperlink, i.isLocked end
  elseif GetContainerItemInfo then
    local _, _, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
    return link, locked
  end
end

-- the item being disenchanted is the one the game locked in your bags
local function lockedTarget()
  if not NumSlots then return nil end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do -- the reagent bag too, where there is one
    for slot = 1, (NumSlots(bag) or 0) do
      local link, locked = slotInfo(bag, slot)
      if link and locked and FA.DisenchantInfo(link) then return link end
    end
  end
end

-- an item in your bags by name (UNIT_SPELLCAST_SENT names the item a spell is cast on)
local function bagLinkByName(name)
  if not (NumSlots and type(name) == "string" and name ~= "") then return nil end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (NumSlots(bag) or 0) do
      local link = slotInfo(bag, slot)
      if link and link:find("[" .. name .. "]", 1, true) and FA.DisenchantInfo(link) then return link end
    end
  end
end

-- every item that could be disenchanted, by link, with how many: compared before and after the cast
local function bagSnapshot()
  local snap = {}
  if not NumSlots then return snap end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    for slot = 1, (NumSlots(bag) or 0) do
      local link = slotInfo(bag, slot)
      if link and FA.DisenchantInfo(link) then snap[link] = (snap[link] or 0) + 1 end
    end
  end
  return snap
end
local function goneSince(snap)
  local now = bagSnapshot()
  for link, n in pairs(snap or {}) do
    if (now[link] or 0) < n then return link end
  end
end

local lastSent -- the item named when the cast was sent
local lastUsed -- backup: the item clicked while the spell was targeting
local pending
local function onUse(bag, slot)
  if SpellIsTargeting and SpellIsTargeting() then
    local link = slotInfo(bag, slot)
    if link then lastUsed = { link = link, at = GetTime() } end
  end
end
if CB.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", onUse) end
if UseContainerItem then hooksecurefunc("UseContainerItem", onUse) end

-- /fa disenchant debug: say in chat what the log saw, step by step
local function dbg(msg)
  if settings().deDebug then print(PREFIX .. GRAY .. "disenchant debug: " .. msg .. "|r") end
end

-- the item, if it's not known yet: whatever left your bags since the cast started
local function resolve()
  if pending and not pending.link and pending.snap then pending.link = goneSince(pending.snap) end
  return pending and pending.link
end

-- Save what came out a moment after the loot shows up, so the item is known by then. The loot window is
-- used when it has the items; with auto loot it can be empty, and the "You receive loot" chat lines are.
local function flush()
  if not pending or pending.logged then return end
  local out = pending.window or pending.chat
  if not (out and next(out)) then return end
  pending.logged = true
  local link = resolve()
  if not link then
    dbg("got the materials, but couldn't tell which item was disenchanted: not saved")
  else
    dbg("logged from " .. (pending.window and "the loot window" or "chat loot lines") .. ": " .. tostring(link))
    pcall(record, link, out)
  end
  pending = nil
end
local function flushSoon()
  if pending.flushing then return end
  pending.flushing = true
  if C_Timer and C_Timer.After then C_Timer.After(1, function() pcall(flush) end) else flush() end
end

local function readLoot()
  if not pending then dbg("loot window, but no disenchant cast seen") return end
  if pending.logged then return end
  -- the loot window can open just before the cast's success event
  if GetTime() - (pending.done or pending.at) > 6 then pending = nil return end
  local out, any = {}, false
  for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local link = GetLootSlotLink and GetLootSlotLink(i)
    local id = link and itemIdOf(link)
    local qty = select(3, GetLootSlotInfo(i)) or 1
    if id then out[id] = (out[id] or 0) + qty; any = true end
  end
  if not any then dbg("loot window was empty (auto loot): waiting for the loot lines in chat") return end
  pending.window = out
  flushSoon()
end

-- Auto loot can empty the loot window before it's read: then the "You receive loot" lines in chat
-- are what came out. Collected for a moment after the cast, then saved together.
local function onChatLoot(msg, guid)
  if not (pending and not pending.logged) then return end
  if GetTime() - (pending.done or pending.at) > 6 then return end
  local li = FA.ParseSelfLoot and FA.ParseSelfLoot(msg, guid)
  if not (li and li.id) then return end
  if not KIND[li.id] then return end -- only enchanting materials come out of a disenchant
  pending.chat = pending.chat or {}
  pending.chat[li.id] = (pending.chat[li.id] or 0) + (li.qty or 1)
  flushSoon()
end
local flushChat = flush
FA._DisenchantTest = { setPending = function(p) pending = p end, chat = onChatLoot, flush = flushChat }

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_LOOT" then
    local msg = ...
    local guid = select(12, ...)
    pcall(onChatLoot, msg, guid)
    return
  end
  local unit, a2, a3, a4 = ...
  -- UNIT_SPELLCAST_SENT is (unit, target, castGUID, spellID); the others are (unit, castGUID, spellID)
  local spellID = (event == "UNIT_SPELLCAST_SENT") and a4 or a3
  if event == "PLAYER_LOGIN" then
    pcall(hookTooltips)
    ev:RegisterEvent("UNIT_SPELLCAST_SENT")
    ev:RegisterEvent("UNIT_SPELLCAST_START")
    ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    ev:RegisterEvent("UNIT_SPELLCAST_FAILED")
    ev:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    ev:RegisterEvent("LOOT_READY")
    ev:RegisterEvent("LOOT_OPENED")
    ev:RegisterEvent("CHAT_MSG_LOOT")
    return
  end
  if event == "LOOT_READY" or event == "LOOT_OPENED" then pcall(readLoot) return end
  if unit ~= "player" or not isDE(spellID) then return end
  if event == "UNIT_SPELLCAST_SENT" then
    -- the game names the item the cast is on: find it in your bags
    local link = bagLinkByName(a2)
    lastSent = link and { link = link, at = GetTime() } or nil
    dbg("cast sent on " .. tostring(a2) .. (link and "" or " (not found in your bags)"))
  elseif event == "UNIT_SPELLCAST_START" then
    local link, how = nil, nil
    if lastSent and GetTime() - lastSent.at < 3 then link, how = lastSent.link, "named" end
    if not link then link = lockedTarget(); how = link and "locked" end
    if not link and lastUsed and GetTime() - lastUsed.at < 10 then link, how = lastUsed.link, "clicked" end
    -- still nothing: note the bags now, and see what's gone when the cast finishes
    pending = { link = link, at = GetTime(), snap = (not link) and bagSnapshot() or nil }
    dbg("cast started on " .. tostring(link or "?") .. " (" .. (how or "will check your bags when it finishes") .. ")")
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if pending then
      pending.done = GetTime()
      if not pending.link and pending.snap then
        local snap = pending.snap
        local function check()
          if pending and not pending.link then
            pending.link = goneSince(snap)
            dbg("from your bags: " .. tostring(pending.link or "no item went missing"))
          end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pcall(check) end) else check() end
      end
    end
    dbg("cast finished" .. (pending and "" or ", but the cast's start wasn't seen"))
  else
    dbg("cast stopped (" .. event:gsub("UNIT_SPELLCAST_", ""):lower() .. ")")
    pending = nil
  end
end)
if FA.GuardEvents then pcall(FA.GuardEvents, ev) end

---------------------------------------------------------------- /fa disenchant

-- for the Enchanting Craft log tab: newest first, what came out of all of them, and how many matched
--   rows { { link, id, out = { [id] = n }, ok, il, w, t, outText, expectText } }, totals { { id, n, name } }, n, ok
function FA.DisenchantLogView()
  local L = log()
  local rows, sum, ok = {}, {}, 0
  for i = #L.list, 1, -1 do
    local e = L.list[i]
    if e.ok then ok = ok + 1 end
    local got = {}
    for id, c in pairs(e.out or {}) do
      got[#got + 1] = c .. " " .. nameOf(id)
      sum[id] = (sum[id] or 0) + c
    end
    table.sort(got)
    local expect = {}
    local res = e.link and FA.DisenchantInfo(e.link)
    for _, r in ipairs(res or {}) do
      expect[#expect + 1] = ("%s %s (%s)"):format(r.min == r.max and r.min or (r.min .. "-" .. r.max), nameOf(r.id), pct(r.chance))
    end
    rows[#rows + 1] = { link = e.link, id = e.link and itemIdOf(e.link), out = e.out, ok = e.ok, il = e.il, w = e.w, t = e.t,
      outText = table.concat(got, ", "), expectText = #expect > 0 and table.concat(expect, ", ") or nil }
  end
  local totals = {}
  for id, n in pairs(sum) do totals[#totals + 1] = { id = id, n = n, name = nameOf(id) } end
  table.sort(totals, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  return rows, totals, #L.list, ok
end

function FA.DisenchantLogSummary()
  local L = log()
  local n, ok, bad = #L.list, 0, {}
  for _, e in ipairs(L.list) do
    if e.ok then ok = ok + 1 else bad[#bad + 1] = e end
  end
  if n == 0 then
    print(PREFIX .. "no disenchants logged yet. Each one you do is saved and checked against the usual table.")
    return
  end
  print(PREFIX .. ("%d disenchant%s logged, %d match%s the usual table%s."):format(n, n == 1 and "" or "s", ok, ok == 1 and "es" or "",
    #bad > 0 and (", " .. RED .. #bad .. (#bad == 1 and " doesn't|r" or " don't|r")) or ""))
  for i = math.max(1, #bad - 9), #bad do
    local e = bad[i]
    local got = {}
    for id, c in pairs(e.out or {}) do got[#got + 1] = c .. "x " .. nameOf(id) end
    print(("  %s  item level %s %s: %s"):format(e.link or "?", tostring(e.il), e.w and "weapon" or "armor", table.concat(got, ", ")))
  end
end

function FA.DisenchantCommand(rest)
  local r = (rest or ""):lower()
  local s = settings()
  if r == "log" then FA.DisenchantLogSummary() return end
  if r == "debug" then
    s.deDebug = not s.deDebug or nil
    print(PREFIX .. "disenchant debug " .. (s.deDebug and "on: each disenchant says in chat what was seen. /fa disenchant debug again turns it off." or "off."))
    return
  end
  if r == "on" then s.deTips = nil
  elseif r == "off" then s.deTips = false end
  print(PREFIX .. "Disenchant values on item tooltips (beta): " .. (FA.DisenchantTipsOn() and "on" or "off")
    .. ". " .. GRAY .. "/fa disenchant on | off | log|r")
end

-- /fa disenchant (and /fa de): Disenchant.lua loads after Modules.lua, so it wraps the /fa handler
local orig = SlashCmdList and SlashCmdList.FOREVERARTISAN
if orig then
  SlashCmdList.FOREVERARTISAN = function(msg)
    local word, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    if word == "disenchant" or word == "de" then FA.DisenchantCommand(rest) return end
    return orig(msg)
  end
end

-- for the tests
FA._DisenchantRecord = record
FA._DisenchantFits = fits
