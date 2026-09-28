-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Trade Contacts - finder. Turns your saved contacts into answers:
-- "Sold by" lines on item tooltips, search, and waypoints. Only NPCs you've met.
local ADDON, ns = ...
local FA = ForeverArtisan
local GOLD, GREY = FA.GOLD, FA.GRAY
local PREFIX = FA.Prefix("Trade Contacts")
local MAX_TIP_LINES = 3

local npcs, byId, byName = {}, {}, {}
local dirty = true

local function DB() return ForeverArtisanContactsDB end
local function Settings() return (DB() and DB().settings) or {} end

---------------------------------------------------------------- saved contacts -> lookup tables

-- "Requires Tailoring (125)" -> "Tailoring (125)"
local function skillReq(requires)
  for _, r in ipairs(requires or {}) do
    local rest = r:match("^Requires (.+)$")
    if rest and not rest:find("^Level") and rest:find("%(%d+%)") then return rest end
  end
end

-- How many game updates since this contact was last seen: 0 = current, 1 = before the last
-- update (shown, marked), 2+ = not seen through two updates (hidden from tooltips and search).
local function UpdatesSince(e)
  local builds = DB() and DB().builds
  if not builds or #builds == 0 or not e.build then return 0 end
  for i = #builds, 1, -1 do
    if builds[i] == e.build then return #builds - i end
  end
  return #builds -- older than anything we remember
end
ns.HIDE_AFTER = 2

local function Rebuild()
  wipe(npcs); wipe(byId); wipe(byName)
  local entries = DB() and DB().entries or {}
  for key, e in pairs(entries) do
    if (e.kind == "vendor" or e.kind == "trainer") and e.name then
      local npc = { n = e.name, t = e.title, k = e.kind, z = e.zone, s = e.subzone, m = e.mapID, x = e.x, y = e.y,
                    seen = e.seenAt or e.lastSeen, visited = e.lastSeen, age = UpdatesSince(e), key = key, items = {} }
      if e.kind == "vendor" then
        for _, it in ipairs(e.items or {}) do
          if it.name then
            npc.items[#npc.items + 1] = { n = it.name, id = it.itemId, p = it.priceCopper, lv = it.levelReq,
              sk = skillReq(it.requires), lim = it.limited, stack = it.stack }
          end
        end
      else
        for _, sk in ipairs(e.skills or {}) do
          if sk.name then
            npc.items[#npc.items + 1] = { n = sk.name .. (sk.rank and (" (" .. sk.rank .. ")") or ""), p = sk.priceCopper,
              sk = sk.skillReq, lv = sk.levelReq, train = true }
          end
        end
      end
      npcs[#npcs + 1] = npc
      -- contacts not seen through two game updates stay in the list but stop answering questions
      if npc.age < ns.HIDE_AFTER then
      for _, it in ipairs(npc.items) do
        local hit = { npc = npc, item = it }
        if it.id then byId[it.id] = byId[it.id] or {}; table.insert(byId[it.id], hit) end
        local key = it.n:lower()
        byName[key] = byName[key] or {}; table.insert(byName[key], hit)
      end
      end
    end
  end
  table.sort(npcs, function(a, b) return (a.n or "") < (b.n or "") end)
  dirty = false
end

local function Ensure() if dirty then Rebuild() end end

function ns.OnContactsChanged()
  dirty = true
  if ns.OnChange then ns.OnChange() end
end

function ns.Contacts() Ensure(); return npcs end

---------------------------------------------------------------- helpers

local function money(it)
  if it.p and it.p > 0 then
    if GetCoinTextureString then return GetCoinTextureString(it.p) end
    local g, s, c = math.floor(it.p / 10000), math.floor(it.p / 100) % 100, it.p % 100
    return (g > 0 and g .. "g " or "") .. (s > 0 and s .. "s " or "") .. (c > 0 and c .. "c" or "")
  end
  if it.p == 0 then return "free" end
  return "?"
end
ns.Money = money

local function where(npc) return npc.s or npc.z or "?" end
ns.Where = where

local function playerPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return end
  local m = C_Map.GetBestMapForUnit("player")
  if not m then return end
  local pos = C_Map.GetPlayerMapPosition(m, "player")
  if not pos then return m end
  local x, y = pos:GetXY()
  return m, x * 100, y * 100
end

-- same map first (nearest first), then by town and name
local function sortHits(hits)
  local m, px, py = playerPos()
  for _, h in ipairs(hits) do
    if m and px and h.npc.m == m and h.npc.x then
      local dx, dy = h.npc.x - px, h.npc.y - py
      h.dist = math.sqrt(dx * dx + dy * dy)
    else
      h.dist = 1e9
    end
  end
  table.sort(hits, function(a, b)
    if (a.npc.age or 0) ~= (b.npc.age or 0) then return (a.npc.age or 0) < (b.npc.age or 0) end
    if a.dist ~= b.dist then return a.dist < b.dist end
    if where(a.npc) ~= where(b.npc) then return where(a.npc) < where(b.npc) end
    local an, bn = a.item and a.item.n or "", b.item and b.item.n or ""
    if an ~= bn then return an < bn end
    return a.npc.n < b.npc.n
  end)
  return hits
end

function ns.SetWaypoint(npc)
  if not (npc.m and npc.x and npc.y) then
    print(PREFIX .. "no coordinates saved for " .. npc.n .. ".")
    return
  end
  local title = npc.n .. " (" .. where(npc) .. ")"
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(npc.m, npc.x / 100, npc.y / 100, { title = title, persistent = false, crazy = true })
    print(PREFIX .. "waypoint set: " .. title)
    return
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(npc.m, npc.x / 100, npc.y / 100))
    if ok then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
      print(PREFIX .. "map pin set: " .. title)
      return
    end
  end
  print(PREFIX .. string.format("%s is at %.1f, %.1f in %s.", title, npc.x, npc.y, npc.z or "?"))
