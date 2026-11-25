-- Copyright (c) 2026 ForeverArtisan. All rights reserved.
-- ForeverArtisan: Core: your account at a glance, on the /fa Modules tab.
--   Legacy points: worked out from the rules seen on the beta (1 point per class at level 25, 45 and 60,
--   and 1 per crafting profession at skill 150, 225 and 300), from every character that has logged in
--   with ForeverArtisan. The game doesn't hand addons the real number, so it's an estimate.
--   Crafting cooldowns (transmutes, Mooncloth and the like): read from the game when you use one or open
--   the profession window, saved per character, and a chat line when one is ready again.
--   FA.NoteCharacter()          refresh this character's level, class and crafting skills
--   FA.LegacyPoints()           total, { { kind, name, best, who, earned, next }, ... }
--   FA.LegacyLines()            the Modules tab line and its tooltip lines
--   FA.CooldownList()           { { name, who, readyAt, mine }, ... } soonest first
--   FA.CooldownLines()          the Modules tab line and its tooltip lines
local FA = ForeverArtisan
local GOLD, GRAY, GREEN = "|cffd4a94e", "|cff9d9d9d", "|cff40ff40"
local PREFIX = FA.Prefix and FA.Prefix() or "ForeverArtisan: "

local CRAFTING = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring" }
local LEVELS = { 25, 45, 60 }
local SKILLS = { 150, 225, 300 }

local function Plain(v) return v ~= nil and not (FA.IsSecret and FA.IsSecret(v)) end

local function Store()
  ForeverArtisanSettings = ForeverArtisanSettings or {}
  local s = ForeverArtisanSettings
  s.account = s.account or {}
  s.account.chars = s.account.chars or {}
  return s.account
end

local function Me()
  local a = Store()
  local key = FA.CharKey(a.chars)
  local c = a.chars[key]
  if not c then c = {}; a.chars[key] = c end
  c.cds = c.cds or {}
  c.profs = c.profs or {}
  return c, key
end

