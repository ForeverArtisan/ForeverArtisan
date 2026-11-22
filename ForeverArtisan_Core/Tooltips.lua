-- ForeverArtisan: which lines ForeverArtisan adds to tooltips, all in one place (0.9.51).
-- One switch per kind of line, shown on the /fa panel's Tooltips tab. Asked for on Discord
-- (Nov 2026: "is there also an option to disable the 'dropped by' on tooltips?").
--
--   FA.TipOn(kind)            true unless that kind of line is turned off
--   FA.SetTip(kind, on, only) turn a kind on or off; "on" also turns the matching window
--                             checkboxes back on, unless only is true (a single window asked)
--   FA.TipOwner(kind, fn)     a module whose window has its own checkbox for this kind:
--                             fn(on) sets that checkbox's saved value
--
-- Saved in ForeverArtisanSettings.tips[kind] = false (nil means on). The older switches still
-- count: priceTips = false (Auction House prices) and deTips = false (disenchant values).

local FA = ForeverArtisan

FA.TIP_KINDS = {
  { key = "price", label = "Auction House price", desc = "What an item sells for at your Auction House, from pages you've seen.",
    note = function() return (type(_G.Auctionator) == "table" and _G.Auctionator.API) and "Auctionator shows its own, so ForeverArtisan stays quiet." or nil end },
  { key = "sell", label = "Where to sell", desc = "Your Auction House or the goblin one, after their cuts, once you've seen both." },
  { key = "drop", label = "Dropped by", desc = "Which mob a material dropped from for you, and where." },
  { key = "sold", label = "Sold by", desc = "Vendors you've met (and Questie's, when installed) who sell it.",
    need = function() return not (FA.Vendors) and "Needs Trade Contacts on." or nil end },
  { key = "recipe", label = "Recipe colors", desc = "On a recipe: the skill where it turns yellow, green and gray, and where you stand." },
  { key = "prof", label = "Used in (your professions)", desc = "Which of your recipes use a material, and whether you know a recipe. Every crafting window, Cooking and First Aid." },
  { key = "gather", label = "Herbs, ore and leather", desc = "Your color for herbs, ore veins and skinnable corpses, and what they give." },
  { key = "de", label = "Disenchant value", desc = "What a green or blue item disenchants into, and what that's worth." },
}

local LEGACY = { price = "priceTips", de = "deTips" }

local function S()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  return ForeverArtisanSettings
end

function FA.TipOn(kind)
  local s = ForeverArtisanSettings
  if not s then return true end
  if s.tips and s.tips[kind] == false then return false end
  if LEGACY[kind] and s[LEGACY[kind]] == false then return false end
  return true
end

local owners = {}
function FA.TipOwner(kind, fn)
  owners[kind] = owners[kind] or {}
  table.insert(owners[kind], fn)
end

function FA.SetTip(kind, on, only)
  local s = S()
  s.tips = s.tips or {}
  if on then s.tips[kind] = nil else s.tips[kind] = false end
  if LEGACY[kind] then
    if on then s[LEGACY[kind]] = nil else s[LEGACY[kind]] = false end
  end
  if next(s.tips) == nil then s.tips = nil end
  if on and not only then
    for _, fn in ipairs(owners[kind] or {}) do pcall(fn, true) end
  end
end
