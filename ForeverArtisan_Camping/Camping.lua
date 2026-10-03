-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Camping
-- Your side of Forever's camps: the camp item each of your professions can place, the shared one-hour
-- cooldown after you place one, the Cooking campfire kits, and a reminder when you're at a fire and yours is ready.
-- It never maps other players' fires, and it never places anything for you.
local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_Camping"
ns = ns or {}

local GREEN, YELLOW, GRAY = "|cff40ff40", "|cffffff00", "|cff9d9d9d"
local COOLDOWN = 3600
local db
local say = ForeverArtisan.Printer("Camping")
ns.say = say
ns.DB = function() return db end

local function CharRec()
  local key = (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
  db.chars[key] = db.chars[key] or {}
  return db.chars[key]
end
ns.CharRec = CharRec

local function SpellName(id)
  if not id then return end
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); return i and i.name
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

---------------------------------------------------------------- skills
-- skill line -> rank for every profession this character has (primary and secondary)
function ns.Skills()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ a, b, c, d, e, f }) do
        local name, _, rank, _, _, _, line = GetProfessionInfo(idx)
        if rank and line then out[line] = rank end
        if rank and name then out[name] = rank end
      end
    end
  end
  if next(out) == nil and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank = GetSkillLineInfo(i)
      if not header and name and rank then out[name] = rank end
    end
  end
  return out
end

local function SkillFor(skills, prof, line) return skills[line] or skills[prof] end

---------------------------------------------------------------- bags
-- camp items and kits in your bags: lower name -> { id, n, name }
-- One pass over the bags gives both: camp items and kits (lower name -> { id, n, name, item }) and a count of
-- every item by lower name (for materials). Cached until the bags change (BAG_UPDATE_DELAYED).
local cache
local function Scan()
  if cache then return cache end
  local found, counts = {}, {}
  local num = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local link = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  local info = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
  if num and link then
    for bag = 0, 4 do
      for slot = 1, (num(bag) or 0) do
        local l = link(bag, slot)
        local name = l and l:match("%[(.-)%]")
        if name then
          local n = 1
          local i = info and info(bag, slot)
          if type(i) == "table" then n = i.stackCount or 1 elseif type(i) == "number" then n = select(2, info(bag, slot)) or 1 end
          local key = name:lower()
          counts[key] = (counts[key] or 0) + n
          local hit = ns.CampItem(name) or ns.kitByName[key]
          if hit then
            local f = found[key]
            if not f then f = { id = tonumber(l:match("item:(%d+)")), n = 0, name = name, item = hit }; found[key] = f end
            f.n = f.n + n
          end
        end
      end
    end
  end
  cache = { items = found, counts = counts }
  return cache
end
function ns.InvalidateBags() cache = nil end
function ns.BagItems() return Scan().items end
local function BagCounts() return Scan().counts end

---------------------------------------------------------------- reagents
-- what a camp item takes: learned from the profession window when it's open, else what we saw in the beta
function ns.Reagents(itemName)
  return (db.reagents and db.reagents[itemName]) or ns.SEED_REAGENTS[itemName]
end

