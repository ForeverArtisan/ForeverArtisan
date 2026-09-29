# ForeverArtisan

Free tradeskill addons for WoW Forever. One download, one version; `ForeverArtisan_Core` is required, and each profession is its own module you can turn on or off in game (`/fa`).

Site, guides and feedback: https://foreverartisan.app

## Layout
- `ForeverArtisan_*` – the ten addon folders (the game reads these through junctions in `Interface\AddOns`).
- `docs\` – ARCHITECTURE.md (read first) and RELEASE-CHECKLIST.md.
- `tools\release.py` – sets the version in every TOC, syntax-checks, dates the changelog.
- `tools\build_crafts.py` – writes the crafting modules that share one engine (Alchemy, Leatherworking) from `tools\templates\`. Edit the template, never the generated files.

## Releasing
1. Add changes under `## x.y.z (unreleased)` at the top of `CHANGELOG.md` as you go.
2. Run the in-game checklist in `docs\RELEASE-CHECKLIST.md`.
3. `python tools\release.py . 0.9.2` – sets every TOC and dates the changelog.
4. GitHub Desktop: commit, then History > right-click the commit > Create tag `v0.9.2` > Push origin.
5. The Release workflow builds the zip and uploads it to GitHub Releases, CurseForge and Wago.

Before launch builds are `0.9.x`: they upload to the stores as Release so players can find them, and show no tag in game. Add `-beta.N` only for rough test builds (the stores hide those behind a Beta filter). Launch is `1.0.0`; after that fixes are `1.0.1`…, test builds `1.1.0-beta.1`….
