-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: the on-screen goals list (like quest objectives).
--   Shopping list items you track (right-click a row, or Track all) and your gathering goals, in one
--   small list you can move, lock or hide. Everything counts bags + bank, so buying, looting,
--   fishing or gathering all move it (a gathering Progress tab still counts this session).
--   FA.Track.IsTracked(prof, id)          true when that shopping list item is on screen
--   FA.Track.Toggle(prof, e)              track or untrack one shopping list entry { id, name, need }
--   FA.Track.TrackAll(prof, list)         track every item on the list; FA.Track.UntrackAll(prof)
--   FA.Track.AllOn(prof)                  true while Track all is on for that profession
--   FA.Track.Sync(prof, list)             the plan changed: amounts follow it, items it dropped go
--   FA.Track.Goals(prof, rowsFn, knowsFn) a gathering module's goals (ns.GoalRows) show here too, on
--                                         characters that have the profession (knowsFn)
--   FA.Track.Lines()                      { { title, lines = { { id, name, have, want, note, done } } } }
--   FA.Track.Refresh()                    redraw now
local FA = ForeverArtisan
local T = {}
FA.Track = T
local GOLD, GRAY, GREEN = "|cffd4a94e", "|cff9d9d9d", "|cff40ff40"
local say = FA.Printer and FA.Printer() or print
local DONE_HOLD = 8 -- seconds a finished line stays green before it drops off

---------------------------------------------------------------- saved state (per character)
local function S()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.track = s.track or {}
  local key = FA.CharKey(s.track)
  local t = s.track[key]
  if not t then t = {}; s.track[key] = t end
  t.items = t.items or {}   -- [prof] = { [id] = { name, want } }
  t.all = t.all or {}       -- [prof] = true while Track all is on
  return t
end

local CountAPI = (C_Item and C_Item.GetItemCount) or GetItemCount
local function Own(id)
  local ok, n = pcall(CountAPI, id)
  n = (ok and tonumber(n)) or 0
  if FA.BankCount then n = n + (FA.BankCount(id) or 0) end
  return n
end

-- trade goods the gathering professions bring in: grouped under that profession on screen
local InstantAPI = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GATHER_SUB = { [7] = "Mining", [9] = "Herbalism", [6] = "Skinning" }
local function GatheredBy(id)
  if not InstantAPI then return end
  local ok, _, _, _, _, _, classID, subID = pcall(InstantAPI, id)
  if ok and classID == 7 then return GATHER_SUB[subID] end
end

-- the shopping list entries we can track: real items, not "Train ..." lines
local function Trackable(e) return e and type(e.id) == "number" and not e.train and (e.need or 0) > 0 end

local Refresh -- below

function T.IsTracked(prof, id)
  local p = S().items[prof]
  return (p and id and p[id]) and true or false
end
function T.AllOn(prof) return S().all[prof] and true or false end

function T.Toggle(prof, e)
  if not Trackable(e) then return end
  local s = S()
  s.items[prof] = s.items[prof] or {}
  local p = s.items[prof]
  if p[e.id] then
    p[e.id] = nil
    s.all[prof] = nil
  else
    p[e.id] = { name = e.name, want = e.need }
    s.hidden = nil
  end
  Refresh()
  return p[e.id] ~= nil
end

function T.TrackAll(prof, list)
  local s = S()
  s.items[prof] = s.items[prof] or {}
  local n = 0
  for _, e in ipairs(list or {}) do
    if Trackable(e) and e.have < e.need then s.items[prof][e.id] = { name = e.name, want = e.need }; n = n + 1 end
  end
  s.all[prof] = true
  s.hidden = nil
  Refresh()
  return n
end

function T.UntrackAll(prof)
  local s = S()
  s.items[prof], s.all[prof] = nil, nil
  Refresh()
end

-- the shopping list was rebuilt (new target, new recipes): amounts follow the plan, items the
-- plan no longer needs drop off, and with Track all on, new items join
function T.Sync(prof, list)
  local s = S()
  local p = s.items[prof]
  if not p and not s.all[prof] then return end
  p = p or {}
  local seen = {}
  for _, e in ipairs(list or {}) do
    if Trackable(e) then
      seen[e.id] = true
      if p[e.id] then p[e.id].want, p[e.id].name = e.need, e.name or p[e.id].name
      elseif s.all[prof] and e.have < e.need then p[e.id] = { name = e.name, want = e.need } end
    end
  end
  for id in pairs(p) do if not seen[id] then p[id] = nil end end
  s.items[prof] = next(p) and p or nil
  Refresh()
