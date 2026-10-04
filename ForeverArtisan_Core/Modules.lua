-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan Core: module manager.
-- /fa            open the module panel
-- /fa <module>   pass a command to a module (/fa fish zone, /fa log help)
-- /fa <text>     anything else searches vendors
-- Modules are any installed addon named ForeverArtisan_<Name>. A module can add
-- "## X-FA-Slash: <SlashCmdList key>" and "## X-FA-Alias: <short name>" to its TOC
-- so /fa can forward commands to it.
local ADDON = ...
local FA = ForeverArtisan
local GOLD, GREY, GREEN, RED = FA.GOLD, FA.GRAY, FA.GREEN, FA.RED
local PREFIX = FA.Prefix()
local MODULE_PREFIX = "ForeverArtisan_"

---------------------------------------------------------------- addon API (works on old and new clients)

local A = C_AddOns or {}
local GetNum = A.GetNumAddOns or GetNumAddOns
local GetInfo = A.GetAddOnInfo or GetAddOnInfo
local IsLoaded = A.IsAddOnLoaded or IsAddOnLoaded
local GetMeta = A.GetAddOnMetadata or GetAddOnMetadata
local EnableAO = A.EnableAddOn or EnableAddOn
local DisableAO = A.DisableAddOn or DisableAddOn

-- Changes made in the panel this session (the game only applies them after a reload).
local intent = {}

-- Is this addon turned on for the character you're playing?
local function isEnabled(name)
  if intent[name] ~= nil then return intent[name] end
  local _, _, _, loadable, reason = GetInfo(name)
  if reason == "DISABLED" then return false end
  if IsLoaded(name) then return true end
  local who = UnitName("player")
  local ok, state
  if A.GetAddOnEnableState then
    ok, state = pcall(A.GetAddOnEnableState, name, who)
    if not (ok and type(state) == "number") then ok, state = pcall(A.GetAddOnEnableState, who, name) end
  elseif GetAddOnEnableState then
    ok, state = pcall(GetAddOnEnableState, who, name)
  end
  if ok and type(state) == "number" then return state == 2 end
  return loadable and true or false
end

-- Turn an addon on or off for this character and for all characters,
-- so a per-character setting can't quietly keep it off.
local function setAddOn(name, on)
  local f = on and EnableAO or DisableAO
  pcall(f, name)
  pcall(f, name, UnitName("player"))
  intent[name] = on
end

local function meta(name, field)
  local ok, v = pcall(GetMeta, name, field)
  return ok and v or nil
end

---------------------------------------------------------------- module list

local modules, pending = {}, false

-- Planned modules. Any that aren't installed show in the panel as "Coming soon".
local PLANNED = {
  "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid",
  "Fishing", "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring",
}
local SOON_COLS, SOON_H = 3, 18

