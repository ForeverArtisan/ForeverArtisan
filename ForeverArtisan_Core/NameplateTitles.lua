-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: job titles under NPC names in town.
-- Friendly NPC nameplates show their job under the name, like <Leatherworking Trainer>. The game's own
-- nameplates never show titles. This lives in Core so it works for everyone, with or without Trade Contacts.
-- It needs the game's friendly NPC nameplates on: ForeverArtisan never changes that setting by itself.
-- When they're off, a chat line in town says so once per session, and /fa nameplates turns them on.
-- Trade Contacts notes the crafting NPCs you pass from the same nameplates (FA.OnTownUnit), colors the
-- titles it cares about (FA.TitleRelevant) and fills in titles it already saved (FA.KnownTitle).
local FA = ForeverArtisan

local PREFIX = FA.Prefix()
local PLATE_CVARS = { "nameplateShowFriends", "nameplateShowFriendlyNPCs" }

local function S()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  return ForeverArtisanSettings
end

-- Nameplate addons that draw their own plates (and usually titles). With one of these running we leave
-- titles to it, so nobody sees the same title twice. Trade Contacts' noting of NPCs still works either way.
FA.PLATE_ADDONS = {
  { "Plater", "Plater" }, { "TidyPlates_ThreatPlates", "Threat Plates" }, { "TidyPlates", "Tidy Plates" },
  { "NeatPlates", "Neat Plates" }, { "Kui_Nameplates", "KuiNameplates" }, { "Platynator", "Platynator" },
  { "nPlates", "nPlates" },
}
local function Loaded(name)
  local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local ok, on = pcall(f, name)
  return ok and on
end
function FA.OtherPlatesAddon()
  for _, a in ipairs(FA.PLATE_ADDONS) do if Loaded(a[1]) then return a[2] end end
  -- ElvUI only counts when its own nameplates are on
  local E = ElvUI and ElvUI[1]
  if E and E.private and E.private.nameplates and E.private.nameplates.enable then return "ElvUI" end
end

-- Titles: automatic (on, unless another nameplate addon is running) until the player picks with /fa titles.
-- The old Trade Contacts switch (scoutOff) is ignored on purpose: it mostly meant "don't touch my nameplates".
function FA.TownNamesOn()
  local pick = S().titlesPick
  if pick ~= nil then return pick and true or false end
  return FA.OtherPlatesAddon() == nil
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
  -- another addon replaced the game's plate (it hides the original): there's nothing of ours to sit under
  local uf = plate.UnitFrame
  if uf and uf.IsShown and not uf:IsShown() then
    if plate.faTitle then plate.faTitle:Hide() end
    return
  end
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

-- plates already on screen (after /reload, or right after nameplates are turned on) get their titles too
local ticker
local function StartTicker()
  if ticker or not (C_Timer and C_Timer.NewTicker and C_NamePlate and C_NamePlate.GetNamePlates) then return end
  ticker = C_Timer.NewTicker(0.5, function()
    if InCombatLockdown() then return end
    local titles = FA.TownNamesOn()
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
      local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
      if titles and unit and not plate.faTitleDone then pcall(PlateTitle, unit) end
      -- Trade Contacts notes NPCs as you pass them (and sharpens where they stand)
      if unit and FA.OnTownUnit then pcall(FA.OnTownUnit, unit) end
    end
  end)
end

