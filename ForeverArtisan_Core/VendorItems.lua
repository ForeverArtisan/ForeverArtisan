-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan Core: reagents that only ever come from vendors.
--
-- Trade Contacts only knows the NPCs you've actually met, so an item you haven't seen on a
-- vendor yet would otherwise show nothing on its tooltip and "Drops from mobs" in a shopping
-- list. This is the small, fixed set of vendor-only crafting reagents from Classic, by name,
-- with the kind of vendor that carries it. No NPC names and no coordinates: Forever may place
-- vendors differently, and the moment you meet one the real "Sold by" line takes over.
--
-- Keep this list short and certain. Add a profession's items when its module ships.
local FA = ForeverArtisan

local COOK  = "Cooking Supplies / Trade Goods vendors"
local BAR   = "Bartenders and innkeepers"
local TRADE = "Trade Goods / General Goods vendors"
local SMITH = "Blacksmithing / Mining Supplies vendors"
local ALCH  = "Alchemy Supplies vendors"
local CLOTH = "Tailoring / Leatherworking Supplies vendors"
local ENG   = "Engineering Supplies vendors"
local ENCH  = "Enchanting Supplies vendors"
local FISH  = "Fishing Supplies vendors"

local ITEMS = {
  -- Cooking
  ["Mild Spices"] = COOK, ["Hot Spices"] = COOK, ["Soothing Spices"] = COOK, ["Holiday Spices"] = COOK,
  ["Refreshing Spring Water"] = TRADE, ["Ice Cold Milk"] = TRADE,
  ["Flask of Port"] = BAR, ["Rhapsody Malt"] = BAR, ["Skin of Dwarven Stout"] = BAR,
  -- First Aid: nothing; every bandage reagent is dropped cloth
  -- Blacksmithing / Engineering / Smelting
  ["Weak Flux"] = SMITH, ["Strong Flux"] = SMITH, ["Coal"] = SMITH,
  ["Wooden Stock"] = ENG, ["Heavy Stock"] = ENG,
  -- Alchemy
  ["Empty Vial"] = ALCH, ["Leaded Vial"] = ALCH, ["Crystal Vial"] = ALCH, ["Flask of Oil"] = TRADE,
  -- Tailoring / Leatherworking
  ["Coarse Thread"] = CLOTH, ["Fine Thread"] = CLOTH, ["Silken Thread"] = CLOTH,
  ["Heavy Silken Thread"] = CLOTH, ["Rune Thread"] = CLOTH, ["Salt"] = CLOTH,
  ["Gray Dye"] = CLOTH, ["Red Dye"] = CLOTH, ["Blue Dye"] = CLOTH, ["Green Dye"] = CLOTH,
  ["Yellow Dye"] = CLOTH, ["Orange Dye"] = CLOTH, ["Purple Dye"] = CLOTH, ["Black Dye"] = CLOTH, ["Bleach"] = CLOTH,
  -- Enchanting
  ["Copper Rod"] = ENCH, ["Silver Rod"] = ENCH, ["Golden Rod"] = ENCH, ["Truesilver Rod"] = ENCH,
  -- Fishing lures
  ["Shiny Bauble"] = FISH, ["Nightcrawlers"] = FISH, ["Bright Baubles"] = FISH, ["Aquadynamic Fish Attractor"] = FISH,
}

local byLower = {}
for name, kind in pairs(ITEMS) do byLower[name:lower()] = kind end

FA.VendorItems = ITEMS

-- Returns the vendor kind for a vendor-only reagent, or nil. Accepts a name, an item link,
-- or an item ID (resolved through the item cache when it's loaded).
function FA.VendorHint(item)
  if not item then return nil end
  local name = item
  if type(item) == "number" then
    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    name = GetInfo and GetInfo(item) or nil
  elseif type(item) == "string" and item:find("|h%[") then
    name = item:match("%[(.-)%]")
  end
  return name and byLower[name:lower()] or nil
end
