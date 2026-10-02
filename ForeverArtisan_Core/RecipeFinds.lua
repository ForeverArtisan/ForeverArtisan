-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: where to get a recipe you don't have yet.
-- Answers from what this account has actually seen in Forever, never a shipped database:
--   trainers and vendors you've met (Trade Contacts), recipe drops you looted, quest rewards you were offered.
-- Every crafting module's Recipe book uses FA.RecipeWhere.
local FA = ForeverArtisan

-- recipe items, by profession: "Recipe: Spiced Wolf Meat", "Pattern: Linen Bag", ...
local PREFIXES = { "Recipe: ", "Pattern: ", "Plans: ", "Schematic: ", "Formula: ", "Manual: " }

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

-- who dropped it: the mob you're targeting if it's the loot's source, else "a mob" / "a container"
local function LootFrom(slot)
  local ok, guid
  if GetLootSourceInfo then ok, guid = pcall(GetLootSourceInfo, slot) end
  if ok and type(guid) == "string" then
    if guid:find("^Item") then return "a container" end
    if guid:find("^GameObject") then return "a chest" end
    if UnitGUID and UnitGUID("target") == guid then return UnitName("target") or "a mob" end
  end
  if UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target") then return UnitName("target") or "a mob" end
  return "a mob"
end

local function OnLoot()
  for i = 1, ((GetNumLootItems and GetNumLootItems()) or 0) do
    local link = GetLootSlotLink and GetLootSlotLink(i)
    local name = link and link:match("%[(.-)%]")
    if IsRecipeItem(name) then Note(name, "drops", LootFrom(i)) end
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
for _, e in ipairs({ "LOOT_OPENED", "QUEST_DETAIL", "QUEST_COMPLETE" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e)
  if e == "LOOT_OPENED" then pcall(OnLoot) else pcall(OnQuest) end
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
