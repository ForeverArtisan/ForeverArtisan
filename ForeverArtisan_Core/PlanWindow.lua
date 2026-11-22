-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: the plan, popped out (0.9.52).
--   Kerry, Nov 22 (First Aid Progress tab): "Can we get the plan to popout into a transparent
--   window (like the shopping list). Functionality should be exactly the same".
--   A crafting Progress tab's "Plan to skill" rows in a small see-through window, like the goals
--   list: same rows, colors and hover text, and it follows your skill with the window closed.
--   Move it, fold it, lock it (/fa plan lock); right-click a heading to put that plan back.
--   FA.PlanPop.Button(p, prof)            the "Pop out" button by "Plan to skill"
--   FA.PlanPop.Register(prof, fn, openFn) fn() refreshes that module's Progress tab (it calls Set);
--                                         openFn() opens the module window on its Progress tab
--   FA.PlanPop.Set(prof, d)               d = { rows, target, rank, max, note } or { empty = text }
--   FA.PlanPop.Toggle(prof), IsOn(prof), Refresh(), Slash(rest)
local FA = ForeverArtisan
local P = {}
FA.PlanPop = P
local GOLD, GRAY = "|cffd4a94e", "|cff9d9d9d"
local say = FA.Printer and FA.Printer() or print
P.MAX_ROWS = 12 -- rows per plan before the mouse wheel scrolls it, like the tab

---------------------------------------------------------------- saved state (per character)
local function S()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.planPop = s.planPop or {}
  local key = FA.CharKey(s.planPop)
  local t = s.planPop[key]
  if not t then t = {}; s.planPop[key] = t end
  t.on = t.on or {} -- [prof] = true while that plan is popped out
  return t
end

local data, sources, opens, offs, buttons = {}, {}, {}, {}, {}
P._data, P._buttons = data, buttons -- for the test suite

function P.IsOn(prof) return S().on[prof] and true or false end

function P.Register(prof, fn, openFn) sources[prof], opens[prof] = fn, openFn end

local dirty = true
local Draw
function P.Set(prof, d)
  data[prof] = d
  if S().on[prof] then Draw() end
end

local function Fresh(prof)
  if sources[prof] and not (InCombatLockdown and InCombatLockdown()) then pcall(sources[prof]) end
end

local function Label(prof)
  local b = buttons[prof]
  if b then b:SetText(P.IsOn(prof) and "Pop in" or "Pop out") end
end

function P.Toggle(prof, on)
  local s = S()
  if on == nil then on = not s.on[prof] end
  if on then
    s.on[prof] = true; s.hidden = nil
    if not data[prof] then Fresh(prof) end
  else
    s.on[prof] = nil; offs[prof] = nil
  end
  Label(prof)
  Draw()
end

function P.Button(p, prof)
  local b = FA.UI.Button(p, "Pop out", 70, function() P.Toggle(prof) end)
  b:SetHeight(20); b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -24, -50)
  FA.UI.Tip(b, function()
    GameTooltip:AddLine("Pop the plan out")
    GameTooltip:AddLine("Shows this plan in a small see-through window on screen, like the goals list. It keeps up as you skill, window open or not. Drag it to move it; /fa plan lock keeps it in place.", 1, 1, 1, true)
  end)
  buttons[prof] = b
  Label(prof)
  return b
end

---------------------------------------------------------------- the frame
local f, pool, ROW_H, W = nil, {}, 18, 340

local function Build()
  f = CreateFrame("Frame", "ForeverArtisanPlanFrame", UIParent)
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
  f.title:SetText(GOLD .. "Plan to skill|r")
  f.fold = CreateFrame("Button", nil, f); f.fold:SetSize(16, 16); f.fold:SetPoint("TOPRIGHT", -22, -2)
  f.fold.t = FA.UI.Text(f.fold, "GameFontHighlight", "CENTER", 0, 0); f.fold.t:SetText("-")
  f.fold:SetScript("OnClick", function() local s = S(); s.folded = not s.folded or nil; Draw() end)
  f.close = CreateFrame("Button", nil, f); f.close:SetSize(16, 16); f.close:SetPoint("TOPRIGHT", -4, -2)
  f.close.t = FA.UI.Text(f.close, "GameFontHighlight", "CENTER", 0, 0); f.close.t:SetText("x")
  f.close:SetScript("OnClick", function()
    local s = S()
    for prof in pairs(s.on) do s.on[prof] = nil; offs[prof] = nil; Label(prof) end
    Draw()
    say("Plan put back in its window. Pop out on a Progress tab shows it again.")
  end)
  FA.UI.Tip(f.fold, function() GameTooltip:AddLine("Fold or unfold the plan") end)
  FA.UI.Tip(f.close, function()
    GameTooltip:AddLine("Close the pop-out")
    GameTooltip:AddLine("The plan stays on the Progress tab. Pop out there shows it here again.", 1, 1, 1, true)
  end)
  f:EnableMouseWheel(true)
  local pos = S().pos
  if pos then f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
  else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -340, -330) end
