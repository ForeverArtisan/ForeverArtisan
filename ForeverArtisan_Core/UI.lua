-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan Core: the shared style kit. Every window in the suite is built from these
-- pieces so the modules look and behave the same. New profession modules should use this
-- instead of drawing their own frames, rows or buttons.
--
--   local FA = ForeverArtisan
--   local say = FA.Printer("Herbalism")          -- "ForeverArtisan Herbalism: ..." in gold
--   local K = FA.UI.Kit(ns, view)                -- widgets bound to this module
--   f = K.Window({ name = ..., title = "Herbalism", tabs = order, pages = pages, tabButtons = tabs, onTab = ShowTab })
ForeverArtisan = ForeverArtisan or {}
local FA = ForeverArtisan

---------------------------------------------------------------- colors + chat
FA.GOLD   = "|cffd4a94e"   -- the brand color: prefixes, titles, highlights
FA.GRAY   = "|cff9d9d9d"
FA.GREEN  = "|cff40ff40"
FA.YELLOW = "|cffffff00"
FA.RED    = "|cffff4040"
FA.ORANGE = "|cffff9020"
FA.BAR    = { 0.83, 0.66, 0.31, 0.85 }  -- brand gold for bars
FA.BAR_DONE = { 0.25, 1, 0.25, 0.85 }
FA.BAR_CAPPED = { 1, 0.25, 0.25, 0.85 }
FA.WEBSITE = "foreverartisan.app"

-- ONE version for the whole suite. It lives in every TOC (## Version) and is set for all of
-- them at once by tools/release.py. Core's copy is the reference; modules must match it.
function FA.Version(addon)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get, addon or "ForeverArtisan_Core", "Version")
  return (ok and v) or "?"
end

-- Beta build? Only versions named that way: "1.2.0-beta.1" or "-alpha". Plain numbered
-- releases (0.9.4, 1.0.0) are tested builds and show no tag. Decided Sep 30, 2026.
function FA.IsBeta()
  local v = FA.Version():lower()
  return v:find("beta", 1, true) ~= nil or v:find("alpha", 1, true) ~= nil
end

-- Dev build? The working copy between releases is "x.y.z-dev". It never ships:
-- tools/release.py replaces it with the real version before tagging.
function FA.IsDev()
  return FA.Version():lower():find("-dev", 1, true) ~= nil
end

-- "v0.9.4", "v1.1.0-beta.1  BETA" or "v0.9.4-dev  DEV"
function FA.VersionTag()
  local tag = ""
  if FA.IsBeta() then tag = "  " .. FA.ORANGE .. "BETA|r"
  elseif FA.IsDev() then tag = "  |cff888888DEV|r" end
  return "v" .. FA.Version() .. tag
end

function FA.Prefix(title)
  return FA.GOLD .. "ForeverArtisan" .. (title and (" " .. title) or "") .. ":|r "
end

-- say = FA.Printer("Fishing"); say("Goal done.")
function FA.Printer(title, quietFn)
  local prefix = FA.Prefix(title)
  return function(msg)
    if quietFn and quietFn() then return end
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(msg))
  end
end

-- One-time move of saved data from an old SavedVariables name to the new one.
-- The TOC lists both names for the release that does the move; the old one is cleared
-- so it disappears from the file on the next save.
function FA.Migrate(newName, oldName)
  local old = _G[oldName]
  if old ~= nil then
    if _G[newName] == nil then _G[newName] = old end
    _G[oldName] = nil
  end
  return _G[newName]
end

---------------------------------------------------------------- basic widgets
local UI = {}
FA.UI = UI
UI.W, UI.H, UI.ROW_H, UI.BAR_W = 470, 578, 24, 250
UI.HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

local GetIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
function UI.Icon(id) return (id and GetIcon and GetIcon(id)) or 134400 end

function UI.QColor(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return (c and c.hex) or "|cffffffff"
end

function UI.Clock(sec)
  sec = math.floor(sec or 0)
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

function UI.Text(parent, font, point, x, y, rel, relPoint)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetPoint(point or "TOPLEFT", rel or parent, relPoint or point or "TOPLEFT", x or 0, y or 0)
  fs:SetJustifyH("LEFT")
  return fs
end

-- section heading, same spot and font in every module
function UI.Header(parent, y, label, x)
  local fs = UI.Text(parent, "GameFontNormal", "TOPLEFT", x or 16, y)
  fs:SetText(FA.GOLD .. label .. "|r")
  return fs
end

-- "Open Alchemy window": casts the profession spell when clicked, which opens its window so the
-- module can read the recipes. Secure buttons can't be shown or hidden in combat, so ShowIf waits.
function UI.ProfessionButton(parent, spellName, w)
  local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
  b:SetSize(w or 220, 26)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "spell")
  b:SetAttribute("spell", spellName)
  b:SetText("Open " .. spellName .. " window")
  function b:ShowIf(on)
    if InCombatLockdown() then return end
    if on then self:Show() else self:Hide() end
  end
  b:Hide()
  return b
