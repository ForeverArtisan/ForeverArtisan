-- ForeverArtisan smoke test: loads every module with a stubbed WoW API and exercises the main paths.
-- run from the repo:  lua5.1 tools/tests/suite.lua .     (needs Lua 5.1; ends with "SUITE OK")
io.stdout:setvbuf("no")
-- smoke test: load the whole ForeverArtisan suite with stubbed WoW API
local ROOT = arg[1]
date=os.date tinsert=table.insert wipe=function(t) for k in pairs(t) do t[k]=nil end return t end
strtrim=function(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local frames, noop = {}, function() end
local function obj()
  local o={scripts={},attrs={},_w=470,_h=578}
  return setmetatable(o,{__index=function(t,k)
    if k=="SetScript" then return function(s,n,fn) s.scripts[n]=fn end end
    if k=="HookScript" then return function(s,n,fn) s.scripts[n]=fn end end
    if k=="GetScript" then return function(s,n) return s.scripts[n] end end
    if k=="SetAttribute" then return function(s,a,v) s.attrs[a]=v end end
    if k=="CreateFontString" or k=="CreateTexture" then return function() return obj() end end
    if k=="SetText" then return function(s,v) s._text=v end end
    if k=="GetText" then return function(s) return s._text end end
    if k=="GetPoint" then return function() return "CENTER",nil,"CENTER",0,0 end end
    if k=="IsShown" or k=="IsVisible" then return function(s) return s._shown end end
    if k=="Show" then return function(s) s._shown=true end end
    if k=="Hide" then return function(s) s._shown=false end end
    if k=="SetShown" then return function(s,v) s._shown=v and true or false end end
    if k=="GetChecked" or k=="HasFocus" then return function() return false end end
    if k=="SetSize" then return function(s,w,h) s._w, s._h = w, h end end
    if k=="SetWidth" then return function(s,w) s._w=w end end
    if k=="GetWidth" then return function(s) return s._w end end
    if k=="GetHeight" then return function(s) return s._h end end
    if k=="GetCenter" then return function() return 100,100 end end
    if k=="GetChildren" then return function() end end
    if k=="GetNumPoints" or k=="GetFrameLevel" or k=="NumLines" then return function() return 0 end end
    if k=="GetItem" then return function() return nil end end
    if type(k)=="string" and k:match("^%l") then return nil end
    return noop end})
end
local U; U=setmetatable({},{__index=function() return U end,__call=function() return nil end})
CreateFrame=function(kind,name) local f=obj(); frames[#frames+1]=f; if name then _G[name]=f end; return f end
UIParent=obj(); WorldFrame=obj(); GameTooltip=obj(); ItemRefTooltip=obj(); Minimap=obj(); UISpecialFrames={}
local chat={}
DEFAULT_CHAT_FRAME={AddMessage=function(_,m) chat[#chat+1]=m; print("CHAT:",(tostring(m):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""))) end}
print=print
SlashCmdList={}
InCombatLockdown=function() return false end GetTime=function() return 1000 end time=os.time
UnitName=function() return "Tester" end UnitFactionGroup=function() return "Horde" end UnitLevel=function() return 20 end
UnitExists=function() return false end UnitGUID=function() return nil end
GetRealZoneText=function() return "Desolace" end GetSubZoneText=function() return "Shadowprey Village" end GetZoneText=GetRealZoneText GetMinimapZoneText=GetSubZoneText
C_Map={GetBestMapForUnit=function() return 1443 end, GetPlayerMapPosition=function() return {GetXY=function() return .2,.7 end} end, GetMapInfo=function() return {name="Desolace"} end}
C_Timer={After=noop, NewTicker=function() return {Cancel=noop} end}
GetProfessions=function() return 1,2,3,4,5,6,7,8 end
GetProfessionInfo=function(i) local t={[1]={"Herbalism",182},[2]={"Mining",186},[3]={"Skinning",393},[4]={"Fishing",356},[5]={"Cooking",185},[6]={"First Aid",129},[7]={"Alchemy",171},[8]={"Leatherworking",165}} local e=t[i] return e[1],1,150,225,0,0,e[2],0 end
GetCVar=function() return "1" end SetCVar=noop GetCVarBool=function() return true end
ClearOverrideBindings=noop SetOverrideBindingClick=noop SetOverrideBinding=noop RegisterStateDriver=noop GetBindingText=function(k) return k end
GetInventoryItemID=function() return nil end GetWeaponEnchantInfo=function() return false end
COUNTS={} NAMES={}
GetItemInfo=function(id) return NAMES[id] end GetItemIcon=function() return 1 end GetItemCount=function(id) return COUNTS[id] or 0 end
ITEM_QUALITY_COLORS={} PlaySound=noop IsAltKeyDown=noop IsControlKeyDown=noop IsShiftKeyDown=noop GetCursorInfo=noop ClearCursor=noop
GetNumLootItems=function() return 0 end
C_DateAndTime={GetCurrentCalendarTime=function() return {year=2026,month=9,monthDay=27,hour=12,minute=30,weekday=1} end}
C_Calendar={OpenCalendar=noop, GetMonthInfo=function() return {numDays=30,month=9,year=2026} end, GetNumDayEvents=function() return 0 end}
GetCameraZoom=function() return 8 end SaveView=noop SetView=noop GetCursorPosition=function() return 0,0 end
ReloadUI=noop HideUIPanel=noop
GetContainerNumSlots=function() return 0 end GetContainerItemID=noop GetContainerItemLink=noop GetContainerItemInfo=noop
GetGameTime=function() return 12,0 end
GetBuildInfo=function() return "1.16.0","16001","Sep 1 2026",11601 end
GetLocale=function() return "enUS" end GetRealmName=function() return "Beta" end UnitClass=function() return "Druid","DRUID" end UnitRace=function() return "Tauren","Tauren" end GetMoney=function() return 0 end
-- addon list
local ADDONS={"ForeverArtisan_Core","ForeverArtisan_Contacts","ForeverArtisan_Fishing","ForeverArtisan_Cooking","ForeverArtisan_Herbalism","ForeverArtisan_Mining","ForeverArtisan_Skinning","ForeverArtisan_FirstAid","ForeverArtisan_Alchemy","ForeverArtisan_Leatherworking","ForeverArtisan_Blacksmithing","ForeverArtisan_Tailoring","ForeverArtisan_Engineering","ForeverArtisan_Enchanting"}
local META={}
C_AddOns={GetNumAddOns=function() return #ADDONS end,
  GetAddOnInfo=function(i) local n=type(i)=="number" and ADDONS[i] or i; return n, "ForeverArtisan: "..n:gsub("ForeverArtisan_",""), "notes", true, nil end,
  IsAddOnLoaded=function() return true end, GetAddOnMetadata=function(n,f) return META[n] and META[n][f] end,
  EnableAddOn=noop, DisableAddOn=noop, GetAddOnEnableState=function() return 2 end}
-- Old SavedVariables present -> migration test
MatsledgerSettings={tooltips=false, minimapAngle=200}
MatsFishDB={settings={key="SPACE"}, zones={}, goals={{id=8365,want=7}}}
ForeverArtisanLoggerDB={entries={
 ["vendor:2394"]={kind="vendor",name="Mallen Swain",title="Tailoring Supplies",zone="Hillsbrad Foothills",subzone="Tarren Mill",mapID=1424,x=62.1,y=19.5,lastSeen=1790000000,
   items={{name="Silken Thread",itemId=4291,priceCopper=500},{name="Pattern: Red Woolen Bag",itemId=5772,priceCopper=500,limited=1,requires={"Requires Tailoring (115)"}}}},
 ["trainer:3363"]={kind="trainer",name="Magar",title="Tailoring Trainer",zone="Orgrimmar",mapID=1454,x=63,y=51,skills={{name="Bolt of Silk Cloth",priceCopper=1000,skillReq="Tailoring 125"}}},
 ["service:1"]={kind="service",name="Banker Bob",service="banker"}}}
ForeverArtisanHerbDB={settings={}, zones={}, goals={}}
setmetatable(_G,{__index=function(_,k) if type(k)=="string" and (k:match("^C_") or k:match("^Enum") or k=="SOUNDKIT" or k=="Settings" or k=="TooltipDataProcessor") then return nil end return nil end})
local loadedFrames={}
for _,a in ipairs(ADDONS) do
  local toc=io.open(ROOT.."/"..a.."/"..a..".toc"):read("*a")
  META[a]={}
  for k,v in toc:gmatch("## ([%w%-]+): ([^\n]*)") do META[a][k]=v end
  local ns={}
  local first=#frames
  for line in toc:gmatch("[^\n]+") do
    if line:match("%.lua$") then
      local fn=assert(loadfile(ROOT.."/"..a.."/"..line))
      local ok,err=pcall(fn,a,ns); if not ok then print("LOAD ERROR",a,line,err) os.exit(1) end
    end
  end
  loadedFrames[a]={first=first+1,last=#frames,ns=ns}
end
local function fire(ev,...) for _,f in ipairs(frames) do local h=f.scripts.OnEvent if h then local ok,err=pcall(h,f,ev,...) if not ok then print("EVENT ERROR",ev,err) os.exit(1) end end end end
for _,a in ipairs(ADDONS) do fire("ADDON_LOADED",a) end
fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false)
print("MIGRATE settings", ForeverArtisanSettings and ForeverArtisanSettings.tooltips, MatsledgerSettings)
print("MIGRATE fish", ForeverArtisanFishingDB and ForeverArtisanFishingDB.settings.key, MatsFishDB, #ForeverArtisanFishingDB.goals)
print("MIGRATE contacts", ForeverArtisanContactsDB and ForeverArtisanContactsDB.entries["vendor:2394"] ~= nil, ForeverArtisanLoggerDB)
print("MIGRATE herb", ForeverArtisanHerbalismDB ~= nil, ForeverArtisanHerbDB)
local function run(cmd, arg)
  local ok,err=pcall(SlashCmdList[cmd], arg or "")
  if not ok then print("SLASH ERROR",cmd,arg,err) os.exit(1) end
end
for k in pairs(SlashCmdList) do io.write(k," ") end print()
run("FOREVERARTISAN",""); run("FOREVERARTISAN","help"); run("FOREVERARTISAN","silk"); run("FASEARCH","tailoring")
local cns=loadedFrames["ForeverArtisan_Contacts"].ns
local r=cns.Search("silk"); print("SEARCH silk", #r, r[1] and (r[1].item and r[1].item.n or r[1].npc.n))
r=cns.Search("tailoring"); print("SEARCH tailoring", #r)
local h=ForeverArtisan.Vendors.hitsForLink(nil,"Pattern: Red Woolen Bag"); print("HITS", #h, h[1] and h[1].npc.n, h[1] and h[1].item.lim, h[1] and h[1].item.sk)
print("CONTACTS", #cns.Contacts())
-- freshness: three builds, contacts seen on each
local db=ForeverArtisanContactsDB
db.builds={"15000","15500","16001"}
db.entries["vendor:2394"].build="15000"   -- 2 updates ago -> hidden
db.entries["trainer:3363"].build="15500"  -- 1 update ago -> marked
cns.OnContactsChanged()
local r2=cns.Search("silk"); print("FRESH search silk", #r2, r2[1] and r2[1].npc.n, r2[1] and r2[1].npc.age)
print("FRESH hits pattern", #ForeverArtisan.Vendors.hitsForLink(nil,"Pattern: Red Woolen Bag"))
for _,n in ipairs(cns.Contacts()) do print("AGE", n.n, n.age, cns.AgeNote(n)) end
-- passing by refreshes
UnitExists=function() return true end UnitIsPlayer=function() return false end UnitReaction=function() return 5 end
UnitGUID=function() return "Creature-0-0-0-0-2394-0" end CheckInteractDistance=function() return true end
C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .5,.5 end} end
cns.TouchContact(2394,"target")
for _,n in ipairs(cns.Contacts()) do print("AFTER TOUCH", n.n, n.age, n.x, n.y, n.s) end
cns.Forget("trainer:3363"); print("AFTER FORGET", #cns.Contacts())
for _,alias in ipairs({"fish","cook","herb","mine","skin","aid","contacts","alch","lw","bs","tailor","eng","ench"}) do run("FOREVERARTISAN", alias.." help") end
-- open every module window and click every tab
local wins={ForeverArtisanFishingFrame="FAFISH",ForeverArtisanCookingFrame="FACOOK",ForeverArtisanHerbalismFrame="FAHERB",ForeverArtisanMiningFrame="FAMINING",ForeverArtisanSkinningFrame="FASKIN",ForeverArtisanFirstAidFrame="FAAID",ForeverArtisanContactsFrame="FACONTACTS",ForeverArtisanAlchemyFrame="FAALCH",ForeverArtisanLeatherworkingFrame="FALW",ForeverArtisanBlacksmithingFrame="FABS",ForeverArtisanTailoringFrame="FATAILOR",ForeverArtisanEngineeringFrame="FAENG",ForeverArtisanEnchantingFrame="FAENCH"}
for wname,cmd in pairs(wins) do
  local before=#frames
  run(cmd,"")
  local w=_G[wname]
  if not w then print("NO WINDOW",wname) os.exit(1) end
  print("WINDOW",wname,"title:",(w.title._text or ""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""), "shown", w._shown)
  for i=before+1,#frames do local b=frames[i]
    if b._text and b.scripts.OnClick and ({Progress=1,Fishing=1,["Catch log"]=1,["Cast marker"]=1,Herbalism=1,Mining=1,Skinning=1,Cooking=1,["Gather log"]=1,["Herb guide"]=1,["Mining log"]=1,["Node guide"]=1,["Skinning log"]=1,["Level guide"]=1,["Cook log"]=1,["Recipe book"]=1,["First Aid"]=1,["Craft log"]=1,Search=1,Contacts=1,["Limited stock"]=1,Alchemy=1,Leatherworking=1,Blacksmithing=1,Tailoring=1,Engineering=1,Enchanting=1})[b._text] then
      local ok,err=pcall(b.scripts.OnClick,b) if not ok then print("TAB ERROR",wname,b._text,err) os.exit(1) end
    end
  end
  if w.scripts.OnUpdate then local ok,err=pcall(w.scripts.OnUpdate,w,2) if not ok then print("UPDATE ERROR",wname,err) os.exit(1) end end
end
-- goals with bars + editable amounts in gathering modules
for _,a in ipairs({"ForeverArtisan_Herbalism","ForeverArtisan_Mining","ForeverArtisan_Skinning"}) do
  local ns=loadedFrames[a].ns
  ns.AddGoal(2447,20,"Peacebloom"); ns.SetGoalWant(1,35); ns.OnChange()
  print("GOAL",a,ns.DB().goals[1].want, ns.GoalRows()[1].want)
end
-- First Aid window scan
local RECIPES={[3275]={name="Linen Bandage",learned=true,maxTrivialLevel=50,relativeDifficulty=1,out=1251,reag={{2589,1}}},
 [3276]={name="Heavy Linen Bandage",learned=true,maxTrivialLevel=80,relativeDifficulty=0,out=2581,reag={{2589,2}}},
 [3277]={name="Wool Bandage",learned=false,maxTrivialLevel=115,relativeDifficulty=0,out=3530,reag={{2592,1}}}}
C_TradeSkillUI={GetAllRecipeIDs=function() local t={} for k in pairs(RECIPES) do t[#t+1]=k end return t end,
 GetRecipeInfo=function(id) local r=RECIPES[id] return {name=r.name,learned=r.learned,maxTrivialLevel=r.maxTrivialLevel,relativeDifficulty=r.relativeDifficulty} end,
 GetTradeSkillLineForRecipe=function() return 129,"First Aid",129 end,
 GetRecipeSchematic=function(id) local r=RECIPES[id] local sl={} for _,g in ipairs(r.reag) do sl[#sl+1]={reagents={{itemID=g[1]}},quantityRequired=g[2]} end return {outputItemID=r.out,reagentSlotSchematics=sl} end}
C_Timer={After=function(_,fn) fn() end}
fire("TRADE_SKILL_SHOW")
local aid=loadedFrames["ForeverArtisan_FirstAid"].ns
local now=aid.MakeNow(); print("MAKE NOW",#now, now[1] and now[1].r.name, now[1] and now[1].color)
local steps,shop,stuck,target=aid.Plan(100); print("PLAN to",target,#steps,"stuck",stuck)
for _,st in ipairs(steps) do print("  ",st.r.name,st.crafts,st.from,st.to) end
for _,e in ipairs(shop) do print("  shop",e.name,e.need,e.source) end
run("FAAID","next"); run("FAAID","plan 100"); run("FAAID","")
run("FAAID","") ; run("FAAID","")
for i=1,#frames do local b=frames[i] if b._text and b.scripts.OnClick and ({Progress=1,["Craft log"]=1,["Recipe book"]=1})[b._text] then pcall(b.scripts.OnClick,b) end end
print("ADVICE", aid.SkillInfo().advice)
aid.OnChange()
local fishns=loadedFrames["ForeverArtisan_Fishing"].ns
fishns.DB().zones = {x={items={[6308]={name="Raw Bristle Whisker Catfish"}}}}
ForeverArtisanCookingDB.chars = {["Tester-Beta"]={skill=163,recipes={["Bristle Whisker Catfish"]={name="Bristle Whisker Catfish",learned=true,grayAt=180,reagents={{id=6308,n=1,name="Raw Bristle Whisker Catfish"}}}}}}
local list,rank,why=fishns.CookingSuggestions(); print("FISH SUGGEST",#list,rank,why,list[1] and list[1].name,list[1] and list[1].want)

-- ===== Alchemy + Leatherworking =====
local alch=loadedFrames["ForeverArtisan_Alchemy"].ns
local lw=loadedFrames["ForeverArtisan_Leatherworking"].ns
-- the First Aid window above must not be read by the new modules
print("FOREIGN WINDOW alch", alch.HasRecipes(), "lw", lw.HasRecipes())
assert(not alch.HasRecipes() and not lw.HasRecipes(), "new modules read the First Aid window")
local counts=COUNTS
NAMES[783]="Light Hide" NAMES[4289]="Salt" NAMES[4231]="Cured Light Hide" NAMES[2318]="Light Leather" NAMES[2319]="Medium Leather"
NAMES[2320]="Coarse Thread" NAMES[2321]="Fine Thread" NAMES[785]="Mageroyal" NAMES[2449]="Earthroot" NAMES[3371]="Empty Vial" NAMES[118]="Minor Healing Potion"
C_Item={GetItemInfoInstant=function(id) if id==2449 or id==785 then return id,"Herb","Herb","",1,7,9 end return id,"x","x","",1,7,0 end}
-- Leatherworking window: Cured Light Hide = Light Hide + Salt; Hillman's Shoulders uses 2 Cured Light Hide
local LW={[3816]={name="Cured Light Hide",learned=true,maxTrivialLevel=55,relativeDifficulty=0,out=4231,reag={{783,1},{4289,1}}},
 [3761]={name="Fine Leather Tunic",learned=true,maxTrivialLevel=115,relativeDifficulty=0,out=4243,reag={{2318,6},{2320,2}}},
 [3768]={name="Hillman's Shoulders",learned=true,maxTrivialLevel=130,relativeDifficulty=0,out=4251,reag={{4231,2},{2319,4},{2321,1}}},
 [3777]={name="Guardian Leather Bracers",learned=false,maxTrivialLevel=215,relativeDifficulty=0,out=5964,reag={{4234,6}}}}
C_TradeSkillUI={GetAllRecipeIDs=function() local t={} for k in pairs(LW) do t[#t+1]=k end return t end,
 GetRecipeInfo=function(id) local r=LW[id] return {name=r.name,learned=r.learned,maxTrivialLevel=r.maxTrivialLevel,relativeDifficulty=r.relativeDifficulty} end,
 GetTradeSkillLineForRecipe=function() return 165,"Leatherworking",165 end,
 GetRecipeSchematic=function(id) local r=LW[id] local sl={} for _,g in ipairs(r.reag) do sl[#sl+1]={reagents={{itemID=g[1]}},quantityRequired=g[2]} end return {outputItemID=r.out,reagentSlotSchematics=sl,quantityMin=1} end}
ForeverArtisanSkinningDB.zones={z={zone="The Barrens",sub="The Crossroads",items={[783]={n=40}}}}
counts[4231]=1  -- one Cured Light Hide in bags already
local baseProf=GetProfessionInfo
GetProfessionInfo=function(i) if i==8 then return "Leatherworking",1,100,150,0,0,165,0 end return baseProf(i) end
fire("TRADE_SKILL_SHOW")
print("LW read", lw.HasRecipes(), "alch", alch.HasRecipes())
assert(lw.HasRecipes() and not alch.HasRecipes())
local st,sh,stk,tg=lw.Plan(140)
print("LW PLAN to",tg,"steps",#st,"stuck",stk)
for _,x in ipairs(st) do print("   step",x.r.name,x.crafts,x.from,x.to) end
local cured,hide
for _,e in ipairs(sh) do print("   shop",e.name,e.need,e.have,e.craft,e.source) if e.id==4231 then cured=e end if e.id==783 then hide=e end end
assert(cured and cured.craft, "cured hide should be a sub-craft")
local hillCrafts=0 for _,x in ipairs(st) do if x.r.name=="Hillman's Shoulders" then hillCrafts=hillCrafts+x.crafts end end
local directCured=0 for _,x in ipairs(st) do if x.r.name=="Cured Light Hide" then directCured=directCured+x.crafts end end
assert(cured.need==hillCrafts*2, "cured need")
assert(cured.craft+directCured==cured.need-1, "craft only the shortfall (direct crafts count toward it)")
assert(hide and hide.need==cured.craft+directCured, "light hide = sub-crafts + direct cured crafts")
assert(hide.source:find("Crossroads") and hide.source:find("Skinning log"), "light hide should point to Skinning log")
run("FALW","plan 140"); run("FALW","next"); run("FALW","")
print("LW ADVICE", lw.SkillInfo().advice)
-- a trainer you met wins over the Classic answer
ForeverArtisanContactsDB.entries["trainer:9000"]={kind="trainer",name="Una",title="Leatherworking Trainer",zone="Thunder Bluff",mapID=1456,x=40,y=60,
  skills={{name="Leatherworking",rank="Artisan",skillReq="Leatherworking 200",levelReq=35}}}
loadedFrames["ForeverArtisan_Contacts"].ns.OnContactsChanged()
GetProfessionInfo=function(i) if i==8 then return "Leatherworking",1,225,225,0,0,165,0 end return baseProf(i) end
local inf=lw.SkillInfo(); print("LW CAPPED", inf.capped, inf.advice)
assert(inf.capped and inf.advice:find("Una") and inf.advice:find("Trade Contacts"), "trainer from contacts")
GetProfessionInfo=baseProf
-- Alchemy window: transmute must be skipped by the plan; herb points to Herbalism log
local AL={[2330]={name="Minor Healing Potion",learned=true,maxTrivialLevel=55,relativeDifficulty=0,out=118,reag={{2447,1},{765,1},{3371,1}}},
 [2337]={name="Lesser Healing Potion",learned=true,maxTrivialLevel=165,relativeDifficulty=0,out=858,reag={{118,1},{2450,1}}},
 [3452]={name="Elixir of Wisdom",learned=true,maxTrivialLevel=170,relativeDifficulty=0,out=3383,reag={{785,1},{2449,2},{3371,1}}},
 [11479]={name="Transmute: Iron to Gold",learned=true,maxTrivialLevel=240,relativeDifficulty=0,out=3577,reag={{3575,1}}}}
C_TradeSkillUI={GetAllRecipeIDs=function() local t={} for k in pairs(AL) do t[#t+1]=k end return t end,
 GetRecipeInfo=function(id) local r=AL[id] return {name=r.name,learned=r.learned,maxTrivialLevel=r.maxTrivialLevel,relativeDifficulty=r.relativeDifficulty} end,
 GetTradeSkillLineForRecipe=function() return 171,"Alchemy",171 end,
 GetRecipeSchematic=function(id) local r=AL[id] local sl={} for _,g in ipairs(r.reag) do sl[#sl+1]={reagents={{itemID=g[1]}},quantityRequired=g[2]} end return {outputItemID=r.out,reagentSlotSchematics=sl} end}
ForeverArtisanHerbalismDB.zones={a={zone="Mulgore",sub="Red Rocks",items={[785]={hauls=12}}}}
fire("TRADE_SKILL_SHOW")
local lwCount=0 for _ in pairs(lw.CharRec().recipes) do lwCount=lwCount+1 end
print("ALCH read", alch.HasRecipes(), "LW still", lwCount)
assert(alch.HasRecipes() and lwCount==4, "alchemy scan must not touch leatherworking")
local ast,ash=alch.Plan(180)
for _,x in ipairs(ast) do print("   step",x.r.name,x.crafts,x.from,x.to) assert(not x.r.name:find("^Transmute"), "transmute in plan") end
local mage,earth
for _,e in ipairs(ash) do print("   shop",e.name,e.need,e.have,e.craft,e.source) if e.id==785 then mage=e end if e.id==2449 then earth=e end end
assert(mage.source:find("Red Rocks") and mage.source:find("Herbalism log"), "mageroyal from herb log")
assert(earth.source:find("not in your Herbalism log"), "earthroot not logged yet")
-- Lesser Healing Potion uses Minor Healing Potion: made, not bought
local minor for _,e in ipairs(ash) do if e.id==118 then minor=e end end
print("   minor potion craft", minor and minor.craft)
local now=alch.MakeNow() for _,e in ipairs(now) do assert(not e.r.name:find("^Transmute")) end
run("FAALCH","plan 180"); run("FAALCH","next"); run("FAALCH","tooltips"); run("FAALCH","tooltips"); run("FAALCH","")
for i=1,#frames do local b=frames[i] if b._text and b.scripts.OnClick and ({Progress=1,["Craft log"]=1,["Recipe book"]=1})[b._text] then local ok,err=pcall(b.scripts.OnClick,b) if not ok then print("TAB ERROR",err) os.exit(1) end end end
alch.OnChange(); lw.OnChange()
-- crafting logs
fire("UNIT_SPELLCAST_SUCCEEDED","player",nil,2330); fire("CHAT_MSG_SKILL","Your skill in Alchemy has increased to 151.")
print("ALCH session", alch.SessionInfo().crafts, alch.SessionInfo().ups, alch.CharRec().skill)
assert(alch.SessionInfo().crafts==1 and alch.SessionInfo().ups==1)
assert(lw.SessionInfo().ups==0, "alchemy skill-up counted in leatherworking")
-- regression: First Aid learned, Cooking not (GetProfessions returns nil for the cooking slot)
GetProfessions=function() return 1,2,nil,4,nil,6 end
local realName=UnitName; UnitName=function() return "Fresh" end  -- new character: nothing saved yet
local aidInfo=aid.SkillInfo(); print("AID WITHOUT COOKING", aidInfo.rank)
assert(aidInfo.rank, "First Aid not found when Cooking is missing")
UnitName=realName
GetProfessions=function() return 1,2,3,4,5,6,7,8 end
-- Trade Contacts search: status words, one row per trainer, seen-only NPCs
do
  local db=ForeverArtisanContactsDB
  db.entries["trainer:777"]={kind="trainer",npcId=777,name="Chaw Stronghide",title="Journeyman Leatherworker",zone="Mulgore",subzone="Bloodhoof Village",mapID=1412,x=45,y=61.5,
    skills={{name="Camp Tent",rank="unavailable",skillReq="Leatherworking 30"},{name="Cured Light Hide",rank="available",skillReq="Leatherworking 35"},
            {name="Journeyman Leatherworking",rank="available",skillReq="Leatherworking 50"}}}
  db.scouted=db.scouted or {}
  db.scouted[888]={name="Carolai Anise",title="Journeyman Alchemist",zone="Tirisfal Glades",subzone="Brill",mapID=1420,x=59.6,y=52.1,relevant=true,lastSeen=1}
  db.scouted[889]={name="Tavern Keeper",title="Innkeeper",zone="Tirisfal Glades",subzone="Salty Tavern",relevant=nil}
  local cns3=loadedFrames["ForeverArtisan_Contacts"].ns
  cns3.OnContactsChanged()
  local r=cns3.Search("leatherworking")
  local rows, trains, status = 0, nil, false
  for _,h in ipairs(r) do
    if h.npc.n=="Chaw Stronghide" then rows=rows+1; if h.trains then trains=h.trains end end
    if h.item and h.item.n:find("available") then status=true end
  end
  local ranks
  for _,h in ipairs(r) do if h.npc.n=="Chaw Stronghide" then ranks=h.ranks end end
  print("SEARCH GROUPED", rows, trains, status, ranks and #ranks)
  assert(trains==2, "trainer recipes should collapse into one row")
  assert(rows==1, "one row per trainer, rank rows folded in")
  assert(ranks and #ranks==1, "Journeyman Leatherworking folded into the trainer row")
  assert(not status, "status words must not show as ranks")
  local a=cns3.Search("alchemy"); local seen=false
  for _,h in ipairs(a) do if h.seen and h.npc.n=="Carolai Anise" then seen=true end end
  print("SEARCH SEEN", seen)
  assert(seen, "seen-only alchemist should be found by 'alchemy'")
  for _,h in ipairs(cns3.Search("salty")) do assert(not h.seen, "seen-only NPCs match on name/title only") end
  -- nearest first across zones: you're in Brill (Tirisfal), Chaw is on another continent
  CreateVector2D=function(x,y) return {x=x,y=y} end
  local oldWorld=C_Map.GetWorldPosFromMapPos
  C_Map.GetWorldPosFromMapPos=function(m,v) local c=({[1420]=0,[1412]=1})[m]; if c==nil then return nil end return c,{x=v.x*1000,y=v.y*1000} end
  C_Map.GetBestMapForUnit=function() return 1420 end
  C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .618,.528 end} end
  local j=cns3.Search("journeyman")
  print("SEARCH NEAREST", j[1] and j[1].npc.n)
  assert(j[1] and j[1].npc.n=="Carolai Anise", "closest NPC should come first even if only seen")
  C_Map.GetWorldPosFromMapPos=oldWorld
end
-- where to learn: an Expert-only trainer is skipped, the Apprentice one is named
do
  local db=ForeverArtisanContactsDB
  db.entries["trainer:901"]={kind="trainer",npcId=901,name="Brawn",title="Expert Leatherworker",zone="Stranglethorn Vale",subzone="Grom'gol Base Camp",mapID=1434,x=31.6,y=28.8,
    skills={{name="Expert Leatherworking",skillReq="Leatherworking 125"}}}
  db.entries["trainer:777"].skills[#db.entries["trainer:777"].skills+1]={name="Apprentice Leatherworking",rank="available"}
  loadedFrames["ForeverArtisan_Contacts"].ns.OnContactsChanged()
  local who=lw.LearnFrom()
  print("LEARN FROM", who and who.n)
  assert(who and who.n=="Chaw Stronghide", "should name the trainer who teaches Apprentice, not Brawn")
  -- no Apprentice alchemy trainer on file: falls back to the closest alchemy trainer you passed
  local a=alch.LearnFrom()
  assert(a and a.n=="Carolai Anise" and a.seenOnly, "falls back to a seen alchemy trainer")
  -- talked to, but only the chat window opened: a contact, not "seen"
  db.entries["service:902"]={kind="service",npcId=902,name="Brawn Two",title="Expert Leatherworker",zone="Stranglethorn Vale",subzone="Grom'gol Base Camp",mapID=1434,x=31.6,y=28.8,service="expert leatherworker"}
  db.scouted[902]={name="Brawn Two",title="Expert Leatherworker",zone="Stranglethorn Vale",subzone="Grom'gol Base Camp",mapID=1434,x=31.6,y=28.8,relevant=true}
  loadedFrames["ForeverArtisan_Contacts"].ns.OnContactsChanged()
  local cn=loadedFrames["ForeverArtisan_Contacts"].ns
  local found
  for _,h in ipairs(cn.Search("leatherworker")) do if h.npc.n=="Brawn Two" then found=h end end
  print("CHAT-ONLY CONTACT", found and found.npc.k, found and found.seen)
  assert(found and found.npc.k=="service" and not found.seen, "chat-only visit should be a contact")
  local un=cn.Unvisited(); local hasBrawn=false
  for _,h in ipairs(un) do if h.npc.n=="Brawn Two" then hasBrawn=true end end
  assert(not hasBrawn, "a visited NPC is not in Only not visited")
  print("UNVISITED", #un)
  cn.SetScout(false); assert(not cn.ScoutOn()); cn.SetScout(true); assert(cn.ScoutOn())
end
-- Contacts tab: grouped by town, Zone and Trade pickers
do
  local cn=loadedFrames["ForeverArtisan_Contacts"].ns
  local db=ForeverArtisanContactsDB
  db.entries["vendor:903"]={kind="vendor",npcId=903,name="Innkeeper Test",title="Innkeeper",zone="Stranglethorn Vale",subzone="Grom'gol Base Camp",mapID=1434,x=31,y=28,items={}}
  cn.OnContactsChanged()
  local function tab(name) for _,b in ipairs(frames) do if b._text==name and b.scripts.OnClick then b.scripts.OnClick(b) end end end
  local function visible()
    local out={}
    for _,r in ipairs(cn.Pages.contacts.rows) do if r.data and r._shown then out[#out+1]=(r.data.header and "H:" or "")..(r.left._text or ""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","") end end
    return out
  end
  local set=db.settings
  set.listZone, set.listTrade = "all", "crafting"
  ForeverArtisanContactsFrame:Show()
  tab("Contacts")
  local v=visible(); local inn=false, false
  for _,t in ipairs(v) do if t:find("Innkeeper Test") then inn=true end end
  assert(not inn, "innkeepers hidden under All crafting")
  set.listTrade="Leatherworking"; cn.OnChange(); v=visible()
  local heads, lw, other = 0, 0, 0
  for _,t in ipairs(v) do if t:find("^H:") then heads=heads+1 elseif t:find("Leatherwork") then lw=lw+1 else other=other+1 end end
  print("CONTACTS LW", heads, lw, other, table.concat(v," ; "))
  assert(heads>0 and lw>0 and other==0, "Leatherworking filter shows only leatherworkers, under town headers")
  set.listTrade="all"; set.listZone="Stranglethorn Vale"; cn.OnChange(); v=visible()
  inn=false; for _,t in ipairs(v) do if t:find("Innkeeper Test") then inn=true end end
  assert(inn, "Everyone + zone shows the innkeeper")
  for _,r in ipairs(cn.Pages.contacts.rows) do if r.data and r.data.header and r._shown then r.scripts.OnClick(r,"LeftButton") break end end
  v=visible(); print("FOLDED", #v, v[1]); assert(#v==1 and v[1]:find("^H:%+"), "clicking a town folds it")
  -- both pickers open, list their choices, and only one menu is open at a time
  local pg=cn.Pages.contacts
  pg.zonePick.scripts.OnClick(pg.zonePick); pg.tradePick.scripts.OnClick(pg.tradePick)
  assert(pg.tradePick.menu._shown and not pg.zonePick.menu._shown, "one picker menu at a time")
  local tn=0 for _,it in ipairs(pg.tradePick.menu.items) do if it._shown then tn=tn+1 end end
  print("TRADE CHOICES", tn, pg.tradePick._text); assert(tn>=3)
  set.listZone, set.listTrade = nil, nil
end
-- Fishing: skill and gear are per character (an alt without Fishing must not show the main's skill or pole)
do
  local fns=loadedFrames["ForeverArtisan_Fishing"].ns
  local main=fns.SkillInfo()
  print("FISH MAIN", main.rank, main.notLearned)
  assert(main.rank, "main reads its fishing skill")
  fns.SetGear("pole", 6256)
  assert(select(3, fns.GearSet())==6256, "main keeps its pole")
  local oldName, oldProf = UnitName, GetProfessions
  UnitName=function() return "Alt" end
  GetProfessions=function() return 7,nil,nil,nil,5,6 end
  local alt=fns.SkillInfo()
  print("FISH ALT", alt.rank, alt.notLearned, select(3, fns.GearSet()))
  assert(alt.rank==nil and alt.notLearned, "alt without Fishing shows not learned")
  assert(select(3, fns.GearSet())==nil, "alt doesn't get the main's pole")
  UnitName, GetProfessions = oldName, oldProf
  assert(fns.SkillInfo().rank and select(3, fns.GearSet())==6256, "back on the main, all still there")
  -- old account-wide pole: a character takes it over once its bags are readable
  ForeverArtisanFishingDB.settings.pole=6256
  UnitName=function() return "Old" end
  assert(select(3, fns.GearSet())==nil, "bags not loaded yet: no pole")
  COUNTS[6256]=1
  assert(select(3, fns.GearSet())==6256, "adopts the old pole once it has one")
  COUNTS[6256]=nil
  UnitName=oldName
  -- the Fishing tab renders the not-learned line without errors
  UnitName=function() return "Alt" end GetProfessions=function() return 7,nil,nil,nil,5,6 end
  run("FAFISH",""); run("FAFISH","")
  UnitName, GetProfessions = oldName, oldProf
end
-- Plan: materials you craft (Light Leather from scraps) give skill-ups too, so fewer vests are needed
do
  local function lwWindow(leatherLearned)
    local R={[2881]={name="Light Leather",learned=leatherLearned,maxTrivialLevel=40,relativeDifficulty=0,out=2318,reag={{2934,3}}},
     [3753]={name="Handstitched Leather Vest",learned=true,maxTrivialLevel=75,relativeDifficulty=0,out=5957,reag={{2318,3},{2320,1}}},
     [9058]={name="Handstitched Leather Cloak",learned=true,maxTrivialLevel=75,relativeDifficulty=0,out=5961,reag={{2318,2},{2320,1}}}}
    C_TradeSkillUI={GetAllRecipeIDs=function() local t={} for k in pairs(R) do t[#t+1]=k end return t end,
     GetRecipeInfo=function(id) local r=R[id] return {name=r.name,learned=r.learned,maxTrivialLevel=r.maxTrivialLevel,relativeDifficulty=r.relativeDifficulty} end,
     GetTradeSkillLineForRecipe=function() return 165,"Leatherworking",165 end,
     GetRecipeSchematic=function(id) local r=R[id] local sl={} for _,g in ipairs(r.reag) do sl[#sl+1]={reagents={{itemID=g[1]}},quantityRequired=g[2]} end return {outputItemID=r.out,reagentSlotSchematics=sl,quantityMin=1} end}
    wipe(lw.CharRec().recipes) -- only these two recipes
    fire("TRADE_SKILL_SHOW")
  end
  local baseProf2=GetProfessionInfo
  GetProfessionInfo=function(i) if i==8 then return "Leatherworking",1,30,75,0,0,165,0 end return baseProf2(i) end
  local function vests(st) local n,sub=0,0 for _,x in ipairs(st) do if x.r.name~="Light Leather" then n=n+x.crafts for _,k in pairs(x.sub) do sub=sub+k end end end return n,sub end
  lwWindow(false)
  local bought=vests((lw.Plan(60)))
  lwWindow(true)
  local st,sh=lw.Plan(60)
  local made,sub=vests(st)
  local leather for _,e in ipairs(sh) do if e.id==2318 then leather=e end end
  print("PLAN SUBSKILL vests bought-leather", bought, "made-leather", made, "leather made along the way", sub, leather and leather.craft)
  assert(sub>0 and leather and leather.craft==sub, "Light Leather made along the way")
  assert(made<bought, "leather crafts should count toward skill, so fewer vests")
  local names={} for _,x in ipairs(st) do names[#names+1]=x.r.name end
  print("PLAN PICKS", table.concat(names,", "))
  assert(not table.concat(names,","):find("Vest"), "same skill-up chance: the cloak uses less leather than the vest")
  GetProfessionInfo=baseProf2
end
-- unlearning a profession: the saved skill must not keep it "learned"
do
  local hns=loadedFrames["ForeverArtisan_Herbalism"].ns
  local cns2=loadedFrames["ForeverArtisan_Cooking"].ns
  assert(hns.Skill() and cns2.Skill(), "learned at first")
  local oldProf=GetProfessions
  GetProfessions=function() return nil,2,nil,4,nil,6 end -- Herbalism and Cooking dropped
  print("UNLEARNED", hns.Skill(), hns.Knows(), cns2.Skill())
  assert(hns.Skill()==nil and not hns.Knows(), "herbalism unlearned")
  assert(cns2.Skill()==nil, "cooking unlearned")
  GetProfessions=oldProf
  assert(hns.Skill(), "relearned shows again")
end
-- one-button fishing: reel-in key = fishing key turns on "same key reels in"
do
  local fns=loadedFrames["ForeverArtisan_Fishing"].ns
  local st=ForeverArtisanFishingDB.settings
  fns.SetKey("key","F"); st.reelSameKey=false
  fns.SetKey("reelKey","F")
  assert(st.key=="F" and st.reelKey=="" and st.reelSameKey==true, "same key turns on one-button fishing")
  fns.SetKey("reelKey","")
  assert(st.reelSameKey==false and st.key=="F", "Clear on reel-in turns it off, fishing key kept")
  st.reelSameKey=true
end
-- the four new crafting modules: Tailoring makes its own bolts, Blacksmithing points ore to the Mining log,
-- Enchanting reads the old Craft window (Classic) and logs casts
do
  local tl=loadedFrames["ForeverArtisan_Tailoring"].ns
  local bs=loadedFrames["ForeverArtisan_Blacksmithing"].ns
  local en=loadedFrames["ForeverArtisan_Enchanting"].ns
  local eg=loadedFrames["ForeverArtisan_Engineering"].ns
  assert(not tl.Knows() and not bs.Knows() and not en.Knows() and not eg.Knows(), "not learned on this character")
  local baseProf3=GetProfessionInfo
  local extra={[9]={"Tailoring",197},[10]={"Blacksmithing",164},[11]={"Enchanting",333},[12]={"Engineering",202}}
  local oldProfs=GetProfessions
  GetProfessions=function() return 1,2,3,4,5,6,7,8,9,10,11,12 end
  GetProfessionInfo=function(i) local e=extra[i] if e then return e[1],1,60,75,0,0,e[2],0 end return baseProf3(i) end
  -- Tailoring: Bolt of Linen Cloth is crafted for the Linen Bag
  local TR={[2963]={name="Bolt of Linen Cloth",learned=true,maxTrivialLevel=75,relativeDifficulty=0,out=2996,reag={{2589,2}}},
   [3755]={name="Linen Bag",learned=true,maxTrivialLevel=95,relativeDifficulty=0,out=4238,reag={{2996,3},{2320,3}}}}
  local function window(R,line,name,tools)
    C_TradeSkillUI={GetRecipeTools=tools,GetAllRecipeIDs=function() local t={} for k in pairs(R) do t[#t+1]=k end return t end,
     GetRecipeInfo=function(id) local r=R[id] return {name=r.name,learned=r.learned,maxTrivialLevel=r.maxTrivialLevel,relativeDifficulty=r.relativeDifficulty} end,
     GetTradeSkillLineForRecipe=function() return line,name,line end,
     GetRecipeSchematic=function(id) local r=R[id] local sl={} for _,g in ipairs(r.reag) do sl[#sl+1]={reagents={{itemID=g[1]}},quantityRequired=g[2]} end return {outputItemID=r.out,reagentSlotSchematics=sl,quantityMin=1} end}
    fire("TRADE_SKILL_SHOW")
  end
  window(TR,197,"Tailoring")
  assert(tl.HasRecipes() and not bs.HasRecipes(), "tailoring read only by tailoring")
  local st,sh=tl.Plan(80)
  local bolt for _,e in ipairs(sh) do if e.id==2996 then bolt=e end end
  print("TAILOR PLAN", #st, bolt and bolt.need, bolt and bolt.craft)
  assert(bolt and bolt.craft, "bolts are crafted, not bought")
  -- Blacksmithing: copper bars and rough stone; ore and stone sources
  NAMES[2770]="Copper Ore"; NAMES[2835]="Rough Stone"; NAMES[2840]="Copper Bar"
  local BR={[2660]={name="Rough Sharpening Stone",learned=true,maxTrivialLevel=65,relativeDifficulty=0,out=2862,reag={{2835,1}}},
   [2663]={name="Copper Bracers",learned=true,maxTrivialLevel=80,relativeDifficulty=0,out=2853,reag={{2840,2}}}}
  window(BR,164,"Blacksmithing",function(id) if id==2663 then return "|cffff2020Blacksmith Hammer|r, Anvil" end end)
  assert(bs.HasRecipes(), "blacksmithing read")
  -- tools: the hammer isn't in the bags, so Copper Bracers says what it needs, and the plan lists the hammer
  COUNTS[2840]=10
  local now=bs.MakeNow() local brac for _,e in ipairs(now) do if e.r.name=="Copper Bracers" then brac=e end end
  print("TOOLS", brac and table.concat(brac.missing,","), brac and table.concat(brac.stations,","), brac and brac.make)
  assert(brac and brac.missing[1]=="Blacksmith Hammer" and brac.stations[1]=="Anvil" and brac.make==0, "missing hammer, made at anvil")
  local _,tsh=bs.Plan(80) local hammer for _,e in ipairs(tsh) do if e.tool then hammer=e end end
  assert(hammer and hammer.name=="Blacksmith Hammer" and hammer.have==0 and tsh[1]==hammer, "hammer first on the shopping list")
  COUNTS["Blacksmith Hammer"]=1
  now=bs.MakeNow() for _,e in ipairs(now) do if e.r.name=="Copper Bracers" then brac=e end end
  assert(#brac.missing==0 and brac.make==5, "with the hammer in bags it can be made")
  COUNTS["Blacksmith Hammer"]=nil COUNTS[2840]=nil
  -- newer windows: tools come from the recipe's requirements ("Requires: Runed Copper Rod")
  window(BR,164,"Blacksmithing")
  C_TradeSkillUI.GetRecipeRequirements=function(id) if id==2663 then return {{name="Blacksmith Hammer",met=false},{name="Anvil",met=true}} end return {} end
  fire("TRADE_SKILL_SHOW"); COUNTS[2840]=10
  now=bs.MakeNow() brac=nil for _,e in ipairs(now) do if e.r.name=="Copper Bracers" then brac=e end end
  print("TOOLS FROM REQUIREMENTS", brac and table.concat(brac.missing,","), brac and table.concat(brac.stations,","))
  assert(brac and brac.missing[1]=="Blacksmith Hammer" and brac.stations[1]=="Anvil", "tools read from requirements")
  COUNTS[2840]=nil
  run("FABS","next"); bs.OnChange()
  local _,bsh=bs.Plan(80)
  for _,e in ipairs(bsh) do print("   bs shop",e.name,e.need,e.source) end
  local bar,stone for _,e in ipairs(bsh) do if e.id==2840 then bar=e end if e.id==2835 then stone=e end end
  assert(bar and bar.source:find("smelt") , "bars: smelt ore")
  assert(stone and (stone.source:find("Stone") or stone.source:find("Mining")), "stone points to mining")
  -- Enchanting through the Classic Craft window
  C_TradeSkillUI=nil
  local CR={{"Enchanting","","header"},{"Enchant Bracer - Minor Health","","optimal",10},{"Runed Copper Rod","","easy",nil}}
  GetCraftDisplaySkillLine=function() return "Enchanting",60,75 end
  GetNumCrafts=function() return #CR end
  GetCraftInfo=function(i) local c=CR[i] return c[1],c[2],c[3] end
  GetCraftItemLink=function(i) if i==2 then return "|cffffffff|Henchant:7418|h[Enchant Bracer - Minor Health]|h|r" end return "|cffffffff|Hitem:6218|h[Runed Copper Rod]|h|r" end
  GetCraftNumReagents=function(i) return i==2 and 1 or 2 end
  GetCraftReagentInfo=function(i,j) if i==2 then return "Strange Dust",nil,1 end return (j==1 and "Copper Rod" or "Strange Dust"),nil,1 end
  GetCraftReagentItemLink=function(i,j) if i==2 or j==2 then return "|Hitem:10940|h" end return "|Hitem:6217|h" end
  GetCraftSpellFocus=function(i) if i==2 then return "Runed Copper Rod",nil end end
  NAMES[10940]="Strange Dust"
  fire("CRAFT_SHOW")
  print("ENCH read", en.HasRecipes(), "tailor still", tl.HasRecipes())
  assert(en.HasRecipes(), "enchanting read from the Craft window")
  local r=en.CharRec().recipes["Enchant Bracer - Minor Health"]
  assert(r and r.id==7418 and r.reagents[1].id==10940, "enchant spell id and dust read")
  assert(r.tools and r.tools[1].name=="Runed Copper Rod" and not r.tools[1].station, "rod read as a tool")
  local rodShop=select(2,en.Plan(70)) local rod for _,e in ipairs(rodShop) do if e.tool then rod=e end end
  print("ROD", rod and rod.source)
  assert(rod and rod.source:find("Made with Enchanting"), "rod source")
  local _,esh=en.Plan(70)
  local dust for _,e in ipairs(esh) do if e.id==10940 then dust=e end end
  print("ENCH dust", dust and dust.need, dust and dust.source)
  assert(dust and dust.source:find("Disenchant"), "dust comes from disenchanting")
  fire("UNIT_SPELLCAST_SUCCEEDED","player","guid",7418)
  assert(en.SessionInfo().crafts==1, "enchant cast logged")
  run("FAENCH","plan 70"); run("FAENCH","next"); run("FABS","plan 80"); run("FATAILOR","plan 80"); run("FAENG","")
  GetCraftDisplaySkillLine,GetNumCrafts,GetCraftInfo,GetCraftItemLink,GetCraftNumReagents,GetCraftReagentInfo,GetCraftReagentItemLink,GetCraftSpellFocus=nil
  GetProfessions,GetProfessionInfo=oldProfs,baseProf3
end
-- where to get a recipe you don't have: trainers and vendors you've met, drops you looted, quest rewards
do
  local FA=ForeverArtisan
  ForeverArtisanContactsDB.entries["trainer:9100"]={kind="trainer",npcId=9100,name="Magar",title="Tailoring Trainer",zone="Orgrimmar",mapID=1454,x=63,y=51,
    skills={{name="Bolt of Silk Cloth",priceCopper=1000,skillReq="Tailoring 125"}}}
  loadedFrames["ForeverArtisan_Contacts"].ns.OnContactsChanged()
  local lines,tag,npc,sk=FA.RecipeWhere("Bolt of Silk Cloth",{"Pattern: "})
  print("WHERE trainer", tag, npc and npc.n, sk, lines[1])
  assert(tag=="trainer" and npc and npc.n=="Magar" and lines[1]:find("Train: Magar"), "trainer you met")
  lines,tag,npc=FA.RecipeWhere("Red Woolen Bag",{"Pattern: "})
  print("WHERE vendor", tag, lines[1])
  assert(tag=="vendor" and lines[1]:find("Sold by: Mallen Swain") and lines[1]:find("limited"), "vendor you met")
  lines,tag=FA.RecipeWhere("Goretusk Liver Pie",{"Recipe: "})
  assert(tag==nil and lines[1]:find("Not found yet"), "unknown source")
  -- loot a recipe from the mob you're targeting
  local saved={GetNumLootItems,GetLootSlotLink,GetLootSourceInfo,UnitGUID,UnitName}
  GetNumLootItems=function() return 1 end
  GetLootSlotLink=function() return "|cffffffff|Hitem:2697|h[Recipe: Goretusk Liver Pie]|h|r" end
  GetLootSourceInfo=function() return "Creature-0-1-2-3-157-0000" end
  UnitGUID=function(u) if u=="target" then return "Creature-0-1-2-3-157-0000" end end
  UnitName=function(u) if u=="target" then return "Goretusk" end return "Tester" end
  fire("LOOT_OPENED")
  lines,tag=FA.RecipeWhere("Goretusk Liver Pie",{"Recipe: "})
  print("WHERE drop", tag, lines[1])
  assert(tag=="drop" and lines[1]:find("Dropped by Goretusk") and lines[1]:find("Desolace"), "drop you looted")
  -- a crafting material off a mob you didn't target: named from the combat log, counted by quantity
  -- you moused over it while fighting, then looted it without it being your target
  local oldExists,oldPlayer=UnitExists,UnitIsPlayer
  UnitExists=function(u) return u=="mouseover" end UnitIsPlayer=function() return false end
  UnitGUID=function(u) if u=="mouseover" then return "Creature-0-1-2-3-1513-0001" end end
  UnitName=function(u) if u=="mouseover" then return "Mangy Duskbat" end return "Tester" end
  fire("UPDATE_MOUSEOVER_UNIT")
  UnitExists,UnitIsPlayer=oldExists,oldPlayer
  UnitGUID=function() return nil end
  GetLootSlotLink=function() return "|cffffffff|Hitem:12223|h[Meaty Bat Wing]|h|r" end
  GetLootSourceInfo=function() return "Creature-0-1-2-3-1513-0001" end
  GetLootSlotInfo=function() return 0,"Meaty Bat Wing",2 end
  fire("LOOT_OPENED"); fire("LOOT_OPENED")
  local mw=FA.MaterialWhere(12223)
  print("MATERIAL", mw)
  assert(mw and mw:find("Dropped by Mangy Duskbat") and mw:find("2 times"), "material drop remembered")
  local ck=loadedFrames["ForeverArtisan_Cooking"].ns
  assert(ck.SourceFor(12223,"Meaty Bat Wing"):find("Mangy Duskbat"), "cooking shopping list names the mob")
  -- from a chest or herb node: not a mob drop
  GetLootSourceInfo=function() return "GameObject-0-1-2-3-999-0001" end
  GetLootSlotLink=function() return "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r" end
  fire("LOOT_OPENED")
  assert(FA.MaterialWhere(2589)==nil, "chest loot isn't a mob drop")
  GetLootSlotInfo=nil
  GetNumLootItems,GetLootSlotLink,GetLootSourceInfo,UnitGUID,UnitName=saved[1],saved[2],saved[3],saved[4],saved[5]
  -- a quest that rewards a recipe
  GetTitleText=function() return "Kaldorei Spider Kabob" end
  GetNumQuestRewards=function() return 1 end GetNumQuestChoices=function() return 0 end
  GetQuestItemLink=function() return "|Hitem:5482|h[Recipe: Kaldorei Spider Kabob]|h" end
  fire("QUEST_DETAIL")
  lines,tag=FA.RecipeWhere("Kaldorei Spider Kabob",{"Recipe: "})
  print("WHERE quest", tag, lines[1])
  assert(tag=="quest" and lines[1]:find("Quest reward: Kaldorei Spider Kabob"), "quest reward")
  GetTitleText,GetNumQuestRewards,GetNumQuestChoices,GetQuestItemLink=nil
  -- the Recipe book renders unlearned recipes with a source tag
  run("FATAILOR",""); run("FACOOK",""); run("FAAID","")
  loadedFrames["ForeverArtisan_Tailoring"].ns.OnChange(); loadedFrames["ForeverArtisan_Cooking"].ns.OnChange()
  for _,name in ipairs({"FACOOK","FATAILOR"}) do end
  for _,f in pairs(frames) do if f._text=="Recipe book" and f.scripts.OnClick then f.scripts.OnClick(f) end end
  local book=loadedFrames["ForeverArtisan_Cooking"].ns.lastBook
  if book then
    print("BOOK", book[1] and book[1].left, #book)
    assert(book[1].header and book[1].left:find("Learned"), "learned header first")
    local seenUnknown, order = false, true
    for _,d in ipairs(book) do
      if d.header and d.left:find("Not learned") then seenUnknown=true
      elseif d.recipe and seenUnknown and d.recipe.learned then order=false end
    end
    assert(order, "learned recipes come before unlearned ones")
    local cns=loadedFrames["ForeverArtisan_Cooking"].ns
    local function click(t) local n=0 for _,f in pairs(frames) do if type(f._text)=="string" and f._text:find(t) and f.scripts.OnClick then f.scripts.OnClick(f) n=n+1 end end return n>0 end
    assert(click("Not learned"), "Not learned button")
    _G.ForeverArtisanCookingFrame:Show(); cns.OnChange()
    print("BOOK AFTER", cns.lastBook[1] and cns.lastBook[1].left, #cns.lastBook)
    for _,d in ipairs(cns.lastBook) do assert(not (d.recipe and d.recipe.learned), "Not learned shows only unlearned") end
    _G.ForeverArtisanCookingFrame:Hide(); _G.ForeverArtisanCookingFrame:Show()
    local h=_G.ForeverArtisanCookingFrame.scripts.OnShow
    print("BOOK FILTER ok")
  end
end
-- welcome notice: shown once, "Got it" remembers it, /fa welcome brings it back
do
  local w=_G.ForeverArtisanWelcome
  assert(w and w._shown, "welcome shows on first login")
  for _,b in ipairs(frames) do if b._text=="Got it" and b.scripts.OnClick then b.scripts.OnClick(b) end end
  assert(not w._shown and ForeverArtisanSettings.welcomeSeen==1, "Got it closes and remembers")
  run("FOREVERARTISAN","welcome")
  assert(w._shown, "/fa welcome reopens it")
  for _,b in ipairs(frames) do if b._text=="Pick my professions" and b.scripts.OnClick then b.scripts.OnClick(b) end end
  assert(not w._shown and _G.ForeverArtisanPanel and _G.ForeverArtisanPanel._shown, "opens the module panel")
end
-- class trainers: saved and searchable, kept out of the crafting lists, own class only in "not visited"
do
  local db=ForeverArtisanContactsDB
  local cns=loadedFrames["ForeverArtisan_Contacts"].ns
  db.entries["trainer:3033"]={kind="trainer",npcId=3033,name="Turak Runetotem",title="Druid Trainer",zone="Thunder Bluff",subzone="Elder Rise",mapID=1456,x=76.5,y=27.3,
    skills={{name="Moonfire",rank="Rank 2",levelReq=10}}}
  db.scouted[4501]={name="Ursyn Ghull",title="Mage Trainer",zone="Thunder Bluff",subzone="Spirit Rise",mapID=1456,x=25,y=20,lastSeen=1}
  db.scouted[4502]={name="Kym Wildmane",title="Druid Trainer",zone="Thunder Bluff",subzone="Elder Rise",mapID=1456,x=76,y=28,lastSeen=1}
  cns.OnContactsChanged()
  assert(cns.ClassTrainer("Druid Trainer")=="druid" and cns.ClassTrainer("Pet Trainer")==nil and cns.ClassTrainer("Leatherworking Trainer")==nil, "class trainer titles")
  assert(cns.IsRelevant("Mage Trainer") and cns.IsIgnored("Mage Trainer"), "relevant for saving, ignored for crafting lists")
  local found=false
  for _,n in ipairs(cns.Contacts()) do if n.n=="Turak Runetotem" then found=true end end
  assert(found, "class trainer is a contact")
  db.entries["trainer:3033"].skills={{name="Moonfire",rank="Rank 2",levelReq=10,priceCopper=200},{name="Rejuvenation",rank="Rank 3",levelReq=16,priceCopper=900},
    {name="Healing Touch",rank="Rank 1",levelReq=1,priceCopper=10}}
  cns.OnContactsChanged()
  local oldLvl=UnitLevel; UnitLevel=function() return 12 end
  for _,n in ipairs(cns.Contacts()) do if n.n=="Turak Runetotem" then
    local d=cns.DetailText(n); print("CLASS TIP", (d:gsub("\n"," | ")))
    assert(d:find("Teaches 3 spells") and d:find("Rejuvenation") and d:find("level 16"), "class trainer tooltip lists spells")
    assert(d:find("Rejuvenation") < d:find("Moonfire"), "next spells for your level come first")
  end end
  UnitLevel=oldLvl
  local mage=false
  for _,h in ipairs(cns.Search("mage")) do if h.npc.n=="Ursyn Ghull" then mage=true end end
  assert(mage, "search finds a seen mage trainer")
  local mine, other=false, false
  for _,h in ipairs(cns.Unvisited()) do
    if h.npc.n=="Kym Wildmane" then mine=true end
    if h.npc.n=="Ursyn Ghull" then other=true end
  end
  print("CLASS TRAINERS", found, mage, mine, other)
  assert(mine and not other, "not-visited lists only your own class's trainer")
  -- nearest trainer button: your class, and professions only from trainers (not supply vendors)
  db.entries["vendor:7777"]={kind="vendor",npcId=7777,name="Hide Seller",title="Leatherworking Supplies",zone="Mulgore",mapID=1412,x=40,y=40,items={}}
  db.scouted[4503]={name="Brewer Bob",title="Alchemy Supplies",zone="Thunder Bluff",mapID=1456,x=40,y=40,lastSeen=1}
  db.scouted[4504]={name="Herb Teacher",title="Herbalism Trainer",zone="Thunder Bluff",mapID=1456,x=41,y=41,lastSeen=1}
  cns.OnContactsChanged()
  local names=function(k) local t={} for _,h in ipairs(cns.NearestTrainerHits(k)) do t[h.npc.n]=true end return t end
  local cl, lw, al = names("class"), names("Leatherworking"), names("Alchemy")
  assert(cl["Turak Runetotem"] and cl["Kym Wildmane"] and not cl["Ursyn Ghull"], "nearest class trainer: own class only")
  assert(lw["Chaw Stronghide"] and not lw["Hide Seller"], "nearest leatherworking trainer skips the supplies vendor")
  assert(not al["Brewer Bob"] and not al["Herb Teacher"], "alchemy: no supply vendor, no herbalism trainer")
  local opt=cns.NearestOptions(); print("NEAREST OPTS", opt[1].text, #opt)
  assert(opt[1].value=="class" and opt[1].text:find("Druid trainer: ") and opt[1].text:find("Turak") or opt[1].text:find("Kym"), "your class comes first, closest named")
  _G.ForeverArtisanContactsFrame:Show(); cns.ShowTab("search")
  cns.GoNearest("class")
  assert(cns.Pages.search.nearest, "button on the Search tab")
  local st=cns.Pages.search.status:GetText() or ""
  local r1=cns.Pages.search.rows[1].data
  print("NEAREST LIST", st, r1 and r1.right)
  assert(st:find("Druid trainers you've met, nearest first"), "nearest list status")
  assert(r1 and (r1.npc.n=="Turak Runetotem" or r1.npc.n=="Kym Wildmane") and r1.right:find("yd") or r1.right:find("other continent"), "rows show distance")
end
-- /fa <profession>: key, alias, the person's name or a clear start all reach the module
do
  local oldBS, oldSearch, hits, searched = SlashCmdList.FABS, SlashCmdList.FASEARCH, 0, 0
  SlashCmdList.FABS=function() hits=hits+1 end
  SlashCmdList.FASEARCH=function() searched=searched+1 end
  for _,w in ipairs({"blacksmithing","bs","blacksmith","Blacksmith","black","smith"}) do SlashCmdList.FOREVERARTISAN(w) end
  SlashCmdList.FOREVERARTISAN("copper rod")
  SlashCmdList.FABS, SlashCmdList.FASEARCH = oldBS, oldSearch
  print("FA ROUTE", hits, searched)
  assert(hits==6 and searched==1, "all six reach Blacksmithing, copper rod searches contacts")
end
-- scrolling lists say how many more are below
do
  local K=ForeverArtisan.UI.Kit({}, {})
  local holder=CreateFrame("Frame")
  local rows=K.MakeRows(holder, 3, 0, false)
  for _,r in ipairs(rows) do r.GetParent=function() return holder end end
  local data={} for i=1,10 do data[i]={left="r"..i} end
  K.Fill(rows, data, 0)
  print("MORE", rows.more and rows.more._text)
  assert(rows.more and rows.more._text=="7 more below, scroll down", "more-below hint")
  K.Fill(rows, data, 7)
  assert(rows.more._text:find("end of list"), "end of list hint")
  K.Fill(rows, {data[1]}, 0)
end
-- minimap: the anvil and the Trade Contacts book, both built (own buttons, no LibDBIcon in the test)
do
  local book=_G.ForeverArtisanContactsMinimapButton
  print("MINIMAP", _G.ForeverArtisanMinimapButton~=nil, book~=nil)
  assert(_G.ForeverArtisanMinimapButton and book, "both minimap buttons")
  local opened
  local oldOpen=ForeverArtisan.Vendors.open
  ForeverArtisan.Vendors.open=function() opened=true end
  book.scripts.OnClick(book,"LeftButton")
  ForeverArtisan.Vendors.open=oldOpen
  assert(opened, "book opens Trade Contacts")
  ForeverArtisan.minimap("contacts"); ForeverArtisan.minimap("contacts")
end
print("CRAFTS OK")
print("SUITE OK")
