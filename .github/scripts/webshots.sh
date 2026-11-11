#!/bin/bash
# Launches each bundled web app in the booted simulator and screenshots it.
set -u
mkdir -p shots
UDID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next(dv["udid"] for rt in d for dv in d[rt]))')
FAIL=0

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
  perl -e 'alarm 90; exec @ARGV' xcrun simctl spawn "$UDID" log show --last 2m --style compact --predicate 'process == "Roamr" OR eventMessage CONTAINS "Roamr" OR eventMessage CONTAINS "com.troydunn.roamr"' 2>/dev/null | grep -E "CRASHTRACE|Fatal error" | head -60
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
  if ! xcrun simctl list devices booted | grep -q "$UDID"; then
    echo "(simulator was shut down; booting again)"
    xcrun simctl boot "$UDID" || true
    xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
    xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 > /dev/null 2>&1 || true
  fi
}
for pair in FoodBook:com.troydunn.foodbook NatalOrbit:com.troydunn.natalorbit RideQuest:com.troydunn.ridequest; do
  T=${pair%%:*}; B=${pair##*:}
  APP=build/Build/Products/Debug-iphonesimulator/$T.app
  [ -d "$APP" ] || { echo "MISSING $APP"; FAIL=1; continue; }
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" "$B" -demo > /dev/null
  sleep 0.6; xcrun simctl io "$UDID" screenshot "shots/web-$T-0-splash.png" > /dev/null 2>&1
  sleep 9;   xcrun simctl io "$UDID" screenshot "shots/web-$T-1-loaded.png" > /dev/null 2>&1
  if xcrun simctl spawn "$UDID" launchctl list | grep -q "$B"; then echo "OK    $T"; else echo "CRASH $T"; FAIL=1; fi
  xcrun simctl terminate "$UDID" "$B" 2>/dev/null || true
done

# Food Book supplements tab (demo stack)
APPF=build/Build/Products/Debug-iphonesimulator/FoodBook.app
booted
if [ -d "$APPF" ]; then
  xcrun simctl terminate "$UDID" com.troydunn.foodbook 2>/dev/null || true
  xcrun simctl launch "$UDID" com.troydunn.foodbook -supps > /dev/null; sleep 5
  xcrun simctl io "$UDID" screenshot shots/food-2-supps.png > /dev/null 2>&1
  xcrun simctl terminate "$UDID" com.troydunn.foodbook 2>/dev/null || true
  xcrun simctl launch "$UDID" com.troydunn.foodbook -demo -snap > /dev/null; sleep 6
  xcrun simctl io "$UDID" screenshot shots/food-3-plate.png > /dev/null 2>&1
  if xcrun simctl spawn "$UDID" launchctl list | grep -q com.troydunn.foodbook; then echo "OK    food-plate"; else echo "CRASH food-plate"; FAIL=1; fi
  xcrun simctl terminate "$UDID" com.troydunn.foodbook 2>/dev/null || true
fi

# Roamr test drive on I-280 at ~80 mph: truck avatar, chase cam, speed limit HUD, colored route.
APP=build/Build/Products/Debug-iphonesimulator/Roamr.app
booted
if [ -d "$APP" ]; then
  xcrun simctl install "$UDID" "$APP"
  for svc in location location-always motion; do xcrun simctl privacy "$UDID" grant $svc com.troydunn.roamr || true; done
  xcrun simctl location "$UDID" set 37.3229,-122.0322 || true
  xcrun simctl launch "$UDID" com.troydunn.roamr -demo -autodrive || echo "launch failed"
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
  sleep 30; xcrun simctl io "$UDID" screenshot "shots/drive-1.png" > /dev/null 2>&1
  sleep 20; xcrun simctl io "$UDID" screenshot "shots/drive-2.png" > /dev/null 2>&1
  if xcrun simctl spawn "$UDID" launchctl list | grep -q com.troydunn.roamr; then echo "OK    roamr-drive"; else echo "CRASH roamr-drive"; crashinfo; FAIL=1; fi
  xcrun simctl terminate "$UDID" com.troydunn.roamr || true
  # Same drive with turn-by-turn directions on
  booted
  xcrun simctl launch "$UDID" com.troydunn.roamr -demo -autodrive -nav > /dev/null
  sleep 4
  xcrun simctl location "$UDID" start --speed=36 --interval=1 $ROUTE || true
  sleep 25; xcrun simctl io "$UDID" screenshot "shots/drive-3-nav.png" > /dev/null 2>&1
  if xcrun simctl spawn "$UDID" launchctl list | grep -q com.troydunn.roamr; then echo "OK    roamr-nav"; else echo "CRASH roamr-nav"; crashinfo; FAIL=1; fi
  xcrun simctl location "$UDID" clear || true
fi

# Clicker in demo mode (pretend-paired TV): apps grid and remote.
APP=build/Build/Products/Debug-iphonesimulator/Clicker.app
booted
if [ -d "$APP" ]; then
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" com.troydunn.clicker -demo > /dev/null; sleep 5
  xcrun simctl io "$UDID" screenshot shots/clicker-1-apps.png > /dev/null 2>&1
  xcrun simctl terminate "$UDID" com.troydunn.clicker
  xcrun simctl launch "$UDID" com.troydunn.clicker -demo -remote > /dev/null; sleep 5
  xcrun simctl io "$UDID" screenshot shots/clicker-2-remote.png > /dev/null 2>&1
  if xcrun simctl spawn "$UDID" launchctl list | grep -q com.troydunn.clicker; then echo "OK    clicker"; else echo "CRASH clicker"; FAIL=1; fi
  xcrun simctl terminate "$UDID" com.troydunn.clicker
  xcrun simctl launch "$UDID" com.troydunn.clicker -demo -pc > /dev/null; sleep 5
  xcrun simctl io "$UDID" screenshot shots/clicker-3-pc.png > /dev/null 2>&1
  xcrun simctl terminate "$UDID" com.troydunn.clicker
  xcrun simctl launch "$UDID" com.troydunn.clicker -demo -switcher > /dev/null; sleep 5
  xcrun simctl io "$UDID" screenshot shots/clicker-4-switcher.png > /dev/null 2>&1
  xcrun simctl terminate "$UDID" com.troydunn.clicker
  xcrun simctl launch "$UDID" com.troydunn.clicker -demo -picker > /dev/null; sleep 5
  xcrun simctl io "$UDID" screenshot shots/clicker-5-picker.png > /dev/null 2>&1
  xcrun simctl terminate "$UDID" com.troydunn.clicker
  xcrun simctl launch "$UDID" com.troydunn.clicker > /dev/null; sleep 4
  xcrun simctl io "$UDID" screenshot shots/clicker-0-setup.png > /dev/null 2>&1
  if xcrun simctl spawn "$UDID" launchctl list | grep -q com.troydunn.clicker; then echo "OK    clicker-setup"; else echo "CRASH clicker-setup"; FAIL=1; fi
fi

# Pulse Lab in demo mode (fake Apple Health + WHOOP data): Today, Sleep, Heart, Moves, VS.
APP=build/Build/Products/Debug-iphonesimulator/PulseLab.app
booted
if [ -d "$APP" ]; then
  xcrun simctl install "$UDID" "$APP"
  for T in today sleep heart moves vs; do
    xcrun simctl terminate "$UDID" com.troydunn.pulselab 2>/dev/null || true
    xcrun simctl launch "$UDID" com.troydunn.pulselab -demo -tab $T > /dev/null; sleep 5
    xcrun simctl io "$UDID" screenshot "shots/pulse-$T.png" > /dev/null 2>&1
  done
  if xcrun simctl spawn "$UDID" launchctl list | grep -q com.troydunn.pulselab; then echo "OK    pulselab"; else echo "CRASH pulselab"; FAIL=1; fi
  xcrun simctl terminate "$UDID" com.troydunn.pulselab 2>/dev/null || true
fi

# Still Point (meditation) in demo mode: Today, Traditions, Journey, and a breathing session.
APP=build/Build/Products/Debug-iphonesimulator/StillPoint.app
booted
if [ -d "$APP" ]; then
  xcrun simctl install "$UDID" "$APP"
  for T in today traditions journey; do
    xcrun simctl terminate "$UDID" com.troydunn.stillpoint 2>/dev/null || true
    xcrun simctl launch "$UDID" com.troydunn.stillpoint -demo -tab $T > /dev/null; sleep 5
    xcrun simctl io "$UDID" screenshot "shots/still-$T.png" > /dev/null 2>&1
  done
  xcrun simctl terminate "$UDID" com.troydunn.stillpoint 2>/dev/null || true
  xcrun simctl launch "$UDID" com.troydunn.stillpoint -demo -session resonance > /dev/null; sleep 7
  xcrun simctl io "$UDID" screenshot "shots/still-session.png" > /dev/null 2>&1
  if xcrun simctl spawn "$UDID" launchctl list | grep -q com.troydunn.stillpoint; then echo "OK    stillpoint"; else echo "CRASH stillpoint"; FAIL=1; fi
  xcrun simctl terminate "$UDID" com.troydunn.stillpoint 2>/dev/null || true
fi
exit $FAIL
