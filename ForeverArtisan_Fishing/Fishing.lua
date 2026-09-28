-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Fishing
-- One key casts Fishing, and puts a lure on the pole first whenever it's missing.
-- Every catch is logged by zone/subzone with skill, lure and game time.

local ADDON, ns = ...
ADDON = ADDON or "ForeverArtisan_Fishing"
ns = ns or {}
local LURE_GUARD = 8          -- seconds after applying a lure before we'd try again
local LURE_MIN_LEFT = 5       -- treat a lure with less than this many seconds left as gone
local RAW_CAP = 5000          -- max raw catch entries kept

BINDING_HEADER_FOREVERARTISAN_FISHING = "ForeverArtisan: Fishing"
_G["BINDING_NAME_CLICK ForeverArtisanFishingCastButton:LeftButton"] = "Cast / apply lure"
_G["BINDING_NAME_CLICK ForeverArtisanFishingSwapButton:LeftButton"] = "Swap pole / weapons"

-- Known lures (itemID -> skill bonus). Unknown lures are picked up by tooltip text.
local KNOWN_LURES = {
  [6529] = 25,  -- Shiny Bauble
  [6530] = 50,  -- Nightcrawlers
  [6811] = 50,  -- Aquadynamic Fish Lens
  [6532] = 75,  -- Bright Baubles
  [7307] = 75,  -- Flesh Eating Worm
  [6533] = 100, -- Aquadynamic Fish Attractor
}
local FISHING_IDS = { [7620]=true, [7731]=true, [7732]=true, [18248]=true }

local db
local lureCache = {}          -- itemID -> bonus or false
local lastLureAt = -100
local lastLootAt = -100
local warnedNoLure = false

local say = ForeverArtisan.Printer("Fishing")

---------------------------------------------------------------- API wrappers
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local i = C_Spell.GetSpellInfo(id); return i and i.name
  end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local FISHING = SpellName(7620) or "Fishing"

local function ItemInstant(id)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if f then return f(id) end
end