local function comingSoon()
  local have, out = {}, {}
  for _, m in ipairs(modules) do have[m.title:lower()] = true; have[m.key] = true end
  for _, name in ipairs(PLANNED) do
    local k = name:lower()
    if not have[k] and not have[(k:gsub("%s", ""))] then out[#out + 1] = name end
  end
  return out
end

local function scan()
  wipe(modules)
  for i = 1, GetNum() do
    local name, title, notes = GetInfo(i)
    if name and name:sub(1, #MODULE_PREFIX) == MODULE_PREFIX and name ~= ADDON then
      local key = name:sub(#MODULE_PREFIX + 1):lower()
      modules[#modules + 1] = {
        name = name,
        key = key,
        alias = (meta(name, "X-FA-Alias") or ""):lower(),
        slash = meta(name, "X-FA-Slash"),
        title = (title or name):gsub("^ForeverArtisan:%s*", ""),
        notes = notes or "",
        loaded = IsLoaded(name) and true or false,
        version = meta(name, "Version"),
        enabled = isEnabled(name),
      }
    end
  end
  -- professions first (A to Z), then tools like the Logger
  local isProf = {}
  for _, n in ipairs(PLANNED) do isProf[n:lower()] = true end
  for _, m in ipairs(modules) do m.isProf = isProf[m.title:lower()] or false end
  table.sort(modules, function(a, b)
    local pa, pb = isProf[a.title:lower()] or false, isProf[b.title:lower()] or false
    if pa ~= pb then return pa end
    return a.title < b.title
  end)
  return modules
end

-- what people type for a profession: the person ("blacksmith", "enchanter") or a short start of it
local NOUNS = {
  blacksmith = "blacksmithing", smith = "blacksmithing", armorsmith = "blacksmithing", weaponsmith = "blacksmithing",
  tailor = "tailoring", engineer = "engineering", enchanter = "enchanting", alchemist = "alchemy",
  leatherworker = "leatherworking", cook = "cooking", chef = "cooking", fisher = "fishing", fisherman = "fishing",
  herbalist = "herbalism", herbs = "herbalism", miner = "mining", skinner = "skinning", firstaid = "firstaid",
  medic = "firstaid", contacts = "contacts", vendors = "contacts",
  campfire = "camping", camps = "camping", campsite = "camping",
}

local function find(word)
  word = (word or ""):lower()
  if word == "" then return end
  local mods = scan()
  for _, m in ipairs(mods) do
    if m.key == word or m.alias == word or m.title:lower() == word then return m end
  end
  local key = NOUNS[word] or NOUNS[(word:gsub("s$", ""))]
  if key then
    for _, m in ipairs(mods) do if m.key == key then return m end end
  end
  -- a clear start of one profession's name ("black", "leather", "engin"), never a shared one
  if #word >= 4 then
    local hit
    for _, m in ipairs(mods) do
      if m.isProf and (m.key:sub(1, #word) == word or m.title:lower():sub(1, #word) == word) then
        if hit then return end
        hit = m
      end
    end
    return hit
  end
end

local function setEnabled(m, on)
  setAddOn(m.name, on)
  m.enabled = on
  pending = true
  print(PREFIX .. m.title .. (on and " turned on." or " turned off.") .. " Type /reload to apply.")
end

---------------------------------------------------------------- panel

local ROW_H = 30 -- compact: every profession has a module now, so notes live in the hover tooltip
local panel

-- a module whose version doesn't match Core came from a different download
local function outdated(m)
  return m.loaded and m.version and m.version ~= FA.Version()
end

local function statusText(m)
  if outdated(m) then return RED .. "Update needed|r" end
  if m.enabled and m.loaded then return GREEN .. "Running|r" end
  if not m.enabled and not m.loaded then return GREY .. "Off|r" end
  return GOLD .. "Reload to apply|r"
end

local function refreshPanel()
  if not panel then return end
  scan()
  for i, row in ipairs(panel.rows) do
    local m = modules[i]
    if m then
      row.m = m
      row.check:SetChecked(m.enabled)
      row.title:SetText(m.title .. (m.alias ~= "" and (GREY .. "   /fa " .. m.alias .. "|r") or ""))
      row.notes:SetText(m.notes)
      row.status:SetText(statusText(m))
      row.open:SetShown(m.loaded and m.slash ~= nil)
      row:Show()
    else
      row.m = nil
      row:Hide()
    end
  end
  panel.empty:SetShown(#modules == 0)
  panel.reload:SetShown(pending)
  panel.searchBtn:SetShown(FA.Vendors ~= nil)
  panel.scout:SetShown(FA.Vendors ~= nil and FA.Vendors.setScout ~= nil)
  if FA.Vendors and FA.Vendors.scoutOn then panel.scout:SetChecked(FA.Vendors.scoutOn() and true or false) end

  -- "Coming soon" grid under the installed modules
  local shown = math.min(#modules, #panel.rows)
  local top = (shown > 0) and (-54 - shown * ROW_H - 10) or -110
  local soon = comingSoon()
  panel.soonHeader:ClearAllPoints()
  panel.soonHeader:SetPoint("TOPLEFT", 18, top)
  panel.soonHeader:SetShown(#soon > 0)
  local colW = 420 / SOON_COLS
  for i, fs in ipairs(panel.soon) do
    local name = soon[i]
    if name then
      local r, c = math.floor((i - 1) / SOON_COLS), (i - 1) % SOON_COLS
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 22 + c * colW, top - 20 - r * SOON_H)
      fs:SetText(GREY .. name .. "|r")
      fs:Show()
    else
      fs:Hide()
    end
  end
  local gridRows = math.ceil(#soon / SOON_COLS)
  panel:SetHeight(math.max(260, -top + 20 + gridRows * SOON_H + 110))
end

local function buildPanel()
  panel = FA.UI.Frame({ name = "ForeverArtisanPanel", title = "Modules", width = 460, height = 360, strata = "DIALOG",
    getPos = function() return ForeverArtisanSettings and ForeverArtisanSettings.panelPos end,
    setPos = function(pos) ForeverArtisanSettings = ForeverArtisanSettings or {}; ForeverArtisanSettings.panelPos = pos end,
    defaultPos = { "CENTER", 0, 0 } })

  FA.UI.Header(panel, -34, "Modules", 18)

  panel.rows = {}
  for i = 1, 16 do
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(420, ROW_H)
    row:SetPoint("TOPLEFT", 16, -54 - (i - 1) * ROW_H)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
      if row.m then setEnabled(row.m, self:GetChecked() and true or false); refreshPanel() end
    end)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("LEFT", 34, 0); row.title:SetJustifyH("LEFT")
    row.open = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.open:SetSize(60, 20); row.open:SetPoint("RIGHT", -2, 0); row.open:SetText("Open")
    row.open:SetScript("OnClick", function()
      local m = row.m
      if m and m.slash and SlashCmdList[m.slash] then panel:Hide(); SlashCmdList[m.slash]("") end
    end)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("RIGHT", -70, 0)
    row.notes = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.notes:SetPoint("TOPLEFT", 34, -22); row.notes:SetWidth(310); row.notes:SetJustifyH("LEFT"); row.notes:SetWordWrap(false)
    row.notes:Hide() -- shown in the hover tooltip instead
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      if not self.m then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.m.title)
      GameTooltip:AddLine(self.m.notes, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.rows[i] = row
  end

  panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  panel.empty:SetPoint("TOP", 0, -80)
  panel.empty:SetText("No modules installed yet.")

  panel.soonHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.soonHeader:SetText(GOLD .. "Coming soon|r")
  panel.soon = {}
  for i = 1, #PLANNED do
    panel.soon[i] = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  end

  -- vendor search lives in Trade Contacts; the button only shows while that module is on
  panel.searchBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.searchBtn:SetSize(130, 24)
  panel.searchBtn:SetPoint("BOTTOMLEFT", 16, 12)
  panel.searchBtn:SetText("Vendor search")
  panel.searchBtn:SetScript("OnClick", function() panel:Hide(); if FA.Vendors then FA.Vendors.open() end end)

  -- scout mode, right where people look first (also on Trade Contacts' Search tab)
  panel.scout = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  panel.scout:SetSize(24, 24)
  panel.scout:SetPoint("BOTTOMLEFT", 14, 40)
  local sl = panel.scout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sl:SetPoint("LEFT", panel.scout, "RIGHT", 2, 0)
  sl:SetText("Show NPC names in town " .. GREY .. "(finds crafting NPCs as you pass)|r")
  panel.scout:SetScript("OnClick", function(self)
    if FA.Vendors and FA.Vendors.setScout then FA.Vendors.setScout(self:GetChecked() and true or false) end
  end)
  -- the label is part of the button, so hovering or clicking the words works too
  panel.scout:SetHitRectInsets(0, -((sl:GetStringWidth() or 0) + 4), 0, 0)
  FA.UI.Tip(panel.scout, function()
    if FA.Vendors and FA.Vendors.scoutTip then FA.Vendors.scoutTip(GameTooltip) end
  end)

  panel.reload = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.reload:SetSize(130, 24)
  panel.reload:SetPoint("BOTTOMRIGHT", -16, 12)
  panel.reload:SetText("Reload UI")
  panel.reload:SetScript("OnClick", ReloadUI)


  panel:SetScript("OnShow", refreshPanel)
  panel:Hide()
end

local function togglePanel()
  if not panel then buildPanel() end
  if panel:IsShown() then panel:Hide() else panel:Show() end
end

---------------------------------------------------------------- Blizzard options entry (Esc > Options > AddOns)

local function registerOptions()
  local canvas = CreateFrame("Frame")
  canvas.name = "ForeverArtisan"
  local h = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOPLEFT", 16, -16)
  h:SetText("ForeverArtisan")
  local t = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  t:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -8)
  t:SetText("Turn modules on or off, and search vendors.")
  local b = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
  b:SetSize(160, 24)
  b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
  b:SetText("Open module panel")
  b:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then InterfaceOptionsFrame:Hide() end
    if not panel then buildPanel() end
    panel:Show()
  end)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(canvas, "ForeverArtisan")
    Settings.RegisterAddOnCategory(cat)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(canvas)
  end
end

---------------------------------------------------------------- welcome notice
-- Who ForeverArtisan is for, shown once per account (and again if WELCOME_REV goes up because the
-- message changed). /fa welcome, /fa about or /fa feedback opens it any time. Beta builds add a line.
local FEEDBACK_URL = "https://foreverartisan.app"
local WELCOME_REV = 1
local welcomeFrame

local WELCOME_TEXT =
  "Like many players, I'm treating Forever as a chance to rediscover the game. The magic of WoW "
  .. "is that first journey, and this addon is built to support that experience.\n\n"
  .. "While ForeverArtisan lists every recipe, where to get each one comes from your own play. It remembers "
  .. "where you've been, not where you're going: the trainers you meet, what you gather, the recipes "
  .. "you find. Want to look ahead? Crowdsourced sites have that covered.\n\n"
  .. "Feedback and ideas:"

local function showWelcome()
  if not welcomeFrame then
    local b = FA.UI.Frame({ name = "ForeverArtisanWelcome", title = "Welcome", width = 440, height = 340, strata = "DIALOG",
      defaultPos = { "CENTER", 0, 80 } })
    local head = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOP", 0, -34)
    head:SetText(GOLD .. "Welcome to ForeverArtisan|r")

    local body = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 22, -62); body:SetWidth(396); body:SetJustifyH("LEFT"); body:SetSpacing(2)
    body:SetText(WELCOME_TEXT)

    local link = CreateFrame("EditBox", nil, b, "InputBoxTemplate")
    link:SetSize(250, 22); link:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 6, -8)
    link:SetAutoFocus(false); link:SetText(FEEDBACK_URL)
    link:SetScript("OnTextChanged", function(self) self:SetText(FEEDBACK_URL); self:HighlightText() end)
    link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    link:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", link, "RIGHT", 8, 0); hint:SetText("click, then Ctrl+C")

    local enjoy = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enjoy:SetPoint("TOPLEFT", link, "BOTTOMLEFT", -6, -12); enjoy:SetText("Enjoy the journey!")

    local beta = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    beta:SetPoint("TOPLEFT", enjoy, "BOTTOMLEFT", 0, -8); beta:SetWidth(396); beta:SetJustifyH("LEFT")
    beta:SetText(FA.IsBeta() and "This is a test build: some things may change or not work quite right yet." or "")

    local ok = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    ok:SetSize(120, 24); ok:SetPoint("BOTTOMRIGHT", b, "BOTTOM", -6, 14); ok:SetText("Got it")
    local function seen()
      -- only a click counts as seen, so a notice that never really showed comes back next login
      ForeverArtisanSettings = ForeverArtisanSettings or {}
      ForeverArtisanSettings.welcomeSeen = WELCOME_REV
      b:Hide()
    end
    ok:SetScript("OnClick", seen)
    local mods = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    mods:SetSize(150, 24); mods:SetPoint("BOTTOMLEFT", b, "BOTTOM", 6, 14); mods:SetText("Pick my professions")
    mods:SetScript("OnClick", function() seen(); if not panel then buildPanel() end; panel:Show() end)
    local note = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOM", 0, 44); note:SetText("Bring this back any time with /fa welcome")
    welcomeFrame = b
  end
  welcomeFrame:Show()
end
FA.ShowWelcome = showWelcome

---------------------------------------------------------------- what's new (chat, once per update)
-- After an update, the first login prints the headline features of every release since the one you last
-- ran (up to three). A fresh install gets the welcome notice instead. /fa new prints it again.
-- Add one line per release, newest last; players only see releases newer than the one they had.
local NEWS = {
  { "0.9.8", "Camping: your camp items, the camp cooldown and campfire kits, with a reminder at a fire (/fa camp). "
    .. "Tauren: herb tooltips say when Cultivation is ready." },
}

local function verNum(v)
  local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)")
  if not a then return nil end
  return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end

-- the releases after `since`, up to the running version
local function newsSince(since)
  local from, to = verNum(since) or 0, verNum(FA.Version()) or math.huge
  local out = {}
  for _, n in ipairs(NEWS) do
    local v = verNum(n[1])
    if v and v > from and v <= to then out[#out + 1] = n end
  end
  while #out > 3 do table.remove(out, 1) end
  return out
end

local function showNews(list, all)
  if all then list = NEWS end
  if #list == 0 then print(PREFIX .. "nothing new to show for " .. FA.Version() .. ".") return end
  print(PREFIX .. GOLD .. "What's new" .. (all and "" or (" in " .. FA.Version())) .. ":|r")
  for i = math.max(1, #list - 2), #list do
    print("  " .. GOLD .. list[i][1] .. "|r  " .. list[i][2])
  end
  if not all then print("  " .. GREY .. "/fa new shows this again. Full changelog: " .. FA.WEBSITE .. "|r") end
end

local function checkNews()
  local s = ForeverArtisanSettings
  local cur = FA.Version()
  if not verNum(cur) then return end
  local last = s.lastVersion
  -- before 0.9.9 nothing recorded the version: someone who already saw the welcome is updating from 0.9.7 or 0.9.8
  if not last and s.welcomeSeen then last = "0.9.7" end
  s.lastVersion = cur
  if not last or last == cur then return end -- fresh install (the welcome covers it) or same version
  local list = newsSince(last)
  if #list > 0 then
    if C_Timer then C_Timer.After(6, function() showNews(list) end) else showNews(list) end
  end
end

-- warn once per login if any module is from a different release than Core
local function checkVersions()
  local bad = {}
  for _, m in ipairs(scan()) do
    if outdated(m) then bad[#bad + 1] = m.title .. " " .. m.version end
  end
  if #bad > 0 then
    print(PREFIX .. RED .. "Some parts are from a different release than Core " .. FA.Version() .. ": |r"
      .. table.concat(bad, ", ") .. ". Reinstall the whole ForeverArtisan download so they match.")
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  pcall(registerOptions)
  pcall(checkVersions)
  -- the welcome notice, once per account (again when the message changes)
  FA.Migrate("ForeverArtisanSettings", "MatsledgerSettings")
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  if ForeverArtisanSettings.welcomeSeen ~= WELCOME_REV then
    if C_Timer then C_Timer.After(4, showWelcome) else showWelcome() end
  end
  pcall(checkNews)
end)

---------------------------------------------------------------- /fa

local function help()
  print(PREFIX .. "version " .. FA.Version() .. "  -  commands")
  print("  /fa  - module panel (turn modules on/off)")
  print("  /fa version  - suite version, and a check that every part matches")
  print("  /fa welcome  - what ForeverArtisan is for, and where to send bugs and ideas")
  print("  /fa new  - what's new in recent releases")
  print("  /fa minimap [angle | reset | contacts]  - show/hide or move the minimap buttons")
  if FA.Vendors then print("  /fa <item, vendor or town>  - search your Trade Contacts") end
  print("  /fa enable <module>  |  /fa disable <module>")
  scan()
  local soon = comingSoon()
  if #soon > 0 then print("  " .. GREY .. "Coming soon: " .. table.concat(soon, ", ") .. "|r") end
  for _, m in ipairs(modules) do
    local word = m.alias ~= "" and m.alias or m.key
    print(("  /fa %s ...  - %s %s"):format(word, m.title, m.loaded and "" or (GREY .. "(off)|r")))
  end
end

SLASH_FOREVERARTISAN1 = "/fa"
SLASH_FOREVERARTISAN2 = "/artisan"
SlashCmdList.FOREVERARTISAN = function(msg)
  msg = strtrim(msg or "")
  local word, rest = msg:match("^(%S*)%s*(.-)$")
  local lower = (word or ""):lower()

  if msg == "" then
    togglePanel()
  elseif lower == "minimap" then
    if ForeverArtisan and ForeverArtisan.minimap then ForeverArtisan.minimap(rest) end
  elseif lower == "beta" or lower == "feedback" or lower == "welcome" or lower == "about" then
    showWelcome()
  elseif lower == "new" or lower == "news" or lower == "whatsnew" then
    showNews({}, true)
  elseif lower == "version" or lower == "ver" then
    print(PREFIX .. "ForeverArtisan " .. FA.Version())
    checkVersions()
  elseif lower == "help" then
    help()
  elseif lower == "modules" then
    togglePanel()
  elseif lower == "enable" or lower == "disable" then
    local m = find(rest)
    if not m then print(PREFIX .. "no module called '" .. rest .. "'. /fa help lists them.") return end
    setEnabled(m, lower == "enable")
    refreshPanel()
  elseif lower == "search" then
    if SlashCmdList.FASEARCH then SlashCmdList.FASEARCH(rest) end
  else
    local m = find(lower)
    if m then
      if not m.loaded then
        print(PREFIX .. m.title .. " is off. Tick it in the /fa panel (or /fa enable " .. (m.alias ~= "" and m.alias or m.key)
          .. "), then /reload. To search vendors and trainers instead: /fa search " .. m.title:lower() .. ".")
      elseif m.slash and SlashCmdList[m.slash] then
        SlashCmdList[m.slash](rest)
      else
        print(PREFIX .. m.title .. " has no commands.")
      end
    else
      -- anything else searches the vendors you've met (Trade Contacts)
      if SlashCmdList.FASEARCH then
        SlashCmdList.FASEARCH(msg)
      else
        print(PREFIX .. "no module called '" .. word .. "'. Turn on Trade Contacts to search vendors you've met. /fa help lists modules.")
      end
    end
  end
end

---------------------------------------------------------------- public

FA.modules, FA.open, FA.isEnabled = scan, togglePanel, isEnabled
