#!/usr/bin/env python3
"""Collect review candidates for missing LibreReplace icons from each vendor's site.

No auto-approvals: a web site's icon or open-graph image is NOT necessarily
its app's Dock icon. The output is a private contact sheet and provenance ZIP,
compatible with studio_approve_local_artwork.py when product and image agree.
Does not install applications or write to the LibreReplace source tree.
"""
from __future__ import annotations
import argparse
import concurrent.futures
import datetime
import hashlib
import html
from html.parser import HTMLParser
import json
import re
import struct
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAX_PAGE = 2 * 1024 * 1024
MAX_IMAGE = 8 * 1024 * 1024
PNG_HEADER = b'\x89PNG\r\n\x1a\n'
UA = 'LibreReplaceArtworkAudit/1.0 (user-initiated private review)'

class PageImages(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []
    def handle_starttag(self, tag, attrs):
        attrs = {key.lower(): (value or '') for key, value in attrs if key}
        if tag == 'link':
            rel = attrs.get('rel', '').lower()
            href = attrs.get('href', '')
            if 'apple-touch-icon' in rel:
                self.links.append((0, 'apple-touch-icon', href))
            elif 'icon' in rel and ('192' in attrs.get('sizes', '') or '256' in attrs.get('sizes', '') or '512' in attrs.get('sizes', '')):
                self.links.append((1, 'large-site-icon', href))
        elif tag == 'meta':
            prop = attrs.get('property', attrs.get('name', '')).lower()
            if prop in ('og:image', 'twitter:image'):
                self.links.append((2, 'social-preview', attrs.get('content', '')))

def fetch(url: str, limit: int) -> bytes:
    if urllib.parse.urlparse(url).scheme != 'https':
        raise ValueError('Only HTTPS URLs are accepted')
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': 'image/png,image/*;q=0.9,text/html;q=0.8'})
    with urllib.request.urlopen(req, timeout=9) as res:
        if urllib.parse.urlparse(res.geturl()).scheme != 'https':
            raise ValueError('Redirected to non-HTTPS URL')
        data = res.read(limit + 1)
        if len(data) > limit:
            raise ValueError('Content exceeds size limit')
        return data

def png_dimensions(data):
    if len(data) < 33 or data[:8] != PNG_HEADER or data[12:16] != b'IHDR':
        return None
    w, h = struct.unpack('>II', data[16:24])
    if min(w, h) < 256 or max(w,h) > 8192 or abs(w-h) > max(w,h)*0.08:
        return None
    return (w,h)

def safe_slug(text):
    return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')[:65]

def candidate_links(page, base):
    p = PageImages()
    try: p.feed(page.decode('utf-8', errors='replace'))
    except Exception: return []
    seen = set(); links = []
    for _, role, href in sorted(p.links):
        url = urllib.parse.urljoin(base, html.unescape(href))
        obj = urllib.parse.urlparse(url)
        if obj.scheme != 'https' or not obj.hostname or url in seen:
            continue
        seen.add(url); links.append((role,url))
    return links[:6]

def process_product(entry):
    name, metadata = entry
    url = metadata.get('sourcePage')
    if not isinstance(url, str) or not url.startswith('https://'):
        return name, [], 'No official HTTPS page'
    try: page = fetch(url, MAX_PAGE)
    except Exception as exc: return name, [], 'Website: ' + str(exc)[:90]
    images = []
    for role, image_url in candidate_links(page, url):
        if len(images) >= 3: break
        try:
            data = fetch(image_url, MAX_IMAGE)
            size = png_dimensions(data)
            if not size: continue
            images.append({'data': data, 'sourceURL': image_url, 'role': role, 'dimensions': list(size)})
        except Exception: continue
    return name, images, '' if images else 'No qualifying square PNG found on vendor page'

def build_catalog_review(root, out, limit=100):
    catalog = json.loads((root / 'Catalog/app_artwork.json').read_text())['apps']
    # Restricted third-party artwork remains out of automated acquisition.
    targets = [(name, entry) for name,entry in catalog.items()
               if entry.get('artworkStatus') == 'unverified'][:limit]
    out.mkdir(parents=True, exist_ok=True)
    (out/'candidates').mkdir(exist_ok=True)
    manifest = {'schemaVersion':1, 'source': 'individual vendor website icon/metadata candidates; each requires visual review', 'assets':[]}
    report = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for name, images, issue in pool.map(process_product, targets):
            report.append({'product':name, 'candidates':len(images),'reasonIfNone':issue})
            for index, result in enumerate(images):
                digest = hashlib.sha256(result['data']).hexdigest()
                filename = f'{safe_slug(name)}-app-icon-candidate-{index:02d}-{digest[:10]}.png'
                relative = 'candidates/'+filename
                (out/relative).write_bytes(result['data'])
                manifest['assets'].append({'product':name,'candidateFile':relative,'dimensionsIfPNG':result['dimensions'],
                   'sha256':digest, 'sourceURL':result['sourceURL'], 'discovery':result['role'], 'reviewed':False})
    # The existing review tool requires an exact product name, so preserve it as the brand's catalog name.
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2))
    (out/'coverage.json').write_text(json.dumps(report,indent=2))
    cards = []
    for i, item in enumerate(manifest['assets']):
        cards.append('<figure><img loading="lazy" src="'+html.escape(item['candidateFile'],quote=True)+'"><figcaption><b>'+html.escape(item['product'])+'</b><div>Candidate '+str(i)+' · '+html.escape(item['discovery'])+'</div><small>'+html.escape(item['sourceURL'])+'</small></figcaption></figure>')
    (out/'REVIEW.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>LibreReplace — Catalog Artwork Candidates</title><style>body{font:15px system-ui;background:#18191c;color:#eee;padding:24px}h1{font-size:27px}p{max-width:850px;color:#b9bac0}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:14px}figure{margin:0;background:#27282e;border-radius:16px;padding:16px}img{display:block;width:170px;height:170px;object-fit:contain;margin:auto}figcaption{padding-top:12px}small{overflow-wrap:anywhere;color:#9ba0ad}</style><h1>Catalog artwork candidates</h1><p>These are not automatically accepted as application icons. Images were discovered on the official product sites, but may be website or marketing graphics. Visually verify the exact app identity before approving any.</p><main>'+''.join(cards)+'</main></html>')
    zip_path = out.with_suffix('.zip')
    with zipfile.ZipFile(zip_path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in out.rglob('*'):
            if file.is_file(): z.write(file,file.relative_to(out))
    with zipfile.ZipFile(zip_path) as z:
        if z.testzip() is not None: raise RuntimeError('ZIP integrity check failed')
    return len(targets), len(manifest['assets']), zip_path

if __name__ == '__main__':
    arg = argparse.ArgumentParser(description=__doc__)
    arg.add_argument('--limit',type=int,default=100,help='Maximum number of missing vendor pages to inspect (1–100)')
    options = arg.parse_args()
    if not 1 <= options.limit <= 100: arg.error('--limit must be from 1 to 100')
    date = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    out = Path.home()/'Downloads'/('LibreReplace-Full-Catalog-Artwork-Review-'+date)
    print('Reviewing up to',options.limit,'missing product-icon sources; no app settings will change.')
    count, assets, zip_path = build_catalog_review(ROOT, out, options.limit)
    print('\nVendor pages examined:',count)
    print('Square PNG candidates:',assets)
    print('Open REVIEW.html in the created folder to inspect before approval.')
    print('Review ZIP:',zip_path)
    print('No assets were approved, and no application or source files were modified.')
