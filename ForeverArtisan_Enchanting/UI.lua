-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Enchanting: window (/fa ench) with Enchanting / Progress / Craft log / Recipe book tabs
-- Same window as First Aid; tools/build_crafts.py writes this file from a template.
local _, ns = ...
if not ns or not ns.DB then return end

local ROW_H, W, H = 24, 470, 578
local FA = ForeverArtisan
local GOLD, GRAY, GREEN, YELLOW, RED = FA.GOLD, FA.GRAY, FA.GREEN, FA.YELLOW, FA.RED


local f
local pages, tabs = {}, {}
local view = { tab = "main", logOff = 0, guideOff = 0, bookAll = false }

---------------------------------------------------------------- shared style kit (ForeverArtisan Core)
local K = FA.UI.Kit(ns, view)
local Text, Button, Check, Icon, Header = K.Text, K.Button, K.Check, K.Icon, K.Header
local MakeRows, Fill, Wheel = K.MakeRows, K.Fill, K.Wheel
local function S() return ns.DB().settings end

local function ReagentTip(r)
  local lines = {}
  for _, g in ipairs(r.reagents or {}) do
    local have = ns.Count(g.id)
    local col = have >= (g.n or 1) and GREEN or RED
    lines[#lines + 1] = ("%s%d/%d|r %s"):format(col, math.min(have, g.n or 1), g.n or 1, ns.ItemName(g.id, g.name))
  end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------- page 1: Enchanting
local NOW_ROWS = 9
local function BuildMainPage(p)
  p.skill = Text(p, "GameFontNormalLarge", "TOPLEFT", 18, -6)
  p.color = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -28); p.color:SetWidth(430); p.color:SetWordWrap(true)
  p.find = Text(p, "GameFontHighlight", "TOPLEFT", 18, -60); p.find:SetWidth(330)
  p.learnBtn = FA.UI.Button(p, "Waypoint", 90, function()
    local V = ForeverArtisan.Vendors
    if p.learnFrom and V and V.waypoint then V.waypoint(p.learnFrom) end
  end)
  p.learnBtn:SetPoint("TOPRIGHT", -20, -56); p.learnBtn:Hide()

  Header(p, -88, "This session")
  p.sess = Text(p, "GameFontHighlight", "TOPLEFT", 18, -108); p.sess:SetWidth(430)
  p.last = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -128); p.last:SetWidth(430)

  Header(p, -158, "Make now")
  Text(p, "GameFontDisableSmall", "TOPLEFT", 90, -160):SetText("recipes that still give skill-ups")
  p.rows = MakeRows(p, NOW_ROWS, -178, false)
  p.empty = Text(p, "GameFontDisable", "TOPLEFT", 20, -182); p.empty:SetWidth(420)
  p.open = FA.UI.ProfessionButton(p, "Enchanting", 240); p.open:SetPoint("TOPLEFT", 20, -208)

  p.checks = {
    Check(p, "Show Enchanting info on material tooltips", 16, -412,
      function() return S().tooltips end, function(v) S().tooltips = v end),
  }
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("/fa ench next  ·  /fa ench plan 225  ·  open your Enchanting window to refresh recipes")
end

