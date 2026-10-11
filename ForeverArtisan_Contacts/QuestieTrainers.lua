-- Profession trainers from QuestieDB (the database Questie installs), when the player has it.
-- QuestieDB publishes a read API for other addons (LibQuestieDB) with a version contract; we only
-- read through it, never copy or ship its data. Trade Contacts shows these trainers after your own
-- contacts and the beta trainers (SeedTrainers.lua): who and where, not what they teach.
-- Off switch: /fa contacts questie off. Anything unexpected and the feature quietly stays off.
local _, ns = ...
local FA = ForeverArtisan

local CONTRACT = 3      -- the LibQuestieDB contract this file was written against
local BATCH = 400       -- NPCs read per frame while building, so login doesn't stutter

-- a trainer's title -> profession (first match wins; the order matters for "Fisherman")
local PROF_WORDS = {
  { "alchem", "Alchemy" }, { "blacksmith", "Blacksmithing" }, { "armorsmith", "Blacksmithing" },
  { "weaponsmith", "Blacksmithing" }, { "enchant", "Enchanting" }, { "engineer", "Engineering" },
  { "first aid", "First Aid" }, { "medic", "First Aid" }, { "nurse", "First Aid" }, { "physician", "First Aid" },
  { "fisherman", "Fishing" }, { "fishing", "Fishing" }, { "herbalis", "Herbalism" },
  { "leatherwork", "Leatherworking" }, { "tanner", "Leatherworking" }, { "mining", "Mining" }, { "miner", "Mining" },
  { "skinn", "Skinning" }, { "tailor", "Tailoring" }, { "cooking", "Cooking" }, { "cook", "Cooking" }, { "chef", "Cooking" },
}
-- titles that sell for a trade rather than teach it
local NOT_TRAINER = { "suppl", "vendor", "merchant", "goods", "wares", "reagent", "quartermaster", "import", "fabric", "tackle" }

local state = { list = nil, status = "none", building = false }

local function Lib() return FA.QDB and FA.QDB.Lib() end

local function Version() return FA.QDB and FA.QDB.Version() or "?" end

local function Off()
  local db = ForeverArtisanContactsDB
  return db and db.settings and db.settings.questieOff
end

local function ProfFor(title)
  if type(title) ~= "string" or title == "" then return nil end
  local t = title:lower()
  for _, w in ipairs(NOT_TRAINER) do if t:find(w, 1, true) then return nil end end
  for _, pw in ipairs(PROF_WORDS) do if t:find(pw[1], 1, true) then return pw[2] end end
end

-- QuestieDB stores spawns by AreaID; the game's maps use UiMapIDs (Core's QuestieDB.lua maps them)
local function UiMap(areaId) return FA.QDB and FA.QDB.UiMap(areaId) end

local function hasTrainerFlag(flags)
  return type(flags) == "number" and math.floor(flags / 16) % 2 == 1
end

local function Read(L, id)
  local okF, flags = pcall(L.Npc.npcFlags, id)
  local okT, title = pcall(L.Npc.subName, id)
  -- new Forever NPCs can lack the flag; a clear trainer title is enough then
  if not okT then return nil end
  local prof = ProfFor(title)
  if not prof then return nil end
  if okF and flags and not hasTrainerFlag(flags) then return nil end
  local _, name = pcall(L.Npc.name, id)
  local _, fr = pcall(L.Npc.friendlyToFaction, id)
  local _, spawns = pcall(L.Npc.spawns, id)
  local f = (fr == "AH" and "Both") or (fr == "A" and "Alliance") or (fr == "H" and "Horde") or nil
  if type(name) ~= "string" or not f or type(spawns) ~= "table" then return nil end
  for area, pts in pairs(spawns) do
    local m = UiMap(area)
    local p = type(pts) == "table" and pts[1]
    if m and m > 0 and type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) and p[1] >= 0 and p[2] >= 0 then
      return { id = id, n = name, t = title, prof = prof, f = f, m = m, x = p[1], y = p[2] }
    end
  end
end

-- how many of them are for this player's faction (neutral towns count for both)
local function Fitting(list)
  local n = 0
  for _, q in ipairs(list or {}) do if not ns.SeedFits or ns.SeedFits(q) then n = n + 1 end end
  return n
end

local function Finish(list, L)
  local db = ForeverArtisanContactsDB
  if db then db.questieCache = { version = Version(), contract = L.contractVersion, list = list } end
  state.list, state.status, state.building = list, "ready", false
  -- we read every NPC once; let QuestieDB drop what it cached for us
  if type(L.InvalidateCache) == "function" then pcall(L.InvalidateCache, "Npc") end
  if ns.OnContactsChanged then ns.OnContactsChanged() end
  -- once per account: say what changed
  local st = db and db.settings
  local n = Fitting(list)
  if st and not st.questieNoted and n > 0 then
    st.questieNoted = true
    if ns.say then
      ns.say(("found Questie: %d profession trainers for your faction from its database now show in search and Nearest trainer. /fa contacts questie off turns this off."):format(n))
    end
  end
end

-- read QuestieDB once per QuestieDB version; later logins use the saved list
function ns.BuildQuestieTrainers()
  if state.building or Off() then return end
  local L = Lib()
  if not L then state.status = rawget(_G, "LibQuestieDB") and "incompatible" or "missing"; return end
  local cache = ForeverArtisanContactsDB and ForeverArtisanContactsDB.questieCache
  if cache and cache.version == Version() and cache.contract == L.contractVersion and type(cache.list) == "table" then
    state.list, state.status = cache.list, "ready"
    if ns.OnContactsChanged then ns.OnContactsChanged() end
    return
  end
  local okIds, ids = pcall(L.Npc.GetAllIds)
  if not okIds or type(ids) ~= "table" then state.status = "incompatible"; return end
  state.building, state.status = true, "building"
  local out, i = {}, 1
  local function step()
    local stop = math.min(#ids, i + BATCH - 1)
    for k = i, stop do
      local ok, t = pcall(Read, L, ids[k])
      if ok and t then out[#out + 1] = t end
    end
    i = stop + 1
    if i <= #ids and C_Timer then C_Timer.After(0, step)
    elseif i <= #ids then step()
    else Finish(out, L) end
  end
  step()
end

-- the trainers to show right now, or nil
function ns.QuestieTrainers()
  if Off() or state.status ~= "ready" then return nil end
  return state.list
end

-- "installed, N trainers" / "not installed" / "off" for help lines
function ns.QuestieStatus()
  if Off() then return "off", Fitting(state.list) end
  if state.status == "ready" then return "on", Fitting(state.list) end
  if state.status == "building" then return "reading", 0 end
  if Lib() then return "installed", 0 end
  return rawget(_G, "LibQuestieDB") and "incompatible" or "missing", 0
end

-- the /fa panel's "Works best with" line reads this (Core can't see Trade Contacts' ns)
if FA then FA.QuestieStatus = function() return ns.QuestieStatus() end end

function ns.QuestieReset()
  state.list, state.status, state.building = nil, "none", false
  if FA.QDB and FA.QDB.Reset then FA.QDB.Reset() end
  if ForeverArtisanContactsDB then ForeverArtisanContactsDB.questieCache = nil end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  -- after login settles, so reading never competes with the loading screen
  if C_Timer then C_Timer.After(6, function() pcall(ns.BuildQuestieTrainers) end)
  else pcall(ns.BuildQuestieTrainers) end
end)
if FA and FA.GuardEvents then FA.GuardEvents(ev) end
