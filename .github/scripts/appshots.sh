#!/bin/bash
# Runs the native apps built this run in an iPhone simulator with demo data and screenshots them: a Roamr test
# drive, Clicker, Pulse Lab and Still Point. A launch that crashes fails the step; Roamr's drive only warns (MapKit's
# VectorKit hits a SIGFPE on the Intel simulators). Rootbound has its own step (screenshots.sh), the web apps theirs
# (webshots.sh). Apps not built this run are skipped; with no usable simulator the step is skipped with a warning.
set -u
mkdir -p shots
P=build/Build/Products/Debug-iphonesimulator
BUILT=""
for a in Roamr Clicker PulseLab StillPoint; do [ -d "$P/$a.app" ] && BUILT="$BUILT $a"; done
[ -n "$BUILT" ] || { echo "None of Roamr, Clicker, Pulse Lab or Still Point was built this run; nothing to run."; exit 0; }
echo "Running:$BUILT"

UDID=$(python3 .github/scripts/sim_pick.py --boot)
if [ -z "$UDID" ]; then
  echo "::warning title=App screenshots skipped::No usable iPhone simulator on this runner, so$BUILT were not run."
  exit 0
fi
FAIL=0
limit() { perl -e 'alarm shift; exec @ARGV' "$@"; }   # limit <seconds> <command...>: no simctl call can hang the step

