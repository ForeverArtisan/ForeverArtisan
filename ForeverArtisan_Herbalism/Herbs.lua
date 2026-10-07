-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Herbalism: herb reference data.
-- Skill requirements are the Classic values. Forever may change some; logged data wins when it disagrees.
local _, ns = ...

-- { item id, name, skill needed }
ns.HERBS = {
  { 2447,  "Peacebloom",          1 },
  { 765,   "Silverleaf",          1 },
  { 2449,  "Earthroot",          15 },
  { 785,   "Mageroyal",          50 },
  { 2450,  "Briarthorn",         70 },
  { 3820,  "Stranglekelp",       85 },
  { 2453,  "Bruiseweed",        100 },
  { 3355,  "Wild Steelbloom",   115 },
  { 3369,  "Grave Moss",        120 },
  { 3356,  "Kingsblood",        125 },
  { 3357,  "Liferoot",          150 },
  { 3818,  "Fadeleaf",          160 },
  { 3821,  "Goldthorn",         170 },
  { 3358,  "Khadgar's Whisker", 185 },
  { 3819,  "Wintersbite",       195 },
  { 4625,  "Firebloom",         205 },
  { 8831,  "Purple Lotus",      210 },
  { 8836,  "Arthas' Tears",     220 },
  { 8838,  "Sungrass",          230 },
  { 8839,  "Blindweed",         235 },
  { 8845,  "Ghost Mushroom",    245 },
  { 8846,  "Gromsblood",        250 },
  { 13464, "Golden Sansam",     260 },
  { 13463, "Dreamfoil",         270 },
  { 13465, "Mountain Silversage", 280 },
  { 13466, "Plaguebloom",       285 },
  { 13467, "Icecap",            290 },
  { 13468, "Black Lotus",       300 },
}

-- bonus herbs that drop from other nodes (not nodes themselves)
ns.BONUS = {
  [2452] = "Swiftthistle",   -- Mageroyal, Briarthorn
  [8153] = "Wildvine",       -- Purple Lotus, Arthas' Tears and others
}

ns.herbById, ns.herbByName = {}, {}
for _, h in ipairs(ns.HERBS) do
  local rec = { id = h[1], name = h[2], req = h[3] }
  ns.herbById[rec.id] = rec
  ns.herbByName[rec.name:lower()] = rec
end
-- for crafting shopping lists: the Herbalism skill an herb needs, or nil when it isn't an herb
ForeverArtisan.HerbSkill = function(id) local h = id and ns.herbById[id]; return h and h.req end

-- Classic gathering colors: orange = always a skill-up, yellow = usually, green = sometimes, gray = never.
function ns.HerbColor(req, skill)
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
