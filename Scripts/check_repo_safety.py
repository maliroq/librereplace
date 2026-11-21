#!/usr/bin/env python3
import os, pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
SKIP = {".git", ".build", "build", ".swiftpm", "DerivedData", "artifacts", "__pycache__", "LibreReplace.xcodeproj", ".LibreReplaceLaunchBuild"}
problems=[]
for obsolete in ("Launch", "Research"):
    if (ROOT / obsolete).exists():
        problems.append(f"obsolete internal directory present: {obsolete}")
for folder, dirs, names in os.walk(ROOT, topdown=True, followlinks=False):
    directory = pathlib.Path(folder)
    dirs[:] = [name for name in dirs if name not in SKIP and not (directory / name).is_symlink()]
    for name in names:
        path = directory / name
        if not path.is_file() or path.is_symlink() or path.name in SKIP: continue
        if path.resolve() == pathlib.Path(__file__).resolve(): continue
        if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".zip", ".pyc"}: continue
        try: text=path.read_text(errors="ignore")
        except Exception: continue
        if re.search(r"/Users/[^/\s]+/", text): problems.append(f"absolute user path in {path.relative_to(ROOT)}")
        if "shell -c" in text or "/bin/sh -c" in text: problems.append(f"shell execution pattern in {path.relative_to(ROOT)}")
if problems:
    print("Repository safety check failed:")
    for p in problems: print(" -",p)
    sys.exit(1)
print("Repository safety check OK")
