#!/usr/bin/env python3
"""compare.py REFERENCE RENDER OUT [x0 y0 x1 y1 [scale]]

Writes a three-panel study sheet: reference | render | 50% blend (with the reference's edges
in red over the render), optionally cropped and enlarged. Prints per-cell mean-colour error on a
coarse grid so palette drift can be tracked numerically as the shader changes.
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

ref_p, ren_p, out_p = sys.argv[1:4]
box = tuple(map(int, sys.argv[4:8])) if len(sys.argv) >= 8 else None
scale = float(sys.argv[8]) if len(sys.argv) >= 9 else 1.0

ref = Image.open(ref_p).convert('RGB')
ren = Image.open(ren_p).convert('RGB').resize(ref.size, Image.LANCZOS)

# coarse palette report (mean absolute colour difference per 100x100 cell, plus luma bias)
a = np.asarray(ref).astype(float) / 255
b = np.asarray(ren).astype(float) / 255
h, w, _ = a.shape
cell = 100
rows = []
for cy in range(0, h, cell):
    row = []
    for cx in range(0, w, cell):
        d = b[cy:cy+cell, cx:cx+cell].mean((0, 1)) - a[cy:cy+cell, cx:cx+cell].mean((0, 1))
        row.append(f"{d[0]:+.2f}{d[1]:+.2f}{d[2]:+.2f}")
    rows.append(' '.join(row))
print('mean RGB error per 100px cell (render - reference):')
print('\n'.join(rows))
print(f'overall blurred RMSE: {np.sqrt(((np.asarray(ref.filter(ImageFilter.GaussianBlur(6))).astype(float) - np.asarray(ren.filter(ImageFilter.GaussianBlur(6))).astype(float))**2).mean())/255:.4f}')

edges = ref.filter(ImageFilter.GaussianBlur(1.2)).convert('L').filter(ImageFilter.FIND_EDGES)
e = np.asarray(edges).astype(float)
mask = np.clip((e - 10) / 30, 0, 1)[..., None]
blend = np.asarray(ren).astype(float) * (1 - mask) + np.array([255, 30, 30]) * mask
panels = [ref, ren, Image.fromarray(blend.astype(np.uint8))]
if box:
    panels = [p.crop(box) for p in panels]
if scale != 1.0:
    panels = [p.resize((int(p.width * scale), int(p.height * scale)), Image.LANCZOS) for p in panels]
sheet = Image.new('RGB', (sum(p.width for p in panels) + 8 * (len(panels) - 1), panels[0].height), (20, 20, 20))
x = 0
for p in panels:
    sheet.paste(p, (x, 0)); x += p.width + 8
sheet.save(out_p)