end

function UI.Button(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 100, 22); b:SetText(label or "")
  b:SetScript("OnClick", onClick)
  return b
end

function UI.Tip(frame, fn)
  frame:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); fn(self); GameTooltip:Show() end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- a click-twice-to-confirm button (Reset log, Clear goals...)
function UI.ConfirmButton(parent, label, w, onConfirm)
  local b
  b = UI.Button(parent, label, w, function(self)
    if self.armed then
      self.armed = false; self:SetText(label); onConfirm()
    else
      self.armed = true; self:SetText(FA.RED .. "Click to confirm|r")
      if C_Timer then C_Timer.After(3, function() self.armed = false; self:SetText(label) end) end
    end
  end)
  return b
end

-- small number box (goal amounts)
function UI.NumberBox(parent, w, default)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(w or 46, 20)
  eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(4); eb:SetJustifyH("CENTER")
  eb:SetText(tostring(default or 20))
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return eb
end

-- progress bar: bar:Set(fraction, "done" | "capped" | nil)
function UI.Bar(parent, w, h)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(w, h or 8)
  local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.1)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
  function bar:Set(pct, state)
    pct = math.max(0, math.min(1, pct or 0))
    self.fill:SetWidth(math.max(1, self:GetWidth() * pct))
    local c = (state == "done" and FA.BAR_DONE) or (state == "capped" and FA.BAR_CAPPED) or FA.BAR
    self.fill:SetColorTexture(c[1], c[2], c[3], c[4])
  end
  bar:Set(0)
  return bar
end

-- Big "Skill 142 / 150" line with a bar under it. Same on every Progress tab.
function UI.SkillBar(parent, y, name)
  local box = CreateFrame("Frame", nil, parent)
  box:SetPoint("TOPLEFT", 16, y); box:SetSize(UI.W - 32, 30)
  box.big = UI.Text(box, "GameFontNormalLarge", "TOPLEFT", 2, 0)
  box.bar = UI.Bar(box, UI.W - 50, 8); box.bar:SetPoint("TOPLEFT", 2, -20)
  function box:Set(rank, max, capped)
    if rank then
      self.big:SetText(("%s %d%s"):format(name or "Skill", rank, max and (" / " .. max) or ""))
      self.bar:Set((max and max > 0) and rank / max or 0, capped and "capped" or nil)
    else
      self.big:SetText(FA.GRAY .. "Can't read your " .. (name or "skill") .. " yet.|r")
      self.bar:Set(0)
    end
  end
  return box
end

---------------------------------------------------------------- window

-- Base window: same frame, size, title, brand line, drag and Esc behavior everywhere.
-- opts: name, title, width, height, getPos(), setPos(pos), defaultPos {point, x, y}
function UI.Frame(opts)
  local name = opts.name
  local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", name, UIParent)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.85)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)
  end
  f:SetSize(opts.width or UI.W, opts.height or UI.H)
  f:SetFrameStrata(opts.strata or "HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if opts.setPos then
      local p, _, rp, x, y = self:GetPoint()
      opts.setPos({ p, rp, x, y })
    end
  end)
  local pos = opts.getPos and opts.getPos()
  local d = opts.defaultPos or { "CENTER", 40, 40 }
  f:ClearAllPoints()
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint(d[1], UIParent, d[1], d[2], d[3]) end
  if name then tinsert(UISpecialFrames, name) end

  -- title bar: "ForeverArtisan: Herbalism" in the middle, version (+ BETA) in the left corner
  f.title = UI.Text(f, "GameFontNormal", "TOP", 0, -6, f, "TOP")
  f.title:SetJustifyH("CENTER")
  f.title:SetText(FA.GOLD .. "ForeverArtisan|r" .. (opts.title and (": " .. opts.title) or ""))
  if type(f.TitleText) == "table" and f.TitleText.SetText then f.TitleText:SetText("") end
  f.brand = UI.Text(f, "GameFontDisableSmall", "TOPLEFT", 12, -9, f, "TOPLEFT")
  f.brand:SetText(FA.VersionTag()) -- short on purpose: the title is centered and must never be covered
  return f
end

