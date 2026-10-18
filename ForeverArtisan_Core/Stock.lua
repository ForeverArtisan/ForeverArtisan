-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: what you could make, counting more than your bags.
--   Your bank: read each time you open it, saved per character (the game only shows it at the bank).
--   Vendor mats: Coarse Thread, flux, vials and the like. If buying them is all that stands between you
--   and a craft, the "Make now" list says how many you could make once you buy them, and what it costs.
--   FA.BankCount(id)            n in this character's bank (as of the last visit), and whether it's been seen
--   FA.BankSeenAt()             when the bank was last read, or nil
--   FA.VendorBuy(id, name)      true, price per unit (or nil) when a vendor always has it
--   FA.MakeCounts(r, Count)     { bags, bank, buy, buyList = { { id, name, n, price } }, buyCost }
--   FA.MakeText(m)              the "Make now" row's right side when your bags alone can't make it
--   FA.MakeTipLines(r, m)       tooltip lines: bank and vendor notes
local FA = ForeverArtisan
local GOLD, GRAY, GREEN, YELLOW = "|cffd4a94e", "|cff9d9d9d", "|cff40ff40", "|cffffd200"
local ALT = "|cffb89a6a" -- a dimmer gold: worth knowing, not ready to make

---------------------------------------------------------------- the bank
local function Store()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.bank = s.bank or {}
  local key = FA.CharKey(s.bank)
  local b = s.bank[key]
  if not b then b = {}; s.bank[key] = b end
  return b
end

local CC = rawget(_G, "C_Container")
local function NumSlots(bag)
  local f = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
  local ok, n = pcall(f, bag)
  return ok and tonumber(n) or 0
end
local function SlotItem(bag, slot)
  if CC and CC.GetContainerItemInfo then
    local ok, info = pcall(CC.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" then return info.itemID, info.stackCount or 1 end
    return nil
  end
  local idF = GetContainerItemID
  local id = idF and idF(bag, slot)
  if not id then return nil end
  local _, count = GetContainerItemInfo(bag, slot)
  return id, tonumber(count) or 1
end

local function BankBags()
  local first = (NUM_BAG_SLOTS or 4) + 1
  local list = { BANK_CONTAINER or -1 }
  for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do list[#list + 1] = b end
  return list
end

local bankOpen = false
function FA.ReadBank()
  if not bankOpen then return end
  local items = {}
  for _, bag in ipairs(BankBags()) do
    for slot = 1, NumSlots(bag) do
      local id, n = SlotItem(bag, slot)
      if id then items[id] = (items[id] or 0) + n end
    end
  end
  local b = Store()
  b.items, b.at = items, time()
end

function FA.BankCount(id)
  local b = Store()
  if not (id and b.items) then return 0, b.at ~= nil end
  return b.items[id] or 0, true
end
function FA.BankSeenAt() return Store().at end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e)
  if e == "BANKFRAME_OPENED" then bankOpen = true; FA.ReadBank()
  elseif e == "BANKFRAME_CLOSED" then FA.ReadBank(); bankOpen = false
  elseif bankOpen then FA.ReadBank() end
end)
FA._SetBankOpen = function(v) bankOpen = v end -- for the tests

-- Cloth (Linen, Wool, Silk...) drops from humanoids; it's never skinned, mined or picked. The gathering
-- logs can still catch it when a corpse is looted right after a skin (auto loot), so shopping lists skip
-- those logs for cloth. Item class 7 (Trade Goods), subclass 5 (Cloth); by name until the game has the item.
function FA.IsCloth(id, name)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if id and f then
    local ok, _, _, _, _, _, classID, subID = pcall(f, id)
    if ok and classID == 7 and subID == 5 then return true end
  end
  return type(name) == "string" and name:find(" Cloth$") ~= nil and not name:find("^Bolt of ")
end

