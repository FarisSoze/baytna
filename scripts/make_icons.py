"""Renders the app icon (a house whose body is a list) in its night and day versions and writes every size Android and iOS need.
Run on a machine with Edge or Chrome:  python scripts/make_icons.py"""
import os, subprocess, sys, tempfile, json, shutil
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BROWSERS = [r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe', r'C:\Program Files\Google\Chrome\Application\chrome.exe']
browser = next((b for b in BROWSERS if os.path.exists(b)), None) or sys.exit('no Edge or Chrome found')

def glyph(roof, bars, faint, dot):
    return f'''<path d="M124 228 256 118l132 110" fill="none" stroke="{roof}" stroke-width="34" stroke-linecap="round" stroke-linejoin="round"/>
<rect x="150" y="262" width="150" height="34" rx="17" fill="{bars}"/><circle cx="345" cy="279" r="17" fill="{dot}"/>
<rect x="150" y="318" width="150" height="34" rx="17" fill="{bars}" fill-opacity="{faint}"/><circle cx="345" cy="335" r="17" fill="{bars}" fill-opacity="{faint}"/>
<rect x="150" y="374" width="150" height="34" rx="17" fill="{bars}" fill-opacity="{faint}"/><circle cx="345" cy="391" r="17" fill="{bars}" fill-opacity="{faint}"/>'''

def wash(base, cols):
    spots = [('100%', '0%', '75%'), ('0%', '25%', '70%'), ('85%', '70%', '65%'), ('10%', '100%', '70%')]
    defs = ''.join(f'<radialGradient id="g{i}" cx="{x}" cy="{y}" r="{r}"><stop offset="0" stop-color="{c}"/><stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient>' for i, ((x, y, r), c) in enumerate(zip(spots, cols)))
    return f'<defs>{defs}<linearGradient id="tl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7DF0DD"/><stop offset="1" stop-color="#19B8A0"/></linearGradient></defs><rect width="512" height="512" fill="{base}"/>' + ''.join(f'<rect width="512" height="512" fill="url(#g{i})"/>' for i in range(4))

THEMES = {
    'night': (wash('#080A12', ['#1D4F8C', '#4A2E8E', '#70352B', '#136052']), glyph('#FFFFFF', '#FFFFFF', '.45', 'url(#tl)')),
    'day':   (wash('#EEF4FF', ['#9CD8FF', '#CDB3FF', '#FFD0BA', '#A9F1DC']), glyph('#0D1B2E', '#0D1B2E', '.4', '#0B8A78')),
}
def svg(inner, transparent=False):
    return f'<!doctype html><html><body style="margin:0;background:{"transparent" if transparent else "#000"}"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="1024" height="1024" style="display:block">{inner}</svg></body></html>'

tmp = tempfile.mkdtemp()
def render(name, html):
    src, out = os.path.join(tmp, name + '.html'), os.path.join(tmp, name + '.png')
    open(src, 'w', encoding='utf-8').write(html)
    subprocess.run([browser, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1', '--default-background-color=00000000',
                    '--window-size=1024,1024', f'--screenshot={out}', 'file:///' + src.replace('\\', '/')], check=True, capture_output=True, timeout=120)
    return Image.open(out).convert('RGBA')

def save(img, size, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)

def round_mask(img):
    m = Image.new('L', img.size, 0); ImageDraw.Draw(m).ellipse((0, 0, img.size[0] - 1, img.size[1] - 1), fill=255)
    out = img.copy(); out.putalpha(m); return out

RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
DENS = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
for theme, (bg, g) in THEMES.items():
    full = render(theme, svg(bg + g))
    back = render(theme + '-bg', svg(bg))
    # Adaptive icons crop to the middle two thirds, so the drawing sits at 62% in the foreground layer.
    fore = render(theme + '-fg', svg(wash('#000', ['#000'] * 4).split('<rect')[0] + f'<g transform="translate(256 256) scale(.62) translate(-256 -262)">{g}</g>', True))
    suffix = '' if theme == 'night' else '_day'
    for d, px in DENS.items():
        save(full, px, os.path.join(RES, f'mipmap-{d}', f'ic_launcher{suffix}.png'))
        save(round_mask(full), px, os.path.join(RES, f'mipmap-{d}', f'ic_launcher{suffix}_round.png'))
        save(fore, round(px * 108 / 48), os.path.join(RES, f'mipmap-{d}', f'ic_launcher{suffix}_foreground.png'))
        save(back, round(px * 108 / 48), os.path.join(RES, f'mipmap-{d}', f'ic_launcher{suffix}_background.png'))
    for shape in ('', '_round'):
        open(os.path.join(RES, 'mipmap-anydpi-v26', f'ic_launcher{suffix}{shape}.xml'), 'w', encoding='utf-8', newline='\n').write(
            f'<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@mipmap/ic_launcher{suffix}_background"/>\n    <foreground android:drawable="@mipmap/ic_launcher{suffix}_foreground"/>\n</adaptive-icon>\n')
    # iOS wants one opaque 1024 image per icon set.
    name = 'AppIcon' if theme == 'night' else 'AppIconDay'
    folder = os.path.join(ROOT, 'ios', 'App', 'App', 'Assets.xcassets', name + '.appiconset')
    os.makedirs(folder, exist_ok=True)
    full.convert('RGB').save(os.path.join(folder, 'AppIcon-512@2x.png'), optimize=True)
    json.dump({'images': [{'filename': 'AppIcon-512@2x.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}},
              open(os.path.join(folder, 'Contents.json'), 'w', encoding='utf-8'), indent=2)
    save(full, 512, os.path.join(ROOT, 'designs', f'icon-{theme}.png'))
shutil.rmtree(tmp, ignore_errors=True)
print('icons written')
