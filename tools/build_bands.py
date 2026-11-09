#!/usr/bin/env python3
"""Builds ForeverArtisan_Core/RecipeBandsData.lua: where each recipe turns yellow and gray, from the
game's own recipe data (the SkillLineAbility table). The game only tells addons the gray point, so
without this the plans guess where yellow and green start.

  python3 tools/build_bands.py <SkillLineAbility.csv> [repo folder]

Get the CSV for the current Forever build from
  https://wago.tools/db2/SkillLineAbility/csv?build=<build>
(the build is on the login screen, bottom left, or in "World of Warcraft/.build.info"; product wowf).
TrivialSkillLineRankLow is where yellow starts, TrivialSkillLineRankHigh where gray starts; green
starts halfway between them. Rerun after a patch. Never edit the output by hand.
"""
import csv, os, re, sys

SKILL_LINES = {171: "Alchemy", 164: "Blacksmithing", 185: "Cooking", 333: "Enchanting",
               202: "Engineering", 129: "First Aid", 165: "Leatherworking", 197: "Tailoring"}

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src, repo = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else ".")
    build = re.search(r"(\d+\.\d+\.\d+\.\d+)", os.path.basename(src))
    bands, counts = {}, {}
    with open(src, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            line = int(r["SkillLine"] or 0)
            if line not in SKILL_LINES:
                continue
            spell, lo, hi = int(r["Spell"]), int(r["TrivialSkillLineRankLow"] or 0), int(r["TrivialSkillLineRankHigh"] or 0)
            if spell <= 0 or lo <= 0 or hi <= 0 or lo > hi:
                continue
            bands[spell] = (lo, hi)
            counts[SKILL_LINES[line]] = counts.get(SKILL_LINES[line], 0) + 1
    out = os.path.join(repo, "ForeverArtisan_Core", "RecipeBandsData.lua")
    with open(out, "w", encoding="utf-8", newline="\n") as w:
        w.write("-- Copyright (c) 2026 ForeverArtisan. All rights reserved.\n")
        w.write("-- ForeverArtisan: Core: where each recipe turns yellow and gray, from the game's recipe data\n")
        w.write("-- (SkillLineAbility%s). [spell id] = { yellow at, gray at }; green starts halfway.\n" % (", build " + build.group(1) if build else ""))
        w.write("-- Made by tools/build_bands.py. Never edit by hand; rerun it after a patch.\n")
        w.write("ForeverArtisan.RECIPE_BANDS = {\n")
        for spell in sorted(bands):
            lo, hi = bands[spell]
            w.write("  [%d]={%d,%d},\n" % (spell, lo, hi))
        w.write("}\n")
    for k in sorted(counts):
        print("%-15s %4d recipes" % (k, counts[k]))
    print("wrote", out, "(%d recipes)" % len(bands))

if __name__ == "__main__":
    main()