---------------------------------------------------------------- vendor mats
-- A vendor you've met who always has it (not limited stock), cheapest first; else the fixed list of
-- vendor-only reagents (no price until you meet one).
-- remembered for a few seconds: the Make now list asks for every reagent of every recipe
local buyMemo, buyAt = {}, -100
function FA.VendorBuy(id, name)
  local now = GetTime and GetTime() or 0
  if now - buyAt > 10 then wipe(buyMemo); buyAt = now end
  local key = tostring(id) .. ":" .. tostring(name)
  local hit = buyMemo[key]
  if hit then return hit[1], hit[2] end
  local isV, price = FA._VendorBuy(id, name)
  buyMemo[key] = { isV, price }
  return isV, price
end
function FA._VendorBuy(id, name)
  local V = FA.Vendors
  local best
  if V and V.hitsForLink and (id or name) then
    local ok, hits = pcall(V.hitsForLink, id and ("item:" .. id) or nil, name)
    for _, h in ipairs(ok and type(hits) == "table" and hits or {}) do
      local it = h.item
      if it and not it.train and not it.limited and (not id or not it.id or it.id == id) and it.p and it.p > 0 then
        local unit = it.p / (it.stack or 1)
        if not best or unit < best then best = unit end
      end
    end
  end
  if best then return true, best end
  if FA.VendorHint and FA.VendorHint(name or id) then return true, nil end
  return false
end

