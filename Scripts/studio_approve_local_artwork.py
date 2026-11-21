#!/usr/bin/env python3
"""Approve individual official artwork candidates by exact product identity.

Usage:
  python3 Scripts/studio_approve_local_artwork.py --list archive.zip
  python3 Scripts/studio_approve_local_artwork.py --approve archive.zip "Tower" 3

Never automatically approves an image. Restart LibreReplace to refresh icons.
"""
import argparse, hashlib, json, os, re, struct, tempfile, zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
group = parser.add_mutually_exclusive_group(required=True)
group.add_argument('--list', metavar='ZIP')
group.add_argument('--approve', nargs=3, metavar=('ZIP','PRODUCT','INDEX'))
args = parser.parse_args()
archive_path = Path(args.list or args.approve[0]).expanduser()
if not archive_path.is_file():
    parser.error('Archive not found')
with zipfile.ZipFile(archive_path) as z:
    if z.testzip() is not None or 'manifest.json' not in z.namelist():
        parser.error('Invalid archive')
    manifest = json.loads(z.read('manifest.json'))
    records = manifest.get('assets', [])
    if not isinstance(records, list) or len(records) > 1000:
        parser.error('Invalid candidate list')
    if args.list:
        print('OFFICIAL PRESS-KIT CANDIDATES — REVIEW BEFORE APPROVING')
        for n, r in enumerate(records):
            print(f"{n:3d}  {r['product']:<18} {r.get('dimensionsIfPNG')}  {r['candidateFile']}")
        print('\nOnly square, original, visibly correct PNG icons should be approved.')
        exit(0)
    _, product, number = args.approve
    try: r = records[int(number)]
    except (ValueError, IndexError): parser.error('Invalid candidate index. Run --list first')
    if product != r['product']:
        parser.error('Product name must exactly match the source press kit')
    rel = r['candidateFile']
    if not rel.startswith('candidates/') or '..' in Path(rel).parts or rel not in z.namelist():
        parser.error('Invalid candidate path')
    if not rel.lower().endswith('.png'):
        parser.error('Choose a PNG from this press kit')
    filename = Path(rel).name.lower()
    if not any(term in filename for term in ('icon','dock','app')):
        parser.error('Candidate filename is not an obvious application icon; review another file')
    data = z.read(rel)
    if len(data) > 12 * 1024 * 1024 or data[:8] != b'\x89PNG\r\n\x1a\n':
        parser.error('PNG must be valid and under 12 MB')
    width, height = struct.unpack('>II', data[16:24])
    if min(width, height) < 256 or abs(width-height) > max(width,height)*0.08:
        parser.error('PNG must be approximately square and at least 256 x 256')
    if hashlib.sha256(data).hexdigest() != r['sha256']:
        parser.error('Downloaded file does not match its provenance manifest')

base = Path.home()/'Library/Application Support/LibreReplace/Approved Artwork'
base.mkdir(parents=True, exist_ok=True)
meta = base/'manifest.json'
existing = json.loads(meta.read_text()) if meta.exists() else {'schemaVersion':1,'apps':{}}
if existing.get('schemaVersion') != 1 or not isinstance(existing.get('apps'), dict):
    parser.error('Existing local manifest cannot be safely updated')
key = product.lower()
if key in existing['apps']:
    parser.error('This product already has approved artwork; remove or back it up manually before replacing')
slug = re.sub(r'[^a-z0-9]+','-', key).strip('-')
name = slug+'.png'
if (base/name).exists():
    parser.error('File already exists')
sha = hashlib.sha256(data).hexdigest()
if any(item.get('sha256') == sha for item in existing['apps'].values()):
    parser.error('Identical artwork is already assigned to another product')
# Exclusive create + safe metadata replacement. No app bundles or repository edits.
fd = os.open(base/name, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
with os.fdopen(fd,'wb') as f:
    f.write(data)
    f.flush()
    os.fsync(f.fileno())
existing['apps'][key] = {'filename': name,'sha256':sha}
with tempfile.NamedTemporaryFile('w',dir=base,delete=False,prefix='.artwork-') as temp:
    json.dump(existing,temp,indent=2)
    temp.flush()
    os.fsync(temp.fileno())
    temporary = temp.name
os.replace(temporary,meta)
print(f'APPROVED: {product} — {width}×{height} pixels, SHA-256 {sha[:12]}...')
print('Restart LibreReplace to see the approved official artwork.')
