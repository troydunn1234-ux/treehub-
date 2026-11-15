"""Take an app's App Store screenshots in the simulator, driven by store/<app>/metadata.json.

usage: store_capture.py <metadata.json> <products dir> <out dir>

metadata.json keys used (all optional except capture):
  "bundle":   "com.troydunn.roamr"
  "scheme":   "Roamr"                       -> <products dir>/Roamr.app
  "location": "37.7694,-122.4862"           simulated GPS for the iPhone
  "grant":    ["location", "location-always", "motion", "photos"]
  "capture":  [{"file": "roamr-1-track.png", "args": "-demo -tab track", "wait": 7,
                "route": ["lat,lng", ...] (optional: drive the simulated GPS along these points first),
                "section": "arcade" (optional, web-app shells: open this section)}]
  "paywall":  {"args": "-demo -paywall -demoPrice 2.99", "wait": 6}   -> <out>/paywall/iap-review.png
  "ipad":     {"shots": ["roamr-1.png", ...]} (optional: which of the "shots" files to also take on the
              13-inch iPad; default the first 5). iPad shots are only taken when the built app supports iPad
              (UIDeviceFamily contains 2) -> <out>/ipad/
  "watch":    {"product": "RoamrWatch", "bundle": "com.troydunn.roamr.watchkitapp",
               "capture": [{"file": "w1.png", "args": "-demo", "wait": 6}]}   -> <out>/watch/

Writes raw iPhone shots to <out>/raw, watch shots to <out>/watch, the paywall to <out>/paywall.
Only demo data is ever shown: every launch passes -demo.
"""
import functools, json, os, re, subprocess, sys, time
print = functools.partial(print, flush=True)

meta = json.load(open(sys.argv[1]))
products, out = sys.argv[2], sys.argv[3]
for d in ("raw", "watch", "paywall", "ipad"):
    os.makedirs(os.path.join(out, d), exist_ok=True)


def sh(*cmd, check=False, quiet=False, timeout=240):
    print("  $", " ".join(cmd[:6]), flush=True)
    try:
        r = subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print("  ! timed out:", " ".join(cmd[:6]), flush=True)
        if check: sys.exit(f"timed out: {' '.join(cmd)}")
        return subprocess.CompletedProcess(cmd, 1, "", "timeout")
    if r.returncode and not quiet:
        print("  !", " ".join(cmd[:4]), "->", (r.stderr or r.stdout).strip()[:300])
    if check and r.returncode:
        sys.exit(f"failed: {' '.join(cmd)}")
    return r


def devices():
    return json.loads(sh("xcrun", "simctl", "list", "devices", "available", "-j").stdout)["devices"]


def pick(platform, prefer):
    """Newest runtime, then the preferred device name."""
    best = None
    for rt, devs in devices().items():
        if platform not in rt: continue
        ver = tuple(int(x) for x in re.findall(r"\d+", rt.split(platform)[-1]))
        for dv in devs:
            score = (ver, prefer(dv["name"]))
            if best is None or score > best[0]: best = (score, dv["udid"], dv["name"], rt)
    return best


def boot(udid):
    sh("xcrun", "simctl", "boot", udid, quiet=True)
    sh("xcrun", "simctl", "bootstatus", udid, "-b", quiet=True, timeout=900)


