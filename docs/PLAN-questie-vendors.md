# Plan: Questie vendors in Trade Contacts (after launch)

Status: planned, not started. Target 0.9.22 or 1.0.x, after the Nov 4, 2026 launch.
Decided Oct 12, 2026.

## Why
Trade Contacts already brings in Questie's profession trainers you haven't met. Vendors only come from your own play. Questie also knows which NPCs sell each item. Today ForeverArtisan only uses that on demand: "Sold by" lines in recipe books and "Vendor:" lines on shopping lists.

## Why it waits until after launch
- Questie's vendor data is from Classic: no prices, no limited stock, and nothing Forever added (camping materials such as Simple Wood). Vendors you meet have all of that.
- The useful part ("who sells this?") already works in recipe books and shopping lists.
- Adding every vendor would make Trade Contacts longer and noisier, and would slow the first read after login right before launch.

## Scope (the narrow version)
- Bring in only vendors that sell profession materials or recipes. Build the item list from our own data: recipe reagents, recipe items and vendor-only reagents.
- Tag them "Questie" like the trainers (`npc.questie = true`, key `questie:<id>`), and only for your faction (neutral towns fit both).
- Show them in Search, Nearest vendor lookups and "Sold by" item tooltips. Keep them out of the Contacts book, which stays "vendors and trainers you've met".
- Item rows from Questie have no price: show "price unknown (from Questie)".
- A vendor you meet replaces its Questie copy, the same as trainers (blocked by `full` / `current`).
- On/off goes with the existing Questie switch (`/fa contacts questie off` and the Works best with line).

## Build notes
- Read it in QuestieTrainers.lua's batched step, or a sibling QuestieVendors.lua using the same batches and cache (`questieCache`, keyed by Questie version and contract).
- Reverse index: for each item on our list, `L.Item.vendors(itemId)` gives NPC ids, then `QDB.Npc(id)` gives name, spawns and faction.
- Watch the time on the first read after a Questie update. Keep batches small, and keep it under the trainer read.
- The /fa panel's Trade Contacts tab: add "From Questie: N more vendors you haven't met" and include them in the "All together" line.

## Tests
- A stubbed Questie with one material vendor and one non-crafting vendor: only the material vendor is added.
- Meeting the vendor replaces the Questie copy.
- `questie off` removes them. A Questie we can't read adds nothing and throws no errors.
- The Contacts book doesn't list them, while Search and tooltips do.

## Copy rules
Naming Questie is fine in game and in the download's CHANGELOG. Never name it on the site, the store or CurseForge relations: there it is "a popular quest-helper addon".
