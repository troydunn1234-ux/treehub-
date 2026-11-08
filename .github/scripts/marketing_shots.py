"""Turn raw simulator screenshots into App Store screenshots (1320x2868, 6.9").

Each shot: deep-space gradient with aurora glows and stars, a small glowing
eyebrow pill, a huge two-line headline (second line in the neon gradient), a
short subline, then the screenshot inside a drawn iPhone (titanium rim,
Dynamic Island) with floating glass feature chips.

metadata.json "shots": [{file, eyebrow, line1, line2, sub, chips: [..], tilt}]
usage: marketing_shots.py metadata.json shots_dir out_dir
"""
import json, math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

meta, shots, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
W, H = 1320, 2868
HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "store", "fonts"))

def font(name, size):
    for f in (os.path.join(FONT_DIR, name), "/System/Library/Fonts/SFNS.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(f):
            try: return ImageFont.truetype(f, size)
            except Exception: pass
    return ImageFont.load_default()

HEAVY = lambda s: font("InterDisplay-Black.otf", s)
BOLD = lambda s: font("Inter-ExtraBold.otf", s)
SEMI = lambda s: font("Inter-SemiBold.otf", s)

MAGENTA, VIOLET, CYAN = (255, 61, 158), (140, 84, 255), (64, 224, 255)
BG_TOP, BG_BOT = (14, 10, 34), (4, 4, 12)

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
def neon(t): return lerp(MAGENTA, VIOLET, t * 2) if t < .5 else lerp(VIOLET, CYAN, (t - .5) * 2)

def background(seed):
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        d.line([(0, y), (W, y)], fill=lerp(BG_TOP, BG_BOT, y / H) + (255,))
    rnd = random.Random(seed * 7 + 3)
    spots = [(MAGENTA, .1, .06, 760), (VIOLET, .95, .3, 900), (CYAN, .2, .78, 820), (MAGENTA, .9, .98, 700)]
    rot = seed % len(spots)
    spots = spots[rot:] + spots[:rot]
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for c, x, y, r in spots:
        gd.ellipse([x * W - r, y * H - r, x * W + r, y * H + r], fill=c + (95,))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(300)))
    stars = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stars)
    for _ in range(230):
        x, y, r = rnd.uniform(0, W), rnd.uniform(0, H), rnd.choice([1, 1, 1.5, 2, 2.5])
        sd.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, rnd.randint(40, 170)))
    img = Image.alpha_composite(img, stars)
    # faint perspective grid at the bottom, like a stage floor
    grid = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g = ImageDraw.Draw(grid)
    hy = int(H * .80)
    for i in range(-14, 15):
        g.line([(W / 2 + i * 30, hy), (W / 2 + i * 260, H)], fill=VIOLET + (38,), width=2)
    for k in range(1, 12):
        y = hy + (H - hy) * (k / 11) ** 1.8
        g.line([(0, y), (W, y)], fill=VIOLET + (30,), width=2)
    return Image.alpha_composite(img, grid)

def gradient_fill(size, x0, x1):
    grad = Image.new("RGBA", size)
    gd = ImageDraw.Draw(grad)
    for x in range(size[0]):
        t = min(1, max(0, (x - x0) / max(1, x1 - x0)))
        gd.line([(x, 0), (x, size[1])], fill=neon(t) + (255,))
    return grad

def centered_text(img, y, text, f, fill=None, glow=None, track=0):
    d = ImageDraw.Draw(img)
    widths = [d.textlength(ch, font=f) + track for ch in text] if track else None
    w = sum(widths) - track if track else d.textlength(text, font=f)
    x = (W - w) / 2
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    if track:
        cx = x
        for ch, cw in zip(text, widths):
            md.text((cx, y), ch, font=f, fill=255); cx += cw
    else:
        md.text((x, y), text, font=f, fill=255)
    if glow:
        halo = Image.new("RGBA", img.size, glow + (0,))
        halo.putalpha(mask.filter(ImageFilter.GaussianBlur(28)).point(lambda v: int(v * .75)))
        img.alpha_composite(halo)
    layer = gradient_fill(img.size, x, x + w) if fill is None else Image.new("RGBA", img.size, fill)
    img.paste(layer, (0, 0), mask)
    return x, w

def pill(img, cx, y, text, f, accent):
    d = ImageDraw.Draw(img)
    tw = d.textlength(text, font=f) + len(text) * 5
    pw, ph = tw + 110, 78
    x0, y0 = cx - pw / 2, y
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([x0, y0, x0 + pw, y0 + ph], ph / 2, fill=accent + (120,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(30)))
    body = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle([x0, y0, x0 + pw, y0 + ph], ph / 2, fill=(255, 255, 255, 26), outline=accent + (200,), width=3)
    bd.ellipse([x0 + 34, y0 + ph / 2 - 9, x0 + 52, y0 + ph / 2 + 9], fill=accent + (255,))
    img.alpha_composite(body)
    cx2 = x0 + 74
    for ch in text:
        ImageDraw.Draw(img).text((cx2, y0 + 19), ch, font=f, fill=(255, 255, 255, 235))
        cx2 += ImageDraw.Draw(img).textlength(ch, font=f) + 5

