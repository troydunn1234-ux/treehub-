"""Run one bundled web app (the WKWebView shell in WebApps/Shell) in the simulator and fail on a real crash.

usage: webcheck.py <udid> <path/to/App.app> <bundle id> <shots dir>

A copy of the built app gets a small probe <script> at the top of web/index.html; the build products are never
changed. From the page's first line on, the probe records uncaught JavaScript errors, unhandled promise
rejections, console.error calls and resources that failed to load, then saves a report through the shell's own
storage bridge (window.claude.use("db")) into the app's Documents/store.json, where this script reads it.

Fails (exit 1) when the app process dies, the page never reports (it didn't load, its scripts didn't run or the
storage bridge is broken), the shell had to reload the page (its web content process crashed or was killed), or
the page threw an uncaught error or left a promise rejection unhandled. console.error calls and failed resource
loads are only warnings. Writes shots/web-<App>-0-splash.png, -1-loaded.png and -report.json. Demo mode only.
"""
import atexit, glob, json, os, re, shutil, subprocess, sys, tempfile, time

udid, app, bundle, shots = sys.argv[1:5]
name = os.path.basename(app.rstrip("/"))[:-4]
os.makedirs(shots, exist_ok=True)
KEY = "__ci/probe"   # document path in the shell's store; nothing in the apps reads it

PROBE = """<script>/* CI probe: added to a copy of the build by .github/scripts/webcheck.py, never shipped */
(function () {
  if (window.__ciProbe) return;
  var R = window.__ciProbe = { start: Date.now(), errors: [], rejections: [], console: [], resources: [] };
  function str(x) {
    try {
      if (x && x.stack) return String(x.stack);
      if (x && x.message) return String(x.message);
      return typeof x === "object" ? JSON.stringify(x) : String(x);
    } catch (e) { return String(x); }
  }
  function add(list, s) { if (list.length < 20) list.push(String(s).slice(0, 800)); }
  window.addEventListener("error", function (e) {
    var t = e && e.target;
    if (t && t !== window && t.tagName) { add(R.resources, t.tagName.toLowerCase() + " " + (t.src || t.href || "")); return; }
    add(R.errors, (e.message || "error") + " (" + (e.filename || "?") + ":" + (e.lineno || 0) + ":" + (e.colno || 0) + ")" +
        (e.error && e.error.stack ? "\\n" + e.error.stack : ""));
  }, true);
  window.addEventListener("unhandledrejection", function (e) { add(R.rejections, str(e && e.reason)); });
  var ce = console.error;
  console.error = function () {
    try { add(R.console, Array.prototype.map.call(arguments, str).join(" ")); } catch (x) {}
    return ce.apply(console, arguments);
  };
  function report(tag) {
    try {
      R.tag = tag; R.at = Date.now(); R.ready = document.readyState;
      try {
        var n = performance.getEntriesByType("navigation")[0];
        R.nav = n ? n.type : (performance.navigation && performance.navigation.type === 1 ? "reload" : "navigate");
      } catch (x) {}
      R.elements = document.getElementsByTagName("*").length;
      R.text = document.body ? (document.body.innerText || "").length : 0;
      var c = window.claude;
      if (!c || typeof c.use !== "function") return;
      c.use("db").then(function (db) { if (db) return db.doc("__ci/probe").set(JSON.parse(JSON.stringify(R))); })
                 .then(null, function () {});
    } catch (e) {}
  }
  window.addEventListener("load", function () { setTimeout(function () { report("load+3s"); }, 3000); });
  setTimeout(function () { report("final"); }, 12000);
})();
</script>
"""


def sh(*cmd, timeout=120):
    try:
        return subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"  ! timed out after {timeout}s: {' '.join(cmd[:6])}", flush=True)
        return subprocess.CompletedProcess(cmd, 124, "", "timeout")


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def running(pid):
    if pid:
        return alive(pid)
    r = sh("xcrun", "simctl", "spawn", udid, "launchctl", "list", timeout=60)
    return r.returncode == 124 or bundle in r.stdout


def screenshot(path):
    sh("xcrun", "simctl", "io", udid, "screenshot", path, timeout=90)


def read_report(store, since):
    try:
        rep = json.load(open(store)).get(KEY)
    except Exception:
        return None
    # Only a report from this launch counts (the simulator shares the runner's clock).
    return rep if isinstance(rep, dict) and rep.get("at", 0) / 1000 >= since - 5 else None


