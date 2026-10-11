-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: where to get a recipe you don't have yet.
-- Answers from what this account has actually seen in Forever, never a shipped database:
--   trainers and vendors you've met (Trade Contacts), recipe drops you looted, quest rewards you were offered.
-- Every crafting module's Recipe book uses FA.RecipeWhere.
-- Crafting materials you loot from mobs (bat wings, boar meat, spider legs) are remembered the same
-- way, so shopping lists can say "Dropped by Vampire Bat, Tirisfal Glades" (FA.MaterialWhere).
local FA = ForeverArtisan

-- recipe items, by profession: "Recipe: Spiced Wolf Meat", "Pattern: Linen Bag", ...
local PREFIXES = { "Recipe: ", "Pattern: ", "Plans: ", "Schematic: ", "Formula: ", "Manual: " }

local function MatStore()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  ForeverArtisanSettings.matFinds = ForeverArtisanSettings.matFinds or {}
  return ForeverArtisanSettings.matFinds
end

-- mobs you've targeted, moused over or seen on a nameplate, so a corpse you loot still has a name
-- (the combat log is off-limits to addons on Forever's client, so it's not used)
local deadNames, deadOrder = {}, {}
-- Forever hands addons "secret" strings for some units (in combat, some nameplates). They look like
-- strings but can't be compared or used as table keys, so anything secret is skipped.
local function Plain(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) end
local RememberDead
local function RememberUnit(unit)
  if not (UnitGUID and UnitName and UnitExists and UnitExists(unit)) then return end
  if UnitIsPlayer and UnitIsPlayer(unit) then return end
  local ok, guid, name = pcall(function() return UnitGUID(unit), UnitName(unit) end)
  if ok then RememberDead(guid, name) end
