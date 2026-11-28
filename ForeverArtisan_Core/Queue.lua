-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: the craft queue (0.9.56).
--   Kerry, Nov 25: "I want to make 5 of each most profitable items ... give me materials to make 5 spider
--   silk slippers and 5 woolen reagent bags". Right-click a recipe in Best crafts or the Recipe book,
--   say how many, and the goals window gets a "<prof> queue" group: the crafts (made / queued) and every
--   material they need, against what's in your bags and bank. A craft counts down as you make it and
--   leaves the queue when it's done. Right-click a craft line to drop it, the heading to clear the queue.
--   FA.Queue.Ask(prof, recipe)        the "Queue how many?" box
--   FA.Queue.Add(prof, recipe, n)     add n crafts (on top of any already queued)
--   FA.Queue.Remove(prof, name), Clear(prof)
--   FA.Queue.Groups() -> { { prof, crafts = { e, ... }, mats = { { id, name, need }, ... }, profit, cost }, ... }
--   FA.Queue.Made(prof, name, spellId) a craft of it was made (the cast listener calls it)
local FA = ForeverArtisan
local Q = {}
FA.Queue = Q
local say = FA.Printer and FA.Printer("Queue") or print
local AH_CUT = 0.95

---------------------------------------------------------------- saved (per character)
local function S()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.queue = s.queue or {}
  local key = FA.CharKey and FA.CharKey(s.queue) or "me"
  s.queue[key] = s.queue[key] or {}
  return s.queue[key] -- [prof] = { list = { e, ... } }, e = { name, n, made, id, itemId, makes, reagents }
end
Q._S = S -- for the test suite

local function Redraw()
  if FA.Track then
    if FA.Track.ShowList then FA.Track.ShowList() elseif FA.Track.Refresh then FA.Track.Refresh() end
  end
end

local function Find(prof, name)
  local p = S()[prof]
  for i, e in ipairs(p and p.list or {}) do if e.name == name then return e, i end end
end