local function ItemName(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local n = f and f(id)
  return n or ("item:" .. id)
end

local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local SlotItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID

-- Item counts: newer clients moved GetItemCount to C_Item. Fall back to counting bags ourselves.
local CountAPI = (C_Item and C_Item.GetItemCount) or GetItemCount
local function SlotCount(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
  elseif GetContainerItemInfo then
    local _, count = GetContainerItemInfo(bag, slot)
    return count or 0
  end
  return 0
end
local function ItemCount(id, includeBank)
  if not id then return 0 end
  if CountAPI then
    local ok, n = pcall(CountAPI, id, includeBank)
    if ok and type(n) == "number" then return n end
  end
  local n = 0
  for bag = 0, 4 do
    for slot = 1, (NumSlots(bag) or 0) do
      if SlotItemID(bag, slot) == id then n = n + SlotCount(bag, slot) end
    end
  end
  return n
end
ns.ItemCount = ItemCount

---------------------------------------------------------------- lures
local scanTip = CreateFrame("GameTooltip", "ForeverArtisanFishingScanTip", nil, "GameTooltipTemplate")

local function TooltipBonus(bag, slot)
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  scanTip:SetBagItem(bag, slot)
  for i = 2, scanTip:NumLines() do
    local fs = _G["ForeverArtisanFishingScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    -- a real lure says it goes on your pole: "When applied to your fishing pole, increases Fishing by 75"
    local l = t and t:lower()
    if l and l:find("fishing pole") and l:find("increase") then
      local n = tonumber(l:match("by (%d+)"))
      if n and n > 0 and n <= 200 then return n end
    end
  end
  return false
end

local function LureBonus(id, bag, slot)
  if KNOWN_LURES[id] then return KNOWN_LURES[id] end
  if lureCache[id] ~= nil then return lureCache[id] end
  local _, _, _, _, _, classID, subclassID = ItemInstant(id)
  if classID and classID ~= 0 then lureCache[id] = false; return false end -- consumables only
  if subclassID == 5 then lureCache[id] = false; return false end         -- never food or drink
  local b = TooltipBonus(bag, slot)
  lureCache[id] = b
  if b then say(("Learned new lure: %s (+%d)"):format(ItemName(id), b)) end
  return b
end

-- Returns itemID, bonus of the lure to use (pinned name first, else biggest bonus).
local function PickLure()
  local best, bestBonus, pinned
  local want = db.settings.lure and db.settings.lure:lower()
  for bag = 0, 4 do
    for slot = 1, (NumSlots(bag) or 0) do
      local id = SlotItemID(bag, slot)
      if id then
        local b = LureBonus(id, bag, slot)
        if b then
          if want and ItemName(id):lower() == want then pinned = id end
          if not bestBonus or b > bestBonus then best, bestBonus = id, b end
        end
      end
    end
  end
  if pinned then return pinned, LureBonus(pinned) or KNOWN_LURES[pinned] or 0 end
  return best, bestBonus
end

local function PoleEquipped()
  local id = GetInventoryItemID("player", 16)
  if not id then return false end
  local _, _, _, _, _, classID, subclassID = ItemInstant(id)
  return classID == 2 and subclassID == 20
end

-- seconds of lure left on the main hand (0 if none)
local function LureLeft()
  local has, ms = GetWeaponEnchantInfo()
  if has and ms then return ms / 1000 end
  return 0
end

---------------------------------------------------------------- the button
local btn = CreateFrame("Button", "ForeverArtisanFishingCastButton", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:SetAttribute("macrotext", "/cast " .. FISHING)
btn.mode = "cast"
-- In combat the fishing key equips your weapons instead (runs securely, so it works mid-fight).
btn:SetAttribute("_onstate-combat", [[
  if newstate == "fight" then
    local m = self:GetAttribute("weaponmacro")
    if m and m ~= "" then self:SetAttribute("macrotext", m) end
  end
]])
RegisterStateDriver(btn, "combat", "[combat] fight; fish")

btn:SetScript("PreClick", function(self)
  if InCombatLockdown() then return end
  local text, mode = "/cast " .. FISHING, "cast"
  if db.settings.autoLure and PoleEquipped()
     and LureLeft() < LURE_MIN_LEFT and (GetTime() - lastLureAt) > LURE_GUARD then
    local id, bonus = PickLure()
    if id then
      text, mode = ("/use item:%d\n/use 16"):format(id), "lure"
      self.lureId, self.lureBonus = id, bonus
      warnedNoLure = false
    elseif not warnedNoLure then
      say("No lures in your bags. Casting without one.")
      warnedNoLure = true
    end
  end
  self.mode = mode
  self:SetAttribute("macrotext", text)
end)

btn:SetScript("PostClick", function(self, _, down)
  if self.mode == "lure" and down == GetCVarBool("ActionButtonUseKeyDown") then
    lastLureAt = GetTime()
    say(("Applying %s (+%d). Press again to cast."):format(ItemName(self.lureId), self.lureBonus or 0))
  end
end)

---------------------------------------------------------------- fishing mode key
local owner = CreateFrame("Frame")
local pendingMode = false
local channeling = false
-- Reel-in uses Blizzard's own "Interact with target" binding on the bobber (soft targeting).
ns.reelOK = GetCVar and GetCVar("SoftTargetInteract") ~= nil

-- Reel-in command: if the game soft-targets the bobber we use "Interact with Target"
-- (no aiming). If it doesn't (Classic clients often don't), we use "Interact with Mouseover":
-- rest the mouse on the bobber and press the key instead of right-clicking it.
local softSeen = false
local castToken = 0
local function ReelCommand()
  return (ns.reelOK and softSeen) and "INTERACTTARGET" or "INTERACTMOUSEOVER"
end
ns.ReelMode = function() return (ns.reelOK and softSeen) and "target" or "mouseover" end

local function UpdateMode()
  if InCombatLockdown() then pendingMode = true; return end
  pendingMode = false
  ClearOverrideBindings(owner)
  if not PoleEquipped() then return end
  local s = db.settings
  local key, reel = s.key, s.reelKey
  if key and key ~= "" then
    if channeling and s.reelSameKey then
      SetOverrideBinding(owner, true, key, ReelCommand())
    else
      SetOverrideBindingClick(owner, true, key, "ForeverArtisanFishingCastButton", "LeftButton")
    end
  end
  if reel and reel ~= "" and reel ~= key then
    SetOverrideBinding(owner, true, reel, ReelCommand())
  end
end

-- Is the fishing key actually bound right now? (Another addon, a bindings reload, or equip timing can drop it.)
local CAST_ACTION = "CLICK ForeverArtisanFishingCastButton:LeftButton"
local function KeyActive()
  local k = db and db.settings.key
  if not k or k == "" or not GetBindingAction then return false end
  local ok, action = pcall(GetBindingAction, k, true)
  return ok and (action == CAST_ACTION or (channeling and action and action:find("^INTERACT"))) or false
end
ns.KeyActive = KeyActive

-- Re-apply shortly after something changes, and keep checking while the pole is on.
local function UpdateModeSoon()
  if not C_Timer then UpdateMode(); return end
  C_Timer.After(0.3, function() if not InCombatLockdown() then UpdateMode() end end)
  C_Timer.After(1.5, function() if not InCombatLockdown() then UpdateMode() end end)
end
ns.UpdateModeSoon = UpdateModeSoon
if C_Timer and C_Timer.NewTicker then
  C_Timer.NewTicker(2, function()
    if not db or InCombatLockdown() or channeling then return end
    local k = db.settings.key
    if k and k ~= "" and PoleEquipped() and not KeyActive() then UpdateMode() end
  end)
end

local function Diag() db.diag = db.diag or {}; return db.diag end

-- is the game's soft interact target our bobber (not a mailbox or an NPC)?
-- Fishing pools (schools) are game objects too, and the game may soft-target the pool
-- instead of your bobber. Only a named bobber counts; any other named object doesn't.
local function SoftIsBobber(guid)
  if guid and not tostring(guid):find("^GameObject") then return false end
  local name = UnitName and UnitName("softinteract")
  if db then db.diag = db.diag or {}; db.diag.softName = name or "(none)" end
  if not name or name == "" then return true end
  return name:lower():find("bobber") ~= nil
end

local function StartChannel()
  channeling, softSeen = true, false
  castToken = castToken + 1
  local tok = castToken
  local d = Diag(); d.channels = (d.channels or 0) + 1
  d.softCVar = GetCVar and GetCVar("SoftTargetInteract") or "missing"
  UpdateMode()
  -- if the game already soft-targets something (the bobber), switch to Interact with Target
  if C_Timer then
    C_Timer.After(0.8, function()
      if tok == castToken and channeling and UnitExists and UnitExists("softinteract")
         and SoftIsBobber(UnitGUID and UnitGUID("softinteract")) then
        softSeen = true; d.softHits = (d.softHits or 0) + 1
        d.lastSoft = UnitName and UnitName("softinteract") or "?"
        UpdateMode()
      end
    end)
    -- safety: never leave the key stuck on reel-in
    C_Timer.After(30, function() if tok == castToken and channeling then channeling = false; UpdateMode() end end)
  end
end

local function StopChannel()
  if not channeling then return end
  channeling, softSeen = false, false
  UpdateMode()
end

---------------------------------------------------------------- fishing environment (CVars)
-- While the pole is on: soft-target the bobber for reel-in, and boost splash sounds.
-- Your own values are saved in ForeverArtisanFishingDB and put back when the pole comes off or you log out.
local function WantedCVars()
  local s, w = db.settings, {}
  if ns.reelOK and (s.reelSameKey or (s.reelKey and s.reelKey ~= "")) then
    w.SoftTargetInteract, w.SoftTargetInteractArc, w.SoftTargetInteractRange = "3", "2", "30"
  end
  if s.soundBoost then
    w.Sound_EnableSFX, w.Sound_SFXVolume, w.Sound_MusicVolume, w.Sound_AmbienceVolume = "1", "1.0", "0", "0"
  end
  return w
end

local function RestoreEnv()
  if not db.envSaved then return end
  for k, v in pairs(db.envSaved) do pcall(SetCVar, k, v) end
  db.envSaved = nil
end

function ns.UpdateEnv()
  RestoreEnv()
  if not PoleEquipped() then return end
  db.envSaved = {}
  for k, v in pairs(WantedCVars()) do
    local cur = GetCVar(k)
    if cur ~= nil then
      db.envSaved[k] = cur
      pcall(SetCVar, k, v)
    end
  end
end
ns.RestoreEnv = RestoreEnv

---------------------------------------------------------------- weapon swap
-- Toggle: pole on -> equip your weapons; weapons on -> equip the pole. Works in combat
-- because the choice is made by a secure state driver, not by addon code.
local POLE_TYPE = (GetItemSubClassInfo and GetItemSubClassInfo(2, 20)) or "Fishing Poles"
local MH_OK = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OH_OK = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true, INVTYPE_WEAPON = true }

local swap = CreateFrame("Button", "ForeverArtisanFishingSwapButton", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
swap:RegisterForClicks("AnyUp", "AnyDown")
swap:SetAttribute("type", "macro")
swap:SetAttribute("_onstate-pole", [[
  if newstate == "yes" then
    self:SetAttribute("macrotext", self:GetAttribute("weaponmacro"))
  else
    self:SetAttribute("macrotext", self:GetAttribute("polemacro"))
  end
]])
RegisterStateDriver(swap, "pole", "[equipped:" .. POLE_TYPE .. "] yes; no")
ns.swapButton = swap

local function IsPole(id)
  if not id then return false end
  local _, _, _, _, _, classID, subclassID = ItemInstant(id)
  return classID == 2 and subclassID == 20
end
local function EquipLoc(id) if id then return select(4, ItemInstant(id)) end end

-- which slot(s) an item may go in: "pole", "mh", "oh"
function ns.GearFits(id, slot)
  if slot == "pole" then return IsPole(id) end
  local loc = EquipLoc(id)
  if IsPole(id) then return false end
  if slot == "mh" then return MH_OK[loc] or false end
  return OH_OK[loc] or false
end

-- remember what you wear so empty slots still work
function ns.TrackGear()
  local mh, oh = GetInventoryItemID("player", 16), GetInventoryItemID("player", 17)
  if IsPole(mh) then db.settings.pole = mh
  elseif mh then db.lastGear = { mh = mh, oh = oh } end
end

-- effective set: slots you filled win, otherwise what you last wore
function ns.GearSet()
  local g = db.settings.gear or {}
  local last = db.lastGear or {}
  local mh, oh = g.mh, g.oh
  if not mh then mh, oh = last.mh, (g.oh or last.oh) end
  if EquipLoc(mh) == "INVTYPE_2HWEAPON" then oh = nil end
  return mh, oh, db.settings.pole
end

local function EquipName(id)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return (f and f(id)) or ("item:" .. id)
end

local function WeaponMacro()
  local mh, oh = ns.GearSet()
  local lines = {}
  if mh then lines[#lines + 1] = "/equip " .. EquipName(mh) end
  if oh then lines[#lines + 1] = "/equipslot 17 " .. EquipName(oh) end
  return table.concat(lines, "\n")
end

function ns.UpdateGear()
  if InCombatLockdown() then ns.gearPending = true; return end
  ns.gearPending = false
  local _, _, pole = ns.GearSet()
  local wm = WeaponMacro()
  local pm = pole and ("/equip " .. EquipName(pole)) or ""
  swap:SetAttribute("weaponmacro", wm)
  swap:SetAttribute("polemacro", pm)
  swap:SetAttribute("macrotext", PoleEquipped() and wm or pm)
  btn:SetAttribute("weaponmacro", wm)
end

function ns.SetGear(slot, id)
  if slot == "pole" then db.settings.pole = id
  else db.settings.gear = db.settings.gear or {}; db.settings.gear[slot] = id end
  ns.UpdateGear()
  if ns.OnChange then ns.OnChange() end
end

local swapOwner = CreateFrame("Frame")
function ns.UpdateSwapKey()
  if InCombatLockdown() then return end
  ClearOverrideBindings(swapOwner)
  local k = db.settings.swapKey
  if k and k ~= "" then SetOverrideBindingClick(swapOwner, true, k, "ForeverArtisanFishingSwapButton", "LeftButton") end
end

---------------------------------------------------------------- key assignment
-- One key per job. Setting a key that another ForeverArtisan Fishing job uses moves it here.
local KEY_JOBS = { key = "Fishing key", reelKey = "Reel-in key", swapKey = "Swap key" }
local function KeyLabel(k)
  if not k or k == "" then return "none" end
  return (GetBindingText and GetBindingText(k, "KEY_")) or k
end
ns.KeyLabel = KeyLabel

function ns.SetKey(field, key)
  if InCombatLockdown() then say("Can't change keys in combat."); return end
  key = (key and key ~= "") and key:upper() or ""
  if key == "OFF" or key == "NONE" then key = "" end
  local s = db.settings
  if key ~= "" then
    if field == "reelKey" and key == s.key then
      -- reel on the fishing key = the "same key reels in" option
      s.reelKey, s.reelSameKey = "", true
      say("Your fishing key already reels in, so no separate reel key is needed.")
      UpdateMode(); ns.UpdateEnv(); if ns.OnChange then ns.OnChange() end
      return
    end
    for other, label in pairs(KEY_JOBS) do
      if other ~= field and s[other] == key then
        s[other] = ""
        say(("%s was also %s. Cleared it there."):format(label, KeyLabel(key)))
      end
    end
  end
  s[field] = key
  if key == "SPACE" and field ~= "swapKey" then
    say("Heads up: Space won't jump while your fishing pole is equipped. It goes back to jumping when the pole comes off.")
  end
  say(("%s: %s"):format(KEY_JOBS[field], KeyLabel(key)))
  UpdateMode(); ns.UpdateSwapKey(); ns.UpdateEnv()
  if ns.OnChange then ns.OnChange() end
end

-- what a key does right now (for the status line)
function ns.KeyNow()
  local s = db.settings
  if not PoleEquipped() then return "pole off: your keys work normally" end
  if InCombatLockdown() then return "in combat: fishing key equips weapons" end
  if channeling and s.reelSameKey then
    return ns.ReelMode() == "target" and "bobber out: fishing key reels in"
      or "bobber out: point at the bobber and press your fishing key"
  end
  return "ready: fishing key casts (or puts a lure on first)"
end

---------------------------------------------------------------- catch log
-- Forever uses the modern profession API, so try several sources and remember which worked.
local FISHING_SKILL_LINE = 356
local skillSource = "none"

local function IsFishingName(n) return n and (n == FISHING or n == "Fishing") end

local FishingSkillLive
local function FishingSkill()
  local r, m, mx = FishingSkillLive()
  if r and skillSource ~= "chat" and db then db.skill = r; if mx and mx > 0 then db.skillMax = mx end end
  return r, m, mx or (db and db.skillMax)
end
FishingSkillLive = function()
  -- 1) modern: GetProfessions() -> fishing slot -> GetProfessionInfo
  if GetProfessions and GetProfessionInfo then
    local ok, p1, p2, arch, fish, cook = pcall(GetProfessions)
    if ok then
      for _, idx in ipairs({ fish, p1, p2, cook, arch }) do
        if idx then
          local name, _, rank, maxr, _, _, line, mod = GetProfessionInfo(idx)
          if rank and (line == FISHING_SKILL_LINE or IsFishingName(name)) then
            skillSource = "GetProfessionInfo"; return rank, mod, maxr
          end
        end
      end
    end
  end
  -- 2) modern: C_TradeSkillUI by skill line id
  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, FISHING_SKILL_LINE)
    if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
      skillSource = "C_TradeSkillUI"; return info.skillLevel, info.skillModifier, info.maxSkillLevel
    end
  end
  -- 3) classic: skill lines
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod, maxr = GetSkillLineInfo(i)
      if not header and IsFishingName(name) and rank then
        skillSource = "GetSkillLineInfo"; return rank, mod, maxr
      end
    end
  end
  -- 4) last value seen in chat ("Your skill in Fishing has increased to N.")
  if db and db.skill then skillSource = "chat"; return db.skill, nil, db.skillMax end
