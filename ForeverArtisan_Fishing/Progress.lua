-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Fishing: skill-up tracker and catch goals
local _, ns = ...
if not ns or not ns.DB then return end

local GREEN, YELLOW, RED = "|cff40ff40", "|cffffff00", "|cffff4040"

---------------------------------------------------------------- skill tracker
local session = { catches = 0, ups = 0, firstCatch = nil, startSkill = nil, cappedWarned = {} }
ns.session = session

-- Where to train next. Forever finds noted; Classic defaults otherwise.
-- verified = seen in the Forever beta; otherwise it's the Classic answer and says so.
local ADVICE = {
  Horde = {
    [75]  = "Journeyman: any Horde Fishing trainer, needs 50. Classic: Lumak (Orgrimmar), Kah Mistrunner (Thunder Bluff), Armand Cromwell (Undercity). Not logged in Forever yet.",
    [150] = "Expert: Expert Fishing book from Old Man Heming, Booty Bay (1g, needs 125). Neutral, both factions. Confirmed in Forever.",
    [225] = "Artisan: Classic has Nat Pagle's quest in Dustwallow Marsh (needs 225). Neutral, both factions. Not confirmed in Forever yet.",
    [300] = "Top rank. Nothing left to train.",
  },
  Alliance = {
    [75]  = "Journeyman: any Alliance Fishing trainer, needs 50. Classic: Arnold Leland (Stormwind), Grimnur Stonebrand (Ironforge), Androl Oakhand (Rut'theran Village). No Alliance data in Forever yet.",
    [150] = "Expert: Expert Fishing book from Old Man Heming, Booty Bay (1g, needs 125). Neutral, both factions. Confirmed in Forever.",
    [225] = "Artisan: Classic has Nat Pagle's quest in Dustwallow Marsh (needs 225). Neutral, both factions. Not confirmed in Forever yet.",
    [300] = "Top rank. Nothing left to train.",
  },
}
local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return (f == "Alliance" or f == "Horde") and f or "Horde"
end

function ns.SkillInfo()
  local rank, mod, max = ns.FishingSkill()
  local info = { rank = rank, mod = mod, max = max }
  if not rank then return info end
  session.startSkill = session.startSkill or rank
  info.gained = rank - session.startSkill
  -- catches per skill point: this session if we have skill-ups, else recent history
  local cpp
  if session.ups > 0 then cpp = session.catches / session.ups end
  if not cpp then
    local log, n, c = ns.DB().skillLog, 0, 0
    for i = #log, math.max(1, #log - 9), -1 do
      if (log[i].c or 0) > 0 then n, c = n + 1, c + log[i].c end
    end
    if n > 0 then cpp = c / n end
  end
  info.cpp = cpp
  if max and max > rank and cpp then
    info.toCap = max - rank
    info.catchesToCap = math.ceil(info.toCap * cpp)
    if session.firstCatch and session.catches >= 3 then
      local mins = (GetTime() - session.firstCatch) / 60
      local perMin = session.catches / math.max(mins, 1)
      info.minsToCap = math.ceil(info.catchesToCap / perMin)
    end
  end
  info.capped = max and rank >= max and max < 300
  info.faction = Faction()
  info.advice = max and ADVICE[info.faction][max]
  info.sinceUp = ns.DB().sinceUp or 0
  return info
end

function ns.IsCapped()
  local i = ns.SkillInfo()
  return i.capped
end

function ns.OnCatch(entry)
  -- goal progress = what you've caught since logging in (kept through /reload)
  local db0 = ns.DB()
  db0.goalCaught = db0.goalCaught or {}
  for _, it in ipairs((entry and entry.items) or {}) do
    db0.goalCaught[it.id] = (db0.goalCaught[it.id] or 0) + (it.n or 1)
  end
  if ns.CheckGoals then ns.CheckGoals() end
  session.catches = session.catches + 1
  session.firstCatch = session.firstCatch or GetTime()
  local db = ns.DB()
  db.sinceUp = (db.sinceUp or 0) + 1
  local i = ns.SkillInfo()
  if i.capped and not session.cappedWarned[i.max] then
    session.cappedWarned[i.max] = true
    ns.say(RED .. ("Fishing is capped at %d. You're not gaining skill.|r %s"):format(i.max, i.advice or ""))
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
  end
end

