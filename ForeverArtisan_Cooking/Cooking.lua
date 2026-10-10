-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Cooking
-- Reads your recipes from the Cooking window, shows what you can cook right now for skill-ups,
-- plans the cooks to reach a target skill with a shopping list (bags, vendors, your catch
-- and gathering logs), logs what you cook, and adds cooking lines to ingredient tooltips.
local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_Cooking"
ns = ns or {}

local GREEN, YELLOW, RED, GRAY = "|cff40ff40", "|cffffff00", "|cffff4040", "|cff9d9d9d"
local COOKING_SKILL_LINE = 185

local db
local say = ForeverArtisan.Printer("Cooking")
ns.say = say
ns.DB = function() return db end

local function Today() return date("%Y-%m-%d") end

---------------------------------------------------------------- items
local function ItemName(id, fallback)
  if not id then return fallback or "?" end
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local n = f and f(id)
  -- not loaded yet: ask the game for it; the list redraws when it arrives
  if not n and ForeverArtisan.WaitForItem then ForeverArtisan.WaitForItem(id) end
  return n or fallback or ("item:" .. id)
end
ns.ItemName = ItemName

local CountAPI = (C_Item and C_Item.GetItemCount) or GetItemCount
local function Count(id)
  if not id or not CountAPI then return 0 end
  local ok, n = pcall(CountAPI, id)
  return (ok and n) or 0
end
ns.Count = Count

---------------------------------------------------------------- per character
local function CharRec()
  db.chars = db.chars or {}
  local key = ForeverArtisan.CharKey(db.chars)
  local c = db.chars[key]
  if not c then c = { recipes = {} }; db.chars[key] = c end
  c.recipes = c.recipes or {}
  return c
end
ns.CharRec = CharRec

---------------------------------------------------------------- skill
local function IsCookName(n) return n and (n == "Cooking" or n == (PROFESSIONS_COOKING or "Cooking")) end

local function SkillLive()
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ e, a, b, c, d, f }) do -- pairs: a profession you lack is nil, and ipairs would stop there
        if idx then
          local name, _, rank, maxr, _, _, line, mod = GetProfessionInfo(idx)
          if rank and (line == COOKING_SKILL_LINE or IsCookName(name)) then return rank, mod, maxr end
        end
      end
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, COOKING_SKILL_LINE)
    if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
      return info.skillLevel, info.skillModifier, info.maxSkillLevel
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod, maxr = GetSkillLineInfo(i)
      if not header and IsCookName(name) and rank then return rank, mod, maxr end
    end
  end
end

local function Skill()
  local r, m, mx = SkillLive()
  if not db then return r, m, mx end
  local c = CharRec()
  if r then c.skill = r; if mx and mx > 0 then c.skillMax = mx end; return r, m, mx or c.skillMax end
  -- the game's list loaded without this profession: not learned (or unlearned), so drop the old value
  if ForeverArtisan.ProfessionListLoaded and ForeverArtisan.ProfessionListLoaded() then
    c.skill = nil
    -- recipes marked learned here came from another character (or an old save): not this one's
    for _, r in pairs(c.recipes or {}) do r.learned = false end
    return nil
  end
  return c.skill, nil, c.skillMax
end
ns.Skill = Skill

function ns.Knows() return Skill() ~= nil end

---------------------------------------------------------------- recipe colors
-- Forever reports the skill where a recipe turns gray. Logged history shows green starts
-- 20 below that and yellow 40 below, the Classic pattern.
function ns.ColorFor(r, skill)
  if not r then return "unknown" end
  if not r.learned then return "unlearned" end
  if not skill then return "unknown" end
  if r.grayAt then
    if skill >= r.grayAt then return "gray" end
    -- guessed 40 and 20 below gray, moved to fit the colors you've seen at other skills
    local y, g = ForeverArtisan.RecipeBands(r, r.grayAt)
    if skill >= g then return "green" end
    if skill >= y then return "yellow" end
    return "orange"
  end
  if r.scanSkill == skill and r.color then return r.color end
  return "unknown"
end

-- chance that one cook gives a skill-up
function ns.Chance(r, skill)
  local c = ns.ColorFor(r, skill)
  if c == "orange" then return 1 end
  if (c == "yellow" or c == "green") and r.grayAt then return ForeverArtisan.FadeChance(r, r.grayAt, skill) end
  if c == "yellow" then return 0.75 end
  if c == "green" then return 0.25 end
  return 0
