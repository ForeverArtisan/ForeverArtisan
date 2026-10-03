"""Writes the crafting modules that share the First Aid engine (Alchemy, Leatherworking, Blacksmithing,
Tailoring, Engineering, Enchanting).

usage (from the repo):  python tools\\build_crafts.py .

Each profession's settings live in CRAFTS below. The engine and window live in
tools/templates/Craft.lua.tpl and UI.lua.tpl. Fix a bug there once, run this, and every
crafting module gets it. Never hand-edit the generated ForeverArtisan_<Name>/*.lua files.
The version in each TOC is copied from ForeverArtisan_Core so the suite stays on one number.
"""
import os
import re
import sys

CRAFTS = [
    {
        "ID": "Alchemy", "NAME": "Alchemy", "LINE": 171,
        "SLASH": "FAALCH", "SLASHCMD": "/faalch", "ALIAS": "alch",
        "DB": "ForeverArtisanAlchemyDB", "FLAG": "faAlchDone",
        "GROUPS": ["alchemy", "potion", "elixir", "flask", "transmute"],
        "PREFIXES": ["Recipe: "],
        "SKIP": "^Transmute",
        "SUBEXAMPLE": "anything one of your recipes makes",
        "EMPTYLOG": "Nothing made yet. Grab some herbs and vials!",
        "NOTES": "What to make next for skill-ups, a plan and shopping list to your target skill "
                 "(herbs point to your Herbalism log), a craft log, where to train next, and material tooltips.",
        "ADVICE": {
            "Horde": {
                75: "Journeyman: any Alchemy trainer (needs 50, level 10).",
                150: "Expert: an Alchemy trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: Rogvar, Stonard, Swamp of Sorrows (needs 200, level 35). Classic answer, not confirmed in Forever.",
                300: "Top rank. Nothing left to train.",
            },
            "Alliance": {
                75: "Journeyman: any Alchemy trainer (needs 50, level 10).",
                150: "Expert: an Alchemy trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: Ainethil, Darnassus (needs 200, level 35). Classic answer, not confirmed in Forever.",
                300: "Top rank. Nothing left to train.",
            },
        },
    },
    {
        "ID": "Leatherworking", "NAME": "Leatherworking", "LINE": 165,
        "SLASH": "FALW", "SLASHCMD": "/falw", "ALIAS": "lw",
        "DB": "ForeverArtisanLeatherworkingDB", "FLAG": "faLwDone",
        "GROUPS": ["leatherworking", "leather", "armor kit", "quiver", "ammo pouch", "cured"],
        "PREFIXES": ["Pattern: "],
        "SKIP": None,
        "SUBEXAMPLE": "cured hides",
        "EMPTYLOG": "Nothing made yet. Grab some leather and thread!",
        "NOTES": "What to make next for skill-ups, a plan and shopping list to your target skill "
                 "(cured hides counted as crafts, leather points to your Skinning log), a craft log, "
                 "where to train next, and material tooltips.",
        "ADVICE": {
            "Horde": {
                75: "Journeyman: any Leatherworking trainer (needs 50, level 10).",
                150: "Expert: a Leatherworking trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: Hahrana Ironhide, Camp Mojache, Feralas (needs 200, level 35). Classic answer, not confirmed in Forever.",
                300: "Top rank. Nothing left to train.",
            },
            "Alliance": {
                75: "Journeyman: any Leatherworking trainer (needs 50, level 10).",
                150: "Expert: a Leatherworking trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: Drakk Stonehand, Aerie Peak, The Hinterlands (needs 200, level 35). Classic answer, not confirmed in Forever.",
                300: "Top rank. Nothing left to train.",
            },
        },
    },
    {
        "ID": "Blacksmithing", "NAME": "Blacksmithing", "LINE": 164,
        "SLASH": "FABS", "SLASHCMD": "/fabs", "ALIAS": "bs",
        "DB": "ForeverArtisanBlacksmithingDB", "FLAG": "faBsDone",
        "GROUPS": ["blacksmithing", "sharpening", "weightstone", "plate", "sword", "axe", "mace", "buckle"],
        "PREFIXES": ["Plans: "],
        "SKIP": None,
        "SUBEXAMPLE": "grinding stones",
        "EMPTYLOG": "Nothing made yet. Grab some bars and stone!",
        "NOTES": "What to make next for skill-ups, a plan and shopping list to your target skill "
                 "(ore and stone point to your Mining log), a craft log, where to train next, and material tooltips.",
        "ADVICE": {
            "Horde": {
                75: "Journeyman: any Blacksmithing trainer (needs 50, level 10).",
                150: "Expert: a Blacksmithing trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: ask a capital-city guard for an Artisan Blacksmithing trainer (needs 200, level 35).",
                300: "Top rank. Nothing left to train.",
            },
            "Alliance": {
                75: "Journeyman: any Blacksmithing trainer (needs 50, level 10).",
                150: "Expert: a Blacksmithing trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: ask a capital-city guard for an Artisan Blacksmithing trainer (needs 200, level 35).",
                300: "Top rank. Nothing left to train.",
            },
        },
    },
    {
        "ID": "Tailoring", "NAME": "Tailoring", "LINE": 197,
        "SLASH": "FATAILOR", "SLASHCMD": "/fatailor", "ALIAS": "tailor",
        "DB": "ForeverArtisanTailoringDB", "FLAG": "faTailorDone",
        "GROUPS": ["tailoring", "cloth", "robe", "shirt", "bag", "bolt", "cloak"],
        "PREFIXES": ["Pattern: "],
        "SKIP": "^Mooncloth$",
        "SUBEXAMPLE": "bolts of cloth",
        "EMPTYLOG": "Nothing made yet. Grab some cloth and thread!",
        "NOTES": "What to make next for skill-ups, a plan and shopping list to your target skill "
                 "(bolts of cloth counted as crafts), a craft log, where to train next, and material tooltips.",
        "ADVICE": {
            "Horde": {
                75: "Journeyman: any Tailoring trainer (needs 50, level 10).",
                150: "Expert: a Tailoring trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: ask a capital-city guard for an Artisan Tailoring trainer (needs 200, level 35).",
                300: "Top rank. Nothing left to train.",
            },
            "Alliance": {
                75: "Journeyman: any Tailoring trainer (needs 50, level 10).",
                150: "Expert: a Tailoring trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: ask a capital-city guard for an Artisan Tailoring trainer (needs 200, level 35).",
                300: "Top rank. Nothing left to train.",
            },
        },
    },
    {
        "ID": "Engineering", "NAME": "Engineering", "LINE": 202,
        "SLASH": "FAENG", "SLASHCMD": "/faeng", "ALIAS": "eng",
        "DB": "ForeverArtisanEngineeringDB", "FLAG": "faEngDone",
        "GROUPS": ["engineering", "explosive", "device", "goggles", "gun", "scope", "parts", "bomb"],
        "PREFIXES": ["Schematic: "],
        "SKIP": None,
        "SUBEXAMPLE": "blasting powder, bolts and tubes",
        "EMPTYLOG": "Nothing made yet. Grab some bars and stone!",
        "NOTES": "What to make next for skill-ups, a plan and shopping list to your target skill "
                 "(powders, bolts and tubes counted as crafts, ore points to your Mining log), a craft log, "
                 "where to train next, and material tooltips.",
        "ADVICE": {
            "Horde": {
                75: "Journeyman: any Engineering trainer (needs 50, level 10).",
                150: "Expert: a Engineering trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: ask a capital-city guard for an Artisan Engineering trainer (needs 200, level 35).",
                300: "Top rank. Nothing left to train.",
            },
            "Alliance": {
                75: "Journeyman: any Engineering trainer (needs 50, level 10).",
                150: "Expert: a Engineering trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: ask a capital-city guard for an Artisan Engineering trainer (needs 200, level 35).",
                300: "Top rank. Nothing left to train.",
            },
        },
    },
    {
        "ID": "Enchanting", "NAME": "Enchanting", "LINE": 333,
        "SLASH": "FAENCH", "SLASHCMD": "/faench", "ALIAS": "ench",
        "DB": "ForeverArtisanEnchantingDB", "FLAG": "faEnchDone",
        "GROUPS": ["enchanting", "enchant", "oil", "wand", "rod"],
        "PREFIXES": ["Formula: "],
        "SKIP": None,
        "SUBEXAMPLE": "runed rods",
        "EMPTYLOG": "Nothing enchanted yet. Disenchant some greens for dust!",
        "NOTES": "What to enchant next for skill-ups, a plan and shopping list to your target skill "
                 "(dust and essences from disenchanting), a craft log, where to train next, and material tooltips.",
        "ADVICE": {
            "Horde": {
                75: "Journeyman: any Enchanting trainer (needs 50, level 10).",
                150: "Expert: a Enchanting trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: ask a capital-city guard for an Artisan Enchanting trainer (needs 200, level 35).",
                300: "Top rank. Nothing left to train.",
            },
            "Alliance": {
                75: "Journeyman: any Enchanting trainer (needs 50, level 10).",
                150: "Expert: a Enchanting trainer in a capital city (needs 125, level 20). Classic answer, not confirmed in Forever.",
                225: "Artisan: ask a capital-city guard for an Artisan Enchanting trainer (needs 200, level 35).",
                300: "Top rank. Nothing left to train.",
            },
        },
    },
]

