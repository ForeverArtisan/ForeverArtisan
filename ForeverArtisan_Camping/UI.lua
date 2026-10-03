-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Camping: window (/fa camp) with Camp / Campfire kits tabs
local _, ns = ...
if not ns or not ns.DB then return end

local FA = ForeverArtisan
local GOLD, GRAY, GREEN, YELLOW, RED = FA.GOLD, FA.GRAY, FA.GREEN, FA.YELLOW, FA.RED

local f
local pages, tabs = {}, {}
local view = { tab = "main" }

local K = FA.UI.Kit(ns, view)
local Text, Check, Header = K.Text, K.Check, K.Header
local MakeRows, Fill = K.MakeRows, K.Fill
local function S() return ns.DB().settings end

---------------------------------------------------------------- page 1: Camp
local function BuildMainPage(p)
  p.cd = Text(p, "GameFontNormalLarge", "TOPLEFT", 18, -6); p.cd:SetWidth(430)
  p.fire = Text(p, "GameFontHighlightSmall", "TOPLEFT", 18, -32); p.fire:SetWidth(430)

  Header(p, -58, "Your camp items")
  p.rows = MakeRows(p, 11, -78, true)
  p.empty = Text(p, "GameFontDisable", "TOPLEFT", 20, -82); p.empty:SetWidth(420)

  p.checks = {
    Check(p, "Remind me at a campfire when mine is ready", 16, -364,
      function() return S().reminder end, function(v) S().reminder = v end),
    Check(p, "Chat line when camp items are ready again", 16, -390,
      function() return S().readyMsg end, function(v) S().readyMsg = v end),
  }
  local help = Text(p, "GameFontDisableSmall", "BOTTOMLEFT", 20, 18, p, "BOTTOMLEFT"); help:SetWidth(430)
  help:SetText("One camp item per player per fire. Placing one puts all of yours on a one-hour cooldown.")
end

