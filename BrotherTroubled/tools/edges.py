#!/usr/bin/env python3
"""edges.py RENDER [REFERENCE] -- compare the cow's silhouette edges numerically against the painting.

Thresholded on luminance, as the painted cow is much brighter than the barn behind it. Prints, for each
probe line, the reference edge and the render edge in painting pixels (800x668) and the difference.
"""
import sys
import numpy as np
from PIL import Image
import os
REF = os.environ.get('BT_REFERENCE', 'reference/painting.jpg')  # the 800x668 source painting (not shipped)
ren = np.asarray(Image.open(sys.argv[1]).convert('RGB').resize((800, 668), Image.LANCZOS)).astype(float) / 255
ref = np.asarray(Image.open(sys.argv[2] if len(sys.argv) > 2 else REF).convert('RGB')).astype(float) / 255
lum = lambda a: 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
Lr, Lm = lum(ref), lum(ren)

def first(L, y0, y1, x, thr):   # scanning down
    col = L[y0:y1, x]; i = np.argmax(col > thr); return y0 + i if col[i] > thr else -1
def last_x(L, y, x0, x1, thr):  # right-most bright pixel in [x0,x1) excluding thin tail strand (needs run >= 6px)
    row = L[y, x0:x1] > thr
    xs = np.where(row)[0]
    if not len(xs): return -1
    # take the right end of the first long run from the left
    run_end = xs[0]
    for a in xs[1:]:
        if a == run_end + 1: run_end = a
        else:
            if run_end - xs[0] >= 6: break
            run_end = a
    return x0 + run_end
def report(name, pairs):
    print(name); 
    for k, (a, b) in pairs: print(f'   {k:>4}: ref {a:4d}  render {b:4d}  diff {b-a:+4d}')
tr, tm = 0.42, 0.42
report('back line (y of top edge) at x', [(x, (first(Lr, 250, 420, x, tr), first(Lm, 250, 420, x, tm))) for x in range(250, 630, 40)])
report('rump edge (x) at y', [(y, (last_x(Lr, y, 560, 700, tr), last_x(Lm, y, 560, 700, tm))) for y in range(310, 480, 20)])
def first_x(L, y, x0, x1, thr):
    row = L[y, x0:x1] > thr; xs = np.where(row)[0]; return x0 + xs[0] if len(xs) else -1
report('front edge (x) at y', [(y, (first_x(Lr, y, 200, 320, tr), first_x(Lm, y, 200, 320, tm))) for y in range(400, 490, 15)])
def last_y(L, x, y0, y1, thr):
    col = L[y0:y1, x] > thr; ys = np.where(col)[0]; return y0 + ys.max() if len(ys) else -1
report('belly edge (y) at x', [(x, (last_y(Lr, x, 440, 500, tr), last_y(Lm, x, 440, 500, tm))) for x in range(340, 540, 40)])
