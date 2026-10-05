-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan Core: minimap buttons. The anvil opens the suite; the book opens Trade Contacts.
-- Left-click opens the hub (/fa); from there each module has an Open button.
-- If another addon ships LibDBIcon we register with it so the button lines up with
-- the others and respects button bags. Otherwise we draw our own round button.
local ADDON = ...
local GREY, GREEN = "|cff9d9d9d", "|cff40ff40"
local PREFIX = ForeverArtisan.Prefix()
local LDB_NAME = "ForeverArtisan"
-- our own textures (ForeverArtisan_Core\Media): the gold FA, and a gold map pin for Trade Contacts
local MEDIA = "Interface\\AddOns\\ForeverArtisan_Core\\Media\\"
local ICON = MEDIA .. "minimap"

local mm, cm, LDBIcon -- cm: the Trade Contacts button
local CONTACTS_LDB = "ForeverArtisanContacts"
local CONTACTS_ICON = MEDIA .. "contacts"

local function S()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  return ForeverArtisanSettings
end

local function OnClick()
  if ForeverArtisan and ForeverArtisan.open then ForeverArtisan.open() end
end

local function TooltipLines(tt)
  tt:AddLine("ForeverArtisan  " .. ForeverArtisan.VersionTag())
  local mods = ForeverArtisan and ForeverArtisan.modules and ForeverArtisan.modules() or {}
  local any = false
  for _, m in ipairs(mods) do
    if m.loaded and m.isProf then
      any = true
      tt:AddDoubleLine(m.title, GREY .. "/fa " .. (m.alias ~= "" and m.alias or m.key) .. "|r", 1, 1, 1)
    end
  end
  if not any then tt:AddLine(GREY .. "No modules running yet.|r") end
  tt:AddLine(" ")
  tt:AddLine(GREEN .. "Click:|r open ForeverArtisan", 1, 1, 1)
  tt:AddLine(GREEN .. "Drag:|r move around the minimap", 1, 1, 1)
  tt:AddLine(GREY .. "/fa minimap hides it|r")
end

