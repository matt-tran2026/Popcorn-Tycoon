"""Draws the shared leaf particle texture (original art) with PIL: a chunky cartoon corn-leaf
fleck with a darker outline and a light midrib, on transparency. 128x128."""
import math, os
from PIL import Image, ImageDraw, ImageFilter
S = 512  # draw large, downsample for smooth edges
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
def leaf(scale):
    pts = []
    for i in range(61):
        t = i / 60
        y = S * 0.08 + t * S * 0.84
        w = math.sin(math.pi * t) ** 0.8 * S * 0.22 * scale
        pts.append((S / 2 + w + math.sin(t * 3) * 18, y))
    for i in range(60, -1, -1):
        t = i / 60
        y = S * 0.08 + t * S * 0.84
        w = math.sin(math.pi * t) ** 0.8 * S * 0.22 * scale
        pts.append((S / 2 - w + math.sin(t * 3) * 18, y))
    return pts
d.polygon(leaf(1.12), fill=(30, 98, 38, 255))
d.polygon(leaf(1.0), fill=(92, 186, 72, 255))
d.polygon([(p[0] - 10, p[1]) for p in leaf(0.45)], fill=(124, 210, 92, 255))
d.line([(S / 2 + math.sin(t / 40 * 3) * 18, S * 0.12 + t / 40 * S * 0.78) for t in range(41)], fill=(196, 238, 150, 255), width=14)
img = img.resize((128, 128), Image.LANCZOS)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures", "Leaf_Fleck.png")
img.save(out)
print(out, img.size)
