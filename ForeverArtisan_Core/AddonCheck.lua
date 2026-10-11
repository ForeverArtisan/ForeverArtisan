-- Is every other addon ForeverArtisan reads still readable? An update to one of them can change
-- what we read; the feature then goes quiet instead of erroring. This says so, once per version
-- of that addon, so players (and we) find out instead of wondering where a feature went.
--   FA.AddonHealth()   { { name, state = "ok"|"off"|"missing"|"broken", what }, ... }
local FA = ForeverArtisan
local PREFIX = "|cffd4a94eForeverArtisan:|r "

local function Version(addon)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or function() end, addon, "Version")
  return ok and v or "?"
end

local CHECKS = {
  { name = "Questie", folder = "QuestieDB", what = "every profession trainer and recipe sources",
    state = function()
      if type(rawget(_G, "LibQuestieDB")) ~= "table" then return "missing" end
      if FA.QDB and FA.QDB.Off() then return "off" end
      if not (FA.QDB and FA.QDB.Lib()) then return "broken" end
      local L = FA.QDB.Lib()
      if not (L.Npc and type(L.Npc.GetAllIds) == "function" and L.Item and type(L.Item.vendors) == "function") then return "broken" end
      if FA.QDB.ZoneMapOK and not FA.QDB.ZoneMapOK() then return "broken" end
      return "ok"
    end },
  { name = "Syndicator", folder = "Syndicator", what = "what your alts hold",
    state = function()
      local S = rawget(_G, "Syndicator")
      if type(S) ~= "table" then return "missing" end
      if ForeverArtisanSettings and ForeverArtisanSettings.altsOff then return "off" end
      if type(S.API) ~= "table" or type(S.API.GetInventoryInfoByItemID) ~= "function" then return "broken" end
      return "ok"
    end },
  { name = "GatherMate2", folder = "GatherMate2", what = "herb and ore spots",
    state = function()
      local st = FA.GatherStatus and FA.GatherStatus() or "missing"
      return (st == "incompatible" and "broken") or (st == "on" and "ok") or st
    end },
}

function FA.AddonHealth()
  local out = {}
  for _, c in ipairs(CHECKS) do
    local ok, st = pcall(c.state)
    out[#out + 1] = { name = c.name, folder = c.folder, what = c.what, state = ok and st or "broken",
      version = Version(c.folder) }
  end
  return out
end

-- one chat line per addon version that we can't read
local function Warn()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local seen = ForeverArtisanSettings.addonWarned or {}
  ForeverArtisanSettings.addonWarned = seen
  for _, a in ipairs(FA.AddonHealth()) do
    if a.state == "broken" and seen[a.name] ~= a.version then
      seen[a.name] = a.version
      print(PREFIX .. ("can't read this version of %s (%s), so %s are off for now. Everything else works. Please report it at %s"):format(
        a.name, a.version, a.what, FA.BUG_URL or "foreverartisan.app/bug"))
    elseif a.state == "ok" then
      seen[a.name] = nil -- readable again: warn again if a later version breaks
    end
  end
end
FA.AddonWarn = Warn

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  -- after the Questie and GatherMate2 reads have started (6 s and 12 s)
  if C_Timer then C_Timer.After(20, function() pcall(Warn) end) else pcall(Warn) end
end)
if FA.GuardEvents then FA.GuardEvents(ev) end
