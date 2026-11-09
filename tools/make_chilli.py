"""Draws the chilli icon used by the addon and writes Media/Chilli.tga (64x64, 32-bit).

Run: python3 tools/make_chilli.py   (needs Pillow). Also writes docs/chilli.png (256px preview).
"""
import math
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 512  # supersampled canvas, downscaled to 64
OUT = 64
root = Path(__file__).resolve().parent.parent

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))


def bezier(p0, p1, p2, p3, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


# Body: a fat curved pepper from top-right shoulder down to a curled tip bottom-left.
outer = bezier((350, 150), (470, 260), (360, 470), (95, 445))
inner = bezier((95, 445), (300, 400), (330, 260), (245, 175))
cap = bezier((245, 175), (275, 130), (320, 125), (350, 150), 20)
body = outer + inner + cap


def layer(points, fill, blur=0):
    lay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(lay).polygon(points, fill=fill)
    if blur:
        lay = lay.filter(ImageFilter.GaussianBlur(blur))
    return lay


# dark outline, red body, darker underside, glossy highlight
outline = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(outline).polygon(body, fill=(40, 6, 6, 255))
outline = outline.filter(ImageFilter.MaxFilter(17))
img.alpha_composite(outline)
img.alpha_composite(layer(body, (214, 32, 28, 255)))

shade = bezier((392, 250), (400, 380), (300, 450), (110, 440)) + bezier((110, 440), (290, 415), (360, 330), (392, 250), 30)
img.alpha_composite(layer(shade, (150, 14, 16, 200), blur=6))

gloss = bezier((300, 190), (360, 220), (360, 300), (318, 340), 30) + bezier((318, 340), (335, 290), (330, 230), (300, 190), 30)
img.alpha_composite(layer(gloss, (255, 190, 170, 210), blur=4))

# green calyx + stem
d = ImageDraw.Draw(img)
calyx = [(225, 165), (260, 120), (300, 108), (345, 118), (372, 150), (340, 160), (300, 150), (262, 172)]
co = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(co).polygon(calyx, fill=(16, 40, 10, 255))
co = co.filter(ImageFilter.MaxFilter(13))
img.alpha_composite(co)
d.polygon(calyx, fill=(70, 160, 40, 255))
stem = bezier((300, 112), (295, 70), (320, 40), (365, 35), 30)
for w, col in ((30, (16, 40, 10, 255)), (18, (90, 175, 50, 255))):
    d.line(stem, fill=col, width=w, joint="curve")
    for p in (stem[0], stem[-1]):
        d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=col)

small = img.resize((OUT, OUT), Image.LANCZOS)
img.resize((256, 256), Image.LANCZOS).save(root / "docs" / "chilli.png")

# Uncompressed 32-bit TGA, bottom-left origin (the safest format for WoW).
px = small.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA")
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, OUT, OUT, 32, 8)
(root / "SpicySideQuests" / "Media" / "Chilli.tga").write_bytes(header + px)
print("wrote Media/Chilli.tga")
