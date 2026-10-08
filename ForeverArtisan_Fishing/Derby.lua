-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Fishing: derby countdown (from the in-game calendar) and the cast marker
local _, ns = ...
if not ns or not ns.DB then return end

local DERBY_MATCH = "fishing"          -- calendar titles containing this (case-insensitive)
local FALLBACK_WEEKDAY, FALLBACK_HOUR, FALLBACK_LEN = 1, 14, 2 * 3600   -- Sunday 2 PM, 2 hours (Classic)

---------------------------------------------------------------- time helpers (realm time)
local function NowTable()
  if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    local t = C_DateAndTime.GetCurrentCalendarTime()
    if t then return t end
  end
  local h, m = GetGameTime()
  local d = date("*t")
  return { year = d.year, month = d.month, monthDay = d.day, hour = h, minute = m, weekday = d.wday }
end
local function Epoch(t)
  return time({ year = t.year, month = t.month, day = t.monthDay or t.day, hour = t.hour or 0, min = t.minute or 0, sec = 0 })
end
local function NowEpoch()
  local t = NowTable()
  return Epoch(t) + (date("*t").sec or 0)
end

---------------------------------------------------------------- find the derby
local derby = { source = "none" }      -- start, stop (epoch, realm time), title, rules, source
ns.derby = derby

local function FromCalendar()
  if not (C_Calendar and C_Calendar.GetNumDayEvents and C_Calendar.GetDayEvent) then return false end
  if CalendarFrame and CalendarFrame:IsShown() then return false end  -- don't move the calendar under the player
  local now = NowTable()
  local nowE = NowEpoch()
  -- Never call SetAbsMonth here: it fires CALENDAR_UPDATE_EVENT_LIST, which called us again (stack overflow).
  -- Work out how far the calendar's current month is from today's month instead.
  local cur = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
  local base = 0
  if cur and cur.year and cur.month then base = (now.year - cur.year) * 12 + (now.month - cur.month) end
  for offset = base, base + 1 do
    local info = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(offset)
    local days = (info and info.numDays) or 31
    for day = (offset == base and now.monthDay or 1), days do
      local n = C_Calendar.GetNumDayEvents(offset, day) or 0
      for i = 1, n do
        local ev = C_Calendar.GetDayEvent(offset, day, i)
        if ev and ev.title and ev.title:lower():find(DERBY_MATCH) and ev.startTime and ev.sequenceType ~= "ONGOING" then
          local s = Epoch(ev.startTime)
          local e = ev.endTime and Epoch(ev.endTime) or (s + FALLBACK_LEN)
          if e <= s then e = s + FALLBACK_LEN end
          if e > nowE then
            derby.start, derby.stop, derby.title, derby.source = s, e, ev.title, "calendar"
            if C_Calendar.GetHolidayInfo then
              local ok, h = pcall(C_Calendar.GetHolidayInfo, offset, day, i)
              if ok and type(h) == "table" and h.description and h.description ~= "" then derby.rules = h.description end
            end
            return true
          end
        end
      end
    end
  end
  return false
end

local function FromSchedule()
  local now = NowTable()
  local nowE = NowEpoch()
  local todayStart = Epoch({ year = now.year, month = now.month, monthDay = now.monthDay, hour = FALLBACK_HOUR, minute = 0 })
  local daysAhead = ((FALLBACK_WEEKDAY - (now.weekday or 1)) % 7)
  local s = todayStart + daysAhead * 86400
  if s + FALLBACK_LEN <= nowE then s = s + 7 * 86400 end
  derby.start, derby.stop, derby.title, derby.source = s, s + FALLBACK_LEN, "Stranglethorn Fishing Extravaganza", "schedule"
end

local refreshing = false
function ns.RefreshDerby()
  if refreshing then return derby end          -- calendar calls can fire events that bring us back here
  refreshing = true
  local ok, found = pcall(FromCalendar)
  refreshing = false
  if not (ok and found) then
    if derby.source ~= "calendar" or not derby.stop or derby.stop <= NowEpoch() then FromSchedule() end
  end
  return derby
end

