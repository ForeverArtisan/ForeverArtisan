-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: First Aid
-- Reads your recipes from the First Aid window, shows what you can make right now for skill-ups,
-- plans the crafts to reach a target skill with a shopping list (bags, vendors, your gathering
-- logs), logs what you make, tells you where the next rank is trained, and adds First Aid lines
-- to material tooltips (cloth, herbs, venom sacs...).
local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_FirstAid"
ns = ns or {}

local GREEN, YELLOW, RED, GRAY = "|cff40ff40", "|cffffff00", "|cffff4040", "|cff9d9d9d"
local AID_SKILL_LINE = 129

local db
local say = ForeverArtisan.Printer("First Aid")
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
local function IsAidName(n) return n and (n == "First Aid" or n == (PROFESSIONS_FIRST_AID or "First Aid")) end

local function SkillLive()
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if ok then
      for _, idx in ipairs({ e, a, b, c, d, f }) do
        if idx then
          local name, _, rank, maxr, _, _, line, mod = GetProfessionInfo(idx)
          if rank and (line == AID_SKILL_LINE or IsAidName(name)) then return rank, mod, maxr end
        end
      end
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, AID_SKILL_LINE)
    if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
      return info.skillLevel, info.skillModifier, info.maxSkillLevel
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod, maxr = GetSkillLineInfo(i)
      if not header and IsAidName(name) and rank then return rank, mod, maxr end
    end
  end
end

local function Skill()
  local r, m, mx = SkillLive()
  if not db then return r, m, mx end
  local c = CharRec()
  if r then c.skill = r; if mx and mx > 0 then c.skillMax = mx end; return r, m, mx or c.skillMax end
  return c.skill, nil, c.skillMax
end
ns.Skill = Skill

function ns.Knows() return Skill() ~= nil end

---------------------------------------------------------------- recipe colors
-- Forever reports the skill where a recipe turns gray. First Aid ranges vary by recipe, so the
-- live color from your last window scan is used first; otherwise green is guessed 20 below gray
-- and yellow 40 below.
function ns.ColorFor(r, skill)
  if not r then return "unknown" end
  if not r.learned then return "unlearned" end
  if not skill then return "unknown" end
  -- the color the game showed when you last opened the window at this exact skill wins
  if r.scanSkill == skill and r.color then return r.color end
  if r.grayAt then
    if skill >= r.grayAt then return "gray" end
    if skill >= r.grayAt - 20 then return "green" end
    if skill >= r.grayAt - 40 then return "yellow" end
    return "orange"
  end
  if r.scanSkill == skill and r.color then return r.color end
  return "unknown"
end

-- chance that one craft gives a skill-up
function ns.Chance(r, skill)
  local c = ns.ColorFor(r, skill)
  if c == "orange" then return 1 end
  if (c == "yellow" or c == "green") and r.grayAt then
    return math.max(0.05, math.min(1, (r.grayAt - skill) / 40))
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

---------------------------------------------------------------- reading the First Aid window
local AID_GROUP = { "bandage", "first aid", "anti-venom", "antivenom", "poultice", "tourniquet", "potion", "salve", "toxin" }
local function IsAidGroup(g)
  if not g then return false end
  g = g:lower()
  for _, w in ipairs(AID_GROUP) do if g:find(w, 1, true) then return true end end
  return false
end

local function Try(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "gray" }

-- Is the open profession window First Aid? Ask the game first, then look at the recipes.
local function WindowIsFirstAid(ids, infos)
  local T = C_TradeSkillUI
  if T.GetTradeSkillLineForRecipe and ids[1] then
    local a, b, c = Try(T.GetTradeSkillLineForRecipe, ids[1])
    if a == AID_SKILL_LINE or c == AID_SKILL_LINE or IsAidName(b) then return true end
  end
  if T.GetBaseProfessionInfo then
    local info = Try(T.GetBaseProfessionInfo)
    if type(info) == "table" and (info.professionID == AID_SKILL_LINE or IsAidName(info.professionName)) then return true end
  end
  local aidy = 0
  for _, ri in ipairs(infos) do if IsAidGroup(ri.group) then aidy = aidy + 1 end end
  return aidy >= 3
end

local function ScanModern()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs) then return end
  local ids = Try(T.GetAllRecipeIDs)
  if type(ids) ~= "table" or #ids == 0 then return end
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
  if not WindowIsFirstAid(ids, infos) then return end
  local rank = Skill()
  local out = {}
  for _, e in ipairs(infos) do
    local ri = e.ri
    local r = { id = e.id, name = ri.name, learned = ri.learned and true or false, group = e.group,
                grayAt = (ri.maxTrivialLevel and ri.maxTrivialLevel > 0) and ri.maxTrivialLevel or nil,
                ups = (ri.numSkillUps and ri.numSkillUps > 1) and ri.numSkillUps or nil,
                color = ri.learned and DIFF[ri.relativeDifficulty] or nil, scanSkill = rank, reagents = {} }
    local sch = T.GetRecipeSchematic and Try(T.GetRecipeSchematic, e.id, false)
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
  if not IsAidName(name) then return end
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
    c.recipes[name] = r
  end
  local first = not c.scanned
  c.scanned = time()
  IndexRecipes()
  if first then say(("Read your First Aid window: %d recipes, %d learned."):format(n, learned)) end
  if ns.OnChange then ns.OnChange() end
