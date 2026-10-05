-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: NPC names in town.
-- Friendly NPC nameplates show their job under the name, like <Leatherworking Trainer>. The game's own
-- nameplates never show titles. This lives in Core so it works for everyone, with or without Trade
-- Contacts. When Trade Contacts runs, it uses the same switch to note the crafting NPCs you pass, and
-- colors the titles it cares about (FA.TitleRelevant) and fills in titles it already saved (FA.KnownTitle).
local FA = ForeverArtisan

local PREFIX = FA.Prefix()
local PLATE_CVARS = { "nameplateShowFriends", "nameplateShowFriendlyNPCs" }

local function S()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  return ForeverArtisanSettings
end

-- On unless the player turned it off. Before 0.9.10 the switch lived in Trade Contacts (scoutOff).
function FA.TownNamesOn()
  local s = S()
  if s.townNames == nil then
    s.townNames = not (ForeverArtisanContactsDB and ForeverArtisanContactsDB.scoutOff)
  end
  return s.townNames and true or false
end

---------------------------------------------------------------- reading titles
local tip = CreateFrame("GameTooltip", "ForeverArtisanTitleScanTip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function NpcId(guid)
  if not guid or FA.IsSecret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- the "<Title>" line under an NPC's name in its tooltip, e.g. "Leatherworking Supplies"
local function ReadTitle(unit)
  tip:ClearLines()
  tip:SetUnit(unit)
  for i = 2, math.min(tip:NumLines(), 3) do
    local fs = _G["ForeverArtisanTitleScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if FA.IsSecret(t) then return nil end
    if t and t:match("^<.+>$") then return t:sub(2, -2) end
    -- some Classic clients show titles without brackets
    if t and i == 2 and not t:find(LEVEL or "Level") and not t:find("PvP") and not t:find("%d") then return t end
  end
end

local titleOf = {} -- npc id -> title, or false for NPCs without one (most of a town): read the tooltip once
function FA.NpcTitle(unit)
  local id = NpcId(UnitGUID(unit))
  if id then
    local known = FA.KnownTitle and FA.KnownTitle(id)
    if known then return known, id end
    if titleOf[id] == nil then titleOf[id] = ReadTitle(unit) or false end
    return titleOf[id] or nil, id
  end
  return ReadTitle(unit), nil
end

-- gold for crafting NPCs: Trade Contacts knows exactly which; without it, a short list of obvious words
local CRAFT_WORDS = { "trainer", "supplies", "supplier", "vendor", "merchant", "goods", "trade" }
local function Relevant(title)
  if FA.TitleRelevant then return FA.TitleRelevant(title) end
  local t = title:lower()
  for _, w in ipairs(CRAFT_WORDS) do if t:find(w, 1, true) then return true end end
  return false
end

---------------------------------------------------------------- drawing
local labeled = {}

local function Friendly(unit)
  if not UnitExists(unit) or UnitIsPlayer(unit) then return false end
  local reaction = UnitReaction(unit, "player")
  return reaction and not FA.IsSecret(reaction) and reaction >= 4
end

local function PlateTitle(unit)
  if not FA.TownNamesOn() or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
  if not Friendly(unit) then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
  local title = FA.NpcTitle(unit)
  plate.faTitleDone = true
  if not plate.faTitle then
    -- our own small frame above the nameplate's art, so the health bar can't cover the text
    local holder = CreateFrame("Frame", nil, plate)
    holder:SetAllPoints(plate)
    if plate.GetFrameStrata then holder:SetFrameStrata(plate:GetFrameStrata()) end
    local base = (plate.UnitFrame and plate.UnitFrame.GetFrameLevel and plate.UnitFrame:GetFrameLevel())
      or (plate.GetFrameLevel and plate:GetFrameLevel()) or 1
    holder:SetFrameLevel(base + 10)
    plate.faTitle = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plate.faTitle:SetShadowOffset(1, -1)
    labeled[#labeled + 1] = plate.faTitle
  end
  local fs = plate.faTitle
  if not title then fs:Hide(); return end
  -- under the health bar, or under the name when the plate has no bar
  local uf = plate.UnitFrame
  local anchor = uf and (uf.healthBar or uf.HealthBar or uf.name) or plate
  fs:ClearAllPoints()
  fs:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
  fs:SetText("<" .. title .. ">")
  if Relevant(title) then fs:SetTextColor(1, 0.82, 0.3) else fs:SetTextColor(0.75, 0.75, 0.75) end
  fs:Show()
end

local function HideTitle(unit)
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
  if plate then plate.faTitleDone = nil; if plate.faTitle then plate.faTitle:Hide() end end
end

local function HideAll() for _, fs in ipairs(labeled) do fs:Hide() end end

-- plates already on screen (after /reload, or when the switch is turned on) get their titles too
local ticker
local function StartTicker()
  if ticker or not (C_Timer and C_Timer.NewTicker and C_NamePlate and C_NamePlate.GetNamePlates) then return end
  ticker = C_Timer.NewTicker(0.5, function()
    if not FA.TownNamesOn() or InCombatLockdown() then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
      if unit and not plate.faTitleDone then pcall(PlateTitle, unit) end
      -- Trade Contacts notes NPCs as you pass them (and sharpens where they stand)
      if unit and FA.OnTownUnit then pcall(FA.OnTownUnit, unit) end
    end
  end)
end

---------------------------------------------------------------- the switch
-- Friendly NPC nameplates have to be on for names in town; the player's own settings come back when off.
local function SetPlates(on)
  local s = S()
  s.savedPlateCVars = s.savedPlateCVars or {}
  -- carry over what Trade Contacts saved before 0.9.10
  local old = ForeverArtisanContactsDB and ForeverArtisanContactsDB.savedCVars
  if old then
    for k, v in pairs(old) do if s.savedPlateCVars[k] == nil then s.savedPlateCVars[k] = v end end
    ForeverArtisanContactsDB.savedCVars = nil
  end
  for _, cv in ipairs(PLATE_CVARS) do
    local ok, cur = pcall(GetCVar, cv)
    if ok and cur ~= nil then
      if on then
        if s.savedPlateCVars[cv] == nil then s.savedPlateCVars[cv] = cur end
        pcall(SetCVar, cv, "1")
      elseif s.savedPlateCVars[cv] ~= nil then
        pcall(SetCVar, cv, s.savedPlateCVars[cv])
        s.savedPlateCVars[cv] = nil
      end
    end
  end
end

-- quiet = no chat line (slash commands print their own)
function FA.SetTownNames(on, quiet)
  on = on and true or false
  S().townNames = on
  if ForeverArtisanContactsDB then ForeverArtisanContactsDB.scoutOff = (not on) or nil end
  SetPlates(on)
  if on then StartTicker() else HideAll() end
  if not quiet then
    print(PREFIX .. (on and "NPC names in town on. Friendly NPCs show their job under their name."
      or "NPC names in town off. Your nameplate settings are back."))
  end
  if FA.OnTownNamesChanged then pcall(FA.OnTownNamesChanged, on) end
end

-- the switch's hover text; Trade Contacts adds what it does with it
function FA.TownNamesTip(tt)
  tt:AddLine("Show NPC names in town")
  tt:AddLine("Friendly NPCs show their job under their name, like <Leatherworking Trainer>.", 1, 1, 1, true)
  if FA.TownNamesExtraTip then
    FA.TownNamesExtraTip(tt)
  end
  tt:AddLine(" ")
  tt:AddLine("Turn it off and your own nameplate settings come back.", 0.6, 0.6, 0.6, true)
  tt:AddLine("Open world only: the game hides nameplates in dungeons.", 0.6, 0.6, 0.6, true)
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, unit)
  if e == "PLAYER_LOGIN" then
    -- the nameplate settings only change when the player flips the switch, never at login
    if FA.TownNamesOn() then StartTicker() end
  elseif e == "NAME_PLATE_UNIT_REMOVED" then
    if unit then HideTitle(unit) end
  elseif e == "NAME_PLATE_UNIT_ADDED" and unit and FA.TownNamesOn() and not InCombatLockdown() then
    pcall(PlateTitle, unit)
  end
end)
FA.GuardEvents(ev)