---------------------------------------------------------------- this character
function FA.NoteCharacter()
  local c = Me()
  local name = UnitName and UnitName("player")
  if Plain(name) and type(name) == "string" then c.name = name end
  -- the full name ("Boomz Dynamitez"): the game gives addons only the first, Syndicator knows the rest
  local S = rawget(_G, "Syndicator")
  if type(S) == "table" and type(S.API) == "table" and type(S.API.GetCurrentCharacter) == "function" then
    local ok, cur = pcall(S.API.GetCurrentCharacter)
    if ok and type(cur) == "string" and cur ~= "" then
      local full = cur:gsub("%-[^%-]*$", "")
      if c.name and full:sub(1, #c.name) == c.name then c.fullName = full end
    end
  end
  local cname, token
  if UnitClass then cname, token = UnitClass("player") end
  if Plain(token) and type(token) == "string" then c.class, c.className = token, cname end
  local lvl = UnitLevel and UnitLevel("player")
  if Plain(lvl) and tonumber(lvl) then c.level = tonumber(lvl) end
  local known = FA.LearnedTrades and FA.LearnedTrades() or {}
  local profs = {}
  for _, p in ipairs(CRAFTING) do
    local t = known[p:lower()]
    if t and t.rank then profs[p] = t.rank end
  end
  c.profs = profs
  -- every profession with its skill (Cooking and First Aid too), and where this character lives:
  -- recipe watch uses these for your alts on the same realm and faction (what you can mail)
  local trades = {}
  for k, t in pairs(known) do if type(k) == "string" and t.rank then trades[k] = t.rank end end
  c.trades = trades
  local realm = GetRealmName and GetRealmName()
  if Plain(realm) and type(realm) == "string" then c.realm = realm end
  local fac = UnitFactionGroup and UnitFactionGroup("player")
  if Plain(fac) and type(fac) == "string" then c.faction = fac end
  c.seen = time and time() or 0
end

-- this character's key in the account list (the same key the profession modules use)
function FA.MyCharKey() local _, key = Me(); return key end

---------------------------------------------------------------- your other characters
-- One line each for the Modules tab, the same on every character (Kerry, Nov 22: "This is confusing
-- when switching between alts"). From what each character saved the last time it logged in.
--   FA.AltRows() -> { { key, title, line, tip = { lines } }, ... } highest level first, not this one
--   FA.ForgetCharacter(key)  drop a character you deleted from the list
local function Title(p) return (p:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)) end
function FA.AltRows()
  local a, out = Store(), {}
  local _, mine = Me()
  for key, c in pairs(a.chars) do
    if key ~= mine and c.name then
      local list = {}
      for p, rank in pairs(c.trades or {}) do list[#list + 1] = { p = Title(p), r = rank } end
      table.sort(list, function(x, y) if x.r ~= y.r then return x.r > y.r end return x.p < y.p end)
      local parts = {}
      for _, t in ipairs(list) do parts[#parts + 1] = t.p .. " " .. t.r end
      local who = c.fullName or c.name
      local tip = { who .. (c.className and ("  (" .. c.className .. (c.level and (" " .. c.level) or "") .. ")") or "") }
      for _, t in ipairs(list) do tip[#tip + 1] = t.p .. ": " .. t.r end
      if #list == 0 then tip[#tip + 1] = "No professions yet." end
      if c.seen and c.seen > 0 and date then tip[#tip + 1] = GRAY .. "As of " .. date("%b %d", c.seen) .. ", the last time it logged in.|r" end
      tip[#tip + 1] = "|cff80c0ffRight-click to remove it from this list (a character you deleted).|r"
      out[#out + 1] = { key = key, level = c.level or 0, who = who, tip = tip,
        title = GOLD .. who .. "|r" .. GRAY .. "  " .. (c.className or "") .. (c.level and (" " .. c.level) or "") .. "|r",
        line = #parts > 0 and table.concat(parts, GRAY .. "  ·  |r") or (GRAY .. "no professions yet|r") }
    end
  end
  table.sort(out, function(x, y) if x.level ~= y.level then return x.level > y.level end return x.who < y.who end)
  return out
end
-- which of your other characters know each profession: { ["herbalism"] = { { who, rank, key }, ... } },
-- best skill first (the Modules tab's "Learned on your other characters" group)
function FA.AltTrades()
  local out = {}
  for _, r in ipairs(FA.AltRows()) do
    local c = Store().chars[r.key]
    for p, rank in pairs(c and c.trades or {}) do
      local k = p:lower()
      out[k] = out[k] or {}
      table.insert(out[k], { who = c.name or r.who, full = r.who, rank = rank, key = r.key })
    end
  end
  for _, l in pairs(out) do table.sort(l, function(x, y) if x.rank ~= y.rank then return x.rank > y.rank end return x.who < y.who end) end
  return out
end
---------------------------------------------------------------- who of yours knows a recipe
-- A recipe item's tooltip lists your characters with that profession: who knows it, who can learn it now,
-- who needs more skill (CurseForge request, Nov 23: "show what alts know or could learn a recipe").
--   FA.TipRequires(tt)  -> skill, profession   from the item's "Requires Tailoring (145)" line
--   FA.RecipeWho(prof, rname, chars, tt) -> rows (tooltip lines, not this character), need; or nil when
--     none of your characters' saved lists has the recipe and the item doesn't require this profession
--   chars = the profession module's saved db.chars (each character's recipes, saved when it opened its window)
local REQ_PATTERN
local function ReqPattern()
  if REQ_PATTERN then return REQ_PATTERN end
  local f = type(ITEM_MIN_SKILL) == "string" and ITEM_MIN_SKILL or "Requires %s (%d)"
  f = f:gsub("%%%d%$", "%%"):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  REQ_PATTERN = "^" .. f:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
  return REQ_PATTERN
end
FA._ReqPattern = ReqPattern
function FA.TipRequires(tt)
  local name = tt and tt.GetName and tt:GetName()
  local n = tt and tt.NumLines and tt:NumLines() or 0
  for i = 2, n do
    local fs = name and _G[name .. "TextLeft" .. i]
    local t = fs and fs.GetText and fs:GetText()
    if type(t) == "string" then
      local p, v = t:match(ReqPattern())
      if p and tonumber(v) then return tonumber(v), p end
    end
  end
end

local function FindRecipe(list, rname)
  if type(list) ~= "table" then return nil end
  if list[rname] then return list[rname] end
  local low = rname:lower()
  for k, r in pairs(list) do if type(k) == "string" and k:lower() == low then return r end end
end

function FA.RecipeWho(prof, rname, chars, tt)
  if not (prof and rname) then return nil end
  local need, reqProf = FA.TipRequires(tt)
  local ours = reqProf and reqProf:lower() == prof:lower()
  local profKey = prof:lower()
  local a = Store()
  local _, mine = Me()
  local seen, rows = {}, {}
  local function add(key)
    if seen[key] or key == mine then return end
    seen[key] = true
    -- only characters on your list (the Modules tab's): one you removed there stays gone here too
    local c = a.chars[key]
    if not c then return end
    local rec = type(chars) == "table" and chars[key] or nil
    local r = rec and FindRecipe(rec.recipes, rname)
    if r then ours = true end
    local rank = (c.trades and c.trades[profKey]) or (rec and rec.skill)
    if not rank and not (r and r.learned) then return end
    local who = c.name or (type(key) == "string" and key:match("^([^%-]+)")) or "?"
    local order, text
    if r and r.learned then
      order, text = 1, GREEN .. "knows it|r"
    elseif not (rec and type(rec.recipes) == "table" and next(rec.recipes)) then
      order, text = 4, GRAY .. "hasn't opened " .. prof .. " yet (" .. rank .. ")|r"
    elseif need and rank >= need then
      order, text = 2, "|cffffff00can learn it (" .. rank .. ")|r"
    elseif need then
      order, text = 3, GRAY .. "needs " .. need .. " (has " .. rank .. ")|r"
    else
      order, text = 2, "|cffffff00doesn't know it (" .. rank .. ")|r"
    end
    rows[#rows + 1] = { order = order, who = who, text = text }
  end
  for key in pairs(type(chars) == "table" and chars or {}) do add(key) end
  for key in pairs(a.chars) do add(key) end
  if not ours or #rows == 0 then return nil, need end
  table.sort(rows, function(x, y) if x.order ~= y.order then return x.order < y.order end return x.who < y.who end)
  local out = {}
  for i, r in ipairs(rows) do
    if i > 8 then out[#out + 1] = GRAY .. "  +" .. (#rows - 8) .. " more|r"; break end
    out[#out + 1] = "  " .. r.who .. "  " .. r.text
  end
  return out, need
end

function FA.ForgetCharacter(key)
  local a = Store()
  local _, mine = Me()
  if key and key ~= mine then a.chars[key] = nil end
end

---------------------------------------------------------------- legacy points
local function Reached(value, steps)
  local n, nextStep = 0, nil
  for _, s in ipairs(steps) do
    if (value or 0) >= s then n = n + 1 elseif not nextStep then nextStep = s end
  end
  return n, nextStep
end

function FA.LegacyPoints()
  local a = Store()
  local bestClass, bestProf = {}, {}
  for _, c in pairs(a.chars) do
    if c.class and c.level then
      local b = bestClass[c.class]
      if not b or c.level > b.best then bestClass[c.class] = { best = c.level, who = c.name, label = c.className or c.class } end
    end
    for p, rank in pairs(c.profs or {}) do
      local b = bestProf[p]
      if not b or rank > b.best then bestProf[p] = { best = rank, who = c.name } end
    end
  end
  local rows, total = {}, 0
  for class, b in pairs(bestClass) do
    local n, nx = Reached(b.best, LEVELS)
    total = total + n
    rows[#rows + 1] = { kind = "class", key = class, name = b.label, best = b.best, who = b.who, earned = n, next = nx }
  end
  for p, b in pairs(bestProf) do
    local n, nx = Reached(b.best, SKILLS)
    total = total + n
    rows[#rows + 1] = { kind = "prof", key = p, name = p, best = b.best, who = b.who, earned = n, next = nx }
  end
  table.sort(rows, function(x, y)
    if x.kind ~= y.kind then return x.kind == "class" end
    return x.name < y.name
  end)
  return total, rows
end

-- Modules tab: "Legacy points: 3 (estimate)  ·  next: level 25 Mage (you're 14), Tailoring 150 (74)"
function FA.LegacyLines()
  local c = Me()
  local total, rows = FA.LegacyPoints()
  local nexts = {}
  for _, r in ipairs(rows) do
    if r.next then
      if r.kind == "class" and r.key == c.class then
        nexts[#nexts + 1] = ("level %d %s (best %d)"):format(r.next, r.name, r.best)
      elseif r.kind == "prof" and c.profs[r.key] then
        nexts[#nexts + 1] = ("%s %d (best %d)"):format(r.name, r.next, r.best)
      end
    end
  end
  local line = GOLD .. "Legacy points:|r " .. total .. GRAY .. " earned (estimate)|r"
    .. (#nexts > 0 and (GRAY .. "  ·  next: |r" .. table.concat(nexts, ", ")) or "")
  local tip = { "Legacy points (estimate)",
    "1 point per class at level 25, 45 and 60, and 1 per crafting profession at skill 150, 225 and 300, earned across your account. Other challenges (PvP, exploring, dungeons, raids) aren't counted here.",
    " " }
  for _, r in ipairs(rows) do
    tip[#tip + 1] = ("%s: %d of 3  " .. GRAY .. "(best %d%s%s)|r"):format(r.name, r.earned, r.best,
      r.who and (", " .. r.who) or "", r.next and ("; next at " .. r.next) or "")
  end
  if #rows == 0 then tip[#tip + 1] = GRAY .. "Nothing yet. Log in on each character once so ForeverArtisan can count it.|r" end
  tip[#tip + 1] = " "
  tip[#tip + 1] = GRAY .. "Counts characters that have logged in with ForeverArtisan on. Gathering professions, Cooking, First Aid and Fishing don't earn points.|r"
  return line, tip
end

---------------------------------------------------------------- crafting cooldowns
-- spells with a long cooldown that matter: every transmute, Mooncloth, and anything else the
-- profession window reports with a cooldown
local function Tracked(name)
  return type(name) == "string" and (name:find("^Transmute") or name == "Mooncloth") and true or false
end

local function NoteCooldown(name, secondsLeft)
  if not (name and secondsLeft and secondsLeft > 60) then return end
  local c = Me()
  c.cds[name] = { readyAt = time() + math.floor(secondsLeft), told = nil }
  FA.ScheduleReady(name, secondsLeft)
end

local scheduled = {}
function FA.ScheduleReady(name, secondsLeft)
  if not (C_Timer and C_Timer.After) or secondsLeft > 6 * 3600 or scheduled[name] then return end
  scheduled[name] = true
  C_Timer.After(secondsLeft + 1, function()
    scheduled[name] = nil
    local c = Me()
    local cd = c.cds[name]
    if cd and cd.readyAt <= time() and not cd.told then
      cd.told = true
      print(PREFIX .. GREEN .. name .. " is ready again.|r")
    end
  end)
end

local function SpellCooldownLeft(spell)
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
    if ok and type(info) == "table" then start, duration = info.startTime, info.duration end
  elseif GetSpellCooldown then
    local ok, s, d = pcall(GetSpellCooldown, spell)
    if ok then start, duration = s, d end
  end
  if not (Plain(start) and Plain(duration) and tonumber(start) and tonumber(duration)) then return nil end
  if duration <= 2 or start <= 0 then return 0 end
  return start + duration - GetTime()
end

-- the open profession window: every recipe it says is on cooldown
local function ReadTradeSkill()
  if not (GetNumTradeSkills and GetTradeSkillInfo and GetTradeSkillCooldown) then return end
  if FA.OthersTradeSkill and FA.OthersTradeSkill() then return end -- someone else's cooldowns
  local ok, n = pcall(GetNumTradeSkills)
  for i = 1, (ok and tonumber(n) or 0) do
    local ok2, name, kind = pcall(GetTradeSkillInfo, i)
    if ok2 and kind ~= "header" and Plain(name) then
      local ok3, cd = pcall(GetTradeSkillCooldown, i)
      if ok3 and Plain(cd) and tonumber(cd) and cd > 60 then NoteCooldown(name, cd) end
    end
  end
end

function FA.CooldownList()
  local a, out, now = Store(), {}, time()
  local _, me = Me()
  for key, c in pairs(a.chars) do
    for name, cd in pairs(c.cds or {}) do
      out[#out + 1] = { name = name, who = c.name or "?", readyAt = cd.readyAt, ready = cd.readyAt <= now, mine = key == me }
    end
  end
  table.sort(out, function(x, y)
    if x.readyAt ~= y.readyAt then return x.readyAt < y.readyAt end
    return x.name < y.name
  end)
  return out
end

local function Left(secs)
  secs = math.max(0, secs)
  local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
  if d > 0 then return d .. "d " .. h .. "h" end
  if h > 0 then return h .. "h " .. m .. "m" end
  return math.max(1, m) .. "m"
end

-- Modules tab: "Cooldowns: Transmute: Arcanite ready (Boomz)  ·  Mooncloth 2d 4h (Tailor)"
function FA.CooldownLines()
  local list, now = FA.CooldownList(), time()
  local parts, tip = {}, { "Crafting cooldowns", " " }
  for i, cd in ipairs(list) do
    local when = cd.ready and (GREEN .. "ready|r") or Left(cd.readyAt - now)
    if i <= 3 then parts[#parts + 1] = ("%s %s %s(%s)|r"):format(cd.name, when, GRAY, cd.who) end
    tip[#tip + 1] = ("%s: %s  " .. GRAY .. "(%s)|r"):format(cd.name, when, cd.who)
  end
  if #list == 0 then
    tip[#tip + 1] = "Transmutes, Mooncloth and other crafting cooldowns show here after you use one or open that profession's window."
  end
  tip[#tip + 1] = " "
  tip[#tip + 1] = GRAY .. "Read from the game on each character; a chat line says when one is ready again.|r"
  local line = GOLD .. "Cooldowns:|r " .. (#parts > 0 and (table.concat(parts, GRAY .. "  ·  |r") .. (#list > 3 and (GRAY .. "  +" .. (#list - 3)) or ""))
    or (GRAY .. "none tracked yet|r"))
  return line, tip
end

-- after login: one chat line for anything on this character that came off cooldown while you were away
local function TellReady()
  local c, now, ready = Me(), time(), {}
  for name, cd in pairs(c.cds) do
    if cd.readyAt <= now then
      if not cd.told then cd.told = true; ready[#ready + 1] = name end
    else
      FA.ScheduleReady(name, cd.readyAt - now)
    end
  end
  table.sort(ready)
  if #ready > 0 then print(PREFIX .. GREEN .. "Ready again: " .. table.concat(ready, ", ") .. ".|r") end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UNIT_SPELLCAST_SUCCEEDED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
  if e == "PLAYER_LOGIN" then
    pcall(FA.NoteCharacter)
    if C_Timer then C_Timer.After(10, function() pcall(TellReady) end) else pcall(TellReady) end
  elseif e == "PLAYER_LEVEL_UP" or e == "SKILL_LINES_CHANGED" then
    if C_Timer then C_Timer.After(1, function() pcall(FA.NoteCharacter) end) else pcall(FA.NoteCharacter) end
  elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 ~= "player" then return end
    local spellID = a3
    local name = spellID and GetSpellInfo and GetSpellInfo(spellID)
    if type(name) ~= "string" and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID) end
    if not (Plain(name) and Tracked(name)) then return end
    local function read()
      local left = SpellCooldownLeft(spellID)
      if left and left > 60 then NoteCooldown(name, left) end
    end
    if C_Timer then C_Timer.After(0.5, function() pcall(read) end) else pcall(read) end
  elseif e == "TRADE_SKILL_SHOW" or e == "TRADE_SKILL_UPDATE" then
    pcall(ReadTradeSkill)
  end
end)
if FA.GuardEvents then FA.GuardEvents(ev) end

FA._AccountReadTradeSkill = ReadTradeSkill -- for the tests
FA._AccountTellReady = TellReady