end

function ns.HasRecipes() return db and next(CharRec().recipes) ~= nil end

---------------------------------------------------------------- where to get things
-- Uses Core's vendor list and your Herbalism / Skinning / Mining / Fishing logs when they're loaded.
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
  if w then return "Herb: " .. w end
  w = BestLogged(ForeverArtisanSkinningDB, id)
  if w then return "Skin: " .. w end
  w = BestLogged(ForeverArtisanMiningDB, id)
  if w then return "Mine: " .. w end
  w = BestLogged(ForeverArtisanFishingDB, id)
  if w then return "Fish: " .. w end
  if name and name:find("Cloth$") then return "Cloth: drops from humanoid mobs" end
  if name and name:find("Venom Sac$") then return "Drops from spiders" end
  return "Drops from mobs"
end

-- where to buy an unlearned recipe, if Core's vendor list knows (First Aid books are "Manual: ...")
function ns.RecipeSource(name)
  local v, price = VendorFor("Manual: " .. name)
  if not v then v, price = VendorFor("Recipe: " .. name) end
  if not v then return end
  local money = price and GetCoinTextureString and GetCoinTextureString(price) or ""
  return v .. (money ~= "" and ("  " .. money) or "")
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

-- learned recipes that still give skill-ups, best first
function ns.MakeNow()
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