function Q.Add(prof, r, n)
  n = math.floor(tonumber(n) or 0)
  if not (prof and type(r) == "table" and r.name) or n < 1 then return end
  local s = S()
  s[prof] = s[prof] or { list = {} }
  local e = Find(prof, r.name)
  if e then
    e.n = e.n + n
  else
    -- a copy of what it takes, so the queue keeps working with the profession window closed
    local reagents = {}
    for _, g in ipairs(r.reagents or {}) do
      if g.id then reagents[#reagents + 1] = { id = g.id, n = g.n or 1, name = g.name } end
    end
    e = { name = r.name, n = n, made = 0, id = r.id, itemId = r.itemId, makes = r.makes or 1, reagents = reagents }
    table.insert(s[prof].list, e)
  end
  say(("%s x%d queued. Its materials are in the goals window."):format(r.name, e.n - e.made))
  Redraw()
  return e
end

function Q.Remove(prof, name)
  local _, i = Find(prof, name)
  if i then table.remove(S()[prof].list, i) end
  if S()[prof] and #S()[prof].list == 0 then S()[prof] = nil end
  Redraw()
end

function Q.Clear(prof)
  S()[prof] = nil
  Redraw()
end

function Q.Has(prof) local p = S()[prof]; return p and #p.list > 0 or false end

---------------------------------------------------------------- crafting counts it down
function Q.Made(prof, name, spellId)
  for p, q in pairs(S()) do
    if not prof or p == prof then
      for i, e in ipairs(q.list or {}) do
        if (spellId and e.id and e.id == spellId) or (name and e.name == name) then
          e.made = e.made + 1
          if e.made >= e.n then
            table.remove(q.list, i)
            if #q.list == 0 then S()[p] = nil end
            say(("%s x%d done."):format(e.name, e.n))
          end
          if FA.Track and FA.Track.Refresh then FA.Track.Refresh() end
          return true
        end
      end
    end
  end
end

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then local i = C_Spell.GetSpellInfo(id); return i and i.name end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
do
  local ev = CreateFrame("Frame")
  pcall(ev.RegisterEvent, ev, "UNIT_SPELLCAST_SUCCEEDED")
  ev:SetScript("OnEvent", function(_, _, unit, _, spellId)
    if unit ~= "player" or not next(S()) then return end
    if FA.IsSecret and FA.IsSecret(spellId) then return end
    local ok, n = pcall(SpellName, spellId)
    Q.Made(nil, ok and n or nil, spellId)
  end)
end

---------------------------------------------------------------- what the goals window shows
local function Price(id)
  if not FA.ItemPrice then return nil end
  local ok, p = pcall(FA.ItemPrice, id)
  return ok and type(p) == "number" and p > 0 and p or nil
end
local function SalePrice(id)
  if not id then return nil end
  -- "Sell to a vendor" ticked: the queue's profit is what a vendor pays, like Best crafts (0.9.56;
  -- Kerry's goals window said profit ~28c on Linen Belts that lose 40c each at the vendor)
  if FA.VendorOnly and FA.VendorOnly() then
    local ok, v = pcall(FA.VendorSell or function() end, id)
    return ok and type(v) == "number" and v > 0 and v or nil
  end
  if not FA.AHPrice then return nil end
  local ok, p = pcall(FA.AHPrice, id)
  return ok and type(p) == "number" and p > 0 and math.floor(p * AH_CUT) or nil
end

---------------------------------------------------------------- AH or make
-- Each crafting module hands over its recipes; a material one of your learned recipes makes from plain
-- materials (Bolt of Woolen Cloth from Wool Cloth) gets "AH or make", like the plan's shopping lists.
local books = {}
function Q.Register(prof, fn) books[prof] = fn end
local function Makers(prof)
  local fn = books[prof]
  local ok, recs = false, nil
  if fn then ok, recs = pcall(fn) end
  if not (ok and type(recs) == "table") then return {} end
  local makes = {}
  for _, r in pairs(recs) do
    if type(r) == "table" and r.learned and r.itemId and type(r.reagents) == "table" and #r.reagents > 0 then
      makes[r.itemId] = makes[r.itemId] or r
    end
  end
  -- plain: every material it takes is bought, not made (no chains)
  for id, r in pairs(makes) do
    for _, g in ipairs(r.reagents) do if not g.id or makes[g.id] then makes[id] = nil; break end end
  end
  return makes
end

function Q.Groups()
  local out, profs = {}, {}
  for p, q in pairs(S()) do if q.list and #q.list > 0 then profs[#profs + 1] = p end end
  table.sort(profs)
  for _, prof in ipairs(profs) do
    local need, order, names = {}, {}, {}
    local cost, sale, priced = 0, 0, true
    for _, e in ipairs(S()[prof].list) do
      local left = math.max(0, e.n - e.made)
      for _, g in ipairs(e.reagents or {}) do
        if not need[g.id] then order[#order + 1] = g.id end
        need[g.id] = (need[g.id] or 0) + left * (g.n or 1)
        names[g.id] = names[g.id] or g.name
        local p = Price(g.id)
        if p then cost = cost + p * left * (g.n or 1) else priced = false end
      end
      local sp = SalePrice(e.itemId)
      if sp then sale = sale + sp * left * (e.makes or 1) else priced = false end
    end
    local mats, makes = {}, Makers(prof)
    for _, id in ipairs(order) do
      local m = { id = id, name = names[id], need = need[id] }
      local r = makes[id]
      if r then
        local from = {}
        for _, g in ipairs(r.reagents) do from[#from + 1] = { id = g.id, name = g.name, n = g.n or 1 } end
        m.alt = { makes = r.makes or 1, from = from }
      end
      mats[#mats + 1] = m
    end
    out[#out + 1] = { prof = prof, crafts = S()[prof].list, mats = mats,
      profit = priced and (sale - cost) or nil, cost = priced and cost or nil }
  end
  return out
end

---------------------------------------------------------------- "Queue how many?"
local asking
function Q.Ask(prof, r)
  if not (prof and type(r) == "table" and r.name) then return end
  asking = { prof = prof, r = r }
  if not StaticPopupDialogs or not StaticPopup_Show then return Q.Add(prof, r, 1) end
  StaticPopupDialogs.FOREVERARTISAN_QUEUE = StaticPopupDialogs.FOREVERARTISAN_QUEUE or {
    text = "Queue how many %s?",
    button1 = "Queue", button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 4, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    OnShow = function(self)
      local eb = self.editBox or self.EditBox
      if eb then eb:SetNumeric(true); eb:SetText("5"); eb:HighlightText(); eb:SetFocus() end
    end,
    OnAccept = function(self)
      local eb = self.editBox or self.EditBox
      if asking then Q.Add(asking.prof, asking.r, eb and tonumber(eb:GetText()) or 0) end
    end,
    EditBoxOnEnterPressed = function(self)
      local parent = self:GetParent()
      if asking then Q.Add(asking.prof, asking.r, tonumber(self:GetText()) or 0) end
      parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  }
  StaticPopup_Show("FOREVERARTISAN_QUEUE", r.name)
end

---------------------------------------------------------------- /fa queue
function Q.Slash(rest)
  rest = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if rest == "clear" then
    for p in pairs(S()) do S()[p] = nil end
    say("Queue cleared.")
    Redraw()
    return
  end
  local any = false
  for _, g in ipairs(Q.Groups()) do
    any = true
    local parts = {}
    for _, e in ipairs(g.crafts) do parts[#parts + 1] = ("%s %d/%d"):format(e.name, e.made, e.n) end
    say(g.prof .. ": " .. table.concat(parts, ", ") .. (g.profit and ("  (" .. (g.profit >= 0 and "profit" or "loss") .. " ~" .. FA.Money(math.abs(g.profit)) .. ")") or ""))
  end
  if not any then say("Nothing queued. Right-click a recipe in Best crafts or the Recipe book to queue it.") end
end
