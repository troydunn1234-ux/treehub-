"""Simulator QA pass: launch an app in demo mode on each screen listed in .github/qa/<app>.json, take a
screenshot, keep the app's log for that launch and any crash report.

usage: qa_capture.py <qa.json> <products dir> <out dir>

qa.json: {"scheme", "bundle", "location"?, "grant"?: [...],
          "shots": [{"name", "args", "wait", "size"? (content size, e.g. accessibility-large),
                     "appearance"? ("light"/"dark"), "url"? (opened after launch)}],
          "watch"?: {"product", "bundle", "shots": [...]}}
Writes <out>/<name>.png, <out>/logs/<name>.log, <out>/crashes/*, <out>/summary.txt. Demo data only.

It never hangs silently: every simctl call has a timeout, the whole pass has a time budget (QA_BUDGET_MIN, default
50; screens still to do when it runs out are listed as SKIPPED), a line with the runner's load, free memory and
busiest processes is printed at least once a minute while anything is slow, and summary.txt is rewritten after
every screen, so a run that is cut short still shows how far it got. The app is stopped as soon as its screenshot
is taken, and stopped early if it grows past QA_APP_MAX_MB (default 3072) of memory. Its log is read once per pass
and split by time into each screen's log (a log show per screen took a minute or two on these runners).
QA_SKIP (a regex matched against screen names) and QA_SKIP_ARGS (matched against a screen's launch arguments,
reason in QA_SKIP_ARGS_WHY) leave screens out: qa.yml uses QA_SKIP_ARGS for screens with a live 3D map, which
have taken the Intel runner down every time (GitHub "lost communication" with it and kept no log).
With QA_PUSH_URL and QA_BRANCH set, <out> is pushed to that branch after every screen (and while something is
slow), with progress.txt (every line printed here), so even a runner that dies leaves what it captured.
Shards (qa.yml splits a long pass, e.g. Roamr's, over several runners): with QA_SHARD set, only the iPhone screens
named in QA_SHOTS (comma-separated; empty = no iPhone pass, the simulator isn't even booted) are taken, and the Watch
screens only when QA_WATCH is 1.
Exit code 1 only when not a single screen could be captured (no simulator, it didn't boot, app missing).
"""
import functools, glob, json, os, plistlib, re, shutil, subprocess, sys, tempfile, threading, time
print = functools.partial(print, flush=True)

cfg = json.load(open(sys.argv[1]))
products, out = sys.argv[2], sys.argv[3]
for d in ("", "logs", "crashes"):
    os.makedirs(os.path.join(out, d), exist_ok=True)
summary = []
CRASH_DIR = os.path.expanduser("~/Library/Logs/DiagnosticReports")
started = time.time()
BUDGET = float(os.environ.get("QA_BUDGET_MIN") or 50) * 60
DEADLINE = started + BUDGET
MAX_MB = float(os.environ.get("QA_APP_MAX_MB") or 3072)


def regex(var):
    v = os.environ.get(var, "").strip()
    try:
        return re.compile(v) if v else None
    except re.error as e:
        print(f"::warning title=QA {cfg['scheme']}::{var} is not a valid regex ({e}); ignored")
        return None


SKIP, SKIP_ARGS = regex("QA_SKIP"), regex("QA_SKIP_ARGS")
SKIP_ARGS_WHY = os.environ.get("QA_SKIP_ARGS_WHY") or "QA_SKIP_ARGS"
PUSH_URL, BRANCH = os.environ.get("QA_PUSH_URL", ""), os.environ.get("QA_BRANCH", "")
SHARD = os.environ.get("QA_SHARD", "").strip()
if SHARD:
    want = {n.strip() for n in os.environ.get("QA_SHOTS", "").split(",") if n.strip()}
    cfg["shots"] = [s for s in cfg.get("shots", []) if s["name"] in want]
    if os.environ.get("QA_WATCH", "0") != "1":
        cfg.pop("watch", None)
pub = {"git": None, "last": 0.0}
pub_lock = threading.Lock()
APP_NAME = cfg["scheme"]
counts = {"OK": 0, "CRASH": 0, "KILLED": 0, "SKIPPED": 0}
busy = {"what": "starting", "since": time.time()}    # what we are waiting on, for the heartbeat
windows = []                                       # (screen name, start, end) of this pass, for its app log
line_of = {}                                       # screen name -> its line in summary