def diagnostics(t0):
    """On failure: the newest crash report from this launch and the app's recent error/fault log lines."""
    reports = [f for f in glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/**/*.ips"), recursive=True)
               if os.path.getmtime(f) >= t0 - 5 and (name in os.path.basename(f) or "WebContent" in os.path.basename(f))]
    for f in sorted(reports, key=os.path.getmtime)[-2:]:
        print("  crash report:", os.path.basename(f))
        try:
            raw = open(f, errors="ignore").read().split("\n", 1)
            body = json.loads(raw[1]) if len(raw) > 1 else {}
            print("   exception:", json.dumps(body.get("exception")), "| termination:", json.dumps(body.get("termination"))[:300])
            for k in ("asi", "lastExceptionBacktrace"):
                if body.get(k):
                    print("   ", k, json.dumps(body[k])[:1200])
        except Exception as e:
            print("   (unreadable:", e, ")")
    secs = int(time.time() - t0) + 10
    log = sh("xcrun", "simctl", "spawn", udid, "log", "show", "--last", f"{secs}s", "--style", "compact", "--predicate",
             f'process == "{name}" OR process == "com.apple.WebKit.WebContent"', timeout=150)
    lines = [l for l in log.stdout.splitlines()
             if re.match(r"^\S+ \S+ (E|F)\s", l) or "processDidTerminate" in l or "Fatal error" in l]
    if lines:
        print(f"  --- {name} / WebContent error and fault log lines (last {secs}s) ---")
        print("\n".join("  " + l[:400] for l in lines[-40:]))


# 1. A probed copy of the build.
tmp = tempfile.mkdtemp(prefix="webcheck-")
atexit.register(shutil.rmtree, tmp, True)
copy = os.path.join(tmp, os.path.basename(app.rstrip("/")))
shutil.copytree(app, copy, symlinks=True)
page = os.path.join(copy, "web", "index.html")
probed = os.path.isfile(page)
if probed:
    html = open(page, "rb").read()
    # After <meta charset>, so the page's encoding is still declared within its first 1024 bytes.
    m = re.search(rb"<meta[^>]*charset[^>]*>", html[:4096], re.I) or re.search(rb"<head[^>]*>", html, re.I)
    at = m.end() if m else 0
    open(page, "wb").write(html[:at] + PROBE.encode() + html[at:])
else:
    print(f"WARN  {name}: no web/index.html in the app; checking the app process only")

# 2. Fresh install and a demo launch.
sh("xcrun", "simctl", "terminate", udid, bundle, timeout=60)
sh("xcrun", "simctl", "uninstall", udid, bundle, timeout=120)
r = sh("xcrun", "simctl", "install", udid, copy, timeout=300)
if r.returncode:
    print(f"FAIL  {name}: could not install it in the simulator: {(r.stderr or r.stdout).strip()[:400]}")
    print(f"::error title=Web app {name}::could not install it in the simulator")
    sys.exit(1)
t0 = time.time()
r = sh("xcrun", "simctl", "launch", udid, bundle, "-demo", timeout=180)
m = re.search(r":\s*(\d+)\s*$", r.stdout.strip())
pid = int(m.group(1)) if m else None
if r.returncode or not pid:
    print(f"  ! launch: {(r.stderr or r.stdout).strip()[:300]}")
time.sleep(0.6)
screenshot(os.path.join(shots, f"web-{name}-0-splash.png"))

# 3. Wait for the page's report (written about 3 s after load and again 12 s after the page starts).
store, rep = "", None
while probed and time.time() - t0 < 75:
    if not store:
        container = sh("xcrun", "simctl", "get_app_container", udid, bundle, "data", timeout=60).stdout.strip()
        store = os.path.join(container, "Documents", "store.json") if container else ""
    rep = (read_report(store, t0) if store else None) or rep
    if (rep and rep.get("tag") == "final") or not running(pid):
        break
    time.sleep(2)
if not probed:
    time.sleep(10)
waited = int(time.time() - t0)
screenshot(os.path.join(shots, f"web-{name}-1-loaded.png"))
up = running(pid)
sh("xcrun", "simctl", "terminate", udid, bundle, timeout=60)
if rep:
    json.dump(rep, open(os.path.join(shots, f"web-{name}-report.json"), "w"), indent=1)

# 4. Verdict.
problems, warnings = [], []
if not up:
    problems.append("the app quit while the page was loading (crashed)")
if probed and not rep:
    problems.append(f"the page never reported back in {waited}s (it didn't load, its scripts didn't run, "
                    "or the shell's storage bridge is broken)")
if rep:
    if rep.get("nav") == "reload":
        problems.append("the shell had to reload the page: its web content process crashed or was killed")
    problems += ["uncaught JavaScript error: " + e for e in rep.get("errors", [])]
    problems += ["unhandled promise rejection: " + e for e in rep.get("rejections", [])]
    warnings += ["console.error: " + e for e in rep.get("console", [])]
    warnings += ["failed to load: " + e for e in rep.get("resources", [])]
    if rep.get("tag") != "final":
        warnings.append(f"only the early report arrived within {waited}s (slow runner?)")
for w in warnings:
    print(f"WARN  {name}: {w}")
    print(f"::warning title=Web app {name}::{w.splitlines()[0][:300]}")
if problems:
    for p in problems:
        print(f"FAIL  {name}: {p}")
        print(f"::error title=Web app {name}::{p.splitlines()[0][:300]}")
    diagnostics(t0)
    sys.exit(1)
if rep:
    print(f"OK    {name}  (page ran {(rep['at'] - rep['start']) / 1000:.0f}s with no JavaScript errors; "
          f"{rep.get('elements')} elements, {rep.get('text')} characters of text; ready={rep.get('ready')})")
else:
    print(f"OK    {name}  (still running after {waited}s)")
