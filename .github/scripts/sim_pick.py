"""Pick an iPhone simulator for the screenshot steps and (with --boot) make sure it is booted.

usage: sim_pick.py [--boot]

Prints the simulator's UDID on stdout, or prints nothing (exit code 0) when no usable simulator exists or none
would boot, so a caller can skip with a warning instead of failing. Notes go to stderr.
Order: an iPhone that is already booted (an earlier step's), then the newest iOS runtime's iPhone Pro Max, Pro,
any iPhone, then any other iOS device. A device that won't boot is shut down again and one more is tried.
Booting gives up after SIM_BOOT_BUDGET seconds in all (default 720), so the caller's step timeout is never hit.
"""
import json, os, re, subprocess, sys, time

BOOT = "--boot" in sys.argv[1:]
DEADLINE = time.time() + float(os.environ.get("SIM_BOOT_BUDGET", "720"))


def note(*a):
    print(*a, file=sys.stderr, flush=True)


def sh(*cmd, timeout=120):
    try:
        return subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", f"timed out after {timeout}s")
    except OSError as e:
        return subprocess.CompletedProcess(cmd, 127, "", str(e))


def devices():
    r = sh("xcrun", "simctl", "list", "devices", "available", "-j")
    try:
        return json.loads(r.stdout)["devices"]
    except Exception:
        note("simctl list failed:", (r.stderr or r.stdout).strip()[:300])
        return {}


def candidates():
    out = []
    for rt, devs in devices().items():
        if "iOS" not in rt:
            continue
        ver = tuple(int(x) for x in re.findall(r"\d+", rt.split("iOS")[-1]))
        for dv in devs:
            n = dv.get("name", "")
            score = (dv.get("state") == "Booted", n.startswith("iPhone"), ver, "Pro Max" in n, "Pro" in n)
            out.append((score, dv["udid"], n, rt.split(".")[-1], dv.get("state")))
    return sorted(out, reverse=True)


def booted(udid):
    return any(d["udid"] == udid and d.get("state") == "Booted" for devs in devices().values() for d in devs)


def left():
    return int(DEADLINE - time.time())


cands = candidates()
if not cands:
    note("No iOS simulator is available on this runner.")
    sys.exit(0)
for _, udid, name, rt, state in cands[:2]:
    if not BOOT or state == "Booted":
        note(f"Simulator: {name} ({rt}){' (already booted)' if state == 'Booted' else ''}")
        print(udid)
        sys.exit(0)
    if left() < 120:
        break
    t0 = time.time()
    note(f"Booting {name} ({rt}) ...")
    r = sh("xcrun", "simctl", "boot", udid, timeout=min(240, left()))
    if r.returncode and "current state: Booted" not in r.stderr:
        note("  boot failed:", (r.stderr or r.stdout).strip()[:300])
    sh("xcrun", "simctl", "bootstatus", udid, "-b", timeout=max(30, left() - 60))
    if booted(udid):
        note(f"Simulator: {name} ({rt}), booted in {int(time.time() - t0)}s")
        sh("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged",
           "--batteryLevel", "100", timeout=60)
        print(udid)
        sys.exit(0)
    note(f"  {name} did not finish booting after {int(time.time() - t0)}s; trying another")
    sh("xcrun", "simctl", "shutdown", udid, timeout=120)
note("No simulator would boot.")