def clock():
    m, s = divmod(int(time.time() - started), 60)
    return f"[{m:02d}:{s:02d}]"


def left():
    return DEADLINE - time.time()


def say(line):
    """Print a progress line and keep it in progress.txt (pushed with the results)."""
    line = f"{clock()} {line}"
    print(line)
    try:
        with open(os.path.join(out, "progress.txt"), "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def publish(why, min_gap=0):
    """Push <out> as it is now to the results branch, so a run whose runner dies still leaves what it captured."""
    if not (PUSH_URL and BRANCH) or time.time() - pub["last"] < min_gap or not pub_lock.acquire(blocking=False):
        return
    try:
        if pub["git"] is None:
            pub["git"] = os.path.join(tempfile.mkdtemp(prefix="qa-git-"), ".git")
            subprocess.run(["git", "init", "-q", os.path.dirname(pub["git"])], capture_output=True, timeout=30)
        g = ["git", "--git-dir", pub["git"], "--work-tree", out,
             "-c", "user.name=TreeHub CI", "-c", "user.email=ci@users.noreply.github.com"]
        subprocess.run(g + ["add", "-A"], capture_output=True, timeout=60)
        subprocess.run(g + ["commit", "-q", "-m", f"QA in progress: {why}"], capture_output=True, timeout=60)
        r = subprocess.run(g + ["push", "-q", "-f", PUSH_URL, f"HEAD:refs/heads/{BRANCH}"],
                           capture_output=True, text=True, timeout=120)
        pub["last"] = time.time()
        if r.returncode:
            print(f"  (progress not pushed: {r.stderr.strip()[-200:]})")
    except Exception as e:
        print(f"  (progress not pushed: {e})")
    finally:
        pub_lock.release()


def save_summary():
    open(os.path.join(out, "summary.txt"), "w").write("\n".join(summary) + "\n")


def note(line, level=None, screen=None):
    """A result line: printed, added to summary.txt right away, and (level) shown on the run's page."""
    say(line)
    if screen:
        line_of[screen] = len(summary)
    summary.append(line)
    save_summary()
    if level:
        print(f"::{level} title=QA {APP_NAME}::{line}")


def machine():
    """Load, free memory, swap and the busiest processes, in one line."""
    parts = []
    try:
        parts.append(f"load {os.getloadavg()[0]:.1f} on {os.cpu_count()} cpus")
    except OSError:
        pass
    try:
        vm = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=10).stdout
        page = int(re.search(r"page size of (\d+)", vm).group(1))
        free = sum(int(re.search(rf"{k}:\s+(\d+)", vm).group(1)) for k in ("Pages free", "Pages inactive", "Pages speculative"))
        parts.append(f"~{free * page >> 20} MB free")
        sw = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True, timeout=10).stdout
        m = re.search(r"used = ([\d.]+)M", sw)
        if m:
            parts.append(f"swap {float(m.group(1)):.0f} MB")
    except Exception:
        pass
    try:
        rows = subprocess.run(["ps", "-Ao", "pcpu=,rss=,comm=", "-r"], capture_output=True, text=True, timeout=10).stdout
        top = []
        for row in rows.splitlines()[:3]:
            cpu, rss, comm = row.split(None, 2)
            top.append(f"{os.path.basename(comm)} {cpu}% {int(rss) >> 10} MB")
        parts.append("busiest: " + ", ".join(top))
    except Exception:
        pass
    return "; ".join(parts)


def heartbeat():
    while True:
        time.sleep(60)
        waited = time.time() - busy["since"]
        if waited >= 50:
            say(f"  ... still on {busy['what']} ({int(waited)}s); {machine()}")
            publish("waiting on " + busy["what"], min_gap=90)


threading.Thread(target=heartbeat, daemon=True).start()


