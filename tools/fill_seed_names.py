#!/usr/bin/env python3
# Fill reagent names the live client hadn't loaded ("item:6361") in every SeedRecipes.lua, from the
# game's own item data (ItemSparse.csv from wago.tools, same build). Run after tools/build_recipes.lua.
#   python3 tools/fill_seed_names.py . path/to/ItemSparse.csv
import csv, glob, os, re, sys

root, sparse = sys.argv[1], sys.argv[2]
names = {}
with open(sparse, newline="", encoding="utf-8") as fh:
    for r in csv.DictReader(fh):
        n = (r.get("Display_lang") or "").strip()
        if n:
            names[r["ID"]] = n

def lua_str(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')

total = left = 0
for path in sorted(glob.glob(os.path.join(root, "ForeverArtisan_*", "SeedRecipes.lua"))):
    text = open(path, encoding="utf-8").read()
    def fix(m):
        global total, left
        iid = m.group(1)
        n = names.get(iid)
        if n:
            total += 1
            return '[%s]="%s",' % (iid, lua_str(n))
        left += 1
        return m.group(0)
    new = re.sub(r'\[(\d+)\]="item:\1",', fix, text)
    if new != text:
        open(path, "w", encoding="utf-8", newline="").write(new)
print("filled %d names, %d still unknown" % (total, left))
