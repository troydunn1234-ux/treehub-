"""Check store/<app>/metadata.json before a listing run, so a bad field fails in seconds instead of after the
simulator captures (or gets refused by App Store Connect halfway through an upload).

usage: store_lint.py [store/<app>/metadata.json ...]     (no arguments: every store/*/metadata.json)

Errors (exit 1):
  - over an App Store limit: name and subtitle 30, promotional text 170, keywords 100 bytes,
    description and review notes 4000
  - superlatives ("best", "#1", "number one") or medical claims (cure, treat, diagnose, heal, therapy,
    clinically, prescription) in the public text
  - a price above 0 on an app that also sells its own unlock in the app ("paywall"): that would charge twice
  - a caption with a missing field, or for a screenshot no "capture" entry takes; "ipad" shots that aren't captioned
Warnings: the caption style in marketing_shots.py (one statement ending in a period, two chips, lines that fit
without shrinking), keywords with spaces after commas, repeats, or words already in the name or subtitle, and
other companies' names in keywords.
"""
import glob, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
FONT_DIR = os.path.join(ROOT, "store", "fonts")
GH = os.environ.get("GITHUB_ACTIONS") == "true"

LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170, "description": 4000, "reviewNotes": 4000}
PUBLIC = ("name", "subtitle", "promotionalText", "keywords", "description")
BANNED = [
    (r"\bbest\b", "superlative"), (r"#\s?1\b", "superlative"), (r"\bnumber one\b", "superlative"),
    (r"\bno\.\s?1\b", "superlative"),
    (r"\bcur(e|es|ed|ing)\b", "medical claim"), (r"\btreat(s|ed|ing|ment|ments)?\b", "medical claim"),
    (r"\bdiagnos\w*", "medical claim"), (r"\bheal(s|ed|ing)?\b", "medical claim"),
    (r"\btherap(y|ies|eutic)\b", "medical claim"), (r"\bclinically\b", "medical claim"),
    (r"\bprescri\w*", "medical claim"),
]
# Other companies' names don't belong in keywords (App Review guideline 2.3.7).
TRADEMARKS = {"apple", "iphone", "ipad", "siri", "whoop", "garmin", "fitbit", "oura", "strava", "netflix", "roku",
              "vizio", "samsung", "lg", "google", "android", "alexa", "windows", "microsoft", "hulu", "youtube"}

problems = {"error": 0, "warning": 0}


def report(kind, app, msg):
    problems[kind] += 1
    if GH:
        print(f"::{kind}::{app}: {msg}")
    else:
        print(f"{kind.upper():8}{app}: {msg}")


def measure():
    """Pixel widths in the caption fonts, or None without Pillow / the fonts."""
    try:
        from PIL import Image, ImageDraw, ImageFont
        d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
        f = {k: ImageFont.truetype(os.path.join(FONT_DIR, n), s) for k, (n, s) in
             {"head": ("InterDisplay-Black.otf", 148), "sub": ("Inter-SemiBold.otf", 54),
              "chip": ("Inter-ExtraBold.otf", 46)}.items()}
        return lambda text, kind: d.textlength(text, font=f[kind])
    except Exception:
        return None