end

---------------------------------------------------------------- gathering goals
local goalSources, goalKnows, goalRemove = {}, {}, {} -- [prof] = ns.GoalRows, has the profession, ns.RemoveGoal
function T.Goals(prof, rowsFn, knowsFn, removeFn)
  goalSources[prof], goalKnows[prof], goalRemove[prof] = rowsFn, knowsFn, removeFn
end

-- right-click a line on screen: stop tracking it (a gathering goal is removed, like its Remove button)
function T.Untrack(prof, id)
  local s = S()
  local p = s.items[prof]
  if p then p[id] = nil; if not next(p) then s.items[prof] = nil end end
  s.all[prof] = nil
  Refresh()
end
function T.RemoveLine(ln)
  if not ln then return end
  S().removedOnce = true -- they've found it: the hint under the list can go
  if ln.shopProf then T.Untrack(ln.shopProf, ln.id)
  elseif ln.goalProf and goalRemove[ln.goalProf] and ln.goalIndex then
    pcall(goalRemove[ln.goalProf], ln.goalIndex)
    Refresh()
  end
end

---------------------------------------------------------------- what to show
local doneAt = {} -- [key] = time it was first seen done (the line drops off a little later)
local goalSeen -- goal keys seen so far this session: a new one brings a hidden list back
local function Now() return (GetTime and GetTime()) or 0 end

