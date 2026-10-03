-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Camping: camp item and campfire kit names.
-- Names and skill tiers come from the Forever beta (Oct 2026) and may change before launch.
-- Seen in game (Oct 3): Fish Bowl, Incense Candle, Camp Chair, First Aid Kit (all "Requires <profession> (20)",
-- crafted under "Camping" in the profession window) and Basic Campfire Kit (Cooking 1, its own 5-minute cooldown).
-- Only names and tiers: buff values, costs and Blueprint sources are still moving, so they aren't here.
local _, ns = ...

ns.TIERS = { 20, 140, 300 }

-- { profession, skill line, icon, { tier 1, tier 2, tier 3 } }
ns.CAMP = {
  { "Alchemy",        171, "Interface\\Icons\\Trade_Alchemy",              { "Mana Well", "Fermenter", "Alchemy Lab" } },
  { "Blacksmithing",  164, "Interface\\Icons\\Trade_BlackSmithing",        { "Sharpening Wheel", "Anvil", "Master Forge" } },
  { "Enchanting",     333, "Interface\\Icons\\Trade_Engraving",            { "Enchanted Lute", "Arcane Salvager", "Arcane Forge" } },
  { "Engineering",    202, "Interface\\Icons\\Trade_Engineering",          { "Reagent Bot", "Repair Bot", "Workbench" } },
  { "First Aid",      129, "Interface\\Icons\\Spell_Holy_SealOfSacrifice", { "First Aid Kit", "Toxin Study", "Laboratory" } },
  { "Fishing",        356, "Interface\\Icons\\Trade_Fishing",              { "Fish Bowl", "Fishing Rack", "Fishing Hut" } },
  { "Herbalism",      182, "Interface\\Icons\\Trade_Herbalism",            { "Incense Candle", "Greenhouse", "Seed Hybridizer" } },
  { "Leatherworking", 165, "Interface\\Icons\\INV_Misc_ArmorKit_17",       { "Camp Tent", "Tanning Rack", "Sewing Machine" } },
  { "Mining",         186, "Interface\\Icons\\Trade_Mining",               { "Lodestone", "Rock Garden", "Molten Foundry" } },
  { "Skinning",       393, "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",      { "Camp Chair", "Field Guide", "Trapper's Workbench" } },
  { "Tailoring",      197, "Interface\\Icons\\Trade_Tailoring",            { "Faction Banner", "Spinning Wheel", "Loom" } },
}

-- Reagents seen in the profession windows (Oct 3). Opening a window replaces these with what the game says.
ns.SEED_REAGENTS = {
  ["Fish Bowl"]          = { { name = "Raw Brilliant Smallfish", n = 1 }, { name = "Empty Vial", n = 1 } },
  ["Incense Candle"]     = { { name = "Peacebloom", n = 1 }, { name = "Silverleaf", n = 1 } },
  ["Camp Chair"]         = { { name = "Light Leather", n = 3 }, { name = "Simple Wood", n = 2 } },
  ["First Aid Kit"]      = { { name = "Linen Bandage", n = 3 }, { name = "Refreshing Spring Water", n = 1 } },
  ["Basic Campfire Kit"] = { { name = "Simple Wood", n = 1 } },
}

-- What each camp item gives, short, from the item tooltips (Oct 3). Tier 2 and 3 get theirs once we've seen them.
ns.BUFF = {
  ["Fish Bowl"]      = "+stats",
  ["Incense Candle"] = "+Intellect",
  ["Camp Chair"]     = "+crit",
  ["First Aid Kit"]  = "+Stamina",
}

-- Cooking makes the fire. Each kit needs more skill to use than to learn.
ns.KITS = {
  { name = "Basic Campfire Kit",      learn = 1,   use = 1,   slots = 3 },
  { name = "Journeyman Campfire Kit", learn = 90,  use = 140, slots = 5 },
  { name = "Expert Campfire Kit",     learn = 200, use = 220, slots = 10 },
}
ns.COOKING_LINE = 185

-- camp item name -> { prof, tier }
ns.itemByName = {}
for _, p in ipairs(ns.CAMP) do
  for t, name in ipairs(p[4]) do ns.itemByName[name:lower()] = { prof = p[1], tier = t, name = name } end
end
ns.kitByName = {}
for _, k in ipairs(ns.KITS) do ns.kitByName[k.name:lower()] = k end

-- "Anarchist's Workbench" counts as the Workbench; the exact word wins when both match
function ns.CampItem(name)
  if not name then return end
  local low = name:lower()
  if ns.itemByName[low] then return ns.itemByName[low] end
  -- only the Workbench has a longer in-game name; skip the loop for every other item in your bags
  if low:sub(-10) == " workbench" then return ns.itemByName.workbench end
end
