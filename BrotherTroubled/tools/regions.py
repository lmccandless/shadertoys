#!/usr/bin/env python3
"""regions.py RENDER -- mean colour of named painting regions, reference vs render (sRGB 0..1).

Boxes are (x0, y0, x1, y1) in painting pixels (800x668). The last column is the signed luma error, so
'too dark' / 'too bright' is obvious at a glance.
"""
import sys
import numpy as np
from PIL import Image
import os
REF = os.environ.get('BT_REFERENCE', 'reference/painting.jpg')  # the 800x668 source painting (not shipped)
ren = np.asarray(Image.open(sys.argv[1]).convert('RGB').resize((800, 668), Image.LANCZOS)).astype(float) / 255
ref = np.asarray(Image.open(sys.argv[2] if len(sys.argv) > 2 else REF).convert('RGB')).astype(float) / 255
R = {
 'sky teal TL':      (0, 0, 120, 80),   'sky teal mid':  (120, 40, 240, 110),
 'cloud lobe':       (170, 110, 235, 170), 'cloud left':   (0, 150, 120, 230),
 'cloud floor':      (0, 240, 220, 330),  'horizon hills': (0, 350, 200, 362),
 'tree crown':       (215, 190, 290, 280),'tree horizon L': (0, 372, 100, 410),
 'meadow':           (90, 418, 210, 448), 'ground olive L': (0, 470, 200, 540),
 'ground front L':   (0, 570, 300, 640),  'ground front M': (300, 590, 560, 650),
 'ground front R':   (560, 580, 800, 650),'ground shadow':  (300, 500, 560, 545),
 'ground right':     (640, 520, 800, 600),
 'wall glow':        (340, 120, 480, 280),'wall mid':       (480, 100, 600, 280),
 'wall right':       (700, 60, 800, 300), 'wall lower R':   (640, 320, 800, 480),
 'wall top':         (340, 0, 700, 60),   'post':           (300, 100, 325, 260),
 'thatch':           (255, 5, 320, 55),   'shutter':        (595, 140, 685, 260),
 'cow back':         (300, 300, 600, 320),'cow mid flank':  (300, 340, 600, 400),
 'cow lower':        (300, 430, 520, 470),'cow chest':      (232, 400, 260, 450),
 'cow rump':         (560, 340, 612, 420),'cow head':       (150, 340, 200, 375),
 'cow leg NF':       (302, 495, 325, 530),'cow leg NR':     (562, 500, 585, 545),
}
print(f"{'region':16s} {'reference':>18s} {'render':>18s}   dLuma")
tot = 0
for k, (x0, y0, x1, y1) in R.items():
    a = ref[y0:y1, x0:x1].reshape(-1, 3).mean(0); b = ren[y0:y1, x0:x1].reshape(-1, 3).mean(0)
    la = 0.2126*a[0] + 0.7152*a[1] + 0.0722*a[2]; lb = 0.2126*b[0] + 0.7152*b[1] + 0.0722*b[2]
    tot += (b - a).__abs__().mean()
    print(f"{k:16s} ({a[0]:.2f},{a[1]:.2f},{a[2]:.2f})    ({b[0]:.2f},{b[1]:.2f},{b[2]:.2f})   {lb-la:+.2f}")
print(f'mean |dRGB| over regions: {tot/len(R):.3f}')
