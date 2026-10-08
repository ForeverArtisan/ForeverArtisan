-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Cooking: window (/fa cook) with Cooking / Progress / Cook log / Recipe book tabs
local _, ns = ...
if not ns or not ns.DB then return end

local ROW_H, W, H = 24, 470, 578
local FA = ForeverArtisan
local GOLD, GRAY, GREEN, YELLOW, RED = FA.GOLD, FA.GRAY, FA.GREEN, FA.YELLOW, FA.RED


local f
local pages, tabs = {}, {}
local view = { tab = "main", logOff = 0, guideOff = 0, bookShow = "all" }

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
  -- what one craft costs and what it sells for (Auction House or vendor)
  local value = FA.CraftValueLines and FA.CraftValueLines(r) or {}
  if #value > 0 then
    lines[#lines + 1] = " "
    for _, l in ipairs(value) do lines[#lines + 1] = l end
  end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------- page 1: Cooking
local NOW_ROWS = 9
-- Click a recipe you know: open the game's Cooking window on it (the window itself opens from a
-- secure button, "Open window", top right; this only works once the window is open or the client allows it).
local function OpenOnRecipe(r)
  if not (r and r.learned) or (InCombatLockdown and InCombatLockdown()) then return end
  local T = C_TradeSkillUI
  local function shown()
    for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
      if _G[name] and _G[name]:IsShown() then return true end
    end
  end
  if T and T.OpenRecipe and r.id then pcall(T.OpenRecipe, r.id) end
  -- if the client didn't open it for us, say how
  if C_Timer then C_Timer.After(0.3, function() if not shown() then print(FA.Prefix("Cooking") .. "use Open window on the first tab, then pick " .. r.name .. ".") end end) end
end

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

  Header(p, -158, "Cook now")
  Text(p, "GameFontDisableSmall", "TOPLEFT", 90, -160):SetText("recipes that still give skill-ups")
  p.rows = MakeRows(p, NOW_ROWS, -178, false)
  p.empty = Text(p, "GameFontDisable", "TOPLEFT", 20, -182); p.empty:SetWidth(420)
  p.open = FA.UI.ProfessionButton(p, "Cooking", 240); p.open:SetPoint("TOPLEFT", 20, -208)
  -- always there once you know the profession: opens the game's own window
  p.openTop = FA.UI.ProfessionButton(p, "Cooking", 110, "Open window", 22); p.openTop:SetPoint("TOPRIGHT", -16, -4)
  FA.UI.Tip(p.openTop, function()
    GameTooltip:AddLine("Open your Cooking window")
    GameTooltip:AddLine("Opening it also refreshes your recipes here.", 1, 1, 1, true)
  end)
  for _, row in ipairs(p.rows) do
    row:SetScript("OnClick", function(self) if self.data and self.data.recipe then OpenOnRecipe(self.data.recipe) end end)
  end

  p.checks = {
    Check(p, "Show cooking info on ingredient tooltips", 16, -412,
      function() return S().tooltips end, function(v) S().tooltips = v end),
  }
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("/fa cook next  ·  /fa cook plan 225  ·  open your Cooking window to refresh recipes")
end

-- the only part of the first tab that changes with time; the rest refreshes on change
function ns.RefreshSession(p)
  local s = ns.SessionInfo()
  if s.cooks > 0 then
    p.sess:SetText(("%d cooked  ·  %d skill-up%s%s"):format(s.cooks, s.ups, s.ups == 1 and "" or "s",
      s.perHour and ("  ·  " .. GOLD .. s.perHour .. " cooks/hour|r") or ""))
    p.last:SetText(s.last and (GRAY .. "Last cook: |r" .. s.last) or "")
  else
    p.sess:SetText(GRAY .. "Nothing cooked yet this session.|r"); p.last:SetText("")
  end
end

local function RefreshMainPage(p)
  local i = ns.SkillInfo()
  local knows = ns.Knows()
  if i.rank then
    p.skill:SetText(("Cooking %d%s%s"):format(i.rank, i.max and (" / " .. i.max) or "",
      (i.mod and i.mod > 0) and (GREEN .. "  (+" .. i.mod .. ")|r") or ""))
    if i.capped then
      p.color:SetText(RED .. ("Capped at %d.|r "):format(i.max) .. (i.advice or "Train the next rank to keep gaining skill."))
    else
      p.color:SetText(i.advice and (GRAY .. "Next rank: " .. i.advice .. "|r") or "")
    end
  else
    p.skill:SetText("Cooking")
    p.color:SetText(GRAY .. "You haven't learned Cooking on this character.|r")
  end

  local list = {}
  if knows and ns.HasRecipes() then
    local c = ns.CharRec()
    local n, learned = 0, 0
    for _, r in pairs(c.recipes) do n = n + 1; if r.learned then learned = learned + 1 end end
    p.find:SetText(GREEN .. ("%d recipes read, %d learned|r"):format(n, learned))
    for _, e in ipairs((ns.CookNow())) do
      list[#list + 1] = { id = e.r.itemId, icon = Icon(e.r.itemId), recipe = e.r,
        left = ns.COLOR_CODE[e.color] .. e.r.name .. "|r",
        right = e.make > 0 and (GREEN .. "can make " .. e.make .. "|r") or (GRAY .. "missing ingredients|r"),
        tip = ReagentTip(e.r) }
    end
    p.empty:SetText(#list == 0 and "None of your recipes give skill-ups right now. Learn new ones or train." or "")
  elseif knows then
    p.find:SetText(YELLOW .. "Your recipes haven't been read yet.|r")
    p.empty:SetText(YELLOW .. "Open the Cooking window once and every recipe is read. Click here:|r")
  else
    p.find:SetText(""); p.empty:SetText("")
  end
  Fill(p.rows, list, 0)

  ns.RefreshSession(p)
  p.open:ShowIf(knows and not ns.HasRecipes())
  p.openTop:ShowIf(knows and ns.HasRecipes())
  -- not learned: say where to learn it
  p.learnFrom = nil
  if not i.rank then
    local npc = ns.LearnFrom and ns.LearnFrom()
    p.learnFrom = npc
    if npc then
      p.find:SetText(GOLD .. "Learn from: " .. npc.n .. ", " .. (npc.s or npc.z or "?") .. "|r"
        .. (npc.seenOnly and (GRAY .. "  (seen, talk to them)|r") or ""))
    else
      p.find:SetText(GRAY .. "Ask a city guard for a Cooking trainer.|r")
    end
  end
  p.find:SetWidth(p.learnFrom and 330 or 430)
  p.learnBtn:SetShown(p.learnFrom ~= nil)
  for _, c in ipairs(p.checks) do c:Sync() end
end

---------------------------------------------------------------- page 2: Progress (plan + shopping list)
local PLAN_ROWS, SHOP_ROWS = 5, 8     -- at the normal window height
local PLAN_MAX, SHOP_MAX = 12, 20     -- when the window is dragged taller
-- A taller window shows more of both lists: a third of the extra rows go to the plan, the rest
-- to the shopping list (which moves down). True when the row counts changed.
local function LayoutProgress(p, extra)
  local more = math.floor(math.max(0, extra or 0) / ROW_H)
  local addPlan = math.min(PLAN_MAX - PLAN_ROWS, math.ceil(more / 3))
  local addShop = math.min(SHOP_MAX - SHOP_ROWS, more - addPlan)
  if p.planRows and #p.planRows == PLAN_ROWS + addPlan and #p.shopRows == SHOP_ROWS + addShop then return false end
  p.planRows = K.Visible(p.planAll, PLAN_ROWS + addPlan, p.planRows)
  p.shopRows = K.Visible(p.shopAll, SHOP_ROWS + addShop, p.shopRows)
  p.shopBox:ClearAllPoints(); p.shopBox:SetPoint("TOPLEFT", 0, -238 - addPlan * ROW_H)
  return true
end
local function BuildProgressPage(p)
  p.skillBar = K.SkillBar(p, -2, "Cooking")
  p.rate = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -36); p.rate:SetWidth(430)

  Header(p, -54, "Plan to skill")
  p.target = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  p.target:SetSize(46, 20); p.target:SetPoint("TOPLEFT", 120, -50)
  p.target:SetAutoFocus(false); p.target:SetNumeric(true); p.target:SetMaxLetters(3)
  p.target:SetScript("OnEnterPressed", function(self) self:ClearFocus(); view.target = tonumber(self:GetText()); view.planOff, view.shopOff = 0, 0; ns.OnChange() end)
  p.target:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  Text(p, "GameFontDisableSmall", "TOPLEFT", 176, -56):SetText("type a skill and press Enter")
  -- cap / stuck notes sit right under the target box so the reason for a short plan is obvious
  p.note = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -74); p.note:SetWidth(430); p.note:SetJustifyH("LEFT")
  p.planAll = MakeRows(p, PLAN_MAX, -100, false)

  -- the shopping list moves down when the window is taller and the plan shows more rows
  p.shopBox = CreateFrame("Frame", nil, p); p.shopBox:SetSize(W, 20); p.shopBox:SetPoint("TOPLEFT", 0, -238)
  Header(p.shopBox, 0, "Shopping list")
  Text(p.shopBox, "GameFontDisableSmall", "TOPLEFT", 120, -2):SetText("have / need  ·  hover for where to get it and price")
  p.shopAll = MakeRows(p.shopBox, SHOP_MAX, -20, false)
  -- click a shopping list item at the Auction House: its name goes in the search box (you press Search)
  for _, r in ipairs(p.shopAll) do
    r:SetScript("OnClick", function(self)
      local d = self.data
      -- a Train line: waypoint to the trainer
      if d and d.waypoint and FA.Vendors and FA.Vendors.waypoint then FA.Vendors.waypoint(d.waypoint) return end
      if not (d and d.name) then return end
      if FA.SearchAH and FA.SearchAH(d.name) then return end
      -- away from the Auction House: a waypoint to the cheapest vendor you've met who sells it
      local npc = FA.VendorNPC and FA.VendorNPC(d.id, d.name)
      if npc and FA.Vendors and FA.Vendors.waypoint then FA.Vendors.waypoint(npc) return end
      ns.say(("No vendor you've met sells %s. At the Auction House, click it here to search for it."):format(d.name))
    end)
  end
  -- mouse wheel over either list scrolls it
  K.ScrollRows(p.planAll, "planOff", function() return (p.planCount or 0) - #p.planRows end)
  K.ScrollRows(p.shopAll, "shopOff", function() return (p.shopCount or 0) - #p.shopRows end)
  LayoutProgress(p, 0)
  p.cost = Text(p, "GameFontHighlightSmall", "BOTTOMLEFT", 20, 36, p, "BOTTOMLEFT"); p.cost:SetWidth(430); p.cost:SetJustifyH("LEFT")
  p.empty = Text(p, "GameFontDisable", "TOPLEFT", 20, -104); p.empty:SetWidth(420)
  p.open = FA.UI.ProfessionButton(p, "Cooking", 240); p.open:SetPoint("TOPLEFT", 20, -128)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Cook counts are estimates: orange always skills up, yellow and green less often.")
end

local function RefreshProgressPage(p)
  local i = ns.SkillInfo()
  if i.rank then
    p.skillBar:Set(i.rank, i.max, i.capped)
    p.rate:SetText(i.cpp and ("About %.1f cooks per point lately"):format(i.cpp) or (GRAY .. "Cook a few things and your pace shows here.|r"))
  else
    p.skillBar:Set(nil); p.rate:SetText(GRAY .. "You haven't learned Cooking on this character.|r")
  end
  if i.rank then p.rate:SetText(("%d cook%s since your last skill-up  ·  "):format(i.sinceUp or 0, (i.sinceUp or 0) == 1 and "" or "s") .. (p.rate:GetText() or "")) end
  p.open:ShowIf(ns.Knows() and not ns.HasRecipes())
  if not (ns.Knows() and ns.HasRecipes()) then
    Fill(p.planRows, {}, 0); Fill(p.shopRows, {}, 0); p.note:SetText(""); p.cost:SetText(""); p.target:SetTextColor(1, 1, 1)
    p.empty:SetText(ns.Knows() and "Open your Cooking window once so I can read your recipes." or "")
    return
  end
  p.empty:SetText("")
  local default = math.min((i.max and i.max > i.rank) and i.max or (i.rank + 25), 300)
  local target = view.target or default
  if not p.target:HasFocus() then p.target:SetText(tostring(target)) end
  local steps, shopping, stuck, _, _, hint = ns.Plan(target)

  local plan = {}
  for _, st in ipairs(steps) do
    local c = ns.ColorFor(st.r, st.from)
    plan[#plan + 1] = { id = st.r.itemId, icon = Icon(st.r.itemId),
      left = ns.COLOR_CODE[c] .. st.r.name .. "|r  " .. GRAY .. "x" .. st.cooks .. "|r",
      right = GRAY .. ("skill %d-%d"):format(st.from, st.to) .. "|r", tip = ReagentTip(st.r) }
  end
  -- recipes to train on the way: say where and when
  for k, st in ipairs(steps) do
    local row = plan[k]
    if st.train and row then
      row.right = YELLOW .. ("train at %d"):format(st.train.at) .. "|r  " .. (row.right or "")
      row.tip = YELLOW .. ("Not learned yet: train it at %d%s."):format(st.train.at,
        st.train.who and (" from " .. st.train.who) or "") .. "|r\n" .. (row.tip or "")
    end
  end
  if #plan == 0 and i.rank and target <= i.rank then
    plan[1] = { icon = 134400, left = GREEN .. "You're already there.|r", right = "" }
  end
  p.planCount = #plan
  view.planOff = math.max(0, math.min(view.planOff or 0, #plan - #p.planRows))
  Fill(p.planRows, plan, view.planOff)
  -- explain why the plan is short: capped rank first, then recipes running out
  local notes, unreachable = {}, false
  if i.capped and target > i.max then
    notes[#notes + 1] = RED .. ("Capped at %d. Train the next rank first; the plan past %d won't count until you do.|r"):format(i.max, i.max)
    unreachable = true
  end
  if stuck and stuck < target then
    notes[#notes + 1] = YELLOW .. ("Your recipes stop giving skill-ups at %d. Learn new recipes to go further.|r"):format(stuck)
    if hint then notes[#notes + 1] = GRAY .. hint .. "|r" end
    unreachable = true
  end
  p.note:SetText(table.concat(notes, "\n"))
  if unreachable then p.target:SetTextColor(1, .4, .4) else p.target:SetTextColor(1, 1, 1) end

  -- training first: what you can learn now in one line, then the rest by the skill you need
  local shop = FA.TrainShopRows and FA.TrainShopRows(shopping, i.rank) or {}
  for _, e in ipairs(shopping) do
    if not e.train then
    local done = e.have >= e.need
    local cost = (not done and e.price) and (GRAY .. "  ·  " .. FA.Money(e.price * (e.need - e.have)) .. "|r") or ""
    shop[#shop + 1] = { id = e.id, icon = Icon(e.id), name = e.name,
      left = (done and GREEN or "") .. e.name .. (done and "|r" or ""),
      right = ("%s%d / %d|r"):format(done and GREEN or YELLOW, math.min(e.have, e.need), e.need) .. cost,
      tip = " \n" .. GOLD .. "Shopping list|r\n" .. e.source
        .. ((not e.craft and FA.VendorNPC and FA.VendorNPC(e.id, e.name)) and "\n|cff80c0ffClick for a waypoint to the vendor (at the Auction House: search it)|r" or "") .. ((FA.RowPriceLine and FA.RowPriceLine(e.id, e.name)) and ("\n" .. FA.RowPriceLine(e.id, e.name)) or "") }
    end
  end
  p.shopCount = #shop
  view.shopOff = math.max(0, math.min(view.shopOff or 0, #shop - #p.shopRows))
  Fill(p.shopRows, shop, view.shopOff)
  p.cost:SetText(FA.ShopCostText and FA.ShopCostText(shopping) or "")
end

---------------------------------------------------------------- page 3: Cook log
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
  p.header:SetText("Everything you've cooked on this character. Colors are for your skill now.")
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
  Wheel(p, "logOff", function() return (p.count or 0) - LOG_ROWS end)
end

local function RefreshLogPage(p)
  local data = LogData()
  p.count = #data
  view.logOff = math.min(view.logOff, math.max(0, #data - LOG_ROWS))
  Fill(p.rows, data, view.logOff)
  p.empty:SetText(#data == 0 and "Nothing cooked yet. Fire up a campfire!" or "")
end

---------------------------------------------------------------- page 4: Recipe book
local BOOK_ROWS = 16
local function BookData()
  local c = ns.CharRec()
  local skill = ns.Skill()
  local list = {}
  local show = view.bookShow or "all"
  for _, r in pairs(c.recipes) do
    if show == "all" or (show == "learned") == (r.learned and true or false) then list[#list + 1] = r end
  end
  -- where to get each recipe you don't know (looked up once)
  local where = {}
  for _, r in ipairs(list) do
    if not r.learned then
      local w = {}
      if FA.RecipeWhere then
        w.lines, w.tag, w.npc = FA.RecipeWhere(r.name, ns.RecipePrefixes)
      else
        local src = ns.RecipeSource(r.name)
        w.lines = { src and ("Sold by: " .. src) or "Not from a vendor you've met yet." }
      end
      where[r] = w
    end
  end
  -- one list: what you know first, then what's still out there (ones you know a source for first),
  -- each by gray level
  table.sort(list, function(a, b)
    if a.learned ~= b.learned then return a.learned end
    if not a.learned then
      local fa, fb = where[a].tag ~= nil, where[b].tag ~= nil
      if fa ~= fb then return fa end
    end
    if (a.grayAt or 0) ~= (b.grayAt or 0) then return (a.grayAt or 0) < (b.grayAt or 0) end
    return a.name < b.name
  end)
  local data = {}
  local learned, unknown, headed = 0, 0, false
  for _, r in pairs(c.recipes) do if r.learned then learned = learned + 1 else unknown = unknown + 1 end end
  if learned > 0 and show ~= "unlearned" then
    data[#data + 1] = { header = true, noIcon = true, left = GOLD .. ("Learned (%d)"):format(learned) .. "|r" }
  end
  for _, r in ipairs(list) do
    if not r.learned and not headed then
      headed = true
      data[#data + 1] = { header = true, noIcon = true,
        left = GOLD .. ("Not learned yet (%d)"):format(unknown) .. "|r", right = GRAY .. "hover one for where to get it|r" }
    end
    local col = ns.ColorFor(r, skill)
    local tip = ReagentTip(r)
    local tag, npc
    if not r.learned then
      local lines = where[r].lines
      tag, npc = where[r].tag, where[r].npc
      tip = GOLD .. "Where to get it|r\n" .. table.concat(lines, "\n")
        .. (npc and ("\n|cff80c0ffClick for a waypoint|r") or "") .. "\n\n" .. tip
    end
    data[#data + 1] = { id = r.itemId, icon = Icon(r.itemId), recipe = r,
      left = ns.COLOR_CODE[col] .. r.name .. "|r",
      right = (function()
        local g = r.grayAt and ("gray at " .. r.grayAt) or nil
        local t = (not r.learned) and (tag or "not found yet") or nil
        return GRAY .. ((g and t) and (g .. "  ·  " .. t) or g or t or "") .. "|r"
      end)(),
      npc = npc,
      tip = tip }
  end
  return data
end

local function BuildGuidePage(p)
  p.rows = MakeRows(p, BOOK_ROWS, -4, false)
  -- an unlearned recipe with a trainer or vendor you've met: click for a waypoint
  for _, r in ipairs(p.rows) do
    r:SetScript("OnClick", function(self)
      local d = self.data
      if d and d.recipe and d.recipe.learned then OpenOnRecipe(d.recipe)
      elseif d and d.npc and FA.Vendors and FA.Vendors.waypoint then FA.Vendors.waypoint(d.npc) end
    end)
  end
  p.empty = Text(p, "GameFontDisable", "TOP", 0, -100, p, "TOP"); p.empty:SetJustifyH("CENTER")
  p.open = FA.UI.ProfessionButton(p, "Cooking", 240); p.open:SetPoint("TOP", 0, -126)
  -- Show: All (default each time the window opens) / Learned / Not learned. The one showing stays lit.
  local showLabel = Text(p, "GameFontNormal", "BOTTOMLEFT", 20, 46, p, "BOTTOMLEFT"); showLabel:SetText("Show:")
  p.showBtns = {}
  local prev
  for _, o in ipairs({ { "all", "All", 70 }, { "learned", "Learned", 90 }, { "unlearned", "Not learned", 110 } }) do
    local b = Button(p, o[2], o[3], function() view.bookShow, view.guideOff = o[1], 0; ns.OnChange() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", showLabel, "RIGHT", 8, 0) end
    b.value = o[1]
    p.showBtns[#p.showBtns + 1] = b
    prev = b
  end
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 16, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Click a recipe you know to open it. Hover one you don't know for where to get it.")
  Wheel(p, "guideOff", function() return (p.count or 0) - BOOK_ROWS end)
end

local function RefreshGuidePage(p)
  local data = BookData()
  p.count = #data
  ns.lastBook = data -- for the test suite
  for _, b in ipairs(p.showBtns or {}) do
    if b.value == (view.bookShow or "all") then
      if b.LockHighlight then b:LockHighlight() end
      b:SetText(GREEN .. (b.value == "all" and "All" or b.value == "learned" and "Learned" or "Not learned") .. "|r")
    else
      if b.UnlockHighlight then b:UnlockHighlight() end
      b:SetText(b.value == "all" and "All" or b.value == "learned" and "Learned" or "Not learned")
    end
  end
  view.guideOff = math.min(view.guideOff, math.max(0, #data - BOOK_ROWS))
  Fill(p.rows, data, view.guideOff)
  p.empty:SetText(#data > 0 and "" or (not ns.Knows() and "This character hasn't learned Cooking.")
    or (not ns.HasRecipes() and "Open your Cooking window once so I can read your recipes.")
    or ((view.bookShow == "learned") and "You haven't learned any yet. Pick All to see every recipe.")
    or "You know every recipe in the list. Pick All to see them.")
  p.open:ShowIf(ns.Knows() and not ns.HasRecipes())
end

---------------------------------------------------------------- page 5: Best crafts
-- Your learned recipes ranked three ways. Prices: Auctionator's scan or your own Auction House
-- visits; the dot says how much to trust each price. Never searches, posts or buys.
local BEST_ROWS = 14
local BEST_MODES = {
  { "profit", "Most profit", 100, "Recipes you know, ranked by profit per craft after the Auction House's cut." },
  { "level", "Cheapest to level", 140, "Recipes that still give skill-ups, cheapest per point first." },
  { "both", "Profit + skill-ups", 140, "Crafts that level you and pay for themselves." },
}
local DOT = {
  good = "|TInterface\\COMMON\\Indicator-Green:14|t",
  ok = "|TInterface\\COMMON\\Indicator-Yellow:14|t",
  shaky = "|TInterface\\COMMON\\Indicator-Gray:14|t",
}
local CONF_WORD = { good = "steady price", ok = "price looks fair, check it", shaky = "shaky price: old, few listed or swinging" }

local function BestMode() return S().bestMode or "profit" end

local function ConfLines(c)
  if not c then return "" end
  local t = { (c.level == "good" and GREEN or c.level == "ok" and YELLOW or GRAY) .. CONF_WORD[c.level] .. "|r" }
  local bits = {}
  if c.listed then bits[#bits + 1] = c.listed .. " listed" end
  if c.age then bits[#bits + 1] = "seen " .. FA.AgeText(c.age) end
  if c.low and c.high and c.high > c.low then bits[#bits + 1] = "this week " .. FA.Money(c.low) .. " to " .. FA.Money(c.high) end
  if #bits > 0 then t[#t + 1] = GRAY .. table.concat(bits, "  ·  ") .. "|r" end
  return table.concat(t, "\n")
end

local GOLD_TAG = FA.GOLD
local function BestData()
  local mode = BestMode()
  local base, bonus, cap = ns.Skill()
  local skill = base and (base + (bonus or 0))
  -- at your rank's cap nothing gives skill-ups until you train the next rank
  local capped = base and cap and cap > 0 and base >= cap
  local rows = FA.BestCrafts(ns.CharRec().recipes, function(r) return capped and 0 or ns.Chance(r, skill) end, mode)
  local data = {}
  for _, row in ipairs(rows) do
    local c = row.conf or {}
    if not (S().bestHideShaky and c.level == "shaky") then
      local r = row.r
      local col = ns.ColorFor(r, skill)
      local right
      if mode == "level" then
        right = row.perPoint > 0 and (FA.Money(math.floor(row.perPoint + 0.5)) .. " a point")
          or (GREEN .. "earns " .. FA.Money(math.floor(-row.perPoint + 0.5)) .. " a point|r")
      else
        -- a clearly better house replaces the "sells" price with where to sell
        local tag = FA.HouseTag and FA.HouseTag(FA.HouseCompare(r.itemId, r.makes))
        right = (row.profit >= 0 and (GREEN .. "+" .. FA.Money(row.profit)) or (RED .. FA.Money(row.profit))) .. "|r"
          .. (tag and (GOLD_TAG .. "  " .. tag .. "|r") or (GRAY .. "  sells " .. FA.Money(row.sale or row.vend or 0) .. "|r"))
      end
      data[#data + 1] = { id = r.itemId, icon = Icon(r.itemId), recipe = r,
        left = (ns.COLOR_CODE[col] or "") .. r.name .. ((r.makes or 1) > 1 and (" x" .. r.makes) or "") .. "|r",
        right = right, tail = DOT[c.level or "shaky"],
        tip = ConfLines(c) .. "\n\n" .. ReagentTip(r) }  -- ReagentTip ends with "What it's worth" and "Where to sell"
    end
  end
  return data
end

local function BuildBestPage(p)
  p.modeBtns = {}
  local prev
  for _, m in ipairs(BEST_MODES) do
    local b = Button(p, m[2], m[3], function()
      S().bestMode = m[1]; view.bestOff = 0; ns.OnChange()
    end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 20, -4) end
    b.value, b.label = m[1], m[2]
    p.modeBtns[#p.modeBtns + 1] = b
    prev = b
  end
  p.explain = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -32); p.explain:SetWidth(430)
  p.source = Text(p, "GameFontDisableSmall", "TOPLEFT", 20, -48); p.source:SetWidth(430)
  p.rows = MakeRows(p, BEST_ROWS, -80, false)
  for _, row in ipairs(p.rows) do
    row:SetScript("OnClick", function(self)
      local d = self.data
      if not (d and d.recipe) then return end
      -- at the Auction House: put the name in the search box (you press Search); else open the recipe
      if FA.AuctionHouseOpen and FA.AuctionHouseOpen() and FA.SearchAH then FA.SearchAH(d.recipe.name)
      else OpenOnRecipe(d.recipe) end
    end)
  end
  p.empty = Text(p, "GameFontDisable", "TOP", 0, -150, p, "TOP"); p.empty:SetJustifyH("CENTER"); p.empty:SetWidth(400)
  p.hide = K.Check(p, "Hide shaky prices", 16, -(80 + BEST_ROWS * 24 + 4),
    function() return S().bestHideShaky end, function(v) S().bestHideShaky = v or nil; view.bestOff = 0 end)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 16, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText(GOLD_TAG .. "Gold:|r a goblin Auction House (Booty Bay, Gadgetzan, Everlook) pays that much more a craft. Hover for both houses. Dots: green steady, yellow check it, gray shaky. Click to open the recipe (at the Auction House: search it).")
  Wheel(p, "bestOff", function() return (p.count or 0) - BEST_ROWS end)
end

local function RefreshBestPage(p)
  local mode = BestMode()
  for _, b in ipairs(p.modeBtns) do
    if b.value == mode then
      if b.LockHighlight then b:LockHighlight() end
      b:SetText(GREEN .. b.label .. "|r")
    else
      if b.UnlockHighlight then b:UnlockHighlight() end
      b:SetText(b.label)
    end
  end
  for _, m in ipairs(BEST_MODES) do if m[1] == mode then p.explain:SetText(m[4]) end end
  p.source:SetText(table.concat(FA.PriceSourceLines(), "\n"))
  local data = ns.Knows() and BestData() or {}
  p.count = #data
  ns.lastBest = data -- for the test suite
  view.bestOff = math.min(view.bestOff or 0, math.max(0, #data - BEST_ROWS))
  Fill(p.rows, data, view.bestOff)
  if p.hide.Sync then p.hide:Sync() end
  p.empty:SetText(#data > 0 and "" or (not ns.Knows() and "This character hasn't learned Cooking.")
    or (not ns.HasRecipes() and "Open your Cooking window once so I can read your recipes.")
    or (mode ~= "profit" and (function() local b, _, c = ns.Skill(); return b and c and c > 0 and b >= c end)()
      and "You're at this rank's cap: train the next rank and skill-up crafts show here again.")
    or (mode == "level" and "Nothing that still gives skill-ups has prices yet. Visit the Auction House, or scan with Auctionator.")
    or (mode == "both" and "None of your skill-up recipes pays for itself at today's prices.")
    or "No prices yet for what you craft. Visit the Auction House, or scan with Auctionator.")
end

-- the items your recipes use and make get a short price history (Core), on every character
local function WatchMine()
  local db = ns.DB and ns.DB()
  if not (db and db.chars and FA.WatchItems) then return end
  local ids = {}
  for _, c in pairs(db.chars) do
    for _, r in pairs(c.recipes or {}) do
      if r.itemId then ids[#ids + 1] = r.itemId end
      for _, g in ipairs(r.reagents or {}) do if g.id then ids[#ids + 1] = g.id end end
    end
  end
  FA.WatchItems(ids)
end
ns.WatchMine = WatchMine
do
  local w = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW" }) do pcall(w.RegisterEvent, w, e) end
  w:SetScript("OnEvent", function() pcall(WatchMine) end)
end

---------------------------------------------------------------- frame
local REFRESH = { main = RefreshMainPage, progress = RefreshProgressPage, log = RefreshLogPage, guide = RefreshGuidePage,
  best = RefreshBestPage }

local function ShowTab(name)
  view.tab = name
  for k, pg in pairs(pages) do pg:SetShown(k == name) end
  for k, b in pairs(tabs) do b:SetEnabled(k ~= name) end
  if REFRESH[name] then REFRESH[name](pages[name]) end
end

local function Build()
  local order = { { "main", "Cooking" }, { "progress", "Progress" }, { "log", "Cook log" }, { "guide", "Recipe book" }, { "best", "Best crafts" } }
  f = K.Window({ name = "ForeverArtisanCookingFrame", title = "Cooking", tabs = order, pages = pages, tabButtons = tabs, onTab = ShowTab })
  BuildMainPage(pages.main)
  BuildProgressPage(pages.progress)
  BuildLogPage(pages.log)
  BuildGuidePage(pages.guide)
  BuildBestPage(pages.best)
  -- drag the corner to make the window taller: the Progress tab shows more of the plan and list
  K.Tall(f, "height", 900, function(extra)
    if LayoutProgress(pages.progress, extra) and view.tab == "progress" then ns.OnChange() end
  end, "pos")

  f:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t > 5 then self.t = 0; if view.tab == "main" then ns.RefreshSession(pages.main) end end
  end)
  f:HookScript("OnShow", function() view.bookShow, view.guideOff, view.planOff, view.shopOff = "all", 0, 0, 0 end)
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
-- new Auction House prices refresh the shopping list while it's open
if FA.PriceWatchers then
  table.insert(FA.PriceWatchers, function() if view.tab == "progress" or view.tab == "best" then ns.OnChange() end end)
end
