-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: a reminder to check for updates. Addons can't reach the internet, so this goes
-- by the version's own age: tools/release.py stamps the release date into Core's TOC
-- (## X-Release-Date), and once that's more than 7 days ago, login says so in one chat line, at most
-- once a week. Off: /fa updates off, or the Settings tab.
local FA = ForeverArtisan
local GOLD, GRAY = "|cffd4a94e", "|cff9d9d9d"
local DAYS = 7

local function Settings() ForeverArtisanSettings = ForeverArtisanSettings or {}; return ForeverArtisanSettings end
function FA.UpdateCheckOn() return Settings().updateCheck ~= false end

-- the release date as a time (noon that day), or nil for a build without one (a test build)
function FA.ReleaseTime()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, d = pcall(get or function() end, "ForeverArtisan_Core", "X-Release-Date")
  if not ok or type(d) ~= "string" then return nil end
  local y, m, day = d:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then return nil end
  return time({ year = tonumber(y), month = tonumber(m), day = tonumber(day), hour = 12 })
end

-- whole days since this version was released, or nil
function FA.VersionAgeDays()
  local t = FA.ReleaseTime()
  if not t then return nil end
  return math.max(0, math.floor((time() - t) / 86400))
end

-- the reminder line when it's due (and remembers it was shown), else nil
function FA.UpdateReminder()
  if not FA.UpdateCheckOn() then return nil end
  local age = FA.VersionAgeDays()
  if not age or age <= DAYS then return nil end
  local s = Settings()
  if s.updateNagAt and time() - s.updateNagAt < DAYS * 86400 then return nil end
  s.updateNagAt = time()
  return ("%sForeverArtisan:|r version %s is %d days old. Check the CurseForge app for updates. %s(/fa updates off hides this)|r")
    :format(GOLD, FA.Version(), age, GRAY)
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  -- a few seconds in, after the login chat settles
  local function Say() local line = FA.UpdateReminder(); if line then print(line) end end
  if C_Timer and C_Timer.After then C_Timer.After(8, Say) else Say() end
end)
if FA.GuardEvents then FA.GuardEvents(ev) end

-- /fa updates on | off
function FA.UpdateCheckCommand(rest)
  local r = (rest or ""):lower()
  if r == "off" then Settings().updateCheck = false elseif r == "on" then Settings().updateCheck = nil end
  local age = FA.VersionAgeDays()
  print(("%sForeverArtisan:|r update reminder %s. %s%s(/fa updates on | off)|r"):format(GOLD,
    FA.UpdateCheckOn() and "on" or "off", GRAY, age and ("This version is " .. age .. " days old. ") or ""))
end

-- /fa updates (Modules.lua loads first, so this wraps its /fa handler)
local orig = SlashCmdList and SlashCmdList.FOREVERARTISAN
if orig then
  SlashCmdList.FOREVERARTISAN = function(msg)
    local word, rest = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if (word or ""):lower() == "updates" then FA.UpdateCheckCommand(rest) return end
    return orig(msg)
  end
end
