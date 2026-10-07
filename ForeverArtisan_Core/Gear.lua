-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: profession gear. Reads the tooltips of what you wear and carry, so it knows
-- items Forever adds without a list: "Equip: Increased Fishing +35.", "Requires Fishing (300)",
-- "Use: Replaces the fishing line on your fishing pole...", "Enchanted: Eternium Line".
-- It only says what it finds. It never equips or uses anything for you.
local FA = ForeverArtisan

-- words that tie an "Equip:" line to a profession when there's no "+N" (speed gear and the like)
local WORDS = {
  Fishing = { "fishing" }, Herbalism = { "herbalism", "herb" }, Mining = { "mining", "smelt" },
  Skinning = { "skinning" }, Cooking = { "cooking" }, ["First Aid"] = { "first aid", "bandage" },
  Alchemy = { "alchemy" }, Blacksmithing = { "blacksmithing" }, Enchanting = { "enchanting" },
  Engineering = { "engineering" }, Leatherworking = { "leatherworking" }, Tailoring = { "tailoring" },
}

-- equipment slot for an item's equip location (what it would replace)
local SLOT = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4, INVTYPE_CHEST = 5,
  INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
  INVTYPE_HAND = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15,
  INVTYPE_WEAPON = 16, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17,
  INVTYPE_HOLDABLE = 17, INVTYPE_SHIELD = 17, INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18,
}

local function Plain(v) return type(v) == "string" and not (FA.IsSecret and FA.IsSecret(v)) end

-- the text lines of an item's tooltip, in a bag slot or worn
local scan
local function Lines(bag, slot)
  local out = {}
  local TI = C_TooltipInfo
  local ok, data
  if TI then
    if bag then ok, data = pcall(TI.GetBagItem, bag, slot) else ok, data = pcall(TI.GetInventoryItem, "player", slot) end
  end
  if ok and type(data) == "table" and type(data.lines) == "table" then
    for _, l in ipairs(data.lines) do if Plain(l.leftText) then out[#out + 1] = l.leftText end end
    return out
  end
  if not scan then
    scan = CreateFrame("GameTooltip", "ForeverArtisanGearScan", nil, "GameTooltipTemplate")
  end
  scan:SetOwner(WorldFrame, "ANCHOR_NONE")
  scan:ClearLines()
  if bag then pcall(scan.SetBagItem, scan, bag, slot) else pcall(scan.SetInventoryItem, scan, "player", slot) end
  for i = 1, (scan.NumLines and scan:NumLines() or 0) do
    local fs = _G["ForeverArtisanGearScanTextLeft" .. i]
    local t = fs and fs:GetText()
    if Plain(t) then out[#out + 1] = t end
  end
  return out
end

-- what one item does for a profession, from its tooltip lines
-- a "+N" for a profession in one tooltip line, in any of the ways items and enchants word it:
-- "Equip: Increased Fishing +35.", "Enchanted: Mining +2", "Enchanted: +5 Skinning"
local function Bonus(t, prof)
  local n = t:match("Increased " .. prof .. " %+(%d+)") or t:match(prof .. " %+(%d+)") or t:match("%+(%d+) " .. prof)
  return n and tonumber(n)
end

local function Read(lines, prof)
  local r = {}
  local low = prof:lower()
  for _, t in ipairs(lines) do
    local lt = t:lower()
    if lt:find("^equip:") then
      local n = Bonus(t, prof)
      if n then r.bonus = (r.bonus or 0) + n
      else
        for _, w in ipairs(WORDS[prof] or { low }) do
          if lt:find(w, 1, true) then r.perk = t:gsub("^Equip:%s*", ""); break end
        end
      end
    elseif lt:find("^use:") and prof == "Fishing" and lt:find("fishing pole", 1, true) then
      r.attach = t:gsub("^Use:%s*", "")
    elseif lt:find("^enchanted:") then
      r.enchant = t:gsub("^Enchanted:%s*", "")
      -- glove enchants like "Mining +2" count toward the item's bonus
      local n = Bonus(t, prof)
      if n then r.bonus = (r.bonus or 0) + n end
    end
    local req = t:match("^Requires " .. prof .. " %((%d+)%)")
    if req then r.req = tonumber(req) end
  end
  return r
end

local function ItemName(link)
  return link and link:match("%[(.-)%]") or "?"
end

local function EquipSlot(link)
  local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not (link and Instant) then return end
  local ok, _, _, _, loc = pcall(Instant, link)
  return ok and SLOT[loc] or nil
end

-- this character's skill in a profession (nil if not learned or not readable).
-- The profession list comes first: Forever's skill list can hide rows under a collapsed header.
function FA.ProfSkill(prof)
  local function Num(v) if v == nil or (FA.IsSecret and FA.IsSecret(v)) then return end return tonumber(v) end
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ a, b, c, d, e, f }) do
        local ok2, name, _, rank = pcall(GetProfessionInfo, idx)
        if ok2 and name == prof and Num(rank) then return Num(rank) end
      end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    local ok, n = pcall(GetNumSkillLines)
    for i = 1, (ok and tonumber(n) or 0) do
      local ok2, name, header, _, rank = pcall(GetSkillLineInfo, i)
      if ok2 and not header and name == prof and Num(rank) then return Num(rank) end
    end
  end
  -- a module that tracks its own skill (Fishing reads chat too) can answer last
  local mod = FA.SkillFrom and FA.SkillFrom[prof]
  if mod then local ok, r = pcall(mod); if ok then return Num(r) end end