function ns.OnSkillUp(n)
  local db = ns.DB()
  session.ups = session.ups + 1
  session.startSkill = session.startSkill or (n - 1)
  local log = db.skillLog
  log[#log + 1] = { s = n, c = db.sinceUp or 0, d = ns.Today(), t = time() }
  if #log > 500 then table.remove(log, 1) end
  db.sinceUp = 0
end

---------------------------------------------------------------- goals
local function ItemIdByName(name)
  name = name:lower()
  local db = ns.DB()
  for _, z in pairs(db.zones) do
    for id, it in pairs(z.items) do
      if it.name and it.name:lower() == name then return id end
    end
  end
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not f then return end
  local _, link = f(name)
  return link and tonumber(link:match("item:(%d+)"))
end

-- progress counts catches since you logged in, not what's in your bags
local function Have(id)
  local c = ns.DB().goalCaught
  return (c and c[id]) or 0
end

function ns.ResetGoalProgress(quiet)
  local db = ns.DB()
  db.goalCaught = {}
  for _, g in ipairs(db.goals or {}) do g.met = nil end
  if not quiet then ns.say("Goal progress reset to 0.") end
  if ns.OnChange then ns.OnChange() end
end

function ns.BestSpot(id)
  local best, bestPct
  for _, z in pairs(ns.DB().zones) do
    local it = z.items[id]
    if it and z.catches > 0 then
      local pct = it.hauls * 100 / z.catches
      if not bestPct or pct > bestPct then best, bestPct = z, pct end
    end
  end
  return best, bestPct and math.floor(bestPct + 0.5)
end

function ns.AddGoal(id, want, name)
  if not id then return end
  want = math.max(1, math.min(9999, tonumber(want) or 20))
  local goals = ns.DB().goals
  for _, g in ipairs(goals) do
    if g.id == id then g.want = want; g.met = nil; ns.say(("Goal updated: %d %s."):format(want, g.name or ns.ItemName(id))); ns.OnChange(); return end
  end
  goals[#goals + 1] = { id = id, want = want, name = name or ns.ItemName(id) }
  ns.say(("Goal added: %d %s."):format(want, name or ns.ItemName(id)))
  ns.OnChange()
end

-- add many at once (skips ones you already have as goals); returns number added
function ns.AddGoals(list, want)
  want = math.max(1, math.min(9999, tonumber(want) or 20))
  local goals, have, added = ns.DB().goals, {}, 0
  for _, g in ipairs(goals) do have[g.id] = true end
  for _, it in ipairs(list) do
    if not have[it.id] then
      goals[#goals + 1] = { id = it.id, want = want, name = it.name or ns.ItemName(it.id) }
      have[it.id] = true; added = added + 1
    end
  end
  ns.say(added > 0 and ("Added %d goal%s of %d each."):format(added, added == 1 and "" or "s", want) or "Those are already all goals.")
  ns.OnChange()
  return added
end

function ns.AddGoalByName(name, want)
  local id = ItemIdByName(name)
  if not id then ns.say("I don't know that item yet. Catch one first, or drag it into the goal slot.") return end
  ns.AddGoal(id, want, name)
end

function ns.SetGoalWant(i, n)
  local g = ns.DB().goals[i]
  n = math.max(1, math.min(9999, math.floor(tonumber(n) or 0)))
  if not g or g.want == n then return end
  g.want = n; g.met = nil
  ns.OnChange()
end

function ns.RemoveGoal(i)
  table.remove(ns.DB().goals, i)
  ns.OnChange()
end

function ns.GoalRows()
  local rows = {}
  for i, g in ipairs(ns.DB().goals) do
    local z, pct = ns.BestSpot(g.id)
    rows[#rows + 1] = { i = i, id = g.id, name = g.name or ns.ItemName(g.id), want = g.want, have = Have(g.id),
      best = z and ("%s (%s) %d%%"):format(z.sub, z.zone, pct) or nil }
  end
  return rows
end

local function CheckGoals()
  for _, g in ipairs(ns.DB().goals) do
    local have = Have(g.id)
    if have >= g.want and not g.met then
      g.met = true
      ns.say(GREEN .. ("Goal done: %d %s.|r"):format(g.want, g.name or ns.ItemName(g.id)))
      pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
    elseif have < g.want then
      g.met = nil
    end
  end
end

---------------------------------------------------------------- cooking suggestions
-- Uses the Cooking module's recipe scan (ForeverArtisanCookingDB) for this character.
-- Falls back to the Logger's scan if that's all there is (Logger isn't in the public download).
local function CookingRank()
  if GetProfessions and GetProfessionInfo then
    local ok, _, _, _, _, cook = pcall(GetProfessions)
    if ok and cook then
      local _, _, rank = GetProfessionInfo(cook)
      if rank then return rank end
    end
  end
end

local function CookingRecipes()
  local cdb = ForeverArtisanCookingDB
  if type(cdb) == "table" and type(cdb.chars) == "table" then
    local key = (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
    local c = cdb.chars[key]
    if c and c.recipes and next(c.recipes) then
      local out = {}
      for name, r in pairs(c.recipes) do
        local reagents = {}
        for _, g in ipairs(r.reagents or {}) do
          reagents[#reagents + 1] = { itemId = g.id, name = g.name, count = g.n or 1 }
        end
        out[name] = { learned = r.learned, grayAt = r.grayAt, reagents = reagents }
      end
      return out, c.skill
    end
  end
  local P = ForeverArtisanLoggerDB and ForeverArtisanLoggerDB.professions and ForeverArtisanLoggerDB.professions.Cooking
  if P and P.recipes then return P.recipes, tonumber(P.rank) end
end

local function CaughtIds()
  local ids = {}
  for _, z in pairs(ns.DB().zones) do for id in pairs(z.items) do ids[id] = true end end
  return ids
end

-- returns list, cookingRank, reason
function ns.CookingSuggestions()
  local recipes, savedRank = CookingRecipes()
  if not recipes then
    return {}, nil, "Open your Cooking window once (with the Cooking module on), then try again."
  end
  local rank = CookingRank() or savedRank or 0
  local caught, out = CaughtIds(), {}
  for rname, r in pairs(recipes) do
    if r.learned and r.grayAt and r.grayAt > rank then
      for _, g in ipairs(r.reagents or {}) do
        local id = g.itemId
        if id and ((g.name and g.name:match("^Raw ")) or caught[id]) then
          local left = math.min(r.grayAt - rank, 25)
          out[#out + 1] = { recipe = rname, grayAt = r.grayAt, id = id, name = g.name or ns.ItemName(id),
            per = g.count or 1, want = (g.count or 1) * left, left = left }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.grayAt < b.grayAt end)
  return out, rank
end

---------------------------------------------------------------- events
ns.CheckGoals = CheckGoals
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, e, isInitialLogin)
  if not ns.DB() then return end
  -- a real login starts goal progress over; /reload and zoning keep it
  if e == "PLAYER_ENTERING_WORLD" and isInitialLogin then ns.ResetGoalProgress(true) end
end)