-- state: "live", "soon" (within 1h), "later"; seconds until start or until end
function ns.DerbyStatus()
  if not derby.start or (derby.stop and derby.stop <= NowEpoch()) then ns.RefreshDerby() end
  local now = NowEpoch()
  if now >= derby.start and now < derby.stop then return "live", derby.stop - now end
  local left = derby.start - now
  return (left <= 3600) and "soon" or "later", left
end

function ns.DerbyClock(sec)
  sec = math.max(0, math.floor(sec or 0))
  local d, h, m, s = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60), sec % 60
  if d > 0 then return ("%dd %dh %dm"):format(d, h, m) end
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  return ("%dm %02ds"):format(m, s)
end

function ns.DerbyWhen()
  if not derby.start then return "" end
  local t = date("*t", derby.start)
  local hr = t.hour % 12; if hr == 0 then hr = 12 end
  return ("%s %d/%d at %d:%02d %s (server time)"):format(
    ({ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" })[t.wday],
    t.month, t.day, hr, t.min, t.hour < 12 and "AM" or "PM")
end

---------------------------------------------------------------- derby catches
local function DerbyKey() return derby.start and date("%Y-%m-%d", derby.start) end

function ns.OnDerbyCatch(entry)
  if ns.DerbyStatus() ~= "live" then return end
  local db = ns.DB()
  db.derbies = db.derbies or {}
  local key = DerbyKey()
  local d = db.derbies[key] or { catches = 0, items = {}, title = derby.title }
  db.derbies[key] = d
  d.catches = d.catches + 1
  for _, it in ipairs(entry.items or {}) do
    local r = d.items[it.id] or { n = 0, name = ns.ItemName(it.id) }
    r.n = r.n + (it.n or 1)
    d.items[it.id] = r
  end
end

function ns.DerbyCatches()
  local db = ns.DB()
  local d = db.derbies and db.derbies[DerbyKey() or ""]
  local list = {}
  if d then
    for id, r in pairs(d.items) do list[#list + 1] = { id = id, name = r.name, n = r.n } end
    table.sort(list, function(a, b) return a.n > b.n end)
  end
  return list, d and d.catches or 0
end

---------------------------------------------------------------- alerts
local warned = {}
local function Tick()
  if not ns.DB() then return end
  local state, sec = ns.DerbyStatus()
  local key = DerbyKey() or "?"
  if state == "soon" and sec <= 600 and not warned[key .. "soon"] then
    warned[key .. "soon"] = true
    ns.say(("|cffd4a94e%s starts in %s.|r"):format(derby.title or "The derby", ns.DerbyClock(sec)))
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
  elseif state == "live" and not warned[key .. "live"] then
    warned[key .. "live"] = true
    ns.say(("|cff40ff40%s is live! Ends in %s.|r"):format(derby.title or "The derby", ns.DerbyClock(sec)))
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
  end
end

---------------------------------------------------------------- cast marker
-- Your bobber lands the same distance straight ahead every cast. With the camera in the same
-- spot behind you, it lands on the same spot on your screen. We remember that spot.
local MARK_VIEW = 5   -- camera view slot we save/restore (views 2-5 are user slots)
local marker

local function BuildMarker()
  marker = CreateFrame("Frame", "ForeverArtisanFishingCastMarker", UIParent)
  marker:SetSize(60, 60)
  marker:SetFrameStrata("HIGH")
  marker:EnableMouse(false)
  -- big crosshair drawn from plain color bars, with a dark outline so it shows on bright water
  marker.bars = {}
  local function bar(w, h, x, y)
    local o = marker:CreateTexture(nil, "ARTWORK")
    o:SetSize(w + 2, h + 2); o:SetPoint("CENTER", x, y); o:SetColorTexture(0, 0, 0, 0.8)
    local t = marker:CreateTexture(nil, "OVERLAY")
    t:SetSize(w, h); t:SetPoint("CENTER", x, y)
    marker.bars[#marker.bars + 1] = t
  end
  bar(16, 3, -16, 0); bar(16, 3, 16, 0); bar(3, 16, 0, 16); bar(3, 16, 0, -16); bar(4, 4, 0, 0)
  for _, b in ipairs(marker.bars) do b:SetColorTexture(1, 0.82, 0, 0.95) end
  -- ring of dots = how far your casts actually scatter (grows as you add casts)
  marker.ring = {}
  for i = 1, 16 do
    local d = marker:CreateTexture(nil, "OVERLAY")
    d:SetSize(4, 4); d:SetColorTexture(1, 0.82, 0, 0.8)
    marker.ring[i] = d
  end
  marker:Hide()
end

function ns.MarkerSet() local m = ns.DB().settings.marker; return m and m.x and m.y end

local testUntil = 0
-- /fa fish marker test: show the crosshair in the middle of the screen for 5 seconds
function ns.TestMarker()
  if not marker then return end
  testUntil = GetTime() + 5
  marker:ClearAllPoints(); marker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  for _, b in ipairs(marker.bars) do b:SetColorTexture(1, 0.82, 0, 0.95) end
  marker:Show()
  ns.say("Showing the cast marker in the middle of your screen for 5 seconds.")
end

function ns.MarkerStatus()
  local s = ns.DB().settings
  local m = s.marker
  ns.say(("Marker: %s | Show marker: %s | Pole equipped: %s | On screen now: %s"):format(
    (m and m.x) and ("set at %d%% across, %d%% up from %d cast(s)"):format(m.x * 100, m.y * 100, m.samples and #m.samples or 1) or "NOT SET (cast, then Set marker and click your bobber)",
    s.showMarker and "on" or "off", ns.PoleEquipped() and "yes" or "no",
    (marker and marker:IsShown()) and "yes" or "no"))
end

function ns.UpdateMarker()
  if not marker then return end
  if GetTime() < testUntil then return end
  local s = ns.DB().settings
  local m = s.marker
  if s.showMarker and m and m.x and ns.PoleEquipped() then
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", UIParent, "BOTTOMLEFT", m.x * w, m.y * h)
    local r = m.spread and m.spread > 0 and math.max(24, math.min(220, m.spread * w)) or nil
    for i, d in ipairs(marker.ring) do
      if r then
        local a = (i - 1) / #marker.ring * 2 * math.pi
        d:ClearAllPoints(); d:SetPoint("CENTER", marker, "CENTER", math.cos(a) * r, math.sin(a) * r); d:Show()
      else
        d:Hide()
      end
    end
    -- red when the camera zoom no longer matches the calibration
    local z = GetCameraZoom and GetCameraZoom()
    local off = z and m.zoom and math.abs(z - m.zoom) > 0.75
    for _, b in ipairs(marker.bars) do
      if off then b:SetColorTexture(1, 0.25, 0.25, 0.95) else b:SetColorTexture(1, 0.82, 0, 0.95) end
    end
    for _, d in ipairs(marker.ring) do
      if off then d:SetColorTexture(1, 0.25, 0.25, 0.8) else d:SetColorTexture(1, 0.82, 0, 0.8) end
    end
    marker.off = off
    marker:Show()
  else
    marker:Hide()
  end
end

function ns.SnapCamera()
  local m = ns.DB().settings.marker
  if not (m and m.view) then ns.say("Set the cast marker first; that also saves the camera view.") return end
  if SetView then pcall(SetView, MARK_VIEW); pcall(SetView, MARK_VIEW) end   -- twice = no camera glide
end
ForeverArtisanFishingSnapCamera = ns.SnapCamera   -- for the key binding
BINDING_NAME_FOREVERARTISAN_FISHING_SNAPCAMERA = "ForeverArtisan: snap to fishing camera"

-- calibration: dim the screen a little and wait for one click on the bobber
local cal
function ns.CalibrateMarker(add)
  if InCombatLockdown() then return end
  if add and not (ns.DB().settings.marker and ns.DB().settings.marker.samples) then add = false end
  if not cal then
    cal = CreateFrame("Button", "ForeverArtisanFishingMarkerCalibrate", UIParent)
    cal:SetAllPoints(UIParent)
    cal:SetFrameStrata("FULLSCREEN_DIALOG")
    local bg = cal:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.15)
    local t = cal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", 0, -120)
    t:SetText("Move the + onto your bobber and left-click")
    local t2 = cal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t2:SetPoint("TOP", t, "BOTTOM", 0, -8)
    t2:SetText("The gold + follows your mouse; it's saved exactly where you click. Right-click or Esc cancels.")
    -- live preview: the marker sits under the cursor while you aim, so you can see what gets saved
    local function CursorFrac()
      local x, y = GetCursorPosition()
      local sc = UIParent:GetEffectiveScale()
      return (x / sc) / UIParent:GetWidth(), (y / sc) / UIParent:GetHeight()
    end
    cal.CursorFrac = CursorFrac
    cal:SetScript("OnUpdate", function()
      if not marker then return end
      local fx, fy = CursorFrac()
      marker:ClearAllPoints()
      marker:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fx * UIParent:GetWidth(), fy * UIParent:GetHeight())
      for _, b in ipairs(marker.bars) do b:SetColorTexture(1, 0.82, 0, 0.95) end
      marker:SetFrameStrata("TOOLTIP")
      marker:Show()
    end)
    cal:SetScript("OnHide", function()
      if marker then marker:SetFrameStrata("HIGH") end
      if cal.hidWindow and ForeverArtisanFishingFrame then ForeverArtisanFishingFrame:Show(); cal.hidWindow = nil end
      ns.UpdateMarker()
    end)
    cal:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cal:EnableKeyboard(true)
    cal:SetScript("OnKeyDown", function(self, key)
      if key == "ESCAPE" then self:Hide() end
      if self.SetPropagateKeyboardInput then pcall(self.SetPropagateKeyboardInput, self, key ~= "ESCAPE") end
    end)
    cal:SetScript("OnClick", function(self, button)
      if button ~= "LeftButton" then self:Hide(); return end
      local fx, fy = self.CursorFrac()
      local s = ns.DB().settings
      local m = s.marker
      if self.fresh or not (m and m.samples) then
        m = { samples = {}, zoom = GetCameraZoom and GetCameraZoom() or nil }
        if SaveView then
          local ok = pcall(SaveView, MARK_VIEW)
          m.view = ok and MARK_VIEW or nil
        end
        s.marker = m
      end
      m.samples[#m.samples + 1] = { fx, fy }
      if #m.samples > 12 then table.remove(m.samples, 1) end
      -- marker = average landing spot; ring = how far casts wander from it
      local sx, sy = 0, 0
      for _, p in ipairs(m.samples) do sx, sy = sx + p[1], sy + p[2] end
      m.x, m.y = sx / #m.samples, sy / #m.samples
      local aspect = UIParent:GetHeight() / UIParent:GetWidth()
      local far = 0
      for _, p in ipairs(m.samples) do
        local dx, dy = p[1] - m.x, (p[2] - m.y) * aspect
        far = math.max(far, math.sqrt(dx * dx + dy * dy))
      end
      m.spread = (#m.samples > 1) and far or nil
      s.showMarker = true
      if #m.samples == 1 then
        ns.say("Marker set from 1 cast. Casts scatter a little, so cast a few more times and click Add cast after each; " ..
          "the + moves to your average spot and a ring shows your scatter.")
      else
        ns.say(("Added cast %d. The + is your average landing spot; the ring shows how far casts wander."):format(#m.samples))
      end
      self:Hide()
      if ns.OnChange then ns.OnChange() end
    end)
  end
  -- get the addon window out of the way so it can't cover the bobber
  if ForeverArtisanFishingFrame and ForeverArtisanFishingFrame:IsShown() then ForeverArtisanFishingFrame:Hide(); cal.hidWindow = true end
  cal.fresh = not add
  cal:Show()
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "CALENDAR_UPDATE_EVENT_LIST", "PLAYER_EQUIPMENT_CHANGED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e)
  if not ns.DB() then return end
  if e == "PLAYER_LOGIN" then
    BuildMarker()
    if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
    ns.RefreshDerby()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(15, Tick) end
  elseif e == "CALENDAR_UPDATE_EVENT_LIST" then
    -- the calendar sends this in bursts; look once, a moment later
    if not ev.pending and C_Timer then
      ev.pending = true
      C_Timer.After(1, function() ev.pending = false; ns.RefreshDerby() end)
    end
  end
  ns.UpdateMarker()
end)
-- keep the marker's zoom warning current
local t = 0
ev:SetScript("OnUpdate", function(_, el)
  t = t + el
  if t > 1 then t = 0; if marker and marker:IsShown() then ns.UpdateMarker() end end
end)

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(ev)
