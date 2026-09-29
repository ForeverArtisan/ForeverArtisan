# ForeverArtisan — how the app is built (read this first)

ONE app, ONE download, ONE version, built as a SUITE: **ForeverArtisan_Core** is the hub and the shared style kit; every tradeskill is a module underneath it and must look and behave the same.
**Source of truth: the Git repo `D:\ForeverArtisan`** (GitHub: Forever-Artisan org). It is the ONLY copy: the ten folders in `Interface\AddOns` are junctions pointing into the repo (new module = new junction: `mklink /J "<AddOns>\ForeverArtisan_X" "D:\ForeverArtisan\ForeverArtisan_X"`), so the game runs the repo files. Both Claude projects (addon + website) edit the repo and nothing else; never write into AddOns or keep a second copy. Copies under `claude/addons/` in the project are reference snapshots only. Moved to the repo Sep 28, 2026.

## Versioning: one suite version
- Current release: **0.9.3** (Sep 28, 2026; first public builds 0.9.1-beta.1 → 0.9.2 → 0.9.3 the same day). Next is **0.9.4** (bundles the BETA-tag change with Alchemy + Leatherworking). 1.0.0 is reserved for launch day (Nov 4, 2026).
- Stores: CurseForge project **1716370**, Wago **b6mzv4KP** (IDs in Core's TOC); GitHub org/repo **ForeverArtisan/ForeverArtisan** (owner account foreverartisan-dev). Secrets `CF_API_KEY`, `WAGO_API_TOKEN`.
- Every TOC is `## Interface: 16001` only (WoW Forever; the stores list it as game version 1.60.1). Don't add Classic Era interface numbers: addon managers would offer the suite to Classic Era players, where it doesn't work. The packager then names the zip `ForeverArtisan-vX.Y.Z-forever.zip`.
- Tags must start with a lowercase `v` (`v0.9.4`); a tag without it starts no release run. Order in GitHub Desktop: commit → tag → push (pushing the commit first and the tag afterwards also works).
- Store label comes from the tag: a tag with "beta" uploads as Beta (hidden from CurseForge's default filter), anything else as Release. Decision (Sep 28): normal pre-launch builds are plain `0.9.x` so casual players find them; Decision (Sep 30): they show no BETA tag in game either. Use `-beta.N` only for rough test builds.
- Every TOC carries the same `## Version`. Never bump one module alone. Run `python tools\release.py . <version>` in the repo: it sets all TOCs, syntax-checks every file and renames the `## x.y.z (unreleased)` changelog section to the version with today's date.
- Lua reads it with `FA.Version()` (Core's TOC is the reference). Window brand line shows "v0.9.4" (plus BETA on -beta builds, DEV on -dev); `/fa version` prints it; the module panel shows "Update needed" and login warns if a module's version differs from Core (half-updated install).
- No version numbers in Lua headers or code. `db.version` records the suite version that last wrote the data.
- Beta vs Release is decided by the version, not a setting: `FA.IsBeta()` is true only for versions containing `beta` or `alpha` (e.g. `1.1.0-beta.1`). Beta builds show BETA (windows, minimap tooltip) and the one-time beta notice; plain numbered releases (0.9.4, 1.0.0) show nothing. `/fa feedback` opens the notice any time.
- Dev copy: between releases every TOC says `x.y.z-dev` (e.g. `0.9.4-dev`), so the working copy in game shows a grey DEV tag and can't be mistaken for the public build. `FA.IsDev()` checks it. Never tag a -dev version: `tools/release.py . 0.9.4` replaces it with the real number first.

## Scope: crafting, not a database
- The product is crafting help (what to make/gather next, skill-ups, goals, plans, shopping lists). No general item/NPC database: Wowhead/AtlasLoot/Questie cover that.
- No shipped vendor list. Where-to-buy answers come from **Trade Contacts**: each player's own address book, filled only by NPCs they've met. It covers crafting vendors, general-goods reagent sellers and profession trainers, and skips class trainers, weapon/armor sellers, bankers, auctioneers and flight masters.
- Freshness (data must be right): each contact stores the game build it was last seen on (`e.build`; `db.builds` = builds this account has run). 0 updates since = normal; 1 = shown grey "before update"; 2+ = hidden from tooltips/search, grey in the list. Passing by (nameplate/mouseover/target) refreshes the build stamp, and within ~10 yd the location. Stock/prices only change when the window is opened. Forget one: double right-click in the list or `/fa contacts forget <name>`. Never auto-delete (phasing/events cause false misses).
- Exception: `Core\VendorItems.lua` is a short list of vendor-only reagents mapped to the KIND of vendor that sells them (no NPC names, no coordinates). It only fills the gap until you've met a vendor; a real "Sold by" line from Trade Contacts always wins. Keep it short and certain.
- Curated knowledge (trainers per rank, key recipe/manual vendors, both factions) belongs in the website guides first. A profession's verified list may ship later as starter data for that module, once complete.
- Kerry's research: `/fa contacts dev` also saves full profession-window dumps for the website pipeline (dump.lua reads ForeverArtisanContactsDB).

## Packaging and release (GitHub)
- Repo root: the ten `ForeverArtisan_*` folders, `.pkgmeta`, `.github\workflows\release.yml`, `CHANGELOG.md`, `README.md`, `docs\` (this file, RELEASE-CHECKLIST.md), `tools\` (release.py, build_crafts.py + templates\, tests\suite.lua: `lua5.1 tools/tests/suite.lua .` must end with SUITE OK before a release). New module folders also need a `move-folders` line in `.pkgmeta`. `.pkgmeta` keeps docs/tools/README/CHANGELOG out of the player zip.
- As you work: add player-facing lines under `## x.y.z (unreleased)` at the top of CHANGELOG.md.
- Ship: run `docs\RELEASE-CHECKLIST.md` in game → `python tools\release.py . 0.9.2` → commit in GitHub Desktop → tag the commit `v0.9.2` (tag = TOC version with a `v`) → Push origin.
- The tag runs the BigWigs packager (GitHub Actions): one zip `ForeverArtisan-<version>.zip` with every module folder at the top level, attached to a GitHub Release and uploaded to CurseForge and Wago with the changelog. Keys live only in GitHub Secrets (`CF_API_KEY`, `WAGO_API_TOKEN`); project IDs in Core's TOC (`## X-Curse-Project-ID`, `## X-Wago-ID`).
- The repo is public so the GitHub release zip can be the site's direct download (release assets of private repos need a login).
- After launch: fixes go out as 1.0.1, 1.0.2…; bigger test builds as 1.1.0-beta.1, -beta.2, then 1.1.0.
- Don't install ForeverArtisan from the CurseForge app on the dev PC: an "update" would write into the junctions, i.e. into the repo.
- The old `D:\ForeverArtisan.App\releases\` folders are retired; GitHub Releases is the archive.

## Core (ForeverArtisan_Core, SavedVariables ForeverArtisanSettings)
- **UI.lua – the shared style kit (load order: first).** Global `ForeverArtisan` (FA):
  - Colors: `FA.GOLD` (#d4a94e, the one brand color used everywhere), GRAY/GREEN/YELLOW/RED/ORANGE, bar colors.
  - Chat: `FA.Printer("Herbalism")` → every message reads "ForeverArtisan Herbalism: ..." in gold. `FA.Prefix(title)`.
  - `FA.Migrate(new, old)` – one-time SavedVariables rename (TOC lists both names for that release).
  - `FA.UI.Frame` (same frame, 470x578, title "ForeverArtisan: <Module>", brand line + BETA, drag, Esc), `FA.UI.Tabs`, `Text`, `Header` (gold), `Button`, `Tip`, `ConfirmButton`, `NumberBox`, `Bar`, `SkillBar`, `Icon`, `QColor`, `Clock`.
  - `FA.UI.Kit(ns, view)` → module-bound widgets: `Window`, `Check`, `SavePos/LoadPos/Draggable`, `MakeRows(p, n, top, withAct, {goals=true})`, `Fill`, `GoalData`, `Wheel`.
- **Modules.lua** – hub. `/fa` panel (on/off, status, Open, Coming soon), `/fa <alias> ...` forwarding via TOC `## X-FA-Slash` / `## X-FA-Alias`, `/fa help|beta|minimap|enable|disable`, anything else = search Trade Contacts (if that module is on). Sets `FA.modules/open/isEnabled`.
- **Minimap.lua** – one button for the suite (`FA.minimap`). (Core has no vendor data of its own any more; the old Core.lua/Data.lua vendor finder moved into Trade Contacts.)

## Modules (all `## Dependencies: ForeverArtisan_Core`)
| Module | /fa alias | Own slash | SavedVariables |
|---|---|---|---|
| Fishing | fish | /fafish (FAFISH) | ForeverArtisanFishingDB |
| Cooking | cook | /facook (FACOOK) | ForeverArtisanCookingDB |
| Herbalism | herb | /faherb (FAHERB) | ForeverArtisanHerbalismDB |
| Mining | mine | /famining (FAMINING) | ForeverArtisanMiningDB |
| Skinning | skin | /faskin (FASKIN) | ForeverArtisanSkinningDB |
| First Aid | aid | /faaid (FAAID) | ForeverArtisanFirstAidDB |
| Alchemy | alch | /faalch (FAALCH) | ForeverArtisanAlchemyDB |
| Leatherworking | lw | /falw (FALW) | ForeverArtisanLeatherworkingDB |
| Trade Contacts | contacts | /facontacts (FACONTACTS), /fasearch | ForeverArtisanContactsDB (account-wide) |
Old names (MatsledgerSettings, MatsFishDB, ForeverArtisanLoggerDB, ForeverArtisanHerbDB) are still listed in the TOCs for this release only so FA.Migrate can carry data over; drop them in the next release. Old slash commands (/mfish, /mlog, /mats, /falog) are gone. Trade Contacts (files Contacts.lua = recording, Finder.lua = tooltips/search/`FA.Vendors`, UI.lua = Search / Contacts / Limited stock tabs) replaced the old Logger module. Frame names are ForeverArtisan<Module>Frame; Fishing buttons ForeverArtisanFishingCastButton / SwapButton; key bindings header FOREVERARTISAN_FISHING.

## Crafting modules: one engine (Alchemy, Leatherworking, and the next ones)
- `tools\build_crafts.py` writes `ForeverArtisan_<Name>\<Name>.lua`, `UI.lua` and the TOC from `tools\templates\Craft.lua.tpl` + `UI.lua.tpl`. Each profession is one entry in its `CRAFTS` list (skill line, slash, alias, SavedVariables, recipe item prefix, trainer advice, recipes the plan skips). Never hand-edit the generated files; fix the template and rerun. The TOC version is copied from Core.
- Same engine as First Aid (reads the profession window, Make now, Plan + shopping list, craft log, recipe book, tooltips), plus:
  - Sub-crafts: a reagent that one of your learned recipes makes (Cured Light Hide) is crafted, not bought. Only the shortfall after your bags, up to three levels deep; its materials join the list. Shown in gold ("craft N").
  - Sources: Trade Contacts vendor → Core vendor-kind hint → your Herbalism / Skinning / Mining / Fishing log ("Herb: Red Rocks (Mulgore), from your Herbalism log") → "not in your Herbalism/Skinning log yet" by item type.
  - Where to train: a trainer from Trade Contacts who teaches the next rank wins; otherwise the Classic answer, labeled as such.
  - The window check is strict: a module only reads a profession window the game says is its own, so Alchemy never reads a Leatherworking window.
- First Aid and Cooking predate the engine and are still their own files. Move them onto it when they next need real work.
- Next on the engine: Tailoring, Enchanting, Blacksmithing, Engineering (one CRAFTS entry each, plus anything profession-specific).

## Suite style rules (every module, including new professions)
- Build windows only through `FA.UI.Kit`: `K.Window` with tabs **Main (profession name) / Progress / Log / Guide** (Fishing's 4th tab is Cast marker: marker tools on top, fishing derby below).
- Progress tab: `K.SkillBar` at top, "N since your last skill-up · pace" line, "Pick next" list, Goals with progress bars + editable amounts (`MakeRows(..., {goals=true})` + `K.GoalData`), Amount box, goals count since login.
- Section headings via `Header` (gold). Chat via `FA.Printer`. No per-module accent colors: gold everywhere.
- Module code layout: API wrappers → skill → where → session → `ns.SkillInfo` → pick next → goals (`AddGoal`, `SetGoalWant`, `RemoveGoal`, `GoalRows`, reset on login) → log → reminder → tooltips → events → slash.
- Herbalism, Mining and Skinning are near-clones (gathering pattern); Cooking and First Aid are near-clones (crafting pattern: scan the profession window, Make now, plan + shopping list, craft log, recipe book). Fix a bug in one → check its siblings. New crafting professions start from First Aid.

## Rules
- No automation: every action needs a key press. Free, no premium, no in-game donation asks.
- Forever client 16001: use C_Item.*, C_Spell.*, C_TradeSkillUI, GetProfessions (old globals missing).
- After any change: luac -p every file, run the suite smoke test (stub harness), note it under "(unreleased)" in CHANGELOG.md. Changes land in the repo only. Version bumps happen only through tools\release.py, for the whole suite.