---------------------------------------------------------------- counting
-- bags: from your bags; bank: bags + bank; buy: bags + bank + vendor mats (nil when every mat
-- comes from a vendor, or buying doesn't add any)
function FA.MakeCounts(r, Count)
  local m = { bags = 0, bank = 0 }
  if not (r and r.reagents and #r.reagents > 0) then return m end
  local bags, bank, buy
  local vend, all = {}, {}
  for _, g in ipairs(r.reagents) do
    local need = math.max(1, g.n or 1)
    local inBags = Count(g.id) or 0
    local both = inBags + (FA.BankCount(g.id))
    local a, b = math.floor(inBags / need), math.floor(both / need)
    bags = (not bags or a < bags) and a or bags
    bank = (not bank or b < bank) and b or bank
    local isV, price = FA.VendorBuy(g.id, g.name)
    if isV then vend[#vend + 1] = { g = g, need = need, have = both, price = price }
    else buy = (not buy or b < buy) and b or buy end
    all[#all + 1] = { g = g, need = need, bags = inBags, bank = both - inBags, vendor = isV }
  end
  m.bags, m.bank = bags or 0, bank or 0
  -- the mats that cap the count (not vendor mats): your alts may have more of these
  m.limits = {}
  if buy then
    for _, a in ipairs(all) do
      if not a.vendor and math.floor((a.bags + a.bank) / a.need) == buy then
        m.limits[#m.limits + 1] = { id = a.g.id, name = a.g.name, need = a.need, have = a.bags + a.bank }
      end
    end
  end
  if buy and #vend > 0 and buy > m.bank then
    m.buy, m.buyList, m.buyCost = buy, {}, 0
    for _, v in ipairs(vend) do
      local short = v.need * buy - v.have
      if short > 0 then
        m.buyList[#m.buyList + 1] = { id = v.g.id, name = v.g.name, n = short, price = v.price }
        if v.price and m.buyCost then m.buyCost = m.buyCost + v.price * short else m.buyCost = nil end
      end
    end
    -- and what to take out of the bank first (your bags alone are short)
    m.fetch = {}
    for _, a in ipairs(all) do
      local take = math.min(a.bank, math.max(0, a.need * buy - a.bags))
      if take > 0 then m.fetch[#m.fetch + 1] = { id = a.g.id, name = a.g.name, n = take } end
    end
  end
  return m
end

local function ItemName(e)
  local f = (C_Item and C_Item.GetItemNameByID) or GetItemInfo
  return (e.id and f and f(e.id)) or e.name or "?"
end

function FA.MakeText(m)
  if m.bank > m.bags then
    return YELLOW .. m.bank .. " with bank mats|r"
  end
  if m.buy then
    local what = #m.buyList == 1 and ("buy " .. ItemName(m.buyList[1])) or "buy vendor mats"
    if m.fetch and #m.fetch > 0 then what = "bank + " .. (#m.buyList == 1 and ItemName(m.buyList[1]) or "vendor mats") end
    return GOLD .. ("%s: make %d|r"):format(what, m.buy)
  end
  -- nothing here, but your alts have what's missing: say so (the count stays 0, they'd need mailing)
  if m.bank == 0 and FA.AltStock and m.limits and #m.limits > 0 then
    for _, g in ipairs(m.limits) do
      -- only when the alts have enough for at least one craft (12 bolts, not 11)
      local total = FA.AltStock(g.id)
      if not (total and g.have + total >= g.need) then return nil end
    end
    return ALT .. (#m.limits == 1 and ItemName(m.limits[1]) or "mats") .. " on alts|r"
  end
end

function FA.MakeTipLines(r, m)
  local lines = {}
  if m.bank > m.bags then
    lines[#lines + 1] = GREEN .. ("With your bank: make %d (%d from your bags alone).|r"):format(m.bank, m.bags)
  end
  if m.buy then
    lines[#lines + 1] = GOLD .. ("Buy from a vendor and make %d:|r"):format(m.buy)
    for _, b in ipairs(m.buyList) do
      lines[#lines + 1] = ("  %d %s%s"):format(b.n, ItemName(b),
        b.price and (GRAY .. "  " .. FA.Money(b.price * b.n) .. "|r") or (GRAY .. "  (meet a vendor to see the price)|r"))
    end
    if m.buyCost and #m.buyList > 1 then lines[#lines + 1] = GRAY .. "Total: " .. FA.Money(m.buyCost) .. "|r" end
    if m.fetch and #m.fetch > 0 then
      lines[#lines + 1] = GREEN .. "And take from your bank:|r"
      for _, f in ipairs(m.fetch) do lines[#lines + 1] = ("  %d %s"):format(f.n, ItemName(f)) end
    end
  end
  -- not counted above (they'd need mailing), but worth knowing
  if FA.AltStock then
    for _, g in ipairs(m.limits or {}) do
      local total, list = FA.AltStock(g.id)
      if total and total > 0 then
        local enough = (g.have or 0) + total >= (g.need or 1)
        -- what they add, in crafts (this mat only; the others are in your bags, bank or at a vendor)
        local have, need = g.have or 0, g.need or 1
        local more = math.floor((have + total) / need) - math.floor(have / need)
        lines[#lines + 1] = enough and (GOLD .. ("%d more %s on your alts (%d more craft%s, mail them over):|r"):format(
          total, ItemName(g), more, more == 1 and "" or "s"))
          or (GRAY .. ("%d %s on your alts, not enough for one (needs %d):|r"):format(total, ItemName(g), g.need))
        -- who has them, most first (bags, bank and mailbox together)
        -- full names ("Boomz Dynamitez"; Forever characters can share a first name), without the realm
        for i = 1, math.min(3, #(list or {})) do
          lines[#lines + 1] = ("  %s: %d"):format((tostring(list[i].name):gsub("%-[^%-]*$", "")), list[i].n)
        end
        if list and #list > 3 then lines[#lines + 1] = GRAY .. ("  ...and %d more|r"):format(#list - 3) end
      end
    end
  end
  if not FA.BankSeenAt() then
    lines[#lines + 1] = GRAY .. "Open your bank once and its mats count here too.|r"
  elseif m.bank > m.bags or (m.buy and m.bank > 0) then
    lines[#lines + 1] = GRAY .. "Bank as of your last visit.|r"
  end
  return lines
end

FA._StockReset = function() wipe(buyMemo); buyAt = -100 end
