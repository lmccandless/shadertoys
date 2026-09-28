"""Build a LOCAL stand-in for Shadertoy's SDF font texture (same 16x16 layout,
same char codes, SDF in alpha: 0.5 + distance in cell units, inside < 0.5;
normal in g/b). Only used by viewer.html for offline testing; the exported
JSON binds the real Shadertoy texture (id 4dXGzr)."""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
GREEK = 'αβγδεθλμξπρστφψω' + 'ΓΔΘΛΠΣΦΨΩ∞ƒ∘∫∂∇√'
S = 256          # hi-res cell
OUT = 64         # output cell

def codepoint(i):
    if 0x80 <= i < 0xA0:
        return GREEK[i - 0x80]
    return chr(i) if i >= 0x21 and i != 0x7F and i != 0xA0 and i != 0xAD else None

font = ImageFont.truetype(FONT, int(S * 0.62))
atlas = np.zeros((16 * OUT, 16 * OUT, 4), np.uint8)
for i in range(256):
    ch = codepoint(i)
    cell = Image.new('L', (S, S), 0)
    if ch:
        d = ImageDraw.Draw(cell)
        l, t, r, b = d.textbbox((0, 0), ch, font=font)
        asc, _ = font.getmetrics()
        x = (S - (r - l)) / 2 - l
        y = 0.80 * S - asc          # baseline at 0.8 of the cell (from the top)
        d.text((x, y), ch, font=font, fill=255)
    m = np.array(cell) > 127
    if m.any():
        dist = distance_transform_edt(~m) - distance_transform_edt(m)
    else:
        dist = np.full((S, S), S * 1.0)
    dist = dist / S                              # cell units, + outside
    k = S // OUT
    ds = dist.reshape(OUT, k, OUT, k).mean(axis=(1, 3))
    gy, gx = np.gradient(ds)
    n = np.sqrt(gx * gx + gy * gy) + 1e-9
    a = np.clip(0.5 + ds, 0, 1)
    cy, cx = divmod(i, 16)
    blk = atlas[cy * OUT:(cy + 1) * OUT, cx * OUT:(cx + 1) * OUT]
    blk[..., 0] = 255
    blk[..., 1] = np.clip((gx / n * 0.5 + 0.5) * 255, 0, 255)
    blk[..., 2] = np.clip((gy / n * 0.5 + 0.5) * 255, 0, 255)
    blk[..., 3] = np.round(a * 255)
Image.fromarray(atlas, 'RGBA').save(os.path.join(ROOT, 'tools', 'font_standin.png'))
print('ok')
