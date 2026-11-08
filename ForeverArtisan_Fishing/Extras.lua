-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Fishing: session stats (catches, skill-ups and gold per hour), day and night fish,
-- fishing pool alerts (with pool spots remembered per zone) and rare catch alerts.
local _, ns = ...
if not ns or not ns.DB then return end
local FA = ForeverArtisan
local GOLD, GRAY, GREEN = FA.GOLD or "|cffd4a94e", FA.GRAY or "|cff9d9d9d", FA.GREEN or "|cff40ff40"

local function S() local db = ns.DB(); return db and db.settings or {} end
-- pool and rare catch alerts: on unless turned off (Fishing tab checkbox)
function ns.AlertsOn() return S().alerts ~= false end

local function Info(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if f then return f(id) end
end
local function Instant(id)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if f then return f(id) end
end
local function Money(c) return FA.Money and FA.Money(c) or (tostring(c) .. "c") end
-- on the Master channel: while the pole is on, splashes are turned up to full, and an alert on the
-- sound effects channel gets lost in them
local function Sound(kind, fallback)
  local k = SOUNDKIT and SOUNDKIT[kind]
  pcall(PlaySound, k or fallback, "Master")
end

---------------------------------------------------------------- the alert banner
-- Its own banner, not the yellow "bobber out of reach" line: higher up, with an icon and its own color
-- (blue for a pool, the item's quality color for a rare catch), and casting again doesn't clear it.
local alertFrame
function ns.Alert(text, icon, r, g, b)
  if not alertFrame then
    alertFrame = CreateFrame("Frame", "ForeverArtisanFishingAlert", UIParent)
    alertFrame:SetSize(640, 44)
    alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 230)
    alertFrame:SetFrameStrata("HIGH")
    alertFrame:EnableMouse(false)
    alertFrame.text = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    alertFrame.text:SetPoint("CENTER", 18, 0)
    alertFrame.icon = alertFrame:CreateTexture(nil, "OVERLAY")
    alertFrame.icon:SetSize(36, 36)
    alertFrame.icon:SetPoint("RIGHT", alertFrame.text, "LEFT", -8, 0)
  end
  alertFrame.text:SetText(text)
  alertFrame.text:SetTextColor(r or 1, g or 1, b or 1)
  alertFrame.icon:SetTexture(icon or 136245)
  alertFrame:SetAlpha(1)
  alertFrame:Show()
  alertFrame.until_ = GetTime() + 6
  alertFrame:SetScript("OnUpdate", function(self)
    local left = self.until_ - GetTime()
    if left <= 0 then self:Hide(); self:SetScript("OnUpdate", nil)
    elseif left < 1.5 then self:SetAlpha(left / 1.5) end
  end)
end

---------------------------------------------------------------- session stats
-- what one of an item is worth to you: the Auction House after its 5% cut, or a vendor, whichever pays more
function ns.CatchValue(id)
  local ah = FA.AHPrice and FA.AHPrice(id)
  local vend = select(11, Info(id))
  local best = math.max(ah and math.floor(ah * 0.95) or 0, vend or 0)
  return best > 0 and best or nil
end

local function AddValue(entry)
  local ses = ns.session
  if not ses then return end
  ses.value = ses.value or 0
  ses.unpriced = ses.unpriced or 0
  ses.started = ses.started or GetTime()
  for _, it in ipairs((entry and entry.items) or {}) do
    local v = ns.CatchValue(it.id)
    if v then ses.value = ses.value + v * (it.n or 1) else ses.unpriced = ses.unpriced + (it.n or 1) end
  end
end

-- { catches, ups, value, unpriced, mins, perHour = { catches, ups, value } } (perHour after 5 minutes)
function ns.SessionStats()
  local ses = ns.session or {}
  local mins = ses.firstCatch and (GetTime() - ses.firstCatch) / 60 or 0
  local out = { catches = ses.catches or 0, ups = ses.ups or 0, value = ses.value or 0, unpriced = ses.unpriced or 0, mins = mins }
  if mins >= 5 then
    local h = mins / 60
    out.perHour = { catches = math.floor(out.catches / h + 0.5), ups = math.floor(out.ups / h + 0.5), value = math.floor(out.value / h) }
  end
  return out
end

function ns.SessionLine()
  local st = ns.SessionStats()
  if st.catches == 0 then return GRAY .. "This session: no catches yet.|r" end
  local worth = st.value > 0 and ("worth ~" .. Money(st.value)) or (GRAY .. "no prices yet|r")
  if st.perHour then
    return ("This session: %d catches, %s   %s(%d catches, %d skill-ups, ~%s an hour)|r"):format(
      st.catches, worth, GRAY, st.perHour.catches, st.perHour.ups, Money(st.perHour.value))
  end
  return ("This session: %d catches, %s   %s(per hour after 5 minutes)|r"):format(st.catches, worth, GRAY)
end

---------------------------------------------------------------- day and night fish
-- Some fish only bite at certain hours of game time (the clock on the minimap). Known ones from Classic,
-- the rest learned from your catch log: a fish only ever caught at night, in waters you've also fished by day.
local NIGHT_FROM, NIGHT_TO = 18, 6
local KNOWN_TIME = { [13759] = "night", [13760] = "day" } -- Raw Nightfin Snapper, Raw Sunscale Salmon
local function IsNight(h) return h >= NIGHT_FROM or h < NIGHT_TO end
local timeCache, cacheSize = {}, -1

local function LearnTimes()
  local raw = ns.DB() and ns.DB().raw or {}
  if #raw == cacheSize then return end
  cacheSize = #raw
  wipe(timeCache)
  local byItem, byZone = {}, {}
  for _, e in ipairs(raw) do
    local h = e.gt and tonumber(e.gt:match("^(%d+)"))
    if h then
      local zk = (e.zone or "?") .. "/" .. (e.sub or "?")
      local z = byZone[zk] or { night = 0, day = 0 }; byZone[zk] = z
      if IsNight(h) then z.night = z.night + 1 else z.day = z.day + 1 end
      for _, it in ipairs(e.items or {}) do
        local b = byItem[it.id] or { night = 0, day = 0, zones = {} }; byItem[it.id] = b
        if IsNight(h) then b.night = b.night + 1 else b.day = b.day + 1 end
        b.zones[zk] = true
      end
    end
  end
  for id, b in pairs(byItem) do
    local only = (b.day == 0 and b.night >= 6 and "night") or (b.night == 0 and b.day >= 6 and "day") or nil
    if only then
      -- only counts when you also fished those waters at the other time and never caught it then
      local other = 0
      for zk in pairs(b.zones) do other = other + (only == "night" and byZone[zk].day or byZone[zk].night) end
      if other >= 6 then timeCache[id] = only end
    end
  end
end

-- "night", "day" or nil; second value: true when it comes from your own log
function ns.FishTime(id)
  if KNOWN_TIME[id] then return KNOWN_TIME[id], false end
  LearnTimes()
  if timeCache[id] then return timeCache[id], true end
end

function ns.FishTimeTip(id)
  local t, learned = ns.FishTime(id)
  if not t then return nil end
  local h, m = GetGameTime()
  local now = ("%02d:%02d"):format(h, m)
  local open = (t == "night") == IsNight(h)
  return ("Bites at %s only (about %s, game time)%s. Now %s: %s"):format(t,
    t == "night" and "18:00 to 06:00" or "06:00 to 18:00", learned and ", from your catch log" or "", now,
    open and (GREEN .. "biting|r") or (GRAY .. "come back " .. (t == "night" and "after 18:00" or "after 06:00") .. "|r"))
end

---------------------------------------------------------------- pool alerts
-- Fishing pools (schools, wreckage, oil spills) are world objects. When one is in view (the game's soft
-- target picks it up while the pole is on, or you mouse over it) you hear a ping and see its name, once a
-- minute per pool; its spot is remembered for the zone.
local POOL_PATTERNS = { "school$", "swarm$", "wreckage$", "debris$", "oil spill$", "elemental water$", "^school of " }
function ns.IsPoolName(name)
  if type(name) ~= "string" or name == "" then return false end
  local l = name:lower()
  for _, p in ipairs(POOL_PATTERNS) do if l:find(p) then return true end end
  return false
end

local lastPoolAlert = {}
function ns.SeenPool(name)
  if not ns.IsPoolName(name) or (FA.IsSecret and FA.IsSecret(name)) then return end
  local db = ns.DB(); if not db then return end
  local zone, sub, _, x, y = ns.Where()
  local key = (zone or "?") .. " / " .. (sub or "?")
  db.pools = db.pools or {}
  local zp = db.pools[key] or {}; db.pools[key] = zp
  local list = zp[name] or {}; zp[name] = list
  if x and y then
    local near
    for _, s in ipairs(list) do if math.abs(s.x - x) < 1.5 and math.abs(s.y - y) < 1.5 then near = s end end
    if near then near.n = (near.n or 1) + 1; near.t = time()
    elseif #list < 20 then list[#list + 1] = { x = x, y = y, n = 1, t = time() } end
  end
  local now = GetTime()
  if ns.AlertsOn() and now - (lastPoolAlert[name] or -1000) > 60 then
    lastPoolAlert[name] = now
    Sound("READY_CHECK", 8960)
    ns.Alert("Fishing pool: " .. name, 136245, 0.35, 0.8, 1)
    ns.say(("Fishing pool in view: %s%s|r"):format(GOLD, name))
  end
  return true
end

-- pools seen at a catch-log spot ("Zone / Subzone"): { { name, spots, seen } } most seen first
function ns.PoolsAt(key)
  local db = ns.DB()
  local zp = db and db.pools and db.pools[key]
  local out = {}
  for name, list in pairs(zp or {}) do
    local seen = 0
    for _, s in ipairs(list) do seen = seen + (s.n or 1) end
    out[#out + 1] = { name = name, spots = #list, seen = seen }
  end
  table.sort(out, function(a, b) return a.seen > b.seen end)
  return out
end

local function SoftName()
  if not (UnitExists and UnitExists("softinteract")) then return end
  local n = UnitName and UnitName("softinteract")
  if n and not (FA.IsSecret and FA.IsSecret(n)) then return n end
end

---------------------------------------------------------------- rare catch alerts
local RARE_WORDS = { "chest", "box", "crate", "trunk", "footlocker", "lockbox", "strongbox" }
-- uncommon or better, a quest item, or a chest
function ns.IsRareCatch(id)
  local name, _, quality = Info(id)
  local classID = select(6, Instant(id))
  if quality and quality >= 2 then return true end
  if classID == 12 then return true end
  local l = name and name:lower() or ""
  for _, w in ipairs(RARE_WORDS) do if l:find(w, 1, true) then return true end end
  return false
end

local function RareAlert(entry)
  if not ns.AlertsOn() then return end
  for _, it in ipairs((entry and entry.items) or {}) do
    if ns.IsRareCatch(it.id) then
      local name, _, quality = Info(it.id)
      name = name or ns.ItemName(it.id)
      local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
      if not c or quality < 2 then c = { r = 0.1, g = 1, b = 0.1 } end
      Sound("UI_EPICLOOT_TOAST", 31578)
      ns.Alert("Rare catch: " .. name, select(5, Instant(it.id)), c.r, c.g, c.b)
      return true
    end
  end
end

---------------------------------------------------------------- hooks
local baseOnCatch = ns.OnCatch
function ns.OnCatch(entry)
  if baseOnCatch then baseOnCatch(entry) end
  pcall(AddValue, entry)
  pcall(RareAlert, entry)
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_SOFT_INTERACT_CHANGED")
ev:SetScript("OnEvent", function()
  local n = SoftName()
  if n then ns.SeenPool(n) end
end)
if FA.GuardEvents then FA.GuardEvents(ev) end

-- mousing over a pool counts too (the game's object tooltip)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
   and Enum.TooltipDataType.Object then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tt)
    if tt ~= GameTooltip then return end
    local fs = _G[tt:GetName() .. "TextLeft1"]
    local n = fs and fs:GetText()
    if n then pcall(ns.SeenPool, n) end
  end)
end