def blank(path):
    """True when there's nothing drawn below the status bar yet (launch screen): almost no edges."""
    try:
        from PIL import Image, ImageFilter, ImageStat
        im = Image.open(path).convert("L")
        w, h = im.size
        im = im.crop((0, int(h * 0.08), w, h)).resize((max(1, w // 4), max(1, int(h * 0.92) // 4))).filter(ImageFilter.FIND_EDGES)
        return ImageStat.Stat(im).mean[0] < 1.0
    except Exception:
        return False


def is_running(udid, bundle):
    r = sh("xcrun", "simctl", "spawn", udid, "launchctl", "list", quiet=True, timeout=60)
    return r.stderr == "timeout" or bundle in r.stdout   # a hung launchctl says nothing about the app


def shoot(udid, bundle, args, wait, path, route=None, section=None):
    sh("xcrun", "simctl", "terminate", udid, bundle, quiet=True)
    if section:  # web-app shells: the section to open, as a Siri request would leave it (ShellLink)
        sh("xcrun", "simctl", "spawn", udid, "defaults", "write", bundle, "shell.pendingSection", "-string", section)
        sh("xcrun", "simctl", "spawn", udid, "defaults", "write", bundle, "shell.pendingSectionAt", "-float", str(time.time()))
    sh("xcrun", "simctl", "launch", udid, bundle, *args.split())
    if route:
        time.sleep(3)
        sh("xcrun", "simctl", "location", udid, "start", "--speed=6", "--interval=1", *route, quiet=True)
    time.sleep(float(wait))
    ok = is_running(udid, bundle)
    sh("xcrun", "simctl", "io", udid, "screenshot", path)
    # Still on the plain launch screen (a slow cold start)? Give it longer and take it again.
    for _ in range(6):
        if not blank(path): break
        print("  (still loading, waiting)")
        time.sleep(10)
        sh("xcrun", "simctl", "io", udid, "screenshot", path)
    if route:
        sh("xcrun", "simctl", "location", udid, "clear", quiet=True)
    print(("OK    " if ok else "CRASH ") + os.path.basename(path), args)
    return ok


fails = 0
bundle = meta["bundle"]
app = os.path.join(products, "Release-iphonesimulator", meta["scheme"] + ".app")
if not os.path.isdir(app):
    sys.exit(f"missing {app}")

# ---- iPhone (largest Pro Max on the newest iOS)
best = pick("iOS", lambda n: (n.startswith("iPhone"), "Pro Max" in n, "Pro" in n))
udid = best[1]
print("iPhone simulator:", best[2], best[3])
boot(udid)
sh("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
   "--cellularBars", "4", "--wifiBars", "3", "--operatorName", "")
sh("xcrun", "simctl", "install", udid, app, check=True)
for svc in meta.get("grant", []):
    sh("xcrun", "simctl", "privacy", udid, "grant", svc, bundle, quiet=True)
if meta.get("location"):
    sh("xcrun", "simctl", "location", udid, "set", meta["location"], quiet=True)

for c in meta.get("capture", []):
    if c.get("fresh"):  # start from a clean install (e.g. no trip left over from the previous shot)
        sh("xcrun", "simctl", "uninstall", udid, bundle, quiet=True)
        sh("xcrun", "simctl", "install", udid, app, check=True)
        for svc in meta.get("grant", []):
            sh("xcrun", "simctl", "privacy", udid, "grant", svc, bundle, quiet=True)
    fails += not shoot(udid, bundle, c.get("args", "-demo"), c.get("wait", 7), os.path.join(out, "raw", c["file"]), c.get("route"), c.get("section"))

if meta.get("paywall"):
    p = meta["paywall"]
    # A fresh install so nothing (trial, purchase cache) is remembered.
    sh("xcrun", "simctl", "uninstall", udid, bundle, quiet=True)
    sh("xcrun", "simctl", "install", udid, app, check=True)
    for svc in meta.get("grant", []):
        sh("xcrun", "simctl", "privacy", udid, "grant", svc, bundle, quiet=True)
    fails += not shoot(udid, bundle, p["args"], p.get("wait", 7), os.path.join(out, "paywall", "iap-review.png"))
sh("xcrun", "simctl", "shutdown", udid, quiet=True)

# ---- iPad Pro 13-inch (2064x2752), only when the app runs on iPad (App Store Connect then requires a 13" set)
import plistlib
try:
    family = plistlib.load(open(os.path.join(app, "Info.plist"), "rb")).get("UIDeviceFamily", [1])
except Exception as e:
    print("::warning::couldn't read UIDeviceFamily:", e); family = [1]
print("UIDeviceFamily:", family)
if 2 in family:
    def ipad13():
        best = None
        for rt, devs in devices().items():
            if "iOS" not in rt: continue
            ver = tuple(int(x) for x in re.findall(r"\d+", rt.split("iOS")[-1]))
            for dv in devs:
                n = dv["name"]
                if not (n.startswith("iPad Pro") and ("13-inch" in n or "12.9-inch" in n)): continue
                score = (ver, "13-inch" in n, n)
                if best is None or score > best[0]: best = (score, dv["udid"], n, rt)
        return best
    ip = ipad13()
    if not ip or "13-inch" not in ip[2]:
        rts = [r for r in json.loads(sh("xcrun", "simctl", "list", "runtimes", "-j").stdout)["runtimes"]
               if r.get("platform") == "iOS" and r.get("isAvailable")]
        types = sorted([t for t in json.loads(sh("xcrun", "simctl", "list", "devicetypes", "-j").stdout)["devicetypes"]
                        if t["name"].startswith("iPad Pro 13-inch")], key=lambda t: t["name"])
        if rts and types:
            sh("xcrun", "simctl", "create", "Store iPad 13", types[-1]["identifier"], rts[-1]["identifier"])
            ip = ipad13()
    if not ip:
        print("::warning::no 13-inch iPad simulator available")
    else:
        iid = ip[1]
        print("iPad simulator:", ip[2], ip[3])
        boot(iid)
        sh("xcrun", "simctl", "status_bar", iid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
           "--wifiBars", "3", "--operatorName", "")
        sh("xcrun", "simctl", "install", iid, app, check=True)
        for svc in meta.get("grant", []):
            sh("xcrun", "simctl", "privacy", iid, "grant", svc, bundle, quiet=True)
        if meta.get("location"):
            sh("xcrun", "simctl", "location", iid, "set", meta["location"], quiet=True)
        shot_files = [s["file"] for s in meta.get("shots", [])]
        want = set((meta.get("ipad") or {}).get("shots") or shot_files[:5])
        for c in meta.get("capture", []):
            if c["file"] in shot_files and c["file"] not in want: continue   # warm-up shots (not in "shots") still run
            if c.get("fresh"):
                sh("xcrun", "simctl", "uninstall", iid, bundle, quiet=True)
                sh("xcrun", "simctl", "install", iid, app, check=True)
                for svc in meta.get("grant", []):
                    sh("xcrun", "simctl", "privacy", iid, "grant", svc, bundle, quiet=True)
            if not shoot(iid, bundle, c.get("args", "-demo"), c.get("wait", 7), os.path.join(out, "ipad", c["file"]), c.get("route"), c.get("section")):
                print("::warning::iPad shot", c["file"], "- the app was not running when it was taken")
        sh("xcrun", "simctl", "shutdown", iid, quiet=True)
else:
    print("iPhone-only app: no iPad screenshots")

# ---- Apple Watch
w = meta.get("watch")
if w:
    wapp = os.path.join(products, "Release-watchsimulator", w["product"] + ".app")
    if not os.path.isdir(wapp):
        print("::warning::watch app not built:", wapp)
    else:
        best = pick("watchOS", lambda n: ("Ultra" in n, "Series" in n, n))
        if not best:
            # No watch simulator yet: make an Ultra on the newest watchOS runtime.
            rts = [r for r in json.loads(sh("xcrun", "simctl", "list", "runtimes", "-j").stdout)["runtimes"]
                   if r.get("platform") == "watchOS" and r.get("isAvailable")]
            types = [t for t in json.loads(sh("xcrun", "simctl", "list", "devicetypes", "-j").stdout)["devicetypes"]
                     if "Watch" in t["name"]]
            ultra = sorted([t for t in types if "Ultra" in t["name"]], key=lambda t: t["name"]) or types
            if rts and ultra:
                sh("xcrun", "simctl", "create", "Store Watch", ultra[-1]["identifier"], rts[-1]["identifier"])
                best = pick("watchOS", lambda n: ("Ultra" in n, "Series" in n, n))
        if not best:
            print("::warning::no watch simulator available")
        else:
            wid = best[1]
            print("Watch simulator:", best[2], best[3])
            boot(wid)
            sh("xcrun", "simctl", "status_bar", wid, "override", "--time", "9:41", quiet=True)
            sh("xcrun", "simctl", "install", wid, wapp, check=True)
            for c in w.get("capture", []):
                fails += not shoot(wid, w["bundle"], c.get("args", "-demo"), c.get("wait", 7), os.path.join(out, "watch", c["file"]))
            sh("xcrun", "simctl", "shutdown", wid, quiet=True)

print("captured:", {d: sorted(os.listdir(os.path.join(out, d))) for d in ("raw", "watch", "paywall", "ipad")})
sys.exit(1 if fails else 0)
