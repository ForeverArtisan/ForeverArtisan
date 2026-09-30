-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Skinning: window (/fa skin) with Skinning / Progress / Skinning log / Level guide tabs
local _, ns = ...
if not ns or not ns.DB then return end

local ROW_H, W, H = 24, 470, 578
local FA = ForeverArtisan
local GOLD, GRAY, GREEN, YELLOW, RED = FA.GOLD, FA.GRAY, FA.GREEN, FA.YELLOW, FA.RED


local f
local pages, tabs = {}, {}
local GOAL_ROWS = 5
local view = { tab = "main", goalOff = 0, mode = "zone", key = nil, logOff = 0, guideOff = 0 }

---------------------------------------------------------------- shared style kit (ForeverArtisan Core)
local K = FA.UI.Kit(ns, view)
local Text, Button, Check, Icon, Header = K.Text, K.Button, K.Check, K.Icon, K.Header
local MakeRows, Fill, Wheel = K.MakeRows, K.Fill, K.Wheel
local function S() return ns.DB().settings end

local function Range(a, b) return (a and b and a ~= b) and (a .. "-" .. b) or tostring(a or b or "?") end

---------------------------------------------------------------- page 1: Skinning
local function BuildMainPage(p)
  p.skill = Text(p, "GameFontNormalLarge", "TOPLEFT", 18, -6)
  p.color = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -30); p.color:SetWidth(430)
  p.find = Text(p, "GameFontHighlight", "TOPLEFT", 18, -56); p.find:SetWidth(430)

  Header(p, -88, "This session")
  p.sess = Text(p, "GameFontHighlight", "TOPLEFT", 18, -108); p.sess:SetWidth(430)
  p.last = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -128); p.last:SetWidth(430)

  p.zoneHead = Text(p, "GameFontNormal", "TOPLEFT", 16, -158)
  p.rows = MakeRows(p, 7, -178, false)
  p.empty = Text(p, "GameFontDisable", "TOPLEFT", 20, -182); p.empty:SetWidth(420)

  p.checks = {
    Check(p, "Remind me when my Skinning Knife is missing", 16, -360,
      function() return S().reminder end, function(v) S().reminder = v; if v then ns.CheckReminders(true) end end),
    Check(p, "Show skinning info on tooltips (beasts and leather)", 16, -386,
      function() return S().tooltips end, function(v) S().tooltips = v end),
    Check(p, "Chat message for every skin", 16, -412,
      function() return S().verbose end, function(v) S().verbose = v end),
  }
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("/fa skin next  ·  /fa skin goal 20 Light Leather  ·  /fa skin zones")
end