# icon in the game's AddOns list
ICONS = {'Alchemy': 'Trade_Alchemy', 'Blacksmithing': 'Trade_BlackSmithing', 'Enchanting': 'Trade_Engraving', 'Engineering': 'Trade_Engineering', 'Leatherworking': 'INV_Misc_ArmorKit_17', 'Tailoring': 'Trade_Tailoring'}

TOC = """## Interface: 16001
## Title: ForeverArtisan: {NAME}
## IconTexture: Interface\\Icons\\{ICON}
## Notes: {NOTES}
## Author: ForeverArtisan
## Version: {VERSION}
## X-Copyright: Copyright (c) 2026 ForeverArtisan. All rights reserved.
## X-Website: https://foreverartisan.app
## Dependencies: ForeverArtisan_Core
## OptionalDeps: ForeverArtisan_Contacts, ForeverArtisan_Herbalism, ForeverArtisan_Skinning, ForeverArtisan_Mining, ForeverArtisan_Fishing
## SavedVariables: {DB}
## X-FA-Slash: {SLASH}
## X-FA-Alias: {ALIAS}

{ID}.lua
UI.lua
"""


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_list(items):
    return "{ " + ", ".join(lua_str(x) for x in items) + " }"


def advice_block(adv):
    out = []
    for faction in ("Horde", "Alliance"):
        out.append("  %s = {" % faction)
        for k in sorted(adv[faction]):
            out.append("    [%d]%s= %s," % (k, " " * (4 - len(str(k))), lua_str(adv[faction][k])))
        out.append("  },")
    return "\n".join(out)


