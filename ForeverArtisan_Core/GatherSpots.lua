-- Gathering spots from GatherMate2 (and its data pack), when the player has it, else from Questie's
-- database (its herb and ore spawn points), when the player has Questie.
-- Both keep every herb and ore node they know by zone. We only read them: nothing is copied
-- into the addon or shipped. Herbalism's and Mining's "Pick next" use them for herbs and ores you
-- haven't logged yourself, and a click on a row sets a waypoint to the nearest spot.
-- Off: /fa gather off (GatherMate2), /fa contacts questie off (Questie). Anything unexpected and it
-- quietly does nothing.
--   FA.GatherStatus()                 "on" | "off" | "missing" | "incompatible"
--   FA.GatherZones(kind, node)        { { m, z, n, here }, ... } best first, and the total; or nil
--   FA.GatherZoneText(kind, node, k, short)  "Mulgore, The Barrens  +3 more" ("+3" when short), or nil
--   FA.GatherTip(kind, node)          tooltip lines, or nil
--   FA.GatherWaypoint(kind, node)     waypoint to the nearest known spot; true when one was set
--   FA.GatherSource(kind, node)       "GatherMate2" or "Questie": where those spots come from, or nil
-- kind is "herb" or "mine"; node is the English node name ("Peacebloom", "Copper Vein").
local FA = ForeverArtisan
local PREFIX = "|cffd4a94eForeverArtisan:|r "
local TYPES = { herb = "Herb Gathering", mine = "Mining" }
local SV = { herb = "GatherMate2HerbDB", mine = "GatherMate2MineDB" }
local FRESH = 60 -- seconds a zone count stays good (GatherMate2 adds nodes as you gather)

local function GM()
  local g = rawget(_G, "GatherMate2")
  if type(g) ~= "table" and LibStub then
    local ok, lib = pcall(LibStub, "AceAddon-3.0", true)
    if ok and lib and lib.GetAddon then
      local ok2, a = pcall(lib.GetAddon, lib, "GatherMate2", true)
      if ok2 then g = a end
    end
  end
  return type(g) == "table" and g or nil
end

local function Off()
  return ForeverArtisanSettings and ForeverArtisanSettings.gatherOff
end

-- GatherMate2's own ids for the Classic herbs and ores (from its Constants.lua; they're the ids it
-- saves, so they don't change). GatherMate2 looks names up in the game's language, so on a German or
-- French client "Peacebloom" isn't found by name: these keep it working in every language.
local GM_IDS = {
  herb = { ["Peacebloom"] = 401, ["Silverleaf"] = 402, ["Earthroot"] = 403, ["Mageroyal"] = 404,
    ["Briarthorn"] = 405, ["Stranglekelp"] = 407, ["Bruiseweed"] = 408, ["Wild Steelbloom"] = 409,
    ["Grave Moss"] = 410, ["Kingsblood"] = 411, ["Liferoot"] = 412, ["Fadeleaf"] = 413, ["Goldthorn"] = 414,
    ["Khadgar's Whisker"] = 415, ["Wintersbite"] = 416, ["Firebloom"] = 417, ["Purple Lotus"] = 418,
    ["Arthas' Tears"] = 420, ["Sungrass"] = 421, ["Blindweed"] = 422, ["Ghost Mushroom"] = 423,
    ["Gromsblood"] = 424, ["Golden Sansam"] = 425, ["Dreamfoil"] = 426, ["Mountain Silversage"] = 427,
    ["Plaguebloom"] = 428, ["Icecap"] = 429, ["Black Lotus"] = 431 },
  mine = { ["Copper Vein"] = 201, ["Tin Vein"] = 202, ["Iron Deposit"] = 203, ["Silver Vein"] = 204,
    ["Gold Vein"] = 205, ["Mithril Deposit"] = 206, ["Ooze Covered Mithril Deposit"] = 207,
    ["Truesilver Deposit"] = 208, ["Ooze Covered Silver Vein"] = 209, ["Ooze Covered Gold Vein"] = 210,
    ["Ooze Covered Truesilver Deposit"] = 211, ["Ooze Covered Rich Thorium Vein"] = 212,
    ["Ooze Covered Thorium Vein"] = 213, ["Small Thorium Vein"] = 214, ["Rich Thorium Vein"] = 215,
    ["Dark Iron Deposit"] = 217, ["Lesser Bloodstone Deposit"] = 218, ["Incendicite Mineral Vein"] = 219,
    ["Indurium Mineral Vein"] = 220 },
}
FA._GM_IDS = GM_IDS -- for the tests