local function RefreshMainPage(p)
  local i = ns.SkillInfo()
  local knows = ns.Knows()
  if i.rank then
    p.skill:SetText(("Enchanting %d%s%s"):format(i.rank, i.max and (" / " .. i.max) or "",
      (i.mod and i.mod > 0) and (GREEN .. "  (+" .. i.mod .. ")|r") or ""))
    if i.capped then
      p.color:SetText(RED .. ("Capped at %d.|r "):format(i.max) .. (i.advice or "Train the next rank to keep gaining skill."))
    else
      p.color:SetText(i.advice and (GRAY .. "Next rank: " .. i.advice .. "|r") or "")
    end
  else
    p.skill:SetText("Enchanting")
    p.color:SetText(GRAY .. "You haven't learned Enchanting on this character.|r")
  end

  local list = {}
  if knows and ns.HasRecipes() then
    local c = ns.CharRec()
    local n, learned = 0, 0
    for _, r in pairs(c.recipes) do n = n + 1; if r.learned then learned = learned + 1 end end
    p.find:SetText(GREEN .. ("%d recipes read, %d learned|r"):format(n, learned))
    for _, e in ipairs((ns.MakeNow())) do
      list[#list + 1] = { id = e.r.itemId, icon = Icon(e.r.itemId),
        left = ns.COLOR_CODE[e.color] .. e.r.name .. "|r",
        right = e.make > 0 and (GREEN .. "can make " .. e.make .. "|r") or (GRAY .. "missing materials|r"),
        tip = ReagentTip(e.r) }
    end
    p.empty:SetText(#list == 0 and "None of your recipes give skill-ups right now. Learn new ones or train." or "")
  elseif knows then
    p.find:SetText(YELLOW .. "Your recipes haven't been read yet.|r")
    p.empty:SetText(YELLOW .. "Open the Enchanting window once and every recipe is read. Click here:|r")
  else
    p.find:SetText(""); p.empty:SetText("")
  end
  Fill(p.rows, list, 0)

  local s = ns.SessionInfo()
  if s.crafts > 0 then
    p.sess:SetText(("%d made  ·  %d skill-up%s%s"):format(s.crafts, s.ups, s.ups == 1 and "" or "s",
      s.perHour and ("  ·  " .. GOLD .. s.perHour .. " crafts/hour|r") or ""))
    p.last:SetText(s.last and (GRAY .. "Last craft: |r" .. s.last) or "")
  else
    p.sess:SetText(GRAY .. "Nothing made yet this session.|r"); p.last:SetText("")
  end
  p.open:ShowIf(knows and not ns.HasRecipes())
  -- not learned: say where to learn it
  p.learnFrom = nil
  if not i.rank then
    local npc = ns.LearnFrom and ns.LearnFrom()
    p.learnFrom = npc
    if npc then
      p.find:SetText(GOLD .. "Learn from: " .. npc.n .. ", " .. (npc.s or npc.z or "?") .. "|r")
    else
      p.find:SetText(GRAY .. "Ask a city guard for a Enchanting trainer.|r")
    end
  end
  p.find:SetWidth(p.learnFrom and 330 or 430)
  p.learnBtn:SetShown(p.learnFrom ~= nil)
  for _, c in ipairs(p.checks) do c:Sync() end
end

---------------------------------------------------------------- page 2: Progress (plan + shopping list)
local PLAN_ROWS, SHOP_ROWS = 5, 8
local function BuildProgressPage(p)
  p.skillBar = K.SkillBar(p, -2, "Enchanting")
  p.rate = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -36); p.rate:SetWidth(430)

  Header(p, -54, "Plan to skill")
  p.target = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  p.target:SetSize(46, 20); p.target:SetPoint("TOPLEFT", 120, -50)
  p.target:SetAutoFocus(false); p.target:SetNumeric(true); p.target:SetMaxLetters(3)
  p.target:SetScript("OnEnterPressed", function(self) self:ClearFocus(); view.target = tonumber(self:GetText()); ns.OnChange() end)
  p.target:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  Text(p, "GameFontDisableSmall", "TOPLEFT", 176, -56):SetText("type a skill and press Enter")
  -- cap / stuck notes sit right under the target box so the reason for a short plan is obvious
  p.note = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -74); p.note:SetWidth(430); p.note:SetJustifyH("LEFT")
  p.planRows = MakeRows(p, PLAN_ROWS, -100, false)

  Header(p, -238, "Shopping list")
  Text(p, "GameFontDisableSmall", "TOPLEFT", 120, -240):SetText("have / need  ·  hover for source  ·  gold = you craft it")
  p.shopRows = MakeRows(p, SHOP_ROWS, -258, false)
  p.empty = Text(p, "GameFontDisable", "TOPLEFT", 20, -104); p.empty:SetWidth(420)
  p.open = FA.UI.ProfessionButton(p, "Enchanting", 240); p.open:SetPoint("TOPLEFT", 20, -128)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Craft counts are estimates: orange always skills up, yellow and green less often.")
end

