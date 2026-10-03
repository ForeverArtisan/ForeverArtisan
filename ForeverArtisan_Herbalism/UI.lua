-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Herbalism: window (/fa herb) with Herbalism / Progress / Gather log / Herb guide tabs
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

---------------------------------------------------------------- page 1: Herbalism
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
    Check(p, "Remind me when Find Herbs is off", 16, -360,
      function() return S().reminder end, function(v) S().reminder = v; if v then ns.CheckFindHerbs(true) end end),
    Check(p, "Show herb info on tooltips", 16, -386,
      function() return S().tooltips end, function(v) S().tooltips = v end),
    Check(p, "Chat message for every pick", 16, -412,
      function() return S().verbose end, function(v) S().verbose = v end),
  }
  -- Tauren only: shown when this character knows the spell
  p.cult = Check(p, "Cultivation reminders (ready, and on herb tooltips)", 16, -438,
    function() return S().cultivation ~= false end, function(v) S().cultivation = v end)
  p.checks[#p.checks + 1] = p.cult
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("/fa herb next  ·  /fa herb goal 20 Peacebloom  ·  /fa herb zones")
end

-- Find Herbs and the Cultivation countdown
local function RefreshFind(p)
  local fh = ns.FindHerbsOn()
  if not ns.Knows() then fh = "skip" end
  local cult = ns.CultivationStatus and ns.CultivationStatus()
  local sep = cult and ("  " .. GRAY .. "·|r  " .. cult) or ""
  if fh == true then p.find:SetText(GREEN .. "Find Herbs: on|r" .. sep)
  elseif fh == false then p.find:SetText(RED .. "Find Herbs: off|r  " .. GRAY .. (cult and "(minimap tracking button)|r" or "Turn it on from the tracking button on your minimap.|r") .. sep)
  elseif fh == "skip" then p.find:SetText(cult or "")
  else p.find:SetText(GRAY .. "Find Herbs: not learned|r" .. sep) end
  p.cult:SetShown(ns.KnowsCultivation and ns.KnowsCultivation() or false)
end

-- the parts of the first tab that change with time; everything else refreshes on change or zone change
function ns.RefreshSession(p)
  local s = ns.SessionInfo()
  if s.nodes > 0 then
    p.sess:SetText(("%d nodes  ·  %d herbs  ·  %d skill-up%s%s"):format(s.nodes, s.herbs, s.ups, s.ups == 1 and "" or "s",
      s.perHour and ("  ·  " .. GOLD .. s.perHour .. " herbs/hour|r") or ""))
    p.last:SetText(s.last and (GRAY .. "Last pick: |r" .. s.last) or "")
  else
    p.sess:SetText(GRAY .. "Nothing picked yet this session.|r")
    p.last:SetText("")
  end
end

local function RefreshMainPage(p)
  local i = ns.SkillInfo()
  if i.rank then
    p.skill:SetText(("Herbalism %d%s%s"):format(i.rank, i.max and (" / " .. i.max) or "",
      (i.mod and i.mod > 0) and (GREEN .. "  (+" .. i.mod .. ")|r") or ""))
    if i.capped then
      p.color:SetText(RED .. ("Capped at %d. Train the next rank at an Herbalism trainer to keep gaining skill.|r"):format(i.max))
    else
      local now = ns.PickNext()
      local top = now[1]
      p.color:SetText(top and ("Best skill-ups right now: " .. ns.COLOR_CODE[top.color] .. top.name .. "|r"
        .. (top.where and (GRAY .. "  (" .. top.where .. ")|r") or "")) or "")
    end
  else
    p.skill:SetText("Herbalism")
    p.color:SetText(GRAY .. "You haven't learned Herbalism on this character.|r")
  end

  RefreshFind(p)

  ns.RefreshSession(p)

  local z = ns.ZoneRec()
  p.zoneHead:SetText(("Logged here: %s  %s(%d nodes)|r"):format(ns.Place(z), GRAY, z.nodes))
  local list = {}
  for id, it in pairs(z.items) do
    local h = ns.herbById[id]
    local c = h and ns.HerbColor(h.req, ns.EffSkill()) or "unknown"
    list[#list + 1] = { id = id, icon = Icon(id), n = it.n,
      left = ns.COLOR_CODE[c] .. (it.name or ns.ItemName(id)) .. "|r",
      right = ("x%d  " .. GRAY .. "(%d nodes)|r"):format(it.n, it.hauls) }
  end
  table.sort(list, function(a, b) return a.n > b.n end)
  Fill(p.rows, list, 0)
  p.empty:SetText(#list == 0 and "Nothing logged in this spot yet." or "")
  for _, c in ipairs(p.checks) do c:Sync() end
end

---------------------------------------------------------------- page 2: Progress
local function BuildProgressPage(p)
  p.skillBar = K.SkillBar(p, -2, "Herbalism")
  p.rate = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -36); p.rate:SetWidth(430)

  Header(p, -54, "Pick next")
  Text(p, "GameFontDisableSmall", "TOPLEFT", 90, -56):SetText("herbs that still give skill-ups")
  p.nextRows = MakeRows(p, 6, -72, true)
  p.soon = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -222); p.soon:SetWidth(430)

  Header(p, -250, "Goals")
  Text(p, "GameFontHighlightSmall", "TOPLEFT", 300, -252):SetText("Amount")
  p.amount = K.NumberBox(p, 46, 20); p.amount:SetPoint("TOPLEFT", 350, -248)
  p.goalRows = MakeRows(p, GOAL_ROWS, -272, true, { goals = true })
  local gl = CreateFrame("Frame", nil, p); gl:SetPoint("TOPLEFT", 0, -272); gl:SetSize(470, GOAL_ROWS * 34)
  gl:SetFrameLevel(p:GetFrameLevel()); Wheel(gl, "goalOff", function() return #ns.GoalRows() - GOAL_ROWS end)
  p.gempty = Text(p, "GameFontDisable", "TOPLEFT", 20, -276); p.gempty:SetWidth(420)
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Goals count herbs picked since you logged in. Right-click any herb in the log or guide to add it.")
end

local function Amount()
  local p = pages.progress
  return (p and p.amount and tonumber(p.amount:GetText())) or 20
end
ns.GoalAmount = Amount

local function RefreshProgressPage(p)
  local i = ns.SkillInfo()
  if i.rank then
    p.skillBar:Set(i.rank, i.max, i.capped)
    if i.capped then
      p.rate:SetText(RED .. "You're capped. Train the next rank to keep going.|r")
    elseif i.npp and i.toCap then
      p.rate:SetText(("About %.1f nodes per point  ·  %d points to %d  ·  ~%d nodes"):format(i.npp, i.toCap, i.max, i.nodesToCap or 0))
    else
      p.rate:SetText(GRAY .. "Pick a few herbs and your pace shows here.|r")
    end
  else
    p.skillBar:Set(nil); p.rate:SetText(GRAY .. ((ForeverArtisan.ProfessionListLoaded and ForeverArtisan.ProfessionListLoaded())
      and "Any Herbalism trainer teaches it. Your log and guide still work." or "Can't read your Herbalism skill yet.") .. "|r")
  end
  if i.rank then p.rate:SetText(("%d nodes since your last skill-up  ·  "):format(i.sinceUp or 0) .. (p.rate:GetText() or "")) end

  local now, soon = ns.PickNext()
  local data = {}
  for _, h in ipairs(now) do
    data[#data + 1] = { id = h.id, icon = Icon(h.id),
      left = ns.COLOR_CODE[h.color] .. h.name .. "|r  " .. GRAY .. h.req .. "|r",
      right = h.where or (GRAY .. "not logged yet|r"),
      act = "Goal", onAct = function() ns.AddGoal(h.id, Amount(), h.name) end }
  end
  Fill(p.nextRows, data, 0)
  if #soon > 0 then
    local bits = {}
    for _, h in ipairs(soon) do bits[#bits + 1] = h.name .. " (" .. h.req .. ")" end
    p.soon:SetText(GRAY .. "Unlocks next: |r" .. table.concat(bits, ", "))
  else
    p.soon:SetText(#now == 0 and i.rank and (GRAY .. "Nothing left that gives skill-ups at your level.|r") or "")
  end

  local goals = K.GoalData(ns.GoalRows(), "Picked in: ")
  view.goalOff = math.min(view.goalOff, math.max(0, #goals - GOAL_ROWS))
  Fill(p.goalRows, goals, view.goalOff)
  p.gempty:SetText(#goals == 0 and "No goals yet. Click Goal on a herb above." or "")
end

---------------------------------------------------------------- page 3: Gather log
local LOG_ROWS = 14
local function LogData()
  local db, data = ns.DB(), {}
  if view.mode == "all" then
    local list = {}
    for key, z in pairs(db.zones) do if z.nodes > 0 then list[#list + 1] = { key = key, z = z } end end
    table.sort(list, function(a, b) return a.z.nodes > b.z.nodes end)
    for _, e in ipairs(list) do
      local kinds = 0
      for _ in pairs(e.z.items) do kinds = kinds + 1 end
      data[#data + 1] = { icon = 134215, left = ns.Place(e.z),
        right = ("%d nodes  ·  %d herb%s"):format(e.z.nodes, kinds, kinds == 1 and "" or "s"),
        spotKey = e.key, tipTitle = e.z.sub, tip = "Click to open this spot." }
    end
    return data, ("%d spots logged"):format(#data)
  end
  local z = view.key and db.zones[view.key] or ns.ZoneRec()
  local list = {}
  for id, it in pairs(z.items) do list[#list + 1] = { id = id, it = it } end
  table.sort(list, function(a, b) return a.it.n > b.it.n end)
  for _, e in ipairs(list) do
    local pct = z.nodes > 0 and math.floor(e.it.hauls * 100 / z.nodes + 0.5) or 0
    data[#data + 1] = { id = e.id, icon = Icon(e.id), name = e.it.name,
      left = e.it.name or ns.ItemName(e.id),
      right = ("x%d  ·  %d%% of nodes%s"):format(e.it.n, pct, e.it.minSkill and (GRAY .. "  ·  from " .. e.it.minSkill .. "|r") or ""),
      tip = "Right-click: add as a goal." }
  end
  return data, ("%s  ·  %d nodes"):format(ns.Place(z), z.nodes)
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
  help:SetText("Wheel: scroll  ·  Click a spot: open it  ·  Right-click a herb: goal")
  Wheel(p, "logOff", function() return #(LogData()) - LOG_ROWS end)
end

local function RefreshLogPage(p)
  local data, head = LogData()
  p.header:SetText(head)
  view.logOff = math.min(view.logOff, math.max(0, #data - LOG_ROWS))
  Fill(p.rows, data, view.logOff)
  p.empty:SetText(#data == 0 and "Nothing logged yet. Go pick something!" or "")
  p.tZone:SetEnabled(view.mode ~= "zone" or view.key ~= nil)
  p.tAll:SetEnabled(view.mode ~= "all")
end

---------------------------------------------------------------- page 4: Herb guide
local GUIDE_ROWS = 17
local function GuideData()
  local skill, data = ns.EffSkill(), {}
  for _, h in ipairs(ns.HERBS) do
    local c = ns.HerbColor(h[3], skill)
    local where = ns.ZoneText(h[1])
    data[#data + 1] = { id = h[1], icon = Icon(h[1]), name = h[2],
      left = ns.COLOR_CODE[c] .. h[2] .. "|r",
      right = GRAY .. h[3] .. "|r   " .. (where or (GRAY .. "not logged|r")),
      tip = (skill and (ns.COLOR_WORD[c] .. ".\n") or "") .. "Right-click: add as a goal." }
  end
  return data
end

local function BuildGuidePage(p)
  p.header = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -4); p.header:SetWidth(430)
  p.header:SetText("Every herb, the skill it needs, and where you've picked it. Colors are for your skill.")
  p.rows = MakeRows(p, GUIDE_ROWS, -24, false)
  for _, r in ipairs(p.rows) do
    r:SetScript("OnClick", function(self, button)
      local d = self.data
      if d and button == "RightButton" then ns.AddGoal(d.id, Amount(), d.name) end
    end)
  end
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("Classic skill levels. Forever may change some; your gather log shows what you actually saw.")
  Wheel(p, "guideOff", function() return #ns.HERBS - GUIDE_ROWS end)
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
  local order = { { "main", "Herbalism" }, { "progress", "Progress" }, { "log", "Gather log" }, { "guide", "Herb guide" } }
  f = K.Window({ name = "ForeverArtisanHerbalismFrame", title = "Herbalism", tabs = order, pages = pages, tabButtons = tabs, onTab = ShowTab })
  BuildMainPage(pages.main)
  BuildProgressPage(pages.progress)
  BuildLogPage(pages.log)
  BuildGuidePage(pages.guide)

  f:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t > 1 then
      self.t = 0
      if view.tab == "main" then
        -- a new spot redraws the whole tab; otherwise only the lines that change with time
        local spot = (GetRealZoneText() or "") .. "/" .. (GetSubZoneText() or "")
        if spot ~= view.spot then view.spot = spot; RefreshMainPage(pages.main)
        else ns.RefreshSession(pages.main); RefreshFind(pages.main) end
      end
    end
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