-- angles (degrees) other minimap icons already use
local function TakenAngles()
  local taken = {}
  if LDBIcon and LDBIcon.GetButtonList then
    for _, name in ipairs(LDBIcon:GetButtonList()) do
      local b = LDBIcon:GetMinimapButton(name)
      if b and b.db and b.db.minimapPos and name ~= LDB_NAME and name ~= CONTACTS_LDB then taken[#taken + 1] = b.db.minimapPos end
    end
  end
  for _, child in ipairs({ Minimap:GetChildren() }) do
    if child ~= mm and child ~= cm and child:IsShown() and child.GetCenter and child:GetCenter() then
      local cx, cy = child:GetCenter(); local mx, my = Minimap:GetCenter()
      if cx and mx and child:GetWidth() < 40 then
        local d = math.sqrt((cx - mx) ^ 2 + (cy - my) ^ 2)
        if d > Minimap:GetWidth() / 2 - 15 then taken[#taken + 1] = math.deg(math.atan2(cy - my, cx - mx)) % 360 end
      end
    end
  end
  return taken
end

local function FreeAngle()
  local taken, best, bestGap = TakenAngles(), 200, -1
  for a = 0, 355, 5 do
    local gap = 360
    for _, t in ipairs(taken) do
      local d = math.abs(((a - t) + 180) % 360 - 180)
      if d < gap then gap = d end
    end
    if gap > bestGap then best, bestGap = a, gap end
  end
  return best
end

-- Our own round minimap buttons (when no LibDBIcon): b.cfg says where its angle and hidden flag live.
local function PlaceOwnButton(b)
  b = b or mm
  local cfg = b.cfg
  local a = math.rad(S()[cfg.angleKey] or cfg.default or 200)
  local r = (Minimap:GetWidth() / 2) + 6
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildOwnButton(cfg)
  local b = CreateFrame("Button", cfg.frameName, Minimap)
  b.cfg = cfg
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(Minimap:GetFrameLevel() + 12)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  -- same layout as current LibDBIcon: the dark disc and the icon sit on the ring's center
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); bg:SetSize(24, 24); bg:SetPoint("CENTER", 0, 1)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(cfg.icon); icon:SetSize(18, 18); icon:SetPoint("CENTER", 0, 1)
  icon:SetTexCoord(0, 1, 0, 1) -- our icons carry their own padding, unlike the game's bordered ones
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(50, 50); border:SetPoint("TOPLEFT")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", cfg.onClick)
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local sc = Minimap:GetEffectiveScale()
      S()[cfg.angleKey] = math.deg(math.atan2(py / sc - my, px / sc - mx)) % 360
      PlaceOwnButton(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); cfg.tooltip(GameTooltip); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  PlaceOwnButton(b)
  b:SetShown(not S()[cfg.hideKey])
  return b
end

-- The button used to belong to Fishing. Keep its spot so it doesn't jump.
local function CarryOverFishingSpot()
  local s = S()
  if s.minimapAngle or (s.ldbIcon and s.ldbIcon.minimapPos) then return end
  local fs = ForeverArtisanFishingDB and ForeverArtisanFishingDB.settings
  if not fs then return end
  local pos = (fs.ldbIcon and fs.ldbIcon.minimapPos) or fs.minimapAngle
  if pos then
    s.minimapAngle = pos
    s.ldbIcon = s.ldbIcon or {}
    s.ldbIcon.minimapPos = pos
  end
  if fs.minimapHide ~= nil then s.minimapHide = fs.minimapHide end
end

-- Trade Contacts: its own button, one click to the search (only while Trade Contacts is on)
local function ContactsClick(_, button)
  local V = ForeverArtisan and ForeverArtisan.Vendors
  if V and V.open then V.open() end
end
local function ContactsTip(tt)
  tt:AddLine("ForeverArtisan: Trade Contacts")
  tt:AddLine("Every crafting vendor and trainer you've met. Search them, find the nearest trainer, get a waypoint.", 1, 1, 1, true)
  tt:AddLine(" ")
  tt:AddLine(GREEN .. "Click:|r open Trade Contacts", 1, 1, 1)
  tt:AddLine(GREEN .. "Drag:|r move around the minimap", 1, 1, 1)
  tt:AddLine(GREY .. "/fa minimap contacts hides it|r")
end

local function BuildContacts()
  if cm or not (ForeverArtisan and ForeverArtisan.Vendors) then return end
  local s = S()
  if LDBIcon then
    local LDB = LibStub("LibDataBroker-1.1", true)
    local obj = LDB:NewDataObject(CONTACTS_LDB, {
      type = "launcher", text = "Trade Contacts", icon = CONTACTS_ICON,
      OnClick = ContactsClick, OnTooltipShow = ContactsTip,
    })
    s.contactsIcon = s.contactsIcon or {}
    if s.contactsIcon.minimapPos == nil then s.contactsIcon.minimapPos = s.contactsAngle or FreeAngle() end
    s.contactsIcon.hide = s.contactsHide and true or false
    LDBIcon:Register(CONTACTS_LDB, obj, s.contactsIcon)
    cm = LDBIcon:GetMinimapButton(CONTACTS_LDB)
  else
    if not s.contactsAngle then s.contactsAngle = FreeAngle() end
    cm = BuildOwnButton({ frameName = "ForeverArtisanContactsMinimapButton", icon = CONTACTS_ICON, onClick = ContactsClick,
      tooltip = ContactsTip, angleKey = "contactsAngle", hideKey = "contactsHide" })
  end
end

local function Build()
  if not Minimap or mm then return end
  CarryOverFishingSpot()
  local s = S()
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
  if LDB and LDBIcon then
    local obj = LDB:NewDataObject(LDB_NAME, {
      type = "launcher", text = "ForeverArtisan", icon = ICON,
      OnClick = OnClick,
      OnTooltipShow = function(tt) TooltipLines(tt) end,
    })
    s.ldbIcon = s.ldbIcon or {}
    if s.ldbIcon.minimapPos == nil then s.ldbIcon.minimapPos = s.minimapAngle or FreeAngle() end
    s.ldbIcon.hide = s.minimapHide and true or false
    LDBIcon:Register(LDB_NAME, obj, s.ldbIcon)
    mm = LDBIcon:GetMinimapButton(LDB_NAME)
  else
    LDBIcon = nil
    if not s.minimapAngle then s.minimapAngle = FreeAngle() end
    mm = BuildOwnButton({ frameName = "ForeverArtisanMinimapButton", icon = ICON, onClick = OnClick,
      tooltip = TooltipLines, angleKey = "minimapAngle", hideKey = "minimapHide" })
  end
end

-- /fa minimap          -> show / hide
-- /fa minimap <0-359>  -> move to that angle (0 = right, 90 = top, 180 = left, 270 = bottom)
-- /fa minimap reset    -> pick the emptiest spot again
-- /fa minimap contacts -> show / hide the Trade Contacts button
local function Command(arg)
  arg = (arg or ""):lower()
  local s = S()
  if arg == "contacts" then
    s.contactsHide = not s.contactsHide
    if LDBIcon and s.contactsIcon then
      s.contactsIcon.hide = s.contactsHide
      if s.contactsHide then LDBIcon:Hide(CONTACTS_LDB) else LDBIcon:Show(CONTACTS_LDB) end
    elseif cm then
      cm:SetShown(not s.contactsHide)
    end
    print(PREFIX .. (s.contactsHide and "Trade Contacts minimap button hidden. /fa minimap contacts brings it back."
      or "Trade Contacts minimap button shown. Drag it to move it."))
    return
  end
  local angle = tonumber(arg)
  if arg == "reset" then angle = FreeAngle() end
  if angle then
    angle = angle % 360
    s.minimapHide = false
    if LDBIcon then
      s.ldbIcon.minimapPos = angle; s.ldbIcon.hide = false
      LDBIcon:Show(LDB_NAME); LDBIcon:Refresh(LDB_NAME, s.ldbIcon)
    elseif mm then
      s.minimapAngle = angle; PlaceOwnButton(mm); mm:Show()
    end
    print(PREFIX .. ("minimap button moved to %d degrees."):format(angle))
    return
  end
  s.minimapHide = not s.minimapHide
  if LDBIcon then
    s.ldbIcon.hide = s.minimapHide
    if s.minimapHide then LDBIcon:Hide(LDB_NAME) else LDBIcon:Show(LDB_NAME) end
  elseif mm then
    mm:SetShown(not s.minimapHide)
  end
  print(PREFIX .. (s.minimapHide and "minimap button hidden. /fa minimap brings it back."
    or "minimap button shown. Drag it, or use /fa minimap 90 (top), 180 (left), 270 (bottom), 0 (right)."))
end

ForeverArtisan = ForeverArtisan or {}
ForeverArtisan.minimap = Command

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() pcall(Build); pcall(BuildContacts) end)