local function RefreshMainPage(p)
  p.cd:SetText(ns.Status())
  p.fire:SetText(ns.AtFire() and (GREEN .. "You're at a campfire.|r") or (GRAY .. "Not at a campfire.|r"))
  local data = {}
  for _, r in ipairs(ns.Rows()) do
    local left
    if r.now then
      left = (r.have and GREEN or "") .. r.prof .. ": " .. r.now .. (r.have and "|r" or "")
    else
      left = GRAY .. r.prof .. ": none yet|r"
    end
    local right = r.next and ((r.skillOK and YELLOW or GRAY) .. "next: " .. ns.NextText(r) .. "|r") or (GOLD .. "top tier|r")
    local tip = ("%s %d."):format(r.prof, r.skill) .. ((r.now and ns.BUFF[r.now]) and ("\nGives: " .. ns.BUFF[r.now] .. " to everyone sitting at the fire.") or "")
    if r.have then
      tip = tip .. ("\nIn your bags: %s%s."):format(r.have, (r.haveN or 1) > 1 and (" x" .. r.haveN) or "")
    elseif r.now then
      tip = tip .. ("\nNot in your bags. Craft it in your %s window, under Camping."):format(r.prof)
    else
      tip = tip .. ("\nYour first camp item comes at skill %d."):format(ns.TIERS[1])
    end
    if r.next and r.blueprint then tip = tip .. "\nTiers 2 and 3 need a Blueprint as well as the skill." end
    local craft, label, off, actTip, actTipTitle
    if r.now then
      craft = function() ns.OpenCraft(r.prof, r.line, r.now) end
      if r.mats then
        tip = tip .. "\n\nTo make one:\n" .. table.concat(r.mats, "\n")
        if (r.can or 0) > 0 then
          label = r.can > 1 and ("Craft " .. math.min(r.can, 99)) or "Craft"
          tip = tip .. ("\n\nCraft: opens your %s window on it. You can make %d."):format(r.prof, r.can)
        else
          label, off = "Craft", true
          tip = tip .. "\n\nMissing materials (red above)."
          actTipTitle = "Can't craft " .. r.now .. " yet"
          actTip = "You're missing materials:\n" .. table.concat(r.mats, "\n")
        end
      else
        label = "Craft"
        tip = tip .. "\nCraft: opens your " .. r.prof .. " window on it."
      end
    end
    data[#data + 1] = { icon = r.icon, left = left, right = right, tipTitle = r.now or r.prof, tip = tip,
      act = label, onAct = craft, actOff = off, actTip = actTip, actTipTitle = actTipTitle }
  end
  Fill(p.rows, data, 0)
  p.empty:SetText(#data == 0 and "Learn a profession to get a camp item. Every profession but Cooking has one." or "")
  for _, c in ipairs(p.checks) do c:Sync() end
end

---------------------------------------------------------------- page 2: Campfire kits
local function BuildKitsPage(p)
  p.head = Text(p, "GameFontHighlight", "TOPLEFT", 18, -6); p.head:SetWidth(430)
  p.rows = MakeRows(p, 3, -32, false)
  local note = Text(p, "GameFontHighlightSmall", "TOPLEFT", 20, -118); note:SetWidth(430)
  note:SetText("Cooking makes the fire. Each kit needs more Cooking to use than to learn, so you can train one before you can light it.")
end

local function RefreshKitsPage(p)
  local rows, cook = ns.KitRows()
  local kl = ns.KitLeft()
  local fire = (kl == nil) and "" or ("  " .. GRAY .. "·|r  " .. ((kl <= 0) and (GREEN .. "Campfire: ready|r") or (YELLOW .. "Next campfire in " .. ns.Mins(kl) .. "|r")))
  p.head:SetText((cook and ("Cooking %d"):format(cook) or (GRAY .. "You haven't learned Cooking on this character.|r")) .. fire)
  local data = {}
  for _, r in ipairs(rows) do
    local k, color, word = r.kit, GRAY, "need Cooking " .. r.kit.learn
    if r.state == "use" then color, word = GREEN, "you can use it"
    elseif r.state == "learn" then color, word = YELLOW, ("learn now, use at %d"):format(k.use) end
    data[#data + 1] = { icon = "Interface\\Icons\\Spell_Fire_Fire", left = color .. k.name .. "|r",
      right = ("%d items  ·  %s"):format(k.slots, word),
      tipTitle = k.name,
      tip = ("Learn at Cooking %d, use at %d. Holds %d camp items.%s%s"):format(k.learn, k.use, k.slots,
        r.have > 0 and ("\nIn your bags: %d."):format(r.have) or "",
        (function() local _, m = ns.CanMake(k.name); return m and ("\n\nTo make one:\n" .. table.concat(m, "\n")) or "" end)()) }
  end
  Fill(p.rows, data, 0)
end

---------------------------------------------------------------- frame
local REFRESH = { main = RefreshMainPage, kits = RefreshKitsPage }

local function ShowTab(name)
  view.tab = name
  for k, pg in pairs(pages) do pg:SetShown(k == name) end
  for k, b in pairs(tabs) do b:SetEnabled(k ~= name) end
  if REFRESH[name] then REFRESH[name](pages[name]) end
end

local function Build()
  local order = { { "main", "Camp" }, { "kits", "Campfire kits" } }
  f = K.Window({ name = "ForeverArtisanCampingFrame", title = "Camping", tabs = order, pages = pages, tabButtons = tabs, onTab = ShowTab })
  BuildMainPage(pages.main)
  BuildKitsPage(pages.kits)
  f:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + el
    if self.t > 1 then
      self.t = 0
      if view.tab == "main" then
        local p = pages.main
        p.cd:SetText(ns.Status())
        p.fire:SetText(ns.AtFire() and (GREEN .. "You're at a campfire.|r") or (GRAY .. "Not at a campfire.|r"))
      end
    end
  end)
  f:Hide()
  ShowTab("main")
end

function ns.ToggleWindow()
  if not f then Build() end
  if f:IsShown() then f:Hide() else f:Show(); ShowTab(view.tab) end
end

function ns.OnChange()
  if f and f:IsShown() and REFRESH[view.tab] then REFRESH[view.tab](pages[view.tab]) end
end