local ORDER = { Mining = 1, Herbalism = 2, Skinning = 3, Fishing = 4 }
function T.Lines()
  local groups, byTitle = {}, {}
  -- sub: an optional gray note after the heading (a separate group with the same title)
  local function Group(title, sub)
    local k = title .. "|" .. (sub or "")
    local g = byTitle[k]
    if not g then g = { title = title, sub = sub, lines = {} }; byTitle[k] = g; groups[#groups + 1] = g end
    return g
  end
  local now, s = Now(), S()
  local function Add(title, key, line, sub)
    line.done = line.have >= line.want
    if line.done then
      doneAt[key] = doneAt[key] or now
      line.gone = (now - doneAt[key]) >= DONE_HOLD
    else
      doneAt[key] = nil
    end
    if not line.gone then table.insert(Group(title, sub).lines, line) end
    return line
  end
  -- shopping list items: gathered ones under the gathering profession, the rest under "<prof> shopping"
  local profs = {}
  for prof in pairs(s.items) do profs[#profs + 1] = prof end
  table.sort(profs)
  for _, prof in ipairs(profs) do
    local ids = {}
    for id in pairs(s.items[prof]) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (s.items[prof][a].name or "") < (s.items[prof][b].name or "") end)
    for _, id in ipairs(ids) do
      local it = s.items[prof][id]
      local by = GatheredBy(id)
      local line = Add(by or (prof .. " shopping"), "s:" .. prof .. ":" .. id,
        { id = id, name = it.name or ("item " .. id), have = Own(id), want = it.want or 1, note = by and prof or nil,
          shopProf = prof })
      -- finished and gone: no longer tracked
      if line.gone then s.items[prof][id] = nil end
    end
    if not next(s.items[prof]) then s.items[prof] = nil; s.all[prof] = nil end
  end
  -- goals set by hand on a gathering Progress tab
  local gp, newSeen = {}, {}
  for prof in pairs(goalSources) do gp[#gp + 1] = prof end
  table.sort(gp, function(a, b) return (ORDER[a] or 9) < (ORDER[b] or 9) end)
  for _, prof in ipairs(gp) do
    -- goals are saved for the whole account: only a character with the profession sees them
    local kf = goalKnows[prof]
    local okK, knows = true, true
    if kf then okK, knows = pcall(kf) end
    local ok, rows = false, nil
    if okK and knows then ok, rows = pcall(goalSources[prof]) end
    for _, g in ipairs(ok and rows or {}) do
      local key = "g:" .. prof .. ":" .. tostring(g.id)
      -- a goal you just added shows, even if you closed the list earlier
      if goalSeen and not goalSeen[key] then s.hidden = nil end
      newSeen[key] = true
      Add(prof, key,
        -- on screen, a goal counts what you hold however you got it (bags + bank), like the shopping
        -- list; the module's own Progress tab still shows what you gathered this session
        { id = g.id, name = g.name or "?", have = (type(g.id) == "number") and Own(g.id) or (g.have or 0),
          want = g.want or 1, goalProf = prof, goalIndex = g.i })
    end
  end
  goalSeen = newSeen
  -- gathering groups first, in the usual order, then the shopping groups
  table.sort(groups, function(a, b)
    local oa, ob = ORDER[a.title] or 9, ORDER[b.title] or 9
    if oa ~= ob then return oa < ob end
    if (a.sub ~= nil) ~= (b.sub ~= nil) then return b.sub ~= nil end
    return a.title < b.title
  end)
  for i = #groups, 1, -1 do if #groups[i].lines == 0 then table.remove(groups, i) end end
  return groups
end

---------------------------------------------------------------- the frame
local f, pool, ROW_H, W = nil, {}, 15, 230

local function Build()
  f = CreateFrame("Frame", "ForeverArtisanGoalsFrame", UIParent)
  f:SetSize(W, 40)
  f:SetFrameStrata("LOW")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not S().locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    S().pos = { point, rel, x, y }
  end)
  f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0, 0, 0, 0.35)
  f.title = FA.UI.Text(f, "GameFontNormal", "TOPLEFT", 6, -4)
  f.title:SetText(GOLD .. "Goals|r")
  -- hide (fold to the title) and close
  f.fold = CreateFrame("Button", nil, f); f.fold:SetSize(16, 16); f.fold:SetPoint("TOPRIGHT", -22, -2)
  f.fold.t = FA.UI.Text(f.fold, "GameFontHighlight", "CENTER", 0, 0); f.fold.t:SetText("-")
  f.fold:SetScript("OnClick", function() local s = S(); s.folded = not s.folded or nil; Refresh() end)
  f.close = CreateFrame("Button", nil, f); f.close:SetSize(16, 16); f.close:SetPoint("TOPRIGHT", -4, -2)
  f.close.t = FA.UI.Text(f.close, "GameFontHighlight", "CENTER", 0, 0); f.close.t:SetText("x")
  f.close:SetScript("OnClick", function()
    S().hidden = true; Refresh()
    say("Goals list hidden. /fa goals brings it back.")
  end)
  FA.UI.Tip(f.fold, function() GameTooltip:AddLine("Fold or unfold the list") end)
  FA.UI.Tip(f.close, function()
    GameTooltip:AddLine("Hide the goals list")
    GameTooltip:AddLine("/fa goals shows it again. Your tracked items stay.", 1, 1, 1, true)
  end)
  local pos = S().pos
  if pos then f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
  else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -330) end
end

local function Line(i)
  local l = pool[i]
  if not l then
    l = {}
    l.text = FA.UI.Text(f, "GameFontHighlightSmall", "TOPLEFT", 0, 0)
    l.text:SetWidth(W - 16); l.text:SetWordWrap(false)
    l.bar = FA.UI.Bar(f, W - 26, 2)
    -- the line is a button: hover for the item, right-click to stop tracking it
    l.btn = CreateFrame("Button", nil, f)
    l.btn:SetPoint("TOPLEFT", l.text, "TOPLEFT", 0, 1); l.btn:SetSize(W - 20, ROW_H)
    l.btn:RegisterForClicks("RightButtonUp")
    l.btn:SetScript("OnClick", function(self) T.RemoveLine(self.ln) end)
    l.btn:SetScript("OnEnter", function(self)
      local ln = self.ln
      if not ln then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      if ln.id and GameTooltip.SetItemByID then GameTooltip:SetItemByID(ln.id) else GameTooltip:AddLine(ln.name or "") end
      GameTooltip:AddLine(ln.goalProf and "Right-click to remove this goal" or "Right-click to stop tracking it", 0.5, 0.75, 1)
      GameTooltip:Show()
    end)
    l.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pool[i] = l
  end
  return l
end

