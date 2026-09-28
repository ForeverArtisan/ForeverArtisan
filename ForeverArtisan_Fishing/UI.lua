-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Fishing: window (/fa fish) with Fishing / Progress / Catch log tabs, and the lure bar
local _, ns = ...
if not ns or not ns.DB then return end

local LOG_ROWS, GOAL_ROWS, ROW_H, GOAL_H, BAR_W = 12, 7, 24, 34, 250
local GOLD, GRAY, GREEN, YELLOW, RED = ForeverArtisan.GOLD, ForeverArtisan.GRAY, ForeverArtisan.GREEN, ForeverArtisan.YELLOW, ForeverArtisan.RED

---------------------------------------------------------------- shared style kit (ForeverArtisan Core)
local FA = ForeverArtisan
local K = FA.UI.Kit(ns, {})
local Icon, QColor, Clock = K.Icon, K.QColor, K.Clock
local Text, Header, Button, Check, Tip = K.Text, K.Header, K.Button, K.Check, K.Tip
local SavePos, LoadPos, Draggable = K.SavePos, K.LoadPos, K.Draggable
local function S() return ns.DB().settings end

-- Reapply bindings + CVars after a setting change (out of combat only)
local function ApplyFishing()
  if InCombatLockdown() then return end
  ns.UpdateMode(); ns.UpdateEnv()
end

---------------------------------------------------------------- key capture
-- A full-screen overlay grabs the next key or mouse button (Space, F, Shift+Middle Mouse...).
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local function Mods()
  return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
