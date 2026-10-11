-- Reading QuestieDB (the database Questie installs), when the player has it.
-- QuestieDB publishes a read API for other addons (LibQuestieDB, with a version contract). We only
-- read through it: nothing is copied into the addon or shipped. Everything here quietly does nothing
-- without Questie, with a QuestieDB we can't read, or when it's turned off (/fa contacts questie off).
--   FA.QDB.Lib()                    the library, or nil
--   FA.QDB.UiMap(areaId)            QuestieDB's zones -> the game's map IDs
--   FA.QDB.Npc(id)                  { n, t, f = "Horde"/"Alliance"/"Both", m, x, y, z } or nil
--   FA.QuestieRecipeSources(name, prefixes)  recipe book lines: who sells or drops it, quest rewards
--   FA.QuestieMaterial(id)          one shopping-list line for a material, or nil
local FA = ForeverArtisan
local QDB = {}
FA.QDB = QDB

local CONTRACT = 3
local BATCH = 500
local PREFIXES = { "Pattern: ", "Recipe: ", "Plans: ", "Schematic: ", "Formula: ", "Manual: ", "Blueprint: " }

function QDB.Lib()
  local L = rawget(_G, "LibQuestieDB")
  if type(L) ~= "table" or type(L.RequireContract) ~= "function" then return nil end
  local ok, good = pcall(L.RequireContract, CONTRACT)
  if not ok or not good then return nil end
  return L
end

-- the same switch as Trade Contacts' trainers: one "Questie on/off" for the whole suite
function QDB.Off()
  local db = rawget(_G, "ForeverArtisanContactsDB")
  return db and db.settings and db.settings.questieOff
end

function QDB.Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or function() end, "QuestieDB", "Version")
  return ok and v or "?"
end

local areaMap
function QDB.UiMap(areaId)
  if not areaMap then
    areaMap = {}
    local L = QDB.Lib()
    local ok, zdb = pcall(function() return L and L.Support and L.Support.Get and L.Support.Get("ZoneDB") end)
    local priv = ok and type(zdb) == "table" and zdb.private
    for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
      local src = type(priv) == "table" and priv[key]
      local t = src
      if type(src) == "string" and loadstring then
        local f = loadstring(src)
        local okRun, r = pcall(f or function() end)
        t = okRun and r or nil
      end
      if type(t) == "table" then for a, m in pairs(t) do areaMap[a] = m end end
    end
  end
  return areaMap[areaId]
end

-- false when QuestieDB loads but its zone table can't be read (trainers would have no place)
function QDB.ZoneMapOK()
  QDB.UiMap(0)
  return next(areaMap or {}) ~= nil
end

local mapNames = {}
local function MapName(m)
  if mapNames[m] == nil then
    local ok, info = pcall(C_Map.GetMapInfo, m)
    mapNames[m] = ok and info and info.name or false
  end
  return mapNames[m] or nil
end

local function Faction(fr)
  return (fr == "AH" and "Both") or (fr == "A" and "Alliance") or (fr == "H" and "Horde") or nil
end

-- one NPC: name, title, faction, first spawn on a map the game knows
local npcCache = {}
function QDB.Npc(id)
  if npcCache[id] ~= nil then return npcCache[id] or nil end
  local L = QDB.Lib()
  if not (L and L.Npc) then return nil end
  local _, n = pcall(L.Npc.name, id)
  local _, t = pcall(L.Npc.subName, id)
  local _, fr = pcall(L.Npc.friendlyToFaction, id)
  local _, spawns = pcall(L.Npc.spawns, id)
  local out = false
  if type(n) == "string" then
    out = { id = id, n = n, t = type(t) == "string" and t or nil, f = Faction(fr) }
    for area, pts in pairs(type(spawns) == "table" and spawns or {}) do
      local m = QDB.UiMap(area)
      local p = type(pts) == "table" and pts[1]
      if m and m > 0 and type(p) == "table" and tonumber(p[1]) and p[1] >= 0 then
        out.m, out.x, out.y, out.z = m, p[1], p[2], MapName(m)
        break
      end
    end
  end
  npcCache[id] = out
  return out or nil
end

-- friendly NPCs for your faction (neutral both); hostile-to-both mobs count for drops
local function MyFaction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return (f == "Horde" or f == "Alliance") and f or nil
end
local function Friendly(npc)
  local mine = MyFaction()
  return npc.f == "Both" or not mine or npc.f == mine
end

-- vendors first in your zone, then the rest
local function SortHere(list)
  local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  table.sort(list, function(a, b)
    local ah, bh = a.m == here, b.m == here
    if ah ~= bh then return ah end
    return a.n < b.n
  end)
  return list
end

local function Where(npc) return npc.z or "?" end

---------------------------------------------------------------- recipe items: name -> id, once per QuestieDB version

local recipeIndex -- [name] = itemId
local building = false

local function Settings()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  return ForeverArtisanSettings
end