end

ns.COLOR_CODE = {
  orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40c040", gray = "|cff808080",
  unlearned = "|cff9d9d9d", unknown = "|cffffffff",
}
ns.COLOR_WORD = {
  orange = "orange: always a skill-up", yellow = "yellow: usually a skill-up",
  green = "green: sometimes a skill-up", gray = "gray: no skill-ups", unlearned = "not learned", unknown = "",
}

---------------------------------------------------------------- reading the Cooking window
local COOKING_GROUP = { "food", "drink", "meal", "delight", "cuisine", "treat", "cooking" }
local function IsCookingGroup(g)
  if not g then return false end
  g = g:lower()
  for _, w in ipairs(COOKING_GROUP) do if g:find(w, 1, true) then return true end end
  return false
end

local function Try(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

-- Is the open profession window Cooking? Ask the game first, then look at the recipes.
-- the game's own answer: true / false, or nil when it can't say (cheap; no recipe reads)
local function QuickOurs(ids)
  local T = C_TradeSkillUI
  if T.GetTradeSkillLineForRecipe and ids[1] then
    local a, b, c = Try(T.GetTradeSkillLineForRecipe, ids[1])
    if a or b or c then return a == COOKING_SKILL_LINE or c == COOKING_SKILL_LINE or IsCookName(b) or false end
  end
  if T.GetBaseProfessionInfo then
    local info = Try(T.GetBaseProfessionInfo)
    if type(info) == "table" and (info.professionID or info.professionName) then
      return info.professionID == COOKING_SKILL_LINE or IsCookName(info.professionName) or false
    end
  end
end

local function WindowIsCooking(ids, infos)
  local quick = QuickOurs(ids)
  if quick ~= nil then return quick end
  local cooky = 0
  for _, ri in ipairs(infos) do if IsCookingGroup(ri.group) then cooky = cooky + 1 end end
  return cooky >= 3
end

local function ScanModern()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs) then return end
  local ids = Try(T.GetAllRecipeIDs)
  if type(ids) ~= "table" or #ids == 0 then return end
  -- another profession's window: stop before reading every recipe
  if QuickOurs(ids) == false then return end
  ns.lastIdCount = #ids
  local infos = {}
  for _, id in ipairs(ids) do
    local ri = Try(T.GetRecipeInfo, id)
    if type(ri) == "table" and ri.name and not ri.isDummyRecipe then
      local group
      if ri.categoryID and T.GetCategoryInfo then
        local cat = Try(T.GetCategoryInfo, ri.categoryID)
        group = type(cat) == "table" and cat.name or nil
      end
      infos[#infos + 1] = { id = id, ri = ri, group = group }
    end
  end
  if not WindowIsCooking(ids, infos) then return end
  local rank = Skill()
  local known = CharRec().recipes
  local out = {}
  for _, e in ipairs(infos) do
    local ri = e.ri
    local r = { id = e.id, name = ri.name, learned = ri.learned and true or false, group = e.group,
                grayAt = (ri.maxTrivialLevel and ri.maxTrivialLevel > 0) and ri.maxTrivialLevel or nil,
                ups = (ri.numSkillUps and ri.numSkillUps > 1) and ri.numSkillUps or nil,
                color = ri.learned and DIFF[ri.relativeDifficulty] or nil, scanSkill = rank, reagents = {} }
    -- reagents and the made item don't change between scans: keep them instead of asking again
    local old = known[ri.name]
    local sch
    if old and old.id == e.id and old.reagents and #old.reagents > 0 then
      r.reagents, r.itemId = old.reagents, old.itemId
    else
      sch = T.GetRecipeSchematic and Try(T.GetRecipeSchematic, e.id, false)
    end
    if type(sch) == "table" then
      r.itemId = sch.outputItemID
      for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        if first and first.itemID then
          r.reagents[#r.reagents + 1] = { id = first.itemID, n = slot.quantityRequired or 1, name = ItemName(first.itemID) }
        end
      end
    end
    out[r.name] = r
  end
  return out
end

local OLD_KIND = { optimal = "orange", medium = "yellow", easy = "green", trivial = "gray" }
local function ScanOld()
  if not (GetTradeSkillLine and GetNumTradeSkills) then return end
  local name = GetTradeSkillLine()
  if not IsCookName(name) then return end
  local rank = Skill()
  local out, header = {}, nil
  for i = 1, GetNumTradeSkills() do
    local rname, kind = GetTradeSkillInfo(i)
    if kind == "header" then header = rname
    elseif rname then
      local r = { name = rname, learned = true, group = header, color = OLD_KIND[kind], scanSkill = rank, reagents = {} }
      local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
      r.itemId = link and tonumber(link:match("item:(%d+)"))
      for j = 1, (GetTradeSkillNumReagents(i) or 0) do
        local n, _, cnt = GetTradeSkillReagentInfo(i, j)
        local rl = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)
        r.reagents[#r.reagents + 1] = { id = rl and tonumber(rl:match("item:(%d+)")), n = cnt or 1, name = n }
      end
      out[rname] = r
    end
  end
  return out
end

local recipeBySpell = {}
local function IndexRecipes()
  wipe(recipeBySpell)
  for name, r in pairs(CharRec().recipes) do if r.id then recipeBySpell[r.id] = r end end
end

local function Scan()
  if not db then return end
  local got = ScanModern() or ScanOld()
  if not got then return end
  local c, n, learned = CharRec(), 0, 0
  for name, r in pairs(got) do
    n = n + 1
    if r.learned then learned = learned + 1 end
    ForeverArtisan.NoteRecipeColor(c.recipes[name], r)
    c.recipes[name] = r
  end
  local first = not c.scanned
  c.scanned = time()
  IndexRecipes()
  if first then say(("Read your Cooking window: %d recipes, %d learned."):format(n, learned)) end
  if ns.OnChange then ns.OnChange() end
  return true
end

function ns.HasRecipes() return db and next(CharRec().recipes) ~= nil end

---------------------------------------------------------------- where to get things
-- Uses Core's vendor list and your Fishing / Herbalism / Mining / Skinning logs when they're loaded.
local function BestLogged(dbTable, id)
  if type(dbTable) ~= "table" or type(dbTable.zones) ~= "table" then return end
  local best, bestN
  for _, z in pairs(dbTable.zones) do
    local it = z.items and z.items[id]
    local n = it and (it.hauls or it.n)
    if n and (not bestN or n > bestN) then best, bestN = z, n end
  end
  if not best then return end
  if not best.sub or best.sub == best.zone then return best.zone end
  return best.sub .. " (" .. best.zone .. ")"
end

local function VendorFor(name)
  local V = ForeverArtisan and ForeverArtisan.Vendors
  if not (V and V.hitsForLink and name) then return end
  local hits = V.hitsForLink(nil, name)
  local h = hits and hits[1]
  if not h then return end
  return h.npc.n .. " (" .. (h.npc.s or h.npc.z or "?") .. ")", h.item and h.item.p
end

-- short text: where to get this ingredient
function ns.SourceFor(id, name)
  local v = VendorFor(name)
  if v then return "Vendor: " .. v end
  local hint = ForeverArtisan and ForeverArtisan.VendorHint and ForeverArtisan.VendorHint(name or id)
  if hint then return "Vendor: " .. hint .. " (none in your Trade Contacts yet)" end
  local w = BestLogged(ForeverArtisanFishingDB, id)
  if w then return "Fish: " .. w end
  w = BestLogged(ForeverArtisanSkinningDB, id)
  if w then return "Skin: " .. w end
  w = BestLogged(ForeverArtisanHerbalismDB, id)
  if w then return "Herb: " .. w end
  w = BestLogged(ForeverArtisanMiningDB, id)
  if w then return "Mine: " .. w end
  local drop = ForeverArtisan.MaterialWhere and ForeverArtisan.MaterialWhere(id)
  if drop then return drop end
  local herbAt = ForeverArtisan.HerbSkill and ForeverArtisan.HerbSkill(id)
  if herbAt then return ("Herb: gather it (Herbalism %d), or the Auction House. It's not in your Herbalism log yet."):format(herbAt) end
  if name and name:find("^Raw ") then return "Fish (not in your catch log yet)" end
  return "Drops from mobs"
end

ns.RecipePrefixes = { "Recipe: " }

-- where to buy an unlearned recipe, if Core's vendor list knows
function ns.RecipeSource(name)
  local v, price = VendorFor("Recipe: " .. name)
  if not v then return end
  local money = price and GetCoinTextureString and GetCoinTextureString(price) or ""
  return v .. (money ~= "" and ("  " .. money) or "")
end

---------------------------------------------------------------- cook now / plan
function ns.Makeable(r)
  if not r.reagents or #r.reagents == 0 then return 0 end
  local n
  for _, g in ipairs(r.reagents) do
    local can = math.floor(Count(g.id) / math.max(1, g.n or 1))
    n = (not n or can < n) and can or n
  end
  return n or 0
end

-- learned recipes that still give skill-ups, best first
function ns.CookNow()
  local skill = (function() local r, m = Skill(); return r and (r + (m or 0)) end)()
  local out = {}
  for _, r in pairs(CharRec().recipes) do
    local c = ns.ColorFor(r, skill)
    if c == "orange" or c == "yellow" or c == "green" then
      out[#out + 1] = { r = r, color = c, chance = ns.Chance(r, skill), make = ns.Makeable(r) }
    end
  end
  table.sort(out, function(a, b)
    if (a.make > 0) ~= (b.make > 0) then return a.make > 0 end
    if a.chance ~= b.chance then return a.chance > b.chance end
    return (a.r.grayAt or 0) > (b.r.grayAt or 0)
  end)
  return out, skill
end

-- Plan cooks from your skill to a target. Picks the best learned recipe at each point.
-- Returns steps { r, cooks, from, to }, shopping { id, name, need, have, source }, stuckAt
function ns.Plan(target)
  local skill = Skill()
  if not skill then return {}, {}, nil end
  local _, _, maxr = Skill()
  target = math.min(tonumber(target) or (skill + 25), 300)
  local learned = {}
  for _, r in pairs(CharRec().recipes) do if r.learned then learned[#learned + 1] = r end end
  -- plus recipes a trainer you've met still teaches (they join the plan at the skill they need)
  local untrained = 0
  if ForeverArtisan.PlanRecipes then learned, untrained = ForeverArtisan.PlanRecipes("Cooking", CharRec().recipes) end
  -- what you can make from your bags doesn't change while planning: count once
  local canMake = {}
  for _, r in ipairs(learned) do canMake[r] = ns.Makeable(r) > 0 end
  -- what each recipe's materials cost, looked up once per plan
  local memo = {}
  local function Money(r) return ForeverArtisan.CraftMoney(r, nil, memo) end
  local steps, byName, s, stuck = {}, {}, skill, nil
  local guard = 0
  while s < target and guard < 400 do
    guard = guard + 1
    -- prefer the best skill-up chance, but favor recipes you can already make from your bags;
    -- when two are close, the cheaper one per skill point
    local opts = {}
    for _, r in ipairs(learned) do
      local ch = (not r.train or s >= r.train.at) and ns.Chance(r, s) or 0
      if ch > 0 then opts[#opts + 1] = { r = r, ch = ch, bag = canMake[r], score = ch + (canMake[r] and 0.15 or 0) } end
    end
    local pick = ForeverArtisan.PickRecipe(opts, Money)
    if not pick then stuck = s; break end
    local best, bestChance = pick.r, pick.ch
    local st = byName[best.name]
    if not st or steps[#steps] ~= st then
      st = { r = best, cooks = 0, from = s, to = s, train = best.train }
      steps[#steps + 1] = st
      byName[best.name] = st
    end
    st.cooks = st.cooks + 1 / bestChance
    s = s + (best.ups or 1)
    st.to = s
  end
  local need = {}
  for _, st in ipairs(steps) do
    st.cooks = math.ceil(st.cooks)
    for _, g in ipairs(st.r.reagents or {}) do
      if g.id then
        local e = need[g.id] or { id = g.id, name = g.name, need = 0 }
        e.need = e.need + st.cooks * (g.n or 1)
        need[g.id] = e
      end
    end
  end
  local shopping = {}
  -- recipes to learn on the way: one line each, with the trainer and what it costs
  local trained = {}
  for _, st in ipairs(steps) do
    local t = st.train
    if t and not trained[st.r.name] then
      trained[st.r.name] = true
      shopping[#shopping + 1] = { name = "Train " .. st.r.name, need = 1, have = 0, train = t, price = t.cost,
        source = ("Learn it at %d from %s%s."):format(t.at, t.who or "a trainer",
          t.cost and (" for " .. ForeverArtisan.Money(t.cost)) or "") }
    end
  end
  for _, e in pairs(need) do
    e.name = ItemName(e.id, e.name)
    e.have = Count(e.id)
    e.source = ns.SourceFor(e.id, e.name)
    shopping[#shopping + 1] = e
  end
  -- what each thing costs: your Auction House visits or Auctionator, or a vendor when cheaper
  if ForeverArtisan.PriceShopping then ForeverArtisan.PriceShopping(shopping) end
  table.sort(shopping, function(a, b)
    if (a.train ~= nil) ~= (b.train ~= nil) then return a.train ~= nil end
    if a.train and b.train and a.train.at ~= b.train.at then return a.train.at < b.train.at end
    local sa, sb = a.need - a.have, b.need - b.have
    if (sa > 0) ~= (sb > 0) then return sa > 0 end
    return (a.name or "") < (b.name or "")
  end)
  local hint
  if stuck then
    local any = false
    for _, r in ipairs(learned) do if r.train then any = true end end
    if not any and ForeverArtisan.TrainHint then hint = ForeverArtisan.TrainHint("Cooking", untrained) end
  end
  return steps, shopping, stuck, target, maxr, hint
end

---------------------------------------------------------------- where to learn it
-- Not learned yet: the nearest trainer in your Trade Contacts whose list includes the
-- Apprentice rank (an Expert-only trainer is skipped). Nil when you haven't met one.
function ns.LearnFrom()
  local V = ForeverArtisan and ForeverArtisan.Vendors
  if not (V and V.search) then return end
  local prof = "cooking"
  for _, h in ipairs(V.search(prof) or {}) do
    for _, r in ipairs(h.ranks or {}) do
      local n = r:lower()
      if n:find("apprentice", 1, true) and n:find(prof, 1, true) then return h.npc end
    end
  end
  -- no Apprentice trainer on file: the closest trainer for it you've met or passed
  if V.nearestTrainer then return V.nearestTrainer("Cooking") end
end

---------------------------------------------------------------- session + cook log
local session = { cooks = 0, ups = 0, start = nil, last = nil }
ns.session = session

function ns.SessionInfo()
  local s = { cooks = session.cooks, ups = session.ups, last = session.last }
  if session.start then
    s.mins = (GetTime() - session.start) / 60
    if s.mins >= 1 then s.perHour = math.floor(session.cooks * 60 / s.mins + 0.5) end
  end
  return s
end

---------------------------------------------------------------- where to train next
local ADVICE = {
  Horde = {
    [75]  = "Journeyman: any Cooking trainer (needs 50).",
    [150] = "Expert: Expert Cookbook (needs 125). Wulan, Shadowprey Village, Desolace, 1g. Confirmed in Forever.",
    [225] = "Artisan: quest from Dirge Quikcleave, Gadgetzan, Tanaris (needs 225 and level 35). Classic answer, not confirmed in Forever.",
    [300] = "Top rank. Nothing left to train.",
  },
  Alliance = {
    [75]  = "Journeyman: any Cooking trainer (needs 50).",
    [150] = "Expert: Expert Cookbook (needs 125). Alliance seller not logged in Forever yet.",
    [225] = "Artisan: quest from Dirge Quikcleave, Gadgetzan, Tanaris (needs 225 and level 35). Classic answer, not confirmed in Forever.",
    [300] = "Top rank. Nothing left to train.",
  },
}
local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return (f == "Alliance" or f == "Horde") and f or "Horde"
end

function ns.SkillInfo()
  local rank, mod, max = Skill()
  local info = { rank = rank, mod = mod, max = max }
  if not rank then return info end
  local c = CharRec()
  info.capped = max and rank >= max and max < 300
  info.faction = Faction()
  info.advice = max and ADVICE[info.faction][max]
  info.sinceUp = c.sinceUp or 0
  local log = c.skillLog or {}
  local n, sum = 0, 0
  for i = #log, math.max(1, #log - 9), -1 do
    if (log[i].c or 0) > 0 then n, sum = n + 1, sum + log[i].c end
  end
  if session.ups > 0 then info.cpp = session.cooks / session.ups elseif n > 0 then info.cpp = sum / n end
  return info
end

local function OnCooked(r)
  local c = CharRec()
  c.log = c.log or {}
  local e = c.log[r.name] or { n = 0 }
  local rank = Skill()
  e.n = e.n + 1
  e.lastSeen = Today()
  if rank then e.lo = math.min(e.lo or rank, rank); e.hi = math.max(e.hi or rank, rank) end
  c.log[r.name] = e
  c.sinceUp = (c.sinceUp or 0) + 1
  session.cooks = session.cooks + 1
  session.start = session.start or GetTime()
  session.last = r.name
  if ns.OnChange then ns.OnChange() end
end

function ns.ResetLog()
  local c = CharRec()
  c.log = {}
  say("Cook log cleared.")
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- tooltips
-- ingredient: which of your recipes use it (and their color); recipe item: learned or not, gray at
local usedBy = {}
local function IndexUses()
  wipe(usedBy)
  for _, r in pairs(CharRec().recipes) do
    for _, g in ipairs(r.reagents or {}) do
      if g.id then usedBy[g.id] = usedBy[g.id] or {}; table.insert(usedBy[g.id], r) end
    end
  end
  -- learned first, sorted once here instead of on every tooltip
  for _, list in pairs(usedBy) do
    table.sort(list, function(a, b)
      if (a.learned and 1 or 0) ~= (b.learned and 1 or 0) then return a.learned and true or false end
      return (a.name or "") < (b.name or "")
    end)
  end
end

local function ItemTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.faCookDone then return end
  local name, link = tt:GetItem()
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return end
  -- most items are nothing to us: check the cheap lookups before reading the skill
  local recipes = CharRec().recipes
  -- "Recipe: Rockscale Cod"
  local rname = name and name:match("^Recipe: (.+)$")
  local uses = usedBy[id]
  if not (rname and recipes[rname]) and not (uses and #uses > 0) then return end
  if not ns.Knows() then return end
  local skill = Skill()
  if rname and recipes[rname] then
    tt.faCookDone = true
    local r = recipes[rname]
    tt:AddLine(" ")
    ForeverArtisan.TipLine(tt, ("|cffd4a94eCooking|r  %s%s|r%s"):format(r.learned and GREEN or YELLOW, r.learned and "You know this recipe" or "Not learned yet",
      r.grayAt and (GRAY .. "  ·  gray at " .. r.grayAt .. "|r") or ""))
    tt:Show()
    return
  end
  tt.faCookDone = true
  tt:AddLine(" ")
  ForeverArtisan.TipLine(tt, "|cffd4a94eCooking:|r used in")
  local shown = 0
  for _, r in ipairs(uses) do
    if shown >= 3 then break end
    local c = ns.ColorFor(r, skill)
    tt:AddLine("  " .. ns.COLOR_CODE[c] .. r.name .. "|r" .. (r.learned and "" or (GRAY .. "  (not learned)|r")))
    shown = shown + 1
  end
  if #uses > 3 then tt:AddLine(GRAY .. "  +" .. (#uses - 3) .. " more|r") end
  tt:Show()
end

local function HookTooltips()
  local function clear(self) self.faCookDone = nil end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
      if tt == GameTooltip or tt == ItemRefTooltip then pcall(ItemTip, tt) end
    end)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      tt:HookScript("OnTooltipSetItem", function(self) pcall(ItemTip, self) end)
    end
  end
  GameTooltip:HookScript("OnTooltipCleared", clear)
  ItemRefTooltip:HookScript("OnTooltipCleared", clear)
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "TRADE_SKILL_SHOW",
  "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "UNIT_SPELLCAST_SUCCEEDED",
  "CHAT_MSG_SKILL", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

local scanToken = 0
local function ScanSoon()
  scanToken = scanToken + 1
  local tok = scanToken
  if C_Timer then
    -- read twice: some windows fill their list a moment after they open
    -- read twice only when needed: the list can fill a moment after the window opens
    local got = false
    C_Timer.After(0.5, function() if tok == scanToken then local ok, r = pcall(Scan); got = ok and r == true; IndexUses() end end)
    C_Timer.After(2.0, function()
      if tok ~= scanToken then return end
      local T = C_TradeSkillUI
      local ids = T and T.GetAllRecipeIDs and Try(T.GetAllRecipeIDs)
      if not got or (type(ids) == "table" and #ids ~= (ns.lastIdCount or 0)) then pcall(Scan); IndexUses() end
    end)
  else
    pcall(Scan); IndexUses()
  end
end

-- Forever's newer profession window doesn't always send the trade skill events: also read when it shows.
local hookedFrames = {}
local function HookFrames()
  for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }) do
    local f = _G[name]
    if f and f.HookScript and not hookedFrames[name] then
      hookedFrames[name] = true
      f:HookScript("OnShow", ScanSoon)
      if f.IsShown and f:IsShown() then ScanSoon() end
    end
  end
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
  if e == "ADDON_LOADED" and a1 == ADDON then
    ForeverArtisanCookingDB = ForeverArtisanCookingDB or {}
    db = ForeverArtisanCookingDB
    db.version = ForeverArtisan.Version()
    db.settings = db.settings or {}
    if db.settings.tooltips == nil then db.settings.tooltips = true end
    if db.settings.verbose == nil then db.settings.verbose = false end
    HookFrames()
    return
  end
  if e == "ADDON_LOADED" then HookFrames() return end
  if not db then return end
  if e == "PLAYER_LOGIN" then
    HookTooltips(); HookFrames()
  elseif e == "PLAYER_ENTERING_WORLD" then
    Skill(); IndexRecipes(); IndexUses()
  elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_LIST_UPDATE" or e == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    ScanSoon()
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    local r = a3 and recipeBySpell[a3]
    if r then OnCooked(r) end
  elseif e == "CHAT_MSG_SKILL" then
    if type(a1) == "string" and a1:find("Cooking", 1, true) then
      local n = tonumber(a1:match("(%d+)%.?%s*$")) or tonumber(a1:match("(%d+)"))
      if n then
        local c = CharRec()
        c.skill = n
        session.ups = session.ups + 1
        c.skillLog = c.skillLog or {}
        c.skillLog[#c.skillLog + 1] = { s = n, c = c.sinceUp or 0, d = Today(), t = time() }
        if #c.skillLog > 500 then table.remove(c.skillLog, 1) end
        c.sinceUp = 0
        if ns.OnChange then ns.OnChange() end
      end
    end
  elseif e == "SKILL_LINES_CHANGED" then
    Skill()
  elseif e == "BAG_UPDATE_DELAYED" then
    if ns.OnChange then ns.OnChange() end
  end
end)

---------------------------------------------------------------- slash
SLASH_FACOOK1 = "/facook"
SlashCmdList.FACOOK = function(msg)
  if not db then return end
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif not ns.Knows() then
    say("You haven't learned Cooking on this character.")
  elseif not ns.HasRecipes() then
    say("Open your Cooking window once so I can read your recipes.")
  elseif cmd == "next" or cmd == "now" then
    local list, skill = ns.CookNow()
    if #list == 0 then say(("Skill %d. None of your recipes give skill-ups. Learn new ones or train."):format(skill or 0)) return end
    say(("Skill %d. Best cooks right now:"):format(skill))
    for i = 1, math.min(6, #list) do
      local e = list[i]
      say(("  %s%s|r  %s"):format(ns.COLOR_CODE[e.color], e.r.name,
        e.make > 0 and (GREEN .. "can make " .. e.make .. "|r") or (GRAY .. "missing ingredients|r")))
    end
  elseif cmd == "plan" or cmd == "shop" then
    local steps, shopping, stuck, target = ns.Plan(tonumber(rest))
    say(("Plan to %d:"):format(target or 0))
    local info = ns.SkillInfo()
    if info.capped and (target or 0) > info.max then
      say(RED .. ("Capped at %d. Train the next rank first; the plan past %d won't count until you do.|r"):format(info.max, info.max))
    end
    for _, st in ipairs(steps) do say(("  %s  x%d  %s(%d-%d)|r"):format(st.r.name, st.cooks, GRAY, st.from, st.to)) end
    if stuck then say(YELLOW .. ("Your recipes run out at %d. Learn new recipes to go further.|r"):format(stuck)) end
    for _, e in ipairs(shopping) do
      local short = e.need - e.have
      say(("  %s%s|r  %d/%d  %s%s|r"):format(short > 0 and YELLOW or GREEN, e.name, math.min(e.have, e.need), e.need, GRAY, e.source))
    end
  elseif cmd == "tooltips" then
    db.settings.tooltips = not db.settings.tooltips
    say("Cooking tooltip lines " .. (db.settings.tooltips and "on." or "off."))
  elseif cmd == "reset" and rest:lower() == "confirm" then
    ns.ResetLog()
  else
    local i = ns.SkillInfo()
    local n, learned = 0, 0
    for _, r in pairs(CharRec().recipes) do n = n + 1; if r.learned then learned = learned + 1 end end
    say(("Skill: %s  ·  %d recipes read, %d learned"):format(i.rank and (i.rank .. (i.max and ("/" .. i.max) or "")) or "?", n, learned))
    say("Commands: /fa cook (window), next, plan [skill], tooltips, reset confirm")
  end
end

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(ev)