end

local function Where()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local x, y
  if mapID then
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then x, y = pos:GetXY() end
  end
  local zone = GetRealZoneText() or GetZoneText() or "?"
  local sub = GetSubZoneText() or ""
  if sub == "" then sub = zone end
  return zone, sub, mapID, x and math.floor(x * 1000 + 0.5) / 10, y and math.floor(y * 1000 + 0.5) / 10
end

local function ZoneRec()
  local zone, sub, mapID = Where()
  local key = zone .. " / " .. sub
  local z = db.zones[key]
  if not z then
    z = { zone = zone, sub = sub, mapID = mapID, casts = 0, catches = 0, escaped = 0, items = {} }
    db.zones[key] = z
  end
  return z, key
end

local function Today() return date("%Y-%m-%d") end

local function LogCatch()
  local now = GetTime()
  if now - lastLootAt < 1 then return end
  lastLootAt = now
  local zone, sub, mapID, x, y = Where()
  local z = ZoneRec()
  local rank, mod = FishingSkill()
  local lure = LureLeft() > 0 and 1 or 0
  local h, m = GetGameTime()
  local entry = { d = Today(), t = time(), zone = zone, sub = sub, mapID = mapID, x = x, y = y,
                  skill = rank, mod = mod, lure = lure, gt = ("%02d:%02d"):format(h, m), items = {} }
  local got = {}
  for i = 1, GetNumLootItems() do
    local link = GetLootSlotLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      local _, name, qty, _, quality = GetLootSlotInfo(i)
      qty = qty or 1
      entry.items[#entry.items + 1] = { id = id, n = qty }
      local it = z.items[id]
      if not it then it = { name = name, q = quality, n = 0, hauls = 0 }; z.items[id] = it end
      it.n = it.n + qty
      it.hauls = it.hauls + 1
      it.name = name or it.name
      it.lastSeen = Today()
      if rank then
        it.minSkill = math.min(it.minSkill or rank, rank)
      end
      got[#got + 1] = (qty > 1 and (qty .. "x ") or "") .. (link or name)
    end
  end
  if #entry.items == 0 then return end
  z.catches = z.catches + 1
  z.lastSeen = Today()
  local raw = db.raw
  raw[#raw + 1] = entry
  if #raw > RAW_CAP then table.remove(raw, 1) end
  if db.settings.verbose then say("Caught " .. table.concat(got, ", ")) end
  if ns.OnCatch then ns.OnCatch(entry) end
  if ns.OnDerbyCatch then ns.OnDerbyCatch(entry) end
  if ns.OnChange then ns.OnChange() end
end

---------------------------------------------------------------- pole durability
-- A broken pole (0 durability) still looks equipped, but the game says
-- "Must have a Fishing Pole equipped". Say what's really wrong instead.
local lastPoleWarn, poleWarnedLow = -100, false
local function CheckPole(fromError)
  if not PoleEquipped() or not GetInventoryItemDurability then return end
  local cur, max = GetInventoryItemDurability(16)
  if not cur or not max or max == 0 then return end
  if cur == 0 then
    if fromError or GetTime() - lastPoleWarn > 30 then
      lastPoleWarn = GetTime()
      say("|cffff4040Your fishing pole is broken (0 durability).|r Repair it at any vendor with a Repair option. That's why the game says a pole isn't equipped.")
      pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
    end
  elseif cur / max <= 0.2 then
    if not poleWarnedLow then
      poleWarnedLow = true
      say(("|cffffff00Your fishing pole is almost broken (%d/%d durability).|r Repair it soon."):format(cur, max))
    end
  else
    poleWarnedLow = false
  end
end
ns.CheckPole = CheckPole

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
local function Reg(e) pcall(ev.RegisterEvent, ev, e) end
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LOOT_OPENED", "UNIT_SPELLCAST_SUCCEEDED",
  "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE", "CHAT_MSG_SKILL", "GET_ITEM_INFO_RECEIVED",
  "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "PLAYER_LOGOUT",
  "PLAYER_SOFT_INTERACT_CHANGED", "LOOT_CLOSED", "UPDATE_INVENTORY_DURABILITY", "UPDATE_BINDINGS" }) do Reg(e) end

local ESCAPED = { [ERR_FISH_ESCAPED or "Fish escaped!"] = true, [ERR_FISH_NOT_HOOKED or "No fish are hooked."] = true }

ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
  if e == "ADDON_LOADED" and a1 == ADDON then
    ForeverArtisan.Migrate("ForeverArtisanFishingDB", "MatsFishDB")
    ForeverArtisanFishingDB = ForeverArtisanFishingDB or {}
    db = ForeverArtisanFishingDB
    db.version = ForeverArtisan.Version()
    db.settings = db.settings or {}
    local s = db.settings
    if s.autoLure == nil then s.autoLure = true end
    if s.key == nil then s.key = "BUTTON3" end
    if s.verbose == nil then s.verbose = false end
    if s.hud == nil then s.hud = true end
    if s.swapKey == nil then s.swapKey = "" end
    if s.reelSameKey == nil then s.reelSameKey = true end
    if s.reelKey == nil then s.reelKey = "" end
    if s.soundBoost == nil then s.soundBoost = false end
    -- older versions let two jobs share one key; keep the first, clear the rest
    local seenKey = {}
    for _, f in ipairs({ "key", "swapKey", "reelKey" }) do
      local k = s[f]
      if k and k ~= "" then
        if seenKey[k] then s[f] = "" else seenKey[k] = true end
      end
    end
    db.goals = db.goals or {}
    db.skillLog = db.skillLog or {}
    db.zones = db.zones or {}
    db.raw = db.raw or {}
  elseif not db then
    return
  elseif e == "PLAYER_ENTERING_WORLD" or e == "PLAYER_EQUIPMENT_CHANGED" or e == "PLAYER_REGEN_ENABLED" then
    if e == "PLAYER_EQUIPMENT_CHANGED" then ns.TrackGear(); CheckPole() end
    if e ~= "PLAYER_REGEN_ENABLED" then ns.UpdateEnv() end
    if e ~= "PLAYER_REGEN_ENABLED" or pendingMode then UpdateMode() end
    if e ~= "PLAYER_REGEN_ENABLED" then UpdateModeSoon() end
    if e ~= "PLAYER_REGEN_ENABLED" or ns.gearPending then ns.UpdateGear() end
    if e == "PLAYER_ENTERING_WORLD" then
      ns.UpdateSwapKey()
      if (db.settings.key or "") == "" and not ns.warnedNoKey then
        ns.warnedNoKey = true
        say("No fishing key set. Type /fa fish and click Fishing key, or /fa fish key SPACE.")
      end
    end
    if ns.OnChange then ns.OnChange() end
  elseif e == "UPDATE_BINDINGS" then
    -- the game reloaded key bindings; put the fishing key back if the pole is on
    if not InCombatLockdown() and not channeling then UpdateModeSoon() end
  elseif e == "PLAYER_REGEN_DISABLED" then
    -- still allowed to rebind here: make sure the fishing key isn't stuck on "reel in"
    channeling = false
    UpdateMode()
  elseif e == "PLAYER_LOGOUT" then
    RestoreEnv()
  elseif (e == "UNIT_SPELLCAST_CHANNEL_START" or e == "UNIT_SPELLCAST_CHANNEL_STOP") and a1 == "player" then
    if FISHING_IDS[a3] or SpellName(a3) == FISHING then
      if e == "UNIT_SPELLCAST_CHANNEL_START" then
        if not channeling then StartChannel() end
      else
        StopChannel()
      end
    end
  elseif e == "PLAYER_SOFT_INTERACT_CHANGED" then
    if channeling and a2 and a2 ~= "" and not softSeen and SoftIsBobber(a2) then
      softSeen = true
      local d = Diag(); d.softHits = (d.softHits or 0) + 1; d.lastSoft = tostring(a2):match("^(%a+)") or "?"
      UpdateMode()
    end
  elseif e == "LOOT_CLOSED" then
    StopChannel()
  elseif e == "GET_ITEM_INFO_RECEIVED" then
    ns.UpdateGear()
  elseif e == "LOOT_OPENED" then
    if IsFishingLoot and IsFishingLoot() then LogCatch() end
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" then
    if FISHING_IDS[a3] or SpellName(a3) == FISHING then
      local z = ZoneRec(); z.casts = z.casts + 1
      if not channeling then StartChannel() end
    end
  elseif e == "CHAT_MSG_SKILL" then
    if type(a1) == "string" and (a1:find(FISHING, 1, true) or a1:find("Fishing", 1, true)) then
      local n = tonumber(a1:match("(%d+)"))
      if n then
        db.skill = n
        if ns.OnSkillUp then ns.OnSkillUp(n) end
        if ns.OnChange then ns.OnChange() end
      end
    end
  elseif e == "UPDATE_INVENTORY_DURABILITY" then
    CheckPole()
  elseif e == "UI_ERROR_MESSAGE" or e == "UI_INFO_MESSAGE" then
    local msg = type(a2) == "string" and a2 or a1
    if ESCAPED[msg] then local z = ZoneRec(); z.escaped = z.escaped + 1 end
    if type(msg) == "string" and msg:lower():find("fishing pole") then CheckPole(true) end
  end
end)