-- Plan crafts from your skill to a target. Picks the best learned recipe at each point.
-- Returns steps { r, crafts, from, to }, shopping { id, name, need, have, source }, stuckAt
function ns.Plan(target)
  local skill = Skill()
  if not skill then return {}, {}, nil end
  local _, _, maxr = Skill()
  target = math.min(tonumber(target) or (skill + 25), 300)
  local learned = {}
  for _, r in pairs(CharRec().recipes) do if r.learned then learned[#learned + 1] = r end end
  local steps, byName, s, stuck = {}, {}, skill, nil
  local guard = 0
  while s < target and guard < 400 do
    guard = guard + 1
    local best, bestChance, bestScore
    for _, r in ipairs(learned) do
      local ch = ns.Chance(r, s)
      if ch > 0 then
        -- prefer the best skill-up chance, but favor recipes you can already make from your bags
        local score = ch + (ns.Makeable(r) > 0 and 0.15 or 0)
        if not best or score > bestScore + 0.001 then best, bestChance, bestScore = r, ch, score end
      end
    end
    if not best then stuck = s; break end
    local st = byName[best.name]
    if not st or steps[#steps] ~= st then
      st = { r = best, crafts = 0, from = s, to = s }
      steps[#steps + 1] = st
      byName[best.name] = st
    end
    st.crafts = st.crafts + 1 / bestChance
    s = s + (best.ups or 1)
    st.to = s
  end
  local need = {}
  for _, st in ipairs(steps) do
    st.crafts = math.ceil(st.crafts)
    for _, g in ipairs(st.r.reagents or {}) do
      if g.id then
        local e = need[g.id] or { id = g.id, name = g.name, need = 0 }
        e.need = e.need + st.crafts * (g.n or 1)
        need[g.id] = e
      end
    end
  end
  local shopping = {}
  for _, e in pairs(need) do
    e.name = ItemName(e.id, e.name)
    e.have = Count(e.id)
    e.source = ns.SourceFor(e.id, e.name)
    shopping[#shopping + 1] = e
  end
  table.sort(shopping, function(a, b)
    local sa, sb = a.need - a.have, b.need - b.have
    if (sa > 0) ~= (sb > 0) then return sa > 0 end
    return (a.name or "") < (b.name or "")
  end)
  return steps, shopping, stuck, target, maxr
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
-- Classic answers until Forever data is logged. Forever reworked First Aid, so each line says so.
local ADVICE = {
  Horde = {
    [75]  = "Journeyman: any First Aid trainer (needs 50). Classic: Arnok (Undercity), Rawrk (Orgrimmar), Pand Stonebinder (Thunder Bluff). Not confirmed in Forever.",
    [150] = "Expert: book 'Expert First Aid - Under Wraps' (needs 125). Classic: Balai Lok'Wein, Brackenwall Village, Dustwallow Marsh. Not confirmed in Forever.",
    [225] = "Artisan: quest 'Triage' (needs 225, level 35). Classic: Doctor Gregory Victor, Hammerfall, Arathi Highlands. Not confirmed in Forever.",
    [300] = "Top rank. Nothing left to train.",
  },
  Alliance = {
    [75]  = "Journeyman: any First Aid trainer (needs 50). Classic: Shaina Fuller (Stormwind), Nissa Firestone (Ironforge), Byancie (Darnassus). Not confirmed in Forever.",
    [150] = "Expert: book 'Expert First Aid - Under Wraps' (needs 125). Classic: Deneb Walker, Stromgarde Keep, Arathi Highlands. Not confirmed in Forever.",
    [225] = "Artisan: quest 'Triage' (needs 225, level 35). Classic: Doctor Gustaf VanHowzen, Theramore Isle, Dustwallow Marsh. Not confirmed in Forever.",
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
end

local function ItemTip(tt)
  if not db or db.settings.tooltips == false or not tt or tt.faAidDone or not ns.Knows() then return end
  local name, link = tt:GetItem()
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return end
  local recipes = CharRec().recipes
  local skill = Skill()
  -- "Manual: Heavy Silk Bandage" (or "Recipe: ...")
  local rname = name and (name:match("^Manual: (.+)$") or name:match("^Recipe: (.+)$"))
  if rname and recipes[rname] then
    tt.faAidDone = true
    local r = recipes[rname]
    tt:AddLine(" ")
    tt:AddLine(("|cffd4a94eFirst Aid|r  %s%s|r%s"):format(r.learned and GREEN or YELLOW, r.learned and "You know this recipe" or "Not learned yet",
      r.grayAt and (GRAY .. "  ·  gray at " .. r.grayAt .. "|r") or ""))
    tt:Show()
    return
  end
  local uses = usedBy[id]
  if not uses or #uses == 0 then return end
  tt.faAidDone = true
  tt:AddLine(" ")
  tt:AddLine("|cffd4a94eFirst Aid:|r used in")
  local shown = 0
  table.sort(uses, function(a, b) return (a.learned and 1 or 0) > (b.learned and 1 or 0) end)
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
  local function clear(self) self.faAidDone = nil end
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
    C_Timer.After(0.5, function() if tok == scanToken then pcall(Scan); IndexUses() end end)
  else
    pcall(Scan); IndexUses()
  end
end

ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
  if e == "ADDON_LOADED" and a1 == ADDON then
    ForeverArtisanFirstAidDB = ForeverArtisanFirstAidDB or {}
    db = ForeverArtisanFirstAidDB
    db.version = ForeverArtisan.Version()
    db.settings = db.settings or {}
    if db.settings.tooltips == nil then db.settings.tooltips = true end
    if db.settings.verbose == nil then db.settings.verbose = false end
    return
  end
  if not db then return end
  if e == "PLAYER_LOGIN" then
    HookTooltips()
  elseif e == "PLAYER_ENTERING_WORLD" then
    Skill(); IndexRecipes(); IndexUses()
  elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_LIST_UPDATE" or e == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    ScanSoon()
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    local r = a3 and recipeBySpell[a3]
    if r then OnMade(r) end
  elseif e == "CHAT_MSG_SKILL" then
    if type(a1) == "string" and a1:find("First Aid", 1, true) then
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
SLASH_FAAID1 = "/faaid"
SlashCmdList.FAAID = function(msg)
  if not db then return end
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif not ns.Knows() then
    say("You haven't learned First Aid on this character.")
  elseif not ns.HasRecipes() then
    say("Open your First Aid window once so I can read your recipes.")
  elseif cmd == "next" or cmd == "now" then
    local list, skill = ns.MakeNow()
    if #list == 0 then say(("Skill %d. None of your recipes give skill-ups. Learn new ones or train."):format(skill or 0)) return end
    say(("Skill %d. Best crafts right now:"):format(skill))
    for i = 1, math.min(6, #list) do
      local e = list[i]
      say(("  %s%s|r  %s"):format(ns.COLOR_CODE[e.color], e.r.name,
        e.make > 0 and (GREEN .. "can make " .. e.make .. "|r") or (GRAY .. "missing materials|r")))
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
    say("First Aid tooltip lines " .. (db.settings.tooltips and "on." or "off."))
  elseif cmd == "reset" and rest:lower() == "confirm" then
    ns.ResetLog()
  else
    local i = ns.SkillInfo()
    local n, learned = 0, 0
    for _, r in pairs(CharRec().recipes) do n = n + 1; if r.learned then learned = learned + 1 end end
    say(("Skill: %s  ·  %d recipes read, %d learned"):format(i.rank and (i.rank .. (i.max and ("/" .. i.max) or "")) or "?", n, learned))
    say("Commands: /fa aid (window), next, plan [skill], tooltips, reset confirm")
  end
end