function Refresh()
  local s = S()
  local groups = T.Lines()
  if s.hidden or #groups == 0 then
    if f then f:Hide() end
    return
  end
  if not f then Build() end
  f:Show()
  -- locked: clicks pass through to the world (the fold and close buttons still work)
  f:EnableMouse(not s.locked)
  f.fold.t:SetText(s.folded and "+" or "-")
  local y, i = -22, 0
  if not s.folded then
    for _, g in ipairs(groups) do
      i = i + 1
      local h = Line(i)
      h.text:ClearAllPoints(); h.text:SetPoint("TOPLEFT", 8, y)
      h.text:SetFontObject("GameFontNormalSmall")
      h.text:SetText(GOLD .. g.title .. "|r" .. (g.sub and (GRAY .. "  (" .. g.sub .. ")|r") or "")); h.text:Show(); h.bar:Hide(); h.btn:Hide(); h.btn.ln = nil
      y = y - ROW_H
      for _, ln in ipairs(g.lines) do
        i = i + 1
        local l = Line(i)
        l.text:ClearAllPoints(); l.text:SetPoint("TOPLEFT", 16, y)
        l.text:SetFontObject("GameFontHighlightSmall")
        local count = ("%d / %d"):format(math.min(ln.have, ln.want), ln.want)
        l.text:SetText(ln.done and (GREEN .. ln.name .. "  " .. count .. "  done|r")
          or (ln.name .. "  " .. count .. (ln.note and (GRAY .. "  (" .. ln.note .. ")|r") or "")))
        l.text:Show()
        l.btn.ln = ln; l.btn:EnableMouse(not s.locked); l.btn:Show()
        l.bar:ClearAllPoints(); l.bar:SetPoint("TOPLEFT", 16, y - ROW_H + 3)
        l.bar:Set(ln.have / math.max(ln.want, 1), ln.done and "done" or nil); l.bar:SetShown(not ln.done)
        y = y - ROW_H - 2
      end
      y = y - 2
    end
  end
  for k = i + 1, #pool do pool[k].text:Hide(); pool[k].bar:Hide(); pool[k].btn:Hide(); pool[k].btn.ln = nil end
  -- a small hint under the list (hidden while locked: lines don't take clicks then)
  if not f.hint then
    f.hint = FA.UI.Text(f, "GameFontDisableSmall", "TOPLEFT", 8, 0)
    f.hint:SetText("Right-click a line to remove it")
  end
  if not s.folded and not s.locked then
    f.hint:ClearAllPoints(); f.hint:SetPoint("TOPLEFT", 8, y - 2); f.hint:Show()
    y = y - ROW_H
  else
    f.hint:Hide()
  end
  f:SetHeight(-y + 4)
end
T.Refresh = Refresh

---------------------------------------------------------------- /fa goals
function T.Slash(rest)
  local r = (rest or ""):lower()
  local s = S()
  if r == "lock" then s.locked = true; say("Goals list locked in place. /fa goals unlock to move it.")
  elseif r == "unlock" then s.locked = nil; say("Goals list unlocked: drag it to move it.")
  elseif r == "reset" then
    s.pos = nil
    if f then f:ClearAllPoints(); f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -330) end
    s.hidden = nil
    say("Goals list moved back to its first spot.")
  elseif r == "clear" then
    s.items, s.all = {}, {}
    say("Stopped tracking shopping list items. Gathering goals stay (remove them on their Progress tab).")
  elseif r == "hide" then s.hidden = true; say("Goals list hidden. /fa goals brings it back.")
  else
    s.hidden = not s.hidden or nil
    if s.hidden then say("Goals list hidden. /fa goals brings it back.")
    elseif #T.Lines() == 0 then
      say("Nothing to track yet. Right-click an item on a shopping list (any crafting Progress tab), or set a gathering goal.")
    end
  end
  Refresh()
  if r ~= "hide" and r ~= "lock" and r ~= "unlock" and r ~= "reset" and r ~= "clear" then
    print(GRAY .. "  /fa goals  show or hide  ·  lock | unlock | reset | clear|r")
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function() Refresh() end)
-- counts change as you loot, buy and bank, and gathering goals count on their own: a light redraw
-- every second covers all of it (also while the list is hidden, so a new goal can bring it back)
local acc = 0
ev:SetScript("OnUpdate", function(_, el)
  acc = acc + (el or 0)
  if acc >= 1 then acc = 0; Refresh() end
end)
