-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Skinning: skill math and leather reference data.
-- Classic values. Forever may change some; your skinning log shows what you actually got.
local _, ns = ...

-- Skill needed to skin a mob of a given level (Classic formula).
function ns.ReqForLevel(level)
  if not level or level < 1 then return nil end
  if level <= 10 then return 1 end
  if level <= 20 then return (level - 10) * 10 end
  return level * 5
end

-- Highest mob level you can skin with a given skill.
function ns.MaxLevelFor(skill)
  if not skill then return nil end
  if skill < 100 then return 10 + math.floor(skill / 10) end
  return math.floor(skill / 5)
end

-- Classic gathering colors: orange = always a skill-up, yellow = usually, green = sometimes, gray = never.
function ns.SkinColor(req, skill)
  if not skill or not req then return "unknown" end
  if skill < req then return "red" end
  if skill < req + 25 then return "orange" end
  if skill < req + 50 then return "yellow" end
  if skill < req + 100 then return "green" end
  return "gray"
end

-- Level range per color for your skill: returns { color = {from, to} }
function ns.LevelBands(skill)
  if not skill then return {} end
  local bands = {}
  for lvl = 1, 63 do
    local c = ns.SkinColor(ns.ReqForLevel(lvl), skill)
    if c ~= "red" then
      local b = bands[c]
      if not b then bands[c] = { lvl, lvl } else b[2] = lvl end
    end
  end
  return bands
end

-- leather and hides: { item id, name, typical mob levels (Classic) }
ns.LEATHER = {
  { 2934, "Ruined Leather Scraps", 1, 20 },
  { 2318, "Light Leather",         5, 25 },
  { 783,  "Light Hide",           10, 25 },
  { 2319, "Medium Leather",       20, 35 },
  { 4232, "Medium Hide",          20, 35 },
  { 4234, "Heavy Leather",        30, 45 },
  { 4235, "Heavy Hide",           30, 45 },
  { 4304, "Thick Leather",        40, 55 },
  { 8169, "Thick Hide",           40, 55 },
  { 8170, "Rugged Leather",       50, 63 },
  { 8171, "Rugged Hide",          50, 63 },
}
-- scales and other skinning extras
ns.EXTRAS = {
  [6470] = "Deviate Scale", [6471] = "Perfect Deviate Scale", [8154] = "Scorpid Scale",
  [8167] = "Turtle Scale", [8165] = "Worn Dragonscale", [7286] = "Black Whelp Scale",
  [7287] = "Red Whelp Scale", [7392] = "Green Whelp Scale",
}
ns.leatherById = {}
for _, l in ipairs(ns.LEATHER) do ns.leatherById[l[1]] = { id = l[1], name = l[2], lo = l[3], hi = l[4] } end

ns.COLOR_CODE = {
  red = "|cffff2020", orange = "|cffff8040", yellow = "|cffffff00",
  green = "|cff40c040", gray = "|cff808080", unknown = "|cffffffff",
}
ns.COLOR_WORD = {
  red = "too high", orange = "orange: always a skill-up", yellow = "yellow: usually a skill-up",
  green = "green: sometimes a skill-up", gray = "gray: no skill-ups", unknown = "",
}
