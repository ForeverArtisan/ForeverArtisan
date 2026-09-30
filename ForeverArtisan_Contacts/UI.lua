-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Trade Contacts: window (/fa contacts) with Search / Contacts / Limited stock tabs
local _, ns = ...
local FA = ForeverArtisan
local GOLD, GRAY, GREEN, YELLOW, RED = FA.GOLD, FA.GRAY, FA.GREEN, FA.YELLOW, FA.RED

ns.DB = ns.DB or function() return ForeverArtisanContactsDB end

local f
local pages, tabs = {}, {}
local view = { tab = "search", searchOff = 0, listOff = 0, stockOff = 0, results = {} }

---------------------------------------------------------------- shared style kit (ForeverArtisan Core)
local K = FA.UI.Kit(ns, view)
local Text, Button, Check, Icon, Header = K.Text, K.Button, K.Check, K.Icon, K.Header
local MakeRows, Fill, Wheel = K.MakeRows, K.Fill, K.Wheel
local function S() return ns.DB().settings end

local function ClickToWaypoint(rows)
  for _, r in ipairs(rows) do
    r:SetScript("OnClick", function(self)
      local d = self.data
      if d and d.npc then ns.SetWaypoint(d.npc) end
    end)
  end
end

local function Counts()
  local v, t = 0, 0
  for _, npc in ipairs(ns.Contacts()) do if npc.k == "vendor" then v = v + 1 else t = t + 1 end end
  return v, t
end

---------------------------------------------------------------- page 1: Search
local SEARCH_ROWS = 17
local function SearchData()
  local data = {}
  for _, h in ipairs(view.results) do
    local npc, it = h.npc, h.item
    if it then
      data[#data + 1] = { id = it.id, icon = it.id and Icon(it.id) or (it.train and 136235 or 134400), npc = npc,
        left = it.n .. (it.sk and (GRAY .. "  " .. it.sk .. "|r") or ""),
        right = GRAY .. npc.n .. ", " .. ns.Where(npc) .. (npc.age > 0 and " (before update)" or "") .. "|r  " .. ns.Money(it),
        tip = npc.n .. (npc.t and (" <" .. npc.t .. ">") or "") .. "\n" .. ns.DetailText(npc, it) }
    elseif npc.seenOnly then
      data[#data + 1] = { icon = 134400, npc = npc, tipTitle = npc.n,
        left = GOLD .. npc.n .. "|r" .. (npc.t and (GRAY .. " <" .. npc.t .. ">|r") or ""),
        right = GRAY .. ns.Where(npc) .. "  ·  seen, not visited yet|r",
        tip = ns.Where(npc) .. (npc.x and ("  (%.1f, %.1f)"):format(npc.x, npc.y) or "")
          .. "\nYou've passed this NPC but haven't talked to them yet.\n|cff80c0ffClick for a waypoint|r" }
    else
      data[#data + 1] = { icon = npc.k == "trainer" and 136235 or 133784, npc = npc, tipTitle = npc.n,
        left = GOLD .. npc.n .. "|r" .. (npc.t and (GRAY .. " <" .. npc.t .. ">|r") or ""),
        right = GRAY .. ns.Where(npc) .. (npc.age > 0 and " (before update)" or "")
          .. (h.trains and ("  ·  trains " .. h.trains) or "") .. "|r",
        tip = ns.DetailText(npc) }
    end
  end
  return data
end

local function RunSearch()
  local p = pages.search
  view.results = ns.Search(p.box:GetText())
  view.searchOff = 0
  ns.OnChange()
end