-- how many you can make from your bags (nil = reagents unknown), plus one line per reagent for the tooltip
function ns.CanMake(itemName, counts)
  local list = ns.Reagents(itemName)
  if not list then return nil end
  counts = counts or BagCounts()
  local can, lines = math.huge, {}
  for _, g in ipairs(list) do
    local have = counts[(g.name or ""):lower()] or 0
    can = math.min(can, math.floor(have / (g.n or 1)))
    lines[#lines + 1] = ("%s%d/%d|r %s"):format(have >= (g.n or 1) and GREEN or "|cffff4040", math.min(have, g.n or 1), g.n or 1, g.name or "?")
  end
  return can == math.huge and 0 or can, lines
end
ns.BagCounts = BagCounts

-- read the open profession window: reagents for any camp item or kit in it
function ns.LearnReagents()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetRecipeSchematic) then return end
  local ok, ids = pcall(T.GetAllRecipeIDs)
  if not ok or type(ids) ~= "table" then return end
  for _, id in ipairs(ids) do
    local info = T.GetRecipeInfo(id)
    local name = info and info.name
    -- the Cooking recipe is "Basic Campfire"; the item it makes is "Basic Campfire Kit"
    local item = name and ((ns.CampItem(name) and ns.CampItem(name).name) or (ns.kitByName[(name .. " kit"):lower()] and name .. " Kit"))
    if item then
      local okS, sch = pcall(T.GetRecipeSchematic, id, false)
      if okS and type(sch) == "table" and sch.reagentSlotSchematics then
        local list = {}
        for _, slot in ipairs(sch.reagentSlotSchematics) do
          local first = slot.reagents and slot.reagents[1]
          local iname = first and first.itemID and ((C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(first.itemID)) or (GetItemInfo and GetItemInfo(first.itemID)))
          if iname then list[#list + 1] = { name = iname, n = slot.quantityRequired or 1 } end
        end
        if #list > 0 then db.reagents = db.reagents or {}; db.reagents[item] = list end
      end
    end
  end
end

---------------------------------------------------------------- your camp items
-- one row per profession you have: what you can place now and what's next
function ns.Rows()
  local skills, bags, rows = ns.Skills(), ns.BagItems(), {}
  local counts = BagCounts()
  for _, p in ipairs(ns.CAMP) do
    local prof, line, icon, names = p[1], p[2], p[3], p[4]
    local skill = SkillFor(skills, prof, line)
    if skill then
      -- tier 1 comes with the skill; tiers 2 and 3 also need a Blueprint, so they only count once one is in your bags
      local tier = skill >= ns.TIERS[1] and 1 or 0
      local r = { prof = prof, line = line, icon = icon, skill = skill }
      for t = #names, 1, -1 do
        for _, b in pairs(bags) do
          if b.item and b.item.prof == prof and b.item.tier == t then r.have, r.haveN = b.name, b.n; break end
        end
        if r.have then tier = math.max(tier, t); break end
      end
      r.tier = tier
      if tier > 0 then r.now = names[tier] end
      if tier < #ns.TIERS then
        r.next, r.nextAt = names[tier + 1], ns.TIERS[tier + 1]
        r.blueprint = tier + 1 >= 2
        r.skillOK = skill >= r.nextAt
      end
      if r.now then r.can, r.mats = ns.CanMake(r.now, counts) end
      rows[#rows + 1] = r
    end
  end
  return rows
end

-- the kits with your Cooking skill: "use" / "learn" / "low"
function ns.KitRows()
  local skills, bags, out = ns.Skills(), ns.BagItems(), {}
  local cook = SkillFor(skills, "Cooking", ns.COOKING_LINE)
  for _, k in ipairs(ns.KITS) do
    local st = "low"
    if cook and cook >= k.use then st = "use" elseif cook and cook >= k.learn then st = "learn" end
    local b = bags[k.name:lower()]
    out[#out + 1] = { kit = k, state = st, cook = cook, have = b and b.n or 0 }
  end
  return out, cook
end

-- "Fishing Rack at 140", "Fishing Rack: needs a Blueprint" once your skill is there
function ns.NextText(r)
  if not r.next then return end
  if r.skillOK and r.blueprint then return r.next .. ": needs a Blueprint" end
  return ("%s at %d%s"):format(r.next, r.nextAt, r.blueprint and " + Blueprint" or "")
end

-- seconds until you can build another campfire (0 = ready), from a kit in your bags; nil = no kit in your bags
function ns.KitLeft()
  local getcd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  for _, b in pairs(ns.BagItems()) do
    if b.item and b.item.slots and b.id then
      if not getcd then return 0 end
      local start, dur = getcd(b.id)
      if start and start > 0 and dur and dur > 1.5 then return math.max(0, start + dur - GetTime()) end
      return 0
    end
  end
end

---------------------------------------------------------------- cooldown
-- seconds until you can place a camp item again (0 = ready). The item's own cooldown wins when one is in
-- your bags; otherwise the time we saved when you placed one.
function ns.Left()
  local getcd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if getcd then
    for _, b in pairs(ns.BagItems()) do
      if b.item and b.item.prof and b.id then
        local start, dur = getcd(b.id)
        if start and start > 0 and dur and dur > 1.5 then return math.max(0, start + dur - GetTime()) end
        if start == 0 then return 0 end
      end
    end
  end
  local c = CharRec()
  if c.readyAt and c.readyAt > time() then return c.readyAt - time() end
  return 0
end

local function Mins(s)
  if s >= 60 then return math.ceil(s / 60) .. " min" end
  return math.ceil(s) .. " sec"
end
ns.Mins = Mins

function ns.Status()
  local left = ns.Left()
  local c = CharRec()
  if left <= 0 then return GREEN .. "Camp items: ready|r" end
  return YELLOW .. "Camp items: ready in " .. Mins(left) .. "|r" .. (c.lastItem and (GRAY .. "  (placed " .. c.lastItem .. ")|r") or "")
end

local wake = 0
local function ScheduleReady(prev)
  local left = ns.Left()
  if left <= 0 or not C_Timer then return end
  if prev and left >= prev then return end -- the clock didn't move: don't spin
  wake = wake + 1
  local mine = wake
  C_Timer.After(left + 1, function()
    if mine ~= wake then return end
    if ns.Left() <= 0 then
      if db.settings.readyMsg then say(GREEN .. "Camp items are ready again.|r") end
      if ns.OnChange then ns.OnChange() end
    else
      ScheduleReady(left)
    end
  end)
end

function ns.Placed(name)
  local it = ns.CampItem(name)
  if not it then return end
  local c = CharRec()
  c.readyAt, c.lastItem, c.lastAt = time() + COOLDOWN, it.name, time()
  c.placed = (c.placed or 0) + 1
  if C_Timer then C_Timer.After(1, function() ScheduleReady() end) end
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- craft one
-- Open the profession's window on the camp item's recipe. Camp items sit under "Camping" in each window,
-- Fishing, Herbalism and Skinning included. If the client won't open it for us, say where it is.
local WINDOWS = { "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }
local function WindowShown()
  for _, name in ipairs(WINDOWS) do if _G[name] and _G[name]:IsShown() then return true end end
end

local function SelectRecipe(itemName)
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
  local ok, ids = pcall(T.GetAllRecipeIDs)
  if not ok or type(ids) ~= "table" then return end
  for _, id in ipairs(ids) do
    local info = T.GetRecipeInfo(id)
    if info and info.name and info.name:lower() == itemName:lower() then
      if T.OpenRecipe then pcall(T.OpenRecipe, id) elseif T.SelectRecipe then pcall(T.SelectRecipe, id) end
      return true
    end
  end
end

function ns.OpenCraft(prof, line, itemName)
  if not itemName or (InCombatLockdown and InCombatLockdown()) then return end
  local T = C_TradeSkillUI
  -- always ask for this profession: another profession's window may be the one that's open
  if T and T.OpenTradeSkill then pcall(T.OpenTradeSkill, line) end
  local function finish()
    if WindowShown() then ns.LearnReagents() end
    local found = WindowShown() and SelectRecipe(itemName)
    if not found then
      say(("Open your %s window, then pick %s under Camping."):format(prof, itemName))
    end
  end
  if C_Timer then C_Timer.After(0.5, finish) else finish() end
end

---------------------------------------------------------------- at a fire
-- the buff the game gives near a campfire ("Campfire Nearby" in the beta)
local function NearFire()
  for i = 1, 40 do
    local name
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not a then break end
      name = a.name
    elseif UnitBuff then
      name = UnitBuff("player", i)
      if not name then break end
    else
      break
    end
    if name and name:lower():find("campfire", 1, true) then return true end
  end
  return false
end
ns.NearFire = NearFire

local atFire, lastNudge = false, -10000
local function CheckFire()
  local now = NearFire()
  if now and not atFire and db.settings.reminder and ns.Left() <= 0 and GetTime() - lastNudge > 600 then
    local mine
    for _, b in pairs(ns.BagItems()) do
      if b.item and b.item.prof then
        if not mine or b.item.tier > mine.item.tier then mine = b end
      end
    end
    if mine then
      lastNudge = GetTime()
      say(YELLOW .. ("Your %s is ready. Place it at this fire."):format(mine.name) .. "|r")
    end
  end
  if now ~= atFire then
    atFire = now
    if ns.OnChange then ns.OnChange() end
  end
end
ns.CheckFire = CheckFire
function ns.AtFire() return atFire end

---------------------------------------------------------------- placing, seen two ways
-- 1) a cast named like a camp item; 2) a camp item leaving your bags while you're at a fire.
-- The second works even if Forever names the cast differently. Casts near a drop are kept for /fa camp debug.
local counts            -- camp item counts at the last bag update
local lastCast          -- { name, t }
local function CampCounts()
  local out = {}
  for key, b in pairs(ns.BagItems()) do
    if b.item and b.item.prof then out[key] = { n = b.n, name = b.name } end
  end
  return out
end

local function BagsChanged()
  local now = CampCounts()
  if counts and NearFire() then
    for key, old in pairs(counts) do
      local n = now[key] and now[key].n or 0
      if n == old.n - 1 then
        local c = CharRec()
        -- already counted from the cast a moment ago? then only note the cast name
        if not (c.lastItem == old.name and c.lastAt and time() - c.lastAt < 5) then ns.Placed(old.name) end
        if lastCast and GetTime() - lastCast.t < 5 then
          db.castNames = db.castNames or {}
          db.castNames[lastCast.name] = old.name
        end
      end
    end
  end
  counts = now
end
ns.BagsChanged = BagsChanged

---------------------------------------------------------------- events
local learnPending = false
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA",
  "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
  if e == "ADDON_LOADED" and a1 == ADDON then
    ForeverArtisanCampingDB = ForeverArtisanCampingDB or {}
    db = ForeverArtisanCampingDB
    db.version = ForeverArtisan.Version()
    db.settings = db.settings or {}
    if db.settings.reminder == nil then db.settings.reminder = true end
    if db.settings.readyMsg == nil then db.settings.readyMsg = true end
    db.chars = db.chars or {}
    return
  end
  if not db then return end
  if e == "PLAYER_ENTERING_WORLD" then
    cache = nil
    counts = CampCounts()
    ScheduleReady()
    CheckFire()
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    -- (unit, castGUID, spellID): placing a camp item is a cast named after the item
    local name = SpellName(a3)
    if name then lastCast = { name = name, t = GetTime() } end
    -- a cast name we've seen place a camp item before, or one named like the item
    ns.Placed((db.castNames and name and db.castNames[name]) or name)
  elseif e == "UNIT_AURA" and a1 == "player" then
    -- newer clients say what changed: skip pure refreshes (stacks, durations), which are most of them in combat
    if type(a2) == "table" and not a2.isFullUpdate and not a2.addedAuras and not a2.removedAuraInstanceIDs then return end
    CheckFire()
  elseif e == "BAG_UPDATE_DELAYED" then
    cache = nil
    BagsChanged()
    if ns.OnChange then ns.OnChange() end
  elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_LIST_UPDATE" then
    -- the list event fires on every craft; read the window once per burst
    if not learnPending then
      learnPending = true
      local function run() learnPending = false; ns.LearnReagents(); if ns.OnChange then ns.OnChange() end end
      if C_Timer then C_Timer.After(0.5, run) else run() end
    end
  elseif e == "SKILL_LINES_CHANGED" then
    if ns.OnChange then ns.OnChange() end
  end
end)

---------------------------------------------------------------- slash
SLASH_FACAMP1 = "/facamp"
SlashCmdList.FACAMP = function(msg)
  if not db then return end
  local cmd = ((msg or ""):match("^(%S*)") or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "status" then
    say(ns.Status())
    for _, r in ipairs(ns.Rows()) do
      say(("  %s %d: %s%s"):format(r.prof, r.skill, r.now or (GRAY .. "nothing yet|r"),
        r.next and (GRAY .. "  (next: " .. ns.NextText(r) .. ")|r") or ""))
    end
  elseif cmd == "debug" then
    local c = CharRec()
    say(("At a fire: %s  ·  saved ready time: %s  ·  last placed: %s"):format(NearFire() and "yes" or "no",
      c.readyAt and date("%H:%M", c.readyAt) or "none", c.lastItem or "none"))
    local any = false
    for key, b in pairs(ns.BagItems()) do any = true; say(("  in bags: %s x%d (item %s)"):format(b.name, b.n, tostring(b.id))) end
    if not any then say("  no camp items or kits in your bags") end
    for cast, item in pairs(db.castNames or {}) do say(("  cast \"%s\" places %s"):format(cast, item)) end
  elseif cmd == "reminder" then
    db.settings.reminder = not db.settings.reminder
    say("Campfire reminder " .. (db.settings.reminder and "on." or "off."))
  elseif cmd == "ready" then
    db.settings.readyMsg = not db.settings.readyMsg
    say("Ready-again message " .. (db.settings.readyMsg and "on." or "off."))
  else
    say("Commands: /fa camp (window), status, reminder, ready, debug")
  end
end