def render(tpl, c):
    subs = {
        "ID": c["ID"], "NAME": c["NAME"], "ICON": ICONS[c["ID"]], "LINE": str(c["LINE"]), "SLASH": c["SLASH"],
        "SLASHCMD": c["SLASHCMD"], "ALIAS": c["ALIAS"], "DB": c["DB"], "FLAG": c["FLAG"],
        "GROUPS": lua_list(c["GROUPS"]), "PREFIXES": lua_list(c["PREFIXES"]),
        "SKIP": lua_str(c["SKIP"]) if c["SKIP"] else "nil",
        "SUBEXAMPLE": c["SUBEXAMPLE"], "EMPTYLOG": c["EMPTYLOG"],
        "ADVICE": advice_block(c["ADVICE"]),
    }
    out = re.sub(r"@@([A-Z]+)@@", lambda m: subs[m.group(1)], tpl)
    left = re.findall(r"@@[A-Z]+@@", out)
    if left:
        sys.exit("unfilled placeholders: %s" % left)
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    here = os.path.join(root, "tools", "templates")
    engine = open(os.path.join(here, "Craft.lua.tpl"), encoding="utf-8").read()
    ui = open(os.path.join(here, "UI.lua.tpl"), encoding="utf-8").read()
    core_toc = open(os.path.join(root, "ForeverArtisan_Core", "ForeverArtisan_Core.toc"), encoding="utf-8").read()
    version = re.search(r"^## Version: (.+?)\s*$", core_toc, re.M).group(1)
    for c in CRAFTS:
        folder = os.path.join(root, "ForeverArtisan_" + c["ID"])
        os.makedirs(folder, exist_ok=True)
        files = {
            c["ID"] + ".lua": render(engine, c),
            "UI.lua": render(ui, c),
            "ForeverArtisan_%s.toc" % c["ID"]: TOC.format(VERSION=version, ICON=ICONS[c["ID"]], **c),
        }
        for name, text in files.items():
            with open(os.path.join(folder, name), "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
        print("wrote ForeverArtisan_%s (%s)" % (c["ID"], ", ".join(sorted(files))))


if __name__ == "__main__":
    main()
