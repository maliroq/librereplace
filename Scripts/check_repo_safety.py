#!/usr/bin/env python3
import pathlib, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
SKIP = {".git", ".build", "build", ".swiftpm", "DerivedData", "artifacts", "__pycache__", "LibreReplace.xcodeproj"}
problems=[]
for obsolete in ("Launch", "Research"):
    if (ROOT / obsolete).exists():
        problems.append(f"obsolete internal directory present: {obsolete}")
for path in ROOT.rglob("*"):
    if not path.is_file() or any(part in SKIP for part in path.parts): continue
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
