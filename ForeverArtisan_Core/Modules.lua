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

local SKILL_LINE_NAMES = { [171] = "alchemy", [164] = "blacksmithing", [185] = "cooking", [333] = "enchanting",
  [202] = "engineering", [129] = "first aid", [356] = "fishing", [182] = "herbalism", [165] = "leatherworking",
  [186] = "mining", [393] = "skinning", [197] = "tailoring" }

-- The professions this character knows: lowercase name -> { rank, max }. Read from the skill list,
-- so it works with every module on or off.
local function learnedTrades()
  local out = {}
  local function add(name, rank, maxr)
    if type(name) ~= "string" or (FA.IsSecret and (FA.IsSecret(name) or FA.IsSecret(rank) or FA.IsSecret(maxr))) then return end
    out[name:lower()] = { rank = tonumber(rank), max = tonumber(maxr) }
  end
  if GetNumSkillLines and GetSkillLineInfo then
    local ok, n = pcall(GetNumSkillLines)
    for i = 1, (ok and tonumber(n) or 0) do
      local ok2, name, header, _, rank, _, _, maxr = pcall(GetSkillLineInfo, i)
      if ok2 and not header then add(name, rank, maxr) end
    end
  end
  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if ok then
      -- pairs: a slot you lack (Archaeology, Fishing) is nil, and ipairs would stop there
      for _, idx in pairs({ a, b, c, d, e, f }) do
        local ok2, name, _, rank, maxr, _, _, line = pcall(GetProfessionInfo, idx)
        if ok2 then
          add(name, rank, maxr)
          -- the skill line ID names it too, in case the game's name differs from the module's
          local byLine = SKILL_LINE_NAMES[tonumber(line) or 0]
          if byLine and not (FA.IsSecret and (FA.IsSecret(rank) or FA.IsSecret(maxr))) then
            out[byLine] = out[byLine] or { rank = tonumber(rank), max = tonumber(maxr) }
          end
        end
      end
    end
  end
  return out
end