def lint(path):
    app = os.path.basename(os.path.dirname(path)) or path
    try:
        m = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        report("error", app, f"can't read {path}: {e}")
        return
    for k, n in LIMITS.items():
        if len(m.get(k) or "") > n:
            report("error", app, f"{k} is {len(m[k])} characters (App Store limit {n})")
    kw = m.get("keywords") or ""
    if len(kw.encode("utf-8")) > 100:
        report("error", app, f"keywords are {len(kw.encode('utf-8'))} bytes (App Store limit 100)")
    for k in PUBLIC:
        text = (m.get(k) or "").lower()
        for pat, why in BANNED:
            hit = re.search(pat, text)
            if hit:
                report("error", app, f'{k} says "{hit.group(0)}" ({why})')
    # Keywords: no spaces after commas, no repeats, nothing already in the name or subtitle, no brand names.
    words = [w.strip() for w in kw.split(",") if w.strip()]
    if ", " in kw:
        report("warning", app, "keywords have spaces after commas (they count toward the 100)")
    seen = set()
    for w in words:
        if w.lower() in seen:
            report("warning", app, f'keyword "{w}" is listed twice')
        seen.add(w.lower())
    title = set(re.findall(r"[a-z0-9]+", ((m.get("name") or "") + " " + (m.get("subtitle") or "")).lower()))
    for w in words:
        if w.lower() in title:
            report("warning", app, f'keyword "{w}" is already in the name or subtitle')
        for part in re.findall(r"[a-z0-9]+", w.lower()):
            if part in TRADEMARKS:
                report("warning", app, f'keyword "{w}" uses another company\'s name')
    # Price: a paid download plus the app's own in-app unlock would charge people twice.
    try:
        price = float(m.get("price") or 0)
    except ValueError:
        report("error", app, f'price "{m.get("price")}" is not a number')
        price = 0
    if price > 0 and m.get("paywall"):
        report("error", app, f"price is {m['price']} but the app sells its own unlock (paywall): "
                             "set price to 0.0 for a free download with in-app Pro")
    # Captions.
    captured = {c.get("file") for c in m.get("capture", [])}
    shots = m.get("shots") or []
    files = [s.get("file") for s in shots]
    for f in (m.get("ipad") or {}).get("shots") or []:
        if f not in files:
            report("error", app, f'ipad shot "{f}" has no caption in "shots"')
    width = measure()
    short = (m.get("name") or "").split(":")[0].strip()
    for i, s in enumerate(shots):
        f = s.get("file", f"shot {i + 1}")
        missing = [k for k in ("file", "eyebrow", "line1", "line2", "sub") if not s.get(k)]
        if missing:
            report("error", app, f"{f}: caption is missing {', '.join(missing)}")
            continue
        if f not in captured:
            report("error", app, f'{f}: no "capture" entry takes this screenshot')
        l1, l2, sub, chips = s["line1"], s["line2"], s["sub"], s.get("chips") or []
        if i == 0 and short and s["eyebrow"] != short:
            report("warning", app, f'{f}: the first eyebrow should be the app name ("{short}")')
        if len(s["eyebrow"].split()) > 2:
            report("warning", app, f'{f}: eyebrow "{s["eyebrow"]}" is longer than two words')
        if not l2.endswith("."):
            report("warning", app, f'{f}: headline should end with a period ("{l2}")')
        if re.search(r"[?!]", l1 + l2):
            report("warning", app, f"{f}: headline should be a statement, not a question or exclamation")
        if re.search(r"[.?!]$", l1):
            report("warning", app, f'{f}: headline is two sentences ("{l1} {l2}"); make it one statement')
        if not sub.endswith("."):
            report("warning", app, f'{f}: subline should end with a period ("{sub}")')
        if len(chips) != 2:
            report("warning", app, f"{f}: {len(chips)} chips (the style uses two)")
        for c in chips:
            if re.search(r"[.!?]$", c):
                report("warning", app, f'{f}: chip "{c}" ends with punctuation')
        if width:
            for line in (l1, l2):
                if width(line, "head") > 1320 - 120:
                    report("warning", app, f'{f}: headline line "{line}" is too wide for the screenshot')
            if width(sub, "sub") > 1320 - 90:
                report("warning", app, f'{f}: subline "{sub}" is too long and will be drawn smaller')
            for c in chips:
                if width(c, "chip") + 120 > 760:
                    report("warning", app, f'{f}: chip "{c}" is too wide')


paths = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "store", "*", "metadata.json")))
for p in paths:
    lint(p)
print(f"store_lint: {len(paths)} file(s), {problems['error']} error(s), {problems['warning']} warning(s)")
sys.exit(1 if problems["error"] else 0)