end
RememberDead = function(guid, name)
  if not (Plain(guid) and Plain(name)) or deadNames[guid] then return end
  deadNames[guid] = name
  deadOrder[#deadOrder + 1] = guid
  if #deadOrder > 200 then deadNames[table.remove(deadOrder, 1)] = nil end
end

local function Store()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  ForeverArtisanSettings.recipeFinds = ForeverArtisanSettings.recipeFinds or {}
  return ForeverArtisanSettings.recipeFinds
end

local function IsRecipeItem(name)
  if not name then return false end
  for _, p in ipairs(PREFIXES) do if name:sub(1, #p) == p then return true end end
  return false
end

local function Where()
  local z = (GetRealZoneText and GetRealZoneText()) or "?"
  local s = GetSubZoneText and GetSubZoneText()
  return z, (s and s ~= "" and s ~= z) and s or nil
end

local function Note(itemName, kind, from)
  local finds = Store()
  local f = finds[itemName] or {}
  finds[itemName] = f
  f[kind] = f[kind] or {}
  local z, s = Where()
  local key = from .. "|" .. z
  local e = f[kind][key] or { from = from, zone = z, sub = s, n = 0 }
  e.n = e.n + 1
  e.last = time()
  f[kind][key] = e
end

-- who dropped it: the mob you're targeting or one that died near you, else "a mob" / "a container".
-- Second return: true when it came off a creature (not a chest, herb, ore vein or bag).
local function LootFrom(slot)
  local ok, guid
  if GetLootSourceInfo then ok, guid = pcall(GetLootSourceInfo, slot) end
  if ok and Plain(guid) then
    if guid:find("^Item") then return "a container", false end
    if guid:find("^GameObject") then return "a chest", false end
    local tg = UnitGUID and UnitGUID("target")
    if Plain(tg) and tg == guid then
      local n = UnitName("target")
      return Plain(n) and n or "a mob", true
    end
    if deadNames[guid] then return deadNames[guid], true end
  end
  if UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target") then
    local n = UnitName("target")
    return Plain(n) and n or "a mob", true
  end
  return "a mob", true
end

-- a crafting material (Trade Goods or Reagent): its item id, else nil
local function MaterialId(link)
  local id = link and tonumber(link:match("item:(%d+)"))
  local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not (id and Instant) then return end
  local ok, _, _, _, _, _, classID = pcall(Instant, id)
  if ok and (classID == 7 or classID == 5) then return id end
end

local function NoteMat(id, from, qty)
  if from == "a mob" then return end -- no name, nothing worth showing
  local finds = MatStore()
  local f = finds[id] or {}
  finds[id] = f
  local z, s = Where()
  local key = from .. "|" .. z
  local e = f[key] or { from = from, zone = z, sub = s, n = 0, q = 0 }
  e.n, e.q, e.last = e.n + 1, e.q + (tonumber(qty) or 1), time()
  f[key] = e
end

local function OnLoot()
  for i = 1, ((GetNumLootItems and GetNumLootItems()) or 0) do
    local link = GetLootSlotLink and GetLootSlotLink(i)
    local name = link and link:match("%[(.-)%]")
    if IsRecipeItem(name) then
      Note(name, "drops", (LootFrom(i)))
    else
      local id = MaterialId(link)
      if id then
        local from, creature = LootFrom(i)
        if creature then
          local qty = GetLootSlotInfo and select(3, GetLootSlotInfo(i))
          NoteMat(id, from, qty)
        end
      end
    end
  end
end

-- With auto loot, Forever can skip the loot window entirely (no LOOT_OPENED), so drops are also
-- counted from your own "You receive loot" line. The mob is your dead target. Herbs, ore, skins,
-- fish, chests and disenchanting aren't mob drops: loot right after those casts is skipped.
local lastWindow, lastGather = -100, -100
local GATHER = { "Skinning", "Herb Gathering", "Mining", "Fishing", "Opening", "Disenchant", "Pick Lock", "Prospecting" }
local function IsGatherSpell(spellID)
  local GetName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(i) return (GetSpellInfo(i)) end)
  local ok, n = pcall(function() return GetName and GetName(spellID) end)
  if not (ok and Plain(n)) then return false end
  for _, g in ipairs(GATHER) do if n:find(g, 1, true) then return true end end
  return false
end
local function OnChatLoot(msg, guid)
  local now = GetTime()
  if now - lastWindow < 3 or now - lastGather < 5 then return end
  local got = FA.ParseSelfLoot and FA.ParseSelfLoot(msg, guid)
  if not got then return end
  if not (UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target")) then return end
  if UnitIsPlayer and UnitIsPlayer("target") then return end
  local n = UnitName("target")
  if not Plain(n) then return end
  if IsRecipeItem(got.name) then
    Note(got.name, "drops", n)
  else
    local id = MaterialId(got.link or ("item:" .. got.id))
    if id then NoteMat(id, n, got.qty) end
  end
end
FA.NoteChatLoot = OnChatLoot

local function OnQuest()
  local title = (GetTitleText and GetTitleText()) or "a quest"
  local giver = UnitName and UnitName("npc")
  local label = title .. (giver and (" (" .. giver .. ")") or "")
  for _, kind in ipairs({ "reward", "choice" }) do
    local n = (kind == "reward" and GetNumQuestRewards and GetNumQuestRewards())
      or (kind == "choice" and GetNumQuestChoices and GetNumQuestChoices()) or 0
    for i = 1, n do
      local link = GetQuestItemLink and GetQuestItemLink(kind, i)
      local name = link and link:match("%[(.-)%]")
      if IsRecipeItem(name) then Note(name, "quests", label) end
    end
  end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_OPENED", "QUEST_DETAIL", "QUEST_COMPLETE", "PLAYER_TARGET_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "CHAT_MSG_LOOT" }) do pcall(ev.RegisterEvent, ev, e) end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
ev:SetScript("OnEvent", function(_, e, a1, ...)
  if e == "CHAT_MSG_LOOT" then pcall(OnChatLoot, a1, (select(11, ...)))
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
    local spellID = select(2, ...)
    if IsGatherSpell(spellID) then lastGather = GetTime() end
  elseif e == "PLAYER_TARGET_CHANGED" then RememberUnit("target")
  elseif e == "UPDATE_MOUSEOVER_UNIT" then RememberUnit("mouseover")
  elseif e == "NAME_PLATE_UNIT_ADDED" then if a1 then RememberUnit(a1) end
  elseif e == "LOOT_OPENED" then lastWindow = GetTime(); pcall(OnLoot) else pcall(OnQuest) end
end)

local function Place(e) return e.sub and (e.sub .. ", " .. e.zone) or e.zone end

