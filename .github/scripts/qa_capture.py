"""Simulator QA pass: launch an app in demo mode on each screen listed in .github/qa/<app>.json, take a
screenshot, keep the app's log for that launch and any crash report.

usage: qa_capture.py <qa.json> <products dir> <out dir>

qa.json: {"scheme", "bundle", "location"?, "grant"?: [...],
          "shots": [{"name", "args", "wait", "size"? (content size, e.g. accessibility-large),
                     "appearance"? ("light"/"dark"), "url"? (opened after launch)}],
          "watch"?: {"product", "bundle", "shots": [...]}}
Writes <out>/<name>.png, <out>/logs/<name>.log, <out>/crashes/*, <out>/summary.txt. Demo data only.
"""
import functools, glob, json, os, plistlib, re, shutil, subprocess, sys, time
print = functools.partial(print, flush=True)

cfg = json.load(open(sys.argv[1]))
products, out = sys.argv[2], sys.argv[3]
for d in ("", "logs", "crashes"):
    os.makedirs(os.path.join(out, d), exist_ok=True)
summary = []
CRASH_DIR = os.path.expanduser("~/Library/Logs/DiagnosticReports")
started = time.time()


def sh(*cmd, timeout=240):
    try:
        return subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print("  ! timed out:", " ".join(cmd[:6]))
        return subprocess.CompletedProcess(cmd, 1, "", "timeout")


def pick(platform, prefer):
    best = None
    for rt, devs in json.loads(sh("xcrun", "simctl", "list", "devices", "available", "-j").stdout)["devices"].items():
        if platform not in rt: continue
        ver = tuple(int(x) for x in re.findall(r"\d+", rt.split(platform)[-1]))
        for dv in devs:
            score = (ver, prefer(dv["name"]))
            if best is None or score > best[0]: best = (score, dv["udid"], dv["name"], rt)
    return best


def executable(app):
    try:
        return plistlib.load(open(os.path.join(app, "Info.plist"), "rb")).get("CFBundleExecutable")
    except Exception:
        return os.path.basename(app)[:-4]


def running(udid, bundle):
    r = sh("xcrun", "simctl", "spawn", udid, "launchctl", "list", timeout=60)
    return r.stderr == "timeout" or bundle in r.stdout


def run(udid, bundle, exe, shots, prefix=""):
    for s in shots:
        name = prefix + s["name"]
        sh("xcrun", "simctl", "terminate", udid, bundle)
        sh("xcrun", "simctl", "ui", udid, "content_size", s.get("size", "large"))
        sh("xcrun", "simctl", "ui", udid, "appearance", s.get("appearance", "dark"))
        t0 = time.time()
        r = sh("xcrun", "simctl", "launch", udid, bundle, *s.get("args", "").split())
        if r.returncode:
            print("  ! launch:", (r.stderr or r.stdout).strip()[:300])
        if s.get("url"):
            time.sleep(4)
            sh("xcrun", "simctl", "openurl", udid, s["url"])
        time.sleep(float(s.get("wait", 8)))
        ok = running(udid, bundle)
        sh("xcrun", "simctl", "io", udid, "screenshot", os.path.join(out, name + ".png"))
        secs = int(time.time() - t0) + 5
        log = sh("xcrun", "simctl", "spawn", udid, "log", "show", "--last", f"{secs}s", "--style", "compact",
                 "--predicate", f'process == "{exe}"', timeout=180)
        open(os.path.join(out, "logs", name + ".log"), "w").write(log.stdout)
        faults = [l for l in log.stdout.splitlines() if re.search(r"\b(Fault|Error)\b|fatal|crash|precondition|Thread \d+", l, re.I)]
        line = ("OK    " if ok else "CRASH ") + name + "  " + s.get("args", "") + (f"  [{len(faults)} error/fault log lines]" if faults else "")
        print(line)
        summary.append(line)


# ---- iPhone
app = os.path.join(products, "Debug-iphonesimulator", cfg["scheme"] + ".app")
if not os.path.isdir(app):
    sys.exit(f"missing {app}")
best = pick("iOS", lambda n: (n.startswith("iPhone"), "Pro Max" in n, "Pro" in n))
udid = best[1]
print("iPhone simulator:", best[2], best[3])
sh("xcrun", "simctl", "boot", udid)
sh("xcrun", "simctl", "bootstatus", udid, "-b", timeout=900)
sh("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
sh("xcrun", "simctl", "install", udid, app)
for svc in cfg.get("grant", []):
    sh("xcrun", "simctl", "privacy", udid, "grant", svc, cfg["bundle"])
if cfg.get("location"):
    sh("xcrun", "simctl", "location", udid, "set", cfg["location"])
run(udid, cfg["bundle"], executable(app), cfg["shots"])
sh("xcrun", "simctl", "ui", udid, "content_size", "large")
sh("xcrun", "simctl", "shutdown", udid)

# ---- Watch (alone: the phone app is not running on a paired phone)
w = cfg.get("watch")
if w:
    wapp = os.path.join(products, "Debug-watchsimulator", w["product"] + ".app")
    if not os.path.isdir(wapp):
        summary.append("WATCH NOT BUILT " + wapp)
    else:
        best = pick("watchOS", lambda n: ("Ultra" in n, "Series" in n, n))
        if best:
            wid = best[1]
            print("Watch simulator:", best[2], best[3])
            sh("xcrun", "simctl", "boot", wid)
            sh("xcrun", "simctl", "bootstatus", wid, "-b", timeout=900)
            sh("xcrun", "simctl", "install", wid, wapp)
            run(wid, w["bundle"], executable(wapp), w["shots"], prefix="watch-")
            sh("xcrun", "simctl", "shutdown", wid)
        else:
            summary.append("NO WATCH SIMULATOR")

# ---- Crash reports from this run (simulator apps write to the host's DiagnosticReports)
for f in glob.glob(os.path.join(CRASH_DIR, "**", "*"), recursive=True):
    if os.path.isfile(f) and os.path.getmtime(f) >= started - 5:
        try:
            body = open(f, errors="ignore").read(4000)
        except Exception:
            continue
        exe = executable(app)
        if exe in body or (w and w["product"] in body):
            shutil.copy(f, os.path.join(out, "crashes"))
            summary.append("CRASH REPORT " + os.path.basename(f))
open(os.path.join(out, "summary.txt"), "w").write("\n".join(summary) + "\n")
print("\n".join(summary))
