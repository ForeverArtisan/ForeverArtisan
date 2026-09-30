# ForeverArtisan changelog

## 0.9.5 (unreleased)
- Trade Contacts: a crafting NPC you talked to is saved even when no trainer or shop window opens (a trainer who won't train you yet only shows chat). They show as "visited, no list yet" instead of "seen, not visited".
- Trade Contacts search: one row per trainer, with the ranks they teach on it ("trains 16 · Apprentice").
- Trade Contacts: two checkboxes on the Search tab replace the scout and todo commands. "Show NPC names in town" finds crafting NPCs as you pass; "Only not visited" lists the ones you haven't talked to, nearest first. The slash commands still work.
- Wording: "seen, not visited yet" is now "seen, talk to save".

## 0.9.4 (2026-09-29)
- Alchemy (new module): what to make now for skill-ups, a plan to your target skill with a shopping list, a craft log, a recipe book, where to train next, and Alchemy lines on herb and vial tooltips. Herbs you're short on point to where your Herbalism log found them. Transmutes stay out of the plan because of their cooldowns. `/fa alch`
- Leatherworking (new module): the same window and plan. Cured hides count as crafts, not purchases: the plan makes only the ones you don't already have and lists the raw hides and Salt instead. Leather and hides point to where your Skinning log found them. `/fa lw`
- Alchemy and Leatherworking name a trainer from your Trade Contacts for your next rank once you've met one.
- Fishing: the Derby tab is now the Cast marker tab. The marker tools sit at the top; the derby countdown, rules and catches are still there underneath.
- Trade Contacts: riding instructors and weapon masters are no longer saved as contacts (class trainers already weren't). Ones saved before stay until you forget them.
- Fix: First Aid said "You haven't learned First Aid" on characters without Cooking. The same check in Cooking, Fishing, Herbalism, Mining and Skinning could miss a profession the same way.
- Trade Contacts search: a trainer shows as one row ("trains 33") instead of one row per recipe; "alchemy" now finds Alchemists and "leatherworking" finds Leatherworkers; NPCs you've passed but not talked to show up too, marked "seen, not visited yet". Results are nearest first, across zones on your continent. Use `/fa search alchemy` when the word is also a module name.
- Trade Contacts: trainer entries no longer end in "(available)" or "(unavailable)".
- Every list: long names and long details share the row instead of printing over each other.
- Cooking, First Aid, Alchemy, Leatherworking: until your recipes are read, every tab shows an "Open <profession> window" button. One click opens the window and the recipes are read.
- Cooking, First Aid, Alchemy, Leatherworking: on a character that hasn't learned the profession, the window names the nearest trainer from your Trade Contacts who teaches Apprentice, with a Waypoint button.
- No more BETA tag on tested releases. Only builds named "-beta" show it now, and the login popup went with it. `/fa feedback` still shows where to send bugs and ideas.

## 0.9.3 (2026-09-28)
- Listed for WoW Forever only. Addon managers no longer offer ForeverArtisan to Classic Era players, where it doesn't work. No changes in game.

## 0.9.2 (2026-09-28)
- Download fix: the zip no longer includes a stray folder without a TOC file, which made Wago reject the 0.9.1-beta.1 upload. No changes in game.

## 0.9.1-beta.1 (2026-09-28)
- Cooking / First Aid: the plan explains itself. A red line shows when you are capped and planning past your rank; the yellow "recipes stop at N" line moved up under the target box; the target turns red when the plan cannot reach it. Same warning in `/fa cook plan` and `/fa aid plan`.
- Trade Contacts: weapon and armor vendors are now read instead of skipped, and saved only if they actually sell crafting goods (with just those items).
- Core: new vendor-only reagent list. Tooltips and shopping lists say what kind of vendor sells a reagent before you have met one ("Cooking Supplies vendors - none in your Trade Contacts yet").

## 0.9.0 (2026-09-27)
- One suite, one version: every part of ForeverArtisan now shares this number. /fa version shows it; the module panel flags any part that doesn't match.
- Suite style: every window, tab row, heading, skill bar and goal list comes from Core's shared style kit. Gold everywhere.
- Names: everything is ForeverArtisan now. Commands /fa fish, /fa cook, /fa herb, /fa mine, /fa skin, /fa aid, /fa contacts (plus /fafish, /facook, /faherb, /famining, /faskin, /faaid, /facontacts, /fasearch). Old /mfish, /mlog, /mats removed. Saved data moves over automatically.
- Herbalism, Mining, Skinning: goals get progress bars and editable amounts; Progress tabs get the skill bar.
- Fishing: the fishing key re-applies itself after you equip the pole (and every couple of seconds if anything drops it), so you no longer have to clear and re-set it. /fa fish status shows whether the key is active.
- Beta notice only counts as seen after you click "Got it", so it can't be missed.
- Beta tag is automatic: every 0.x build (and any -beta build) shows BETA; release builds don't. The minimap tooltip shows the version too.
- Trade Contacts (new, replaces the old vendor list): your own crafting address book. Talk to a crafting vendor or profession trainer and they're saved with what they sell or teach, prices, limited stock and location. Search it (/fa <item>), see "Sold by" on item tooltips, click for a waypoint. It starts empty, only knows NPCs you've met, and is shared by all characters on your account. Turn it off in the /fa panel like any module. Contacts stay honest: passing by one refreshes it, after a game update the ones you haven't seen since are marked "before update", after two updates without a sighting they drop out of tooltips and search, and you can forget one with a double right-click.
- Core no longer ships a built-in vendor list. Fishing's "Suggest from Cooking" now reads the Cooking module.
- Cooking: shows where to train the next rank (and what to do when capped).
- First Aid: new module. Make now, plan + shopping list, craft log, recipe book, where to train next, material tooltips.
