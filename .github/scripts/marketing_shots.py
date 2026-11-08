"""Turn raw simulator screenshots into App Store screenshots (1320x2868, 6.9"):
gradient background with soft color glows, a big two-line headline, and the
screenshot in a rounded frame with a glow.

usage: marketing_shots.py metadata.json shots_dir out_dir
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

meta, shots, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
W, H = 1320, 2868
FONTS = ["/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
         "/System/Library/Fonts/SFNSRounded.ttf", "/System/Library/Fonts/SFNS.ttf",
         "/System/Library/Fonts/Helvetica.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]

def font(size):
    for f in FONTS:
        if os.path.exists(f):
            try: return ImageFont.truetype(f, size)
            except Exception: pass
    return ImageFont.load_default()

MAGENTA, VIOLET, CYAN, BG = (255, 61, 158), (140, 84, 255), (64, 224, 255), (9, 8, 19)

def background(seed):
    img = Image.new("RGBA", (W, H), BG + (255,))
    spots = [(MAGENTA, 0.15, 0.10), (VIOLET, 0.9, 0.35), (CYAN, 0.3, 0.95)]
    spots = spots[seed % 3:] + spots[:seed % 3]
    for c, x, y in spots:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        r = 900
        d.ellipse([x * W - r, y * H - r, x * W + r, y * H + r], fill=c + (120,))
        img = Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(320)))
    return img

def gradient_text(img, xy, text, f):
    """Headline filled with the magenta→violet→cyan gradient."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text(xy, text, font=f, fill=255)
    grad = Image.new("RGBA", img.size)
    gd = ImageDraw.Draw(grad)
    x0, x1 = xy[0], xy[0] + gd.textlength(text, font=f)
    for x in range(int(x0), int(x1) + 1):
        t = (x - x0) / max(1, x1 - x0)
        a, b, u = (MAGENTA, VIOLET, t * 2) if t < .5 else (VIOLET, CYAN, (t - .5) * 2)
        gd.line([(x, 0), (x, img.size[1])], fill=tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)) + (255,))
    img.paste(grad, (0, 0), mask)

m = json.load(open(meta))
for i, (name, line1, line2) in enumerate(m["captions"]):
    src = os.path.join(shots, name)
    if not os.path.exists(src):
        print("missing", src); continue
    img = background(i)
    d = ImageDraw.Draw(img)
    f1, f2 = font(120), font(64)
    w1 = d.textlength(line1, font=f1)
    gradient_text(img, ((W - w1) / 2, 190), line1, f1)
    w2 = d.textlength(line2, font=f2)
    d.text(((W - w2) / 2, 345), line2, font=f2, fill=(255, 255, 255, 215))

    shot = Image.open(src).convert("RGBA")
    sw = int(W * 0.80); sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    radius = 96
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw, sh], radius, fill=255)
    x, y = (W - sw) // 2, 520
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([x - 10, y - 10, x + sw + 10, y + sh + 10], radius + 10, fill=VIOLET + (150,))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(60)))
    img.paste(shot, (x, y), mask)
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([x, y, x + sw, y + sh], radius, outline=(255, 255, 255, 60), width=4)
    img = Image.alpha_composite(img, rim)
    path = os.path.join(out, f"{i + 1:02d}-{name}")
    img.convert("RGB").save(path, "PNG")
    print("made", path)
