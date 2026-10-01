# ForeverArtisan release checklist

Run this in game before every build goes to the site or CurseForge/Wago. Screenshot anything off. A red Lua error is an automatic stop.

## 0. Build
- [ ] `python tools\release.py . <version>` ran clean (syntax OK); it replaced the `-dev` version in every TOC; before launch the version is `0.9.x` (or `0.9.x-beta.N` for a rough test build, which the stores hide behind their Beta filter)
- [ ] CHANGELOG.md top section has the version and today's date and reads right to a player
- [ ] Fully restart WoW if a module is new (the game already runs the repo files through the junctions)

## 1. Start-up
- [ ] Log in with no red Lua errors (also after `/reload`)
- [ ] `/fa version` shows the new number, and there's no "different release" warning
- [ ] The minimap button tooltip shows the version (no BETA or DEV on a normal release)
- [ ] -beta builds only: the beta notice shows once, and "Got it" closes it; `/fa feedback` opens it on any build

## 2. /fa panel
- [ ] Every module is listed and says "Running"
- [ ] The Open button works on each one
- [ ] Unchecking a module and reloading turns it off; re-checking it brings it back
- [ ] "Coming soon" lists only professions that aren't built yet

## 3. Every window: open each one and click every tab
Look for overlapping text, rows running off the edge, and anything cut off.
- [ ] Fishing: Fishing / Progress / Catch log / Cast marker
- [ ] Cooking: Cooking / Progress / Cook log / Recipe book
- [ ] First Aid, Alchemy, Leatherworking, Blacksmithing, Tailoring, Engineering, Enchanting: Main / Progress / Craft log / Recipe book
- [ ] Herbalism, Mining, Skinning: Main / Progress / Log / Guide
- [ ] Trade Contacts: Search / Contacts / Limited stock; both pickers on Contacts open inside the window
- [ ] Windows drag, remember where you left them, and close with Esc

## 4. Saved data survives the update
- [ ] Fishing catch log, goals and key bindings; your main keeps its Fishing skill and pole, an alt without Fishing shows "not learned yet"
- [ ] Trade Contacts entries
- [ ] Recipes in every crafting module (if missing, open the profession window once)

## 5. Fishing
- [ ] The cast key casts, and applies a lure when none is on the pole
- [ ] Reel-in works
- [ ] Weapon swap works, including in combat
- [ ] Marker test works, and the cast marker shows where you set it
- [ ] Catches show in the Catch log and count toward goals
- [ ] The Cast marker tab shows the derby countdown

## 6. Crafting and gathering
- [ ] Every crafting module: "Make now" and a plan with a shopping list
- [ ] Enchanting: opening the Enchanting window reads recipes (it may be the older Craft window); casting an enchant shows in the Craft log
- [ ] Tailoring: bolts of cloth show as "craft N" in the shopping list; Blacksmithing and Engineering: bars say "smelt", ore points to your Mining log
- [ ] `/fa` panel: all 13 modules fit in the window
- [ ] On a character without the profession: "Learn from: <trainer>" with a Waypoint button, or the Open window button once learned
- [ ] Capped and "Next rank" text reads right
- [ ] Progress tabs: the skill bar fills correctly
- [ ] Herbalism, Mining, Skinning: typing a new goal amount sticks, the goal bar fills, and extra goals scroll
- [ ] Hovering an ingredient shows the recipes that use it

## 7. Trade Contacts
- [ ] Talking to a new crafting vendor gives a "saved ..." chat line
- [ ] Weapon and armor vendors and class trainers are not saved
- [ ] `/fa <item>` finds results, and clicking one sets a waypoint
- [ ] An item's tooltip shows "Sold by ..."
- [ ] The Limited stock tab lists limited items
- [ ] Riding past a known contact doesn't cause errors; after a game patch, older contacts have grey names
- [ ] Contacts tab: Zone and Trade pickers filter, town headers fold, innkeepers only under Everyone
- [ ] "Show NPC names in town" (in `/fa` and on Search) turns nameplate titles on and off; hover shows the tooltip
- [ ] Search with "Only not visited" says when it hid a match; results are nearest first
- [ ] Right-clicking a contact twice forgets it

## 8. Publish
- [ ] Commit, tag `v<version>` (exactly the TOC version), Push origin
- [ ] GitHub Actions run is green; the GitHub Release has the zip
- [ ] CurseForge and Wago show the new file (Release for 0.9.x and 1.x, Beta only for -beta.N tags)
- [ ] The site download link and changelog match the build
