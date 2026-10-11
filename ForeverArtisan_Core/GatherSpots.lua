-- Gathering spots from GatherMate2 (and its data pack), when the player has it.
-- GatherMate2 keeps every herb and ore node it knows by zone. We only read it: nothing is copied
-- into the addon or shipped. Herbalism's and Mining's "Pick next" use it for herbs and ores you
-- haven't logged yourself, and a click on a row sets a waypoint to the nearest spot.
-- Off: /fa gather off. Anything unexpected and it quietly does nothing.
--   FA.GatherStatus()                 "on" | "off" | "missing" | "incompatible"
--   FA.GatherZones(kind, node)        { { m, z, n, here }, ... } best first, and the total; or nil
--   FA.GatherZoneText(kind, node, k, short)  "Mulgore, The Barrens  +3 more" ("+3" when short), or nil
--   FA.GatherTip(kind, node)          tooltip lines, or nil
--   FA.GatherWaypoint(kind, node)     waypoint to the nearest known spot; true when one was set
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
  return type(ids) == "table" and ids[node] or nil
end

-- the node table for a kind: [uiMapID] = { [coord] = nodeId }
local function Data(kind)
  local g = GM()
  local db = g and type(g.gmdbs) == "table" and g.gmdbs[TYPES[kind]]
  if type(db) ~= "table" then db = rawget(_G, SV[kind]) end
  return type(db) == "table" and db or nil
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

function FA.GatherZones(kind, node)
  if Off() or not TYPES[kind] then return nil end
  local id = NodeId(kind, node)
  local counts = id and Counts(kind)
  local byMap = counts and counts[id]
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
  return list, total
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
  local list, total = FA.GatherZones(kind, node)
  if not list then return nil end
  local lines = { "|cffd4a94eKnown spots (from GatherMate2)|r" }
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

-- the nearest spot: on your map first, else across your continent, else the zone with the most spots
local function Nearest(kind, node)
  local id = NodeId(kind, node)
  local db = id and Data(kind)
  if not db then return nil end
  local list = FA.GatherZones(kind, node)
  if not list then return nil end
  local pm, px, py = PlayerPos()
  local best, bestD
  -- on your map: plain map distance
  if pm and px and type(db[pm]) == "table" then
    for coord, nid in pairs(db[pm]) do
      if nid == id then
        local x, y = Decode(coord)
        local d = (x - px) ^ 2 + (y - py) ^ 2
        if not bestD or d < bestD then best, bestD = { m = pm, x = x, y = y }, d end
      end
    end
    if best then return best end
  end
  -- your continent: yards
  local pc, pwx, pwy
  if pm and px then pc, pwx, pwy = WorldPos(pm, px, py) end
  if pc then
    for _, z in ipairs(list) do
      for coord, nid in pairs(db[z.m] or {}) do
        if nid == id then
          local x, y = Decode(coord)
          local c, wx, wy = WorldPos(z.m, x, y)
          if c ~= pc then break end -- the whole zone is on another continent
          local d = (wx - pwx) ^ 2 + (wy - pwy) ^ 2
          if not bestD or d < bestD then best, bestD = { m = z.m, x = x, y = y }, d end
        end
      end
    end
    if best then return best end
  end
  -- somewhere else: the zone with the most spots
  local top = list[1]
  for coord, nid in pairs(db[top.m] or {}) do
    if nid == id then
      local x, y = Decode(coord)
      return { m = top.m, x = x, y = y, far = true }
    end
  end
end

function FA.GatherWaypoint(kind, node)
  if Off() then return false end
  local spot = Nearest(kind, node)
  if not spot then
    print(PREFIX .. "GatherMate2 doesn't know any " .. (node or "?") .. " spots yet.")
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
end
