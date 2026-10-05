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
  "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e, a1)
  if e == "PLAYER_TARGET_CHANGED" then RememberUnit("target")
  elseif e == "UPDATE_MOUSEOVER_UNIT" then RememberUnit("mouseover")
  elseif e == "NAME_PLATE_UNIT_ADDED" then if a1 then RememberUnit(a1) end
  elseif e == "LOOT_OPENED" then pcall(OnLoot) else pcall(OnQuest) end
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
local function DropTip(tt, id)
  if not id or tt.faDropTip then return end
  local line = FA.MaterialWhere(id)
  if not line then return end
  tt.faDropTip = true
  tt:AddLine(FA.GOLD .. "ForeverArtisan:|r " .. line, 1, 1, 1, true)
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
