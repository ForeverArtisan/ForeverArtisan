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
local ADDONS={"ForeverArtisan_Core","ForeverArtisan_Contacts","ForeverArtisan_Fishing","ForeverArtisan_Cooking","ForeverArtisan_Herbalism","ForeverArtisan_Mining","ForeverArtisan_Skinning","ForeverArtisan_FirstAid","ForeverArtisan_Alchemy","ForeverArtisan_Leatherworking","ForeverArtisan_Blacksmithing","ForeverArtisan_Tailoring","ForeverArtisan_Engineering","ForeverArtisan_Enchanting","ForeverArtisan_Camping"}
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
for _,alias in ipairs({"fish","cook","herb","mine","skin","aid","contacts","alch","lw","bs","tailor","eng","ench","camp"}) do run("FOREVERARTISAN", alias.." help") end
-- open every module window and click every tab
local wins={ForeverArtisanFishingFrame="FAFISH",ForeverArtisanCookingFrame="FACOOK",ForeverArtisanHerbalismFrame="FAHERB",ForeverArtisanMiningFrame="FAMINING",ForeverArtisanSkinningFrame="FASKIN",ForeverArtisanFirstAidFrame="FAAID",ForeverArtisanContactsFrame="FACONTACTS",ForeverArtisanAlchemyFrame="FAALCH",ForeverArtisanLeatherworkingFrame="FALW",ForeverArtisanBlacksmithingFrame="FABS",ForeverArtisanTailoringFrame="FATAILOR",ForeverArtisanEngineeringFrame="FAENG",ForeverArtisanEnchantingFrame="FAENCH",ForeverArtisanCampingFrame="FACAMP"}
for wname,cmd in pairs(wins) do
  local before=#frames
  run(cmd,"")
  local w=_G[wname]
  if not w then print("NO WINDOW",wname) os.exit(1) end
  print("WINDOW",wname,"title:",(w.title._text or ""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""), "shown", w._shown)
  for i=before+1,#frames do local b=frames[i]
    if b._text and b.scripts.OnClick and ({Progress=1,Fishing=1,["Catch log"]=1,["Cast marker"]=1,Herbalism=1,Mining=1,Skinning=1,Cooking=1,["Gather log"]=1,["Herb guide"]=1,["Mining log"]=1,["Node guide"]=1,["Skinning log"]=1,["Level guide"]=1,["Cook log"]=1,["Recipe book"]=1,["First Aid"]=1,["Craft log"]=1,Search=1,Contacts=1,["Limited stock"]=1,Alchemy=1,Leatherworking=1,Blacksmithing=1,Tailoring=1,Engineering=1,Enchanting=1,Camp=1,["Campfire kits"]=1})[b._text] then
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
  assert(cn.SetScout==nil and cn.SetScoutFromUI==nil, "no scout switch any more")
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
  local was={} for n,r in pairs(cns2.CharRec().recipes) do was[n]=r.learned end
  GetProfessions=function() return nil,2,nil,4,nil,6 end -- Herbalism and Cooking dropped
  print("UNLEARNED", hns.Skill(), hns.Knows(), cns2.Skill())
  assert(hns.Skill()==nil and not hns.Knows(), "herbalism unlearned")
  assert(cns2.Skill()==nil, "cooking unlearned")
  GetProfessions=oldProf
  for n,r in pairs(cns2.CharRec().recipes) do r.learned=was[n] end -- a rescan after relearning restores these
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
  -- controller buttons in the key box: PAD1 as the fishing key; a pad button used as Shift is a modifier
  local oldKey=st.key
  fns.CaptureKey("swapKey")
  local cap=_G.ForeverArtisanFishingKeyCapture
  cap.scripts.OnGamePadButtonDown(cap, "PADDUP")
  assert(st.swapKey=="PADDUP", "controller button as the swap key: "..tostring(st.swapKey))
  local oCV, oSh = GetCVar, IsShiftKeyDown
  GetCVar=function(k) if k=="GamePadEmulateShift" then return "PADLTRIGGER" end return oCV(k) end
  IsShiftKeyDown=function() return true end
  fns.CaptureKey("swapKey")
  cap.scripts.OnGamePadButtonDown(cap, "PADLTRIGGER")
  assert(st.swapKey=="PADDUP", "the Shift stand-in alone doesn't count")
  cap.scripts.OnGamePadButtonDown(cap, "PAD2")
  assert(st.swapKey=="SHIFT-PAD2", "Shift + a controller button: "..tostring(st.swapKey))
  GetCVar, IsShiftKeyDown = oCV, oSh
  fns.SetKey("swapKey","") st.key=oldKey
  -- key bindings that open windows (a controller button can be set in the game's Key Bindings)
  assert(type(ForeverArtisanTogglePanel)=="function" and type(ForeverArtisanFishingToggle)=="function"
    and type(ForeverArtisanContactsToggle)=="function", "binding functions exist")
  assert(BINDING_NAME_FOREVERARTISAN_PANEL:find("^ForeverArtisan:") and BINDING_NAME_FOREVERARTISAN_FISHING_OPEN:find("^ForeverArtisan:")
    and BINDING_NAME_FOREVERARTISAN_CONTACTS_OPEN:find("^ForeverArtisan:") and BINDING_NAME_FOREVERARTISAN_FISHING_SNAPCAMERA:find("^ForeverArtisan:"),
    "binding names say ForeverArtisan")
  ForeverArtisanFishingToggle() ForeverArtisanFishingToggle()
  ForeverArtisanContactsToggle() ForeverArtisanContactsToggle()
  ForeverArtisanTogglePanel() ForeverArtisanTogglePanel()
  for _,b in ipairs({"ForeverArtisan_Core/Bindings.xml","ForeverArtisan_Contacts/Bindings.xml","ForeverArtisan_Fishing/Bindings.xml"}) do
    local fh=assert(io.open((arg[1] or ".").."/"..b)); local x=fh:read("*a"); fh:close()
    for fn in x:gmatch("%s([%w_]+)%(%)") do assert(type(_G[fn])=="function", b.." calls missing "..fn) end
  end
  -- reel-in on a controller: settings reapplied at cast if missing, bobber picked up after a late landing
  do
    local lf=loadedFrames["ForeverArtisan_Fishing"]
    local evf
    for i=lf.first,lf.last do local fr=frames[i]; if fr.scripts.OnEvent and not evf then
      local ok=pcall(fr.scripts.OnEvent, fr, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
      if ok then evf=fr end end end
    local oInv, oII, oCI3, oT, oUE, oUG, oCV, oSCV = GetInventoryItemID, GetItemInfoInstant, C_Item, C_Timer, UnitExists, UnitGUID, GetCVar, SetCVar
    local cv={SoftTargetInteract="0", SoftTargetInteractArc="0", SoftTargetInteractRange="10"}
    GetCVar=function(k) if cv[k] then return cv[k] end return oCV(k) end
    SetCVar=function(k,v) if cv[k] then cv[k]=v end end
    GetInventoryItemID=function(_,slot) if slot==16 then return 6256 end end
    local inst=function() return 6256,"","","INVTYPE_2HWEAPON",1,2,20 end
    GetItemInfoInstant=inst C_Item={GetItemInfoInstant=inst, GetItemInfo=function() end}
    local queue={}
    -- short timers run on tick(); the 30-second safety timer never comes due in this test
    C_Timer={After=function(d,fn) if d<10 then queue[#queue+1]=fn end end, NewTicker=function() return {Cancel=function() end} end}
    local soft=false
    UnitExists=function(u) if u=="softinteract" then return soft end return oUE and oUE(u) end
    UnitGUID=function(u) if u=="softinteract" then return soft and "GameObject-0-1-2-3-35591-9" or nil end return oUG and oUG(u) end
    local oUN=UnitName
    UnitName=function(u) if u=="softinteract" then return soft and "Fishing Bobber" or nil end return oUN(u) end
    fns.SetKey("key","PAD1") fns.SetKey("reelKey","PAD1") ForeverArtisanFishingDB.settings.padRecast=true
    cv.SoftTargetInteract, cv.SoftTargetInteractArc, cv.SoftTargetInteractRange = "0", "0", "10"  -- as if they never went on at login
    assert(fns.EnvMissing(), "settings off at login are noticed")
    evf.scripts.OnEvent(evf, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
    assert(cv.SoftTargetInteract=="3", "cast turns soft targeting on: "..cv.SoftTargetInteract)
    assert(fns.ReelMode()=="mouseover", "no bobber yet")
    local function tick() local q=queue; queue={}; for _,fn in ipairs(q) do fn() end end
    tick() tick() assert(fns.ReelMode()=="mouseover", "still nothing targeted")
    -- a cast with nothing targeted for about 2 seconds is a miss; on a controller the key casts again
    local dg=ForeverArtisanFishingDB.diag or {}
    local none0=dg.softNone or 0
    for _=1,8 do tick() end
    assert((ForeverArtisanFishingDB.diag.softNone or 0)==none0+1, "a missed cast is counted")
    local wf=_G.ForeverArtisanFishingFarWarn
    assert(wf and wf._shown and wf.text._text:find("out of reach"), "controller miss shows the on-screen warning")
    assert(fns.ReelMode()=="recast", "controller key casts again on a far bobber: "..fns.ReelMode())
    -- the bobber turns up later after all: back to reeling in
    soft=true tick() tick()
    assert(fns.ReelMode()=="target", "a late bobber still switches to reel-in")
    assert(not wf._shown, "the warning clears when the bobber turns up late")
    soft=false
    evf.scripts.OnEvent(evf, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
    evf.scripts.OnEvent(evf, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
    tick() tick()
    soft=true tick() tick()
    assert(fns.ReelMode()=="target", "a late bobber is picked up: "..fns.ReelMode())
    evf.scripts.OnEvent(evf, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
    GetInventoryItemID, GetItemInfoInstant, C_Item, C_Timer, UnitExists, UnitGUID, GetCVar, SetCVar, UnitName = oInv, oII, oCI3, oT, oUE, oUG, oCV, oSCV, oUN
    ForeverArtisanFishingDB.settings.padRecast=nil
    fns.RestoreEnv() fns.UpdateEnv()
    print("CONTROLLER REEL ok")
  end
  print("CONTROLLER KEYS ok")
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
  local oldGP=GetProfessions
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
  -- a price (tail) stays whole at the right; the next fill without one hides it
  K.Fill(rows, {{left="Fishing Pole", right="Felicia Doan, Trade Quarter (before update)", tail="23c"}}, 0)
  assert(rows[1].tail and rows[1].tail._text=="23c" and rows[1].tail:IsShown(), "price tail shown")
  K.Fill(rows, {{left="Fishing Pole", right="Old Man Heming"}}, 0)
  assert(not rows[1].tail:IsShown(), "tail hidden without a price")
  print("PRICE TAIL ok")
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
-- Tauren Cultivation: ready line on herb tooltips, one nudge, per-herb level learned from your own casts
do
  local hns=loadedFrames["ForeverArtisan_Herbalism"].ns
  local CULT=99001
  local cdStart, cdDur = 0, 0
  GetSpellInfo=function(x) if x=="Cultivation" or x==CULT then return "Cultivation",nil,1,0,0,0,CULT end if x==2366 then return "Herb Gathering",nil,1,0,0,0,2366 end end
  IsPlayerSpell=function(id) return id==CULT end
  GetSpellCooldown=function() return cdStart, cdDur end
  local function tip(name) local lines={} local tt={AddLine=function(_,l) lines[#lines+1]=l end} hns.CultivationTip(tt,name) return table.concat(lines,"\n") end
  assert(hns.KnowsCultivation(), "knows cultivation")
  assert(hns.CultivationStatus():find("ready"), "status ready")
  assert(tip("Peacebloom"):find("Cultivation ready"), "ready line on tooltip")
  local before=#chat
  fire("UNIT_SPELLCAST_SENT","player","Peacebloom","g1",2366)
  fire("UNIT_SPELLCAST_SENT","player","Silverleaf","g2",2366)
  local nudges=0 for i=before+1,#chat do if chat[i]:find("Cultivation is ready") then nudges=nudges+1 end end
  print("CULT NUDGES", nudges)
  assert(nudges==1, "one nudge per ready period")
  -- too low for Kingsblood: the game's error names the level
  fire("UNIT_SPELLCAST_SENT","player","Kingsblood","g3",CULT)
  fire("UI_ERROR_MESSAGE",0,"Requires level 25")
  local ok,need=hns.CultivationLevelOK("Kingsblood")
  print("CULT KINGSBLOOD", ok, need, tip("Kingsblood"))
  assert(ok==false and need==25 and tip("Kingsblood"):find("needs level 25"), "learned level from the error")
  -- an error with no number: too low at your level
  fire("UNIT_SPELLCAST_SENT","player","Liferoot","g4",CULT)
  fire("UI_ERROR_MESSAGE",0,"Your level is too low")
  ok,need=hns.CultivationLevelOK("Liferoot")
  assert(ok==false and need==21, "too low at 20 -> needs 21+")
  -- a success: works at 20, cooldown starts, no ready line
  fire("UNIT_SPELLCAST_SENT","player","Mageroyal","g5",CULT)
  cdStart, cdDur = 990, 3600
  fire("UNIT_SPELLCAST_SUCCEEDED","player","g5",CULT)
  assert(hns.CultivationLevelOK("Mageroyal")==true, "worked at 20")
  assert(ForeverArtisanHerbalismDB.cultivate.casts==1, "cast counted")
  print("CULT STATUS", hns.CultivationStatus())
  assert(hns.CultivationStatus():find("60 min") and tip("Peacebloom")=="", "on cooldown")
  run("FAHERB","cultivation")
  run("FAHERB","cultivation off")
  cdStart, cdDur = 0, 0
  assert(tip("Peacebloom")=="", "off: no line"); run("FAHERB","cultivation on")
  -- a character without the spell hears nothing
  IsPlayerSpell=function() return false end
  assert(not hns.KnowsCultivation() and tip("Peacebloom")=="" and hns.CultivationStatus()==nil, "not known: silent")
  GetSpellInfo=nil IsPlayerSpell=nil GetSpellCooldown=nil
end
-- Camping: your camp item per profession, kits by Cooking, cooldown after placing, reminder at a fire
do
  local cp=loadedFrames["ForeverArtisan_Camping"].ns
  local rows=cp.Rows()
  local fish for _,r in ipairs(rows) do if r.prof=="Fishing" then fish=r end end
  print("CAMP ROWS", #rows, fish and fish.now, fish and fish.next, fish and fish.nextAt)
  assert(fish and fish.now=="Fish Bowl" and fish.next=="Fishing Rack" and cp.NextText(fish)=="Fishing Rack: needs a Blueprint", "skill 150, no Blueprint item: tier 1")
  local kits,cook=cp.KitRows()
  assert(cook==150 and kits[1].state=="use" and kits[2].state=="use" and kits[3].state=="low", "kits by cooking 150")
  assert(cp.CampItem("Anarchist's Workbench").prof=="Engineering" and cp.CampItem("Trapper's Workbench").prof=="Skinning", "workbench names")
  assert(cp.Left()==0 and cp.Status():find("ready"), "ready at start")
  -- a Fish Bowl in the bags, placed at a fire
  local oldNum,oldLink=GetContainerNumSlots,GetContainerItemLink
  GetContainerNumSlots=function(b) return b==0 and 1 or 0 end
  cp.InvalidateBags()
  GetContainerItemLink=function() return "|cffffffff|Hitem:990001::|h[Fish Bowl]|h|r" end
  cp.InvalidateBags()
  local AURA=false
  UnitBuff=function(_,i) if AURA and i==1 then return "Campfire Nearby" end end
  local before=#chat
  AURA=true; fire("UNIT_AURA","player")
  local nudged=false for i=before+1,#chat do if chat[i]:find("Your Fish Bowl %(%+stats%) is ready") then nudged=true end end
  print("CAMP NUDGE", nudged, cp.AtFire())
  assert(nudged and cp.AtFire(), "reminder at the fire")
  -- placed by a cast with a different name: seen when the Fish Bowl leaves the bags at the fire
  fire("BAG_UPDATE_DELAYED") -- the bowl is in the bags
  GetSpellInfo=function(id) if id==77001 then return "Set Up Camp Feature" end end
  fire("UNIT_SPELLCAST_SUCCEEDED","player","g",77001)
  assert(cp.Left()==0, "cast name alone doesn't match")
  GetContainerItemLink=function() return nil end
  cp.InvalidateBags()
  fire("BAG_UPDATE_DELAYED")
  print("CAMP CASTNAMES", ForeverArtisanCampingDB.castNames and ForeverArtisanCampingDB.castNames["Set Up Camp Feature"])
  assert(ForeverArtisanCampingDB.castNames["Set Up Camp Feature"]=="Fish Bowl", "learned the cast name")
  GetContainerItemLink=function() return "|cffffffff|Hitem:990001::|h[Fish Bowl]|h|r" end
  cp.InvalidateBags()
  print("CAMP STATUS", cp.Status())
  assert(cp.Left()>3500 and cp.Status():find("placed Fish Bowl"), "cooldown after placing")
  assert(cp.KitLeft()==nil, "no kit in bags")
  GetContainerItemLink=function() return "|cffffffff|Hitem:990002::|h[Basic Campfire Kit]|h|r" end
  cp.InvalidateBags()
  GetItemCooldown=function() return 900, 300 end
  print("CAMP KIT", cp.KitLeft())
  assert(cp.KitLeft()>150, "campfire kit's own 5-minute cooldown")
  GetItemCooldown=nil
  GetContainerItemLink=function() return "|cffffffff|Hitem:990001::|h[Fish Bowl]|h|r" end
  cp.InvalidateBags()
  AURA=false; fire("UNIT_AURA","player"); AURA=true
  before=#chat; fire("UNIT_AURA","player")
  for i=before+1,#chat do assert(not chat[i]:find("is ready"), "no reminder while on cooldown") end
  -- Craft: opens the profession window on the camp item's recipe
  do
    local oldT, oldAfter = C_TradeSkillUI, C_Timer.After
    local opened, picked
    C_Timer.After=function(_,fn) fn() end
    C_TradeSkillUI={OpenTradeSkill=function(line) opened=line; _G.ProfessionsFrame=_G.ProfessionsFrame or CreateFrame("Frame"); ProfessionsFrame:Show() end,
      GetAllRecipeIDs=function() return {501,502} end,
      GetRecipeInfo=function(id) return {name=(id==502) and "Fish Bowl" or "Raw Fish"} end,
      OpenRecipe=function(id) picked=id end}
    cp.OpenCraft("Fishing",356,"Fish Bowl")
    print("CAMP CRAFT", opened, picked)
    assert(opened==356 and picked==502, "craft opens the window on the recipe")
    -- another profession's window already open: still switches
    opened=nil; cp.OpenCraft("Skinning",393,"Camp Chair"); assert(opened==393, "switches to Skinning")
    ProfessionsFrame:Hide()
    C_TradeSkillUI={}
    local before=#chat
    cp.OpenCraft("Fishing",356,"Fish Bowl")
    assert(chat[#chat]:find("Open your Fishing window"), "hint when the window won't open")
    C_TradeSkillUI, C_Timer.After = oldT, oldAfter
  end
  -- materials: seed reagents counted from the bags; Craft is gray without them
  do
    local oldLink=GetContainerItemLink
    local can, lines = cp.CanMake("Fish Bowl", {})
    assert(can==0 and lines[1]:find("0/1") and lines[1]:find("Raw Brilliant Smallfish"), "no mats")
    can = cp.CanMake("Camp Chair", {["light leather"]=7, ["simple wood"]=5})
    assert(can==2, "camp chair: 7 leather / 3, 5 wood / 2 -> 2")
    assert(cp.CanMake("Seed Hybridizer")==nil, "unknown reagents")
    GetContainerItemLink=function(_,s) return "|cffffffff|Hitem:1::|h[Raw Brilliant Smallfish]|h|r" end
    cp.InvalidateBags()
    local fish for _,r in ipairs(cp.Rows()) do if r.prof=="Fishing" then fish=r end end
    print("CAMP MATS", fish.can, fish.mats and fish.mats[1])
    assert(fish.can==0, "fish but no vial")
    GetContainerItemLink=oldLink
    cp.InvalidateBags()
  end
  run("FACAMP","status"); run("FACAMP","debug"); run("FACAMP","reminder"); run("FACAMP","reminder")
  GetContainerNumSlots,GetContainerItemLink=oldNum,oldLink
  cp.InvalidateBags()
  UnitBuff=nil GetSpellInfo=nil
end
-- what's new: fresh install stays quiet and records the version; an update prints the releases since
do
  assert(ForeverArtisanSettings.lastVersion==ForeverArtisan.Version(), "fresh install records the version")
  local out={} local P=print
  print=function(...) local t={} for i=1,select("#",...) do t[#t+1]=tostring(select(i,...)) end out[#out+1]=table.concat(t," ") end
  ForeverArtisanSettings.lastVersion="0.9.8"
  fire("PLAYER_LOGIN")
  local txt=table.concat(out,"\n")
  print=P
  assert(txt:find("What's new") and txt:find("tooltips") and txt:find("worth") and txt:find("Best crafts") and not txt:find("Drag the window"), "update prints the last three releases: "..txt)
  assert(txt:find("foreverartisan.app/bug", 1, true), "news ends with the bug line")
  assert(ForeverArtisanSettings.lastVersion==ForeverArtisan.Version(), "remembers the new version")
  out={} print=function(...) out[#out+1]=table.concat({...}," ") end
  fire("PLAYER_LOGIN")
  print=P
  assert(not table.concat(out,"\n"):find("What's new"), "same version stays quiet")
  out={} print=function(...) out[#out+1]=table.concat({...}," ") end
  run("FOREVERARTISAN","new")
  print=P
  assert(table.concat(out,"\n"):find("0.9.16"), "/fa new prints it")
  print("NEWS ok")
end
-- hidden ("secret") values: events carrying them are skipped, their errors dropped, other errors still raised
do
  local FA=ForeverArtisan
  local SECRET=setmetatable({},{__tostring=function() return "<secret>" end})
  local old=issecretvalue
  issecretvalue=function(v) return v==SECRET end
  local calls=0
  local fr={scripts={},GetScript=function(s,n) return s.scripts[n] end,SetScript=function(s,n,fn) s.scripts[n]=fn end}
  fr.scripts.OnEvent=function(_,e,a) calls=calls+1; if e=="BOOM" then error("attempt to compare a secret value") end; if e=="BUG" then error("real bug") end end
  FA.GuardEvents(fr)
  local before=FA.secretSkips
  fr.scripts.OnEvent(fr,"UNIT_SPELLCAST_SENT",SECRET)
  assert(calls==0 and FA.secretSkips==before+1, "event with a hidden argument is skipped")
  fr.scripts.OnEvent(fr,"BOOM","x")
  assert(calls==1 and FA.secretSkips==before+2, "hidden-value error dropped")
  local ok=pcall(fr.scripts.OnEvent,fr,"BUG","x")
  assert(not ok, "other errors still surface")
  assert(FA.IsSecret(SECRET) and not FA.IsSecret("a") and FA.AnySecret(1,SECRET) and not FA.AnySecret(1,2), "helpers")
  issecretvalue=old
  print("SECRET GUARD ok")
end
-- names in town: Core owns the switch and titles; Trade Contacts only adds known titles and relevance
do
  local FA=ForeverArtisan
  assert(type(FA.TownNamesOn)=="function" and type(FA.SetTownNames)=="function" and type(FA.NpcTitle)=="function", "Core has names in town")
  local was=FA.TownNamesOn()
  -- /fa titles off|on changes only the titles, never the player's nameplate settings
  local cv={nameplateShowFriends="0", nameplateShowFriendlyNPCs="1"}
  local oldGet, oldSet = GetCVar, SetCVar
  local sets=0
  GetCVar=function(k) return cv[k] end
  SetCVar=function(k,v) sets=sets+1; cv[k]=v end
  FA.SetTownNames(false,true); assert(FA.TownNamesOn()==false, "titles off")
  FA.SetTownNames(true,true); assert(FA.TownNamesOn()==true, "titles on")
  assert(sets==0, "titles never touch nameplate settings")
  assert(not FA.FriendlyPlatesOn(), "either setting off = plates off")
  local st, off = FA.TownStatus()
  assert(off and st:find("nameplates are off"), "status says plates are off")
  local cn=loadedFrames["ForeverArtisan_Contacts"].ns
  assert(not cn.ScoutOn(), "Trade Contacts knows scouting needs the plates")
  FA.TurnOnFriendlyPlates()
  assert(cv.nameplateShowFriends=="1" and cv.nameplateShowFriendlyNPCs=="1" and FA.FriendlyPlatesOn() and cn.ScoutOn(), "turn on, only when asked")
  st, off = FA.TownStatus(); assert(not off and st:find("Job titles show"), "status when on")
  for _,c in ipairs({"","titles","titles off","titles on","nameplates",""}) do SlashCmdList.FOREVERARTISAN(c) end
  assert(FA.TownNamesOn()==true, "/fa titles on")
  SlashCmdList.FOREVERARTISAN("contacts scout"); SlashCmdList.FOREVERARTISAN("contacts todo")
  GetCVar, SetCVar = oldGet, oldSet
  -- an older install that had turned it off in Trade Contacts keeps it off
  -- automatic: on by itself, off when a nameplate addon like Plater runs, and the old switch doesn't count
  local oldLoaded=C_AddOns.IsAddOnLoaded
  local running={}
  C_AddOns.IsAddOnLoaded=function(n) return running[n]==true end
  ForeverArtisanSettings.titlesPick=nil; ForeverArtisanContactsDB.scoutOff=true
  assert(FA.TownNamesOn()==true and FA.OtherPlatesAddon()==nil, "auto, old switch ignored")
  running.Plater=true
  assert(FA.OtherPlatesAddon()=="Plater" and FA.TownNamesOn()==false, "leaves titles to Plater")
  assert(FA.TownStatus():find("Plater runs your nameplates"), "says why")
  FA.SetTownNames(true,true); assert(FA.TownNamesOn()==true, "player can still pick on")
  FA.SetTownNames(nil,true); assert(FA.TownNamesOn()==false, "back to auto")
  SlashCmdList.FOREVERARTISAN("titles"); SlashCmdList.FOREVERARTISAN("titles auto")
  C_AddOns.IsAddOnLoaded=oldLoaded
  FA.SetTownNames(was,true)
  assert(FA.KnownTitle and FA.KnownTitle(888)=="Journeyman Alchemist", "Trade Contacts supplies saved titles")
  assert(FA.TitleRelevant and FA.TitleRelevant("Journeyman Alchemist") and not FA.TitleRelevant("Innkeeper"), "crafting titles are gold")
  local lines={} local tt={AddLine=function(_,l) lines[#lines+1]=l end}
  FA.TownNamesTip(tt)
  local txt=table.concat(lines,"\n")
  assert(txt:find("Leatherworking Trainer") and txt:find("NPCs seen so far") and txt:find("nameplates"), "tooltip, with the Trade Contacts part")
  print("TOWN NAMES ok")
end
-- gathering still counts when the cast events never arrive: ore or a herb looted from a world object
do
  local mn=loadedFrames["ForeverArtisan_Mining"].ns
  local hb=loadedFrames["ForeverArtisan_Herbalism"].ns
  local mdb,hdb=mn.DB(),hb.DB()
  local sv={GetTime,GetNumLootItems,GetLootSlotLink,GetLootSourceInfo,GetLootSlotInfo}
  local clock=5000
  GetTime=function() return clock end
  GetNumLootItems=function() return 1 end
  local function loot(id,name,src) clock=clock+10
    GetLootSlotLink=function() return "|cffffffff|Hitem:"..id.."|h["..name.."]|h|r" end
    GetLootSlotInfo=function() return 0,name,1,nil,1 end
    GetLootSourceInfo=function() return src end
    fire("LOOT_OPENED") end
  local m0,h0=mdb.sinceUp or 0,hdb.sinceUp or 0
  loot(2770,"Copper Ore","GameObject-0-1-2-3-1731-0001")
  assert((mdb.sinceUp or 0)==m0+1, "mined node counted without cast events")
  loot(2770,"Copper Ore","Creature-0-1-2-3-2735-0001")
  assert((mdb.sinceUp or 0)==m0+1, "ore off a mob is not a mined node")
  loot(2447,"Peacebloom","GameObject-0-1-2-3-1617-0001")
  assert((hdb.sinceUp or 0)==h0+1, "picked herb counted without cast events")
  assert(mdb.raw[#mdb.raw].node=="Copper Vein", "node name from the ore")
  local sk=loadedFrames["ForeverArtisan_Skinning"].ns
  local sdb=sk.DB() local s0=sdb.sinceUp or 0
  loot(2318,"Light Leather","Creature-0-1-2-3-1985-0001")
  assert((sdb.sinceUp or 0)==s0+1, "skin counted without cast events")
  -- a normal corpse loot with coins in it is not a skin
  local oldLink=GetLootSlotLink
  GetNumLootItems=function() return 2 end
  clock=clock+10
  GetLootSlotLink=function(i) if i==1 then return "|Hitem:2318|h[Light Leather]|h" end end
  fire("LOOT_OPENED")
  assert((sdb.sinceUp or 0)==s0+1, "corpse loot with coins is not a skin")
  GetNumLootItems=function() return 1 end
  GetTime,GetNumLootItems,GetLootSlotLink,GetLootSourceInfo,GetLootSlotInfo=sv[1],sv[2],sv[3],sv[4],sv[5]
  -- auto loot with no loot window: the "You receive loot" line counts the node (ore + stone = one node)
  do
    local oldG,oldT=UnitGUID,GetTime
    GetTime=function() return clock end
    UnitGUID=function(u) if u=="player" then return "Player-1-ME" end end
    clock=clock+10
    local m1,items1=mdb.sinceUp or 0,#mdb.raw
    fire("UNIT_SPELLCAST_SENT","player","Copper Vein","Cast-1",2575)
    fire("UNIT_SPELLCAST_SUCCEEDED","player","Cast-1",2575)
    local function line(msg,guid) fire("CHAT_MSG_LOOT",msg,"Me","","","Me","",0,0,"",0,201,guid or "Player-1-ME") end
    line("You receive loot: |cffffffff|Hitem:2770::::::::14:::::|h[Copper Ore]|h|rx2.")
    line("You receive loot: |cffffffff|Hitem:2835::::::::14:::::|h[Rough Stone]|h|r.")
    assert((mdb.sinceUp or 0)==m1+1 and #mdb.raw==items1+1, "one node from the loot lines")
    local e=mdb.raw[#mdb.raw]
    assert(#e.items==2 and e.items[1].n==2 and e.node=="Copper Vein", "ore and stone on the same node")
    clock=clock+10
    line("You receive loot: |cffffffff|Hitem:2770::::::::14:::::|h[Copper Ore]|h|r.")
    assert((mdb.sinceUp or 0)==m1+1, "loot with no cast before it is not a node")
    clock=clock+10
    fire("UNIT_SPELLCAST_SENT","player","Copper Vein","Cast-2",2575)
    fire("UNIT_SPELLCAST_SUCCEEDED","player","Cast-2",2575)
    line("Someone receives loot: |cffffffff|Hitem:2770::::::::14:::::|h[Copper Ore]|h|r.","Player-1-OTHER")
    assert((mdb.sinceUp or 0)==m1+1, "someone else's loot doesn't count")
    local h1=hdb.sinceUp or 0
    clock=clock+10
    fire("UNIT_SPELLCAST_SENT","player","Peacebloom","Cast-3",2366)
    fire("UNIT_SPELLCAST_SUCCEEDED","player","Cast-3",2366)
    line("You receive loot: |cffffffff|Hitem:2447::::::::14:::::|h[Peacebloom]|h|rx3.")
    assert((hdb.sinceUp or 0)==h1+1, "herb from the loot line")
    UnitIsDead=UnitIsDead or function() return true end
    local sdb2=loadedFrames["ForeverArtisan_Skinning"].ns.DB() local k1=sdb2.sinceUp or 0
    clock=clock+10
    fire("UNIT_SPELLCAST_SENT","player","Mangy Wolf","Cast-4",8613)
    fire("UNIT_SPELLCAST_SUCCEEDED","player","Cast-4",8613)
    line("You receive loot: |cffffffff|Hitem:2318::::::::14:::::|h[Light Leather]|h|r.")
    assert((sdb2.sinceUp or 0)==k1+1, "skin from the loot line")
    UnitGUID,GetTime=oldG,oldT
  end
  SlashCmdList.FAMINING("debug")
  GetNumLootItems=function() return 1 end
  GetLootSlotLink=function() return "|Hitem:2770|h[Copper Ore]|h" end
  GetLootSourceInfo=function() return "GameObject-1" end
  GetLootSlotInfo=function() return 0,"Copper Ore",2 end
  fire("LOOT_OPENED") fire("UNIT_SPELLCAST_SENT","player","Copper Vein","guid",2575)
  SlashCmdList.FAMINING("debug")
  GetNumLootItems,GetLootSlotLink,GetLootSourceInfo,GetLootSlotInfo=sv[2],sv[3],sv[4],sv[5]
  print("GATHER FALLBACK ok (mining, herbalism, skinning)")
end
-- material prices for crafting plans: works with no other addon; Auctionator and vendors when there
do
  local FA=ForeverArtisan
  assert(FA.ItemPrice(4306)==nil, "no price before you've seen one")
  local lw=loadedFrames["ForeverArtisan_Leatherworking"].ns
  assert(lw.ShopCostText({{id=4306,name="Silk Cloth",need=4,have=0}}):find("No prices yet"), "says how to get prices")
  -- an Auction House page you looked at (Classic-style)
  GetNumAuctionItems=function() return 2 end
  GetAuctionItemInfo=function(_,i)
    if i==1 then return "Silk Cloth",nil,20,1,true,0,"",0,0,4000,0,nil,nil,"a",nil,0,4306,true end
    return "Silk Cloth",nil,5,1,true,0,"",0,0,750,0,nil,nil,"b",nil,0,4306,true
  end
  fire("AUCTION_ITEM_LIST_UPDATE")
  local p,src,age=FA.ItemPrice(4306)
  assert(p==150 and src=="your Auction House visits" and age==0, "cheapest per unit remembered: "..tostring(p))
  -- the newer Auction House
  C_AuctionHouse={GetBrowseResults=function() return {{itemKey={itemID=2589},minPrice=40}} end}
  fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  assert(FA.ItemPrice(2589)==40, "browse results remembered")
  -- listen test: counts what it heard, including a full-scan (replicate) list read in slices
  C_AuctionHouse={GetNumReplicateItems=function() return 2500 end,
    GetReplicateItemInfo=function(i) return "x",nil,3,1,true,1,0,0,0,100,0,nil,nil,"o",nil,0,50000+(i%1200),true end}
  fire("REPLICATE_ITEM_LIST_UPDATE")
  assert(FA.AHTest.replicate==2500 and FA.AHTest.replicateRead==2500, "full scan read: "..FA.AHTest.replicateRead)
  assert(FA.AHTest.nIds>=1200 and FA.AHTest.withQty>=1200, "distinct items heard: "..FA.AHTest.nIds)
  local outT={} local P0=print print=function(...) outT[#outT+1]=table.concat({...}," ") end
  run("FOREVERARTISAN","ahtest") print=P0
  local rep=table.concat(outT,"\n")
  assert(rep:find("REPLICATE_ITEM_LIST_UPDATE x1") and rep:find("full%-scan list: 2500"), "report: "..rep)
  run("FOREVERARTISAN","ahtest reset")
  assert(FA.AHTest.nIds==0, "reset")
  print("AH LISTEN TEST ok")
  C_AuctionHouse=nil GetNumAuctionItems=nil GetAuctionItemInfo=nil
  -- Auctionator, when installed, is used first
  Auctionator={API={v1={GetAuctionPriceByItemID=function(_,id) if id==4306 then return 120 end end,
    GetAuctionAgeByItemID=function() return 2 end}}}
  p,src,age=FA.ItemPrice(4306)
  assert(p==150 and src=="your Auction House visits", "your visit today beats a 2-day-old Auctionator scan")
  Auctionator.API.v1.GetAuctionAgeByItemID=function() return 0 end
  p,src,age=FA.ItemPrice(4306)
  assert(p==120 and src=="Auctionator" and age==0, "same day: Auctionator")
  -- a vendor in Trade Contacts wins when cheaper
  local oldV=FA.Vendors
  FA.Vendors={hitsForLink=function() return {{npc={n="Tamar"},item={id=4306,p=500,stack=5}}} end}
  p,src=FA.ItemPrice(4306,"Silk Cloth")
  assert(p==100 and src=="vendor", "cheaper vendor wins")
  FA.Vendors=oldV Auctionator=nil
  -- the shopping list total
  local list={{id=4306,name="Silk Cloth",need=10,have=2,price=150,priceAge=3},{id=2321,name="Fine Thread",need=4,have=0},
    {id=4305,name="Bolt of Silk Cloth",need=5,have=0,craft=5}}
  local total,unpriced,oldest,buying=lw.ShopCost(list)
  assert(total==1200 and unpriced==1 and oldest==3 and buying==2, "cost counts only what you still buy")
  local t=lw.ShopCostText(list)
  print("COST", t)
  assert(t:find("up to 3 days old") and t:find("1 item with no price"), "cost line")
  -- clicking a row types into the Auction House search box, nothing more
  local typed
  AuctionFrame={IsShown=function() return true end} BrowseName={SetText=function(_,x) typed=x end}
  assert(FA.SearchAH("Silk Cloth") and typed=="Silk Cloth", "fills the search box")
  AuctionFrame=nil BrowseName=nil
  assert(not FA.SearchAH("Silk Cloth"), "nothing when the Auction House is closed")
  print("PRICES ok")
end
-- plans include recipes a trainer you've met still teaches
do
  local FA=ForeverArtisan
  local fa=loadedFrames["ForeverArtisan_FirstAid"].ns
  local recs=fa.CharRec().recipes
  recs["Test Bandage"]={name="Test Bandage",learned=false,grayAt=240,itemId=999001,reagents={{id=2589,name="Linen Cloth",n=1}}}
  local oldV=FA.Vendors
  FA.Vendors={hitsForLink=function(_,name)
    if name=="Test Bandage" then return {{npc={n="Arnok",s="Undercity"},item={n="Test Bandage",train=true,sk="First Aid 150",p=180}}} end
    return {} end}
  local t=FA.TrainableRecipe("First Aid","Test Bandage")
  assert(t and t.at==150 and t.cost==180 and t.who=="Arnok (Undercity)", "trainer on file")
  assert(FA.TrainableRecipe("Cooking","Test Bandage")==nil, "another profession's trainer doesn't count")
  local steps,shop,stuck,_,_,hint=fa.Plan(170)
  local trainStep,trainLine
  for _,st in ipairs(steps) do if st.train then trainStep=st end end
  for _,e in ipairs(shop) do if e.train then trainLine=e end end
  assert(trainStep and trainStep.r.name=="Test Bandage", "plan uses the recipe you can train")
  assert(trainLine and trainLine.name=="Train Test Bandage" and trainLine.price==180 and trainLine.source:find("Arnok"), "shopping list says where to train")
  assert(shop[1]==trainLine, "training comes first on the list")
  assert(recs["Test Bandage"].learned==false, "the saved recipe stays unlearned")
  -- no trainer on file: a hint instead
  FA.Vendors={hitsForLink=function() return {} end}
  steps,shop,stuck,_,_,hint=fa.Plan(300)
  assert(stuck and hint and hint:find("trainer"), "hint to visit a trainer: "..tostring(hint))
  FA.Vendors=oldV recs["Test Bandage"]=nil
  -- the crafting template does the same
  local lw=loadedFrames["ForeverArtisan_Leatherworking"].ns
  local lr=lw.CharRec().recipes
  lr["Test Belt"]={name="Test Belt",learned=false,grayAt=240,itemId=999002,reagents={{id=2318,name="Light Leather",n=2}}}
  FA.Vendors={hitsForLink=function(_,name)
    if name=="Test Belt" then return {{npc={n="Shelene"},item={n="Test Belt",train=true,sk="Leatherworking 150",p=500}}} end
    return {} end}
  steps,shop=lw.Plan(170)
  local found
  for _,e in ipairs(shop) do if e.train and e.name=="Train Test Belt" then found=e end end
  assert(found and found.price==500, "template plan trains too")
  local total=lw.ShopCost(shop)
  assert(total>=500, "training cost counts in the total")
  FA.Vendors=oldV lr["Test Belt"]=nil
  print("TRAINABLE ok")
end
-- colors you've seen move the guess; close recipes go to the cheaper one per skill point
do
  local FA=ForeverArtisan
  -- bands: guessed 40/20 below gray until you've seen better
  local r={name="Linen",grayAt=60}
  local y,g=FA.RecipeBands(r,60) assert(y==20 and g==40, "default guess")
  FA.NoteRecipeColor(nil,{name="Linen",grayAt=60,color="orange",scanSkill=21}) -- no old: nothing kept but this scan
  local a={name="Linen",grayAt=60,color="orange",scanSkill=21} FA.NoteRecipeColor(nil,a)
  local b={name="Linen",grayAt=60,color="orange",scanSkill=29} FA.NoteRecipeColor(a,b)
  assert(b.seen.o==29, "highest orange kept")
  y,g=FA.RecipeBands(b,60) assert(y==30 and g==40, "yellow moves past what you saw: "..y)
  assert(math.abs(FA.FadeChance(b,60,30)-1)<1e-9 and math.abs(FA.FadeChance(b,60,45)-0.5)<1e-9, "chance falls from yellow to gray")
  local c={name="Linen",grayAt=60,color="green",scanSkill=36} FA.NoteRecipeColor(b,c)
  y,g=FA.RecipeBands(c,60) assert(y==30 and g==36, "green seen early pulls green in")
  local d={name="Linen",grayAt=75,color="yellow",scanSkill=40} FA.NoteRecipeColor(c,d)
  assert(d.seen.o==nil and d.seen.ylo==40, "a new gray level starts over")
  local fa=loadedFrames["ForeverArtisan_FirstAid"].ns
  assert(fa.ColorFor({learned=true,grayAt=60,seen={o=29}},25)=="orange", "First Aid uses what you've seen")
  -- picking
  local cheap,dear={name="cheap"},{name="dear"}
  local price={cheap=23,dear=31}
  local function M(r) return price[r.name] end
  local pick=FA.PickRecipe({{r=dear,ch=1,score=1},{r=cheap,ch=0.95,score=0.95}},M)
  assert(pick.r==cheap, "close enough: cheaper per point wins")
  pick=FA.PickRecipe({{r=dear,ch=1,score=1},{r=cheap,ch=0.5,score=0.5}},M)
  assert(pick.r==dear, "far apart: the better chance wins")
  price.cheap=nil
  pick=FA.PickRecipe({{r=dear,ch=1,score=1},{r=cheap,ch=0.95,score=0.95}},M)
  assert(pick.r==dear, "no price: the better chance wins")
  price.cheap=23
  pick=FA.PickRecipe({{r=dear,ch=1,score=1.15,bag=true},{r=cheap,ch=1,score=1}},M)
  assert(pick.r==dear, "what you can make from your bags still comes first")
  -- money through things you make yourself
  local bolt={name="Bolt",makes=1,reagents={{id=2589,name="Linen Cloth",n=2}}}
  local shirt={name="Shirt",reagents={{id=2996,name="Bolt",n=3}}}
  local oldIP=FA.ItemPrice
  FA.ItemPrice=function(id) if id==2589 then return 10 end end
  assert(FA.CraftMoney(shirt,{[2996]=bolt})==60, "counts through crafted materials")
  assert(FA.CraftMoney(shirt,nil)==nil, "unknown price: nil")
  FA.ItemPrice=oldIP
  print("CHEAPEST ok")
end
-- training lines: what you can learn now in one line, the rest by the skill you learn it at
do
  local FA=ForeverArtisan
  local shop={
    {name="Train Wool Bandage",train={at=80,who="Nurse Neela"},price=250,source="x"},
    {name="Train Lesser Healing Potion",train={at=55,who="Nurse Neela"},price=150,source="x"},
    {name="Train Heavy Linen Bandage",train={at=40,who="Nurse Neela"},price=100,source="x"},
    {name="Train Simple Poultice",train={at=90},price=250,source="x"},
    {name="Linen Cloth",need=2,have=0},
  }
  local rows=FA.TrainShopRows(shop,55)
  assert(#rows==3, "now + 2 later: "..#rows)
  assert(rows[1].left:find("Train now: Heavy Linen Bandage, Lesser Healing Potion") or rows[1].left:find("Train now: Lesser Healing Potion, Heavy Linen Bandage"), rows[1].left)
  assert(rows[1].right:find("2 to learn") and rows[1].right:find("2s 50c"), rows[1].right)
  assert(rows[1].tip:find("Nurse Neela"), "who to see")
  assert(rows[2].left:find("Wool Bandage") and rows[2].right:find("at 80"), "soonest next")
  assert(rows[3].left:find("Simple Poultice") and rows[3].right:find("at 90"), "then later")
  assert(#FA.TrainShopRows(shop,10)==4, "nothing learnable yet: one line each")
  -- the plan's shopping list puts training in that order too
  local fa=loadedFrames["ForeverArtisan_FirstAid"].ns
  local recs=fa.CharRec().recipes
  recs["T1"]={name="T1",learned=false,grayAt=200,itemId=999011,reagents={{id=2589,name="Linen Cloth",n=1}}}
  recs["T2"]={name="T2",learned=false,grayAt=260,itemId=999012,reagents={{id=2589,name="Linen Cloth",n=1}}}
  local oldV=FA.Vendors
  FA.Vendors={hitsForLink=function(_,name)
    if name=="T1" then return {{npc={n="A"},item={n="T1",train=true,sk="First Aid 160",p=1}}} end
    if name=="T2" then return {{npc={n="A"},item={n="T2",train=true,sk="First Aid 150",p=1}}} end
    return {} end}
  local _,sh=fa.Plan(240)
  local order={}
  for _,e in ipairs(sh) do if e.train then order[#order+1]=e.train.at end end
  for k=2,#order do assert(order[k-1]<=order[k], "train lines by skill") end
  FA.Vendors=oldV recs["T1"]=nil recs["T2"]=nil
  print("TRAIN ORDER ok")
end
-- the Progress tab draws in every crafting window, at normal height and dragged taller
do
  local n=0
  for _,f in ipairs(frames) do
    if f._text=="Progress" and f.scripts.OnClick then
      local ok,err=pcall(f.scripts.OnClick,f) assert(ok,"progress tab: "..tostring(err)) n=n+1
    end
  end
  assert(n>=8, "progress tabs clicked: "..n)
  local sized=0
  for _,f in ipairs(frames) do
    if f.scripts.OnSizeChanged then
      local ok,err=pcall(f.scripts.OnSizeChanged,f,470,820) assert(ok,"taller: "..tostring(err))
      ok,err=pcall(f.scripts.OnSizeChanged,f,470,578) assert(ok,"back: "..tostring(err))
      sized=sized+1
    end
  end
  assert(sized>=8, "resizable windows: "..sized)
  local wheeled=0
  for _,f in ipairs(frames) do
    if f.scripts.OnMouseWheel and wheeled<40 then
      local ok,err=pcall(f.scripts.OnMouseWheel,f,-1) assert(ok,"wheel: "..tostring(err)) wheeled=wheeled+1
    end
  end
  print("WINDOWS ok", n, sized)
end
-- prices on item tooltips, and Train lines that set a waypoint
do
  local FA=ForeverArtisan
  local oldA=_G.Auctionator _G.Auctionator=nil
  FA.NotePrice(765, 26)
  local line=FA.TooltipPrice(765)
  assert(line and line:find("26c") and line:find("today"), "tooltip price: "..tostring(line))
  assert(FA.TooltipPrice(999999)==nil, "no price, no line")
  run("FOREVERARTISAN","prices off")
  assert(FA.TooltipPrice(765)==nil and not FA.PriceTipsOn(), "/fa prices off")
  run("FOREVERARTISAN","prices on")
  assert(FA.TooltipPrice(765), "/fa prices on")
  _G.Auctionator={API={v1={}}}
  assert(FA.TooltipPrice(765)==nil, "quiet when Auctionator shows its own")
  _G.Auctionator=oldA
  -- waypoints
  local neela={n="Nurse Neela",m=1420,x=61,y=52}
  local rows=FA.TrainShopRows({
    {name="Train A",train={at=40,npc=neela},price=100,source="x"},
    {name="Train B",train={at=80,npc=neela},price=250,source="y"}},55)
  assert(rows[1].waypoint==neela and rows[1].tip:find("Click for a waypoint to Nurse Neela"), "train now: waypoint")
  assert(rows[2].waypoint==neela and rows[2].tip:find("waypoint"), "later: waypoint")
  local oldV=FA.Vendors
  FA.Vendors={hitsForLink=function(_,name)
    if name=="X" then return {{npc=neela,item={n="X",train=true,sk="First Aid 40",p=100}}} end return {} end}
  assert(FA.TrainableRecipe("First Aid","X").npc==neela, "trainer contact kept")
  FA.Vendors=oldV
  print("TOOLTIP PRICES ok")
end
-- 0.9.14 fixes from in-game testing
do
  local FA=ForeverArtisan
  -- TomTom: the arrow comes back even when TomTom already has that waypoint
  local added, arrowed, removed = 0, nil, nil
  local oldTT=TomTom
  TomTom={profile={arrow={arrival=15}},
    AddWaypoint=function(_,m,x,y,o) added=added+1 return "uid"..added end,
    RemoveWaypoint=function(_,u) removed=u end,
    SetCrazyArrow=function(_,u) arrowed=u end}
  local cns=loadedFrames["ForeverArtisan_Contacts"].ns
  cns.SetWaypoint({n="Nurse Neela",m=1420,x=61,y=52,z="Tirisfal Glades"})
  assert(arrowed=="uid1", "arrow pointed at the waypoint")
  cns.SetWaypoint({n="Nurse Neela",m=1420,x=61,y=52,z="Tirisfal Glades"})
  assert(removed=="uid1" and arrowed=="uid2", "old one replaced, arrow shown again")
  TomTom=oldTT
  -- material rows: waypoint to the cheapest vendor with a place on the map
  local a={n="Far",m=1,x=1,y=1} local b2={n="Cheap",m=1,x=2,y=2} local c={n="NoMap"}
  local oldV=FA.Vendors
  FA.Vendors={hitsForLink=function() return {
    {npc=a,item={id=3371,p=20}},{npc=b2,item={id=3371,p=10}},{npc=c,item={id=3371,p=1}},
    {npc=a,item={id=3371,train=true,p=1}}} end}
  assert(FA.VendorNPC(3371,"Empty Vial")==b2, "cheapest vendor you can walk to")
  FA.Vendors={hitsForLink=function() return {} end}
  assert(FA.VendorNPC(3371,"Empty Vial")==nil, "none met: nil")
  FA.Vendors=oldV
  -- no price twice: the row skips it when the item tooltip already shows it
  local oldA=_G.Auctionator _G.Auctionator=nil
  FA.NotePrice(2447, 24)
  assert(FA.TooltipPrice(2447) and FA.RowPriceLine(2447,"Peacebloom")==nil, "own price already on the tooltip")
  assert(FA.RowPriceLine(999998,"Nothing"):find("No price yet"), "no price: the hint stays")
  _G.Auctionator=oldA
  -- herbs never say "Drops from mobs"
  assert(FA.HerbSkill and FA.HerbSkill(2447)==1 and FA.HerbSkill(2589)==nil, "herb skill lookup")
  local fa=loadedFrames["ForeverArtisan_FirstAid"].ns
  local src=fa.SourceFor(2449,"Earthroot")
  assert(src:find("Herbalism 15") and not src:find("Drops from mobs"), "First Aid: "..src)
  local ck=loadedFrames["ForeverArtisan_Cooking"].ns
  assert(ck.SourceFor(2449,"Earthroot"):find("Herbalism"), "Cooking herb source")
  -- auto loot: a mob drop counts from the chat line, with the dead target as the source
  local oldT,oldD,oldN,oldE,oldP,oldI=GetTime,UnitIsDead,UnitName,UnitExists,UnitIsPlayer,GetItemInfoInstant
  local clock=5000 GetTime=function() return clock end
  UnitExists=function(u) return u=="target" end UnitIsDead=function(u) return u=="target" end
  UnitIsPlayer=function() return false end
  UnitName=function(u) if u=="target" then return "Vampire Bat" end return "Me" end
  GetItemInfoInstant=function(id) return id,"Trade Goods","Trade Goods","",0,7,0 end
  local me=UnitGUID and UnitGUID("player") or "Player-1"
  fire("CHAT_MSG_LOOT","You receive loot: |cffffffff|Hitem:3685::::::::|h[Bat Wing]|h|r.","","","","","","","","","",me)
  local w=FA.MaterialWhere(3685)
  assert(w and w:find("Vampire Bat"), "drop from chat: "..tostring(w))
  -- right after a gathering cast: not a mob drop
  GetSpellInfo=function() return "Skinning" end
  fire("UNIT_SPELLCAST_SUCCEEDED","player","cast",8613)
  clock=clock+1
  fire("CHAT_MSG_LOOT","You receive loot: |cffffffff|Hitem:4234::::::::|h[Heavy Leather]|h|r.","","","","","","","","","",me)
  assert(FA.MaterialWhere(4234)==nil, "skinning isn't a drop")
  GetTime,UnitIsDead,UnitName,UnitExists,UnitIsPlayer,GetItemInfoInstant=oldT,oldD,oldN,oldE,oldP,oldI GetSpellInfo=nil
  print("IN-GAME FIXES ok")
end
-- module panel: trades you know first, with your skill; a note about Trade Contacts
do
  local oldN,oldI=GetNumSkillLines,GetSkillLineInfo
  local lines={{"Professions",true},{"Tailoring",false,52,75},{"Cooking",false,30,75},{"Secondary Skills",true},{"First Aid",false,51,150}}
  GetNumSkillLines=function() return #lines end
  GetSkillLineInfo=function(i) local l=lines[i] return l[1],l[2],nil,l[3],nil,0,l[4] end
  run("FOREVERARTISAN","")
  local panel=_G.ForeverArtisanPanel
  assert(panel and panel.rows, "panel built")
  panel.scripts.OnShow(panel)
  local titles={}
  for i,row in ipairs(panel.rows) do if row.m then titles[#titles+1]=(row.title._text or ""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","") end end
  local all=table.concat(titles," | ")
  local lastKnown, firstOther = 0, nil
  for i,t in ipairs(titles) do
    if t:find("%d+/%d+") then lastKnown=i elseif not firstOther and not t:find("^Camping") then firstOther=i end
  end
  assert(lastKnown>0 and firstOther and lastKnown<firstOther, "known trades first: "..all)
  assert(all:find("Tailoring  52/75"), "skill shown: "..all)
  for i=2,lastKnown do assert(titles[i-1]<titles[i], "known A to Z: "..all) end
  assert(titles[firstOther]:find("^Alchemy"), "then the other trades A to Z: "..all)
  local campAt
  for i,x in ipairs(titles) do if x:find("^Camping") then campAt=i end end
  assert(campAt and campAt<firstOther, "Camping with what you have: "..all)
  assert(panel.headings[1]._shown and panel.headings[2]._shown and panel.headings[3]._shown, "a heading per group")
  assert(panel.headings[1]._text:find("Your trades") and panel.headings[2]._text:find("Not learned"), "heading text")
  assert(panel.contacts._text and panel.contacts._text:find("Trade Contacts"), "contacts note")
  assert(panel.site and panel.site._text=="foreverartisan.app", "site address to copy")
  -- turning Trade Contacts off asks first
  local shownPopup
  StaticPopupDialogs={} StaticPopup_Show=function(name) shownPopup=name end
  local crow
  for _,row in ipairs(panel.rows) do if row.m and row.m.key=="contacts" then crow=row end end
  local checked=false
  crow.check.GetChecked=function() return checked end
  crow.check.SetChecked=function(_,v) checked=v end
  crow.check.scripts.OnClick(crow.check)
  assert(shownPopup=="FOREVERARTISAN_CONTACTS_OFF" and checked==true, "asks first, stays checked")
  assert(crow.m.enabled~=false, "not turned off yet")
  StaticPopupDialogs.FOREVERARTISAN_CONTACTS_OFF.OnCancel()
  assert(crow.m.enabled~=false, "Keep it on: still on")
  shownPopup=nil
  run("FOREVERARTISAN","disable contacts")
  assert(shownPopup=="FOREVERARTISAN_CONTACTS_OFF", "/fa disable contacts asks too")
  StaticPopupDialogs=nil StaticPopup_Show=nil
  run("FOREVERARTISAN","")
  GetNumSkillLines,GetSkillLineInfo=oldN,oldI
  print("PANEL ORDER ok")
end
-- profession gear read from tooltips, and what a craft is worth
do
  local FA=ForeverArtisan
  local worn={[16]={"Strong Fishing Pole","Equip: Increased Fishing +5.","Enchanted: Eternium Line","Requires Fishing (10)"},
              [7]={"Smelting Pants","Equip: 25% faster smelting."}}
  local bags={[0]={
    {"Arcanite Fishing Pole","Equip: Increased Fishing +35.","Requires Fishing (300)"},
    {"Master Angler's Fishing Hat","Cosmetic","Head","Use: Add this appearance to your Account collection."},
    {"High Test Eternium Fishing Line","Use: Replaces the fishing line on your fishing pole with a high test eternium line.","Requires Fishing (150)"},
    {"Miner's Gloves","Equip: Increased Mining +5."},
    {"Cookie Stirring Rod","Equip: 25% faster cooking."},
    {"Herbalist's Gloves","Enchanted: Herbalism +5"}}}
  local function L(t) local out={} for _,x in ipairs(t) do out[#out+1]={leftText=x} end return {lines=out} end
  local oTI,oC,oL,oN,oI,oInst=C_TooltipInfo,C_Container,GetInventoryItemLink,GetNumSkillLines,GetSkillLineInfo,GetItemInfoInstant
  C_TooltipInfo={GetInventoryItem=function(_,slot) return worn[slot] and L(worn[slot]) end,
                 GetBagItem=function(bag,slot) return bags[bag] and bags[bag][slot] and L(bags[bag][slot]) end}
  C_Container={GetContainerNumSlots=function(bag) return bags[bag] and #bags[bag] or 0 end,
               GetContainerItemLink=function(bag,slot) local it=bags[bag] and bags[bag][slot] return it and ("|Hitem:1|h["..it[1].."]|h") end}
  GetInventoryItemLink=function(_,slot) return worn[slot] and ("|Hitem:2|h["..worn[slot][1].."]|h") end
  GetNumSkillLines=function() return 2 end
  GetSkillLineInfo=function(i) if i==1 then return "Fishing",false,nil,225 end return "Mining",false,nil,41 end
  GetItemInfoInstant=function(link)
    if link:find("Pole") then return 1,"","","INVTYPE_2HWEAPON" end
    if link:find("Gloves") then return 1,"","","INVTYPE_HAND" end
    return 1,"","","INVTYPE_WEAPON" end
  FA.GearChanged()
  local g=FA.GearFor("Fishing")
  assert(g.bonus==5 and g.line=="Eternium Line", "worn pole +5 with the line: "..tostring(g.bonus).." "..tostring(g.line))
  assert(g.better[1] and g.better[1].name=="Arcanite Fishing Pole" and g.better[1].ready==false and g.better[1].req==300, "better pole, not yet")
  local lines=table.concat(FA.GearLines("Fishing"),"\n")
  assert(lines:find("usable at 300") and not lines:find("Hat") and not lines:find("use it on your pole"), "fishing lines: "..lines)
  -- plain pole worn, Strong pole in bags: the one you can use now comes first, even when the
  -- skill list hides Fishing (read from the profession list instead)
  do
    local keep=worn[16]
    worn[16]={"Fishing Pole"}
    table.insert(bags[0], 1, {"Strong Fishing Pole","Equip: Increased Fishing +5.","Enchanted: Eternium Line","Requires Fishing (10)"})
    local sN,sI,oP,oPI=GetNumSkillLines,GetSkillLineInfo,GetProfessions,GetProfessionInfo
    GetNumSkillLines=function() return 0 end
    GetProfessions=function() return nil,nil,nil,7,nil end
    GetProfessionInfo=function(i) if i==7 then return "Fishing",nil,225,225 end end
    FA.GearChanged()
    local gl=FA.GearLine("Fishing")
    assert(gl:find("Strong Fishing Pole") and gl:find("equip it"), "usable pole first: "..tostring(gl))
    local all=table.concat(FA.GearLines("Fishing"),"\n")
    assert(all:find("Arcanite"), "hover lists the 300 pole too: "..all)
    GetNumSkillLines,GetSkillLineInfo,GetProfessions,GetProfessionInfo=sN,sI,oP,oPI
    table.remove(bags[0],1); worn[16]=keep
    FA.GearChanged()
  end
  -- the line still in bags shows until one is on the pole
  worn[16]={"Strong Fishing Pole","Equip: Increased Fishing +5."}
  FA.GearChanged()
  lines=table.concat(FA.GearLines("Fishing"),"\n")
  assert(lines:find("High Test Eternium Fishing Line") and lines:find("use it on your pole"), "line reminder: "..lines)
  -- Mining: gloves are better, pants worn count as worn perk
  g=FA.GearFor("Mining")
  assert(g.better[1] and g.better[1].name=="Miner's Gloves", "mining gloves")
  assert(#g.worn==1 and g.worn[1].perk:find("smelting"), "smelting pants worn")
  assert(FA.GearLine("Mining"):find("Miner's Gloves"), "bags first")
  local hb=FA.GearFor("Herbalism")
  assert(hb.better[1] and hb.better[1].name=="Herbalist's Gloves" and hb.better[1].bonus==5, "glove enchant counts")
  local ck=FA.GearFor("Cooking")
  assert(ck.perks[1] and ck.perks[1].name=="Cookie Stirring Rod", "cooking perk in bags")
  C_TooltipInfo,C_Container,GetInventoryItemLink,GetNumSkillLines,GetSkillLineInfo,GetItemInfoInstant=oTI,oC,oL,oN,oI,oInst
  FA.GearChanged()
  -- craft value: materials, Auction House, vendor, profit
  local oA,oGI=_G.Auctionator,GetItemInfo _G.Auctionator=nil
  FA.NotePrice(990001, 10) FA.NotePrice(990002, 60)
  GetItemInfo=function(id) if id==990002 then return "Thing",nil,1,1,1,"","",1,"",1,15 end end
  local r={itemId=990002, reagents={{id=990001,name="Bit",n=3}}}
  local v=table.concat(FA.CraftValueLines(r),"\n")
  assert(v:find("Materials: about 30c") and v:find("Auction House: about 60c each") and v:find("Vendors pay 15c"), v)
  assert(v:find("Profit: about 27c a craft") and v:find("after its 5%% cut"), "profit after the cut: "..v)
  FA.NotePrice(990003, 5)
  local loss=table.concat(FA.CraftValueLines({itemId=990003, reagents={{id=990001,n=3}}}),"\n")
  assert(loss:find("more than it sells for"), "leveling cost: "..loss)
  -- a vendor that pays more than the Auction House after its cut wins
  FA.NotePrice(990004, 29)
  GetItemInfo=function(id) if id==990004 then return "Poultice",nil,1,1,1,"","",1,"",1,28 end end
  local pv=table.concat(FA.CraftValueLines({itemId=990004, reagents={{id=990001,n=7}}}),"\n")
  assert(pv:find("Costs about 42c more than it sells for %(to a vendor%)"), "vendor beats the house after its cut: "..pv)
  _G.Auctionator,GetItemInfo=oA,oGI
  print("GEAR AND VALUE ok")
end
-- Best crafts: ranking, confidence from price history, goblin houses kept apart, the tab itself
do
  local FA=ForeverArtisan
  local oA=_G.Auctionator _G.Auctionator=nil
  FA.WatchItems({991001,991002,991003,991004})
  FA.NotePrice(991001, 10) FA.NotePrice(991002, 100) FA.NotePrice(991003, 300)
  local oZ=GetMinimapZoneText
  -- today's listings at your faction house: plenty listed, steady
  GetMinimapZoneText=function() return "Valley of Strength" end
  FA.NoteMarket(991002, 100, 40) FA.NoteMarket(991003, 300, 2)
  -- Booty Bay sees a much higher price: stays in its own memory
  GetMinimapZoneText=function() return "Booty Bay" end
  FA.NotePrice(991002, 5000) FA.NoteMarket(991002, 5000, 1)
  GetMinimapZoneText=oZ
  assert(FA.AHPrice(991002)==100, "goblin house price doesn't leak into your faction's: "..tostring(FA.AHPrice(991002)))
  assert(FA.PriceConfidence(991002).level=="good", "40 listed today is steady")
  assert(FA.PriceConfidence(991003).level=="shaky", "2 listed is shaky")
  local recipes={
    A={name="Cheap Thing", learned=true, itemId=991002, reagents={{id=991001,n=2}}},  -- 95-20 = +75
    B={name="Pricey Thing", learned=true, itemId=991003, reagents={{id=991001,n=5}}}, -- 285-50 = +235
    C={name="Loser", learned=true, itemId=991001, reagents={{id=991003,n=1}}},         -- sells 9, costs 300
    D={name="Unknown", learned=false, itemId=991004, reagents={{id=991001,n=1}}},
  }
  recipes.E={name="Basic Campfire", learned=true, itemId=991002, reagents={{id=991001,n=1}}} -- would earn, but left out
  local chance={["Cheap Thing"]=1, ["Loser"]=0.5, ["Basic Campfire"]=1}
  local rows=FA.BestCrafts(recipes, function(r) return chance[r.name] or 0 end, "profit")
  assert(rows[1].r.name=="Pricey Thing" and rows[2].r.name=="Cheap Thing" and rows[3].r.name=="Loser" and #rows==3, "most profit first")
  rows=FA.BestCrafts(recipes, function(r) return chance[r.name] or 0 end, "level")
  assert(#rows==2 and rows[1].r.name=="Cheap Thing" and rows[1].perPoint<0, "cheapest to level: one that earns money first")
  rows=FA.BestCrafts(recipes, function(r) return chance[r.name] or 0 end, "both")
  assert(#rows==1 and rows[1].r.name=="Cheap Thing", "both: skill-ups that pay")
  local src=table.concat(FA.PriceSourceLines(),"\n")
  assert(src:find("own Auction House visits") and src:find("Works best with Auctionator"), "source line without Auctionator: "..src)
  _G.Auctionator={API={v1={}}} AUCTIONATOR_SAVEDVARS={TimeOfLastBrowseScan=time()}
  src=table.concat(FA.PriceSourceLines(),"\n")
  assert(src:find("Auctionator, full scan today") and not src:find("Works best"), "source line with Auctionator: "..src)
  _G.Auctionator=oA AUCTIONATOR_SAVEDVARS=nil
  -- the tab: open Cooking, click Best crafts, switch modes
  local ck=loadedFrames["ForeverArtisan_Cooking"].ns
  local c=ck.CharRec()
  c.recipes["Cheap Thing"]=recipes.A c.recipes["Pricey Thing"]=recipes.B
  for _,f in pairs(frames) do if f._text=="Best crafts" and f.scripts.OnClick then f.scripts.OnClick(f) end end
  assert(ck.lastBest and #ck.lastBest>=2, "best tab rendered: "..tostring(ck.lastBest and #ck.lastBest))
  assert(ck.lastBest[1].left:find("Pricey Thing") and ck.lastBest[1].tail:find("Indicator"), "row with a confidence dot")
  for _,f in pairs(frames) do if f._text=="Cheapest to level" and f.scripts.OnClick then f.scripts.OnClick(f) end end
  assert(ck.DB().settings.bestMode=="level", "mode remembered")
  assert(FA.Money(-30)=="-30c" and FA.Money(-12345)=="-1g 23s", "losses read as losses: "..FA.Money(-30))
  ck.DB().settings.bestMode=nil
  c.recipes["Cheap Thing"]=nil c.recipes["Pricey Thing"]=nil
  -- Auctionator after a Booty Bay scan: its price is the goblin one, so your own house's wins
  do
    local oA2, oZ2 = _G.Auctionator, GetMinimapZoneText
    local aucP = {[991005]=2500, [991006]=900, [991007]=300}
    _G.Auctionator={API={v1={GetAuctionPriceByItemID=function(_,id) return aucP[id] end, GetAuctionAgeByItemID=function() return 0 end}}}
    GetMinimapZoneText=function() return "Undercity" end FA.NotePrice(991005, 450)
    GetMinimapZoneText=function() return "Booty Bay" end
    local oT=time; time=function() return oT()+5 end
    FA.NotePrice(991005, 2500) FA.NotePrice(991007, 300)
    time=oT GetMinimapZoneText=oZ2
    local p, src = FA.AHPrice(991005)
    assert(p==450, "goblin scan doesn't change your house's price: "..tostring(p).." "..tostring(src))
    assert(FA.AHPrice(991006)==900, "items the goblin house didn't see still use Auctionator")
    assert(FA.AHPrice(991007)==nil, "seen only at a goblin house: no price for your own")
    _G.Auctionator=oA2
  end
  -- where to sell: the goblin house pays clearly more (after 15% vs 5%), with a steady price
  do
    local oZ3 = GetMinimapZoneText
    FA.WatchItems({991010, 991011, 991012})
    GetMinimapZoneText=function() return "Undercity" end
    FA.NotePrice(991010, 500) FA.NoteMarket(991010, 500, 12)   -- home 4s 75c after cut
    FA.NotePrice(991011, 500) FA.NoteMarket(991011, 500, 12)
    FA.NotePrice(991012, 3000) FA.NoteMarket(991012, 3000, 12)
    GetMinimapZoneText=function() return "Booty Bay" end
    FA.NotePrice(991010, 2500) FA.NoteMarket(991010, 2500, 6)  -- goblin 21s 25c after cut: wins
    FA.NotePrice(991011, 2500) FA.NoteMarket(991011, 2500, 1)  -- only 1 listed: shaky, no tag
    FA.NotePrice(991012, 1000) FA.NoteMarket(991012, 1000, 8)  -- home pays more: tag only at a goblin house
    assert(FA.HouseCompare(991012).better=="home", "at Booty Bay: your own house pays more")
    assert(FA.HouseCompare(991010).better==nil, "at Booty Bay: no goblin tag, you're already there")
    GetMinimapZoneText=function() return "Undercity" end
    local c = FA.HouseCompare(991010)  -- no item info: a stack of 1, so the full 30c postage
    assert(c and c.better=="goblin" and c.homeNet==475 and c.gobNet==2095 and c.postage==30, "goblin wins after postage: "..tostring(c and c.gobNet))
    assert(FA.HouseTag(c)=="better at goblin AH: +16s 20c", FA.HouseTag(c))
    local oGI, oCI=GetItemInfo, C_Item
    C_Item=nil GetItemInfo=function(id) if id==991010 then return "Goblin Thing",nil,1,1,1,"Consumable","Food",20 end return oGI(id) end
    assert(FA.Postage(991010)==2 and FA.HouseCompare(991010).gobNet==2123, "a stack of 20 shares one 30c slot")
    GetItemInfo, C_Item = oGI, oCI
    -- an item whose details haven't arrived: asked for, and lists redraw when they come in
    local asked, redrawn = nil, 0
    local oCI2, oPC = C_Item, FA.PricesChanged
    C_Item={GetItemInfo=function() return nil end, RequestLoadItemDataByID=function(id) asked=id end}
    FA.PricesChanged=function() redrawn=redrawn+1 end
    FA.WaitForItem(991099)
    assert(asked==991099, "asked the game for the item")
    FA.OnItemInfo(991098) assert(redrawn==0, "items nobody waited on don't redraw")
    FA.OnItemInfo(991099)
    assert(redrawn==1, "redraw once it arrives: "..redrawn)
    C_Item, FA.PricesChanged = oCI2, oPC
    assert(FA.HouseCompare(991011).better==nil, "a shaky goblin price doesn't win")
    assert(FA.HouseCompare(991012).better==nil, "at home, no tag for your own house")
    local lines = table.concat(FA.HouseLines(991010), "\n")
    assert(lines:find("Where to sell") and lines:find("Goblin Auction House: 25s each, about 20s 95c a craft after its 15%% cut and postage")
      and lines:find("pays about 16s 20c more") and lines:find("Postage to a banker there: 30c"), lines)
    local worth = table.concat(FA.CraftValueLines({name="Goblin Thing", itemId=991010, reagents={{id=991001,n=1}}}), "\n")
    assert(worth:find("Where to sell"), "What it's worth includes both houses: "..worth)
    assert(#FA.HouseLines(991001)==0, "no goblin price: no block")
    -- the Best crafts row shows the tag in place of "sells"
    local ck=loadedFrames["ForeverArtisan_Cooking"].ns
    local cr=ck.CharRec()
    cr.recipes["Goblin Thing"]={name="Goblin Thing", learned=true, itemId=991010, reagents={{id=991001,n=1}}}
    ck.DB().settings.bestMode="profit"
    for _,f in pairs(frames) do if f._text=="Best crafts" and f.scripts.OnClick then f.scripts.OnClick(f) end end
    local found
    for _,d in ipairs(ck.lastBest or {}) do if d.left:find("Goblin Thing") then found=d end end
    assert(found and found.right:find("better at goblin AH: %+16s 20c") and not found.right:find("sells"), "row tag: "..tostring(found and found.right))
    local _, nWhere = found.tip:gsub("Where to sell", "")
    assert(nWhere==1, "row tooltip shows Where to sell once: "..nWhere)
    cr.recipes["Goblin Thing"]=nil ck.DB().settings.bestMode=nil
    GetMinimapZoneText=oZ3
    print("WHERE TO SELL ok")
  end
  -- the Modules panel finds Cooking when the Archaeology and Fishing slots are empty (Styzza Artisan)
  local oP, oN = GetProfessions, GetNumSkillLines
  GetProfessions=function() return 7,8,nil,nil,5 end GetNumSkillLines=function() return 0 end
  local known=FA.LearnedTrades()
  assert(known.cooking and known.alchemy and known.leatherworking, "cooking after empty slots")
  GetProfessions, GetNumSkillLines = oP, oN
  print("BEST CRAFTS ok")
end
-- Forever names: first + last. Two "Styzza"s on one realm keep separate records.
do
  local FA=ForeverArtisan
  local oG,oN,oR=UnitGUID,UnitName,GetRealmName
  UnitName=function() return "Styzza" end GetRealmName=function() return "PvE" end
  local t={ ["Styzza-PvE"]={ skill=50 } }
  UnitGUID=function() return "Player-1234-0A1B2C3D" end
  local k1=FA.CharKey(t)
  assert(k1=="Styzza-PvE-0A1B2C3D" and t[k1].skill==50 and t["Styzza-PvE"]==nil, "first one adopts the old record: "..k1)
  UnitGUID=function() return "Player-1234-0E0F1011" end
  local k2=FA.CharKey(t)
  assert(k2~=k1 and t[k2]==nil, "the second Styzza starts fresh")
  UnitGUID=nil
  assert(FA.CharKey({})=="Styzza-PvE", "no game ID yet: plain name-realm")
  UnitGUID,UnitName,GetRealmName=oG,oN,oR
  -- a character without Cooking doesn't show another character's learned recipes
  local ck=loadedFrames["ForeverArtisan_Cooking"].ns
  local rec=ck.CharRec()
  rec.recipes["Old Thing"]={name="Old Thing", learned=true, itemId=1}
  local oGP,oGS,oGN=GetProfessions,GetSkillLineInfo,GetNumSkillLines
  GetProfessions=function() return 1,nil,nil,nil,nil end GetProfessionInfo=GetProfessionInfo or function() end
  GetNumSkillLines=function() return 0 end
  local skillAPI=C_TradeSkillUI C_TradeSkillUI=nil
  assert(ck.Skill()==nil and rec.recipes["Old Thing"].learned==false, "learned flags from another character cleared")
  rec.recipes["Old Thing"]=nil
  GetProfessions,GetSkillLineInfo,GetNumSkillLines,C_TradeSkillUI=oGP,oGS,oGN,skillAPI
  print("CHAR KEY ok")
end
print("CRAFTS OK")
print("SUITE OK")
