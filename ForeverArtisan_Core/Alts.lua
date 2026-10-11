-- What your other characters hold, read from Syndicator (the data side of Baganator) when the player
-- has it. Syndicator publishes Syndicator.API for other addons; we only read through it.
-- Shopping lists show "8 on alts" on a material you still need, and the tooltip says who has it where.
-- Same realm group and faction only (what you can mail). Off: /fa alts off.
--   FA.AltStock(itemId)              total, { { name, bags, bank, mail, n }, ... } or nil
--   FA.AltShopText(itemId, missing, craft)  " · 8 on alts" (or ""), and tooltip lines (or nil)
--   FA.SyndicatorStatus()            "on" | "off" | "missing"
local FA = ForeverArtisan
local GOLD, GRAY = "|cffd4a94e", "|cff9d9d9d"

local function API()
  local S = rawget(_G, "Syndicator")
  local A = type(S) == "table" and S.API
  if type(A) ~= "table" or type(A.GetInventoryInfoByItemID) ~= "function" then return nil end
  if type(A.IsReady) == "function" then
    local ok, ready = pcall(A.IsReady)
    if ok and ready == false then return nil end
  end
  return A
end

local function Off()
  return ForeverArtisanSettings and ForeverArtisanSettings.altsOff
end

function FA.SyndicatorStatus()
  local S = rawget(_G, "Syndicator")
  if type(S) ~= "table" or type(S.API) ~= "table" then return "missing" end
  if Off() then return "off" end
  return "on"
end

function FA.AltStock(itemId)
  if Off() or not itemId then return nil end
  local A = API()
  if not A then return nil end
  local ok, info = pcall(A.GetInventoryInfoByItemID, itemId, true, true)
  if not ok or type(info) ~= "table" or type(info.characters) ~= "table" then return nil end
  local me = UnitName and UnitName("player")
  local total, list = 0, {}
  for _, c in ipairs(info.characters) do
    if type(c) == "table" and c.character ~= me then
      local bags, bank, mail = tonumber(c.bags) or 0, tonumber(c.bank) or 0, tonumber(c.mail) or 0
      local n = bags + bank + mail
      if n > 0 then
        total = total + n
        list[#list + 1] = { name = c.character, bags = bags, bank = bank, mail = mail, n = n }
      end
    end
  end
  table.sort(list, function(a, b) return a.n > b.n end)
  if total == 0 then return nil end
  return total, list
end

-- for a shopping row: a short note when the alts could cover some of what's missing
function FA.AltShopText(itemId, missing, craft)
  if not missing or missing <= 0 then return "", nil end
  local total, list = FA.AltStock(itemId)
  if not total then return "", nil end
  local tip = { " ", GOLD .. "On your other characters|r" }
  for i = 1, math.min(5, #list) do
    local a = list[i]
    local where = {}
    if a.bags > 0 then where[#where + 1] = a.bags .. " in bags" end
    if a.bank > 0 then where[#where + 1] = a.bank .. " in the bank" end
    if a.mail > 0 then where[#where + 1] = a.mail .. " in the mailbox" end
    tip[#tip + 1] = ("%s: %s"):format(a.name, table.concat(where, ", "))
  end
  if #list > 5 then tip[#tip + 1] = GRAY .. "...and " .. (#list - 5) .. " more|r" end
  tip[#tip + 1] = GRAY .. (total >= missing and ("Enough to cover the rest: mail them over instead of " .. (craft and "crafting." or "buying."))
    or ("Covers %d of the %d still needed."):format(total, missing)) .. "|r"
  return GOLD .. "  ·  " .. total .. " on alts|r", table.concat(tip, "\n")
end