FA.LearnedTrades = learnedTrades -- for the tests

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
  -- what this character has first (professions it knows, plus Camping, which everyone has), then
  -- the other professions, then Trade Contacts; A to Z inside each group
  local isProf = {}
  for _, n in ipairs(PLANNED) do isProf[n:lower()] = true end
  local known = learnedTrades()
  for _, m in ipairs(modules) do
    m.isProf = isProf[m.title:lower()] or false
    m.learned = m.isProf and known[m.title:lower()] or nil
  end
  for _, m in ipairs(modules) do
    m.group = (m.learned or m.key == "camping") and 1 or (m.isProf and 2 or 3)
  end
  table.sort(modules, function(a, b)
    local ga, gb = a.group, b.group
    if ga ~= gb then return ga < gb end
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

-- Turning Trade Contacts off asks first: nothing you meet is saved while it's off.
-- after(): refresh whatever asked (the panel), whichever button was pressed.
local function confirmContactsOff(m, after)
  if not (StaticPopupDialogs and StaticPopup_Show) then setEnabled(m, false); if after then after() end; return end
  StaticPopupDialogs.FOREVERARTISAN_CONTACTS_OFF = {
    text = "Turn off Trade Contacts?\n\nWhile it's off, vendors and trainers you meet aren't saved. "
      .. "Shopping lists lose vendor prices and waypoints, and recipe books can't say where to train.\n\n"
      .. "Everything already saved stays, and comes back when you turn it on.",
    button1 = "Turn off", button2 = "Keep it on",
    OnAccept = function() setEnabled(m, false); if after then after() end end,
    OnCancel = function() if after then after() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
  }
  StaticPopup_Show("FOREVERARTISAN_CONTACTS_OFF")
end

---------------------------------------------------------------- panel

local NEWS -- release headlines, filled in under "what's new"; the Info tab shows the newest three
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

-- the "Works best with" line as text, for the test suite
local function addonsText()
  return panel and panel.works and panel.works.text:GetText() or ""
end

local refreshSettings -- the Settings tab (defined with it, below)
local refreshContactsSearch -- the Contacts tab's search (defined with it, below)
local refreshMarket -- the Market tab (defined with it, below)
local showTrend -- its price-trend view (defined after it)
local function refreshPanel()
  if not panel then return end
  scan()
  -- rows flow down the Modules tab under a heading for each group
  local y, prev = -6, nil
  for _, h in ipairs(panel.headings) do h:Hide() end
  for i, row in ipairs(panel.rows) do
    local m = modules[i]
    if m then
      if m.group ~= prev then
        if prev then y = y - 8 end
        local h = panel.headings[m.group]
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", 18, y); h:Show()
        y = y - 20
      end
      prev = m.group
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", 16, y)
      y = y - ROW_H
      row.m = m
      row.check:SetChecked(m.enabled)
      -- trades you know: name in white with your skill; the others gray
      local L = m.learned
      local name = (m.isProf and not L) and (GREY .. m.title .. "|r") or m.title
      local skill = (L and L.rank) and (GOLD .. "  " .. L.rank .. (L.max and ("/" .. L.max) or "") .. "|r") or ""
      row.title:SetText(name .. skill .. (m.alias ~= "" and (GREY .. "   /fa " .. m.alias .. "|r") or ""))
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

  -- Trade Contacts tab: what it knows and where it came from, and its buttons only while it runs
  for _, b in ipairs(panel.tcButtons) do b:SetShown(FA.Vendors ~= nil); b.desc:SetShown(FA.Vendors ~= nil) end
  if FA.Vendors and FA.Vendors.counts then
    local v, t, b, q = FA.Vendors.counts()
    local qs = FA.QuestieStatus and FA.QuestieStatus() or "missing"
    local lines = { ("You've met: |cffffffff%d vendors and %d trainers|r"):format(v, t) }
    if b > 0 then lines[#lines + 1] = ("From the Forever beta: |cffffffff%d more trainers|r you haven't met"):format(b) end
    lines[#lines + 1] = (qs == "missing") and (GREY .. "From Questie: not installed. With it, every profession trainer in the game is included.|r")
      or (qs == "off") and (GREY .. "From Questie: turned off|r")
      -- it reads Questie's database a few seconds after login (longer after a Questie update)
      or (qs == "reading" or qs == "installed") and (GREY .. "From Questie: reading its trainers, a moment...|r")
      or ("From Questie: |cffffffff%d more trainers|r for your faction you haven't met"):format(q)
    -- each trainer counts once: one you've met is left out of the beta and Questie numbers
    if b + q > 0 then lines[#lines + 1] = ("All together: |cffffffff%d trainers|r"):format(t + b + q) end
    panel.known:SetText(table.concat(lines, "\n"))
  else
    -- (turning it off already asks first and says what's lost; this is the reminder while it's off)
    panel.known:SetText(GOLD .. "Trade Contacts is off, so vendors and trainers you meet aren't saved. Turn it on in the Modules tab.|r")
  end
  -- names in town: a status line, and a button when the friendly nameplates they need are off
  if FA.TownStatus then
    local text, off = FA.TownStatus()
    panel.town:SetText(text)
    panel.plates:SetShown(off)
  end
  refreshSettings()
  refreshContactsSearch()
  if panel.tab == "market" then refreshMarket() end

  if panel.works then
    local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t "
    -- installed and used: check mark + name. Installed but off: name (off). Missing: gray name.
    local broken = {}
    for _, a in ipairs(FA.AddonHealth and FA.AddonHealth() or {}) do if a.state == "broken" then broken[a.name] = true end end
    local function show(name, installed, on)
      if broken[name] then return name .. RED .. " (can't read)|r" end
      if not installed then return GREY .. name .. "|r" end -- gray = not installed (the tooltip says so)
      if not on then return name .. GREY .. " (off)|r" end
      return CHECK .. name
    end
    local st = FA.QuestieStatus and FA.QuestieStatus() or "missing"
    local gs = FA.GatherStatus and FA.GatherStatus() or "missing"
    panel.works.text:SetText(GOLD .. "Works best with|r" .. GREY .. "  (hover for what each adds)|r\n"
      .. show("Auctionator", type(_G.Auctionator) == "table", true)
      .. GREY .. "  ·  |r" .. show("Questie", st ~= "missing" and st ~= "incompatible", st ~= "off")
      .. GREY .. "  ·  |r" .. show("Syndicator", FA.SyndicatorStatus and FA.SyndicatorStatus() ~= "missing", not (FA.SyndicatorStatus and FA.SyndicatorStatus() == "off"))
      .. "\n" .. show("GatherMate2", gs ~= "missing", gs ~= "off")
      .. GREY .. "  ·  |r" .. show("TomTom", type(rawget(_G, "TomTom")) == "table", true))
  end

  -- "Coming soon" grid under the installed modules
  local shown = math.min(#modules, #panel.rows)
  local top = (shown > 0) and (y - 10) or -60
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
  -- the Modules tab sets the height (the longest); the other tabs fit in it
  local gridRows = #soon > 0 and math.ceil(#soon / SOON_COLS) or 0
  local listEnd = #soon > 0 and (-top + 20 + gridRows * SOON_H) or -top
  panel:SetHeight(math.max(600, 58 + listEnd + 112)) -- room for the works-with line and Reload UI
end

-- Trade Contacts calls this when its contacts change (a new NPC, Questie's trainers read), so the open
-- panel's counts stay current
function FA.RefreshPanel()
  if panel and panel:IsShown() then pcall(refreshPanel) end
end

local TABS = { { "modules", "Modules" }, { "market", "Market" }, { "contacts", "Contacts" }, { "settings", "Settings" }, { "info", "Info" } }

local function selectTab(name)
  if not (panel and panel.pages[name]) then name = "modules" end
  panel.tab = name
  FA.UI.SelectTab(panel.pages, panel.tabs, name)
  if name == "market" and panel.market then refreshMarket() end
end

-- the game can't open links: each address sits in a box, click it and Ctrl+C
local function CopyBox(parent, text, w, title, tip)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(w, 20)
  box:SetAutoFocus(false); box:SetText(text)
  box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(text); self:HighlightText() end end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  FA.UI.Tip(box, function()
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(tip .. " Click the box, press Ctrl+C, then paste it in your browser.", 1, 1, 1, true)
  end)
  return box
end

local function Txt(parent, font, x, y, w, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", x, y)
  if w then fs:SetWidth(w) end
  fs:SetJustifyH("LEFT")
  if text then fs:SetText(text) end
  return fs
end

local function Head(parent, y, text)
  return Txt(parent, "GameFontNormal", 16, y, nil, GOLD .. text .. "|r")
end

local function buildModulesTab(p)
  panel.rows = {}
  for i = 1, 16 do
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(420, ROW_H)
    row:SetPoint("TOPLEFT", 16, -6 - (i - 1) * ROW_H)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
      if not row.m then return end
      local on = self:GetChecked() and true or false
      if not on and row.m.key == "contacts" then
        self:SetChecked(true) -- stays on until they confirm
        confirmContactsOff(row.m, refreshPanel)
        return
      end
      setEnabled(row.m, on); refreshPanel()
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
      if self.m.isProf then
        local L = self.m.learned
        GameTooltip:AddLine(L and ("You know " .. self.m.title .. (L.rank and (" (" .. L.rank .. (L.max and ("/" .. L.max) or "") .. ")") or "") .. ".")
          or "Not learned on this character. Turn it on to plan ahead, or leave it off.", 0.83, 0.66, 0.31, true)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.rows[i] = row
  end

  -- one heading per group: what this character has, the professions it doesn't, and tools
  panel.headings = {}
  for i, text in ipairs({ "Your trades", "Not learned on this character", "Tools" }) do
    local h = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetText(GOLD .. text .. "|r")
    h:Hide()
    panel.headings[i] = h
  end

  panel.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  panel.empty:SetPoint("TOP", 0, -30)
  panel.empty:SetText("No modules installed yet.")

  panel.soonHeader = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.soonHeader:SetText(GOLD .. "Coming soon|r")
  panel.soon = {}
  for i = 1, #PLANNED do
    panel.soon[i] = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  end

  -- other addons ForeverArtisan reads when you have them (named in game only)
  local works = CreateFrame("Button", nil, p)
  works:SetPoint("BOTTOMLEFT", 16, 44); works:SetSize(428, 56)
  works.text = works:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  works.text:SetPoint("LEFT"); works.text:SetJustifyH("LEFT"); works.text:SetSpacing(4)
  works:SetScript("OnClick", function()
    -- a click turns Questie's trainers on or off, when Questie is installed
    if FA.QuestieStatus and SlashCmdList.FACONTACTS then
      local st = FA.QuestieStatus()
      if st == "on" or st == "reading" then SlashCmdList.FACONTACTS("questie off")
      elseif st == "off" or st == "installed" then SlashCmdList.FACONTACTS("questie on") end
      refreshPanel()
    end
  end)
  FA.UI.Tip(works, function()
    local hasA = type(_G.Auctionator) == "table"
    local st, n = "missing", 0
    if FA.QuestieStatus then st, n = FA.QuestieStatus() end
    GameTooltip:AddLine("Works best with")
    GameTooltip:AddLine("All optional and free on CurseForge and Wago. ForeverArtisan reads what they know; it works fine without them.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Auctionator" .. (hasA and " (installed)" or " (not installed)"), 1, 0.82, 0)
    GameTooltip:AddLine(hasA and "After a full scan, every price in plans, shopping lists and Best crafts is current."
      or "One scan prices the whole Auction House. Without it, prices come from Auction House pages you browse.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Questie" .. ((st == "missing") and " (not installed)" or (st == "off") and " (installed, turned off)" or " (installed)"), 1, 0.82, 0)
    GameTooltip:AddLine((st == "on") and (n .. " profession trainers for your faction from its database, in search and Nearest trainer. Click to turn off.")
      or (st == "off") and "Click to show every profession trainer from its database again."
      or (st == "missing") and "Every profession trainer in the game in search and Nearest trainer, not just the ones you've met."
      or "Reading its database...", 1, 1, 1, true)
    if st ~= "missing" and st ~= "off" then
      GameTooltip:AddLine("Also: where recipes and materials come from, in recipe books and shopping lists.", 1, 1, 1, true)
    end
    local ss = FA.SyndicatorStatus and FA.SyndicatorStatus() or "missing"
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Syndicator" .. ((ss == "missing") and " (not installed)" or (ss == "off") and " (installed, turned off)" or " (installed)"), 1, 0.82, 0)
    GameTooltip:AddLine((ss == "missing") and "Comes with Baganator. Shopping lists show what your other characters hold, so you mail it over instead of buying."
      or (ss == "off") and "Turned off: /fa alts on."
      or "Shopping lists show what your other characters hold (bags, bank, mailbox). /fa alts off turns it off.", 1, 1, 1, true)
    local gs = FA.GatherStatus and FA.GatherStatus() or "missing"
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("GatherMate2" .. ((gs == "missing") and " (not installed)" or (gs == "off") and " (installed, turned off)"
      or (gs == "incompatible") and " (installed, can't read it)" or " (installed)"), 1, 0.82, 0)
    GameTooltip:AddLine((gs == "missing") and "With its data pack, Herbalism and Mining show where to find herbs and ores you haven't logged yet, with a waypoint to the nearest one."
      or (gs == "off") and "Turned off: /fa gather on."
      or (gs == "incompatible") and "This version of GatherMate2 doesn't share its spots the way ForeverArtisan reads them."
      or "Herbalism and Mining show where to find herbs and ores you haven't logged yet. Click a Pick next row for a waypoint. /fa gather off turns it off.", 1, 1, 1, true)
    local hasT = type(rawget(_G, "TomTom")) == "table"
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("TomTom" .. (hasT and " (installed)" or " (not installed)"), 1, 0.82, 0)
    GameTooltip:AddLine(hasT and "Every waypoint (trainers, vendors, herb and ore spots) shows as an arrow on your screen."
      or "Waypoints show as an arrow on your screen. Without it, ForeverArtisan uses the game's own map pin.", 1, 1, 1, true)
  end)
  panel.works = works

  panel.reload = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  panel.reload:SetSize(130, 24)
  panel.reload:SetPoint("BOTTOMRIGHT", -16, 12)
  panel.reload:SetText("Reload UI")
  panel.reload:SetScript("OnClick", ReloadUI)
end

local TC_ROWS = 13
-- the Contacts tab's search: empty shows the Trade Contacts buttons, typing shows results in their place
refreshContactsSearch = function()
  if not (panel and panel.tcRows) then return end
  local q = panel.tcQuery or ""
  local on = FA.Vendors ~= nil
  panel.tcSearch:SetShown(on)
  local searching = on and q ~= ""
  if panel.tcHead then panel.tcHead:SetShown(not searching) end
  for _, b in ipairs(panel.tcButtons or {}) do b:SetShown(not searching); b.desc:SetShown(not searching) end
  local data = searching and FA.Vendors.rows(q) or {}
  panel.tcData = data
  panel.tcOff = math.min(panel.tcOff or 0, math.max(0, #data - TC_ROWS))
  for i, r in ipairs(panel.tcRows) do
    local d = data[i + panel.tcOff]
    r.d = d
    if d then
      r.icon:SetTexture(d.icon or 134400); r.left:SetText(d.left or ""); r.right:SetText(d.right or ""); r:Show()
    else r:Hide() end
  end
  if not searching then panel.tcStatus:SetText("")
  elseif #data == 0 then panel.tcStatus:SetText(GREY .. 'Nothing matches "' .. q .. '" among the NPCs you\'ve met or passed.|r')
  else
    local more = #data - panel.tcOff - TC_ROWS
    panel.tcStatus:SetText(("%d result%s. Click one for a waypoint.%s"):format(#data, #data == 1 and "" or "s",
      more > 0 and (GREY .. "  Scroll for " .. more .. " more.|r") or ""))
  end
end

local function buildContactsTab(p)
  -- what's in it, by where it came from, so the buttons below are clear about what they search
  Head(p, -8, "What Trade Contacts knows")
  panel.known = Txt(p, "GameFontHighlightSmall", 16, -30, 428)
  panel.known:SetSpacing(3)

  -- search right here: type and the results replace the buttons below (no second window)
  panel.tcSearch = FA.UI.SearchBox(p, 428, function(text)
    panel.tcQuery, panel.tcOff = text, 0
    refreshContactsSearch()
  end, "Search items, vendors, towns or a profession")
  panel.tcSearch:SetPoint("TOPLEFT", 22, -100)
  panel.tcStatus = Txt(p, "GameFontHighlightSmall", 16, -128, 428)
  panel.tcRows = {}
  for i = 1, TC_ROWS do
    local r = CreateFrame("Button", nil, p)
    r:SetSize(428, 22); r:SetPoint("TOPLEFT", 16, -148 - (i - 1) * 24)
    r:SetHighlightTexture(FA.UI.HIGHLIGHT, "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 2, 0)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.left:SetPoint("LEFT", 26, 0); r.left:SetWidth(190); r.left:SetJustifyH("LEFT"); r.left:SetWordWrap(false)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -4, 0); r.right:SetWidth(206); r.right:SetJustifyH("RIGHT"); r.right:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
      if self.d and self.d.npc and FA.Vendors then FA.Vendors.waypoint(self.d.npc) end
    end)
    r:SetScript("OnEnter", function(self)
      local d = self.d
      if not d then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if d.id then GameTooltip:SetItemByID(d.id) else GameTooltip:AddLine(d.tipTitle or "") end
      local tip = d.tip or (d.tipFn and d.tipFn())
      if tip then GameTooltip:AddLine(tip, 1, 1, 1, true) end
      if d.npc then GameTooltip:AddLine("Click for a waypoint", 0.5, 0.75, 1) end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    panel.tcRows[i] = r
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    if (panel.tcQuery or "") == "" then return end
    panel.tcOff = math.max(0, math.min((panel.tcOff or 0) - delta * 3, math.max(0, #(panel.tcData or {}) - TC_ROWS)))
    refreshContactsSearch()
  end)

  panel.tcHead = Head(p, -140, "Open Trade Contacts")
  -- each button opens the Trade Contacts window on that tab; Nearest trainer opens with its menu up
  local TC = {
    { "Search", function() FA.Vendors.open() end, "Find any of them by item, NPC, town or profession." },
    { "Contacts", function() FA.Vendors.openTab("contacts") end, "Your contact book: the vendors and trainers you've met, by zone and trade." },
    { "Limited stock", function() FA.Vendors.openTab("stock") end, "Limited-stock items at vendors you've met, and when they come back." },
    { "Nearest trainer", function() FA.Vendors.openNearest() end, "The closest trainer for your class or a profession, from everything above." },
  }
  panel.tcButtons = {}
  for i, t in ipairs(TC) do
    local y = -162 - (i - 1) * 34
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(130, 24); b:SetPoint("TOPLEFT", 16, y); b:SetText(t[1])
    b:SetScript("OnClick", function() if FA.Vendors then panel:Hide(); t[2]() end end)
    b.desc = Txt(p, "GameFontHighlightSmall", 156, y - 1, 288, t[3])
    panel.tcButtons[i] = b
  end
  refreshContactsSearch()

end

-- Settings: every switch that used to be a slash command only. Each row: a box, a name, one gray line.
-- get() true/false (nil = can't be used here: grayed, with need shown); set(on) does what the command does.
local function CSettings() return ForeverArtisanContactsDB and ForeverArtisanContactsDB.settings end
local SETTINGS = {
  { head = "General" },
  { key = "minimap", label = "Minimap button", desc = "Left-click opens this panel, right-click Trade Contacts.",
    get = function() return not (ForeverArtisanSettings and ForeverArtisanSettings.minimapHide) end,
    set = function(on)
      if (not (ForeverArtisanSettings and ForeverArtisanSettings.minimapHide)) ~= on and FA.minimap then FA.minimap("") end
    end },
  { key = "prices", label = "Auction House prices on item tooltips", desc = "What an item sells for, from Auction House pages you've seen.",
    get = function() return FA.PriceTipsOn and FA.PriceTipsOn() end,
    set = function(on) if on then ForeverArtisanSettings.priceTips = nil else ForeverArtisanSettings.priceTips = false end end,
    note = function() return (type(_G.Auctionator) == "table" and _G.Auctionator.API) and "Auctionator shows its own, so ForeverArtisan stays quiet." or nil end },
  { head = "Trade Contacts" },
  { key = "questie", label = "Trainers from Questie", desc = "Every profession trainer for your faction, in search and Nearest trainer.",
    get = function()
      if not (FA.Vendors and FA.QuestieStatus) then return nil end
      local st = FA.QuestieStatus()
      if st == "missing" or st == "incompatible" then return nil end
      return st ~= "off"
    end,
    need = function() return FA.Vendors and "Needs Questie." or "Needs Trade Contacts on." end,
    set = function(on) if SlashCmdList.FACONTACTS then SlashCmdList.FACONTACTS(on and "questie on" or "questie off") end end },
  { key = "seeds", label = "Trainers from the Forever beta", desc = "Trainers we met on the beta, until you meet them yourself.",
    get = function() local st = CSettings(); if not (FA.Vendors and st) then return nil end; return not st.seedsOff end,
    need = function() return "Needs Trade Contacts on." end,
    set = function(on) if SlashCmdList.FACONTACTS then SlashCmdList.FACONTACTS(on and "seeds on" or "seeds off") end end },
  { head = "From your other addons" },
  { key = "alts", label = "What your alts hold, on shopping lists", desc = "Bags, bank and mailbox of your other characters.",
    get = function()
      local st = FA.SyndicatorStatus and FA.SyndicatorStatus() or "missing"
      if st == "missing" then return nil end
      return st ~= "off"
    end,
    need = function() return "Needs Syndicator (Baganator installs it)." end,
    set = function(on) ForeverArtisanSettings.altsOff = (not on) or nil end },
  { key = "gather", label = "Herb and ore spots", desc = "Herbalism and Mining show where to find what you haven't logged.",
    get = function()
      local st = FA.GatherStatus and FA.GatherStatus() or "missing"
      if st == "missing" or st == "incompatible" then return nil end
      return st ~= "off"
    end,
    need = function() return "Needs GatherMate2 and its data pack." end,
    set = function(on) ForeverArtisanSettings.gatherOff = (not on) or nil; if FA.GatherReset then FA.GatherReset() end end },
  { head = "Names in town" },
  { key = "titles", label = "Job titles under NPC names", desc = "\"Cooking Trainer\", \"Trade Supplies\" and so on, in towns.",
    get = function() return FA.TownNamesOn and FA.TownNamesOn() end,
    set = function(on) if FA.SetTownNames then FA.SetTownNames(on, true) end end,
    note = function()
      local other = FA.OtherPlatesAddon and FA.OtherPlatesAddon()
      return (other and (ForeverArtisanSettings or {}).titlesPick == nil) and ("Off on its own while " .. other .. " shows NPC names.") or nil
    end },
}

function refreshSettings()
  for _, r in ipairs(panel.settingRows) do
    local d = r.def
    local on = d.get()
    local usable = on ~= nil
    r.check:SetChecked(on and true or false)
    r.check:SetEnabled(usable)
    r.label:SetText((usable and "" or GREY) .. d.label .. (usable and "" or "|r"))
    local extra = (not usable and d.need and d.need()) or (d.note and d.note()) or nil
    r.desc:SetText(GREY .. d.desc .. (extra and (" " .. extra) or "") .. "|r")
  end
end

local function buildSettingsTab(p)
  panel.settingRows = {}
  local y = -8
  for _, d in ipairs(SETTINGS) do
    if d.head then
      if y < -8 then y = y - 6 end
      Head(p, y, d.head)
      y = y - 22
    else
      local r = { def = d }
      r.check = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
      r.check:SetSize(24, 24); r.check:SetPoint("TOPLEFT", 14, y + 4)
      r.label = Txt(p, "GameFontHighlight", 42, y, 400)
      r.desc = Txt(p, "GameFontHighlightSmall", 42, y - 15, 400) -- wraps to a second line (notes, "Needs ...")
      r.check:SetScript("OnClick", function(self)
        ForeverArtisanSettings = ForeverArtisanSettings or {}
        d.set(self:GetChecked() and true or false)
        refreshPanel()
      end)
      panel.settingRows[#panel.settingRows + 1] = r
      panel.settingRows[d.key] = r
      y = y - 48
    end
  end
  -- the game's friendly nameplates carry the titles: a status line, and a button when they're off
  local townHover = CreateFrame("Frame", nil, p)
  townHover:SetPoint("TOPLEFT", 42, y + 2); townHover:SetSize(400, 30)
  panel.town = Txt(townHover, "GameFontHighlightSmall", 0, 0, 400)
  FA.UI.Tip(townHover, function() if FA.TownNamesTip then FA.TownNamesTip(GameTooltip) end end)
  panel.plates = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  panel.plates:SetSize(150, 24)
  panel.plates:SetPoint("TOPLEFT", 42, y - 30)
  panel.plates:SetText("Turn on nameplates")
  panel.plates:SetScript("OnClick", function()
    if FA.TurnOnFriendlyPlates then FA.TurnOnFriendlyPlates() end
    refreshPanel()
  end)
  FA.UI.Tip(panel.plates, function() if FA.TownNamesTip then FA.TownNamesTip(GameTooltip) end end)
end

-- Market: every profession's Best crafts in one list, by profit after the Auction House cut.
-- Flagged BETA until two weeks after launch: beta and launch-week prices swing too much to trust fully.
local MARKET_ROWS = 15
local MARKET_TOP = -106 -- first row, under the "click a craft" line
-- this week's direction, on rows and in the trend view
local ARROW = { up = "|TInterface\\Buttons\\Arrow-Up-Up:12|t", down = "|TInterface\\Buttons\\Arrow-Down-Up:12|t" }
local MARKET_DOT = {
  good = "|TInterface\\COMMON\\Indicator-Green:14|t",
  ok = "|TInterface\\COMMON\\Indicator-Yellow:14|t",
  shaky = "|TInterface\\COMMON\\Indicator-Gray:14|t",
}
local MARKET_CONF = { good = "steady price", ok = "price looks fair, check it", shaky = "shaky price: old, few listed or swinging" }

-- "beta" before launch, "early" for two weeks after, nil after that
function FA.MarketStage()
  local now, at = (time and time()) or 0, FA.LAUNCH_AT or 0
  if now < at then return "beta" end
  if now < at + 14 * 86400 then return "early" end
end

local function marketData()
  local rows, read = {}, 0
  if FA.MarketRows then rows, read = FA.MarketRows() end
  local hide = ForeverArtisanSettings and ForeverArtisanSettings.marketHideShaky
  local data = {}
  for _, row in ipairs(rows) do
    local c = row.conf or {}
    if not (hide and c.level == "shaky") then data[#data + 1] = row end
  end
  return data, read
end

function refreshMarket()
  local p = panel.market
  if p.showing then showTrend(p.showing) return end
  local stage = FA.MarketStage()
  p.badge:SetText(stage and ("|cffff9020BETA|r") or "")
  p.note:SetText(stage == "beta" and ("|cffff9020These are beta Auction House prices.|r " .. GREY .. "They swing a lot, so treat the ranking as a rough guide until launch.|r")
    or stage == "early" and ("|cffff9020Early days:|r " .. GREY .. "launch prices swing a lot. Check the Auction House before you craft in bulk.|r")
    or (GREY .. "Recipes you know, in every profession, ranked by profit per craft after the Auction House cut.|r"))
  p.source:SetText(FA.PriceSourceLines and table.concat(FA.PriceSourceLines(), "\n") or "")
  local data, read = marketData()
  p.data = data
  p.off = math.max(0, math.min(p.off or 0, #data - MARKET_ROWS))
  for i, r in ipairs(p.rows) do
    local row = data[i + p.off]
    r.row = row
    if row then
      local rec = row.r
      r.icon:SetTexture(FA.UI.Icon(rec.itemId))
      r.left:SetText((row.prof.color and row.prof.color(rec) or "") .. rec.name .. ((rec.makes or 1) > 1 and (" x" .. rec.makes) or "") .. "|r"
        .. GREY .. "  " .. row.prof.name .. "|r")
      local tag = FA.HouseTag and FA.HouseCompare and FA.HouseTag(FA.HouseCompare(rec.itemId, rec.makes))
      local tr = FA.PriceTrend(rec.itemId)
      r.right:SetText(((tr.dir == "up" or tr.dir == "down") and (ARROW[tr.dir] .. " ") or "")
        .. (row.profit >= 0 and (GREEN .. "+" .. FA.Money(row.profit)) or (RED .. FA.Money(row.profit))) .. "|r"
        .. (tag and (GOLD .. "  " .. tag .. "|r") or ""))
      r.dot:SetText(MARKET_DOT[(row.conf or {}).level or "shaky"])
      r:Show()
    else
      r:Hide()
    end
  end
  p.clickHint:SetShown(#data > 0)
  p.empty:SetText(#data > 0 and ""
    or (read == 0 and "Learn a crafting profession and open its window once, so ForeverArtisan can read your recipes.")
    or "No prices yet for what you craft. Visit the Auction House, or scan with Auctionator.")
  p.hide:SetChecked(ForeverArtisanSettings and ForeverArtisanSettings.marketHideShaky and true or false)
end

---------------------------------------------------------------- Market: one craft's price trend
-- Click a Market row: a 14-day chart of what it sells for (each day's lowest price at your Auction
-- House), whether it's trending up or down, and the same for each material.
local CHART_W, CHART_H, CHART_DAYS = 380, 130, 14

-- "up 12% this week" (green/red as good for the seller), or why there's no trend yet.
-- withTurn adds the last move when it went the other way: "down 16% this week, up 29% since yesterday",
-- so the words match the chart's last segment.
local function moveWords(dir, frac, sellerView, tail)
  local pct = math.floor(math.abs(frac) * 100 + 0.5)
  -- for something you sell, up is good; for a material you buy, down is good
  local good = (dir == "up") == (sellerView and true or false)
  return (good and GREEN or RED) .. dir .. " " .. pct .. "% " .. tail .. "|r"
end
local function trendWords(t, sellerView, withTurn)
  if not t or not t.now then return GREY .. "no prices seen yet|r" end
  if not t.dir then return GREY .. "one day seen so far: check back after another scan|r" end
  local week = (t.dir == "flat") and (GREY .. "steady this week|r") or moveWords(t.dir, t.change, sellerView, "this week")
  local flat = FA.TREND_FLAT or 0.05
  local turn = t.step and ((t.step > flat and "up") or (t.step < -flat and "down")) or nil
  if withTurn and turn and turn ~= t.dir then
    local today = FA.Day and FA.Day() or 0
    local since = (t.prevDay == (t.last or today) - 1) and "since yesterday"
      or ("since " .. date("%b ", t.prevDay * 86400) .. tonumber(date("%d", t.prevDay * 86400)))
    week = week .. GREY .. ", |r" .. moveWords(turn, t.step, sellerView, since)
  end
  return week
end
FA.TrendWords = trendWords

-- line (default) or bar chart, remembered; bars only when the client can't draw lines
local function chartMode()
  local m = ForeverArtisanSettings and ForeverArtisanSettings.marketChart
  if not (panel.market.detail and panel.market.detail.canLine) then return "bar" end
  return m == "bar" and "bar" or "line"
end

local function trendArrow(t)
  return t and t.dir and ARROW[t.dir] or ""
end

function showTrend(row, chartId)
  local p = panel.market
  local d = p.detail
  if p.showing ~= row then d.chartId = nil end
  p.showing = row
  if chartId ~= nil then d.chartId = (chartId ~= row.r.itemId) and chartId or nil end
  for _, w in ipairs(p.listParts) do w:Hide() end
  d:Show()
  local rec = row.r
  d.title:SetText((row.prof.color and row.prof.color(rec) or "") .. rec.name .. "|r" .. GREY .. "  " .. row.prof.name .. "|r")
  -- the chart shows the craft, or the material you clicked; the line above it says which
  local mat
  for _, g in ipairs(rec.reagents or {}) do if d.chartId and g.id == d.chartId then mat = g end end
  if not mat then d.chartId = nil end
  local t = FA.PriceTrend(mat and mat.id or rec.itemId)
  d.trend = t
  if mat then
    local now = t.now or (FA.AHPrice and FA.AHPrice(mat.id))
    d.sells:SetText(GOLD .. "Chart: " .. (mat.name or "material") .. "|r  costs " .. (now and FA.Money(now) or "?") .. " each  ·  "
      .. trendWords(t, false, true) .. (t.listed and (GREY .. "  ·  " .. t.listed .. " listed|r") or ""))
  else
    d.sells:SetText(GOLD .. "Chart: " .. rec.name .. "|r  sells for " .. (t.now and FA.Money(t.now) or (row.sale and FA.Money(row.sale)) or "?")
      .. " each  ·  " .. trendWords(t, true, true) .. (t.listed and (GREY .. "  ·  " .. t.listed .. " listed|r") or ""))
  end
  local byDay, hi, lo = {}, 0, nil
  for _, e in ipairs(t.days) do
    byDay[e.day] = e
    if e.p > hi then hi = e.p end
    if not lo or e.p < lo then lo = e.p end
  end
  local today = FA.Day and FA.Day() or 0
  local bw = math.floor(CHART_W / CHART_DAYS)
  local mode = chartMode()
  d.lineBtn:SetEnabled(d.canLine and mode ~= "line"); d.barBtn:SetEnabled(d.canLine and mode ~= "bar")
  d.lineBtn:SetShown(d.canLine); d.barBtn:SetShown(d.canLine)
  -- bars start at 0 (sizes compare); the line spans low to high (the shape shows the trend)
  local bot, top = 0, hi
  if mode == "line" and lo then
    local pad = math.max(1, math.floor((hi - lo) * 0.15 + 0.5))
    if hi == lo then pad = math.max(1, math.floor(hi * 0.1 + 0.5)) end
    bot, top = math.max(0, lo - pad), hi + pad
  end
  local function y(pr) return (top > bot) and ((pr - bot) / (top - bot) * (CHART_H - 4) + 2) or (CHART_H / 2) end
  local prevX, prevY, nLine = nil, nil, 0
  for i = 1, CHART_DAYS do
    local bar, dot = d.bars[i], d.dots[i]
    local e = byDay[today - (CHART_DAYS - i)]
    local latest = e and (i == CHART_DAYS or (t.last and e.day == t.last))
    bar:Hide(); dot:Hide()
    if e and hi > 0 then
      if mode == "bar" then
        bar:SetHeight(math.max(2, math.floor(CHART_H * e.p / hi + 0.5)))
        -- the latest day stands out; the rest in brand gold
        if latest then bar:SetColorTexture(1, 0.82, 0, 0.95) else bar:SetColorTexture(0.83, 0.66, 0.31, 0.7) end
        bar:Show()
      else
        local x, yy = (i - 1) * bw + bw / 2, y(e.p)
        dot:ClearAllPoints(); dot:SetPoint("CENTER", d.chart, "BOTTOMLEFT", x, yy)
        dot:SetSize(latest and 8 or 6, latest and 8 or 6)
        if latest then dot:SetColorTexture(1, 0.82, 0, 1) else dot:SetColorTexture(0.83, 0.66, 0.31, 1) end
        dot:Show()
        -- a line from the last day with a price, across any days without one
        if prevX then
          nLine = nLine + 1
          local ln = d.lines[nLine]
          ln:SetStartPoint("BOTTOMLEFT", d.chart, prevX, prevY)
          ln:SetEndPoint("BOTTOMLEFT", d.chart, x, yy)
          ln:Show()
        end
        prevX, prevY = x, yy
      end
    end
    d.hits[i].e = e
  end
  for k = nLine + 1, #d.lines do d.lines[k]:Hide() end
  -- the week before's average: what "up/down this week" is measured against
  if t.base and hi > 0 then
    local by = (mode == "bar") and (CHART_H * t.base / hi) or y(t.base)
    d.avg:ClearAllPoints(); d.avg:SetPoint("BOTTOMLEFT", d.chart, "BOTTOMLEFT", 0, by); d.avg:SetPoint("RIGHT", d.chart, "RIGHT", 0, 0)
    d.avg:Show()
    d.avgText:ClearAllPoints(); d.avgText:SetPoint("BOTTOMLEFT", d.chart, "BOTTOMLEFT", 4, by + 2)
    d.avgText:SetText("week before: " .. FA.Money(math.floor(t.base + 0.5)))
    d.avgText:Show()
  else
    d.avg:Hide(); d.avgText:Hide()
  end
  d.hiText:SetText(hi > 0 and FA.Money(top) or "")
  d.loText:SetText(hi > 0 and (bot > 0 and FA.Money(bot) or "0") or "")
  d.empty:SetText(#t.days == 0 and "No prices seen for this yet. Scan the Auction House (or browse it) and the chart fills in, one point a day." or "")
  -- materials: what each costs now and which way it's going; click one to chart it
  local n = 0
  for _, g in ipairs(rec.reagents or {}) do
    n = n + 1
    local b = d.matBtns[n]
    if not b then break end
    local mt = FA.PriceTrend(g.id)
    local now = mt.now or (FA.AHPrice and FA.AHPrice(g.id))
    local on = (d.chartId == g.id)
    b.id = g.id
    b.text:SetText((on and (GOLD .. "> |r") or "") .. ("%s%dx %s|r  %s  %s %s"):format("|cffffffff", g.n or 1, g.name or ("item " .. tostring(g.id)),
      now and FA.Money(now) or (GREY .. "no price|r"), trendArrow(mt), trendWords(mt, false)))
    b:Show()
  end
  for k = n + 1, #d.matBtns do d.matBtns[k]:Hide() end
  n = math.min(n, #d.matBtns)
  d.mats:SetText(n == 0 and (GREY .. "No materials listed.|r") or "")
  d.profit:ClearAllPoints()
  d.profit:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -64 - CHART_H - 50 - math.max(1, n) * 18 - 10)
  d.profit:SetText("Profit per craft now: " .. (row.profit >= 0 and (GREEN .. "+" .. FA.Money(row.profit)) or (RED .. FA.Money(row.profit))) .. "|r"
    .. GREY .. "  (after the Auction House cut)|r")
  d.ah:SetEnabled(FA.AuctionHouseOpen and FA.AuctionHouseOpen() and true or false)
end

local function hideTrend()
  local p = panel.market
  p.showing = nil
  p.detail:Hide()
  for _, w in ipairs(p.listParts) do w:Show() end
  refreshMarket()
end

local function buildTrend(p)
  local d = CreateFrame("Frame", nil, p)
  d:SetPoint("TOPLEFT", 0, -80); d:SetPoint("BOTTOMRIGHT", 0, 0)
  d:Hide()
  p.detail = d
  d.back = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  d.back:SetSize(80, 22); d.back:SetPoint("TOPLEFT", 16, -4); d.back:SetText("< Back")
  d.back:SetScript("OnClick", hideTrend)
  d.title = Txt(d, "GameFontNormal", 104, -8, 230)
  d.title:SetWordWrap(false)
  d.sells = Txt(d, "GameFontHighlightSmall", 16, -36, 428)
  -- chart: a frame with a faint background and baseline, the highest price at top left
  local c = CreateFrame("Frame", nil, d)
  c:SetSize(CHART_W, CHART_H); c:SetPoint("TOPLEFT", 48, -64)
  local bg = c:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
  local base = c:CreateTexture(nil, "BORDER"); base:SetHeight(1); base:SetPoint("BOTTOMLEFT"); base:SetPoint("BOTTOMRIGHT")
  base:SetColorTexture(0.6, 0.6, 0.6, 0.8)
  d.hiText = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  d.hiText:SetPoint("TOPRIGHT", c, "TOPLEFT", -4, 0)
  local lo = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  lo:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", -4, 0)
  d.loText = lo
  local left = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  left:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -3); left:SetText("2 weeks ago")
  local right = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  right:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT", 0, -3); right:SetText("today")
  d.chart = c
  -- a faint line at the week before's average, labeled, so "up/down this week" has something to point at
  d.avg = c:CreateTexture(nil, "BORDER"); d.avg:SetHeight(1); d.avg:SetColorTexture(0.75, 0.75, 0.75, 0.45); d.avg:Hide()
  d.avgText = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); d.avgText:Hide()
  -- Line or Bars, top right; the choice is remembered
  d.canLine = type(c.CreateLine) == "function"
  local function setMode(m)
    ForeverArtisanSettings = ForeverArtisanSettings or {}
    ForeverArtisanSettings.marketChart = m
    if p.showing then showTrend(p.showing) end
  end
  d.barBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  d.barBtn:SetSize(56, 22); d.barBtn:SetPoint("TOPRIGHT", -16, -4); d.barBtn:SetText("Bars")
  d.barBtn:SetScript("OnClick", function() setMode("bar") end)
  d.lineBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  d.lineBtn:SetSize(56, 22); d.lineBtn:SetPoint("RIGHT", d.barBtn, "LEFT", -4, 0); d.lineBtn:SetText("Line")
  d.lineBtn:SetScript("OnClick", function() setMode("line") end)
  d.lines, d.dots = {}, {}
  for i = 1, CHART_DAYS do
    local dot = c:CreateTexture(nil, "OVERLAY")
    dot:Hide()
    d.dots[i] = dot
    if d.canLine and i < CHART_DAYS then
      local ln = c:CreateLine(nil, "ARTWORK")
      ln:SetThickness(2); ln:SetColorTexture(0.83, 0.66, 0.31, 0.9)
      ln:Hide()
      d.lines[i] = ln
    end
  end
  d.bars, d.hits = {}, {}
  local bw = math.floor(CHART_W / CHART_DAYS)
  for i = 1, CHART_DAYS do
    local bar = c:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(bw - 4); bar:SetPoint("BOTTOMLEFT", (i - 1) * bw + 2, 1)
    bar:Hide()
    d.bars[i] = bar
    -- a hover area per day (the whole column), so short bars are easy to point at
    local hit = CreateFrame("Frame", nil, c)
    hit:SetSize(bw, CHART_H); hit:SetPoint("BOTTOMLEFT", (i - 1) * bw, 0)
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", function(self)
      local e = self.e
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local ago = CHART_DAYS - i
      GameTooltip:AddLine(ago == 0 and "Today" or ago == 1 and "Yesterday" or (ago .. " days ago"))
      if e then
        GameTooltip:AddLine("Lowest price: " .. FA.Money(e.p), 1, 1, 1)
        if e.q then GameTooltip:AddLine(e.q .. " listed", 1, 1, 1) end
      else
        GameTooltip:AddLine("No prices seen that day.", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.hits[i] = hit
  end
  d.empty = Txt(c, "GameFontDisable", 20, -40, CHART_W - 40)
  d.empty:SetJustifyH("CENTER")

  Txt(d, "GameFontNormal", 16, -64 - CHART_H - 30, nil, GOLD .. "Materials|r" .. GREY .. "  (click one to chart it, click again for the craft)|r")
  d.mats = Txt(d, "GameFontHighlightSmall", 16, -64 - CHART_H - 50, 428)
  d.matBtns = {}
  for i = 1, 6 do
    local b = CreateFrame("Button", nil, d)
    b:SetSize(428, 16); b:SetPoint("TOPLEFT", 14, -64 - CHART_H - 48 - (i - 1) * 18)
    b:SetHighlightTexture(FA.UI.HIGHLIGHT, "ADD")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 2, 0); b.text:SetJustifyH("LEFT"); b.text:SetWidth(424); b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
      local row = p.showing
      if row then showTrend(row, (d.chartId == self.id) and row.r.itemId or self.id) end
    end)
    b:Hide()
    d.matBtns[i] = b
  end
  -- below the materials, however many there are
  d.profit = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d.profit:SetPoint("TOPLEFT", d.mats, "BOTTOMLEFT", 0, -12); d.profit:SetWidth(428); d.profit:SetJustifyH("LEFT")

  d.open = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  d.open:SetSize(130, 24); d.open:SetPoint("TOPLEFT", d.profit, "BOTTOMLEFT", 0, -12); d.open:SetText("Open recipe")
  d.open:SetScript("OnClick", function() local row = p.showing; if row and row.prof.open then row.prof.open(row.r) end end)
  d.ah = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  d.ah:SetSize(170, 24); d.ah:SetPoint("LEFT", d.open, "RIGHT", 8, 0); d.ah:SetText("Search Auction House")
  d.ah:SetScript("OnClick", function() local row = p.showing; if row and FA.SearchAH then FA.SearchAH(row.r.name) end end)
  if d.ah.SetMotionScriptsWhileDisabled then d.ah:SetMotionScriptsWhileDisabled(true) end
  FA.UI.Tip(d.ah, function()
    GameTooltip:AddLine("Search Auction House")
    GameTooltip:AddLine("Puts the name in the Auction House search box (you press Search). Open the Auction House first.", 1, 1, 1, true)
  end)
  local note = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", d.open, "BOTTOMLEFT", 0, -12); note:SetWidth(428); note:SetJustifyH("LEFT")
  note:SetText("Each day is that day's lowest price at your faction's Auction House, from your scans and visits. Hover a day for its price and how many were listed.")
end
FA.MarketTrend = function(row) if panel and panel.market then showTrend(row) end end -- for the test suite

local function buildMarketTab(p)
  panel.market = p
  p.head = Head(p, -8, "Market")
  p.badge = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.badge:SetPoint("LEFT", p.head, "RIGHT", 8, 0)
  p.note = Txt(p, "GameFontHighlightSmall", 16, -28, 428)
  p.source = Txt(p, "GameFontDisableSmall", 16, -58, 428)
  p.rows = {}
  for i = 1, MARKET_ROWS do
    local r = CreateFrame("Button", nil, p)
    r:SetSize(428, 22); r:SetPoint("TOPLEFT", 16, MARKET_TOP - (i - 1) * 24)
    r:SetHighlightTexture(FA.UI.HIGHLIGHT, "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 2, 0)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.left:SetPoint("LEFT", 26, 0); r.left:SetWidth(250); r.left:SetJustifyH("LEFT"); r.left:SetWordWrap(false)
    -- a "next page" arrow at the end of every row says there's more behind it
    r.chart = r:CreateTexture(nil, "OVERLAY"); r.chart:SetSize(22, 22); r.chart:SetPoint("RIGHT", 2, 0)
    r.chart:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    r.dot = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.dot:SetPoint("RIGHT", -24, 0)
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -44, 0); r.right:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
      if self.row then showTrend(self.row) end
    end)
    r:SetScript("OnEnter", function(self)
      local row = self.row
      if not row then return end
      local c = row.conf or {}
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(row.r.name)
      GameTooltip:AddLine(row.prof.name, 1, 1, 1)
      GameTooltip:AddDoubleLine("Materials", FA.Money(row.cost or 0), 1, 1, 1, 1, 1, 1)
      if row.sale then GameTooltip:AddDoubleLine("Sells for (Auction House)", FA.Money(row.sale * (row.r.makes or 1)), 1, 1, 1, 1, 1, 1) end
      if row.vend then GameTooltip:AddDoubleLine("Vendor pays", FA.Money(row.vend * (row.r.makes or 1)), 1, 1, 1, 1, 1, 1) end
      GameTooltip:AddDoubleLine("Profit after the cut", FA.Money(row.profit), 1, 1, 1, 1, 1, 1)
      GameTooltip:AddLine(" ")
      local col = c.level == "good" and GREEN or c.level == "ok" and "|cffffff00" or GREY
      GameTooltip:AddLine(col .. (MARKET_CONF[c.level or "shaky"]) .. "|r")
      GameTooltip:AddLine("Click for its price chart.", 0.5, 0.75, 1, true)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    p.rows[i] = r
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    p.off = math.max(0, math.min((p.off or 0) - delta * 3, #(p.data or {}) - MARKET_ROWS))
    refreshMarket()
  end)
  p.empty = Txt(p, "GameFontDisable", 16, -140, 428)
  p.empty:SetJustifyH("CENTER")
  p.hide = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  p.hide:SetSize(24, 24); p.hide:SetPoint("TOPLEFT", 14, MARKET_TOP - MARKET_ROWS * 24 - 6)
  -- the words sit on the box's middle, and clicking them ticks it too (same as every other checkbox)
  local hl = p.hide:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  hl:SetPoint("LEFT", p.hide, "RIGHT", 2, 0); hl:SetText("Hide shaky prices")
  p.hide:SetHitRectInsets(0, -((hl:GetStringWidth() or 110) + 4), 0, 0)
  p.hide:SetScript("OnClick", function(self)
    ForeverArtisanSettings = ForeverArtisanSettings or {}
    ForeverArtisanSettings.marketHideShaky = self:GetChecked() and true or nil
    p.off = 0
    refreshMarket()
  end)
  -- say it big, right above the list: rows open a price chart
  p.clickHint = Txt(p, "GameFontNormal", 16, -82, 428,
    "Click any craft to see its price chart and whether it's trending up or down.")
  local help = Txt(p, "GameFontDisableSmall", 16, MARKET_TOP - MARKET_ROWS * 24 - 40, 428,
    "Arrows: the price is up or down this week. Dots: green steady price, yellow check it, gray shaky. "
    .. GOLD .. "Gold:|r a goblin Auction House pays that much more.")
  p.listParts = { p.hide, help, p.empty, p.clickHint }
  for _, r in ipairs(p.rows) do p.listParts[#p.listParts + 1] = r end
  buildTrend(p)
end

local function buildInfoTab(p)
  Head(p, -8, "About")
  local about = {
    { "Version", FA.Version() },
    { "Built for", "WoW Forever" .. (GetBuildInfo and (" " .. (select(1, GetBuildInfo()) or "")) or "") },
    { "License", "Free to download and use. All rights reserved." },
  }
  for i, l in ipairs(about) do
    local y = -30 - (i - 1) * 18
    Txt(p, "GameFontDisable", 16, y, 90, l[1])
    Txt(p, "GameFontHighlight", 110, y, 330, l[2])
  end

  Head(p, -100, "Contact")
  -- until launch day the Discord gets a call-out
  panel.discordNews = Txt(p, "GameFontHighlight", 16, -122, 428,
    FA.Prelaunch() and (GREEN .. "The Discord is now live.|r Send your ideas before the November 4 launch.") or "")
  local y0 = FA.Prelaunch() and -146 or -122
  Txt(p, "GameFontHighlightSmall", 16, y0, 428, "Questions, bug reports and ideas: the ForeverArtisan Discord")
  panel.discord = CopyBox(p, FA.DISCORD, 300, "ForeverArtisan Discord", "Questions, bug reports and ideas, and release news.")
  panel.discord:SetPoint("TOPLEFT", 22, y0 - 16)
  Txt(p, "GameFontHighlightSmall", 16, y0 - 46, 428, "Guides, the changelog and the bug form: the site")
  panel.site = CopyBox(p, FA.WEBSITE, 300, "foreverartisan.app", "Guides, the changelog, ideas and the bug form.")
  panel.site:SetPoint("TOPLEFT", 22, y0 - 62)
  Txt(p, "GameFontDisableSmall", 16, y0 - 90, 428, "The game can't open links: click a box, press Ctrl+C, then paste it in your browser.")

  -- the newest releases, from the same lines as the What's new note in chat
  Head(p, y0 - 120, "What's new")
  panel.news = Txt(p, "GameFontHighlightSmall", 16, y0 - 142, 428)
  panel.news:SetSpacing(3)
  local cur = FA.Version()
  local lines = {}
  for i = #NEWS, 1, -1 do
    local n = NEWS[i]
    local a, b = tostring(n[1]), tostring(cur)
    -- only releases up to the one running (a dev build may carry the next one's line already)
    local function num(v) local x, y, z = v:match("^(%d+)%.(%d+)%.(%d+)"); return x and (x * 1000000 + y * 1000 + z) end
    if not num(b) or not num(a) or num(a) <= num(b) then
      lines[#lines + 1] = GOLD .. n[1] .. "|r  " .. n[2]
      if #lines == 3 then break end
    end
  end
  panel.news:SetText(table.concat(lines, "\n\n") .. "\n\n" .. GREY .. "/fa help lists every command. Full changelog on the site.|r")

  local enjoy = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  enjoy:SetPoint("BOTTOMLEFT", 16, 16); enjoy:SetText("Enjoy the journey!")
end

local function buildPanel()
  panel = FA.UI.Frame({ name = "ForeverArtisanPanel", width = 460, height = 600, strata = "DIALOG",
    getPos = function() return ForeverArtisanSettings and ForeverArtisanSettings.panelPos end,
    setPos = function(pos) ForeverArtisanSettings = ForeverArtisanSettings or {}; ForeverArtisanSettings.panelPos = pos end,
    defaultPos = { "CENTER", 0, 0 } })
  panel.pages, panel.tabs = {}, {}
  FA.UI.Tabs(panel, TABS, panel.pages, panel.tabs, selectTab)
  buildModulesTab(panel.pages.modules)
  buildMarketTab(panel.pages.market)
  buildContactsTab(panel.pages.contacts)
  buildSettingsTab(panel.pages.settings)
  buildInfoTab(panel.pages.info)
  panel.AddonsText = addonsText
  selectTab("modules")
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

---------------------------------------------------------------- first run
-- A fresh install opens the module panel once, so new players pick their professions and see the
-- site and Discord boxes. (0.9.21 retired the separate welcome notice; the panel says it all.)
-- until launch day (Nov 4, 2026, 00:00 UTC) the panel calls out the Discord
local LAUNCH_AT = 1793750400
FA.LAUNCH_AT = LAUNCH_AT
function FA.Prelaunch()
  return ((time and time()) or 0) < LAUNCH_AT
end

local function showPanel(tab)
  if not panel then buildPanel() end
  if type(tab) == "string" then selectTab(tab) end
  panel:Show()
end
FA.ShowPanel = showPanel

---------------------------------------------------------------- what's new (chat, once per update)
-- After an update, the first login prints the headline features of every release since the one you last
-- ran (up to three). A fresh install opens the module panel instead. /fa new prints it again.
-- Add one line per release, newest last; players only see releases newer than the one they had.
NEWS = {
  { "0.9.8", "Camping: your camp items, the camp cooldown and campfire kits, with a reminder at a fire (/fa camp). "
    .. "Tauren: herb tooltips say when Cultivation is ready." },
  { "0.9.9", "New gold FA and map pin minimap buttons, this What's new note after updates (/fa new), "
    .. "and a fix for a Lua error near crowded nameplates." },
  { "0.9.10", "Job titles under NPC names in town, no switch needed (they need friendly NPC nameplates on: /fa nameplates). "
    .. "Plays nice with Plater and other nameplate addons. Fewer Lua errors in combat. Bugs: " .. FA.BUG_URL },
  { "0.9.11", "Fixed Mining, Herbalism and Skinning not counting nodes with auto loot. Every node and skin counts again." },
  { "0.9.12", "Prices in your crafting plans: each shopping list shows what missing materials cost and a total. "
    .. "No other addon needed (it remembers Auction House prices you see); uses Auctionator too if you have it." },
  { "0.9.13", "Plans include recipes you can still train, with a \"Train now\" line and the cost. They pick the cheaper "
    .. "recipe when two are close. Drag the window's corner to make it taller; long lists scroll." },
  { "0.9.14", "Auction House prices on item tooltips (Auctionator users keep theirs). Click a Train line or a material "
    .. "on a shopping list for a waypoint to the trainer or vendor. \"Dropped by\" now works with auto loot." },
  { "0.9.15", "Recipe tooltips show what a craft is worth: materials, sale price and profit after the Auction House cut. "
    .. "Profession gear: the Fishing tab shows your pole's bonus and line, and gathering tabs point out better gear in your bags." },
  { "0.9.16", "Best crafts: a new tab ranks your recipes by profit or cheapest leveling, and says when a goblin Auction House "
    .. "pays more (works best with Auctionator). Fishing keys take controller buttons, and new key bindings open the panel, "
    .. "Fishing and Trade Contacts. Characters with the same first name no longer share data." },
  { "0.9.17", "Controller fishing without the Gamepad UI: when a cast lands out of reach, the same button casts again. "
    .. "With the Gamepad UI on, put the white dot on a far bobber. Tested on PlayStation 5 and Xbox-style controllers." },
  { "0.9.18", "Shopping lists and plans show a material's name instead of \"item:2450\" when the game sends it late." },
  { "0.9.19", "Works with your favorite addons: Questie (every profession trainer, where recipes and materials come from), "
    .. "Syndicator (what your alts hold) and GatherMate2 (herb and ore spots). Trainers from the Forever beta come built in." },
  { "0.9.20", "Fishing catches count again with auto loot. Nearest trainer lists trainers from before game updates and "
    .. "trainers with no title under their name, like Cook Torka." },
  { "0.9.21", "The ForeverArtisan Discord is now live: " .. FA.DISCORD .. ". Send your ideas before the November 4 launch. "
    .. "The /fa panel has tabs now: Modules, Market (beta: your most profitable crafts in every profession), Contacts, Settings and Info (the Discord link is there). "
    .. "Right-click the FA minimap button for Trade Contacts; its own map-pin button is gone." },
  { "0.9.22", "Market price charts are clearer: the line above the chart says what it shows, a faint line marks the week before's "
    .. "average, and you can click a material to chart it. When the last day moved the other way, the words say so." },
  { "0.9.23", "Search boxes: type a recipe or material in any Recipe book, or an item, vendor or town on the /fa panel's Contacts tab. "
    .. "With auto loot, herbs, ore, leather and recipe drops now count every time." },
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
  print("  " .. GREY .. FA.BUG_LINE .. "|r")
end

local function checkNews()
  local s = ForeverArtisanSettings
  local cur = FA.Version()
  if not verNum(cur) then return end
  local last = s.lastVersion
  -- before 0.9.9 nothing recorded the version: someone who already saw the welcome is updating from 0.9.7 or 0.9.8
  if not last and s.welcomeSeen then last = "0.9.7" end
  s.lastVersion = cur
  if not last or last == cur then return end -- fresh install (the panel opens instead) or same version
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
-- learn or drop a trade with the panel open: move it to the right group right away
pcall(ev.RegisterEvent, ev, "SKILL_LINES_CHANGED")
ev:SetScript("OnEvent", function(_, event)
  if event == "SKILL_LINES_CHANGED" then
    if panel and panel:IsShown() then pcall(refreshPanel) end
    return
  end
  pcall(registerOptions)
  pcall(checkVersions)
  FA.Migrate("ForeverArtisanSettings", "MatsledgerSettings")
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  -- a fresh install (nothing recorded yet) opens the module panel once
  if not s.lastVersion and not s.welcomeSeen then
    s.welcomeSeen = true
    if C_Timer then C_Timer.After(4, function() showPanel("modules") end) else showPanel("modules") end
  end
  pcall(checkNews)
end)

---------------------------------------------------------------- /fa

local function help()
  print(PREFIX .. "version " .. FA.Version() .. "  -  commands")
  print("  /fa  - module panel (turn modules on/off)")
  print("  /fa version  - suite version, and a check that every part matches")
  print("  /fa bug  - where to report an error (" .. FA.BUG_URL .. ")")
  print("  /fa discord  - the ForeverArtisan Discord (" .. FA.DISCORD .. ")")
  print("  /fa market  - your most profitable crafts, every profession in one list")
  print("  /fa new  - what's new in recent releases")
  print("  /fa nameplates  - turn on friendly NPC nameplates (job titles in town need them)")
  print("  /fa titles on | off | auto  - job titles under NPC names (auto leaves them to Plater and other nameplate addons)")
  print("  /fa prices on | off  - Auction House prices on item tooltips (off while Auctionator shows its own)")
  print("  /fa alts on | off  - what your other characters hold, on shopping lists (needs Syndicator)")
  print("  /fa gather on | off  - herb and ore spots in Herbalism and Mining (needs GatherMate2)")
  local hasA = type(_G.Auctionator) == "table"
  local hasQ = type(rawget(_G, "LibQuestieDB")) == "table"
  local hasS = type(rawget(_G, "Syndicator")) == "table"
  local hasG = FA.GatherStatus and FA.GatherStatus() ~= "missing"
  print("  Works best with: Auctionator (" .. (hasA and "installed" or "not installed") .. ") for current prices, Questie ("
    .. (hasQ and "installed" or "not installed") .. ") for trainers and recipe sources, Syndicator ("
    .. (hasS and "installed" or "not installed") .. ") for what your alts hold, GatherMate2 ("
    .. (hasG and "installed" or "not installed") .. ") for herb and ore spots, TomTom ("
    .. (type(rawget(_G, "TomTom")) == "table" and "installed" or "not installed") .. ") for waypoint arrows. All optional.")
  print("  /fa minimap [angle | reset]  - show/hide or move the minimap button (right-click it for Trade Contacts)")
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
  elseif lower == "feedback" or lower == "bug" or lower == "bugs" then
    print(PREFIX .. FA.BUG_LINE .. "  " .. GREY .. "(ideas: " .. FA.WEBSITE .. ", Discord: " .. FA.DISCORD .. ")|r")
    showPanel("info")
  elseif lower == "discord" then
    print(PREFIX .. "Discord: " .. FA.DISCORD .. "  " .. GREY .. "(copy it from the box on the Info tab)|r")
    showPanel("info")
  elseif lower == "market" then
    showPanel("market")
  elseif lower == "beta" or lower == "welcome" or lower == "about" then
    showPanel("info")
  elseif lower == "new" or lower == "news" or lower == "whatsnew" then
    showNews({}, true)
  elseif lower == "version" or lower == "ver" then
    print(PREFIX .. "ForeverArtisan " .. FA.Version())
    checkVersions()
    -- the other addons it reads, when installed
    for _, a in ipairs(FA.AddonHealth and FA.AddonHealth() or {}) do
      if a.state ~= "missing" then
        print(("  %s %s: %s"):format(a.name, a.version,
          (a.state == "ok" and (GREEN .. "read OK|r")) or (a.state == "off" and (GREY .. "turned off|r"))
          or (RED .. "can't read this version, " .. a.what .. " are off. Please report it at " .. FA.BUG_URL .. "|r")))
      end
    end
    if (FA.secretSkips or 0) > 0 then
      print(GREY .. ("  Hidden game values skipped this session: %d (harmless)"):format(FA.secretSkips) .. "|r")
    end
  elseif lower == "nameplates" or lower == "plates" then
    if FA.TurnOnFriendlyPlates then FA.TurnOnFriendlyPlates() end
    if panel and panel:IsShown() then refreshPanel() end
  elseif lower == "titles" or lower == "names" then
    local r = (rest or ""):lower()
    if r == "on" or r == "off" then
      FA.SetTownNames(r == "on")
    elseif r == "auto" then
      FA.SetTownNames(nil)
    else
      local other = FA.OtherPlatesAddon()
      local auto = (ForeverArtisanSettings or {}).titlesPick == nil
      print(PREFIX .. "Job titles under NPC names: " .. (FA.TownNamesOn() and "on" or "off")
        .. (auto and (other and (" (automatic: " .. other .. " shows NPC names)") or " (automatic)") or "")
        .. ". /fa titles on | off | auto")
      if not FA.FriendlyPlatesOn() then print(PREFIX .. FA.PLATES_OFF_LINE) end
    end
    if panel and panel:IsShown() then refreshPanel() end
  elseif lower == "prices" or lower == "price" then
    local r = (rest or ""):lower()
    ForeverArtisanSettings = ForeverArtisanSettings or {}
    if r == "on" then ForeverArtisanSettings.priceTips = nil
    elseif r == "off" then ForeverArtisanSettings.priceTips = false end
    print(PREFIX .. "Auction House prices on item tooltips: " .. (FA.PriceTipsOn and FA.PriceTipsOn() and "on" or "off")
      .. ((type(_G.Auctionator) == "table" and _G.Auctionator.API) and " (Auctionator shows its own, so ForeverArtisan stays quiet)" or "")
      .. ". /fa prices on | off")
  elseif lower == "alts" then
    local r = (rest or ""):lower()
    ForeverArtisanSettings = ForeverArtisanSettings or {}
    if r == "on" then ForeverArtisanSettings.altsOff = nil
    elseif r == "off" then ForeverArtisanSettings.altsOff = true end
    local st = FA.SyndicatorStatus and FA.SyndicatorStatus() or "missing"
    print(PREFIX .. "What your other characters hold, on shopping lists: "
      .. (st == "missing" and "needs Syndicator (Baganator installs it)" or st)
      .. ". /fa alts on | off")
    if panel and panel:IsShown() then refreshPanel() end
  elseif lower == "gather" then
    local r = (rest or ""):lower()
    ForeverArtisanSettings = ForeverArtisanSettings or {}
    if r == "on" then ForeverArtisanSettings.gatherOff = nil
    elseif r == "off" then ForeverArtisanSettings.gatherOff = true end
    if FA.GatherReset then FA.GatherReset() end
    local st = FA.GatherStatus and FA.GatherStatus() or "missing"
    print(PREFIX .. "Herb and ore spots in Herbalism and Mining: "
      .. (st == "missing" and "needs GatherMate2 and its data pack" or st == "incompatible" and "can't read this GatherMate2" or st)
      .. ". /fa gather on | off")
    if panel and panel:IsShown() then refreshPanel() end
  elseif lower == "ahtest" then
    if FA.AHTestReport then FA.AHTestReport((rest or ""):lower()) end
  elseif lower == "help" then
    help()
  elseif lower == "modules" then
    togglePanel()
  elseif lower == "enable" or lower == "disable" then
    local m = find(rest)
    if not m then print(PREFIX .. "no module called '" .. rest .. "'. /fa help lists them.") return end
    if lower == "disable" and m.key == "contacts" then confirmContactsOff(m, refreshPanel) return end
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
function ForeverArtisanTogglePanel() togglePanel() end   -- for the key binding
BINDING_NAME_FOREVERARTISAN_PANEL = "ForeverArtisan: open the panel (/fa)"

-- hidden values: skip events that carry them, and drop their errors quietly (Core UI.lua)
ForeverArtisan.GuardEvents(ev)