end

local function Row(i)
  local r = pool[i]
  if r then return r end
  r = CreateFrame("Button", nil, f)
  r:SetSize(W - 12, ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 0, 0)
  r.left = FA.UI.Text(r, "GameFontHighlightSmall", "LEFT", 20, 0, r, "LEFT"); r.left:SetWordWrap(false); r.left:SetText("")
  r.right = FA.UI.Text(r, "GameFontHighlightSmall", "RIGHT", -2, 0, r, "RIGHT"); r.right:SetJustifyH("RIGHT"); r.right:SetText("")
  -- a heading: left-click opens the profession on its Progress tab, right-click puts the plan back
  r:SetScript("OnClick", function(self, button)
    if not self.head then return end
    if button == "RightButton" then P.Toggle(self.head, false) return end
    if opens[self.head] then pcall(opens[self.head]) end
  end)
  -- the same hover text as the row on the Progress tab
  r:SetScript("OnEnter", function(self)
    if self.head then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(self.head .. " plan")
      GameTooltip:AddLine("Click to open " .. self.head .. " on its Progress tab", 0.5, 0.75, 1)
      GameTooltip:AddLine("Right-click to put the plan back in the window", 0.5, 0.75, 1)
      GameTooltip:Show()
      return
    end
    local d = self.d
    if not (d and (d.id or d.tip or d.tipFn)) then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if d.id then GameTooltip:SetItemByID(d.id) else GameTooltip:AddLine(d.tipTitle or "") end
    local tip = d.tip or (d.tipFn and d.tipFn())
    if tip then GameTooltip:AddLine(tip, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- the mouse wheel over a plan scrolls it, like the tab
  r:EnableMouseWheel(true)
  r:SetScript("OnMouseWheel", function(self, delta)
    local prof = self.prof
    local d = prof and data[prof]
    local n = d and d.rows and #d.rows or 0
    if n <= P.MAX_ROWS then return end
    offs[prof] = math.max(0, math.min((offs[prof] or 0) - (delta or 0), n - P.MAX_ROWS))
    Draw()
  end)
  pool[i] = r
  return r
end

-- the popped-out plans, in order: { { prof, title, note, rows = { d, ... }, more } }
function P.Groups()
  local s, out, profs = S(), {}, {}
  for prof in pairs(s.on) do profs[#profs + 1] = prof end
  table.sort(profs)
  for _, prof in ipairs(profs) do
    local d = data[prof] or {}
    local title = prof
    if d.rank and d.target then title = title .. GRAY .. ("  ·  %d to %d"):format(d.rank, d.target) .. "|r"
    elseif d.target then title = title .. GRAY .. "  ·  to " .. d.target .. "|r" end
    local all = d.rows or {}
    local off = math.max(0, math.min(offs[prof] or 0, #all - P.MAX_ROWS))
    offs[prof] = off
    local rows = {}
    for k = off + 1, math.min(#all, off + P.MAX_ROWS) do rows[#rows + 1] = all[k] end
    local note = d.empty
    if not note and d.note and d.note ~= "" then note = d.note end
    if not d.rows and not d.empty then note = GRAY .. "Open " .. prof .. " once (/fa) and its plan shows here.|r" end
    out[#out + 1] = { prof = prof, title = title, note = note, rows = rows, more = #all - #rows, off = off }
  end
  return out
end

function Draw()
  local s = S()
  local groups = P.Groups()
  if s.hidden or #groups == 0 then
    if f then f:Hide() end
    return
  end
  if not f then Build() end
  f:Show()
  f:EnableMouse(not s.locked)
  f.fold.t:SetText(s.folded and "+" or "-")
  local y, i = -22, 0
  if not f.notes then f.notes = {} end
  local nNote = 0
  if not s.folded then
    for _, g in ipairs(groups) do
      i = i + 1
      local h = Row(i)
      h.head, h.prof, h.d = g.prof, g.prof, nil
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", 6, y)
      h.icon:SetTexture(nil); h.left:SetWidth(W - 20)
      h.left:SetFontObject("GameFontNormalSmall")
      h.left:SetText(GOLD .. g.title .. "|r"); h.right:SetText("")
      h:EnableMouse(not s.locked); h:Show()
      y = y - ROW_H
      if g.note then
        nNote = nNote + 1
        local t = f.notes[nNote]
        if not t then t = FA.UI.Text(f, "GameFontHighlightSmall", "TOPLEFT", 0, 0); t:SetWidth(W - 24); f.notes[nNote] = t end
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", 14, y)
        t:SetText(g.note); t:Show()
        local th = (t.GetStringHeight and t:GetStringHeight()) or 0
        y = y - math.max(ROW_H - 4, (tonumber(th) or 0)) - 2
      end
      for _, d in ipairs(g.rows) do
        i = i + 1
        local r = Row(i)
        r.head, r.prof, r.d = nil, g.prof, d
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 14, y)
        if d.noIcon then r.icon:SetTexture(nil) else r.icon:SetTexture(d.icon or 134400) end
        r.left:SetFontObject("GameFontHighlightSmall")
        r.left:SetText(d.left or ""); r.right:SetText(d.right or "")
        -- the right side gets what it needs, the name the rest (cut off with "...": hover for all)
        r.right:SetWidth(0)
        local rw = tonumber((r.right.GetStringWidth and r.right:GetStringWidth()) or 0) or 0
        r.left:SetWidth(math.max(80, W - 12 - 20 - rw - 8))
        r:EnableMouse(not s.locked); r:Show()
        y = y - ROW_H
      end
      if g.more > 0 then
        nNote = nNote + 1
        local t = f.notes[nNote]
        if not t then t = FA.UI.Text(f, "GameFontHighlightSmall", "TOPLEFT", 0, 0); t:SetWidth(W - 24); f.notes[nNote] = t end
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", 34, y)
        t:SetText(GRAY .. ("%d more steps: scroll the plan|r"):format(g.more)); t:Show()
        y = y - ROW_H + 2
      end
      y = y - 4
    end
  end
  for k = i + 1, #pool do pool[k]:Hide(); pool[k].d, pool[k].head = nil, nil end
  for k = nNote + 1, #f.notes do f.notes[k]:Hide() end
  f:SetHeight(-y + 4)
end
P.Refresh = Draw

---------------------------------------------------------------- /fa plan
function P.Slash(rest)
  local r = (rest or ""):lower()
  local s = S()
  if r == "lock" then s.locked = true; say("Plan window locked in place. /fa plan unlock to move it.")
  elseif r == "unlock" then s.locked = nil; say("Plan window unlocked: drag it to move it.")
  elseif r == "reset" then
    s.pos = nil
    if f then f:ClearAllPoints(); f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -340, -330) end
    say("Plan window moved back to its first spot.")
  elseif r == "hide" then s.hidden = true; say("Plan window hidden. /fa plan brings it back.")
  else
    s.hidden = not s.hidden or nil
    if not s.hidden and not next(s.on) then
      say("Nothing popped out yet. Click Pop out by \"Plan to skill\" on a crafting Progress tab.")
    end
    print(GRAY .. "  /fa plan  show or hide  ·  lock | unlock | reset|r")
  end
  Draw()
end

---------------------------------------------------------------- fresh plans with the window closed
-- skill-ups, new recipes, bags and prices change the plan: plan again on the next quiet second
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "BAG_UPDATE_DELAYED",
  "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function() dirty = true end)
if FA.PriceWatchers then table.insert(FA.PriceWatchers, function() dirty = true end) end
function P.Replan()
  dirty = false
  for prof in pairs(S().on) do Fresh(prof) end
  Draw()
end
local acc = 0
ev:SetScript("OnUpdate", function(_, el)
  acc = acc + (el or 0)
  if acc < 1 then return end
  acc = 0
  if dirty and ForeverArtisanSettings and not (InCombatLockdown and InCombatLockdown()) then
    local ok, s = pcall(S)
    if ok and next(s.on) then P.Replan() else dirty = false end
  end
end)
