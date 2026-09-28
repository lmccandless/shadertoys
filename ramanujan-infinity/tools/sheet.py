# Tile PNG frames into one contact sheet: python3 tools/sheet.py out.png a.png b.png ...
import sys
from PIL import Image, ImageDraw
out, files = sys.argv[1], sys.argv[2:]
ims = [Image.open(f).convert('RGB') for f in files]
w, h = ims[0].size
cols = 2 if len(ims) > 1 else 1
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * w + (cols - 1) * 4, rows * h + (rows - 1) * 4), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for i, (im, f) in enumerate(zip(ims, files)):
    x, y = (i % cols) * (w + 4), (i // cols) * (h + 4)
    sheet.paste(im, (x, y))
    d.text((x + 6, y + 4), f.split('/')[-1], fill=(255, 255, 0))
sheet.save(out)