# On a crash, show why: newest simulator crash report for the app (Swift fatal error text lives in "asi"/"exception").
crashinfo() {
  { _crashinfo; } 2>&1 | tee "shots/crash-$(date +%s).txt"
}
_crashinfo() {
  sleep 45
  echo "  reports dir:"; ls -lat ~/Library/Logs/DiagnosticReports 2>/dev/null | head -8
  find ~/Library/Logs -iname "*roamr*" 2>/dev/null | head -5
  f=$(find ~/Library/Logs/DiagnosticReports ~/Library/Logs/CrashReporter -name "Roamr*.ips" 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
  [ -n "$f" ] || f=$(find ~/Library/Logs/DiagnosticReports -name "*.ips" -newer shots/drive-1.png 2>/dev/null | head -1)
  ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -5
  echo "  --- unified log (Roamr, last 3 min) ---"
  limit 90 xcrun simctl spawn "$UDID" log show --last 2m --style compact --predicate 'process == "Roamr" OR eventMessage CONTAINS "Roamr" OR eventMessage CONTAINS "com.troydunn.roamr"' 2>/dev/null | grep -E "CRASHTRACE|Fatal error" | head -60
  [ -n "$f" ] || { echo "  (no crash report found)"; return; }
  echo "  crash report: $f"
  python3 - "$f" <<'PY' || head -c 3000 "$f"
import json,sys
raw=open(sys.argv[1]).read().split("\n",1)
hdr=json.loads(raw[0]); body=json.loads(raw[1]) if len(raw)>1 else {}
print("  app:",hdr.get("app_name"),"| exception:",json.dumps(body.get("exception")))
print("  termination:",json.dumps(body.get("termination")))
for k in ("asi","lastExceptionBacktrace"):
    if body.get(k): print(" ",k,":",json.dumps(body[k])[:1500])
t=body.get("threads",[])
for th in t:
    if th.get("triggered"):
        frames=th.get("frames",[])[:25]
        imgs=body.get("usedImages",[])
        for fr in frames:
            img=imgs[fr.get("imageIndex",0)].get("name","?") if fr.get("imageIndex",0)<len(imgs) else "?"
            print("   ",img,fr.get("symbol",""),"+",fr.get("imageOffset",0),fr.get("sourceFile",""),fr.get("sourceLine",""))
PY
}
# The CI simulator sometimes shuts itself down mid-run; boot it again before each app.
booted() {
  if ! limit 60 xcrun simctl list devices booted | grep -q "$UDID"; then
    echo "(simulator was shut down; booting again)"
    limit 240 xcrun simctl boot "$UDID" || true
    limit 480 xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
    limit 60 xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 > /dev/null 2>&1 || true
  fi
}
# up <bundle id>: is the app still running in the simulator? (A launchctl that hangs says nothing about the app.)
up() {
  local out; out=$(limit 60 xcrun simctl spawn "$UDID" launchctl list); [ $? -eq 142 ] && return 0
  echo "$out" | grep -q "$1"
}

# Roamr test drive on I-280 at ~80 mph: truck avatar, chase cam, speed limit HUD, colored route.
APP=$P/Roamr.app
booted
if [ -d "$APP" ]; then
  limit 300 xcrun simctl install "$UDID" "$APP"
  for svc in location location-always motion; do xcrun simctl privacy "$UDID" grant $svc com.troydunn.roamr || true; done
  xcrun simctl location "$UDID" set 37.3229,-122.0322 || true
  limit 120 xcrun simctl launch "$UDID" com.troydunn.roamr -demo -autodrive || echo "launch failed"
  sleep 4
  # Follow a real stretch of I-280 from OpenStreetMap so the speed-limit lookup has a road to find.
  ROUTE=$(curl -s -m 25 -G https://overpass-api.de/api/interpreter --data-urlencode \
    'data=[out:json][timeout:20];way(around:600,37.3302,-122.0480)[highway=motorway];out tags geom;' | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)["elements"]
except Exception:
    sys.exit(0)
ways=sorted(d,key=lambda w:-len(w.get("geometry",[])))
for w in ways[:2]: sys.stderr.write("way %s maxspeed=%s ref=%s pts=%d\n"%(w["id"],w["tags"].get("maxspeed"),w["tags"].get("ref"),len(w["geometry"])))
if ways:
    g=ways[0]["geometry"]
    step=max(1,len(g)//14)
    print(" ".join("%.6f,%.6f"%(p["lat"],p["lon"]) for p in g[::step]))
')
  echo "Drive route: ${ROUTE:-fallback}"
  [ -n "$ROUTE" ] || ROUTE="37.3229,-122.0322 37.3262,-122.0400 37.3302,-122.0480 37.3344,-122.0560 37.3381,-122.0640"
  xcrun simctl location "$UDID" start --speed=36 --interval=1 $ROUTE || true
  sleep 30; limit 90 xcrun simctl io "$UDID" screenshot "shots/drive-1.png" > /dev/null 2>&1
  sleep 20; limit 90 xcrun simctl io "$UDID" screenshot "shots/drive-2.png" > /dev/null 2>&1
  if up com.troydunn.roamr; then echo "OK    roamr-drive"; else echo "WARN  roamr-drive died in the simulator (known: MapKit VectorKit SIGFPE on Intel sims)"; crashinfo; fi
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.roamr || true
  # Same drive with turn-by-turn directions on
  booted
  limit 120 xcrun simctl launch "$UDID" com.troydunn.roamr -demo -autodrive -nav > /dev/null
  sleep 4
  xcrun simctl location "$UDID" start --speed=36 --interval=1 $ROUTE || true
  sleep 25; limit 90 xcrun simctl io "$UDID" screenshot "shots/drive-3-nav.png" > /dev/null 2>&1
  if up com.troydunn.roamr; then echo "OK    roamr-nav"; else echo "WARN  roamr-nav died in the simulator (known: MapKit VectorKit SIGFPE on Intel sims)"; crashinfo; fi
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.roamr || true
  xcrun simctl location "$UDID" clear || true
fi

# Clicker in demo mode (pretend-paired TV): apps grid and remote.
APP=$P/Clicker.app
booted
if [ -d "$APP" ]; then
  limit 300 xcrun simctl install "$UDID" "$APP"
  limit 120 xcrun simctl launch "$UDID" com.troydunn.clicker -demo > /dev/null; sleep 5
  limit 90 xcrun simctl io "$UDID" screenshot shots/clicker-1-apps.png > /dev/null 2>&1
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.clicker
  limit 120 xcrun simctl launch "$UDID" com.troydunn.clicker -demo -remote > /dev/null; sleep 5
  limit 90 xcrun simctl io "$UDID" screenshot shots/clicker-2-remote.png > /dev/null 2>&1
  if up com.troydunn.clicker; then echo "OK    clicker"; else echo "CRASH clicker"; FAIL=1; fi
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.clicker
  limit 120 xcrun simctl launch "$UDID" com.troydunn.clicker -demo -pc > /dev/null; sleep 5
  limit 90 xcrun simctl io "$UDID" screenshot shots/clicker-3-pc.png > /dev/null 2>&1
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.clicker
  limit 120 xcrun simctl launch "$UDID" com.troydunn.clicker -demo -switcher > /dev/null; sleep 5
  limit 90 xcrun simctl io "$UDID" screenshot shots/clicker-4-switcher.png > /dev/null 2>&1
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.clicker
  limit 120 xcrun simctl launch "$UDID" com.troydunn.clicker -demo -picker > /dev/null; sleep 5
  limit 90 xcrun simctl io "$UDID" screenshot shots/clicker-5-picker.png > /dev/null 2>&1
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.clicker
  limit 120 xcrun simctl launch "$UDID" com.troydunn.clicker > /dev/null; sleep 4
  limit 90 xcrun simctl io "$UDID" screenshot shots/clicker-0-setup.png > /dev/null 2>&1
  if up com.troydunn.clicker; then echo "OK    clicker-setup"; else echo "CRASH clicker-setup"; FAIL=1; fi
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.clicker || true
fi

# Pulse Lab in demo mode (fake Apple Health + WHOOP data): Today, Sleep, Heart, Moves, VS.
APP=$P/PulseLab.app
booted
if [ -d "$APP" ]; then
  limit 300 xcrun simctl install "$UDID" "$APP"
  for T in today sleep heart moves vs; do
    limit 60 xcrun simctl terminate "$UDID" com.troydunn.pulselab 2>/dev/null || true
    limit 120 xcrun simctl launch "$UDID" com.troydunn.pulselab -demo -tab $T > /dev/null; sleep 5
    limit 90 xcrun simctl io "$UDID" screenshot "shots/pulse-$T.png" > /dev/null 2>&1
  done
  if up com.troydunn.pulselab; then echo "OK    pulselab"; else echo "CRASH pulselab"; FAIL=1; fi
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.pulselab 2>/dev/null || true
fi

# Still Point (meditation) in demo mode: Today, Traditions, Journey, and a breathing session.
APP=$P/StillPoint.app
booted
if [ -d "$APP" ]; then
  limit 300 xcrun simctl install "$UDID" "$APP"
  for T in today traditions journey; do
    limit 60 xcrun simctl terminate "$UDID" com.troydunn.stillpoint 2>/dev/null || true
    limit 120 xcrun simctl launch "$UDID" com.troydunn.stillpoint -demo -tab $T > /dev/null; sleep 5
    limit 90 xcrun simctl io "$UDID" screenshot "shots/still-$T.png" > /dev/null 2>&1
  done
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.stillpoint 2>/dev/null || true
  limit 120 xcrun simctl launch "$UDID" com.troydunn.stillpoint -demo -session resonance > /dev/null; sleep 7
  limit 90 xcrun simctl io "$UDID" screenshot "shots/still-session.png" > /dev/null 2>&1
  if up com.troydunn.stillpoint; then echo "OK    stillpoint"; else echo "CRASH stillpoint"; FAIL=1; fi
  limit 60 xcrun simctl terminate "$UDID" com.troydunn.stillpoint 2>/dev/null || true
fi
exit $FAIL