end

-- one short freshness note, or nil when the contact is current
function ns.AgeNote(npc)
  local when = npc.seen and (" " .. date("%b %d", npc.seen)) or ""
  if npc.age >= ns.HIDE_AFTER then
    return "Not seen through " .. npc.age .. " game updates" .. (when ~= "" and (" (last seen" .. when .. ")") or "")
      .. ". Hidden from tooltips and search until you see them again."
  elseif npc.age == 1 then
    return "Last seen" .. when .. " before the last game update. May have moved or changed."
  end
end

-- tooltip text for one contact (+ item)
function ns.DetailText(npc, it)
  local lines = {}
  lines[#lines + 1] = string.format("%s, %s  (%.1f, %.1f)", where(npc), npc.z or "", npc.x or 0, npc.y or 0)
  if it then
    lines[#lines + 1] = it.n .. "  " .. money(it)
    if it.sk then lines[#lines + 1] = "Requires " .. it.sk end
    if it.lv then lines[#lines + 1] = "Requires level " .. it.lv end
    if it.lim then lines[#lines + 1] = "|cffff8040Limited stock|r (" .. it.lim .. " when you last looked)" end
  end
  local note = ns.AgeNote(npc)
  if note then
    lines[#lines + 1] = "|cffff9020" .. note .. "|r"
  else
    if npc.seen then lines[#lines + 1] = GREY .. "Last seen " .. date("%b %d", npc.seen) .. "|r" end
    if npc.visited and npc.visited ~= npc.seen then lines[#lines + 1] = GREY .. "Stock checked " .. date("%b %d", npc.visited) .. "|r" end
  end
  lines[#lines + 1] = "|cff80c0ffClick for a waypoint|r"
  return table.concat(lines, "\n")
end

---------------------------------------------------------------- lookups

local function hitsForLink(link, name)
  Ensure()
  -- match by item ID and by name, without duplicates
  local id = link and tonumber(link:match("item:(%d+)"))
  name = name or (link and link:match("%[(.-)%]"))
  local out, seen = {}, {}
  for _, list in ipairs({ id and byId[id] or {}, name and byName[name:lower()] or {} }) do
    for _, h in ipairs(list) do
      if not seen[h] then seen[h] = true; out[#out + 1] = h end
    end
  end
  return out
end

-- search item names, vendor names/titles/towns, and required professions ("tailoring")
local function search(q)
  Ensure()
  q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local hits = {}
  if q == "" then return hits end
  for _, npc in ipairs(npcs) do
    if npc.age >= ns.HIDE_AFTER then -- hidden: not seen through two updates
    else
    local npcMatch = npc.n:lower():find(q, 1, true) or (npc.t and npc.t:lower():find(q, 1, true))
      or (npc.s and npc.s:lower():find(q, 1, true)) or (npc.z and npc.z:lower():find(q, 1, true))
    if npcMatch then table.insert(hits, { npc = npc }) end
    for _, it in ipairs(npc.items) do
      if it.n:lower():find(q, 1, true) or (it.sk and it.sk:lower():find(q, 1, true)) then
        table.insert(hits, { npc = npc, item = it })
      end
    end
    end
  end
  return sortHits(hits)
end

---------------------------------------------------------------- tooltips

local function addToTooltip(tt)
  if not tt or tt.faContactsDone or Settings().tooltips == false then return end
  local name, link = tt:GetItem()
  local hits = hitsForLink(link, name)
  local list = {}
  for i, h in ipairs(hits or {}) do if not h.item.train then list[#list + 1] = h end end
  if #list == 0 then
    -- nobody you've met sells it: for known vendor-only reagents, say what kind of vendor does
    local FA = ForeverArtisan
    local hint = FA and FA.VendorHint and FA.VendorHint(name or link)
    if not hint then return end
    tt.faContactsDone = true
    tt:AddLine(GOLD .. "Sold by|r")
    tt:AddLine(GREY .. "  " .. hint .. " - none in your Trade Contacts yet|r")
    tt:Show()
    return
  end
  tt.faContactsDone = true
  sortHits(list)
  tt:AddLine(GOLD .. "Sold by|r")
  for i = 1, math.min(#list, MAX_TIP_LINES) do
    local h = list[i]
    local old = h.npc.age > 0
    local left = "  " .. (old and GREY or "") .. h.npc.n .. (old and "|r" or "") .. GREY .. " - " .. where(h.npc) .. "|r"
    if h.item.lim then left = left .. " |cffff8040(limited)|r" end
    if old then left = left .. GREY .. " (before update)|r" end
    local c = old and 0.6 or 1
    tt:AddDoubleLine(left, money(h.item), c, c, c, c, c, c)
  end
  if #list > MAX_TIP_LINES then
    tt:AddLine(GREY .. "  +" .. (#list - MAX_TIP_LINES) .. " more: /fa " .. (name or "") .. "|r")
  end
  tt:Show()
end

local function clearFlag(tt) tt.faContactsDone = nil end

local function HookTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
      if tt == GameTooltip or tt == ItemRefTooltip then pcall(addToTooltip, tt) end
    end)
  else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
      tt:HookScript("OnTooltipSetItem", function(self) pcall(addToTooltip, self) end)
    end
  end
  GameTooltip:HookScript("OnTooltipCleared", clearFlag)
  ItemRefTooltip:HookScript("OnTooltipCleared", clearFlag)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() HookTooltips() end)

---------------------------------------------------------------- search entry points

ns.Search = search
ns.HitsForLink = hitsForLink

-- other modules (Cooking, First Aid, the /fa hub) use this; it only exists while Trade Contacts is on
FA.Vendors = {
  search = search,
  hitsForLink = hitsForLink,
  open = function(q) if ns.OpenSearch then ns.OpenSearch(q) end end,
}

SLASH_FASEARCH1 = "/fasearch"
SlashCmdList.FASEARCH = function(msg)
  if ns.OpenSearch then ns.OpenSearch(strtrim(msg or "")) end
end