---------------------------------------------------------------- friendly NPC nameplates (the game's setting)
-- Titles and Trade Contacts' town scouting both read friendly NPC nameplates, so they need them on.
-- ForeverArtisan only changes this when the player asks (/fa nameplates or the panel button).
function FA.FriendlyPlatesOn()
  for _, cv in ipairs(PLATE_CVARS) do
    local ok, v = pcall(GetCVar, cv)
    if ok and v == "0" then return false end
  end
  return true
end

FA.PLATES_OFF_LINE = "Friendly NPC nameplates are off, so ForeverArtisan can't show job titles under NPC names "
  .. "or note the crafting NPCs you pass in town. Type /fa nameplates to turn them on."

function FA.TurnOnFriendlyPlates()
  for _, cv in ipairs(PLATE_CVARS) do pcall(SetCVar, cv, "1") end
  StartTicker()
  print(PREFIX .. "Friendly NPC nameplates on. NPCs in town now show their job under their name"
    .. (FA.Vendors and ", and Trade Contacts notes the crafting NPCs you pass." or "."))
  if FA.OnTownNamesChanged then pcall(FA.OnTownNamesChanged, true) end
end

-- /fa titles on|off|auto: just the job titles; the nameplates themselves stay as the player set them.
-- on = true or false is the player's pick; nil goes back to automatic.
function FA.SetTownNames(on, quiet)
  if on ~= nil then on = on and true or false end
  S().titlesPick = on
  local now = FA.TownNamesOn()
  if now then StartTicker() else HideAll() end
  if not quiet then
    local other = FA.OtherPlatesAddon()
    if on == nil then
      print(PREFIX .. "Job titles under NPC names: automatic (" .. (now and "on" or ("off, " .. other .. " shows NPC names")) .. ").")
    else
      print(PREFIX .. (on and "Job titles under NPC names on." or "Job titles under NPC names off. /fa titles on brings them back."))
    end
    if now and not FA.FriendlyPlatesOn() then print(PREFIX .. FA.PLATES_OFF_LINE) end
  end
  if FA.OnTownNamesChanged then pcall(FA.OnTownNamesChanged, now) end
end

-- one line for the /fa panel and Trade Contacts' Search tab; platesOff means show a "turn on" button
function FA.TownStatus()
  local contacts = FA.Vendors ~= nil
  if not FA.FriendlyPlatesOn() then
    return FA.GOLD .. "Friendly NPC nameplates are off.|r Turn them on to see job titles in town"
      .. (contacts and " and let Trade Contacts note the crafting NPCs you pass." or "."), true
  end
  local noted = contacts and " Crafting NPCs you pass are noted." or ""
  if FA.TownNamesOn() then
    return FA.GRAY .. "Job titles show under NPC names in town." .. noted .. "|r", false
  end
  local other = S().titlesPick == nil and FA.OtherPlatesAddon()
  if other then
    return FA.GRAY .. other .. " runs your nameplates, so ForeverArtisan leaves NPC titles to it." .. noted .. "|r", false
  end
  return FA.GRAY .. "Job titles under NPC names are off (/fa titles on)." .. noted .. "|r", false
end

-- hover text for that line
function FA.TownNamesTip(tt)
  tt:AddLine("Names in town")
  tt:AddLine("Friendly NPCs show their job under their name, like <Leatherworking Trainer>. "
    .. "Crafting trainers and suppliers are gold.", 1, 1, 1, true)
  tt:AddLine(" ")
  tt:AddLine("This reads the game's friendly NPC nameplates, so they have to be on. "
    .. "ForeverArtisan never changes that setting unless you ask it to.", 1, 1, 1, true)
  if FA.FriendlyPlatesOn() then
    tt:AddLine("Friendly NPC nameplates: on", 0.3, 1, 0.3)
  else
    tt:AddLine("Friendly NPC nameplates: OFF. Click Turn on nameplates, or type /fa nameplates.", 1, 0.3, 0.3, true)
  end
  if FA.TownNamesExtraTip then FA.TownNamesExtraTip(tt) end
  tt:AddLine(" ")
  local other = FA.OtherPlatesAddon()
  if other then
    tt:AddLine(other .. " is running, so titles are left to it unless you type /fa titles on.", 0.6, 0.6, 0.6, true)
  end
  tt:AddLine("/fa titles on | off | auto picks for yourself. Your nameplates stay as they are.", 0.6, 0.6, 0.6, true)
end

-- once per session, in a town (resting), when the nameplates the titles need are off
local warned = false
local function MaybeWarn()
  if warned or FA.FriendlyPlatesOn() or not (IsResting and IsResting()) then return end
  warned = true
  print(PREFIX .. FA.PLATES_OFF_LINE)
end

-- earlier versions switched friendly nameplates on and saved the player's old values to put back;
-- now the player owns that setting, so keep it as it is and forget the saved copies
local function ForgetSavedPlates()
  local s = S()
  s.savedPlateCVars = nil
  s.townNames = nil -- 0.9.10 test builds saved this without asking; titlesPick is the player's own choice
  if ForeverArtisanContactsDB then ForeverArtisanContactsDB.savedCVars = nil end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, unit)
  if e == "PLAYER_LOGIN" then
    ForgetSavedPlates()
    StartTicker()
    if C_Timer then C_Timer.After(8, MaybeWarn) end
  elseif e == "PLAYER_UPDATE_RESTING" or e == "ZONE_CHANGED_NEW_AREA" then
    MaybeWarn()
  elseif e == "NAME_PLATE_UNIT_REMOVED" then
    if unit then HideTitle(unit) end
  elseif e == "NAME_PLATE_UNIT_ADDED" and unit and FA.TownNamesOn() and not InCombatLockdown() then
    pcall(PlateTitle, unit)
  end
end)
FA.GuardEvents(ev)
