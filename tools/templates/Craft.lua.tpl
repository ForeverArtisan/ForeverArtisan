-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: @@NAME@@
-- Reads your recipes from the @@NAME@@ window, shows what you can make right now for skill-ups,
-- plans the crafts to reach a target skill with a shopping list (bags, vendors, your gathering
-- logs), crafts in-between materials (@@SUBEXAMPLE@@) instead of buying them, logs what you make,
-- tells you where the next rank is trained, and adds @@NAME@@ lines to material tooltips.
-- Built on the same engine as First Aid; tools/build_crafts.py writes this file from a template.
local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_@@ID@@"
ns = ns or {}

local GREEN, YELLOW, RED, GRAY = "|cff40ff40", "|cffffff00", "|cffff4040", "|cff9d9d9d"
local GOLD = "|cffd4a94e"
local PROF = "@@NAME@@"
local SKILL_LINE = @@LINE@@
-- recipes the plan never picks (cooldowns make them useless for leveling)
local SKIP_IN_PLAN = @@SKIP@@

local db
local say = ForeverArtisan.Printer(PROF)
ns.say = say
ns.DB = function() return db end

local function Today() return date("%Y-%m-%d") end

---------------------------------------------------------------- items
local function ItemName(id, fallback)
  if not id then return fallback or "?" end
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local n = f and f(id)
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

-- item class / subclass (Trade Goods 7: 5 cloth, 6 leather, 7 metal & stone, 9 herb)
local function ItemKind(id)
  local InstantAPI = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not (id and InstantAPI) then return end
  local ok, _, _, _, _, _, classID, subID = pcall(InstantAPI, id)
  if ok then return classID, subID end
end

---------------------------------------------------------------- per character
local function CharRec()
  local key = (UnitName("player") or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "?")
  db.chars = db.chars or {}
  local c = db.chars[key]
  if not c then c = { recipes = {} }; db.chars[key] = c end
  c.recipes = c.recipes or {}
  return c
end
ns.CharRec = CharRec

---------------------------------------------------------------- skill
local function IsProfName(n) return n == PROF end

local function SkillLive()
  if GetProfessions and GetProfessionInfo then
    local got = (function(...) return { n = select("#", ...), ... } end)(pcall(GetProfessions))
    if got[1] then
      for i = 2, got.n do
        local idx = got[i]
        if idx then
          local name, _, rank, maxr, _, _, line, mod = GetProfessionInfo(idx)
          if rank and (line == SKILL_LINE or IsProfName(name)) then return rank, mod, maxr end
        end
      end
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, SKILL_LINE)
    if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
      return info.skillLevel, info.skillModifier, info.maxSkillLevel
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod, maxr = GetSkillLineInfo(i)
      if not header and IsProfName(name) and rank then return rank, mod, maxr end
    end
  end
end

local function Skill()
  local r, m, mx = SkillLive()
  if not db then return r, m, mx end
  local c = CharRec()
  if r then c.skill = r; if mx and mx > 0 then c.skillMax = mx end; return r, m, mx or c.skillMax end
  -- the game's list loaded without this profession: not learned (or unlearned), so drop the old value
  if ForeverArtisan.ProfessionListLoaded and ForeverArtisan.ProfessionListLoaded() then c.skill = nil; return nil end
  return c.skill, nil, c.skillMax
end
ns.Skill = Skill

function ns.Knows() return Skill() ~= nil end

---------------------------------------------------------------- recipe colors
-- Forever reports the skill where a recipe turns gray. The live color from your last window scan
-- is used first; otherwise green is guessed 20 below gray and yellow 40 below.
-- Older windows (the Classic Craft window Enchanting uses) give only today's color, not the gray
-- level. Then the gray level is estimated from that color so plans still work past today's skill.
local GRAY_GUESS = { orange = 45, yellow = 30, green = 10, gray = 0 }
local function GrayAt(r)
  if r.grayAt then return r.grayAt end
  local g = r.color and r.scanSkill and GRAY_GUESS[r.color]
  return g and (r.scanSkill + g) or nil
end
ns.GrayAt = GrayAt

function ns.ColorFor(r, skill)
  if not r then return "unknown" end
  if not r.learned then return "unlearned" end
  if not skill then return "unknown" end
  if r.scanSkill == skill and r.color then return r.color end
  local gray = GrayAt(r)
  if gray then
    if skill >= gray then return "gray" end
    if skill >= gray - 20 then return "green" end
    if skill >= gray - 40 then return "yellow" end
    return "orange"
  end
  return "unknown"
end