def sh(*cmd, timeout=240):
    t = max(10, min(timeout, left() + 120))    # nothing runs far past the budget
    busy.update(what=" ".join(c for c in cmd[1:6] if not re.fullmatch(r"[0-9A-F-]{36}", c))[:70], since=time.time())
    try:
        return subprocess.run(list(cmd), capture_output=True, text=True, timeout=t)
    except subprocess.TimeoutExpired:
        print(f"{clock()}   ! timed out after {int(t)}s: {' '.join(cmd[:6])}")
        return subprocess.CompletedProcess(cmd, 1, "", "timeout")


def pick(platform, prefer):
    best = None
    try:
        devs_by_rt = json.loads(sh("xcrun", "simctl", "list", "devices", "available", "-j", timeout=120).stdout)["devices"]
    except Exception:
        return None
    for rt, devs in devs_by_rt.items():
        if platform not in rt: continue
        ver = tuple(int(x) for x in re.findall(r"\d+", rt.split(platform)[-1]))
        for dv in devs:
            score = (ver, prefer(dv["name"]))
            if best is None or score > best[0]: best = (score, dv["udid"], dv["name"], rt)
    return best


def state(udid):
    try:
        devs = json.loads(sh("xcrun", "simctl", "list", "devices", "-j", timeout=120).stdout)["devices"]
        return next((d.get("state", "?") for ds in devs.values() for d in ds if d["udid"] == udid), "missing")
    except Exception:
        return "unknown"


def boot(udid, label):
    """Boot and wait. These runners are slow to boot (load in the hundreds while iOS starts its daemons) and
    bootstatus can give up before the device is up, so keep waiting while it is still Booting, and boot once more
    if it went back to Shutdown. Up to 15 minutes (less if the budget is short)."""
    t0 = time.time()
    end = t0 + min(900, max(120, left()))
    for attempt in (1, 2):
        r = sh("xcrun", "simctl", "boot", udid, timeout=300)
        if r.returncode and "current state: Booted" not in r.stderr:
            say(f"  simctl boot: {(r.stderr or r.stdout).strip()[-300:]}")
        r = sh("xcrun", "simctl", "bootstatus", udid, "-b", timeout=max(60, int(end - time.time())))
        st = state(udid)
        if st != "Booted":
            say(f"  bootstatus ended (exit {r.returncode}) with the device {st}: {(r.stdout + r.stderr).strip()[-300:]}")
        while st == "Booting" and time.time() < end:
            busy.update(what=f"{label} simulator booting", since=busy["since"])
            time.sleep(15)
            st = state(udid)
        if st == "Booted":
            say(f"{label} simulator booted in {int(time.time() - t0)}s; {machine()}")
            publish(f"{label} simulator booted")
            return True
        if time.time() >= end:
            break
    note(f"FAILED {label} simulator did not boot in {int(time.time() - t0)}s (state: {st})", "error")
    return False


def executable(app):
    try:
        return plistlib.load(open(os.path.join(app, "Info.plist"), "rb")).get("CFBundleExecutable")
    except Exception:
        return os.path.basename(app)[:-4]


def flat(path):
    """True when everything below the status bar is one colour (the launch screen)."""
    try:
        from PIL import Image, ImageStat
        im = Image.open(path).convert("L")
        w, h = im.size
        return max(ImageStat.Stat(im.crop((0, int(h * 0.1), w, h))).stddev) < 1.0
    except Exception:
        return False


def rss_mb(pid):
    """The app's memory in MB (simulator apps are ordinary processes on the runner), or None once it's gone."""
    try:
        r = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True, timeout=10)
        return int(r.stdout.split()[0]) >> 10 if r.stdout.strip() else None
    except Exception:
        return 0


def watch(pid, secs, what):
    """Wait `secs` while the app is on screen; stop it if it passes MAX_MB. Returns (peak MB, killed)."""
    busy.update(what=what, since=time.time())
    end, peak = time.time() + secs, 0
    while True:
        mb = rss_mb(pid) if pid else 0
        if mb is None:
            return peak, False          # it quit; the running check reports that
        peak = max(peak, mb)
        if mb > MAX_MB:
            try:
                os.kill(pid, 9)
            except OSError:
                pass
            return peak, True
        if time.time() >= end:
            return peak, False
        time.sleep(min(2, max(0.1, end - time.time())))


