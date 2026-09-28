#!/usr/bin/env python3
"""ForeverArtisan release helper: one version, one download for the whole suite.

usage (from the repo):  python tools\\release.py . 0.9.1-beta.1\n\nusage: release.py SOURCE_DIR VERSION [--package RELEASES_DIR] ["changelog line" ...]

  SOURCE_DIR    folder that holds the ForeverArtisan_* addon folders
  VERSION       1.2.3 or 1.2.3-beta.1
                  0.x.x          -> Beta   (everything before launch)
                  x.y.z-beta.N   -> Beta   (test builds after launch)
                  1.0.0 and up   -> Release
  --package DIR build the download zip into DIR/Beta or DIR/Release

What it does:
- sets "## Version: VERSION" in every ForeverArtisan_*/*.toc (Core and all modules)
- syntax-checks every .lua file (luac5.1 -p, if installed)
- dates CHANGELOG.md in SOURCE_DIR: renames the "## x.y.z (unreleased)" section to VERSION,
  or adds a new section with the changelog lines given
- with --package: writes ForeverArtisan-VERSION.zip with every ForeverArtisan_* folder
  at the top of the zip (what CurseForge/Wago expect; players unzip into Interface\\AddOns),
  plus a copy of the changelog next to it
"""
import datetime, glob, os, re, shutil, subprocess, sys, zipfile

VERSION_RE = r"\d+\.\d+\.\d+(-beta\.\d+)?"

# Dev tools that never go in the public download. They get their own zip in DIR/Private.
PRIVATE = []  # e.g. ["ForeverArtisan_SomeDevTool"]


def channel(ver):
    return "Beta" if ver.startswith("0.") or "-beta" in ver else "Release"


def set_versions(root, ver):
    tocs = sorted(glob.glob(os.path.join(root, "ForeverArtisan_*", "ForeverArtisan_*.toc")))
    if not tocs:
        sys.exit("no ForeverArtisan_* folders under " + root)
    for t in tocs:
        s = open(t, encoding="utf-8").read()
        s2, n = re.subn(r"^## Version: .*$", "## Version: " + ver, s, flags=re.M)
        if n != 1:
            sys.exit("no single ## Version line in " + t)
        open(t, "w", encoding="utf-8", newline="\n").write(s2)
        print("  %-45s %s" % (os.path.basename(t), ver))


def check_syntax(root):
    luac = shutil.which("luac5.1") or shutil.which("luac")
    if not luac:
        print("syntax: skipped (no luac)")
        return
    bad = 0
    for f in sorted(glob.glob(os.path.join(root, "ForeverArtisan_*", "*.lua"))):
        r = subprocess.run([luac, "-p", f], capture_output=True, text=True)
        if r.returncode:
            bad += 1
            print("SYNTAX ERROR", r.stderr.strip())
    print("syntax:", "OK" if not bad else "%d file(s) failed" % bad)
    if bad:
        sys.exit(1)


def add_changelog(root, ver, notes):
    """Dates the changelog. An '## x.y.z (unreleased)' section is renamed to this version;
    otherwise a new section is added. Changelog lines given on the command line are appended."""
    log = os.path.join(root, "CHANGELOG.md")
    old = open(log, encoding="utf-8").read() if os.path.exists(log) else "# ForeverArtisan changelog\n"
    title = "## %s (%s)" % (ver, datetime.date.today().isoformat())
    lines = "".join("- %s\n" % n for n in notes)
    if ("\n## %s " % ver) in old:
        print("changelog: %s already listed, left as is" % ver)
        return
    m = re.search(r"^## [^\n]*\(unreleased\)[^\n]*\n", old, flags=re.M)
    if m:
        body_end = old.find("\n## ", m.end())
        body_end = len(old) if body_end < 0 else body_end + 1
        body = old[m.end():body_end].rstrip("\n") + "\n" + lines
        new = old[:m.start()] + title + "\n" + body + "\n" + old[body_end:]
        print("changelog: unreleased section is now", ver)
    else:
        head, _, rest = old.partition("\n")
        new = head + "\n\n" + title + "\n" + lines + rest
        print("changelog: added", ver)
    open(log, "w", encoding="utf-8").write(new)


def _zip(zpath, root, folders):
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for d in folders:
            for dirpath, dirnames, files in os.walk(d):
                dirnames[:] = [x for x in dirnames if not x.startswith(".")]
                for fn in sorted(files):
                    if fn.startswith(".") or fn.endswith((".bak", ".tmp")):
                        continue
                    full = os.path.join(dirpath, fn)
                    z.write(full, os.path.relpath(full, root).replace(os.sep, "/"))


def package(root, ver, out_root):
    out_dir = os.path.join(out_root, channel(ver))
    os.makedirs(out_dir, exist_ok=True)
    folders = sorted(d for d in glob.glob(os.path.join(root, "ForeverArtisan_*")) if os.path.isdir(d))
    public = [d for d in folders if os.path.basename(d) not in PRIVATE]
    private = [d for d in folders if os.path.basename(d) in PRIVATE]
    zpath = os.path.join(out_dir, "ForeverArtisan-%s.zip" % ver)
    _zip(zpath, root, public)
    log = os.path.join(root, "CHANGELOG.md")
    if os.path.exists(log):
        shutil.copy(log, os.path.join(out_dir, "CHANGELOG.md"))
    print("package: %s (%d addon folders, %s)" % (zpath, len(public), channel(ver)))
    print("         " + ", ".join(os.path.basename(d) for d in public))
    for d in private:
        pdir = os.path.join(out_root, "Private")
        os.makedirs(pdir, exist_ok=True)
        ppath = os.path.join(pdir, "%s-%s.zip" % (os.path.basename(d), ver))
        _zip(ppath, root, [d])
        print("private: %s (dev tool, do not upload)" % ppath)
    return zpath


def main():
    args = sys.argv[1:]
    out = None
    if "--package" in args:
        i = args.index("--package")
        out = args[i + 1]
        del args[i:i + 2]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    root, ver, notes = args[0], args[1], args[2:]
    if not re.fullmatch(VERSION_RE, ver):
        sys.exit("version must look like 0.9.0 or 1.1.0-beta.1")
    print("ForeverArtisan %s  (%s)" % (ver, channel(ver)))
    set_versions(root, ver)
    check_syntax(root)
    add_changelog(root, ver, notes)
    if out:
        package(root, ver, out)
    if ver.startswith("0.") and "-beta" not in ver:
        print("WARNING: tag v%s would upload to CurseForge/Wago as a RELEASE. Use %s-beta.1 before launch." % (ver, ver))
    print("next: commit in GitHub Desktop, then tag the commit v%s and push origin" % ver)


if __name__ == "__main__":
    main()