local function RefreshProgressPage(p)
  local i = ns.SkillInfo()
  if i.rank then
    p.skillBar:Set(i.rank, i.max, i.capped)
    p.rate:SetText(i.cpp and ("About %.1f crafts per point lately"):format(i.cpp) or (GRAY .. "Make a few things and your pace shows here.|r"))
  else
    p.skillBar:Set(nil); p.rate:SetText(GRAY .. "You haven't learned Enchanting on this character.|r")
  end
  if i.rank then p.rate:SetText(("%d craft%s since your last skill-up  ·  "):format(i.sinceUp or 0, (i.sinceUp or 0) == 1 and "" or "s") .. (p.rate:GetText() or "")) end
  p.open:ShowIf(ns.Knows() and not ns.HasRecipes())
  if not (ns.Knows() and ns.HasRecipes()) then
    Fill(p.planRows, {}, 0); Fill(p.shopRows, {}, 0); p.note:SetText(""); p.target:SetTextColor(1, 1, 1)
    p.empty:SetText(ns.Knows() and "Open your Enchanting window once so I can read your recipes." or "")
    return
  end
  p.empty:SetText("")
  local default = math.min((i.max and i.max > i.rank) and i.max or (i.rank + 25), 300)
  local target = view.target or default
  if not p.target:HasFocus() then p.target:SetText(tostring(target)) end
  local steps, shopping, stuck = ns.Plan(target)

  local plan = {}
  for _, st in ipairs(steps) do
    local c = ns.ColorFor(st.r, st.from)
    -- materials made along the way (they give skill-ups too): "+ 300 Light Leather"
    local extra, tipExtra = {}, {}
    for sr, n in pairs(st.sub or {}) do
      extra[#extra + 1] = n .. " " .. sr.name
      tipExtra[#tipExtra + 1] = ("Also makes %d %s along the way (counted in the skill range)."):format(n, sr.name)
    end
    table.sort(extra)
    plan[#plan + 1] = { id = st.r.itemId, icon = Icon(st.r.itemId),
      left = ns.COLOR_CODE[c] .. st.r.name .. "|r  " .. GRAY .. "x" .. st.crafts
        .. (#extra > 0 and ("  + " .. table.concat(extra, ", ")) or "") .. "|r",
      right = GRAY .. ("skill %d-%d"):format(st.from, st.to) .. "|r",
      tip = ReagentTip(st.r) .. (#tipExtra > 0 and ("\n" .. table.concat(tipExtra, "\n")) or "") }
  end
  if #plan == 0 and i.rank and target <= i.rank then
    plan[1] = { icon = 134400, left = GREEN .. "You're already there.|r", right = "" }
  end
  Fill(p.planRows, plan, 0)
  -- explain why the plan is short: capped rank first, then recipes running out
  local notes, unreachable = {}, false
  if i.capped and target > i.max then
    notes[#notes + 1] = RED .. ("Capped at %d. Train the next rank first; the plan past %d won't count until you do.|r"):format(i.max, i.max)
    unreachable = true
  end
  if stuck and stuck < target then
    notes[#notes + 1] = YELLOW .. ("Your learned recipes stop giving skill-ups at %d. Learn new recipes to go further.|r"):format(stuck)
    unreachable = true
  end
  p.note:SetText(table.concat(notes, "\n"))
  if unreachable then p.target:SetTextColor(1, .4, .4) else p.target:SetTextColor(1, 1, 1) end

  local shop = {}
  for _, e in ipairs(shopping) do
    local done = e.have >= e.need
    shop[#shop + 1] = { id = e.id, icon = Icon(e.id),
      left = (done and GREEN or "") .. e.name .. (done and "|r" or ""),
      right = ("%s%d / %d|r"):format(done and GREEN or YELLOW, math.min(e.have, e.need), e.need)
        .. (e.craft and (GOLD .. "  ·  craft " .. e.craft .. "|r") or ""),
      tip = e.source }
  end
  Fill(p.shopRows, shop, 0)
end

---------------------------------------------------------------- page 3: Craft log
local LOG_ROWS = 15
local function LogData()
  local c = ns.CharRec()
  local list, skill = {}, ns.Skill()
  for name, e in pairs(c.log or {}) do list[#list + 1] = { name = name, e = e } end
  table.sort(list, function(a, b) return a.e.n > b.e.n end)
  local data = {}
  for _, x in ipairs(list) do
    local r = c.recipes[x.name]
    local col = ns.ColorFor(r, skill)
    data[#data + 1] = { id = r and r.itemId, icon = Icon(r and r.itemId),
      left = ns.COLOR_CODE[col] .. x.name .. "|r",
      right = ("x%d%s"):format(x.e.n, x.e.lo and (GRAY .. "  ·  at skill " .. (x.e.lo == x.e.hi and x.e.lo or (x.e.lo .. "-" .. x.e.hi)) .. "|r") or "") }
  end
  return data
end

local function BuildLogPage(p)
  p.header = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -4); p.header:SetWidth(430)
  p.header:SetText("Everything you've made on this character. Colors are for your skill now.")
  p.rows = MakeRows(p, LOG_ROWS, -24, false)
  p.empty = Text(p, "GameFontDisable", "TOP", 0, -100, p, "TOP"); p.empty:SetJustifyH("CENTER")
  local reset = Button(p, "Reset log", 110, function(self)
    if self.armed then
      ns.ResetLog(); self.armed = false; self:SetText("Reset log")
    else
      self.armed = true; self:SetText(RED .. "Click to confirm|r")
      C_Timer.After(3, function() self.armed = false; self:SetText("Reset log") end)
    end
  end)
  reset:SetPoint("BOTTOMRIGHT", -16, 12)
  Wheel(p, "logOff", function() return #LogData() - LOG_ROWS end)
end

local function RefreshLogPage(p)
  local data = LogData()
  view.logOff = math.min(view.logOff, math.max(0, #data - LOG_ROWS))
  Fill(p.rows, data, view.logOff)
  p.empty:SetText(#data == 0 and "Nothing enchanted yet. Disenchant some greens for dust!" or "")
end

---------------------------------------------------------------- page 4: Recipe book
local BOOK_ROWS = 16
local function BookData()
  local c = ns.CharRec()
  local skill = ns.Skill()
  local list = {}
  for _, r in pairs(c.recipes) do
    if view.bookAll or r.learned then list[#list + 1] = r end
  end
  table.sort(list, function(a, b)
    local ga, gb = ns.GrayAt(a) or 0, ns.GrayAt(b) or 0
    if ga ~= gb then return ga < gb end
    return a.name < b.name
  end)
  local data = {}
  for _, r in ipairs(list) do
    local col = ns.ColorFor(r, skill)
    local tip = ReagentTip(r)
    if not r.learned then
      local src = ns.RecipeSource(r.name)
      tip = (src and ("Recipe sold by " .. src) or "Recipe source not in your vendor list yet.") .. "\n" .. tip
    end
    data[#data + 1] = { id = r.itemId, icon = Icon(r.itemId),
      left = ns.COLOR_CODE[col] .. r.name .. "|r",
      right = (r.grayAt and (GRAY .. "gray at " .. r.grayAt .. "|r")
          or (ns.GrayAt(r) and (GRAY .. "gray at ~" .. ns.GrayAt(r) .. "|r")) or "")
        .. (r.learned and "" or (GRAY .. "  ·  not learned|r")),
      tip = tip }
  end
  return data
end

local function BuildGuidePage(p)
  local tLearned = Button(p, "Learned", 90, function() view.bookAll, view.guideOff = false, 0; ns.OnChange() end)
  tLearned:SetPoint("TOPLEFT", 16, -2)
  local tAll = Button(p, "All recipes", 90, function() view.bookAll, view.guideOff = true, 0; ns.OnChange() end)
  tAll:SetPoint("LEFT", tLearned, "RIGHT", 6, 0)
  p.tLearned, p.tAll = tLearned, tAll
  p.rows = MakeRows(p, BOOK_ROWS, -30, false)
  p.empty = Text(p, "GameFontDisable", "TOP", 0, -100, p, "TOP"); p.empty:SetJustifyH("CENTER")
  p.open = FA.UI.ProfessionButton(p, "Enchanting", 240); p.open:SetPoint("TOP", 0, -126)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Hover a recipe for its materials and, if you don't know it, who sells it.")
  Wheel(p, "guideOff", function() return #BookData() - BOOK_ROWS end)
end

local function RefreshGuidePage(p)
  local data = BookData()
  view.guideOff = math.min(view.guideOff, math.max(0, #data - BOOK_ROWS))
  Fill(p.rows, data, view.guideOff)
  p.empty:SetText(#data == 0 and "Open your Enchanting window once so I can read your recipes." or "")
  p.open:ShowIf(ns.Knows() and not ns.HasRecipes())
  p.tLearned:SetEnabled(view.bookAll)
  p.tAll:SetEnabled(not view.bookAll)
end

---------------------------------------------------------------- frame
local REFRESH = { main = RefreshMainPage, progress = RefreshProgressPage, log = RefreshLogPage, guide = RefreshGuidePage }

local function ShowTab(name)
  view.tab = name
  for k, pg in pairs(pages) do pg:SetShown(k == name) end
  for k, b in pairs(tabs) do b:SetEnabled(k ~= name) end
  if REFRESH[name] then REFRESH[name](pages[name]) end
end

local function Build()
  local order = { { "main", "Enchanting" }, { "progress", "Progress" }, { "log", "Craft log" }, { "guide", "Recipe book" } }
  f = K.Window({ name = "ForeverArtisanEnchantingFrame", title = "Enchanting", tabs = order, pages = pages, tabButtons = tabs, onTab = ShowTab })
  BuildMainPage(pages.main)
  BuildProgressPage(pages.progress)
  BuildLogPage(pages.log)
  BuildGuidePage(pages.guide)

  f:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t > 1 then self.t = 0; if view.tab == "main" then RefreshMainPage(pages.main) end end
  end)
  f:Hide()
  ShowTab("main")
end

function ns.ToggleWindow()
  if not f then Build() end
  if f:IsShown() then f:Hide() else f:Show(); ShowTab(view.tab) end
end

function ns.OnChange()
  if f and f:IsShown() and REFRESH[view.tab] then REFRESH[view.tab](pages[view.tab]) end
end