def phone(shot, width):
    """Draw an iPhone around the screenshot. Returns RGBA phone image."""
    bez, rim = int(width * .035), int(width * .012)
    sw = width - 2 * (bez + rim)
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    pw, ph = width, sh + 2 * (bez + rim)
    R = int(width * .16)
    ph_img = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    # titanium rim: vertical metallic gradient
    rim_layer = Image.new("RGBA", (pw, ph))
    rd = ImageDraw.Draw(rim_layer)
    for y in range(ph):
        t = y / ph
        v = int(118 + 60 * math.sin(t * math.pi * 3) ** 2)
        rd.line([(0, y), (pw, y)], fill=(v, v - 4, v + 8, 255))
    m = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, pw - 1, ph - 1], R, fill=255)
    ph_img.paste(rim_layer, (0, 0), m)
    d = ImageDraw.Draw(ph_img)
    d.rounded_rectangle([rim, rim, pw - rim - 1, ph - rim - 1], R - rim, fill=(6, 6, 9, 255))
    # screen
    sm = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(sm).rounded_rectangle([0, 0, sw - 1, sh - 1], R - rim - bez + 6, fill=255)
    ph_img.paste(shot.convert("RGBA"), (rim + bez, rim + bez), sm)
    # Dynamic Island
    iw, ih = int(sw * .30), int(sw * .085)
    ix, iy = (pw - iw) // 2, rim + bez + int(sw * .03)
    d.rounded_rectangle([ix, iy, ix + iw, iy + ih], ih // 2, fill=(0, 0, 0, 255))
    # edge highlight
    d.rounded_rectangle([1, 1, pw - 2, ph - 2], R, outline=(255, 255, 255, 90), width=3)
    # side buttons
    return ph_img

def chip(img, x, y, text, accent, f):
    d = ImageDraw.Draw(img)
    tw = d.textlength(text, font=f)
    w, h = tw + 120, 104
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([x + 8, y + 18, x + w + 8, y + h + 18], 34, fill=(0, 0, 0, 150))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(22)))
    # frosted: blur what's behind
    box = (int(x), int(y), int(x + w), int(y + h))
    region = img.crop(box).filter(ImageFilter.GaussianBlur(26))
    m = Image.new("L", region.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, region.size[0] - 1, region.size[1] - 1], 34, fill=255)
    img.paste(region, box[:2], m)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.rounded_rectangle([x, y, x + w, y + h], 34, fill=(22, 18, 44, 165), outline=accent + (210,), width=3)
    ld.ellipse([x + 34, y + h / 2 - 15, x + 64, y + h / 2 + 15], fill=accent + (255,))
    ld.text((x + 86, y + h / 2 - 27), text, font=f, fill=(255, 255, 255, 245))
    img.alpha_composite(layer)
    return w

m = json.load(open(meta))
accents = [MAGENTA, CYAN, VIOLET]
for i, s in enumerate(m["shots"]):
    src = os.path.join(shots, s["file"])
    if not os.path.exists(src):
        print("missing", src); continue
    acc = accents[i % 3]
    img = background(i)
    pill(img, W / 2, 168, s["eyebrow"].upper(), BOLD(34), acc)
    centered_text(img, 290, s["line1"], HEAVY(148), fill=(255, 255, 255, 255))
    centered_text(img, 450, s["line2"], HEAVY(148), glow=VIOLET)
    centered_text(img, 650, s["sub"], SEMI(54), fill=(222, 216, 255, 210))

    ph = phone(Image.open(src), int(W * .80))
    tilt = s.get("tilt", 0)
    if tilt:
        ph = ph.rotate(tilt, resample=Image.BICUBIC, expand=True)
    px, py = (W - ph.width) // 2, 820
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    a = ph.split()[3].point(lambda v: int(v * .9))
    glow = Image.new("RGBA", ph.size, acc + (0,)); glow.putalpha(a)
    shadow.paste(glow, (px, py + 40), glow)
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(90)))
    img.alpha_composite(ph, (px, py))

    for k, text in enumerate(s.get("chips", [])[:3]):
        f = BOLD(46)
        tw = ImageDraw.Draw(img).textlength(text, font=f) + 120
        left = k % 2 == 0
        x = 28 if left else W - tw - 28
        y = 1640 + k * 600
        chip(img, x, y, text, accents[(i + k + 1) % 3], f)

    path = os.path.join(out, f"{i + 1:02d}-{s['file']}")
    img.convert("RGB").save(path, "PNG", optimize=True)
    print("made", path)
