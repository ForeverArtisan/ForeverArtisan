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
--   FA.Track.Planner(prof, fn)            fn() = the module's shopping list now; tracked lists follow it
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
  if T._gatheredBy then return T._gatheredBy(id) end -- the test suite
  if not InstantAPI then return end
  local ok, _, _, _, _, _, classID, subID = pcall(InstantAPI, id)
  if ok and classID == 7 then return GATHER_SUB[subID] end
end

-- the shopping list entries we can track: real items, and "Train ..." lines (0.9.52, Kerry: "add
-- training to this list"). A Train line is saved under "train:<name>" with its trainer.
local function Trackable(e)
  if not e then return false end
  if e.train then return type(e.name) == "string" end
  return type(e.id) == "number" and (e.need or 0) > 0
end
local function Key(e) return e.train and ("train:" .. e.name) or e.id end
local function Mini(n)
  if type(n) ~= "table" then return nil end
  return { n = n.n, s = n.s, z = n.z, m = n.m, x = n.x, y = n.y, id = n.id }
end
local function Saved(e)
  if e.train then return { name = e.name, want = 1, train = { at = e.train.at, who = e.train.who, npc = Mini(e.train.npc) } } end
  return { name = e.name, want = e.need, alt = e.alt }
end

local Refresh -- below

function T.IsTracked(prof, id)
  local p = S().items[prof]
  return (p and id and p[id]) and true or false
end
function T.AllOn(prof) return S().all[prof] and true or false end

function T.Toggle(prof, e)
  -- the "Train now" line: every recipe on it at once (on unless they're all on already)
  if e and e.group then
    local s = S()
    s.items[prof] = s.items[prof] or {}
    local p, allOn = s.items[prof], true
    for _, x in ipairs(e.group) do if Trackable(x) and not p[Key(x)] then allOn = false end end
    for _, x in ipairs(e.group) do
      if Trackable(x) then if allOn then p[Key(x)] = nil else p[Key(x)] = Saved(x) end end
    end
    if allOn then s.all[prof] = nil else s.hidden = nil end
    if not next(p) then s.items[prof] = nil end
    Refresh()
    return not allOn
  end
  if not Trackable(e) then return end
  local s = S()
  s.items[prof] = s.items[prof] or {}
  local p, k = s.items[prof], Key(e)
  if p[k] then
    p[k] = nil
    s.all[prof] = nil
  else
    p[k] = Saved(e)
    s.hidden = nil
  end
  Refresh()
  return p[k] ~= nil
end

-- a Train line is on screen (any profession): for the check mark on shopping lists
function T.TrainTracked(name)
  for _, p in pairs(S().items) do if p["train:" .. tostring(name)] then return true end end
  return false
end

function T.TrackAll(prof, list)
  local s = S()
  s.items[prof] = s.items[prof] or {}
  local n = 0
  for _, e in ipairs(list or {}) do
    -- (what the plan makes itself, like bolts from cloth, stays off: its cloth is on the list instead.
    -- Kerry, Nov 22: Bolt of Silk Cloth 0/100 next to Silk Cloth 0/400)
    if Trackable(e) and not e.craft and (e.have or 0) < (e.need or 1) then s.items[prof][Key(e)] = Saved(e); n = n + 1 end
  end
  s.all[prof] = true
  s.hidden = nil
  Refresh()
  return n
end

-- the shopping list popped out: make sure the goals window is on screen and unfolded (0.9.55)
function T.ShowList()
  local s = S()
  s.hidden, s.folded = nil, nil
  Refresh()
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
      local k = Key(e)
      seen[k] = true
      if p[k] and e.craft and s.all[prof] then
        p[k] = nil -- the plan makes it now: Track all doesn't keep it
      elseif p[k] then
        if e.train then p[k] = Saved(e) else p[k].want, p[k].name, p[k].alt = e.need, e.name or p[k].name, e.alt end
      elseif s.all[prof] and not e.craft and (e.have or 0) < (e.need or 1) then p[k] = Saved(e) end
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
  if ln.planProf and FA.PlanPop then FA.PlanPop.Toggle(ln.planProf, false)
  elseif ln.shopProf then T.Untrack(ln.shopProf, ln.key or ln.id)
  elseif ln.goalProf and goalRemove[ln.goalProf] and ln.goalIndex then
    pcall(goalRemove[ln.goalProf], ln.goalIndex)
    Refresh()
  end
end

-- right-click a heading: that whole group is done (Kerry, Nov 25: "close out goals from the popout").
-- "<prof> plan" or "<prof> shopping": the profession comes out (Pop in, or its tracked list);
-- a gathering heading: every line under it.
function T.RemoveGroup(g)
  if not g then return end
  S().removedOnce = true
  local prof = g.plan or (type(g.title) == "string" and g.title:match("^(.+) shopping$"))
  if prof then
    if FA.PlanPop and FA.PlanPop.IsOn and FA.PlanPop.IsOn(prof) then FA.PlanPop.Toggle(prof, false) end
    T.UntrackAll(prof)
    return
  end
  local goals = {}
  for _, ln in ipairs(g.lines or {}) do
    if ln.shopProf then
      local p = S().items[ln.shopProf]
      if p then p[ln.key or ln.id] = nil; if not next(p) then S().items[ln.shopProf] = nil end end
      S().all[ln.shopProf] = nil
    elseif ln.goalProf and ln.goalIndex then
      goals[#goals + 1] = ln
    end
  end
  -- gathering goals by index: the last first, so the others keep their place
  table.sort(goals, function(a, b) return a.goalIndex > b.goalIndex end)
  for _, ln in ipairs(goals) do
    if goalRemove[ln.goalProf] then pcall(goalRemove[ln.goalProf], ln.goalIndex) end
  end
  Refresh()
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
      -- a done line whose item another list still needs stays (green), so the shared count adds up
      line.gone = (now - doneAt[key]) >= DONE_HOLD and not line.hold
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
  -- the same item on more than one list (Hot Spices for Cooking and First Aid): what you hold counts
  -- once, filling the lists in order, and each line says how many to buy in all (Kerry, Nov 22)
  local total, lists, left = {}, {}, {}
  for _, prof in ipairs(profs) do
    for id, it in pairs(s.items[prof]) do
      if type(id) == "number" then
        total[id] = (total[id] or 0) + (it.want or 1)
        lists[id] = lists[id] or {}
        table.insert(lists[id], prof)
      end
    end
  end
  for id, l in pairs(lists) do if #l > 1 then left[id] = Own(id) end end
  for _, prof in ipairs(profs) do
    local ids = {}
    for id in pairs(s.items[prof]) do ids[#ids + 1] = id end
    -- training first, in the order you'll learn it (Kerry's screenshot, Nov 22: by name, "at 120" came
    -- first), then the items by name
    table.sort(ids, function(a, b)
      local ta, tb = type(a) == "string", type(b) == "string"
      if ta ~= tb then return ta end
      local ia, ib = s.items[prof][a], s.items[prof][b]
      if ta then
        local aa, ab = ia.train and ia.train.at or 0, ib.train and ib.train.at or 0
        if aa ~= ab then return aa < ab end
      end
      return (ia.name or "") < (ib.name or "")
    end)
    for _, id in ipairs(ids) do
      local it = s.items[prof][id]
      if type(id) == "string" then
        -- a Train line: it drops off once you've learned it (the plan stops listing it). With the plan
        -- popped out it says "train at 80" there already, so the shopping list leaves it out (Kerry,
        -- Nov 22: "Redundant?")
        -- Only training a plan row shows: a recipe the plan uses just to make a material (Bolt of Woolen
        -- Cloth for the capes) has no row of its own, so it stays here (Kerry, Nov 22: "bolt of woolen
        -- cloth is not on the list?")
        if not (FA.PlanPop and FA.PlanPop.IsOn and FA.PlanPop.IsOn(prof) and T.PlanTrains(prof, it.name or id)) then
          Add(prof .. " shopping", "s:" .. prof .. ":" .. id,
            { key = id, name = it.name or id, have = 0, want = 1, train = it.train or {}, shopProf = prof })
        end
      else
      local by = GatheredBy(id)
      -- under the gathering profession only when this character has it; otherwise it's shopping
      -- (Kerry, Nov 22: "Why does it show skinning. She doesn't have skinning?")
      if by and goalKnows[by] then
        local okK, knows = pcall(goalKnows[by])
        if okK and not knows then by = nil end
      end
      local want, have, shared, hold = it.want or 1, Own(id), nil, nil
      -- AH or make (bolts): the cloth for them counts too, past what the cloth's own line needs
      local altNote
      if it.alt and FA.AltHave then
        local mine = s.items[prof]
        have = FA.AltHave(it.alt, math.max(0, have), function(g)
          local other = type(mine[g]) == "table" and (mine[g].want or 0) or 0
          return Own(g) - other
        end)
        altNote = FA.AltNote(it.alt, want - have)
      end
      if left[id] then
        local own = have
        have = math.min(left[id], want)
        left[id] = left[id] - have
        shared = { total = total[id], own = own, lists = lists[id], buy = math.max(0, total[id] - own) }
        if shared.buy > 0 then hold = true end
      end
      local line = Add(by or (prof .. " shopping"), "s:" .. prof .. ":" .. id,
        { id = id, name = it.name or ("item " .. id), have = have, want = want, note = altNote or (by and prof) or nil,
          shopProf = prof, shared = shared, hold = hold })
      -- finished and gone: no longer tracked
      if line.gone then s.items[prof][id] = nil end
      end
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
  -- popped-out plans (Core PlanWindow.lua): "<prof> plan" right above "<prof> shopping" (0.9.55, Kerry:
  -- one Pop out puts the plan and the shopping list in this window)
  if FA.PlanPop and FA.PlanPop.Groups then
    local okP, plans = pcall(FA.PlanPop.Groups, true)
    for _, pg in ipairs(okP and plans or {}) do
      local g = Group(pg.prof .. " plan", pg.sub)
      g.plan = pg.prof
      if pg.note then g.lines[#g.lines + 1] = { planNote = pg.note, name = "", have = 0, want = 1, planProf = pg.prof } end
      for _, d in ipairs(pg.rows) do
        g.lines[#g.lines + 1] = { plan = d, planProf = pg.prof, name = d.left or "", have = 0, want = 1 }
      end
    end
  end
  -- gathering groups first, in the usual order, then the shopping groups
  -- (a profession's plan right above its shopping list: Kerry's screenshot had the plan last)
  local function base(g) return g.plan or (g.title:gsub(" shopping$", "")) end
  table.sort(groups, function(a, b)
    local oa, ob = ORDER[a.title] or 9, ORDER[b.title] or 9
    if oa ~= ob then return oa < ob end
    local ba, bb = base(a), base(b)
    if ba ~= bb then return ba < bb end
    if (a.plan ~= nil) ~= (b.plan ~= nil) then return a.plan ~= nil end
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
  if FA.UI.Badge then FA.UI.Badge(f, f.title) end
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

-- the nearest vendor you've met (or Questie's) who sells a line's item, or nil
function T.Nearest(ln)
  if ln and ln.train then return ln.train.npc end -- a Train line: its trainer
  if not (ln and type(ln.id) == "number" and FA.VendorNPC) then return nil end
  local ok, npc = pcall(FA.VendorNPC, ln.id, ln.name)
  return ok and npc or nil
end

-- left-click a line: search it at the Auction House when it's open, else a waypoint to the nearest vendor
function T.GoTo(ln)
  if ln and ln.train then
    local npc = ln.train.npc
    if npc and FA.Vendors and FA.Vendors.waypoint then FA.Vendors.waypoint(npc) return end
    say(("No trainer known yet for %s. Trade Contacts finds trainers you meet (or Questie's)."):format(ln.name or "that"))
    return
  end
  if not ln or type(ln.id) ~= "number" then return end
  if FA.SearchAH and FA.SearchAH(ln.name) then return end
  local npc = T.Nearest(ln)
  if npc and FA.Vendors and FA.Vendors.waypoint then FA.Vendors.waypoint(npc) return end
  say(("No vendor you've met sells %s. At the Auction House, click it here to search for it."):format(ln.name or "that"))
end

local function Line(i)
  local l = pool[i]
  if not l then
    l = {}
    l.text = FA.UI.Text(f, "GameFontHighlightSmall", "TOPLEFT", 0, 0)
    l.text:SetWidth(W - 16); l.text:SetWordWrap(false); l.text:SetText("")
    -- a plan row's right side ("train at 55  skill 75-81")
    l.right = FA.UI.Text(f, "GameFontHighlightSmall", "TOPLEFT", 0, 0); l.right:SetJustifyH("RIGHT"); l.right:SetText("")
    l.bar = FA.UI.Bar(f, W - 26, 2)
    -- the line is a button: hover for the item, click for the nearest vendor (at the Auction House:
    -- search it), right-click to stop tracking it (left-click: Discord ask, Nov 22). A heading folds its
    -- group; a plan row opens its profession.
    l.btn = CreateFrame("Button", nil, f)
    l.btn:SetPoint("TOPLEFT", l.text, "TOPLEFT", 0, 1); l.btn:SetSize(W - 20, ROW_H)
    l.btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    l.btn:SetScript("OnClick", function(self, button)
      local ln = self.ln
      if not ln then return end
      if ln.head and button == "RightButton" then T.RemoveGroup(ln.group) return end
      if ln.head then
        local st = S(); st.foldG = st.foldG or {}
        st.foldG[ln.head] = not st.foldG[ln.head] or nil
        Refresh()
        return
      end
      if button == "RightButton" then T.RemoveLine(ln) return end
      if ln.plan then
        -- a recipe still to train: a waypoint to its trainer (Kerry, Nov 22: "Clicking on woolen cape should
        -- point you to trainer?"); one you know: its profession window
        local t = ln.plan.train
        if t then
          T.GoTo({ train = t, name = (ln.plan.left or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+x%d.*$", ""):gsub("%s+about.*$", "") })
          return
        end
        if FA.PlanPop and FA.PlanPop.Open then FA.PlanPop.Open(ln.planProf) end
        return
      end
      if ln.planProf then return end
      T.GoTo(ln)
    end)
    l.btn:SetScript("OnEnter", function(self)
      local ln = self.ln
      if not ln then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      if ln.head then
        GameTooltip:AddLine(ln.head)
        GameTooltip:AddLine("Click to fold or unfold it", 0.5, 0.75, 1)
        GameTooltip:AddLine((ln.group and (ln.group.plan or (ln.group.title or ""):find(" shopping$")))
          and "Right-click to close it out (the plan and its shopping list)" or "Right-click to remove everything under it", 0.5, 0.75, 1)
        GameTooltip:Show()
        return
      end
      if ln.plan then
        local d = ln.plan
        if d.id and GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.id) else GameTooltip:AddLine(d.tipTitle or "") end
        if d.tip then GameTooltip:AddLine(d.tip, 1, 1, 1, true) end
        local t = d.train
        if t and t.npc and t.npc.n then
          GameTooltip:AddLine("Click for a waypoint to " .. t.npc.n .. ", " .. (t.npc.s or t.npc.z or "?"), 0.5, 0.75, 1, true)
        elseif not t then
          GameTooltip:AddLine("Click to open " .. ln.planProf, 0.5, 0.75, 1, true)
        end
        GameTooltip:AddLine("Right-click to put the plan and shopping list back", 0.5, 0.75, 1, true)
        GameTooltip:Show()
        return
      end
      if ln.id and GameTooltip.SetItemByID then GameTooltip:SetItemByID(ln.id) else GameTooltip:AddLine(ln.name or "") end
      if ln.shared then
        local sh = ln.shared
        GameTooltip:AddLine(("On %d lists: %d in all. You have %d, so buy %d."):format(#sh.lists, sh.total, sh.own, sh.buy), 1, 1, 1, true)
      end
      local npc = T.Nearest(ln)
      if ln.train then
        if ln.train.who then GameTooltip:AddLine("Learn it at " .. (ln.train.at or "?") .. " from " .. ln.train.who, 1, 1, 1, true) end
        if npc and npc.n then GameTooltip:AddLine("Click for a waypoint to " .. npc.n .. ", " .. (npc.s or npc.z or "?"), 0.5, 0.75, 1, true) end
      elseif npc then
        GameTooltip:AddLine("Click for a waypoint to " .. npc.n .. ", " .. (npc.s or npc.z or "?")
          .. " (at the Auction House: search it)", 0.5, 0.75, 1, true)
      elseif type(ln.id) == "number" then
        GameTooltip:AddLine("At the Auction House: click to search it", 0.5, 0.75, 1)
      end
      GameTooltip:AddLine(ln.goalProf and "Right-click to remove this goal" or "Right-click to stop tracking it", 0.5, 0.75, 1)
      GameTooltip:Show()
    end)
    l.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pool[i] = l
  end
  return l
end

-- the window is wider while a plan shows (its rows say which skill range each craft covers)
local PLAN_W = 340

-- whether the popped-out plan has a row that says "train at" for this Train line ("Train Woolen Cape")
function T.PlanTrains(prof, trainName)
  local want = tostring(trainName or ""):gsub("^Train ", "")
  local d = FA.PlanPop and FA.PlanPop._data and FA.PlanPop._data[prof]
  for _, row in ipairs(d and d.rows or {}) do
    if row.train then
      local left = tostring(row.left or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      if left:sub(1, #want) == want then return true end
    end
  end
  return false
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
  local w = W
  for _, g in ipairs(groups) do if g.plan then w = PLAN_W end end
  f:SetWidth(w)
  -- locked: clicks pass through to the world (the fold and close buttons still work)
  f:EnableMouse(not s.locked)
  f.fold.t:SetText(s.folded and "+" or "-")
  local foldG = s.foldG or {}
  local y, i = -22, 0
  if not s.folded then
    for _, g in ipairs(groups) do
      i = i + 1
      local h = Line(i)
      local folded = foldG[g.title]
      h.text:ClearAllPoints(); h.text:SetPoint("TOPLEFT", 8, y); h.text:SetWidth(w - 16)
      h.text:SetFontObject("GameFontNormalSmall")
      h.text:SetText((folded and (GRAY .. "+ |r") or "") .. GOLD .. g.title .. "|r" .. (g.sub and (GRAY .. "  (" .. g.sub .. ")|r") or "")
        .. (folded and (GRAY .. "  " .. #g.lines .. "|r") or ""))
      h.text:Show(); h.right:SetText(""); h.right:Hide(); h.bar:Hide()
      -- a heading folds its group (Kerry, Nov 22: plan and shopping in one window, kept short)
      h.btn.ln = { head = g.title, group = g }; h.btn:SetSize(w - 20, ROW_H); h.btn:EnableMouse(not s.locked); h.btn:Show()
      y = y - ROW_H
      for _, ln in ipairs(folded and {} or g.lines) do
        i = i + 1
        local l = Line(i)
        l.text:ClearAllPoints(); l.text:SetPoint("TOPLEFT", 16, y)
        l.text:SetFontObject("GameFontHighlightSmall")
        l.right:SetText(""); l.right:Hide()
        if ln.planNote then
          l.text:SetWidth(w - 24); l.text:SetText(ln.planNote); l.text:Show()
          l.btn:Hide(); l.btn.ln = nil; l.bar:Hide()
          y = y - ROW_H
        elseif ln.plan then
          local d = ln.plan
          l.right:SetText(d.right or ""); l.right:SetWidth(0)
          local rw = tonumber(l.right.GetStringWidth and l.right:GetStringWidth()) or 0
          l.right:ClearAllPoints(); l.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, y); l.right:Show()
          l.text:SetWidth(math.max(80, w - 24 - rw - 8)); l.text:SetText(d.left or ""); l.text:Show()
          l.btn.ln = ln; l.btn:SetSize(w - 20, ROW_H); l.btn:EnableMouse(not s.locked); l.btn:Show()
          l.bar:Hide()
          y = y - ROW_H
        else
          l.text:SetWidth(w - 16)
          local count = ("%d / %d"):format(math.min(ln.have, ln.want), ln.want)
          if ln.train then count = ln.train.at and ("at " .. ln.train.at) or "" end
          -- on more than one list: how many to buy for all of them together
          if ln.shared and not ln.done and ln.shared.buy > 0 then
            count = count .. GRAY .. "  (buy " .. ln.shared.buy .. " in all)|r"
          end
          l.text:SetText(ln.done and (GREEN .. ln.name .. "  " .. count .. "  done|r")
            or (ln.name .. "  " .. count .. (ln.note and (GRAY .. "  (" .. ln.note .. ")|r") or "")))
          l.text:Show()
          l.btn.ln = ln; l.btn:SetSize(w - 20, ROW_H); l.btn:EnableMouse(not s.locked); l.btn:Show()
          l.bar:ClearAllPoints(); l.bar:SetPoint("TOPLEFT", 16, y - ROW_H + 3)
          l.bar:Set(ln.have / math.max(ln.want, 1), ln.done and "done" or nil); l.bar:SetShown(not ln.done and not ln.train)
          y = y - ROW_H - 2
        end
      end
      y = y - 2
    end
  end
  for k = i + 1, #pool do pool[k].text:Hide(); pool[k].right:Hide(); pool[k].bar:Hide(); pool[k].btn:Hide(); pool[k].btn.ln = nil end
  -- a small hint under the list (hidden while locked: lines don't take clicks then)
  if not f.hint then
    f.hint = FA.UI.Text(f, "GameFontDisableSmall", "TOPLEFT", 8, 0)
    f.hint:SetText("Click: go there  ·  Right-click: remove  ·  Heading: click to fold, right-click to close")
  end
  if not s.folded and not s.locked then
    f.hint:ClearAllPoints(); f.hint:SetPoint("TOPLEFT", 8, y - 2); f.hint:SetWidth(w - 16); f.hint:Show()
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
    -- back to its first spot, unfolded (Kerry, Nov 22: folded in the top-left corner under the
    -- character portrait, it looked gone)
    s.pos, s.folded = nil, nil
    if f then f:ClearAllPoints(); f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -330) end
    s.hidden = nil
    say("Goals list moved back to its first spot and unfolded.")
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

---------------------------------------------------------------- fresh amounts
-- a crafting module's shopping list for its current target (nil when it can't plan yet). When your
-- bags, bank or skill change, tracked lists are planned again, so what one material still needs
-- follows what you hold of another (scraps for Light Leather, cloth for bolts), window open or not
local planners = {}
function T.Planner(prof, fn) planners[prof] = fn end
T._planners = planners -- for the test suite
local dirty = true
function T.Replan()
  dirty = false
  local s = S()
  for prof, fn in pairs(planners) do
    if s.items[prof] or s.all[prof] then
      local ok, list = pcall(fn)
      if ok and type(list) == "table" then T.Sync(prof, list) end
    end
  end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED",
  "BANKFRAME_CLOSED", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do pcall(ev.RegisterEvent, ev, e) end
-- seconds since the bags last changed: planning again waits until they've been quiet a moment,
-- so looting a pile of things (or buying a stack in clicks) plans once, not after every item
local QUIET = 3
local quiet = QUIET
T.QUIET = QUIET
ev:SetScript("OnEvent", function(_, e)
  dirty = true
  if e == "BAG_UPDATE_DELAYED" or e == "PLAYERBANKSLOTS_CHANGED" then quiet = 0 end
  if e == "PLAYER_ENTERING_WORLD" then Refresh() end
end)
-- counts change as you loot, buy and bank, and gathering goals count on their own: a light redraw
-- every second covers all of it (also while the list is hidden, so a new goal can bring it back).
-- Planning again waits for that tick, for the bags to settle and for the end of combat.
local acc = 0
ev:SetScript("OnUpdate", function(_, el)
  acc = acc + (el or 0)
  quiet = quiet + (el or 0)
  if acc >= 1 then
    acc = 0
    if dirty and quiet >= QUIET and next(planners) and not (InCombatLockdown and InCombatLockdown()) then T.Replan() end
    Refresh()
  end
end)
