#!/usr/bin/env python3
"""crop.py IMAGE OUT x0 y0 x1 y1 [scale]  -- crop and upscale a region for close study."""
import sys
from PIL import Image
src, out, x0, y0, x1, y1 = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:7])
scale = float(sys.argv[7]) if len(sys.argv) > 7 else 3
im = Image.open(src).convert('RGB').crop((x0, y0, x1, y1))
im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
im.save(out)
