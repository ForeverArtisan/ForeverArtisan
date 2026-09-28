-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Mining: node and ore reference data.
-- Skill requirements are the Classic values. Forever may change some; logged data wins when it disagrees.
local _, ns = ...

-- { ore item id (for the icon), node name, skill needed }
ns.NODES = {
  { 2770,  "Copper Vein",                1 },
  { 2771,  "Tin Vein",                  65 },
  { 3340,  "Incendicite Mineral Vein",  65 },
  { 2775,  "Silver Vein",               75 },
  { 4278,  "Lesser Bloodstone Deposit", 75 },
  { 2772,  "Iron Deposit",             125 },
  { 5833,  "Indurium Mineral Vein",    150 },
  { 2776,  "Gold Vein",                155 },
  { 3858,  "Mithril Deposit",          175 },
  { 7911,  "Truesilver Deposit",       230 },
  { 11370, "Dark Iron Deposit",        230 },
  { 10620, "Small Thorium Vein",       245 },
  { 10620, "Rich Thorium Vein",        275 },
}

-- ores: item id -> name, lowest skill that can mine a node giving it
ns.ORES = {}
for _, n in ipairs(ns.NODES) do
  local name = n[2]
  local o = ns.ORES[n[1]]
  if not o or n[3] < o.req then ns.ORES[n[1]] = { req = n[3], node = name } end
end
local ORE_NAMES = {
  [2770] = "Copper Ore", [2771] = "Tin Ore", [3340] = "Incendicite Ore", [2775] = "Silver Ore",
  [4278] = "Lesser Bloodstone Ore", [2772] = "Iron Ore", [5833] = "Indurium Ore", [2776] = "Gold Ore",
  [3858] = "Mithril Ore", [7911] = "Truesilver Ore", [11370] = "Dark Iron Ore", [10620] = "Thorium Ore",
}
for id, name in pairs(ORE_NAMES) do if ns.ORES[id] then ns.ORES[id].name = name end end

-- stones and other extras that come out of nodes
ns.EXTRAS = {
  [2835] = "Rough Stone", [2836] = "Coarse Stone", [2838] = "Heavy Stone",
  [7912] = "Solid Stone", [12365] = "Dense Stone",
}

ns.nodeByName = {}
for _, n in ipairs(ns.NODES) do
  ns.nodeByName[n[2]:lower()] = { id = n[1], name = n[2], req = n[3] }
end

-- "Ooze Covered Mithril Deposit" counts as a Mithril Deposit
function ns.NormalizeNode(name)
  if not name then return end
  local base = name:gsub("^Ooze Covered ", "")
  return ns.nodeByName[base:lower()] and ns.nodeByName[base:lower()].name or base
end

-- Classic gathering colors: orange = always a skill-up, yellow = usually, green = sometimes, gray = never.
function ns.NodeColor(req, skill)
  if not skill or not req then return "unknown" end
  if skill < req then return "red" end
  if skill < req + 25 then return "orange" end
  if skill < req + 50 then return "yellow" end
  if skill < req + 100 then return "green" end
  return "gray"
end

ns.COLOR_CODE = {
  red = "|cffff2020", orange = "|cffff8040", yellow = "|cffffff00",
  green = "|cff40c040", gray = "|cff808080", unknown = "|cffffffff",
}
ns.COLOR_WORD = {
  red = "too high", orange = "orange: always a skill-up", yellow = "yellow: usually a skill-up",
  green = "green: sometimes a skill-up", gray = "gray: no skill-ups", unknown = "",
}