end

-- What you wear and carry for a profession.
-- { bonus = +N worn, worn = { {name, bonus, perk, slot, enchant} }, better = { {name, bonus, req, ready} },
--   perks = { {name, perk, req, ready} } (in bags, not worn), attach = { {name, req, ready} }, line = "Eternium Line" }
function FA.ProfGear(prof)
  local out = { bonus = 0, worn = {}, better = {}, perks = {}, attach = {} }
  local skill = FA.ProfSkill(prof)
  local wornBySlot = {}
  for slot = 1, 19 do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if Plain(link) then
      local r = Read(Lines(nil, slot), prof)
      wornBySlot[slot] = r.bonus or 0
      if r.bonus or r.perk then
        out.worn[#out.worn + 1] = { name = ItemName(link), bonus = r.bonus, perk = r.perk, slot = slot }
        out.bonus = out.bonus + (r.bonus or 0)
      end
      -- a fishing line on the pole shows as "Enchanted: Eternium Line"
      if prof == "Fishing" and slot == 16 and r.enchant and r.enchant:lower():find("line", 1, true) then
        out.line = r.enchant
      end
    end
  end
  local num = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  if not (num and getLink) then return out end
  for bag = 0, 4 do
    for slot = 1, (num(bag) or 0) do
      local link = getLink(bag, slot)
      if Plain(link) then
        local r = Read(Lines(bag, slot), prof)
        local ready = not r.req or (skill and skill >= r.req) or false
        if r.bonus then
          local es = EquipSlot(link)
          if not es or r.bonus > (wornBySlot[es] or 0) then
            out.better[#out.better + 1] = { name = ItemName(link), bonus = r.bonus, req = r.req, ready = ready }
          end
        elseif r.perk then
          out.perks[#out.perks + 1] = { name = ItemName(link), perk = r.perk, req = r.req, ready = ready }
        elseif r.attach then
          out.attach[#out.attach + 1] = { name = ItemName(link), req = r.req, ready = ready }
        end
      end
    end
  end
  table.sort(out.better, function(a, b)
    if a.ready ~= b.ready then return a.ready end
    return a.bonus > b.bonus
  end)
  return out
end

-- Bags and gear are read once and kept until they change (main tabs refresh often).
local cache, gearCache = {}, {}
local watch = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "SKILL_LINES_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
  pcall(watch.RegisterEvent, watch, e)
end
watch:SetScript("OnEvent", function() wipe(cache); wipe(gearCache) end)
function FA.GearChanged() wipe(cache); wipe(gearCache) end

-- FA.ProfGear, kept until bags or gear change
function FA.GearFor(prof)
  if not gearCache[prof] then
    local ok, g = pcall(FA.ProfGear, prof)
    gearCache[prof] = ok and g or { bonus = 0, worn = {}, better = {}, perks = {}, attach = {} }
  end
  return gearCache[prof]
end

-- Lines for a profession's main tab: what you wear, then anything in your bags worth using.
-- Empty when there's nothing to say.
function FA.GearLines(prof)
  if cache[prof] then return cache[prof] end
  local g = FA.GearFor(prof)
  local GOLD, GREEN, GRAY, YELLOW = FA.GOLD, FA.GREEN, FA.GRAY, FA.YELLOW
  local lines = {}
  local worn = {}
  for _, w in ipairs(g.worn) do
    worn[#worn + 1] = w.name .. (w.bonus and (" +" .. w.bonus) or "")
  end
  if #worn > 0 or g.line then
    lines[#lines + 1] = GOLD .. "Wearing:|r " .. table.concat(worn, ", ")
      .. (g.line and ((#worn > 0 and "  ·  " or "") .. GREEN .. g.line .. " on your pole|r") or "")
  end
  -- every better item, the ones you can use now first (the main tab shows the first; hover shows all)
  for i, b in ipairs(g.better) do
    if i > 4 then break end
    lines[#lines + 1] = (b.ready and GREEN or YELLOW) .. "In your bags:|r " .. b.name .. " +" .. b.bonus .. " "
      .. prof .. (b.ready and (GRAY .. " (equip it)|r") or (GRAY .. (" (usable at %d)|r"):format(b.req)))
  end
  for _, p in ipairs(g.perks) do
    lines[#lines + 1] = (p.ready and GREEN or YELLOW) .. "In your bags:|r " .. p.name .. GRAY .. " (" .. p.perk .. ")|r"
  end
  for _, a in ipairs(g.attach) do
    if g.line == nil then
      lines[#lines + 1] = (a.ready and GREEN or YELLOW) .. "In your bags:|r " .. a.name
        .. GRAY .. (a.ready and " (use it on your pole)|r" or (" (usable at %d)|r"):format(a.req))
    end
  end
  cache[prof] = lines
  return lines
end

-- The one line most worth showing: something in your bags to use first, else what you wear.
function FA.GearLine(prof)
  local lines = FA.GearLines(prof)
  for _, t in ipairs(lines) do if t:find("In your bags", 1, true) then return t end end
  return lines[1]
end