-- chance that one craft gives a skill-up
function ns.Chance(r, skill)
  local c = ns.ColorFor(r, skill)
  if c == "orange" then return 1 end
  local gray = GrayAt(r)
  if (c == "yellow" or c == "green") and gray then
    return math.max(0.05, math.min(1, (gray - skill) / 40))
  end
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

---------------------------------------------------------------- tools and stations
-- Some recipes need a tool in your bags (Blacksmith Hammer, Arclight Spanner, a runed rod) or a
-- station you stand next to (anvil, forge). Read from the window and kept on the recipe as r.tools.
local function IsStation(name)
  local n = (name or ""):lower()
  return n:find("anvil", 1, true) or n:find("forge", 1, true) or n:find("moonwell", 1, true)
    or n:find("cooking fire", 1, true) or n:find("campfire", 1, true)
end
local function CleanTool(s)
  s = (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*[Rr]equires:?%s*", "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
-- from "name, has, name, has, ..." (GetTradeSkillTools, GetCraftSpellFocus)
local function ToolsFromPairs(...)
  local out = {}
  for k = 1, select("#", ...), 2 do
    local name = select(k, ...)
    if type(name) == "string" and name ~= "" then
      name = CleanTool(name)
      out[#out + 1] = { name = name, station = IsStation(name) and true or nil }
    end
  end
  return #out > 0 and out or nil
end
-- from one string, "Blacksmith Hammer, Anvil" (C_TradeSkillUI.GetRecipeTools)
local function ToolsFromString(str)
  if type(str) ~= "string" or str == "" then return end
  local out = {}
  for part in str:gmatch("[^,]+") do
    local name = CleanTool(part)
    if name ~= "" then out[#out + 1] = { name = name, station = IsStation(name) and true or nil } end
  end
  return #out > 0 and out or nil
end

-- tools (not stations) for this recipe that aren't in your bags
function ns.MissingTools(r)
  local out = {}
  for _, t in ipairs(r and r.tools or {}) do
    if not t.station and Count(t.name) == 0 then out[#out + 1] = t.name end
  end
  return out
end
-- stations this recipe is made at
function ns.Stations(r)
  local out = {}
  for _, t in ipairs(r and r.tools or {}) do if t.station then out[#out + 1] = t.name end end
  return out
end

---------------------------------------------------------------- reading the @@NAME@@ window
-- recipe group names that only this profession uses (a last resort when the game won't say)
local GROUP_WORDS = @@GROUPS@@
local function IsProfGroup(g)
  if not g then return false end
  g = g:lower()
  for _, w in ipairs(GROUP_WORDS) do if g:find(w, 1, true) then return true end end
  return false
end

local function Try(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

-- Is the open profession window ours? Ask the game first (cheap); nil = it can't say.
local function QuickOurs(ids)
  local T = C_TradeSkillUI
  if T.GetTradeSkillLineForRecipe and ids[1] then
    local a, b, c = Try(T.GetTradeSkillLineForRecipe, ids[1])
    if a or b or c then return a == SKILL_LINE or c == SKILL_LINE or IsProfName(b) end
  end
  if T.GetBaseProfessionInfo then
    local info = Try(T.GetBaseProfessionInfo)
    if type(info) == "table" and (info.professionID or info.professionName) then
      return info.professionID == SKILL_LINE or IsProfName(info.professionName)
    end
  end
end

-- otherwise look at the recipes' groups
local function WindowIsOurs(ids, infos)
  local quick = QuickOurs(ids)
  if quick ~= nil then return quick end
  local ours = 0
  for _, ri in ipairs(infos) do if IsProfGroup(ri.group) then ours = ours + 1 end end
  return ours >= 3
end

local function ScanModern()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs) then return end
  local ids = Try(T.GetAllRecipeIDs)
  if type(ids) ~= "table" or #ids == 0 then return end
  -- another profession's window: stop before reading every recipe (all eight modules hear the same event)
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
  if not WindowIsOurs(ids, infos) then return end
  local rank = Skill()
  local known = CharRec().recipes
  local out = {}
  for _, e in ipairs(infos) do
    local ri = e.ri
    local r = { id = e.id, name = ri.name, learned = ri.learned and true or false, group = e.group,
                grayAt = (ri.maxTrivialLevel and ri.maxTrivialLevel > 0) and ri.maxTrivialLevel or nil,
                ups = (ri.numSkillUps and ri.numSkillUps > 1) and ri.numSkillUps or nil,
                color = ri.learned and DIFF[ri.relativeDifficulty] or nil, scanSkill = rank, reagents = {} }
    -- reagents, tools and the made item don't change between scans: keep them instead of asking again
    local old = known[ri.name]
    if old and old.id == e.id and old.reagents and #old.reagents > 0 then
      r.reagents, r.itemId, r.makes, r.tools = old.reagents, old.itemId, old.makes, old.tools
    else
    if T.GetRecipeTools then r.tools = ToolsFromString((Try(T.GetRecipeTools, e.id))) end
    -- newer windows list tools as requirements ("Requires: Runed Copper Rod")
    if not r.tools and T.GetRecipeRequirements then
      local req = Try(T.GetRecipeRequirements, e.id)
      if type(req) == "table" then
        local out = {}
        for _, q in ipairs(req) do
          local name = type(q) == "table" and q.name and CleanTool(q.name)
          if name and name ~= "" then out[#out + 1] = { name = name, station = IsStation(name) and true or nil } end
        end
        if #out > 0 then r.tools = out end
      end
    end
    local sch = T.GetRecipeSchematic and Try(T.GetRecipeSchematic, e.id, false)
    if type(sch) == "table" then
      r.itemId = sch.outputItemID
      if sch.quantityMin and sch.quantityMin > 1 then r.makes = sch.quantityMin end
      for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        if first and first.itemID then
          r.reagents[#r.reagents + 1] = { id = first.itemID, n = slot.quantityRequired or 1, name = ItemName(first.itemID) }
        end
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
  if not IsProfName(name) then return end
  local rank = Skill()
  local out, header = {}, nil
  for i = 1, GetNumTradeSkills() do
    local rname, kind = GetTradeSkillInfo(i)
    if kind == "header" then header = rname
    elseif rname then
      local r = { name = rname, learned = true, group = header, color = OLD_KIND[kind], scanSkill = rank, reagents = {} }
      if GetTradeSkillTools then r.tools = ToolsFromPairs(GetTradeSkillTools(i)) end
      local rl = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
      r.id = rl and tonumber(rl:match("enchant:(%d+)")) or nil
      local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
      r.itemId = link and tonumber(link:match("item:(%d+)"))
      local made = GetTradeSkillNumMade and GetTradeSkillNumMade(i)
      if made and made > 1 then r.makes = made end
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

-- Classic's Enchanting uses the older Craft window (CraftFrame) instead of the trade skill one.
local function ScanCraft()
  if not (GetNumCrafts and GetCraftInfo) then return end
  local name = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()) or (GetCraftName and GetCraftName())
  if not IsProfName(name) then return end
  local rank = Skill()
  local out, header = {}, nil
  for i = 1, (GetNumCrafts() or 0) do
    local cname, _, kind = GetCraftInfo(i)
    if kind == "header" then header = cname
    elseif cname then
      local r = { name = cname, learned = true, group = header, color = OLD_KIND[kind], scanSkill = rank, reagents = {} }
      if GetCraftSpellFocus then r.tools = ToolsFromPairs(GetCraftSpellFocus(i)) end
      local link = GetCraftItemLink and GetCraftItemLink(i)
      if link then
        r.id = tonumber(link:match("enchant:(%d+)")) or nil
        r.itemId = tonumber(link:match("item:(%d+)")) or nil
      end
      for j = 1, ((GetCraftNumReagents and GetCraftNumReagents(i)) or 0) do
        local n, _, cnt = GetCraftReagentInfo(i, j)
        local rl = GetCraftReagentItemLink and GetCraftReagentItemLink(i, j)
        r.reagents[#r.reagents + 1] = { id = rl and tonumber(rl:match("item:(%d+)")), n = cnt or 1, name = n }
      end
      out[cname] = r
    end
  end
  return out
end

local recipeBySpell = {}
local function IndexRecipes()
  wipe(recipeBySpell)
  for _, r in pairs(CharRec().recipes) do if r.id then recipeBySpell[r.id] = r end end
end

local function Scan()
  if not db then return end
  local got = ScanModern() or ScanOld() or ScanCraft()
  if not got or next(got) == nil then return end
  local c, n, learned = CharRec(), 0, 0
  for name, r in pairs(got) do
    n = n + 1
    if r.learned then learned = learned + 1 end
    c.recipes[name] = r
  end
  local first = not c.scanned
  c.scanned = time()
  IndexRecipes()
  if first then say(("Read your %s window: %d recipes, %d learned."):format(PROF, n, learned)) end
  if ns.OnChange then ns.OnChange() end
  return true
end

function ns.HasRecipes() return db and next(CharRec().recipes) ~= nil end

---------------------------------------------------------------- where to get things
-- Trade Contacts first (vendors you've met), then your Herbalism / Skinning / Mining / Fishing logs.
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

-- short text: where to get this material
function ns.SourceFor(id, name)
  local v = VendorFor(name)
  if v then return "Vendor: " .. v end
  local hint = ForeverArtisan and ForeverArtisan.VendorHint and ForeverArtisan.VendorHint(name or id)
  if hint then return "Vendor: " .. hint .. " (none in your Trade Contacts yet)" end
  local w = BestLogged(ForeverArtisanHerbalismDB, id)
  if w then return "Herb: " .. w .. ", from your Herbalism log" end
  w = BestLogged(ForeverArtisanSkinningDB, id)
  if w then return "Skin: " .. w .. ", from your Skinning log" end
  w = BestLogged(ForeverArtisanMiningDB, id)
  if w then return "Mine: " .. w .. ", from your Mining log" end
  w = BestLogged(ForeverArtisanFishingDB, id)
  if w then return "Fish: " .. w .. ", from your Fishing log" end
  local drop = ForeverArtisan.MaterialWhere and ForeverArtisan.MaterialWhere(id)
  if drop then return drop end
  local class, sub = ItemKind(id)
  name = name or ""
  if (class == 7 and sub == 9) then
    return "Herb: not in your Herbalism log yet. Gather it or check the Auction House."
  end
  if (class == 7 and sub == 6) or name:find("Hide$") or name:find("Leather$") or name:find("Scale$") then
    return "Leather: skin beasts. Not in your Skinning log yet."
  end
  if name:find("Cloth$") then return "Cloth: drops from humanoid mobs" end
  if name:find(" Ore$") then return "Ore: mine it. Not in your Mining log yet." end
  if name:find(" Bar$") then return "Bar: smelt ore at a forge (Mining), or the Auction House" end
  if name:find("^Rough Stone$") or name:find("^Coarse Stone$") or name:find("^Heavy Stone$")
    or name:find("^Solid Stone$") or name:find("^Dense Stone$") then
    return "Stone: comes from mining veins. Not in your Mining log yet."
  end
  if name:find("^Runed .+ Rod$") then return "Made with Enchanting (the " .. name .. " recipe)" end
  if name:find(" Dust$") or name:find(" Essence$") or name:find(" Shard$") then
    return "Disenchant green (uncommon) gear, or the Auction House"
  end
  if (class == 7 and sub == 7) then return "Mining: ore, bars or stone. Mine it or check the Auction House." end
  return "Drops from mobs, or the Auction House"
end

-- where to buy an unlearned recipe, if Trade Contacts knows
local RECIPE_PREFIXES = @@PREFIXES@@
ns.RecipePrefixes = RECIPE_PREFIXES
function ns.RecipeSource(name)
  for _, pre in ipairs(RECIPE_PREFIXES) do
    local v, price = VendorFor(pre .. name)
    if v then
      local money = price and GetCoinTextureString and GetCoinTextureString(price) or ""
      return v .. (money ~= "" and ("  " .. money) or "")
    end
  end
end

---------------------------------------------------------------- make now / plan
function ns.Makeable(r)
  if not r.reagents or #r.reagents == 0 then return 0 end
  local n
  for _, g in ipairs(r.reagents) do
    local can = math.floor(Count(g.id) / math.max(1, g.n or 1))
    n = (not n or can < n) and can or n
  end
  return n or 0
end

local function Skipped(r) return SKIP_IN_PLAN and r.name and r.name:find(SKIP_IN_PLAN) ~= nil end
ns.Skipped = Skipped

-- learned recipes that still give skill-ups, best first
function ns.MakeNow()
  local skill = (function() local r, m = Skill(); return r and (r + (m or 0)) end)()
  local out = {}
  for _, r in pairs(CharRec().recipes) do
    local c = ns.ColorFor(r, skill)
    if (c == "orange" or c == "yellow" or c == "green") and not Skipped(r) then
      local missing = ns.MissingTools(r)
      out[#out + 1] = { r = r, color = c, chance = ns.Chance(r, skill), make = #missing > 0 and 0 or ns.Makeable(r),
        missing = missing, stations = ns.Stations(r) }
    end
  end
  table.sort(out, function(a, b)
    if (a.make > 0) ~= (b.make > 0) then return a.make > 0 end
    if a.chance ~= b.chance then return a.chance > b.chance end
    return (a.r.grayAt or 0) > (b.r.grayAt or 0)
  end)
  return out, skill
end

-- Plan crafts from your skill to a target, one craft at a time. At each step it makes the best
-- learned recipe; materials one of your recipes makes (cured hides, Light Leather, potions for
-- elixirs...) are crafted first when you're short, and those crafts give skill-ups too, so they
-- count toward the target. Skill is tracked as an expected value (a 50% craft adds half a point).
-- Returns steps { r, crafts, from, to, sub = { [recipe] = n } },
-- shopping { id, name, need, have, source, craft, via }, stuckAt, target, max
local PLAN_LIMIT = 6000 -- crafts; stops a plan built on a nearly-gray recipe from running forever
function ns.Plan(target)
  local skill = Skill()
  if not skill then return {}, {}, nil end
  local _, _, maxr = Skill()
  target = math.min(tonumber(target) or (skill + 25), 300)
  local learned, makes = {}, {}
  for _, r in pairs(CharRec().recipes) do
    if r.learned then
      if not Skipped(r) then learned[#learned + 1] = r end
      -- a material counts as "craft it yourself" only if you have the tools for it now
      -- (Dust to Motes needs the Runed Copper Rod, so until you have one, Motes are bought)
      if r.itemId and not makes[r.itemId] and #ns.MissingTools(r) == 0 then makes[r.itemId] = r end
    end
  end

  local stock, used, crafted, names = {}, {}, {}, {}
  local function Have(id) if stock[id] == nil then stock[id] = Count(id) end; return stock[id] end
  local s, total, cur = skill, 0, nil
  local Craft
  -- make sure n of id are on hand, crafting the shortfall when you know a recipe for it
  local function Gather(id, n, depth)
    local via = makes[id]
    local short = n - Have(id)
    if short > 0 and via and depth < 3 then
      for _ = 1, math.ceil(short / (via.makes or 1)) do Craft(via, depth + 1) end
    end
  end
  Craft = function(r, depth)
    for _, g in ipairs(r.reagents or {}) do
      if g.id then
        names[g.id] = names[g.id] or g.name
        Gather(g.id, g.n or 1, depth)
        stock[g.id] = Have(g.id) - (g.n or 1)
        used[g.id] = (used[g.id] or 0) + (g.n or 1)
      end
    end
    s = s + ns.Chance(r, math.floor(s)) * (r.ups or 1)
    total = total + 1
    if r.itemId then stock[r.itemId] = Have(r.itemId) + (r.makes or 1) end
    if depth > 0 then
      if r.itemId then crafted[r.itemId] = (crafted[r.itemId] or 0) + 1 end
      cur.sub[r] = (cur.sub[r] or 0) + 1
    end
  end

  -- materials per craft, counting through what you'd make yourself (3 scraps per Light Leather)
  local costMemo = {}
  local function Cost(r, depth)
    if costMemo[r] then return costMemo[r] end
    local n = 0
    for _, g in ipairs(r.reagents or {}) do
      local via = g.id and makes[g.id]
      local each = (via and via ~= r and (depth or 0) < 3) and (Cost(via, (depth or 0) + 1) / (via.makes or 1)) or 1
      n = n + (g.n or 1) * each
    end
    costMemo[r] = n
    return n
  end

  -- what you can make from your bags doesn't change while planning: count once, not on every pass
  local canMake = {}
  for _, r in ipairs(learned) do canMake[r] = ns.Makeable(r) > 0 end

  local steps, stuck = {}, nil
  while math.floor(s) < target and total < PLAN_LIMIT do
    local at = math.floor(s)
    local best, bestScore, bestCost
    for _, r in ipairs(learned) do
      local ch = ns.Chance(r, at)
      if ch > 0 then
        -- prefer the best skill-up chance, but favor recipes you can already make from your bags;
        -- on a tie, the one that uses fewer materials (Handstitched Cloak over the Vest)
        local score = ch + (canMake[r] and 0.15 or 0)
        local cost = Cost(r)
        if not best or score > bestScore + 0.001
          or (math.abs(score - bestScore) <= 0.001 and cost < bestCost) then
          best, bestScore, bestCost = r, score, cost
        end
      end
    end
    if not best then stuck = at; break end
    if not cur or cur.r ~= best then
      cur = { r = best, crafts = 0, from = at, to = at, sub = {} }
      steps[#steps + 1] = cur
    end
    Craft(best, 0)
    cur.crafts = cur.crafts + 1
    cur.to = math.floor(s)
  end
  if not stuck and math.floor(s) < target then stuck = math.floor(s) end

  local shopping = {}
  -- tools the planned crafts need (not stations): one each, kept in your bags
  local tools = {}
  local function NeedTools(r)
    for _, t in ipairs(r.tools or {}) do
      if not t.station and not tools[t.name] then
        tools[t.name] = true
        local have = math.min(1, Count(t.name))
        shopping[#shopping + 1] = { name = t.name, need = 1, have = have, tool = true,
          source = "Tool: keep it in your bags while you craft. " .. ns.SourceFor(nil, t.name) }
      end
    end
  end
  for _, st in ipairs(steps) do
    NeedTools(st.r)
    for sr in pairs(st.sub or {}) do NeedTools(sr) end
  end
  for id, n in pairs(used) do
    local e = { id = id, name = ItemName(id, names[id]), need = n, have = Count(id) }
    if crafted[id] then
      e.craft, e.via = crafted[id], makes[id]
      local parts = {}
      for _, g in ipairs(e.via.reagents or {}) do parts[#parts + 1] = ItemName(g.id, g.name) end
      e.source = ("Craft %d yourself: %s (%s)"):format(e.craft, e.via.name, table.concat(parts, " + "))
    else
      e.source = ns.SourceFor(id, e.name)
    end
    shopping[#shopping + 1] = e
  end
  table.sort(shopping, function(a, b)
    if (a.tool and a.have < 1) ~= (b.tool and b.have < 1) then return a.tool and a.have < 1 end
    local sa, sb = a.need - a.have, b.need - b.have
    if (sa > 0) ~= (sb > 0) then return sa > 0 end
    if (a.craft ~= nil) ~= (b.craft ~= nil) then return a.craft ~= nil end
    return (a.name or "") < (b.name or "")
  end)
  return steps, shopping, stuck, target, maxr
end

---------------------------------------------------------------- where to learn it
-- Not learned yet: the nearest trainer in your Trade Contacts whose list includes the
-- Apprentice rank (an Expert-only trainer is skipped). Nil when you haven't met one.
function ns.LearnFrom()
  local V = ForeverArtisan and ForeverArtisan.Vendors
  if not (V and V.search) then return end
  local prof = PROF:lower()
  for _, h in ipairs(V.search(prof) or {}) do
    for _, r in ipairs(h.ranks or {}) do
      local n = r:lower()
      if n:find("apprentice", 1, true) and n:find(prof, 1, true) then return h.npc end
    end
  end
  -- no Apprentice trainer on file: the closest trainer for it you've met or passed
  if V.nearestTrainer then return V.nearestTrainer(PROF) end
end

---------------------------------------------------------------- session + craft log
local session = { crafts = 0, ups = 0, start = nil, last = nil }
ns.session = session

function ns.SessionInfo()
  local s = { crafts = session.crafts, ups = session.ups, last = session.last }
  if session.start then
    s.mins = (GetTime() - session.start) / 60
    if s.mins >= 1 then s.perHour = math.floor(session.crafts * 60 / s.mins + 0.5) end
  end
  return s
end

---------------------------------------------------------------- where to train next
-- A trainer you've met (Trade Contacts) wins. Otherwise the Classic answer, marked as such.
local RANK_AT = { [75] = { "Journeyman", 50, 10 }, [150] = { "Expert", 125, 20 }, [225] = { "Artisan", 200, 35 } }
local ADVICE = {
@@ADVICE@@
}
local function Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return (f == "Alliance" or f == "Horde") and f or "Horde"
end

local function TrainerFor(rankName)
  local V = ForeverArtisan and ForeverArtisan.Vendors
  if not (V and V.hitsForLink) then return end
  for _, key in ipairs({ PROF .. " (" .. rankName .. ")", rankName .. " " .. PROF }) do
    local hits = V.hitsForLink(nil, key)
    local h = hits and hits[1]
    if h then return h.npc.n .. ", " .. (h.npc.s or h.npc.z or "?") end
  end
end
ns.TrainerFor = TrainerFor

function ns.SkillInfo()
  local rank, mod, max = Skill()
  local info = { rank = rank, mod = mod, max = max }
  if not rank then return info end
  local c = CharRec()
  info.capped = max and rank >= max and max < 300
  info.faction = Faction()
  local next = max and RANK_AT[max]
  local met = next and TrainerFor(next[1])
  if met then
    info.advice = ("%s: %s, from your Trade Contacts (needs %d, level %d)."):format(next[1], met, next[2], next[3])
  else
    info.advice = max and ADVICE[info.faction][max]
  end
  info.sinceUp = c.sinceUp or 0
  local log = c.skillLog or {}
  local n, sum = 0, 0
  for i = #log, math.max(1, #log - 9), -1 do
    if (log[i].c or 0) > 0 then n, sum = n + 1, sum + log[i].c end
  end
  if session.ups > 0 then info.cpp = session.crafts / session.ups elseif n > 0 then info.cpp = sum / n end
  return info
end

local function OnMade(r)
  local c = CharRec()
  c.log = c.log or {}
  local e = c.log[r.name] or { n = 0 }
  local rank = Skill()
  e.n = e.n + 1
  e.lastSeen = Today()
  if rank then e.lo = math.min(e.lo or rank, rank); e.hi = math.max(e.hi or rank, rank) end
  c.log[r.name] = e
  c.sinceUp = (c.sinceUp or 0) + 1
  session.crafts = session.crafts + 1
  session.start = session.start or GetTime()
  session.last = r.name
  if ns.OnChange then ns.OnChange() end
end

function ns.ResetLog()
  local c = CharRec()
  c.log = {}
  say("Craft log cleared.")
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- tooltips
-- material: which of your recipes use it (and their color); recipe item: learned or not, gray at
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

local function RecipeNameFromItem(name)
  if not name then return end
  for _, pre in ipairs(RECIPE_PREFIXES) do
    if name:sub(1, #pre) == pre then return name:sub(#pre + 1) end
  end
end

local function ItemTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.@@FLAG@@ then return end
  local name, link = tt:GetItem()
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return end
  -- most items are nothing to us: check the cheap lookups before reading the skill
  local recipes = CharRec().recipes
  local rname = RecipeNameFromItem(name)
  local uses = usedBy[id]
  if not (rname and recipes[rname]) and not (uses and #uses > 0) then return end
  if not ns.Knows() then return end
  local skill = Skill()
  if rname and recipes[rname] then
    tt.@@FLAG@@ = true
    local r = recipes[rname]
    tt:AddLine(" ")
    ForeverArtisan.TipLine(tt, ("%s%s|r  %s%s|r%s"):format(GOLD, PROF, r.learned and GREEN or YELLOW, r.learned and "You know this recipe" or "Not learned yet",
      r.grayAt and (GRAY .. "  ·  gray at " .. r.grayAt .. "|r") or ""))
    tt:Show()
    return
  end
  tt.@@FLAG@@ = true
  tt:AddLine(" ")
  ForeverArtisan.TipLine(tt, GOLD .. PROF .. ":|r used in")
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
  local function clear(self) self.@@FLAG@@ = nil end
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
  "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "CRAFT_SHOW", "CRAFT_UPDATE", "UNIT_SPELLCAST_SUCCEEDED",
  "CHAT_MSG_SKILL", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

local scanToken = 0
-- a failed read is kept for /@@SLASHCMD@@ debug instead of vanishing (and printed on dev builds)
function ns.SafeScan()
  local ok, err = pcall(Scan)
  ns.lastScan = { t = time(), ok = ok, err = (not ok) and tostring(err) or nil }
  if not ok and ForeverArtisan.IsDev and ForeverArtisan.IsDev() then say("|cffff5555scan error:|r " .. tostring(err)) end
  return ok and err == true
end

-- did the window's list grow since the last read? (it can fill a moment after it opens)
local function ListGrew()
  local T = C_TradeSkillUI
  local ids = T and T.GetAllRecipeIDs and Try(T.GetAllRecipeIDs)
  return type(ids) == "table" and #ids ~= (ns.lastIdCount or 0)
end

local function ScanSoon()
  scanToken = scanToken + 1
  local tok = scanToken
  if C_Timer then
    -- read twice: some windows fill their list a moment after they open
    local got = false
    C_Timer.After(0.5, function() if tok == scanToken then got = ns.SafeScan(); IndexUses() end end)
    C_Timer.After(2.0, function()
      if tok == scanToken and (not got or ListGrew()) then ns.SafeScan(); IndexUses() end
    end)
  else
    ns.SafeScan(); IndexUses()
  end
end

-- Some clients (Forever's newer profession window) don't send the trade skill events every time.
-- Reading when the window itself shows covers them; the frames load on demand, so hook as they appear.
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
    @@DB@@ = @@DB@@ or {}
    db = @@DB@@
    db.version = ForeverArtisan.Version()
    db.settings = db.settings or {}
    if db.settings.tooltips == nil then db.settings.tooltips = true end
    HookFrames()
    return
  end
  if e == "ADDON_LOADED" then HookFrames() return end
  if not db then return end
  if e == "PLAYER_LOGIN" then
    HookTooltips(); HookFrames()
  elseif e == "PLAYER_ENTERING_WORLD" then
    Skill(); IndexRecipes(); IndexUses()
  elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_LIST_UPDATE" or e == "TRADE_SKILL_DATA_SOURCE_CHANGED"
    or e == "CRAFT_SHOW" or e == "CRAFT_UPDATE" then
    ScanSoon()
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    local r = a3 and recipeBySpell[a3]
    if r then OnMade(r) end
  elseif e == "CHAT_MSG_SKILL" then
    if type(a1) == "string" and a1:find(PROF, 1, true) then
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
SLASH_@@SLASH@@1 = "@@SLASHCMD@@"
SlashCmdList.@@SLASH@@ = function(msg)
  if not db then return end
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "debug" then
    -- what was read: last scan, and the tools saved on each learned recipe (reads now if the window is open)
    HookFrames()
    local open = {}
    for name in pairs(hookedFrames) do if _G[name] and _G[name]:IsShown() then open[#open + 1] = name end end
    if #open > 0 then ns.SafeScan() end
    say("window hooks: " .. (next(hookedFrames) and "yes" or "none yet") .. ", open now: " .. (#open > 0 and table.concat(open, ", ") or "none"))
    local ls = ns.lastScan
    say(ls and (("last read %ds ago: %s"):format(time() - ls.t, ls.ok and "ok" or ("|cffff5555error|r " .. (ls.err or "?"))))
      or "no read this session. Open your " .. PROF .. " window.")
    local T = C_TradeSkillUI
    say(("api: tools %s, requirements %s, old %s, craft %s"):format(tostring(T and T.GetRecipeTools ~= nil),
      tostring(T and T.GetRecipeRequirements ~= nil), tostring(GetTradeSkillTools ~= nil), tostring(GetCraftSpellFocus ~= nil)))
    local n = 0
    for name, r in pairs(CharRec().recipes or {}) do
      if r.learned and n < 12 then
        n = n + 1
        local t = {}
        for _, x in ipairs(r.tools or {}) do t[#t + 1] = x.name .. (x.station and " (station)" or "") end
        say(("  %s: id %s, tools %s"):format(name, tostring(r.id), #t > 0 and table.concat(t, ", ") or "none"))
      end
    end
  elseif not ns.Knows() then
    say("You haven't learned " .. PROF .. " on this character.")
  elseif not ns.HasRecipes() then
    say("Open your " .. PROF .. " window once so I can read your recipes.")
  elseif cmd == "next" or cmd == "now" then
    local list, skill = ns.MakeNow()
    if #list == 0 then say(("Skill %d. None of your recipes give skill-ups. Learn new ones or train."):format(skill or 0)) return end
    say(("Skill %d. Best crafts right now:"):format(skill))
    for i = 1, math.min(6, #list) do
      local e = list[i]
      say(("  %s%s|r  %s"):format(ns.COLOR_CODE[e.color], e.r.name,
        (#e.missing > 0 and (RED .. "needs " .. table.concat(e.missing, ", ") .. "|r"))
        or (e.make > 0 and (GREEN .. "can make " .. e.make .. "|r")) or (GRAY .. "missing materials|r")))
    end
  elseif cmd == "plan" or cmd == "shop" then
    local steps, shopping, stuck, target = ns.Plan(tonumber(rest))
    say(("Plan to %d:"):format(target or 0))
    local info = ns.SkillInfo()
    if info.capped and (target or 0) > info.max then
      say(RED .. ("Capped at %d. Train the next rank first; the plan past %d won't count until you do.|r"):format(info.max, info.max))
    end
    for _, st in ipairs(steps) do say(("  %s  x%d  %s(%d-%d)|r"):format(st.r.name, st.crafts, GRAY, st.from, st.to)) end
    if stuck then say(YELLOW .. ("Your recipes run out at %d. Learn new recipes to go further.|r"):format(stuck)) end
    for _, e in ipairs(shopping) do
      local short = e.need - e.have
      say(("  %s%s|r  %d/%d  %s%s|r"):format(short > 0 and YELLOW or GREEN, e.name, math.min(e.have, e.need), e.need, GRAY, e.source))
    end
  elseif cmd == "tooltips" then
    db.settings.tooltips = not db.settings.tooltips
    say(PROF .. " tooltip lines " .. (db.settings.tooltips and "on." or "off."))
  elseif cmd == "reset" and rest:lower() == "confirm" then
    ns.ResetLog()
  else
    local i = ns.SkillInfo()
    local n, learned = 0, 0
    for _, r in pairs(CharRec().recipes) do n = n + 1; if r.learned then learned = learned + 1 end end
    say(("Skill: %s  ·  %d recipes read, %d learned"):format(i.rank and (i.rank .. (i.max and ("/" .. i.max) or "")) or "?", n, learned))
    say("Commands: /fa @@ALIAS@@ (window), next, plan [skill], tooltips, reset confirm")
  end
end

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(ev)