local function BuildSearchPage(p)
  p.box = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  p.box:SetSize(420, 22); p.box:SetPoint("TOPLEFT", 24, -4)
  p.box:SetAutoFocus(false)
  p.box:SetScript("OnTextChanged", function(_, user) if user then RunSearch() end end)
  p.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  p.status = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -32); p.status:SetWidth(430)
  p.rows = MakeRows(p, SEARCH_ROWS, -50, false)
  ClickToWaypoint(p.rows)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Search items, vendors, towns or a profession (\"tailoring\"). Click a row for a waypoint.")
  Wheel(p, "searchOff", function() return #view.results - SEARCH_ROWS end)
end

local function RefreshSearchPage(p)
  local data = SearchData()
  view.searchOff = math.min(view.searchOff, math.max(0, #data - SEARCH_ROWS))
  Fill(p.rows, data, view.searchOff)
  local v, t = Counts()
  local q = p.box:GetText() or ""
  if v + t == 0 then
    p.status:SetText(YELLOW .. "No contacts yet. Talk to a crafting vendor or profession trainer and they show up here.|r")
  elseif q == "" then
    p.status:SetText(("%d vendors and %d trainers you've met. Type to search."):format(v, t))
  elseif #data == 0 then
    p.status:SetText(GRAY .. "Nothing matches among the NPCs you've met or passed.|r")
  else
    p.status:SetText(("%d result%s"):format(#data, #data == 1 and "" or "s"))
  end
end

---------------------------------------------------------------- page 2: Contacts
local LIST_ROWS = 16
local function ListData()
  local list = {}
  for _, npc in ipairs(ns.Contacts()) do list[#list + 1] = npc end
  table.sort(list, function(a, b)
    if (a.z or "") ~= (b.z or "") then return (a.z or "") < (b.z or "") end
    if ns.Where(a) ~= ns.Where(b) then return ns.Where(a) < ns.Where(b) end
    return a.n < b.n
  end)
  local data = {}
  for _, npc in ipairs(list) do
    local what = npc.k == "trainer" and ("%d skills"):format(#npc.items) or ("%d items"):format(#npc.items)
    local status = (npc.age >= ns.HIDE_AFTER and "  ·  |cffff4040hidden|r") or (npc.age == 1 and "  ·  |cffff9020before update|r") or ""
    local name = (npc.age > 0 and GRAY or "") .. npc.n .. (npc.age > 0 and "|r" or "")
    data[#data + 1] = { icon = npc.k == "trainer" and 136235 or 133784, npc = npc, tipTitle = npc.n,
      left = name .. (npc.t and (GRAY .. " <" .. npc.t .. ">|r") or ""),
      right = GRAY .. ns.Where(npc) .. "  ·  " .. what .. "|r" .. status,
      tip = ns.DetailText(npc) .. "\n|cff9d9d9dRight-click twice to forget this contact.|r" }
  end
  return data
end

local function BuildListPage(p)
  p.header = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -4); p.header:SetWidth(430)
  p.rows = MakeRows(p, LIST_ROWS, -24, false)
  -- left-click: waypoint. Right-click twice (within 3 seconds): forget this contact.
  for _, r in ipairs(p.rows) do
    r:SetScript("OnClick", function(self, button)
      local d = self.data
      if not (d and d.npc) then return end
      if button == "RightButton" then
        if self.armedKey == d.npc.key then
          self.armedKey = nil
          ns.Forget(d.npc.key)
        else
          self.armedKey = d.npc.key
          self.right:SetText(RED .. "Right-click again to forget|r")
          C_Timer.After(3, function() if self.armedKey then self.armedKey = nil; ns.OnChange() end end)
        end
      else
        ns.SetWaypoint(d.npc)
      end
    end)
  end
  p.empty = Text(p, "GameFontDisable", "TOP", 0, -100, p, "TOP"); p.empty:SetJustifyH("CENTER")
  p.checks = {
    Check(p, "Show 'Sold by' on item tooltips", 16, -420,
      function() return S().tooltips ~= false end, function(v) S().tooltips = v end),
  }
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Click: waypoint  ·  Right-click twice: forget  ·  Saved on this computer for all your characters.")
  Wheel(p, "listOff", function() return #ListData() - LIST_ROWS end)
end

local function RefreshListPage(p)
  local data = ListData()
  local v, t = Counts()
  local old = 0
  for _, npc in ipairs(ns.Contacts()) do if npc.age > 0 then old = old + 1 end end
  p.header:SetText(("%d vendors  ·  %d trainers  ·  by zone and town"):format(v, t)
    .. (old > 0 and (GRAY .. ("  ·  %d not seen since a game update"):format(old) .. "|r") or ""))
  view.listOff = math.min(view.listOff, math.max(0, #data - LIST_ROWS))
  Fill(p.rows, data, view.listOff)
  p.empty:SetText(#data == 0 and "No contacts yet.\nTalk to a crafting vendor or profession trainer." or "")
  for _, c in ipairs(p.checks) do c:Sync() end
end

---------------------------------------------------------------- page 3: Limited stock
local STOCK_ROWS = 17
local function StockData()
  local data = {}
  for _, npc in ipairs(ns.Contacts()) do
    for _, it in ipairs(npc.age < ns.HIDE_AFTER and npc.items or {}) do
      if it.lim then
        data[#data + 1] = { id = it.id, icon = it.id and Icon(it.id) or 134400, npc = npc,
          left = it.n, right = GRAY .. npc.n .. ", " .. ns.Where(npc) .. "|r  " .. (it.lim > 0 and (GREEN .. it.lim .. " left|r") or (RED .. "sold out|r")),
          tip = npc.n .. "\n" .. ns.DetailText(npc, it) }
      end
    end
  end
  table.sort(data, function(a, b) return a.left < b.left end)
  return data
end

local function BuildStockPage(p)
  p.header = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -4); p.header:SetWidth(430)
  p.header:SetText("Limited-stock items (recipes, rare reagents) and how many were left when you last looked.")
  p.rows = MakeRows(p, STOCK_ROWS, -24, false)
  ClickToWaypoint(p.rows)
  p.empty = Text(p, "GameFontDisable", "TOP", 0, -100, p, "TOP"); p.empty:SetJustifyH("CENTER")
  Wheel(p, "stockOff", function() return #StockData() - STOCK_ROWS end)
end

local function RefreshStockPage(p)
  local data = StockData()
  view.stockOff = math.min(view.stockOff, math.max(0, #data - STOCK_ROWS))
  Fill(p.rows, data, view.stockOff)
  p.empty:SetText(#data == 0 and "No limited-stock items seen yet." or "")
end

---------------------------------------------------------------- frame
local REFRESH = { search = RefreshSearchPage, contacts = RefreshListPage, stock = RefreshStockPage }

local function ShowTab(name)
  view.tab = name
  for k, pg in pairs(pages) do pg:SetShown(k == name) end
  for k, b in pairs(tabs) do b:SetEnabled(k ~= name) end
  if REFRESH[name] then REFRESH[name](pages[name]) end
end

local function Build()
  local order = { { "search", "Search" }, { "contacts", "Contacts" }, { "stock", "Limited stock" } }
  f = K.Window({ name = "ForeverArtisanContactsFrame", title = "Trade Contacts", tabs = order, pages = pages,
    tabButtons = tabs, onTab = ShowTab })
  BuildSearchPage(pages.search)
  BuildListPage(pages.contacts)
  BuildStockPage(pages.stock)
  f:Hide()
  ShowTab("search")
end

function ns.ToggleWindow()
  if not ns.DB() then return end
  if not f then Build() end
  if f:IsShown() then f:Hide() else f:Show(); ShowTab(view.tab) end
end

function ns.OpenSearch(q)
  if not ns.DB() then return end
  if not f then Build() end
  f:Show(); ShowTab("search")
  local box = pages.search.box
  if q and q ~= "" then box:SetText(q); RunSearch() else box:SetFocus() end
end

function ns.OnChange()
  if f and f:IsShown() and REFRESH[view.tab] then REFRESH[view.tab](pages[view.tab]) end
end