def running(udid, bundle, pid):
    if pid:
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
    r = sh("xcrun", "simctl", "spawn", udid, "launchctl", "list", timeout=60)
    return r.stderr == "timeout" or bundle in r.stdout


def run(udid, bundle, exe, shots, prefix=""):
    for s in shots:
        name = prefix + s["name"]
        args = s.get("args", "")
        if SKIP and SKIP.search(name):
            counts["SKIPPED"] += 1
            note(f"SKIPPED {name}  {args}  (QA_SKIP)")
            continue
        if SKIP_ARGS and SKIP_ARGS.search(args):
            counts["SKIPPED"] += 1
            note(f"SKIPPED {name}  {args}  ({SKIP_ARGS_WHY})")
            continue
        if left() < 60:
            counts["SKIPPED"] += 1
            note(f"SKIPPED {name}  {args}  (the {BUDGET / 60:.0f}-minute budget for this pass is used up)", "warning")
            continue
        t0 = time.time()
        sh("xcrun", "simctl", "terminate", udid, bundle, timeout=90)
        sh("xcrun", "simctl", "ui", udid, "content_size", s.get("size", "large"), timeout=90)
        sh("xcrun", "simctl", "ui", udid, "appearance", s.get("appearance", "dark"), timeout=90)
        r = sh("xcrun", "simctl", "launch", udid, bundle, *args.split(), timeout=180)
        if r.returncode:
            print("  ! launch:", (r.stderr or r.stdout).strip()[:300])
        m = re.search(r":\s*(\d+)\s*$", r.stdout.strip())
        pid = int(m.group(1)) if m else None
        if s.get("url"):
            time.sleep(4)
            sh("xcrun", "simctl", "openurl", udid, s["url"], timeout=90)
        peak, killed = watch(pid, float(s.get("wait", 8)), name + " on screen")
        ok = not killed and running(udid, bundle, pid)
        shot = os.path.join(out, name + ".png")
        sh("xcrun", "simctl", "io", udid, "screenshot", shot, timeout=120)
        # Still on the plain launch screen (slow cold start on the CI Mac)? Wait and take it again.
        for _ in range(4):
            if killed or left() < 30 or not flat(shot): break
            print("  (still on the launch screen, waiting)")
            more, killed = watch(pid, 8, name + " launch screen")
            peak = max(peak, more)
            sh("xcrun", "simctl", "io", udid, "screenshot", shot, timeout=120)
        # Stop the app right after its screenshot, so a busy screen isn't still drawing meanwhile. Its log is read
        # once for the whole pass (collect_logs): a log show per screen took a minute or two on these runners.
        sh("xcrun", "simctl", "terminate", udid, bundle, timeout=90)
        windows.append((name, t0, time.time()))
        status = "KILLED" if killed else ("OK" if ok else "CRASH")
        counts[status] += 1
        extra = ""
        if killed:
            extra += f"  (stopped: the app passed {MAX_MB:.0f} MB of memory)"
        took = f"  ({int(time.time() - t0)}s" + (f", {peak} MB" if peak else "") + ")"
        note(f"{status + ' ':<6}{name}  {args}{extra}{took}", None if status == "OK" else "warning", screen=name)
        say(f"  {machine()}")
        publish(name)


