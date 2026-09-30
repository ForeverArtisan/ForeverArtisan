-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Trade Contacts: window (/fa contacts) with Search / Contacts / Limited stock tabs
local _, ns = ...
local FA = ForeverArtisan
local GOLD, GRAY, GREEN, YELLOW, RED = FA.GOLD, FA.GRAY, FA.GREEN, FA.YELLOW, FA.RED

ns.DB = ns.DB or function() return ForeverArtisanContactsDB end

local f
local pages, tabs = {}, {}
ns.Pages = pages -- for the test suite
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
  for _, npc in ipairs(ns.Contacts()) do if npc.k == "vendor" then v = v + 1 elseif npc.k == "trainer" then t = t + 1 end end
  return v, t
end

---------------------------------------------------------------- page 1: Search
local SEARCH_ROWS = 15
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
        right = GRAY .. ns.Where(npc) .. "  ·  seen, talk to save|r",
        tip = ns.Where(npc) .. (npc.x and ("  (%.1f, %.1f)"):format(npc.x, npc.y) or "")
          .. "\nYou've passed this NPC but haven't talked to them yet.\n|cff80c0ffClick for a waypoint|r" }
    else
      data[#data + 1] = { icon = npc.k == "trainer" and 136235 or 133784, npc = npc, tipTitle = npc.n,
        left = GOLD .. npc.n .. "|r" .. (npc.t and (GRAY .. " <" .. npc.t .. ">|r") or ""),
        right = GRAY .. ns.Where(npc) .. (npc.age > 0 and " (before update)" or "")
          .. (h.trains and ("  ·  trains " .. h.trains) or "")
          .. (h.ranks and ("  ·  " .. table.concat((function()
                local w = {} for _, r in ipairs(h.ranks) do w[#w + 1] = ns.RankWord(r) or r end return w end)(), ", ")) or "")
          .. (npc.k == "service" and "  ·  visited, no list yet" or "") .. "|r",
        tip = ns.DetailText(npc) }
    end
  end
  return data
end

local function RunSearch()
  local p = pages.search
  local q = p.box:GetText() or ""
  view.hidden, view.hiddenName = 0, nil
  if view.onlyNew then
    if q:match("^%s*$") then
      view.results = ns.Unvisited()
    else
      view.results = {}
      for _, h in ipairs(ns.Search(q)) do
        if h.seen then view.results[#view.results + 1] = h
        else
          -- keep count of what the checkbox hid, so an empty list can say why
          view.hidden = view.hidden + 1
          view.hiddenName = view.hiddenName or (h.npc and h.npc.n)
        end
      end
    end
  else
    view.results = ns.Search(q)
  end
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
  p.checks = {
    K.Check(p, "Show NPC names in town", 16, -414, function() return ns.ScoutOn() end, function(v) ns.SetScoutFromUI(v) end),
    K.Check(p, "Only not visited", 250, -414, function() return view.onlyNew end, function(v) view.onlyNew = v; RunSearch() end),
  }
  FA.UI.Tip(p.checks[1], function() ns.ScoutTip(GameTooltip) end)
  FA.UI.Tip(p.checks[2], function()
    GameTooltip:AddLine("Only not visited")
    GameTooltip:AddLine("Lists crafting NPCs you've passed but never talked to, nearest first. Talk to each one to save what it sells or trains.", 1, 1, 1, true)
  end)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Search items, vendors, towns or a profession. Click a row for a waypoint. Hover a checkbox to see what it does.")
  Wheel(p, "searchOff", function() return #view.results - SEARCH_ROWS end)
end

local function RefreshSearchPage(p)
  local data = SearchData()
  view.searchOff = math.min(view.searchOff, math.max(0, #data - SEARCH_ROWS))
  Fill(p.rows, data, view.searchOff)
  for _, c in ipairs(p.checks) do c:Sync() end
  local v, t = Counts()
  local q = p.box:GetText() or ""
  local hid = view.hidden or 0
  if view.onlyNew and hid > 0 and #data == 0 then
    -- the search found someone, the checkbox hid them: say so instead of "nobody"
    p.status:SetText(YELLOW .. (hid == 1 and ((view.hiddenName or "1 NPC") .. " matches, but you've already visited.")
      or (hid .. " NPCs match, but you've already visited them.")) .. " Untick 'Only not visited' to see.|r")
  elseif view.onlyNew and hid > 0 then
    p.status:SetText(("%d not visited yet  " .. GRAY .. "(%d visited hidden. Untick 'Only not visited' to see all.)|r"):format(#data, hid))
  elseif view.onlyNew and q ~= "" and #data == 0 then
    p.status:SetText(GRAY .. "Nothing matches among the NPCs you've met or passed.|r")
  elseif view.onlyNew then
    p.status:SetText(#data == 0 and (GRAY .. "Nobody left to visit. Turn on 'Show NPC names in town' and ride through a town.|r")
      or ("%d crafting NPC%s you've passed but not talked to, nearest first"):format(#data, #data == 1 and "" or "s"))
  elseif v + t == 0 then
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
-- Grouped by town, with a Zone picker and a Trade picker so the list stays short.
local LIST_ROWS = 14

-- Which tradeskills an NPC is for, read from their title. Order is the picker's order.
local TRADES = {
  { "Alchemy", { "alchem", "herbalis" } },
  { "Blacksmithing", { "blacksmith", "armorsmith", "weaponsmith" } },
  { "Cooking", { "cook", "chef", "butcher" } },
  { "Enchanting", { "enchant" } },
  { "Engineering", { "engineer", "tinker" } },
  { "First Aid", { "first aid", "medic", "physician", "bandage" } },
  { "Fishing", { "fish", "tackle" } },
  { "Herbalism", { "herbalis" } },
  { "Leatherworking", { "leather", "tanner" } },
  { "Mining", { "mining", "miner" } },
  { "Skinning", { "skinn" } },
  { "Tailoring", { "tailor", "fabric", "cloth" } },
}
local GOODS = "Trade & general goods" -- supply vendors who sell to every trade (thread, vials, salt, spices)
local OTHER = "Other"

local function TradesOf(npc)
  local t = (npc.t or ""):lower()
  local out = {}
  for _, tr in ipairs(TRADES) do
    for _, w in ipairs(tr[2]) do if t:find(w, 1, true) then out[tr[1]] = true; break end end
  end
  if not next(out) then
    if t:find("suppl", 1, true) or t:find("goods", 1, true) or t:find("sundries", 1, true) or t:find("reagent", 1, true)
      or t:find("provision", 1, true) or t:find("import", 1, true) or t:find("wares", 1, true) then
      out[GOODS] = true
    else
      out[OTHER] = true
    end
  end
  return out
end

-- "crafting" (default) hides innkeepers, class and riding trainers and the like; "all" shows everyone.
local function PassesTrade(npc, trade)
  if trade == "all" then return true end
  if ns.IsIgnored and ns.IsIgnored(npc.t) then return false end
  if trade == "crafting" or not trade then return true end
  return TradesOf(npc)[trade] == true
end

local function ListFilters()
  local st = S()
  return st.listZone or "all", st.listTrade or "crafting"
end

local function ListData()
  local zone, trade = ListFilters()
  local here = GetRealZoneText and GetRealZoneText()
  if zone == "here" then zone = here or "all" end
  local list = {}
  for _, npc in ipairs(ns.Contacts()) do
    if (zone == "all" or npc.z == zone) and PassesTrade(npc, trade) then list[#list + 1] = npc end
  end
  table.sort(list, function(a, b)
    if (a.z or "") ~= (b.z or "") then return (a.z or "") < (b.z or "") end
    if ns.Where(a) ~= ns.Where(b) then return ns.Where(a) < ns.Where(b) end
    return a.n < b.n
  end)
  -- count per town for the headers
  local per = {}
  for _, npc in ipairs(list) do local g = (npc.z or "?") .. "|" .. ns.Where(npc); per[g] = (per[g] or 0) + 1 end
  view.collapsed = view.collapsed or {}
  local data, lastGroup = {}, nil
  for _, npc in ipairs(list) do
    local g = (npc.z or "?") .. "|" .. ns.Where(npc)
    if g ~= lastGroup then
      lastGroup = g
      local shut = view.collapsed[g]
      local town, z = ns.Where(npc), npc.z
      data[#data + 1] = { header = g, noIcon = true,
        left = GOLD .. (shut and "+ " or "- ") .. town .. "|r" .. ((z and z ~= town) and (GRAY .. "  " .. z .. "|r") or ""),
        right = GRAY .. per[g] .. (shut and "  (click to open)" or "") .. "|r" }
    end
    if not view.collapsed[g] then
      local what = (npc.k == "service" and "visited, no list yet")
        or (npc.k == "trainer" and ("%d skills"):format(#npc.items)) or ("%d items"):format(#npc.items)
      local status = (npc.age >= ns.HIDE_AFTER) and "  ·  |cffff4040hidden|r" or ""
      local name = (npc.age > 0 and GRAY or "") .. npc.n .. (npc.age > 0 and "|r" or "")
      data[#data + 1] = { icon = npc.k == "trainer" and 136235 or 133784, npc = npc, tipTitle = npc.n,
        left = name .. (npc.t and (GRAY .. " <" .. npc.t .. ">|r") or ""),
        right = GRAY .. what .. "|r" .. status,
        tip = ns.DetailText(npc) .. (npc.age > 0 and "\n|cffff9020Not seen since a game update.|r" or "")
          .. "\n|cff9d9d9dRight-click twice to forget this contact.|r" }
    end
  end
  return data, #list
end

-- A button that opens a small list of choices under it (no Blizzard dropdown needed).
local openMenu
local function Picker(p, x, w, label, options, get, set)
  local b = Button(p, "", w, nil)
  b:SetPoint("TOPLEFT", x, -2)
  local menu = CreateFrame("Frame", nil, p)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2) -- same width as the button, so it never pokes out of the window
  local edge = menu:CreateTexture(nil, "BACKGROUND"); edge:SetAllPoints(); edge:SetColorTexture(0.45, 0.38, 0.2, 1)
  local bg = menu:CreateTexture(nil, "BORDER"); bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
  bg:SetColorTexture(0.06, 0.06, 0.06, 1)
  menu:EnableMouse(true)
  menu:Hide()
  menu.items = {}
  local function Rebuild()
    local opts = options()
    for i, o in ipairs(opts) do
      local it = menu.items[i]
      if not it then
        it = CreateFrame("Button", nil, menu)
        it:SetSize(w - 8, 18)
        it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
        it:SetHighlightTexture(FA.UI.HIGHLIGHT, "ADD")
        it.text = Text(it, "GameFontHighlightSmall", "LEFT", 4, 0, it, "LEFT"); it.text:SetWidth(w - 16); it.text:SetWordWrap(false)
        menu.items[i] = it
      end
      it.text:SetText((o.value == get() and GOLD or "") .. o.text .. (o.value == get() and "|r" or ""))
      it:SetScript("OnClick", function() set(o.value); menu:Hide() end)
      it:Show()
    end
    for i = #opts + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetSize(w, #opts * 18 + 8)
  end
  b:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide(); return end
    if openMenu and openMenu ~= menu then openMenu:Hide() end
    Rebuild(); menu:Show(); openMenu = menu
  end)
  p:HookScript("OnHide", function() menu:Hide() end)
  b.menu = menu
  b.Sync = function()
    local cur, text = get(), nil
    for _, o in ipairs(options()) do if o.value == cur then text = o.short or o.text end end
    -- the pick can drop out of the list when the other picker narrows it; still name it
    text = text or ({ here = "Where I am", crafting = "All crafting", [GOODS] = "Trade goods" })[cur]
      or (cur == "all" and (label == "Zone" and "All zones" or "Everyone")) or cur
    b:SetText(label .. ": " .. text .. "  v")
  end
  return b
end

-- Counts in each picker follow the other picker: with Trade = Leatherworking, the zone list counts leatherworkers.
local function ZoneOptions()
  local n, total = {}, 0
  local _, trade = ListFilters()
  for _, npc in ipairs(ns.Contacts()) do
    if npc.z and PassesTrade(npc, trade) then n[npc.z] = (n[npc.z] or 0) + 1; total = total + 1 end
  end
  local here = GetRealZoneText and GetRealZoneText()
  local opts = { { value = "all", text = "All zones (" .. total .. ")", short = "All zones" } }
  if here and n[here] then opts[#opts + 1] = { value = "here", text = "Where I am (" .. here .. ")", short = "Where I am" } end
  local zs = {}
  for z in pairs(n) do zs[#zs + 1] = z end
  table.sort(zs)
  for _, z in ipairs(zs) do opts[#opts + 1] = { value = z, text = z .. " (" .. n[z] .. ")", short = z } end
  return opts
end

local function TradeOptions()
  local n, crafting, everyone = {}, 0, 0
  local zone = ListFilters()
  if zone == "here" then zone = (GetRealZoneText and GetRealZoneText()) or "all" end
  for _, npc in ipairs(ns.Contacts()) do
    local inZone = zone == "all" or npc.z == zone
    if inZone then everyone = everyone + 1 end
    if inZone and not (ns.IsIgnored and ns.IsIgnored(npc.t)) then
      crafting = crafting + 1
      for tr in pairs(TradesOf(npc)) do n[tr] = (n[tr] or 0) + 1 end
    end
  end
  local opts = { { value = "crafting", text = "All crafting (" .. crafting .. ")", short = "All crafting" } }
  for _, tr in ipairs(TRADES) do
    if n[tr[1]] then opts[#opts + 1] = { value = tr[1], text = tr[1] .. " (" .. n[tr[1]] .. ")", short = tr[1] } end
  end
  if n[GOODS] then opts[#opts + 1] = { value = GOODS, text = GOODS .. " (" .. n[GOODS] .. ")", short = "Trade goods" } end
  if n[OTHER] then opts[#opts + 1] = { value = OTHER, text = OTHER .. " (" .. n[OTHER] .. ")", short = OTHER } end
  opts[#opts + 1] = { value = "all", text = "Everyone, incl. innkeepers (" .. everyone .. ")", short = "Everyone" }
  return opts
end

local function BuildListPage(p)
  p.zonePick = Picker(p, 16, 210, "Zone", ZoneOptions,
    function() return (ListFilters()) end, function(v) S().listZone = v; view.listOff = 0; ns.OnChange() end)
  p.tradePick = Picker(p, 234, 220, "Trade", TradeOptions,
    function() local _, t = ListFilters(); return t end, function(v) S().listTrade = v; view.listOff = 0; ns.OnChange() end)
  p.rows = MakeRows(p, LIST_ROWS, -32, false)
  -- town header: click to fold. NPC row: left-click waypoint, right-click twice (within 3 seconds) to forget.
  for _, r in ipairs(p.rows) do
    r:SetScript("OnClick", function(self, button)
      local d = self.data
      if d and d.header then
        view.collapsed = view.collapsed or {}
        view.collapsed[d.header] = not view.collapsed[d.header] or nil
        ns.OnChange()
        return
      end
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
  p.header = Text(p, "GameFontDisableSmall", "TOPLEFT", 20, -32 - LIST_ROWS * 24 - 4); p.header:SetWidth(430)
  p.checks = {
    Check(p, "Show 'Sold by' on item tooltips", 16, -420,
      function() return S().tooltips ~= false end, function(v) S().tooltips = v end),
  }
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Click a town to fold it  ·  Click an NPC: waypoint  ·  Right-click twice: forget")
  Wheel(p, "listOff", function() return #ListData() - LIST_ROWS end)
end

local function RefreshListPage(p)
  local data, shown = ListData()
  local total, old = #ns.Contacts(), 0
  for _, npc in ipairs(ns.Contacts()) do if npc.age > 0 then old = old + 1 end end
  p.zonePick.Sync(); p.tradePick.Sync()
  p.header:SetText(("Showing %d of %d contacts"):format(shown, total)
    .. (old > 0 and "  ·  grey name = not seen since a game update" or ""))
  view.listOff = math.min(view.listOff, math.max(0, #data - LIST_ROWS))
  Fill(p.rows, data, view.listOff)
  if total == 0 then p.empty:SetText("No contacts yet.\nTalk to a crafting vendor or profession trainer.")
  elseif shown == 0 then p.empty:SetText("Nobody here with these filters.\nSet Zone to All zones or Trade to All crafting.")
  else p.empty:SetText("") end
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