local function RefreshMainPage(p)
  local i = ns.SkillInfo()
  if i.rank then
    p.skill:SetText(("Skinning %d%s%s"):format(i.rank, i.max and (" / " .. i.max) or "",
      (i.mod and i.mod > 0) and (GREEN .. "  (+" .. i.mod .. ")|r") or ""))
    if i.capped then
      p.color:SetText(RED .. ("Capped at %d. Train the next rank at a Skinning trainer to keep gaining skill.|r"):format(i.max))
    else
      local bands = ns.LevelBands(ns.EffSkill())
      local o = bands.orange or bands.yellow
      p.color:SetText(("You can skin up to level %d.%s"):format(ns.MaxLevelFor(ns.EffSkill()) or 0,
        o and ("  Best skill-ups: " .. ns.COLOR_CODE[bands.orange and "orange" or "yellow"] .. "levels " .. Range(o[1], o[2]) .. "|r") or ""))
    end
  else
    p.skill:SetText("Skinning")
    p.color:SetText(GRAY .. "You haven't learned Skinning on this character.|r")
  end

  local knife = ns.HasKnife()
  if not ns.Knows() then knife = nil end
  p.find:SetText((knife == true and (GREEN .. "Skinning Knife: yes|r")) or (knife == false and (RED .. "Skinning Knife: missing|r")) or "")

  local s = ns.SessionInfo()
  if s.nodes > 0 then
    p.sess:SetText(("%d skinned  ·  %d items  ·  %d skill-up%s%s"):format(s.nodes, s.items, s.ups, s.ups == 1 and "" or "s",
      s.perHour and ("  ·  " .. GOLD .. s.perHour .. " items/hour|r") or ""))
    p.last:SetText(s.last and (GRAY .. "Last skin: |r" .. s.last) or "")
  else
    p.sess:SetText(GRAY .. "Nothing skinned yet this session.|r")
    p.last:SetText("")
  end

  local z = ns.ZoneRec()
  p.zoneHead:SetText(("Logged here: %s  %s(%d skinned)|r"):format(ns.Place(z), GRAY, z.nodes))
  local list = {}
  for name, m in pairs(z.mobs or {}) do
    local c = ns.SkinColor(ns.ReqForLevel(m.maxL or m.minL), ns.EffSkill())
    list[#list + 1] = { icon = 132938, n = m.n + 100000,
      left = ns.COLOR_CODE[c] .. name .. "|r" .. GRAY .. "  level " .. Range(m.minL, m.maxL) .. "|r",
      right = ("%d skinned"):format(m.n), tipTitle = name, tip = ns.COLOR_WORD[c] }
  end
  for id, it in pairs(z.items) do
    list[#list + 1] = { id = id, icon = Icon(id), n = it.n,
      left = it.name or ns.ItemName(id), right = ("x%d"):format(it.n) }
  end
  table.sort(list, function(a, b) return a.n > b.n end)
  Fill(p.rows, list, 0)
  p.empty:SetText(#list == 0 and "Nothing logged in this spot yet." or "")
  for _, c in ipairs(p.checks) do c:Sync() end
end

---------------------------------------------------------------- page 2: Progress
local function BuildProgressPage(p)
  p.skillBar = K.SkillBar(p, -2, "Skinning")
  p.rate = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -36); p.rate:SetWidth(430)

  Header(p, -54, "Skin next")
  p.bands = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -74); p.bands:SetWidth(430); p.bands:SetSpacing(3)
  p.mobHead = Text(p, "GameFontDisableSmall", "TOPLEFT", 20, -126)
  p.nextRows = MakeRows(p, 4, -142, false)

  Header(p, -250, "Goals")
  Text(p, "GameFontHighlightSmall", "TOPLEFT", 300, -252):SetText("Amount")
  p.amount = K.NumberBox(p, 46, 20); p.amount:SetPoint("TOPLEFT", 350, -248)
  p.goalRows = MakeRows(p, GOAL_ROWS, -272, true, { goals = true })
  local gl = CreateFrame("Frame", nil, p); gl:SetPoint("TOPLEFT", 0, -272); gl:SetSize(470, GOAL_ROWS * 34)
  gl:SetFrameLevel(p:GetFrameLevel()); Wheel(gl, "goalOff", function() return #ns.GoalRows() - GOAL_ROWS end)
  p.gempty = Text(p, "GameFontDisable", "TOPLEFT", 20, -276); p.gempty:SetWidth(420)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Goals count items skinned since you logged in. Right-click any item in the log to add it.")
end

local function Amount()
  local p = pages.progress
  return (p and p.amount and tonumber(p.amount:GetText())) or 20
end

local function RefreshProgressPage(p)
  local i = ns.SkillInfo()
  if i.rank then
    p.skillBar:Set(i.rank, i.max, i.capped)
    if i.capped then
      p.rate:SetText(RED .. "You're capped. Train the next rank to keep going.|r")
    elseif i.npp and i.toCap then
      p.rate:SetText(("About %.1f skins per point  ·  %d points to %d  ·  ~%d skins"):format(i.npp, i.toCap, i.max, i.nodesToCap or 0))
    else
      p.rate:SetText(GRAY .. "Skin a few mobs and your pace shows here.|r")
    end
  else
    p.skillBar:Set(nil); p.rate:SetText(GRAY .. ((ForeverArtisan.ProfessionListLoaded and ForeverArtisan.ProfessionListLoaded())
      and "Any Skinning trainer teaches it. Your log and guide still work." or "Can't read your Skinning skill yet.") .. "|r")
  end
  if i.rank then p.rate:SetText(("%d skinned since your last skill-up  ·  "):format(i.sinceUp or 0) .. (p.rate:GetText() or "")) end

  local bands, mobs, skill = ns.PickNext()
  local lines = {}
  for _, c in ipairs({ "orange", "yellow", "green" }) do
    local b = bands[c]
    if b then lines[#lines + 1] = ns.COLOR_CODE[c] .. "Levels " .. Range(b[1], b[2]) .. "|r  " .. GRAY .. ns.COLOR_WORD[c] .. "|r" end
  end
  if skill then
    local nxt = (ns.MaxLevelFor(skill) or 0) + 1
    lines[#lines + 1] = GRAY .. ("Level %d mobs unlock at skill %d."):format(nxt, ns.ReqForLevel(nxt)) .. "|r"
  end
  p.bands:SetText(#lines > 0 and table.concat(lines, "\n") or "")
  p.mobHead:SetText(#mobs > 0 and "Mobs you've skinned that still give skill-ups:" or "Skin a few beasts and the ones worth farming show here.")
  local data = {}
  for _, m in ipairs(mobs) do
    data[#data + 1] = { icon = 132938,
      left = ns.COLOR_CODE[m.color] .. m.name .. "|r  " .. GRAY .. Range(m.minL, m.maxL) .. "|r",
      right = ns.Place(m), tipTitle = m.name, tip = ("Skinned %d times."):format(m.n) }
  end
  Fill(p.nextRows, data, 0)

  local goals = K.GoalData(ns.GoalRows(), "Skinned in: ")
  view.goalOff = math.min(view.goalOff, math.max(0, #goals - GOAL_ROWS))
  Fill(p.goalRows, goals, view.goalOff)
  p.gempty:SetText(#goals == 0 and "No goals yet. Right-click leather in the log or guide, or /fa skin goal 20 Light Leather." or "")
end

---------------------------------------------------------------- page 3: Skinning log
local LOG_ROWS = 14
local function LogData()
  local db, data = ns.DB(), {}
  if view.mode == "all" then
    local list = {}
    for key, z in pairs(db.zones) do if z.nodes > 0 then list[#list + 1] = { key = key, z = z } end end
    table.sort(list, function(a, b) return a.z.nodes > b.z.nodes end)
    for _, e in ipairs(list) do
      local kinds = 0
      for _ in pairs(e.z.mobs or {}) do kinds = kinds + 1 end
      data[#data + 1] = { icon = 134215, left = ns.Place(e.z),
        right = ("%d skinned  ·  %d mob type%s"):format(e.z.nodes, kinds, kinds == 1 and "" or "s"),
        spotKey = e.key, tipTitle = e.z.sub, tip = "Click to open this spot." }
    end
    return data, ("%d spots logged"):format(#data)
  end
  local z = view.key and db.zones[view.key] or ns.ZoneRec()
  local mobs, items = {}, {}
  for name, m in pairs(z.mobs or {}) do mobs[#mobs + 1] = { name = name, m = m } end
  table.sort(mobs, function(a, b) return a.m.n > b.m.n end)
  for _, e in ipairs(mobs) do
    local c = ns.SkinColor(ns.ReqForLevel(e.m.maxL or e.m.minL), ns.EffSkill())
    data[#data + 1] = { icon = 132938, left = ns.COLOR_CODE[c] .. e.name .. "|r" .. GRAY .. "  level " .. Range(e.m.minL, e.m.maxL) .. "|r",
      right = ("%d skinned"):format(e.m.n), tipTitle = e.name, tip = ns.COLOR_WORD[c] }
  end
  for id, it in pairs(z.items) do items[#items + 1] = { id = id, it = it } end
  table.sort(items, function(a, b) return a.it.n > b.it.n end)
  for _, e in ipairs(items) do
    local pct = z.nodes > 0 and math.floor(e.it.hauls * 100 / z.nodes + 0.5) or 0
    data[#data + 1] = { id = e.id, icon = Icon(e.id), name = e.it.name,
      left = e.it.name or ns.ItemName(e.id),
      right = ("x%d  ·  %d%% of skins"):format(e.it.n, pct),
      tip = "Right-click: add as a goal." }
  end
  return data, ("%s  ·  %d skinned"):format(ns.Place(z), z.nodes)
end

local function BuildLogPage(p)
  local tZone = Button(p, "This spot", 90, function() view.mode, view.key, view.logOff = "zone", nil, 0; ns.OnChange() end)
  tZone:SetPoint("TOPLEFT", 16, -2)
  local tAll = Button(p, "All spots", 90, function() view.mode, view.logOff = "all", 0; ns.OnChange() end)
  tAll:SetPoint("LEFT", tZone, "RIGHT", 6, 0)
  p.tZone, p.tAll = tZone, tAll
  p.header = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -32); p.header:SetWidth(430)
  p.rows = MakeRows(p, LOG_ROWS, -50, false)
  for _, r in ipairs(p.rows) do
    r:SetScript("OnClick", function(self, button)
      local d = self.data
      if not d then return end
      if button == "RightButton" and d.id then ns.AddGoal(d.id, Amount(), d.name)
      elseif d.spotKey then view.mode, view.key, view.logOff = "zone", d.spotKey, 0; ns.OnChange() end
    end)
  end
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
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(310)
  help:SetText("Wheel: scroll  ·  Click a spot: open it  ·  Right-click an item: goal")
  Wheel(p, "logOff", function() return #(LogData()) - LOG_ROWS end)
end

local function RefreshLogPage(p)
  local data, head = LogData()
  p.header:SetText(head)
  view.logOff = math.min(view.logOff, math.max(0, #data - LOG_ROWS))
  Fill(p.rows, data, view.logOff)
  p.empty:SetText(#data == 0 and "Nothing logged yet. Go skin something!" or "")
  p.tZone:SetEnabled(view.mode ~= "zone" or view.key ~= nil)
  p.tAll:SetEnabled(view.mode ~= "all")
end

---------------------------------------------------------------- page 4: Level guide
local GUIDE_ROWS = 17
local LEVELS = {}
for lvl = 5, 60, 5 do LEVELS[#LEVELS + 1] = lvl end

local function LeatherFor(lvl)
  local names = {}
  for _, l in ipairs(ns.LEATHER) do
    if lvl >= l[3] and lvl <= l[4] and not l[2]:find("Ruined") then names[#names + 1] = l[2] end
  end
  return table.concat(names, ", ")
end

local function GuideData()
  local skill, data = ns.EffSkill(), {}
  for _, lvl in ipairs(LEVELS) do
    local req = ns.ReqForLevel(lvl)
    local c = ns.SkinColor(req, skill)
    data[#data + 1] = { icon = 132938,
      left = ns.COLOR_CODE[c] .. "Level " .. lvl .. " mobs|r  " .. GRAY .. "skill " .. req .. "|r",
      right = LeatherFor(lvl), tipTitle = "Level " .. lvl .. " mobs",
      tip = "Needs Skinning " .. req .. "." .. (skill and ("\n" .. ns.COLOR_WORD[c] .. " for you.") or "") }
  end
  data[#data + 1] = { icon = 134215, left = GRAY .. "Leather and hides|r", right = "" }
  for _, l in ipairs(ns.LEATHER) do
    local where = ns.ZoneText(l[1])
    data[#data + 1] = { id = l[1], icon = Icon(l[1]), name = l[2], left = l[2],
      right = GRAY .. "levels " .. l[3] .. "-" .. l[4] .. "|r" .. (where and ("  " .. where) or ""),
      tip = "Right-click: add as a goal." }
  end
  return data
end

local function BuildGuidePage(p)
  p.header = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -4); p.header:SetWidth(430)
  p.header:SetText("Skill needed by mob level, and the leather each level usually drops. Colors are for your skill.")
  p.rows = MakeRows(p, GUIDE_ROWS, -24, false)
  for _, r in ipairs(p.rows) do
    r:SetScript("OnClick", function(self, button)
      local d = self.data
      if d and d.id and button == "RightButton" then ns.AddGoal(d.id, Amount(), d.name) end
    end)
  end
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Classic values. Forever may change some; your skinning log shows what you actually got.")
  Wheel(p, "guideOff", function() return #GuideData() - GUIDE_ROWS end)
end

local function RefreshGuidePage(p)
  local data = GuideData()
  view.guideOff = math.min(view.guideOff, math.max(0, #data - GUIDE_ROWS))
  Fill(p.rows, data, view.guideOff)
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
  local order = { { "main", "Skinning" }, { "progress", "Progress" }, { "log", "Skinning log" }, { "guide", "Level guide" } }
  f = K.Window({ name = "ForeverArtisanSkinningFrame", title = "Skinning", tabs = order, pages = pages, tabButtons = tabs, onTab = ShowTab })
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
