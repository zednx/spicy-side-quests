"""Generates all Spicy Side Quests artwork from code (needs Pillow).

    python3 tools/make_art.py

Writes:
  SpicySideQuests/Media/Chilli.tga  64x64 in-game icon (32-bit, uncompressed)
  docs/chilli.png                   256px icon preview
  docs/logo.png                     1024px square project logo (CurseForge, GitHub)
  docs/logo-400.png                 400px logo for sites with small upload limits
"""
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent


def bezier(p0, p1, p2, p3, n=80):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def odd(n):
    n = max(3, int(round(n)))
    return n if n % 2 else n + 1


def draw_chilli(S):
    """Chilli on a transparent S x S canvas. Designed on a 512 grid, scaled by k."""
    k = S / 512
    P = lambda *pts: [(x * k, y * k) for x, y in pts]  # noqa: E731
    B = lambda a, b, c, d, n=80: bezier(*P(a, b, c, d), n)  # noqa: E731

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    def layer(points, fill, blur=0):
        lay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(lay).polygon(points, fill=fill)
        if blur:
            lay = lay.filter(ImageFilter.GaussianBlur(blur * k))
        return lay

    body = B((350, 150), (470, 260), (360, 470), (95, 445)) + B((95, 445), (300, 400), (330, 260), (245, 175)) + B((245, 175), (275, 130), (320, 125), (350, 150), 20)

    outline = layer(body, (40, 6, 6, 255)).filter(ImageFilter.MaxFilter(odd(17 * k)))
    img.alpha_composite(outline)
    img.alpha_composite(layer(body, (214, 32, 28, 255)))
    shade = B((392, 250), (400, 380), (300, 450), (110, 440)) + B((110, 440), (290, 415), (360, 330), (392, 250), 30)
    img.alpha_composite(layer(shade, (150, 14, 16, 200), blur=6))
    gloss = B((300, 190), (360, 220), (360, 300), (318, 340), 30) + B((318, 340), (335, 290), (330, 230), (300, 190), 30)
    img.alpha_composite(layer(gloss, (255, 190, 170, 210), blur=4))

    calyx = P((225, 165), (260, 120), (300, 108), (345, 118), (372, 150), (340, 160), (300, 150), (262, 172))
    img.alpha_composite(layer(calyx, (16, 40, 10, 255)).filter(ImageFilter.MaxFilter(odd(13 * k))))
    d = ImageDraw.Draw(img)
    d.polygon(calyx, fill=(70, 160, 40, 255))
    stem = B((300, 112), (295, 70), (320, 40), (365, 35), 40)
    for w, col in ((30 * k, (16, 40, 10, 255)), (18 * k, (90, 175, 50, 255))):
        d.line(stem, fill=col, width=int(w), joint="curve")
        for p in (stem[0], stem[-1]):
            d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=col)
    return img


def draw_bang(S):
    """A chunky gold exclamation mark with a dark outline and a soft glow."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    k = S / 512
    bar = [(196 * k, 40 * k), (316 * k, 40 * k), (282 * k, 330 * k), (230 * k, 330 * k)]
    dot = (204 * k, 370 * k, 308 * k, 474 * k)

    def shape(fill, grow=0):
        lay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        dr = ImageDraw.Draw(lay)
        dr.polygon(bar, fill=fill)
        dr.ellipse(dot, fill=fill)
        if grow:
            lay = lay.filter(ImageFilter.MaxFilter(odd(grow * k)))
        return lay

    glow = shape((255, 190, 40, 150), 41).filter(ImageFilter.GaussianBlur(26 * k))
    img.alpha_composite(glow)
    img.alpha_composite(shape((70, 40, 0, 255), 29))
    img.alpha_composite(shape((255, 209, 0, 255)))
    # top highlight
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).polygon([(212 * k, 58 * k), (300 * k, 58 * k), (292 * k, 130 * k), (220 * k, 130 * k)], fill=(255, 245, 190, 140))
    img.alpha_composite(hl.filter(ImageFilter.GaussianBlur(10 * k)))
    return img


def draw_logo(S):
    """Rounded dark tile, warm glow, big chilli, gold quest '!' top-right."""
    W = S * 2  # supersample
    tile = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    # vertical gradient background
    grad = Image.new("RGBA", (W, W))
    gd = ImageDraw.Draw(grad)
    for y in range(W):
        t = y / W
        c = (int(36 - 18 * t), int(26 - 13 * t), int(28 - 14 * t), 255)
        gd.line([(0, y), (W, y)], fill=c)
    # warm radial glow behind the chilli
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((W * 0.18, W * 0.22, W * 0.86, W * 0.90), fill=(255, 90, 30, 120))
    grad.alpha_composite(glow.filter(ImageFilter.GaussianBlur(W * 0.12)))

    mask = Image.new("L", (W, W), 0)
    r = int(W * 0.2)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, W - 1, W - 1), radius=r, fill=255)
    tile.paste(grad, (0, 0), mask)

    # inner border
    border = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bw = max(2, int(W * 0.012))
    ImageDraw.Draw(border).rounded_rectangle((bw, bw, W - 1 - bw, W - 1 - bw), radius=r - bw, outline=(255, 140, 60, 110), width=bw)
    tile.alpha_composite(border)

    # chilli, slightly larger than the tile's centre area
    cs = int(W * 0.86)
    chilli = draw_chilli(cs)
    shadow = Image.new("RGBA", (cs, cs), (0, 0, 0, 0))
    shadow.putalpha(chilli.getchannel("A").point(lambda a: int(a * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.015))
    ox, oy = int(W * 0.03), int(W * 0.10)
    tile.alpha_composite(shadow, (ox + int(W * 0.015), oy + int(W * 0.025)))
    tile.alpha_composite(chilli, (ox, oy))

    # quest "!"
    bs = int(W * 0.42)
    tile.alpha_composite(draw_bang(bs), (int(W * 0.55), int(W * 0.06)))

    return tile.resize((S, S), Image.LANCZOS)


def write_tga(img, path):
    px = img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA")
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)  # bottom-left origin
    path.write_bytes(header + px)


if __name__ == "__main__":
    icon = draw_chilli(512)
    write_tga(icon.resize((64, 64), Image.LANCZOS), ROOT / "SpicySideQuests" / "Media" / "Chilli.tga")
    (ROOT / "docs").mkdir(exist_ok=True)
    icon.resize((256, 256), Image.LANCZOS).save(ROOT / "docs" / "chilli.png")
    logo = draw_logo(1024)
    logo.save(ROOT / "docs" / "logo.png")
    logo.resize((400, 400), Image.LANCZOS).save(ROOT / "docs" / "logo-400.png")
    print("wrote Media/Chilli.tga, docs/chilli.png, docs/logo.png, docs/logo-400.png")