-- GatherMate2 has its name lookup at all (an update that removed it: we can't read it)
local function HasLookup(g, t)
  if type(g.nodeIDs) == "table" and type(g.nodeIDs[t]) == "table" then return true end
  if type(g.GetIDForNode) == "function" then return (pcall(g.GetIDForNode, g, t, "")) end
  return false
end

-- node name -> GatherMate2's id for it
local function NodeId(kind, node)
  local g = GM()
  if not g or not node then return nil end
  local t = TYPES[kind]
  if type(g.GetIDForNode) == "function" then
    local ok, id = pcall(g.GetIDForNode, g, t, node)
    if ok and id then return id end
  end
  local ids = type(g.nodeIDs) == "table" and g.nodeIDs[t]
  if type(ids) == "table" and ids[node] then return ids[node] end
  -- not found by its English name (another game language): GatherMate2's own fixed id
  if HasLookup(g, t) then return GM_IDS[kind] and GM_IDS[kind][node] or nil end
  return nil
end

-- the node table for a kind: [uiMapID] = { [coord] = nodeId }
local function Data(kind)
  local g = GM()
  local db = g and type(g.gmdbs) == "table" and g.gmdbs[TYPES[kind]]
  if type(db) ~= "table" then db = rawget(_G, SV[kind]) end
  return type(db) == "table" and db or nil
end

---------------------------------------------------------------- Questie's spawn points (second source)
-- Questie's database has every herb and ore node's spawn points, by object ID but without names.
-- These IDs were checked against our own Herbalism and Mining logs on live Forever (Nov 8, 2026):
-- the logged spots sit on their spawn points. Ore spawn points are shared between ore types in the
-- data (a spot can grow Silver or Gold), so they read as "can spawn here".
local QIDS = {
  herb = {
    -- 656160 and 656161: Forever's small starter-zone nodes (Wilted Peacebloom, Stunted Silverleaf),
    -- which share their spots
    Peacebloom = { 1618, 656160, 656161 }, Silverleaf = { 1617, 656160, 656161 }, Earthroot = { 1619 },
    Mageroyal = { 1620 }, Briarthorn = { 1621 }, Stranglekelp = { 2045 }, Bruiseweed = { 1622 },
    ["Wild Steelbloom"] = { 1623 }, ["Grave Moss"] = { 1628 }, Kingsblood = { 1624 }, Liferoot = { 2041 },
    Fadeleaf = { 2042 }, Goldthorn = { 2046 }, ["Khadgar's Whisker"] = { 2043 }, Wintersbite = { 2044 },
    Firebloom = { 2866 }, ["Purple Lotus"] = { 142140 }, ["Arthas' Tears"] = { 142141 }, Sungrass = { 142142 },
    Blindweed = { 142143 }, ["Ghost Mushroom"] = { 142144 }, Gromsblood = { 142145 }, ["Golden Sansam"] = { 176583 },
    Dreamfoil = { 176584 }, ["Mountain Silversage"] = { 176586 }, Plaguebloom = { 176587 }, Icecap = { 176588 },
    ["Black Lotus"] = { 176589 },
  },
  mine = {
    -- the "Ooze Covered" nodes give the same ore
    ["Copper Vein"] = { 1731 }, ["Tin Vein"] = { 1732 }, ["Incendicite Mineral Vein"] = { 1610 },
    ["Silver Vein"] = { 1733, 73940 }, ["Lesser Bloodstone Deposit"] = { 2653 }, ["Iron Deposit"] = { 1735 },
    ["Indurium Mineral Vein"] = { 19903 }, ["Gold Vein"] = { 1734, 73941 }, ["Mithril Deposit"] = { 2040, 123310 },
    ["Truesilver Deposit"] = { 2047, 123309 }, ["Dark Iron Deposit"] = { 165658 },
    ["Small Thorium Vein"] = { 324, 123848 }, ["Rich Thorium Vein"] = { 175404, 177388 },
  },
}
FA.GATHER_QIDS = QIDS -- for the tests

-- Questie clears the spawns of the common gathering nodes from what it shows (Peacebloom to
-- Kingsblood, Copper to Thorium: "thousands of spawns that Questie never displays"), so the API
-- returns nothing for them. QuestieDB still stores them in its own TOC metadata, in the format its
-- contract covers (X-Object-<id>-4, base64 CBOR, "~N~" for N numbered parts). For those nodes we
-- read that stored row the way QuestieDB does. Read only, and nothing Questie shows changes.
local function StoredSpawns(oid)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local E = C_EncodingUtil
  if not (get and E and E.DecodeBase64 and E.DeserializeCBOR) then return nil end
  local key = "X-Object-" .. oid .. "-4"
  local ok, v = pcall(get, "QuestieDB", key)
  if not ok or type(v) ~= "string" or v == "" then return nil end
  local n = tonumber(v:match("^~(%d+)~$"))
  if n then
    local parts = {}
    for i = 1, n do
      local okP, part = pcall(get, "QuestieDB", key .. "-" .. i)
      if not okP or type(part) ~= "string" then return nil end
      parts[i] = part
    end
    v = table.concat(parts)
  end
  local okB, bytes = pcall(E.DecodeBase64, v)
  if not okB or type(bytes) ~= "string" then return nil end
  local okC, t = pcall(E.DeserializeCBOR, bytes)
  return okC and type(t) == "table" and t or nil
end
FA.GatherStoredSpawns = StoredSpawns -- for the tests

local qSpots = {} -- ["herb:Peacebloom"] = { [uiMapID] = { { x, y }, ... } } or false
local function QSpots(kind, node)
  local ids = node and QIDS[kind] and QIDS[kind][node]
  if not ids or not FA.QDB or (FA.QDB.Off and FA.QDB.Off()) then return nil end
  local key = kind .. ":" .. node
  if qSpots[key] ~= nil then return qSpots[key] or nil end
  local L = FA.QDB.Lib and FA.QDB.Lib()
  if not (L and L.Object and L.Object.spawns) then return nil end -- not ready yet: ask again later
  local out, any = {}, false
  for _, oid in ipairs(ids) do
    local ok, sp = pcall(L.Object.spawns, oid)
    if not (ok and type(sp) == "table" and next(sp)) then sp = StoredSpawns(oid); ok = sp ~= nil end
    for area, pts in pairs(ok and type(sp) == "table" and sp or {}) do
      local m = FA.QDB.UiMap(area)
      if m and m > 0 then
        for _, p in ipairs(type(pts) == "table" and pts or {}) do
          local x, y = type(p) == "table" and tonumber(p[1]), type(p) == "table" and tonumber(p[2])
          if x and y and x >= 0 and y >= 0 then
            local t = out[m] or {}; out[m] = t
            t[#t + 1] = { x, y }; any = true
          end
        end
      end
    end
  end
  qSpots[key] = any and out or false
  return any and out or nil
end

function FA.GatherStatus()
  if not GM() then return "missing" end
  if Off() then return "off" end
  if not (Data("herb") or Data("mine")) or not NodeId("herb", "Peacebloom") then return "incompatible" end
  return "on"
end

-- GatherMate2 packs a spot as xxxxyyyyLL: x and y in ten-thousandths of the map, then a level
local function Decode(coord)
  return math.floor(coord / 1000000) / 100, math.floor((coord % 1000000) / 100) / 100
end

-- GatherMate2 keeps zones in its main saved variable plus any storage add-ons (the data pack can
-- register its own), behind a lookup table that pairs() can't walk. Collect the zone ids from each.
local function ZoneIds(db)
  local ids, seen = {}, {}
  local function add(t)
    if type(t) ~= "table" then return end
    for m in pairs(t) do
      if type(m) == "number" and not seen[m] then seen[m] = true; ids[#ids + 1] = m end
    end
  end
  local base = rawget(db, "__gm2_base_storage")
  if base then
    add(base)
    for _, st in pairs(rawget(db, "__gm2_storage_map") or {}) do add(st) end
  else
    add(db)
  end
  return ids
end

local mapNames = {}
local function MapName(m)
  if mapNames[m] == nil then
    local ok, info = pcall(C_Map.GetMapInfo, m)
    mapNames[m] = ok and info and info.name or false
  end
  return mapNames[m] or nil
end

local function Here()
  return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

-- [kind] = { t = time, counts = { [nodeId] = { [m] = n } } }
local cache = {}
local function Counts(kind)
  local c = cache[kind]
  local now = GetTime and GetTime() or 0
  if c and now - c.t < FRESH then return c.counts end
  local db = Data(kind)
  if not db then return nil end
  local counts = {}
  for _, m in ipairs(ZoneIds(db)) do
    local nodes = db[m]
    if type(nodes) == "table" then
      for _, id in pairs(nodes) do
        local byMap = counts[id]
        if not byMap then byMap = {}; counts[id] = byMap end
        byMap[m] = (byMap[m] or 0) + 1
      end
    end
  end
  cache[kind] = { t = now, counts = counts }
  return counts
end

-- where a node's spots come from: GatherMate2 when it knows the node, else Questie
-- (/fa gather off turns off both)
local function Source(kind, node)
  if not TYPES[kind] or Off() then return nil end
  do
    local id = NodeId(kind, node)
    local counts = id and Counts(kind)
    if counts and counts[id] then return "GatherMate2", counts[id], id end
  end
  local q = QSpots(kind, node)
  if q then
    local byMap = {}
    for m, pts in pairs(q) do byMap[m] = #pts end
    return "Questie", byMap, q
  end
end
function FA.GatherSource(kind, node) return (Source(kind, node)) end

-- spots from somewhere: GatherMate2 readable, or Questie installed and on (for the Settings row)
function FA.GatherAvailable()
  if Off() then return false end
  if FA.GatherStatus() == "on" then return true end
  return FA.QDB and FA.QDB.Lib and FA.QDB.Lib() ~= nil and not (FA.QDB.Off and FA.QDB.Off()) or false
end

function FA.GatherZones(kind, node)
  local src, byMap = Source(kind, node)
  if not byMap then return nil end
  local here, list, total = Here(), {}, 0
  for m, n in pairs(byMap) do
    local z = MapName(m)
    if z then
      list[#list + 1] = { m = m, z = z, n = n, here = (m == here) }
      total = total + n
    end
  end
  if #list == 0 then return nil end
  -- where you are first, then the zones with the most spots
  table.sort(list, function(a, b)
    if a.here ~= b.here then return a.here end
    if a.n ~= b.n then return a.n > b.n end
    return a.z < b.z
  end)
  return list, total, src
end

function FA.GatherZoneText(kind, node, limit, short)
  local list = FA.GatherZones(kind, node)
  if not list then return nil end
  limit = limit or 2
  local names = {}
  for i = 1, math.min(limit, #list) do names[i] = list[i].z end
  local extra = #list - limit
  return table.concat(names, ", ") .. (extra > 0 and ("  +" .. extra .. (short and "" or " more")) or "")
end

function FA.GatherTip(kind, node)
  local list, total, src = FA.GatherZones(kind, node)
  if not list then return nil end
  local lines = { "|cffd4a94eKnown spots (from " .. (src or "GatherMate2") .. ")|r" }
  for i = 1, math.min(5, #list) do
    local z = list[i]
    lines[#lines + 1] = ("%s: %d spot%s%s"):format(z.z, z.n, z.n == 1 and "" or "s", z.here and "  (you're here)" or "")
  end
  if #list > 5 then lines[#lines + 1] = "|cff9d9d9d...and " .. (#list - 5) .. " more zones|r" end
  lines[#lines + 1] = "|cff80c0ffClick for a waypoint to the nearest one.|r"
  return table.concat(lines, "\n"), total
end

---------------------------------------------------------------- nearest spot and the waypoint

local function PlayerPos()
  local m = Here()
  if not m then return end
  local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(m, "player")
  if not pos then return m end
  local x, y = pos:GetXY()
  return m, x * 100, y * 100
end

-- map position (0-100) -> continent and yards, so spots in different zones compare
local function WorldPos(m, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x / 100, y / 100))
  if not ok or not cont or not pos then return end
  local wx, wy = pos.x, pos.y
  if pos.GetXY then wx, wy = pos:GetXY() end
  if wx and wy then return cont, wx, wy end
end

-- a node's spots on one map, as { {x, y}, ... }
local function SpotsOn(kind, node, m)
  local src, _, ref = Source(kind, node)
  if src == "Questie" then return ref[m] or {} end
  local out, db = {}, Data(kind)
  for coord, nid in pairs(db and db[m] or {}) do
    if nid == ref then local x, y = Decode(coord); out[#out + 1] = { x, y } end
  end
  return out
end

-- the nearest spot: on your map first, else across your continent, else the zone with the most spots
local function Nearest(kind, node)
  local list = FA.GatherZones(kind, node)
  if not list then return nil end
  local pm, px, py = PlayerPos()
  local best, bestD
  -- on your map: plain map distance
  if pm and px then
    for _, p in ipairs(SpotsOn(kind, node, pm)) do
      local d = (p[1] - px) ^ 2 + (p[2] - py) ^ 2
      if not bestD or d < bestD then best, bestD = { m = pm, x = p[1], y = p[2] }, d end
    end
    if best then return best end
  end
  -- your continent: yards
  local pc, pwx, pwy
  if pm and px then pc, pwx, pwy = WorldPos(pm, px, py) end
  if pc then
    for _, z in ipairs(list) do
      for _, p in ipairs(SpotsOn(kind, node, z.m)) do
        local c, wx, wy = WorldPos(z.m, p[1], p[2])
        if c ~= pc then break end -- the whole zone is on another continent
        local d = (wx - pwx) ^ 2 + (wy - pwy) ^ 2
        if not bestD or d < bestD then best, bestD = { m = z.m, x = p[1], y = p[2] }, d end
      end
    end
    if best then return best end
  end
  -- somewhere else: the zone with the most spots
  local top = list[1]
  local p = SpotsOn(kind, node, top.m)[1]
  if p then return { m = top.m, x = p[1], y = p[2], far = true } end
end

function FA.GatherWaypoint(kind, node)
  if Off() then return false end
  local spot = Nearest(kind, node)
  if not spot then
    print(PREFIX .. "no known " .. (node or "?") .. " spots yet.")
    return false
  end
  local z = MapName(spot.m) or "?"
  local title = node .. " (" .. z .. ")"
  -- Trade Contacts' waypoint knows TomTom and the game's own map pin; use it when it's on
  if FA.Vendors and FA.Vendors.waypoint then
    FA.Vendors.waypoint({ n = node, z = z, s = z, m = spot.m, x = spot.x, y = spot.y })
    return true
  end
  if TomTom and TomTom.AddWaypoint then
    pcall(TomTom.AddWaypoint, TomTom, spot.m, spot.x / 100, spot.y / 100, { title = title, persistent = false, crazy = true, from = "ForeverArtisan" })
    print(PREFIX .. "waypoint set: " .. title)
    return true
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(spot.m, spot.x / 100, spot.y / 100))
    if ok then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
      print(PREFIX .. ("map pin set: %s at %.1f, %.1f%s"):format(title, spot.x, spot.y,
        spot.m ~= Here() and (". Open the " .. z .. " map to see it.") or ""))
      return true
    end
  end
  print(PREFIX .. ("nearest %s: %s, %.1f, %.1f"):format(node, z, spot.x, spot.y))
  return true
end

function FA.GatherReset()
  for k in pairs(cache) do cache[k] = nil end
  for k in pairs(qSpots) do qSpots[k] = nil end
end