-- Where to get a recipe. prefixes = the profession's recipe item prefixes ({ "Recipe: " } for Cooking).
-- Returns: lines (for the tooltip), tag (one word for the row: "trainer", "vendor", "drop", "quest"),
-- npc (a trainer or vendor to click for a waypoint), skill (the skill a trainer asks for).
function FA.RecipeWhere(recipeName, prefixes)
  local lines, tag, npc, skill = {}, nil, nil, nil
  local V = FA.Vendors
  if V and V.hitsForLink and recipeName then
    for _, h in ipairs(V.hitsForLink(nil, recipeName) or {}) do
      if h.item and h.item.train and h.npc then
        lines[#lines + 1] = ("Train: %s, %s%s"):format(h.npc.n, h.npc.s or h.npc.z or "?",
          h.item.sk and (" (needs " .. h.item.sk .. ")") or "")
        tag, npc, skill = tag or "trainer", npc or h.npc, skill or h.item.sk
        if #lines >= 2 then break end
      end
    end
    for _, p in ipairs(prefixes or PREFIXES) do
      for _, h in ipairs(V.hitsForLink(nil, p .. recipeName) or {}) do
        if h.npc and not (h.item and h.item.train) then
          local price = h.item and h.item.p and GetCoinTextureString and GetCoinTextureString(h.item.p) or ""
          lines[#lines + 1] = ("Sold by: %s, %s%s%s"):format(h.npc.n, h.npc.s or h.npc.z or "?",
            price ~= "" and ("  " .. price) or "",
            (h.item and h.item.lim) and "  (limited stock)" or "")
          tag, npc = tag or "vendor", npc or h.npc
        end
      end
    end
  end
  local finds = Store()
  for _, p in ipairs(prefixes or PREFIXES) do
    local f = finds[p .. recipeName]
    if f then
      for _, e in pairs(f.drops or {}) do
        lines[#lines + 1] = ("Dropped by %s, %s (you looted it%s)"):format(e.from, Place(e), e.n > 1 and (" " .. e.n .. " times") or "")
        tag = tag or "drop"
      end
      for _, e in pairs(f.quests or {}) do
        lines[#lines + 1] = ("Quest reward: %s, %s"):format(e.from, Place(e))
        tag = tag or "quest"
      end
    end
  end
  -- nobody you've met teaches or sells it: what Questie's database knows (when installed)
  if tag ~= "trainer" and tag ~= "vendor" and FA.QuestieRecipeSources then
    local ok, qlines, qnpc = pcall(FA.QuestieRecipeSources, recipeName, prefixes)
    if ok and qlines then
      for _, l in ipairs(qlines) do lines[#lines + 1] = l end
      tag, npc = tag or "Questie", npc or qnpc
    end
  end
  if #lines == 0 then
    lines[1] = "Not found yet. Keep exploring: it could be a trainer, vendor, drop or quest you haven't come across."
  end
  return lines, tag, npc, skill
end

FA.IsRecipeItem = IsRecipeItem

-- Where a material dropped for you: "Dropped by Vampire Bat, Tirisfal Glades (looted 6 times)", or nil.
function FA.MaterialWhere(id)
  local f = id and MatStore()[id]
  if not f then return end
  local best, others = nil, 0
  for _, e in pairs(f) do
    if not best or e.n > best.n then
      if best then others = others + 1 end
      best = e
    else
      others = others + 1
    end
  end
  if not best then return end
  return ("Dropped by %s, %s (you looted it %s)%s"):format(best.from, Place(best),
    best.n == 1 and "once" or (best.n .. " times"), others > 0 and ("  +" .. others .. " more") or "")
end

-- Item tooltips: "Dropped by Greater Duskbat, Tirisfal Glades (you looted it 2 times)" on any material
-- you've looted from a mob, whether or not you know a recipe that uses it yet.
-- Also the Auction House price you last saw for it (when Auctionator isn't there to show its own).
local function DropTip(tt, id)
  if not id or tt.faDropTip then return end
  local line = FA.MaterialWhere(id)
  local price = FA.TooltipPrice and FA.TooltipPrice(id)
  if not line and not price then return end
  tt.faDropTip = true
  if line then tt:AddLine(FA.GOLD .. "ForeverArtisan:|r " .. line, 1, 1, 1, true) end
  if price then tt:AddLine(FA.GOLD .. "ForeverArtisan:|r " .. price, 1, 1, 1, true) end
  tt:Show()
end
local function HookDropTips()
  local function clear(self) self.faDropTip = nil end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      if tt == GameTooltip or tt == ItemRefTooltip then pcall(DropTip, tt, data and data.id) end
    end)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      tt:HookScript("OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        pcall(DropTip, self, link and tonumber(link:match("item:(%d+)")))
      end)
    end
  end
  GameTooltip:HookScript("OnTooltipCleared", clear)
  ItemRefTooltip:HookScript("OnTooltipCleared", clear)
end
local tipEv = CreateFrame("Frame")
tipEv:RegisterEvent("PLAYER_LOGIN")
tipEv:SetScript("OnEvent", function() pcall(HookDropTips) end)

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(ev)
ForeverArtisan.GuardEvents(tipEv)

---------------------------------------------------------------- recipes you can still train
-- Crafting plans use these: a recipe you haven't learned that a trainer in your Trade Contacts
-- teaches, with the skill it needs and what it costs. Only trainers you've opened count (no
-- guessing from Classic data), so a plan never sends you after a recipe nobody here teaches.
-- { at = skill needed, cost = copper or nil, who = "Arnok (Undercity)", npc = the contact } or nil
function ForeverArtisan.TrainableRecipe(prof, name)
  local V = ForeverArtisan.Vendors
  if not (V and V.hitsForLink and name) then return nil end
  local ok, hits = pcall(V.hitsForLink, nil, name)
  if not ok or type(hits) ~= "table" then return nil end
  local best
  for _, h in ipairs(hits) do
    local it = h.item
    if it and it.train then
      local sk = it.sk and tostring(it.sk)
      if not sk or not prof or sk:find(prof, 1, true) then
        local at = sk and tonumber(sk:match("(%d+)%s*$")) or 1
        local who = h.npc and h.npc.n and (h.npc.n .. " (" .. (h.npc.s or h.npc.z or "?")
          .. (h.npc.seed and ", seen on the Forever beta" or "") .. ")")
        -- same skill: the cheaper one, and a trainer you've met over one from the Forever beta
        local better = not best or at < best.at
          or (at == best.at and ((best.npc and best.npc.seed and not h.npc.seed) or (it.p or 0) < (best.cost or 0)))
        if better then
          best = { at = at, cost = it.p, who = who, npc = h.npc }
        end
      end
    end
  end
  return best
end

-- The recipes a plan may use: everything learned, plus unlearned ones a trainer you've met teaches.
-- Trainable ones come back as stand-ins that count as learned, with .train = { at, cost, who }.
-- Second value: how many unlearned recipes had no trainer on file.
function ForeverArtisan.PlanRecipes(prof, recipes, skip)
  local list, unknown = {}, 0
  for _, r in pairs(recipes or {}) do
    if not (skip and skip(r)) then
      if r.learned then
        list[#list + 1] = r
      elseif r.reagents and #r.reagents > 0 then
        local t = ForeverArtisan.TrainableRecipe(prof, r.name)
        if t then
          list[#list + 1] = setmetatable({ learned = true, train = t, base = r }, { __index = r })
        else
          unknown = unknown + 1
        end
      end
    end
  end
  return list, unknown
end

-- one line under a short plan, when meeting a trainer would help
function ForeverArtisan.TrainHint(prof, unknown)
  if not unknown or unknown == 0 then return nil end
  if not ForeverArtisan.Vendors then
    return "Turn on Trade Contacts and open a " .. prof .. " trainer once so plans can include recipes you can train."
  end
  return "Open a " .. prof .. " trainer's list once so plans can include recipes you can train there."
end

---------------------------------------------------------------- recipe colors you've seen
-- Forever only reports the skill where a recipe turns gray, so yellow and green are guessed
-- (40 and 20 below gray). Each time a crafting window shows a recipe's color we remember it at
-- that skill, and the guess moves to fit: orange seen at 28 means yellow starts at 29 or later.
function ForeverArtisan.NoteRecipeColor(old, new)
  if not new then return end
  local seen = {}
  local same = old and old.seen and not (old.grayAt and new.grayAt and old.grayAt ~= new.grayAt)
  if same then for k, v in pairs(old.seen) do seen[k] = v end end
  local c, at = new.color, new.scanSkill
  if c and at then
    if c == "orange" then seen.o = math.max(seen.o or at, at)
    elseif c == "yellow" then seen.ylo = math.min(seen.ylo or at, at); seen.yhi = math.max(seen.yhi or at, at)
    elseif c == "green" then seen.glo = math.min(seen.glo or at, at)
    end
  end
  new.seen = next(seen) and seen or nil
end

-- where yellow and green start for a recipe that turns gray at `gray`
function ForeverArtisan.RecipeBands(r, gray)
  local y, g = gray - 40, gray - 20
  local s = r and r.seen
  if s then
    if s.o then y = math.max(y, s.o + 1); g = math.max(g, s.o + 1) end
    if s.ylo then y = math.min(y, s.ylo) end
    if s.yhi then g = math.max(g, s.yhi + 1) end
    if s.glo then g = math.min(g, s.glo) end
  end
  if g > gray then g = gray end
  if y > g then y = g end
  return y, g
end

-- skill-up chance for a yellow or green recipe: falls evenly from yellow's start to gray
function ForeverArtisan.FadeChance(r, gray, skill)
  local y = ForeverArtisan.RecipeBands(r, gray)
  return math.max(0.05, math.min(1, (gray - skill) / math.max(1, gray - y)))
end

---------------------------------------------------------------- cheapest way up
-- What one craft's materials cost, in copper. Materials you'd make yourself count at what their
-- own materials cost (`makes`: item id -> recipe). nil when anything has no price yet.
function ForeverArtisan.CraftMoney(r, makes, memo, depth)
  memo = memo or {}
  if memo[r] ~= nil then return memo[r] or nil end
  if not r.reagents or #r.reagents == 0 then memo[r] = false; return nil end
  local total = 0
  for _, g in ipairs(r.reagents) do
    local via = g.id and makes and makes[g.id]
    local each
    if via and via ~= r and (depth or 0) < 3 then
      local m = ForeverArtisan.CraftMoney(via, makes, memo, (depth or 0) + 1)
      each = m and m / (via.makes or 1)
    elseif ForeverArtisan.ItemPrice then
      each = ForeverArtisan.ItemPrice(g.id, g.name)
    end
    if not each then memo[r] = false; return nil end
    total = total + each * (g.n or 1)
  end
  memo[r] = total
  return total
end

-- Pick the recipe for the next skill point from opts { r, ch, score, bag, mats }.
-- The best skill-up chance wins (score adds a bonus for things you can make from your bags).
-- Recipes within 0.1 of the best are close enough to compare money: when all of them have
-- prices, the cheapest per skill point wins. Otherwise fewer materials breaks an exact tie.
function ForeverArtisan.PickRecipe(opts, money)
  local top
  for _, o in ipairs(opts) do if not top or o.score > top.score + 0.001 then top = o end end
  if not top then return nil end
  local close, priced = {}, money ~= nil
  for _, o in ipairs(opts) do
    if o.score >= top.score - 0.1 and (o.bag and true or false) == (top.bag and true or false) then
      close[#close + 1] = o
      if priced then
        o.money = money(o.r)
        if not o.money then priced = false end
      end
    end
  end
  local best
  for _, o in ipairs(close) do
    if not best then best = o
    elseif priced then
      local a, b = o.money / o.ch, best.money / best.ch
      if a < b - 0.5 or (math.abs(a - b) <= 0.5 and o.score > best.score + 0.001) then best = o end
    elseif o.score > best.score + 0.001
      or (math.abs(o.score - best.score) <= 0.001 and (o.mats or 0) < (best.mats or 0)) then
      best = o
    end
  end
  return best
end

---------------------------------------------------------------- training on the shopping list
-- Shopping list rows for recipes to train: what you can learn right now in one line (one trip to
-- the trainer), then the rest one line each with the skill you learn it at, soonest first.
function ForeverArtisan.TrainShopRows(shopping, skill)
  local FA = ForeverArtisan
  local now, later = {}, {}
  for _, e in ipairs(shopping or {}) do
    if e.train then
      if skill and (e.train.at or 0) <= skill then now[#now + 1] = e else later[#later + 1] = e end
    end
  end
  table.sort(later, function(a, b)
    if a.train.at ~= b.train.at then return a.train.at < b.train.at end
    return (a.name or "") < (b.name or "")
  end)
  local rows = {}
  local CLICK = "\n|cff80c0ffClick for a waypoint to %s|r"
  if #now > 0 then
    local names, lines, cost, npc = {}, {}, 0, nil
    for _, e in ipairs(now) do
      local n = (e.name or ""):gsub("^Train ", "")
      names[#names + 1] = n
      cost = cost + (e.price or 0)
      npc = npc or e.train.npc
      lines[#lines + 1] = n .. (e.price and ("  " .. FA.Money(e.price)) or "")
        .. (e.train.who and (FA.GRAY .. "  ·  " .. e.train.who .. "|r") or "")
    end
    rows[#rows + 1] = { icon = 136235, tipTitle = "Train now",
      left = FA.YELLOW .. "Train now: " .. table.concat(names, ", ") .. "|r",
      right = FA.YELLOW .. #now .. " to learn|r" .. (cost > 0 and (FA.GRAY .. "  ·  " .. FA.Money(cost) .. "|r") or ""),
      waypoint = npc,
      tip = "Your skill is high enough to learn these now, in one trip:\n" .. table.concat(lines, "\n")
        .. (npc and npc.n and CLICK:format(npc.n) or "") }
  end
  for _, e in ipairs(later) do
    rows[#rows + 1] = { icon = 136235, tipTitle = e.name,
      left = FA.YELLOW .. e.name .. "|r",
      right = FA.YELLOW .. ("at %d"):format(e.train.at) .. "|r" .. (e.price and (FA.GRAY .. "  ·  " .. FA.Money(e.price) .. "|r") or ""),
      waypoint = e.train.npc,
      tip = e.source .. (e.train.npc and e.train.npc.n and CLICK:format(e.train.npc.n) or "") }
  end
  return rows
end
