#!/usr/bin/env python3
"""Gather official vendor press-kit icon CANDIDATES for human review.

No applications are installed; no repository or system files are changed.
Downloaded press-kit artwork is not automatically approved for redistribution.
"""
from pathlib import Path
from datetime import datetime
from urllib.request import Request, urlopen
import argparse, hashlib, json, re, struct, tempfile, zipfile

SOURCES = [
    ("CleanShot X", "https://cleanshot-x.s3.eu-central-1.amazonaws.com/Presskit.zip", "https://cleanshot.com/contact"),
    ("Tower", "https://downloads.git-tower.com/press/tower-dock-icon.zip", "https://www.git-tower.com/company/press/"),
    ("TextExpander", "https://www.smilesoftware.com/assets/TextExpander_Presskit.zip", "https://www.smilesoftware.com/presskit"),
    ("iStat Menus", "https://bjango.com/images/mac/istatmenus7/istatmenus7-mediakit.zip", "https://bjango.com/mac/istatmenus/"),
    ("CleanMyMac", "https://cdn3.macpaw.com/press/cmm-media-kit.zip", "https://macpaw.com/press"),
]
MAX_KIT = 768 * 1024 * 1024  # streamed to a temporary file; never stored in RAM
MAX_FILE = 25 * 1024 * 1024
MAX_TOTAL_ASSETS = 160 * 1024 * 1024
SAFE_TYPES = (".png", ".jpg", ".jpeg", ".icns")

def png_dimensions(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return struct.unpack(">II", data[16:24])
    return (0, 0)

def fetch(url, path):
    req = Request(url, headers={"User-Agent": "LibreReplace-Press-Kit-Review/1.0"})
    with urlopen(req, timeout=35) as stream, path.open('wb') as output:
        n = 0
        while True:
            block = stream.read(256 * 1024)
            if not block:
                break
            n += len(block)
            if n > MAX_KIT:
                raise ValueError("Press kit exceeds the 768 MB streamed review limit")
            output.write(block)
    return n

parser = argparse.ArgumentParser(description="Collect private, unapproved icon candidates from vendor press kits")
parser.add_argument('--products', nargs='+', metavar='NAME', help='Only collect the specified vendor products; quote names with spaces')
args = parser.parse_args()
selected = [item for item in SOURCES if not args.products or item[0].lower() in {v.lower() for v in args.products}]
if not selected:
    parser.error('No vendor matches the requested product list')

out = Path.home() / "Downloads" / ("LibreReplace-Official-Artwork-Review-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
out.mkdir(parents=True, exist_ok=False)
assets = out / "candidates"
assets.mkdir()
records, errors = [], []
asset_bytes = 0
for title, kit_url, source_page in selected:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip('-')
    print("Downloading official", title, "press kit...")
    with tempfile.TemporaryDirectory(prefix="lr-official-icon-") as tmp:
        kit = Path(tmp) / "press-kit.zip"
        try:
            size = fetch(kit_url, kit)
            if not zipfile.is_zipfile(kit):
                raise ValueError("Vendor URL did not return a ZIP file")
            with zipfile.ZipFile(kit) as archive:
                # Selected entries are CRC-checked when read. Avoid decompressing
                # unrelated video/marketing files in a very large vendor archive.
                files = [i for i in archive.infolist()
                         if not i.is_dir()
                         and Path(i.filename).suffix.lower() in SAFE_TYPES
                         and i.file_size <= MAX_FILE
                         and i.file_size > 0
                         and not (i.external_attr >> 16 & 0o170000) == 0o120000
                         and not Path(i.filename).is_absolute()
                         and '..' not in Path(i.filename).parts
                         and '__MACOSX' not in Path(i.filename).parts
                         and not Path(i.filename).name.startswith('._')]
                files.sort(key=lambda i: ("icon" not in i.filename.lower(),
                                          "dock" not in i.filename.lower(),
                                          "app" not in i.filename.lower(),
                                          i.filename.lower()))
                for num, entry in enumerate(files[:100]):
                    if asset_bytes + entry.file_size > MAX_TOTAL_ASSETS:
                        break
                    data = archive.read(entry)
                    dimension = png_dimensions(data)
                    if entry.filename.lower().endswith('.png') and (min(dimension) < 128):
                        continue
                    basename = re.sub(r"[^a-zA-Z0-9._-]+", "-", Path(entry.filename).name)[:90]
                    rel = f"candidates/{slug}-{num:03d}-{basename}"
                    (out / rel).write_bytes(data)
                    asset_bytes += len(data)
                    records.append({"product": title, "sourcePage": source_page,
                                    "kitURL": kit_url, "kitDownloadBytes": size,
                                    "archiveEntry": entry.filename, "candidateFile": rel,
                                    "dimensionsIfPNG": dimension,
                                    "sha256": hashlib.sha256(data).hexdigest(),
                                    "reviewStatus": "UNREVIEWED - confirm actual app icon and usage terms"})
        except Exception as exc:
            errors.append({"product": title, "url": kit_url, "error": str(exc)})
            print("  Could not collect:", exc)

(out / "manifest.json").write_text(json.dumps({"created": datetime.now().isoformat(),
    "assets": records, "errors": errors, "note": "These are exact downloaded vendor files, not automatically validated icons or cleared for redistribution."}, indent=2))
(out / "READ_ME.txt").write_text("LibreReplace official press-kit asset candidates.\nThese files are for review and selection, NOT automatic publication or use.\nCheck which PNG is the real app icon, its dimensions and the vendor's branding terms.\n")
zip_path = out.with_suffix('.zip')
with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in out.rglob('*'):
        if path.is_file():
            archive.write(path, path.relative_to(out))
with zipfile.ZipFile(zip_path) as archive:
    assert archive.testzip() is None
print("\nCollected", len(records), "candidate files from", len(selected) - len(errors), "vendors")
print("Output ZIP:", zip_path)
print("Upload that ZIP for visual verification. No apps or repository files were changed.")