local function HasPrefix(name)
  for _, p in ipairs(PREFIXES) do if name:sub(1, #p) == p then return true end end
  return name:find("^Expert ") or name:find("^Artisan ") -- rank books (Expert Fishing, Expert Cookbook)
end

function QDB.BuildRecipeIndex()
  if building or recipeIndex or QDB.Off() then return end
  local L = QDB.Lib()
  if not (L and L.Item) then return end
  local cache = Settings().questieRecipes
  if cache and cache.version == QDB.Version() and cache.contract == L.contractVersion and type(cache.index) == "table" then
    recipeIndex = cache.index
    return
  end
  local okIds, ids = pcall(L.Item.GetAllIds)
  if not okIds or type(ids) ~= "table" then return end
  building = true
  local index, i = {}, 1
  local function step()
    local stop = math.min(#ids, i + BATCH - 1)
    for k = i, stop do
      local id = ids[k]
      local okC, class = pcall(L.Item.class, id)
      if okC and (class == 9 or class == nil) then
        local okN, name = pcall(L.Item.name, id)
        if okN and type(name) == "string" and (class == 9 or HasPrefix(name)) then index[name] = id end
      end
    end
    i = stop + 1
    if i <= #ids and C_Timer then C_Timer.After(0, step)
    elseif i <= #ids then step()
    else
      recipeIndex, building = index, false
      Settings().questieRecipes = { version = QDB.Version(), contract = L.contractVersion, index = index }
      if type(L.InvalidateCache) == "function" then pcall(L.InvalidateCache, "Item") end
    end
  end
  step()
end

function QDB.Reset()
  recipeIndex, building, areaMap = nil, false, nil
  for k in pairs(npcCache) do npcCache[k] = nil end
  for k in pairs(mapNames) do mapNames[k] = nil end
  if ForeverArtisanSettings then ForeverArtisanSettings.questieRecipes = nil end
end

---------------------------------------------------------------- what we tell the player

local function ListNames(npcs, max)
  local parts = {}
  for i = 1, math.min(max, #npcs) do parts[#parts + 1] = npcs[i].n .. ", " .. Where(npcs[i]) end
  return table.concat(parts, "; ") .. (#npcs > max and ("  +" .. (#npcs - max) .. " more") or "")
end

-- sellers (your faction) and droppers of one item, already looked up
local function Sources(L, itemId)
  local sellers, droppers = {}, {}
  local _, vendors = pcall(L.Item.vendors, itemId)
  for _, nid in ipairs(type(vendors) == "table" and vendors or {}) do
    local npc = QDB.Npc(nid)
    if npc and Friendly(npc) then sellers[#sellers + 1] = npc end
  end
  local _, drops = pcall(L.Item.npcDrops, itemId)
  local dropCount = type(drops) == "table" and #drops or 0
  if dropCount > 0 and dropCount <= 15 then
    for _, nid in ipairs(drops) do
      local npc = QDB.Npc(nid)
      if npc then droppers[#droppers + 1] = npc end
    end
  end
  return SortHere(sellers), SortHere(droppers), dropCount
end

-- Recipe book lines for a recipe nobody in your Trade Contacts teaches or sells:
-- { "Sold by: Darnall, Moonglade (from Questie)", ... }, or nil
function FA.QuestieRecipeSources(recipeName, prefixes)
  if QDB.Off() or not recipeIndex or not recipeName then return nil end
  local L = QDB.Lib()
  if not (L and L.Item) then return nil end
  local itemId
  for _, p in ipairs(prefixes or PREFIXES) do
    itemId = recipeIndex[p .. recipeName]
    if itemId then break end
  end
  itemId = itemId or recipeIndex[recipeName]
  if not itemId then return nil end
  local lines = {}
  local sellers, droppers, dropCount = Sources(L, itemId)
  if #sellers > 0 then lines[#lines + 1] = "Sold by: " .. ListNames(sellers, 2) .. " (from Questie)" end
  if #droppers > 0 then lines[#lines + 1] = "Drops from: " .. ListNames(droppers, 2) .. " (from Questie)"
  elseif dropCount > 15 then lines[#lines + 1] = ("Drops from %d kinds of mobs (from Questie)"):format(dropCount) end
  local _, quests = pcall(L.Item.questRewards, itemId)
  if type(quests) == "table" and quests[1] and L.Quest then
    local _, qn = pcall(L.Quest.name, quests[1])
    if type(qn) == "string" then lines[#lines + 1] = "Quest reward: " .. qn .. " (from Questie)" end
  end
  if #lines == 0 then return nil end
  return lines, sellers[1] or droppers[1]
end

-- One shopping-list line for a material, or nil: a vendor for your faction first, then a short drop list.
-- Long drop lists (cloth from hundreds of mobs) stay with the shorter built-in answers.
function FA.QuestieMaterial(itemId)
  if QDB.Off() or not itemId then return nil end
  local L = QDB.Lib()
  if not (L and L.Item) then return nil end
  local sellers, droppers = Sources(L, itemId)
  if #sellers > 0 then return "Vendor: " .. ListNames(sellers, 1) .. " (from Questie)" end
  if #droppers > 0 then return "Drops from: " .. ListNames(droppers, 2) .. " (from Questie)" end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  -- after Trade Contacts reads its trainers (6 s), so the two reads never overlap
  if C_Timer then C_Timer.After(12, function() pcall(QDB.BuildRecipeIndex) end)
  else pcall(QDB.BuildRecipeIndex) end
end)
if FA.GuardEvents then FA.GuardEvents(ev) end