---------------------------------------------------------------- slash
local function ZoneReport(z, limit)
  local list = {}
  for id, it in pairs(z.items) do list[#list + 1] = { id = id, it = it } end
  table.sort(list, function(a, b) return a.it.hauls > b.it.hauls end)
  local c = math.max(z.catches, 1)
  say(("%s: %d catches, %d casts, %d got away"):format(z.sub, z.catches, z.casts, z.escaped))
  for i = 1, math.min(limit or 99, #list) do
    local it = list[i].it
    say(("  %s  %d%%  (%d total%s)"):format(it.name or list[i].id, math.floor(it.hauls * 100 / c + 0.5), it.n,
      it.minSkill and (", seen at skill " .. it.minSkill) or ""))
  end
end

SLASH_FAFISH1 = "/fafish"
SlashCmdList.FAFISH = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  local s = db.settings
  if cmd == "key" or cmd == "reelkey" or cmd == "swapkey" then
    local field = (cmd == "key" and "key") or (cmd == "reelkey" and "reelKey") or "swapKey"
    if rest == "" then
      say(("%s: %s. Examples: /fa fish %s SPACE, /fa fish %s BUTTON3 (middle mouse), /fa fish %s F, or off."):format(
        KEY_JOBS[field], KeyLabel(s[field]), cmd, cmd, cmd))
    else
      ns.SetKey(field, rest:gsub("%s+", ""))
    end
  elseif cmd == "lure" then
    if rest == "" or rest:lower() == "best" then s.lure = nil; say("Using the best lure in your bags.")
    elseif rest:lower() == "off" then s.autoLure = false; say("Auto-lure off.")
    elseif rest:lower() == "on" then s.autoLure = true; say("Auto-lure on.")
    else s.lure = rest; s.autoLure = true; say("Preferring " .. rest .. " when you have it.") end
  elseif cmd == "zone" then
    local z = ZoneRec(); ZoneReport(z)
  elseif cmd == "zones" then
    for _, z in pairs(db.zones) do if z.catches > 0 then say(("%s / %s: %d catches"):format(z.zone, z.sub, z.catches)) end end
  elseif cmd == "verbose" then
    s.verbose = not s.verbose; say("Catch messages " .. (s.verbose and "on" or "off") .. ".")
  elseif cmd == "minimap" and ns.MinimapCommand then
    ns.MinimapCommand(rest)
  elseif cmd == "hud" then
    s.hud = not s.hud; if ns.OnChange then ns.OnChange() end; say("Lure timer " .. (s.hud and "shown" or "hidden") .. ".")
  elseif cmd == "goal" and ns.AddGoalByName then
    local n, name = rest:match("^(%d+)%s+(.+)$")
    if n then ns.AddGoalByName(name, tonumber(n)) else say("Usage: /fa fish goal 20 Raw Mithril Head Trout") end
  elseif cmd == "derby" and ns.DerbyStatus then
    local st, sec = ns.DerbyStatus()
    say(st == "live" and ("Derby is LIVE, ends in " .. ns.DerbyClock(sec) .. ".")
      or ("Next derby: " .. ns.DerbyWhen() .. ", in " .. ns.DerbyClock(sec) .. "."))
  elseif cmd == "marker" and ns.CalibrateMarker then
    if rest == "off" or rest == "on" then
      s.showMarker = (rest == "on"); if ns.UpdateMarker then ns.UpdateMarker() end
      say("Cast marker " .. rest .. ".")
    elseif rest == "add" then
      ns.CalibrateMarker(true)
    elseif rest == "test" then
      ns.TestMarker()
    elseif rest == "status" then
      ns.MarkerStatus()
    else
      ns.CalibrateMarker()
    end
  elseif cmd == "snap" and ns.SnapCamera then
    ns.SnapCamera()
  elseif cmd == "goals" and rest == "reset" and ns.ResetGoalProgress then
    ns.ResetGoalProgress()
  elseif cmd == "reset" and rest == "confirm" then
    db.zones, db.raw = {}, {}; say("Catch log cleared.")
  elseif cmd == "" and ns.ToggleUI then
    ns.ToggleUI()
  else
    local id, bonus = PickLure()
    local left = LureLeft()
    local rank, mod = FishingSkill()
    say(("Pole: %s | Lure on pole: %s | Best in bags: %s | Skill: %s | Key: %s | Auto-lure: %s"):format(
      PoleEquipped() and "yes" or "no",
      left > 0 and (math.floor(left / 60) .. "m " .. math.floor(left % 60) .. "s") or "none",
      id and (ItemName(id) .. " (+" .. bonus .. ")") or "none",
      rank and (rank .. (mod and mod > 0 and (" +" .. mod) or "") .. " via " .. skillSource) or "? (no source)",
      (s.key and s.key ~= "") and (s.key .. (PoleEquipped() and (KeyActive() and " (active)" or " (not active yet, fixing in 2s)") or " (waits for pole)")) or "off",
      s.autoLure and "on" or "off"))
    local z = db.zones[select(2, ZoneRec())]
    if z and z.catches > 0 then ZoneReport(z, 5) end
    say("Commands: /fa fish (window), key||reelkey||swapkey <KEY||off>, lure <best||name||on||off>, goal <amount> <item name>, zone, zones, verbose, hud, minimap [angle||reset], goals reset, derby, marker [add||on||off||test||status], snap, reset confirm, help")
  end
end

---------------------------------------------------------------- shared with UI.lua
-- every lure in your bags: { {id=, bonus=, count=}, ... } sorted by bonus
local function BagLures()
  local seen, list = {}, {}
  for bag = 0, 4 do
    for slot = 1, (NumSlots(bag) or 0) do
      local id = SlotItemID(bag, slot)
      if id and not seen[id] then
        local b = LureBonus(id, bag, slot)
        if b then
          seen[id] = true
          list[#list + 1] = { id = id, bonus = b, count = ItemCount(id) }
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.bonus > b.bonus end)
  return list
end

ns.DB = function() return db end
ns.say, ns.PickLure, ns.BagLures, ns.LureLeft = say, PickLure, BagLures, LureLeft
ns.PoleEquipped, ns.FishingSkill, ns.Where, ns.ItemName = PoleEquipped, FishingSkill, Where, ItemName
ns.UpdateMode, ns.ZoneRec, ns.Today = UpdateMode, ZoneRec, Today
ns.SkillSource = function() return skillSource end
ns.ResetLog = function() db.zones, db.raw = {}, {}; if ns.OnChange then ns.OnChange() end end