end
local LABEL = { key = "Fishing key", reelKey = "Reel-in key", swapKey = "Swap key" }
local cap
local function Capture(field)
  if InCombatLockdown() then ns.say("Can't change keys in combat."); return end
  if not cap then
    cap = CreateFrame("Button", "ForeverArtisanFishingKeyCapture", UIParent)
    cap:SetAllPoints(UIParent)
    cap:SetFrameStrata("FULLSCREEN_DIALOG")
    local bg = cap:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    cap.title = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    cap.title:SetPoint("CENTER", 0, 30)
    cap.sub = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cap.sub:SetPoint("TOP", cap.title, "BOTTOM", 0, -12)
    cap.sub:SetText("Press any key or mouse button (Shift / Ctrl / Alt combos work). Esc, left- or right-click cancels.")
    cap:EnableMouse(true)
    cap:RegisterForClicks("AnyUp")
    local function Done(key)
      cap:EnableKeyboard(false); cap:Hide()
      if key then ns.SetKey(cap.field, key) else ns.OnChange() end
    end
    cap:SetScript("OnKeyDown", function(_, key)
      if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
      if key == "ESCAPE" then Done(nil); return end
      Done(Mods() .. key)
    end)
    cap:SetScript("OnClick", function(_, button)
      if MOUSE[button] then Done(Mods() .. MOUSE[button]) else Done(nil) end
    end)
    cap:SetScript("OnMouseWheel", function(_, d) Done(Mods() .. (d > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")) end)
    cap:EnableMouseWheel(true)
    cap:Hide()
  end
  cap.field = field
  cap.title:SetText("Set " .. LABEL[field])
  cap:Show()
  cap:EnableKeyboard(true)
  if cap.SetPropagateKeyboardInput then pcall(cap.SetPropagateKeyboardInput, cap, false) end
end

local function KeyButton(parent, x, y, field, _, w)
  local kb = Button(parent, "", w or 150, function() Capture(field) end)
  kb:SetPoint("TOPLEFT", x, y)
  local clr = Button(parent, "Clear", 56, function() ns.SetKey(field, "") end)
  clr:SetPoint("LEFT", kb, "RIGHT", 6, 0)
  kb.field = field
  return kb
end
local function SyncKey(kb)
  local k = S()[kb.field]
  kb:SetText((k and k ~= "") and ns.KeyLabel(k) or (GRAY .. "none|r"))
end

---------------------------------------------------------------- item drop slot
local function ItemSlot(parent, x, y, label, onDrop, onRight, tipFn)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(36, 36); b:SetPoint("TOPLEFT", x, y)
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
  if label then
    local lab = Text(b, "GameFontDisableSmall", "TOP", 0, -2, b, "BOTTOM"); lab:SetJustifyH("CENTER"); lab:SetText(label)
  end
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local function Drop()
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return false end
    onDrop(b, id); ClearCursor()
    return true
  end
  b:SetScript("OnReceiveDrag", Drop)
  b:SetScript("OnClick", function(self, button)
    if Drop() then return end
    if button == "RightButton" and onRight then onRight(self) end
  end)
  Tip(b, function(self)
    if self.itemId then GameTooltip:SetHyperlink("item:" .. self.itemId) elseif label then GameTooltip:AddLine(label) end
    if tipFn then tipFn(self) end
  end)
  return b
end

---------------------------------------------------------------- rows (log, goals)
local view = { tab = "fish", mode = "spot", key = nil, offset = 0, gmode = "goals", goffset = 0, doffset = 0 }
local BuildDerbyPage, RefreshDerbyPage
local function MakeRows(parent, n, y, withAction, offsetKey, rowH)
  rowH = rowH or ROW_H
  local list = CreateFrame("Frame", nil, parent)
  list:SetPoint("TOPLEFT", 14, y); list:SetSize(436, n * rowH)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, d) view[offsetKey] = math.max(0, view[offsetKey] - d); ns.OnChange() end)
  local rows = {}
  for i = 1, n do
    local r = CreateFrame("Button", nil, list)
    r:SetSize(436, rowH); r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetHighlightTexture(FA.UI.HIGHLIGHT, "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 4, 0)
    r.left = Text(r, "GameFontHighlight", "LEFT", 30, 0, r, "LEFT"); r.left:SetWidth(210)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetJustifyH("RIGHT")
    if rowH > ROW_H then
      -- name on top, progress bar underneath
      r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", 30, -3)
      r.bar = CreateFrame("Frame", nil, r)
      r.bar:SetSize(BAR_W, 8); r.bar:SetPoint("TOPLEFT", 30, -21)
      local bbg = r.bar:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(); bbg:SetColorTexture(1, 1, 1, 0.1)
      r.fill = r.bar:CreateTexture(nil, "ARTWORK"); r.fill:SetPoint("TOPLEFT"); r.fill:SetPoint("BOTTOMLEFT")
    end
    if withAction then
      r.act = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
      r.act:SetSize(58, 20); r.act:SetPoint("RIGHT", -2, 0)
      r.right:SetPoint("RIGHT", r.act, "LEFT", -6, 0)
      if rowH > ROW_H then
        -- editable target: type a number, press Enter (or click away)
        local eb = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
        eb:SetSize(42, 18); eb:SetPoint("RIGHT", r.act, "LEFT", -6, 0)
        eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(4); eb:SetJustifyH("CENTER")
        local function Apply(self)
          local n = tonumber(self:GetText())
          if n and n > 0 and r.goalIndex then ns.SetGoalWant(r.goalIndex, n) end
        end
        eb:SetScript("OnEnterPressed", function(self) Apply(self); self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", Apply)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ns.OnChange() end)
        Tip(eb, function() GameTooltip:AddLine("Goal amount"); GameTooltip:AddLine("Type a number and press Enter.", 1, 1, 1) end)
        r.edit = eb
      end
    else
      r.right:SetPoint("RIGHT", -6, 0)
    end
    Tip(r, function(self)
      if self.itemId then GameTooltip:SetHyperlink("item:" .. self.itemId) end
      if self.tip then GameTooltip:AddLine(self.tip, 0.6, 0.8, 1, true) end
    end)
    rows[i] = r
  end
  return rows
end

---------------------------------------------------------------- window
local f, pages, tabs = nil, {}, {}

local function ShowTab(name)
  view.tab = name
  for k, p in pairs(pages) do p:SetShown(k == name) end
  for k, t in pairs(tabs) do t:SetEnabled(k ~= name) end
  ns.OnChange()
end

---------- page 1: Fishing
local function BuildFishingPage(p)
  Header(p, -4, "Status")
  p.lureIcon = p:CreateTexture(nil, "ARTWORK")
  p.lureIcon:SetSize(36, 36); p.lureIcon:SetPoint("TOPRIGHT", -18, -6)
  p.lureCount = Text(p, "NumberFontNormal", "BOTTOMRIGHT", -1, 1, p.lureIcon, "BOTTOMRIGHT")
  p.s1 = Text(p, nil, "TOPLEFT", 20, -24)
  p.s2 = Text(p, nil, "TOPLEFT", 20, -42)
  p.s3 = Text(p, nil, "TOPLEFT", 20, -60)

  Header(p, -86, "Settings")
  p.checks = {
    Check(p, "Put a lure on automatically", 16, -104, function() return S().autoLure end, function(v) S().autoLure = v end),
    Check(p, "Boost splash sound while fishing (music and ambience off)", 16, -128,
      function() return S().soundBoost end, function(v) S().soundBoost = v end, ApplyFishing),
    Check(p, "Same key reels in (mouse on the bobber, press again on the splash)", 16, -152,
      function() return S().reelSameKey end, function(v) S().reelSameKey = v end, ApplyFishing),
    Check(p, "Chat line for each catch", 16, -176, function() return S().verbose end, function(v) S().verbose = v end),
    Check(p, "Show lure bar on screen", 16, -200, function() return S().hud end, function(v) S().hud = v end),
  }

  Text(p, nil, "TOPLEFT", 22, -238):SetText("Fishing key:")
  p.keyBtn = KeyButton(p, 130, -234, "key", ApplyFishing)
  Text(p, nil, "TOPLEFT", 22, -266):SetText("Reel-in key:")
  p.reelBtn = KeyButton(p, 130, -262, "reelKey", ApplyFishing)
  p.reelHint = Text(p, "GameFontDisableSmall", "TOPLEFT", 22, -288); p.reelHint:SetWidth(430)

  Text(p, nil, "TOPLEFT", 22, -314):SetText("Lure to use:")
  local lb = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  lb:SetSize(212, 22); lb:SetPoint("TOPLEFT", 130, -310)
  lb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  lb:SetScript("OnClick", function(_, button)
    if button == "RightButton" then S().lure = nil; ns.OnChange(); return end
    local opts = { false }
    for _, l in ipairs(ns.BagLures()) do opts[#opts + 1] = ns.ItemName(l.id) end
    local cur, idx = S().lure, 1
    for i, name in ipairs(opts) do if name and cur and name:lower() == cur:lower() then idx = i end end
    S().lure = opts[(idx % #opts) + 1] or nil
    ns.OnChange()
  end)
  Tip(lb, function() GameTooltip:AddLine("Click: next lure in your bags"); GameTooltip:AddLine("Right-click: back to the best one", 1, 1, 1) end)
  p.lureBtn = lb

  Header(p, -348, "Weapon swap")
  local LBL = { pole = "Pole", mh = "Main hand", oh = "Off hand" }
  local function slot(kind, x)
    local b = ItemSlot(p, x, -368, LBL[kind],
      function(_, id)
        if ns.GearFits(id, kind) then ns.SetGear(kind, id)
        else ns.say(("That can't go in the %s slot."):format(LBL[kind]:lower())) end
      end,
      function() ns.SetGear(kind, nil) end,
      function(self)
        GameTooltip:AddLine(self.auto and "Remembered from what you last wore." or "Drag an item here from your bags.", 0.6, 0.8, 1)
        GameTooltip:AddLine("Right-click to clear.", 0.6, 0.6, 0.6)
      end)
    b.slot = kind
    return b
  end
  p.slots = { slot("pole", 22), slot("mh", 72), slot("oh", 122) }
  Text(p, nil, "TOPLEFT", 176, -372):SetText("Swap key:")
  p.swapKeyBtn = KeyButton(p, 244, -368, "swapKey", ns.UpdateSwapKey, 120)
  local gh = Text(p, "GameFontDisableSmall", "TOPLEFT", 176, -396); gh:SetWidth(270)
  gh:SetText("Toggles pole <-> weapons, even in combat. Empty slots use what you last wore. The fishing key also grabs your weapons once combat starts.")
end

local function RefreshFishingPage(p)
  local s = S()
  local left, pole = ns.LureLeft(), ns.PoleEquipped()
  local lureTxt = left > 0 and ((left > 60 and GREEN or YELLOW) .. Clock(left) .. "|r") or (RED .. "none|r")
  p.s1:SetText(("Pole: %s     Lure on pole: %s"):format(pole and (GREEN .. "equipped|r") or (GRAY .. "not equipped|r"), lureTxt))
  local i = ns.SkillInfo()
  p.s2:SetText(("Fishing skill: %s%s%s"):format(
    i.rank and (i.rank .. (i.max and (" / " .. i.max) or "")) or (GRAY .. "unknown (fills in at your next skill-up)|r"),
    (i.mod and i.mod > 0) and (GREEN .. " (+" .. i.mod .. " lure)|r") or "",
    i.capped and (RED .. "  capped, train!|r") or ""))
  local zone, sub = ns.Where()
  p.s3:SetText(("Spot: %s%s|r  %s(%s)|r"):format(GOLD, sub, GRAY, zone))
  local id = ns.PickLure()
  p.lureIcon:SetTexture(id and Icon(id) or 134400)
  p.lureIcon:SetDesaturated(not id)
  p.lureCount:SetText(id and ns.ItemCount(id) or "")

  for _, c in ipairs(p.checks) do c:Sync() end
  SyncKey(p.keyBtn); SyncKey(p.reelBtn); SyncKey(p.swapKeyBtn)
  p.reelHint:SetText(GRAY .. "Right now: |r" .. ns.KeyNow() .. GRAY .. ".|r")

  local lures = ns.BagLures()
  if s.lure then
    local have = 0
    for _, l in ipairs(lures) do if ns.ItemName(l.id):lower() == s.lure:lower() then have = l.count end end
    p.lureBtn:SetText(("%s (%d)"):format(s.lure, have))
  else
    local best = lures[1]
    p.lureBtn:SetText(best and ("Best: %s (+%d)"):format(ns.ItemName(best.id), best.bonus) or (GRAY .. "Best (none in bags)|r"))
  end

  local mh, oh, poleId = ns.GearSet()
  local g = s.gear or {}
  local eff = { pole = poleId, mh = mh, oh = oh }
  for _, sl in ipairs(p.slots) do
    local sid = eff[sl.slot]
    sl.itemId = sid
    sl.auto = sid and sl.slot ~= "pole" and not g[sl.slot]
    sl.icon:SetTexture(sid and Icon(sid) or nil)
    sl.icon:SetDesaturated(sl.auto and true or false)
    sl.icon:SetAlpha(sl.auto and 0.6 or 1)
  end
end

---------- page 2: Progress
local function BuildProgressPage(p)
  Header(p, -4, "Fishing skill")
  p.big = Text(p, "GameFontNormalLarge", "TOPLEFT", 20, -24)
  local bar = CreateFrame("Frame", nil, p)
  bar:SetSize(420, 10); bar:SetPoint("TOPLEFT", 20, -50)
  local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.1)
  p.fill = bar:CreateTexture(nil, "ARTWORK"); p.fill:SetPoint("TOPLEFT"); p.fill:SetPoint("BOTTOMLEFT")
  p.fill:SetColorTexture(0.83, 0.66, 0.31, 0.85)
  p.bar = bar
  p.l1 = Text(p, nil, "TOPLEFT", 20, -68)
  p.l2 = Text(p, nil, "TOPLEFT", 20, -86)
  p.l3 = Text(p, nil, "TOPLEFT", 20, -104)
  for _, fs in ipairs({ p.l1, p.l2, p.l3 }) do fs:SetWidth(430); fs:SetWordWrap(false) end
  p.l4 = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -126); p.l4:SetWidth(430)

  Header(p, -176, "Catch goals")
  p.newId = nil
  p.dropSlot = ItemSlot(p, 20, -196, nil,
    function(self, id) p.newId = id; self.itemId = id; self.icon:SetTexture(Icon(id)); self.plus:Hide() end,
    function(self) p.newId = nil; self.itemId = nil; self.icon:SetTexture(nil); self.plus:Show() end,
    function() GameTooltip:AddLine("Drag a fish (or any item) here from your bags, then click Add goal.", 0.6, 0.8, 1, true) end)
  -- make the empty slot obvious: gold border + a "+"
  local ds = p.dropSlot
  local edge = ds:CreateTexture(nil, "BORDER"); edge:SetPoint("TOPLEFT", -2, 2); edge:SetPoint("BOTTOMRIGHT", 2, -2)
  edge:SetColorTexture(0.83, 0.66, 0.31, 0.6)
  local inner = ds:CreateTexture(nil, "BORDER", nil, 1); inner:SetAllPoints(); inner:SetColorTexture(0.05, 0.05, 0.05, 1)
  ds.plus = ds:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge"); ds.plus:SetPoint("CENTER", 0, 1); ds.plus:SetText("+")
  local dl = Text(p, "GameFontDisableSmall", "TOP", 0, -4, ds, "BOTTOM"); dl:SetJustifyH("CENTER"); dl:SetText("drop item")
  Text(p, nil, "TOPLEFT", 66, -206):SetText("Amount")
  local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  eb:SetSize(44, 20); eb:SetPoint("TOPLEFT", 124, -202)
  eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(4); eb:SetText("20")
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.amount = eb
  local add = Button(p, "Add goal", 84, function()
    if not p.newId then ns.say("Drag a fish from your bags into the + box (left of Amount), or right-click a fish in the Catch log.") return end
    ns.AddGoal(p.newId, tonumber(eb:GetText()) or 20)
    p.newId = nil; p.dropSlot.itemId = nil; p.dropSlot.icon:SetTexture(nil); p.dropSlot.plus:Show()
  end)
  add:SetPoint("TOPLEFT", 176, -201)
  p.suggestBtn = Button(p, "Suggest from Cooking", 170, function()
    view.gmode = (view.gmode == "cook") and "goals" or "cook"; view.goffset = 0; ns.OnChange()
  end)
  p.suggestBtn:SetPoint("TOPLEFT", 268, -201)
  p.ghead = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -252); p.ghead:SetWidth(430)
  p.rows = MakeRows(p, GOAL_ROWS, -268, true, "goffset", GOAL_H)
  p.empty = Text(p, "GameFontDisable", "TOPLEFT", 30, -286); p.empty:SetWidth(400)
end

local function RefreshProgressPage(p)
  local i = ns.SkillInfo()
  if i.rank then
    p.big:SetText(("%d%s"):format(i.rank, i.max and (" / " .. i.max) or ""))
    local pct = (i.max and i.max > 0) and math.min(1, i.rank / i.max) or 0
    p.fill:SetWidth(math.max(1, 420 * pct))
    p.fill:SetColorTexture(i.capped and 1 or 0.83, i.capped and 0.25 or 0.66, i.capped and 0.25 or 0.31, 0.85)
  else
    p.big:SetText(GRAY .. "Skill unknown|r"); p.fill:SetWidth(1)
  end
  local ses = ns.session
  p.l1:SetText(("This session: %s+%d|r skill-ups from %d catches"):format(GREEN, i.gained or 0, ses.catches))
  p.l2:SetText(("%d catches since the last point%s"):format(i.sinceUp or 0,
    i.cpp and ("   ·   about %.1f catches per point"):format(i.cpp) or ""))
  if i.capped then
    p.l3:SetText(RED .. "Capped. Catches aren't giving skill until you train.|r")
  elseif i.catchesToCap then
    p.l3:SetText(("~%d catches to %d%s"):format(i.catchesToCap, i.max,
      i.minsToCap and (" (~" .. i.minsToCap .. " min at this pace)") or ""))
  else
    p.l3:SetText(GRAY .. "Skill up once to see your pace.|r")
  end
  p.l4:SetText(i.advice and (GOLD .. "Next rank (" .. (i.faction or "") .. "): |r" .. i.advice) or "")

  -- goals or cooking suggestions
  local data = {}
  if view.gmode == "cook" then
    p.suggestBtn:SetText("Back to goals")
    local list, rank, why = ns.CookingSuggestions()
    if why then
      p.ghead:SetText(why)
    else
      p.ghead:SetText(("Fish your learned Cooking recipes use (Cooking %d). Amount = enough for up to 25 skill-ups."):format(rank or 0))
    end
    for _, sgt in ipairs(list) do
      data[#data + 1] = { id = sgt.id, icon = Icon(sgt.id), left = sgt.name,
        right = ("%s, gray at %d"):format(sgt.recipe, sgt.grayAt), act = "+ Goal",
        tip = ("%d per %s. Add a goal for %d."):format(sgt.per, sgt.recipe, sgt.want),
        onAct = function() ns.AddGoal(sgt.id, sgt.want, sgt.name) end }
    end
    p.empty:SetText((#data == 0 and not why) and "None of your learned recipes need fish right now." or "")
  else
    p.suggestBtn:SetText("Suggest from Cooking")
    local rows = ns.GoalRows()
    p.ghead:SetText(#rows > 0 and "Counts fish caught since you logged in (resets each login). Click a number to change a goal." or "")
    for _, g in ipairs(rows) do
      local done = g.have >= g.want
      data[#data + 1] = { id = g.id, icon = Icon(g.id), pct = math.min(1, g.have / math.max(g.want, 1)), done = done,
        left = (done and GREEN or "") .. g.name .. (done and "|r" or ""),
        right = ("%s%d  /|r"):format(done and GREEN or YELLOW, g.have), want = g.want, goalIndex = g.i,
        tip = g.best and ("Best logged spot: " .. g.best) or "No logged spot yet.",
        act = "Remove", onAct = function() ns.RemoveGoal(g.i) end }
    end
    p.empty:SetText(#data == 0 and "No goals yet. Drag a fish into the + box above, use Suggest from Cooking, or right-click a fish in the catch log." or "")
  end
  view.goffset = math.min(view.goffset, math.max(0, #data - GOAL_ROWS))
  for n, r in ipairs(p.rows) do
    local d = data[n + view.goffset]
    if d then
      r.icon:SetTexture(d.icon); r.left:SetText(d.left); r.right:SetText(d.right)
      r.itemId, r.tip = d.id, d.tip
      r.act:SetText(d.act); r.act:SetScript("OnClick", d.onAct)
      r.goalIndex = d.goalIndex
      if r.edit then
        if d.want then
          r.edit:Show()
          r.right:ClearAllPoints(); r.right:SetPoint("RIGHT", r.edit, "LEFT", -8, 0)
          if not r.edit:HasFocus() then r.edit:SetText(tostring(d.want)) end
        else
          r.edit:Hide()
          r.right:ClearAllPoints(); r.right:SetPoint("RIGHT", r.act, "LEFT", -6, 0)
        end
      end
      if d.pct then
        r.bar:Show()
        r.fill:SetWidth(math.max(1, BAR_W * d.pct))
        if d.done then r.fill:SetColorTexture(0.25, 1, 0.25, 0.85) else r.fill:SetColorTexture(0.83, 0.66, 0.31, 0.85) end
      else
        r.bar:Hide()
      end
      r:Show()
    else
      r:Hide()
    end
  end
end

---------- page 3: Catch log
local function BuildLogPage(p)
  local tSpot = Button(p, "This spot", 90, function() view.mode, view.key, view.offset = "spot", nil, 0; ns.OnChange() end)
  tSpot:SetPoint("TOPLEFT", 16, -2)
  local tAll = Button(p, "All spots", 90, function() view.mode, view.offset = "all", 0; ns.OnChange() end)
  tAll:SetPoint("LEFT", tSpot, "RIGHT", 6, 0)
  p.tSpot, p.tAll = tSpot, tAll
  -- add everything on the current list as a goal (amount from the Progress tab)
  p.addAll = Button(p, "Add as goals", 120, function()
    local list = {}
    for _, e in ipairs(p.shown or {}) do
      if e.itemId then list[#list + 1] = { id = e.itemId, name = e.itemName } end
    end
    if #list == 0 then ns.say("Nothing on this list yet.") return end
    local amt = pages.progress and pages.progress.amount and tonumber(pages.progress.amount:GetText())
    ns.AddGoals(list, amt or 20)
  end)
  p.addAll:SetPoint("TOPRIGHT", -12, -2)
  Tip(p.addAll, function()
    GameTooltip:AddLine("Add as goals")
    GameTooltip:AddLine("Adds everything on this list, using the Amount on the Progress tab. Skips anything already a goal.", 1, 1, 1, true)
  end)
  p.header = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -32); p.header:SetWidth(430)
  p.rows = MakeRows(p, LOG_ROWS, -50, false, "offset")
  for _, r in ipairs(p.rows) do
    r:SetScript("OnClick", function(self, button)
      if button == "RightButton" and self.itemId then
        ns.AddGoal(self.itemId, 20, self.itemName)
      elseif self.spotKey then
        view.mode, view.key, view.offset = "spot", self.spotKey, 0; ns.OnChange()
      end
    end)
  end
  p.empty = Text(p, "GameFontDisable", "TOP", 0, -100, p, "TOP"); p.empty:SetJustifyH("CENTER")
  p.footer = Text(p, "GameFontHighlightSmall", "BOTTOMLEFT", 20, 40, p, "BOTTOMLEFT")
  local reset = Button(p, "Reset log", 110, function(self)
    if self.armed then
      ns.ResetLog(); self.armed = false; self:SetText("Reset log")
    else
      self.armed = true; self:SetText(RED .. "Click to confirm|r")
      C_Timer.After(3, function() self.armed = false; self:SetText("Reset log") end)
    end
  end)
  reset:SetPoint("BOTTOMRIGHT", -16, 12)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(310)
  help:SetText("Wheel: scroll  ·  Click a spot: open it  ·  Right-click a fish: goal")
end

local function SpotItems(z)
  local list = {}
  for id, it in pairs(z.items) do list[#list + 1] = { id = id, it = it } end
  table.sort(list, function(a, b) return a.it.hauls > b.it.hauls end)
  return list
end

local function RefreshLogPage(p)
  local db = ns.DB()
  local data = {}
  p.tSpot:SetEnabled(not (view.mode == "spot" and not view.key))
  p.tAll:SetEnabled(view.mode ~= "all")
  if view.mode == "all" then
    local spots, total = {}, 0
    for key, z in pairs(db.zones) do
      if z.catches > 0 or z.casts > 0 then spots[#spots + 1] = { key = key, z = z } end
    end
    table.sort(spots, function(a, b) return a.z.catches > b.z.catches end)
    for _, sp in ipairs(spots) do
      local z = sp.z
      total = total + z.catches
      local top = SpotItems(z)[1]
      local rate = z.casts > 0 and math.floor(z.catches * 100 / z.casts + 0.5) .. "% hooked" or ""
      data[#data + 1] = { icon = top and Icon(top.id), left = z.sub .. GRAY .. "  " .. z.zone .. "|r",
        right = ("%d catches   %s"):format(z.catches, rate), spotKey = sp.key }
    end
    p.header:SetText(("%d spots logged, %d catches total"):format(#spots, total))
    p.empty:SetText(#spots == 0 and "Nothing logged yet. Go catch something!" or "")
  else
    local z
    if view.key then z = db.zones[view.key] end
    if not z then z = ns.ZoneRec() end
    local c = math.max(z.catches, 1)
    for _, e in ipairs(SpotItems(z)) do
      local it = e.it
      data[#data + 1] = { icon = Icon(e.id), itemId = e.id, itemName = it.name,
        left = QColor(it.q) .. (it.name or ns.ItemName(e.id)) .. "|r",
        right = ("%d%%   %d caught%s"):format(math.floor(it.hauls * 100 / c + 0.5), it.n,
          it.minSkill and ("   skill " .. it.minSkill) or ""),
        tip = ("Seen %d times here%s. Right-click to make it a goal."):format(it.hauls, it.lastSeen and (", last " .. it.lastSeen) or "") }
    end
    local rate = z.casts > 0 and (", " .. math.floor(z.catches * 100 / z.casts + 0.5) .. "% hooked") or ""
    p.header:SetText(("%s%s|r %s(%s)|r   %d catches, %d casts, %d got away%s"):format(
      GOLD, z.sub, GRAY, z.zone, z.catches, z.casts, z.escaped, rate))
    p.empty:SetText(#data == 0 and "No catches at this spot yet." or "")
  end
  p.shown = data
  local spotView = view.mode ~= "all"
  p.addAll:SetShown(spotView)
  view.offset = math.min(view.offset, math.max(0, #data - LOG_ROWS))
  for i, r in ipairs(p.rows) do
    local d = data[i + view.offset]
    if d then
      r.icon:SetTexture(d.icon or 134400); r.left:SetText(d.left); r.right:SetText(d.right)
      r.itemId, r.itemName, r.spotKey, r.tip = d.itemId, d.itemName, d.spotKey, d.tip
      r:Show()
    else
      r:Hide()
    end
  end
  p.footer:SetText(("%d catches in the raw log%s"):format(#db.raw,
    #data > LOG_ROWS and ("   |   showing %d-%d of %d"):format(view.offset + 1, math.min(#data, view.offset + LOG_ROWS), #data) or ""))
end

---------- page 4: Derby
local DERBY_ROWS = 5
BuildDerbyPage = function(p)
  p.title = Text(p, "GameFontNormal", "TOPLEFT", 16, -4)
  p.big = Text(p, "GameFontNormalLarge", "TOPLEFT", 20, -24)
  p.when = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -50); p.when:SetWidth(430)
  Header(p, -74, "Rules")
  p.rules = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -92); p.rules:SetWidth(430); p.rules:SetJustifyV("TOP")
  p.rules:SetHeight(84)
  Header(p, -184, "This derby")
  p.dhead = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -202); p.dhead:SetWidth(430)
  p.rows = MakeRows(p, DERBY_ROWS, -218, false, "doffset")

  Header(p, -350, "Cast marker")
  p.mstat = Text(p, nil, "TOPLEFT", 20, -368); p.mstat:SetWidth(430)
  local set = Button(p, "Set marker", 96, function() ns.CalibrateMarker(false) end)
  set:SetPoint("TOPLEFT", 16, -388)
  Tip(set, function()
    GameTooltip:AddLine("Set marker (start over)")
    GameTooltip:AddLine("Cast first, then click this and click on your bobber. Also saves your camera view.", 1, 1, 1, true)
  end)
  local add = Button(p, "Add cast", 84, function() ns.CalibrateMarker(true) end)
  add:SetPoint("LEFT", set, "RIGHT", 6, 0)
  Tip(add, function()
    GameTooltip:AddLine("Add cast")
    GameTooltip:AddLine("Cast again without turning, then click this and click the new bobber. 4-5 casts gives a reliable average and scatter ring.", 1, 1, 1, true)
  end)
  local snap = Button(p, "Snap camera", 100, function() ns.SnapCamera() end)
  snap:SetPoint("LEFT", add, "RIGHT", 6, 0)
  Tip(snap, function()
    GameTooltip:AddLine("Snap camera")
    GameTooltip:AddLine("Puts the camera back where it was when you set the marker. Also bindable: Key Bindings > AddOns > Snap to fishing camera.", 1, 1, 1, true)
  end)
  p.show = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  p.show:SetSize(24, 24); p.show:SetPoint("LEFT", snap, "RIGHT", 10, 0)
  local sl = Text(p.show, "GameFontHighlight", "LEFT", 24, 0, p.show, "LEFT"); sl:SetText("Show")
  p.show:SetScript("OnClick", function(self) S().showMarker = self:GetChecked() and true or false; ns.UpdateMarker() end)
  local hint = Text(p, "GameFontDisableSmall", "TOPLEFT", 20, -418); hint:SetWidth(430)
  hint:SetText("Casts land roughly the same spot ahead of you, with some random scatter. Stand still, cast 4-5 times and " ..
    "Add cast each time; then turn so the ring covers the pool. Hold right mouse to turn so the camera stays behind you. " ..
    "Red = zoom changed: click Snap camera.")
end

RefreshDerbyPage = function(p)
  local st, sec = ns.DerbyStatus()
  local d = ns.derby
  p.title:SetText(d.title or "Fishing derby")
  if st == "live" then
    p.big:SetText(GREEN .. "LIVE now|r  ·  ends in " .. ns.DerbyClock(sec))
  else
    p.big:SetText((st == "soon" and YELLOW or "") .. "Starts in " .. ns.DerbyClock(sec) .. (st == "soon" and "|r" or ""))
  end
  p.when:SetText(ns.DerbyWhen() .. (d.source == "calendar" and GRAY .. "  ·  from the in-game calendar|r"
    or GRAY .. "  ·  Classic schedule (open your calendar once to use the real one)|r"))
  p.rules:SetText(d.rules or (GRAY .. "The rules show here once the calendar has the event. Also try talking to the derby NPC in Booty Bay.|r"))

  local list, catches = ns.DerbyCatches()
  if st == "live" or catches > 0 then
    p.dhead:SetText(("%d catches this derby"):format(catches))
  else
    p.dhead:SetText(GRAY .. "Catches during the derby are counted here.|r")
  end
  view.doffset = math.min(view.doffset or 0, math.max(0, #list - DERBY_ROWS))
  for i, r in ipairs(p.rows) do
    local e = list[i + (view.doffset or 0)]
    if e then
      r.icon:SetTexture(Icon(e.id)); r.left:SetText(e.name or ns.ItemName(e.id)); r.right:SetText(e.n .. " caught")
      r.itemId, r.tip = e.id, nil
      r:Show()
    else
      r:Hide()
    end
  end

  local m = S().marker
  if m and m.x then
    local z = GetCameraZoom and GetCameraZoom()
    local off = z and m.zoom and math.abs(z - m.zoom) > 0.75
    local n = m.samples and #m.samples or 1
    p.mstat:SetText(off and (RED .. "Marker set, but your camera zoom changed. Click Snap camera.|r")
      or (GREEN .. ("Marker set from %d cast%s.|r "):format(n, n == 1 and "" or "s") ..
        (n < 4 and "Add a few more casts for a reliable spot." or "Shows while your pole is equipped.")))
  else
    p.mstat:SetText(GRAY .. "Not set yet. Cast, click Set marker, then click on your bobber.|r")
  end
  p.show:SetChecked(S().showMarker and true or false)
end

---------- frame
local function Build()
  local order = { { "fish", "Fishing" }, { "progress", "Progress" }, { "log", "Catch log" }, { "derby", "Derby" } }
  f = K.Window({ name = "ForeverArtisanFishingFrame", title = "Fishing", tabs = order, pages = pages, tabButtons = tabs,
    onTab = ShowTab, defaultPos = { "CENTER", 0, 40 } })
  BuildFishingPage(pages.fish)
  BuildProgressPage(pages.progress)
  BuildLogPage(pages.log)
  BuildDerbyPage(pages.derby)

  f:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t > 0.5 then
      self.t = 0; self.n = (self.n or 0) + 1
      if view.tab == "derby" then RefreshDerbyPage(pages.derby) end
      if view.tab == "fish" then RefreshFishingPage(pages.fish)
      elseif view.tab == "progress" and self.n % 4 == 0 then RefreshProgressPage(pages.progress) end
    end
  end)
  f:Hide()
  ShowTab("fish")
end

---------------------------------------------------------------- lure bar + swap button
local hud
local lastPoleAt = -1000
local HUD_LINGER = 300

local function AttachSwap()
  local sw = ns.swapButton
  if not hud or not sw or sw.attached or InCombatLockdown() then return end
  sw:SetParent(hud)
  sw:ClearAllPoints()
  sw:SetSize(26, 26)
  sw:SetPoint("RIGHT", -3, 0)
  sw.icon = sw:CreateTexture(nil, "ARTWORK"); sw.icon:SetAllPoints()
  local hl = sw:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
  sw:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(ns.PoleEquipped() and "Equip weapons" or "Equip fishing pole")
    GameTooltip:AddLine("Works in combat.", 1, 1, 1)
    GameTooltip:Show()
  end)
  sw:HookScript("OnLeave", function() GameTooltip:Hide() end)
  sw:Show()
  sw.attached = true
end

local function BuildHUD()
  hud = CreateFrame("Button", "ForeverArtisanFishingHUD", UIParent)
  hud:SetSize(180, 30)
  Draggable(hud, "hudPos")
  LoadPos(hud, "hudPos", "CENTER", 0, -180)
  local bg = hud:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
  hud.icon = hud:CreateTexture(nil, "ARTWORK"); hud.icon:SetSize(24, 24); hud.icon:SetPoint("LEFT", 3, 0)
  hud.text = Text(hud, "GameFontHighlight", "LEFT", 32, 0, hud, "LEFT")
  hud.cap = Text(hud, "GameFontNormalSmall", "BOTTOMLEFT", 0, 2, hud, "TOPLEFT")
  hud:RegisterForClicks("LeftButtonUp")
  hud:SetScript("OnClick", function() ns.ToggleUI() end)
  Tip(hud, function()
    GameTooltip:AddLine("ForeverArtisan: Fishing")
    GameTooltip:AddLine("Click to open, drag to move. Right icon swaps pole/weapons.", 1, 1, 1)
  end)
  hud:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t < 0.5 then return end
    self.t = 0
    local pole = ns.PoleEquipped()
    if pole then lastPoleAt = GetTime() end
    local left = ns.LureLeft()
    local id = ns.PickLure()
    if not pole then
      self.text:SetText(GRAY .. "Weapons on|r")
      self.icon:SetDesaturated(true)
    elseif left > 0 then
      self.text:SetText((left > 60 and GREEN or YELLOW) .. "Lure " .. Clock(left) .. "|r")
      self.icon:SetDesaturated(false)
    else
      self.text:SetText(id and (YELLOW .. "Lure ready|r") or (RED .. "No lures|r"))
      self.icon:SetDesaturated(true)
    end
    self.icon:SetTexture(id and Icon(id) or 134400)
    local i = ns.SkillInfo()
    local dst, dsec = ns.DerbyStatus and ns.DerbyStatus()
    if dst == "live" then self.cap:SetText(GREEN .. "Derby live: " .. ns.DerbyClock(dsec) .. " left|r")
    elseif i.capped then self.cap:SetText(RED .. "Fishing capped at " .. i.max .. ". Train!|r")
    elseif i.rank and i.max then self.cap:SetText(GRAY .. "Fishing " .. i.rank .. " / " .. i.max .. "|r")
    else self.cap:SetText("") end
    local sw = ns.swapButton
    if sw and sw.icon then
      local mh, _, poleId = ns.GearSet()
      local nextId = pole and mh or poleId
      sw.icon:SetTexture(nextId and Icon(nextId) or 134400)
      sw.icon:SetDesaturated(not nextId)
    end
    if not InCombatLockdown() and not pole and GetTime() - lastPoleAt > HUD_LINGER then ns.OnChange() end
  end)
  AttachSwap()
end

local function UpdateHUD()
  if not hud or InCombatLockdown() then return end
  AttachSwap()
  local pole = ns.PoleEquipped()
  if pole then lastPoleAt = GetTime() end
  if S().hud and (pole or GetTime() - lastPoleAt < HUD_LINGER) then hud:Show() else hud:Hide() end
end

---------------------------------------------------------------- minimap button
-- The minimap button now belongs to ForeverArtisan Core (one button for every module).
function ns.MinimapCommand(arg)
  if ForeverArtisan and ForeverArtisan.minimap then ForeverArtisan.minimap(arg) end
end
ns.ToggleMinimapButton = function() ns.MinimapCommand("") end

---------------------------------------------------------------- hooks
function ns.OnChange()
  UpdateHUD()
  if not (f and f:IsShown()) then return end
  if view.tab == "fish" then RefreshFishingPage(pages.fish)
  elseif view.tab == "progress" then RefreshProgressPage(pages.progress)
  elseif view.tab == "derby" then RefreshDerbyPage(pages.derby)
  else RefreshLogPage(pages.log) end
end
ns.RefreshStatus = function() if f and f:IsShown() and view.tab == "fish" then RefreshFishingPage(pages.fish) end end

function ns.ToggleUI()
  if not f then Build() end
  if f:IsShown() then f:Hide() else f:Show(); ns.OnChange() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ZONE_CHANGED",
  "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED", "CHAT_MSG_SKILL", "BAG_UPDATE", "LOOT_CLOSED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then BuildHUD() end
  if e == "ZONE_CHANGED" or e == "ZONE_CHANGED_INDOORS" or e == "ZONE_CHANGED_NEW_AREA" then
    if view.mode == "spot" then view.key = nil end
  end
  ns.OnChange()
end)
