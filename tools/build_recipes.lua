-- Builds ForeverArtisan_<Module>/SeedRecipes.lua for each crafting module from the SavedVariables folder:
-- every recipe Kerry's characters saw in a profession window on the Forever beta (Forever's window lists
-- learned and unlearned recipes, with their materials). Plans use it to plan ahead for a profession this
-- character doesn't have yet. Trainer levels come from ForeverArtisan_Contacts/SeedTrainers.lua.
--   lua5.1 tools/build_recipes.lua <SavedVariables folder> [repo folder]
-- Keeps only recipe facts (names, ids, materials, gray level, colors seen). No character names.
-- A recipe counts when at least half the characters that read that window saw it (an old bug saved
-- Alchemy recipes into one character's First Aid list). Never edit the output by hand; rerun this.
local dir = assert(arg[1], "usage: lua5.1 tools/build_recipes.lua <SavedVariables folder> [repo]")
local repo = arg[2] or "."

local MODULES = {
  { "Alchemy", "Alchemy" }, { "Blacksmithing", "Blacksmithing" }, { "Cooking", "Cooking" },
  { "Enchanting", "Enchanting" }, { "Engineering", "Engineering" }, { "FirstAid", "First Aid" },
  { "Leatherworking", "Leatherworking" }, { "Tailoring", "Tailoring" },
}

-- trainer levels and costs: the lowest skill any beta trainer (either faction) teaches it at
local train = {}
do
  local ns = {}
  local f = assert(loadfile(repo .. "/ForeverArtisan_Contacts/SeedTrainers.lua"))
  f(nil, ns)
  for _, t in ipairs(ns.SEED_TRAINERS or {}) do
    for _, s in ipairs(t.skills or {}) do
      local prof, lv = (s.sk or ""):match("^(.-) (%d+)$")
      if prof then
        train[prof] = train[prof] or {}
        local cur = train[prof][s.n]
        lv = tonumber(lv)
        if not cur or lv < cur.at or (lv == cur.at and (s.p or 0) < (cur.p or 0)) then
          train[prof][s.n] = { at = lv, p = s.p }
        end
      end
    end
  end
end

local function q(s) return string.format("%q", s) end
local function sortedKeys(t, cmp)
  local k = {}
  for x in pairs(t) do k[#k + 1] = x end
  table.sort(k, cmp)
  return k
end

for _, m in ipairs(MODULES) do
  local mod, prof = m[1], m[2]
  local path = dir .. "/ForeverArtisan_" .. mod .. ".lua"
  local f = io.open(path, "r")
  local chars = {}
  if f then
    f:close()
    dofile(path)
    local db = _G["ForeverArtisan" .. mod .. "DB"]
    chars = (db and db.chars) or {}
  end
  -- how many characters read this window, and how many saw each recipe
  local readers, seenBy, best, learnedBy, learners = 0, {}, {}, {}, 0
  for _, c in pairs(chars) do
    if c.recipes and next(c.recipes) then
      readers = readers + 1
      local any = false
      for name, r in pairs(c.recipes) do
        if r.learned then any = true; learnedBy[name] = (learnedBy[name] or 0) + 1 end
      end
      if any then learners = learners + 1 end
      for name, r in pairs(c.recipes) do
        seenBy[name] = (seenBy[name] or 0) + 1
        -- keep the fullest record (gray level, colors seen)
        local b = best[name]
        local score = (r.grayAt and 2 or 0) + (r.seen and 1 or 0)
        local bscore = b and ((b.grayAt and 2 or 0) + (b.seen and 1 or 0)) or -1
        if score > bscore then best[name] = r end
      end
    end
  end
  local names, items, rows, trained, starters = {}, {}, 0, 0, 0
  local out = {}
  for _, name in ipairs(sortedKeys(best)) do
    local r = best[name]
    if seenBy[name] * 2 >= readers and r.reagents and #r.reagents > 0 then
      local mats = {}
      for _, g in ipairs(r.reagents) do
        if g.id then
          mats[#mats + 1] = g.id .. "," .. (g.n or 1)
          if g.name then names[g.id] = g.name end
        end
      end
      local tools = {}
      -- a station you stand next to (anvil, forge) is marked with a leading "!"
      for _, t in ipairs(r.tools or {}) do if t.name then tools[#tools + 1] = q((t.station and "!" or "") .. t.name) end end
      local t = train[prof] and train[prof][name]
      -- comes with the profession (no trainer teaches it): every character with the profession knows it;
      -- with only one such character, a low recipe it knows that no trainer teaches
      local starter = not t and learnedBy[name] and ((learners >= 2 and learnedBy[name] == learners)
        or (learners == 1 and (r.grayAt or 999) <= 70))
      local s = r.seen
      local seen = s and ("{o=%s,ylo=%s,yhi=%s,glo=%s}"):format(tostring(s.o), tostring(s.ylo), tostring(s.yhi), tostring(s.glo)) or "nil"
      out[#out + 1] = ("  {%s,%s,%s,%s,%s,{%s},{%s},%s,%s,%s,%s%s},"):format(q(name), tostring(r.id), tostring(r.itemId),
        tostring(r.makes or 1), tostring(r.grayAt), table.concat(mats, ","), table.concat(tools, ","),
        t and tostring(t.at) or "nil", t and tostring(t.p) or "nil", seen, r.group and q(r.group) or "nil",
        starter and ",true" or "")
      if starter then starters = starters + 1 end
      rows = rows + 1
      if t then trained = trained + 1 end
      if r.itemId then items[r.itemId] = true end
    end
  end
  local w = assert(io.open(repo .. "/ForeverArtisan_" .. mod .. "/SeedRecipes.lua", "w"))
  w:write("-- GENERATED by tools/build_recipes.lua from the Forever beta. Do not edit; rerun the script.\n")
  w:write("-- " .. prof .. " recipes seen in the profession window on the Forever beta, so a character without " .. prof .. "\n")
  w:write("-- can plan ahead (Progress tab). Your own window, or an alt's, replaces this once read.\n")
  w:write("-- { name, spell, item, makes, gray at, {item,count,...}, {tools, !station}, train at, train cost, colors seen, group, comes with it }\n")
  w:write("local _, ns = ...\n")
  w:write("local N = {\n")
  for _, id in ipairs(sortedKeys(names)) do w:write(("  [%d]=%s,\n"):format(id, q(names[id]))) end
  w:write("}\n")
  w:write("local R = {\n" .. table.concat(out, "\n") .. (#out > 0 and "\n" or "") .. "}\n")
  w:write([==[
local list
-- the recipes as plans expect them (built once, when first asked for)
function ns.SeedRecipes()
  if list then return list end
  list = {}
  for _, e in ipairs(R) do
    local r = { name = e[1], id = e[2], itemId = e[3], makes = e[4], grayAt = e[5], learned = false, reagents = {},
      seen = e[10], group = e[11], seed = true }
    for i = 1, #e[6], 2 do r.reagents[#r.reagents + 1] = { id = e[6][i], n = e[6][i + 1], name = N[e[6][i]] } end
    if #e[7] > 0 then
      r.tools = {}
      for _, t in ipairs(e[7]) do
        local st = t:sub(1, 1) == "!"
        r.tools[#r.tools + 1] = { name = st and t:sub(2) or t, station = st or nil }
      end
    end
    if e[8] then r.seedTrain = { at = e[8], cost = e[9] }
    elseif e[12] then r.seedTrain = { at = 1, starter = true } end
    list[r.name] = r
  end
  R, N = nil, nil
  return list
end
]==])
  w:close()
  io.stderr:write(("%-15s %3d characters read it, %4d recipes, %3d with a trainer level, %d come with it\n"):format(prof, readers, rows, trained, starters))
end