def collect_logs(udid, exe):
    """One log show for the pass just done, split by time into logs/<screen>.log and .errors.log; screens with
    error/fault lines get the count added to their summary line."""
    if not windows:
        return
    stamp = lambda t: time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))
    log = sh("xcrun", "simctl", "spawn", udid, "log", "show", "--start", stamp(windows[0][1] - 2), "--end",
             stamp(windows[-1][2] + 2), "--style", "compact", "--predicate", f'process == "{exe}"',
             timeout=int(min(600, max(180, left() + 300))))
    if log.stderr == "timeout":
        say("  (no app logs for this pass: log show timed out)")
        windows.clear()
        return
    per = {n: [] for n, _, _ in windows}
    for line in log.stdout.splitlines():
        m = re.match(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)(\.\d+)?\s", line)
        if not m:
            continue
        t = time.mktime(time.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")) + float(m.group(2) or 0)
        for n, a, b in windows:
            if a - 1 <= t <= b + 1:
                per[n].append(line)
                break
    for n, lines in per.items():
        open(os.path.join(out, "logs", n + ".log"), "w").write("\n".join(lines) + "\n")
        # Compact style: "<date> <time> <type> <process>[pid:tid] ..."; E = error, F = fault.
        faults = [l for l in lines if re.match(r"^\S+ \S+ (E|F)\s", l)]
        open(os.path.join(out, "logs", n + ".errors.log"), "w").write("\n".join(faults))
        if faults and n in line_of:
            summary[line_of[n]] += f"  [{len(faults)} error/fault log lines]"
    save_summary()
    say(f"  app logs: {sum(len(v) for v in per.values())} lines for {len(per)} screens")
    windows.clear()


# ---- iPhone
app = os.path.join(products, "Debug-iphonesimulator", cfg["scheme"] + ".app")
if SHARD:
    say(f"shard {SHARD}: iPhone screens {', '.join(x['name'] for x in cfg['shots']) or 'none'}; "
        f"Watch screens {'yes' if cfg.get('watch') else 'no'}")
if not cfg["shots"]:
    pass
elif not os.path.isdir(app):
    note(f"FAILED {app} was not built", "error")
    sys.exit(1)
else:
    best = pick("iOS", lambda n: (n.startswith("iPhone"), "Pro Max" in n, "Pro" in n))
    if not best:
        note("FAILED no iOS simulator is available on this runner", "error")
        sys.exit(1)
    udid = best[1]
    say(f"iPhone simulator: {best[2]} {best[3]}; budget {BUDGET / 60:.0f} min; {machine()}")
    try:
        gpu = subprocess.run(["system_profiler", "SPDisplaysDataType"], capture_output=True, text=True, timeout=60).stdout
        say("  graphics: " + "; ".join(l.strip() for l in gpu.splitlines() if re.search(r"Chipset|Metal|VRAM|Vendor", l))[:300])
    except Exception:
        pass
    if not boot(udid, "iPhone"):
        sys.exit(1)
    sh("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
    sh("xcrun", "simctl", "install", udid, app, timeout=300)
    for svc in cfg.get("grant", []):
        sh("xcrun", "simctl", "privacy", udid, "grant", svc, cfg["bundle"])
    if cfg.get("location"):
        sh("xcrun", "simctl", "location", udid, "set", cfg["location"])
    run(udid, cfg["bundle"], executable(app), cfg["shots"])
    collect_logs(udid, executable(app))
    sh("xcrun", "simctl", "ui", udid, "content_size", "large")
    sh("xcrun", "simctl", "shutdown", udid, timeout=180)

# ---- Watch (alone: the phone app is not running on a paired phone)
w = cfg.get("watch")
if w:
    wapp = os.path.join(products, "Debug-watchsimulator", w["product"] + ".app")
    if not os.path.isdir(wapp):
        note("WATCH NOT BUILT " + wapp)
    elif left() < 240:
        counts["SKIPPED"] += len(w["shots"])
        note(f"SKIPPED the Watch screens (the {BUDGET / 60:.0f}-minute budget for this pass is used up)", "warning")
    else:
        best = pick("watchOS", lambda n: ("Ultra" in n, "Series" in n, n))
        if best:
            wid = best[1]
            say(f"Watch simulator: {best[2]} {best[3]}")
            if boot(wid, "Watch"):
                sh("xcrun", "simctl", "install", wid, wapp, timeout=300)
                run(wid, w["bundle"], executable(wapp), w["shots"], prefix="watch-")
                collect_logs(wid, executable(wapp))
            sh("xcrun", "simctl", "shutdown", wid, timeout=180)
        else:
            note("NO WATCH SIMULATOR")

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
summary.append(f"{counts['OK']} OK, {counts['CRASH']} crashed, {counts['KILLED']} stopped for memory, "
               f"{counts['SKIPPED']} skipped, in {(time.time() - started) / 60:.0f} min")
save_summary()
publish("done")
print("\n".join(summary))
if not (counts["OK"] or counts["CRASH"] or counts["KILLED"]):
    print(f"::error title=QA {APP_NAME}::no screen was captured")
    sys.exit(1)
