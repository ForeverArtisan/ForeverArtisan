-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: the plan and the shopping list, popped out (0.9.52, one button since 0.9.55).
--   Kerry, Nov 22: "Can we get the plan to popout into a transparent window (like the shopping list)",
--   then "make one Pop in and popout button ... Maybe the goals continues to include both plan to skill
--   and shopping list?". One "Pop out" by "Plan to skill" on a crafting Progress tab puts that
--   profession's plan ("<prof> plan") and its whole shopping list ("<prof> shopping") in the goals
--   window (Core Tracker.lua); "Pop in" takes both out. Same rows, colors and hover text as the tab, and
--   it keeps up as you skill with the profession window closed.
--   FA.PlanPop.Button(p, prof, shopFn)    the button; shopFn() = the tab's shopping list now
--   FA.PlanPop.Register(prof, fn, openFn) fn() refreshes that module's Progress tab (it calls Set);
--                                         openFn() opens the module window on its Progress tab
--   FA.PlanPop.Set(prof, d)               d = { rows, target, rank, max, note } or { empty = text }
--   FA.PlanPop.Toggle(prof, on), IsOn(prof), Open(prof), Groups(), Replan(), Slash(rest)
local FA = ForeverArtisan
local P = {}
FA.PlanPop = P
local GRAY = "|cff9d9d9d"

---------------------------------------------------------------- saved state (per character)
local function S()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.planPop = s.planPop or {}
  local key = FA.CharKey(s.planPop)
  local t = s.planPop[key]
  if not t then t = {}; s.planPop[key] = t end
  t.on = t.on or {} -- [prof] = true while that plan is popped out
  return t
end

local data, sources, opens, shops, buttons = {}, {}, {}, {}, {}
P._data, P._buttons = data, buttons -- for the test suite

function P.IsOn(prof) return S().on[prof] and true or false end

function P.Register(prof, fn, openFn) sources[prof], opens[prof] = fn, openFn end

function P.Open(prof) if opens[prof] then pcall(opens[prof]) end end

local function Redraw() if FA.Track and FA.Track.Refresh then FA.Track.Refresh() end end

local dirty = true
function P.Set(prof, d)
  data[prof] = d
  if S().on[prof] then Redraw() end
end

local function Fresh(prof)
  if sources[prof] and not (InCombatLockdown and InCombatLockdown()) then pcall(sources[prof]) end
end

local function Label(prof)
  local b = buttons[prof]
  if b then b:SetText(P.IsOn(prof) and "Pop in" or "Pop out") end
end

-- on: the plan and the whole shopping list go in the goals window (shown and unfolded);
-- off: both come out
function P.Toggle(prof, on)
  local s = S()
  if on == nil then on = not s.on[prof] end
  local T = FA.Track
  if on then
    s.on[prof] = true
    if not data[prof] then Fresh(prof) end
    if T then
      local list = shops[prof] and shops[prof]()
      if T.TrackAll and list then T.TrackAll(prof, list) end
      if T.ShowList then T.ShowList() end
    end
  else
    s.on[prof] = nil
    if T and T.UntrackAll and shops[prof] then T.UntrackAll(prof) end
  end
  Label(prof)
  Redraw()
end

function P.Button(p, prof, shopFn)
  shops[prof] = shopFn
  local b = FA.UI.Button(p, "Pop out", 70, function() P.Toggle(prof) end)
  b:SetHeight(20); b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -24, -50)
  FA.UI.Tip(b, function()
    GameTooltip:AddLine("Pop the plan and shopping list out")
    GameTooltip:AddLine("Both go on screen in the goals window, which keeps up as you skill, buy and loot, window open or not. Click a heading there to fold it. Right-click one shopping item to pop out just that one.", 1, 1, 1, true)
  end)
  buttons[prof] = b
  Label(prof)
  return b
end

-- the popped-out plans for the goals window, in order:
-- { { prof, sub = "75 to 150", note, rows = { d, ... } }, ... }
function P.Groups()
  local s, out, profs = S(), {}, {}
  for prof in pairs(s.on) do profs[#profs + 1] = prof end
  table.sort(profs)
  for _, prof in ipairs(profs) do
    local d = data[prof] or {}
    local sub
    if d.rank and d.target then sub = ("%d to %d"):format(d.rank, d.target)
    elseif d.target then sub = "to " .. d.target end
    local note = d.empty
    if not note and d.note and d.note ~= "" then note = d.note end
    if not d.rows and not d.empty then note = GRAY .. "Open " .. prof .. " once (/fa) and its plan shows here.|r" end
    out[#out + 1] = { prof = prof, sub = sub, note = note, rows = d.rows or {} }
  end
  return out
end

-- /fa plan: the plan lives in the goals window now
function P.Slash(rest)
  if FA.Track and FA.Track.Slash then FA.Track.Slash(rest) end
end

---------------------------------------------------------------- fresh plans with the window closed
-- skill-ups, new recipes, bags and prices change the plan: plan again on the next quiet second
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "BAG_UPDATE_DELAYED",
  "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function() dirty = true end)
if FA.PriceWatchers then table.insert(FA.PriceWatchers, function() dirty = true end) end
function P.Replan()
  dirty = false
  for prof in pairs(S().on) do Fresh(prof) end
  Redraw()
end
local acc = 0
ev:SetScript("OnUpdate", function(_, el)
  acc = acc + (el or 0)
  if acc < 1 then return end
  acc = 0
  if dirty and ForeverArtisanSettings and not (InCombatLockdown and InCombatLockdown()) then
    local ok, s = pcall(S)
    if ok and next(s.on) then P.Replan() else dirty = false end
  end
end)