-- Tab row under the title. order = { { "main", "Herbalism" }, { "progress", "Progress" }, ... }
-- Fills pages[key] (content frames) and buttons[key]; clicking calls onTab(key).
function UI.Tabs(f, order, pages, buttons, onTab)
  local n = #order
  local gap = 6
  local w = math.min(104, math.floor((f:GetWidth() - 28 - gap * (n - 1)) / math.max(n, 1)))
  for i, t in ipairs(order) do
    local b = UI.Button(f, t[2], w, function() onTab(t[1]) end)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * (w + gap), -28)
    buttons[t[1]] = b
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", 0, -58); page:SetPoint("BOTTOMRIGHT", 0, 0)
    pages[t[1]] = page
  end
end

-- Standard tab switch: show one page, disable its button.
function UI.SelectTab(pages, buttons, name)
  for k, pg in pairs(pages) do pg:SetShown(k == name) end
  for k, b in pairs(buttons) do b:SetEnabled(k ~= name) end
end

---------------------------------------------------------------- module kit
-- Widgets that need to know the module (its settings, its view state, its OnChange).
-- ns must provide ns.DB().settings and ns.OnChange; view is the module's UI state table.
function UI.Kit(ns, view)
  local K = {}
  local function S() return ns.DB().settings end
  local function Changed() if ns.OnChange then ns.OnChange() end end

  K.Text, K.Header, K.Button, K.Tip, K.Icon = UI.Text, UI.Header, UI.Button, UI.Tip, UI.Icon
  K.QColor, K.Clock, K.Bar, K.NumberBox, K.ConfirmButton, K.SkillBar = UI.QColor, UI.Clock, UI.Bar, UI.NumberBox, UI.ConfirmButton, UI.SkillBar

  function K.Check(parent, label, x, y, get, set, after)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24); c:SetPoint("TOPLEFT", x, y)
    local fs = UI.Text(c, "GameFontHighlight", "LEFT", 24, 0, c, "LEFT"); fs:SetText(label)
    c:SetScript("OnClick", function(self)
      set(self:GetChecked() and true or false)
      if after then after() end
      Changed()
    end)
    c.Sync = function(self) self:SetChecked(get()) end
    return c
  end

  function K.SavePos(frame, key)
    local p, _, rp, x, y = frame:GetPoint()
    S()[key or "pos"] = { p, rp, x, y }
  end
  function K.LoadPos(frame, key, dp, dx, dy)
    local pos = S()[key or "pos"]
    frame:ClearAllPoints()
    if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else frame:SetPoint(dp or "CENTER", UIParent, dp or "CENTER", dx or 0, dy or 0) end
  end
  function K.Draggable(frame, key)
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); K.SavePos(self, key) end)
  end

  -- The module's main window with its tab row. Returns the frame.
  -- opts: name, title, tabs (order), pages, tabButtons, onTab, posKey, defaultPos
  function K.Window(opts)
    local key = opts.posKey or "pos"
    local f = UI.Frame({
      name = opts.name, title = opts.title, width = opts.width, height = opts.height,
      defaultPos = opts.defaultPos,
      getPos = function() return S()[key] end,
      setPos = function(pos) S()[key] = pos end,
    })
    UI.Tabs(f, opts.tabs, opts.pages, opts.tabButtons, opts.onTab)
    return f
  end

  -- Rows: icon + left text + right text, optional action button.
  -- opts.goals = true adds a progress bar under the name and an editable amount box
  -- (typing a number calls ns.SetGoalWant(goalIndex, n)).
  function K.MakeRows(p, n, top, withAct, opts)
    opts = opts or {}
    local goals = opts.goals
    local rowH = goals and 34 or UI.ROW_H
    local rows = {}
    for i = 1, n do
      local r = CreateFrame("Button", nil, p)
      r:SetSize(UI.W - 40, rowH - 2)
      r:SetPoint("TOPLEFT", 16, top - (i - 1) * rowH)
      r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      r:SetHighlightTexture(UI.HIGHLIGHT, "ADD")
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 2, 0)
      r.left = UI.Text(r, "GameFontHighlight", "LEFT", 28, 0, r, "LEFT"); r.left:SetWidth(230); r.left:SetWordWrap(false)
      if goals then
        r.left:ClearAllPoints(); r.left:SetPoint("TOPLEFT", 28, -3)
        r.bar = UI.Bar(r, UI.BAR_W, 8); r.bar:SetPoint("TOPLEFT", 28, -21)
      end
      if withAct then
        r.act = UI.Button(r, "", 64, nil); r.act:SetHeight(20); r.act:SetPoint("RIGHT", -2, 0)
        r.right = UI.Text(r, "GameFontHighlightSmall", "RIGHT", -8, 0, r.act, "LEFT")
      else
        r.act = false
        r.right = UI.Text(r, "GameFontHighlightSmall", "RIGHT", -6, 0, r, "RIGHT")
      end
      r.right:SetJustifyH("RIGHT")
      if goals then
        local eb = UI.NumberBox(r, 42)
        eb:SetHeight(18)
        eb:SetPoint("RIGHT", r.act or r, r.act and "LEFT" or "RIGHT", -6, 0)
        local function Apply(self)
          local v = tonumber(self:GetText())
          if v and v > 0 and r.goalIndex and ns.SetGoalWant then ns.SetGoalWant(r.goalIndex, v) end
        end
        eb:SetScript("OnEnterPressed", function(self) Apply(self); self:ClearFocus() end)
        eb:SetScript("OnEditFocusLost", Apply)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Changed() end)
        UI.Tip(eb, function() GameTooltip:AddLine("Goal amount"); GameTooltip:AddLine("Type a number and press Enter.", 1, 1, 1) end)
        r.edit = eb
      end
      r:SetScript("OnEnter", function(self)
        if not (self.itemId or self.tip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemId then GameTooltip:SetItemByID(self.itemId) else GameTooltip:AddLine(self.tipTitle or "") end
        if self.tip then GameTooltip:AddLine(self.tip, 1, 1, 1, true) end
        GameTooltip:Show()
      end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r:Hide()
      rows[i] = r
    end
    return rows
  end

  -- Share a row between the name (left) and the detail text (right) so they never overlap:
  -- the right side gets what it needs up to 60% of the row, the name gets the rest, and
  -- whichever is too long is cut off with "..." (hover the row for the full text).
  function K.FitRow(r)
    local rowW = (r.GetWidth and r:GetWidth()) or 0
    if not rowW or rowW <= 0 then return end
    local avail = rowW - 28 - 10 - ((r.act and r.act.IsShown and r.act:IsShown()) and ((r.act:GetWidth() or 0) + 8) or 0)
    r.right:SetWidth(0)
    local rw = (r.right.GetStringWidth and r.right:GetStringWidth()) or 0
    local maxRight = math.floor(avail * 0.6)
    if rw > maxRight then rw = maxRight; r.right:SetWidth(rw); r.right:SetWordWrap(false) end
    r.left:SetWidth(math.max(80, avail - rw))
  end

  -- data rows: { id, icon, left, right, tip, tipTitle, act, onAct,  goal rows also: pct, done, want, goalIndex }
  function K.Fill(rows, data, offset)
    for i, r in ipairs(rows) do
      local d = data[i + (offset or 0)]
      if d then
        r.icon:SetTexture(d.icon or 134400)
        r.left:SetText(d.left or ""); r.right:SetText(d.right or "")
        r.itemId, r.tip, r.tipTitle, r.data, r.goalIndex = d.id, d.tip, d.tipTitle, d, d.goalIndex
        if r.act then
          if d.act then r.act:SetText(d.act); r.act:SetScript("OnClick", d.onAct); r.act:Show() else r.act:Hide() end
        end
        if r.edit then
          r.right:ClearAllPoints()
          if d.want then
            r.edit:Show()
            if not r.edit:HasFocus() then r.edit:SetText(tostring(d.want)) end
            r.right:SetPoint("RIGHT", r.edit, "LEFT", -8, 0)
          else
            r.edit:Hide()
            if r.act then r.right:SetPoint("RIGHT", r.act, "LEFT", -8, 0) else r.right:SetPoint("RIGHT", r, "RIGHT", -6, 0) end
          end
        end
        if r.bar then
          if d.pct then r.bar:Show(); r.bar:Set(d.pct, d.done and "done" or nil) else r.bar:Hide() end
        else
          K.FitRow(r)
        end
        r:Show()
      else
        r.data, r.goalIndex = nil, nil
        r:Hide()
      end
    end
  end

  -- Goal rows from ns.GoalRows(): same text, bar and buttons in every module.
  -- noun = "picked" / "mined" / "caught" ...
  function K.GoalData(list, whereLabel)
    local data = {}
    for _, g in ipairs(list) do
      local done = g.have >= g.want
      data[#data + 1] = { id = g.id, icon = UI.Icon(g.id),
        pct = math.min(1, g.have / math.max(g.want, 1)), done = done,
        left = (done and FA.GREEN or "") .. (g.name or "?") .. (done and "|r" or ""),
        right = ("%s%d  /|r"):format(done and FA.GREEN or FA.YELLOW, g.have),
        want = g.want, goalIndex = g.i,
        tip = (g.where or g.best) and ((whereLabel or "Best spot: ") .. (g.where or g.best)) or "No logged spot yet.",
        act = "Remove", onAct = function() ns.RemoveGoal(g.i) end }
    end
    return data
  end

  function K.Wheel(p, key, getMax)
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, d)
      view[key] = math.max(0, math.min((view[key] or 0) - d * 3, math.max(0, getMax())))
      Changed()
    end)
  end

  return K
end
