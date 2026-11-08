#!/bin/bash
# Launches each bundled web app in the booted simulator and screenshots it.
set -u
mkdir -p shots
UDID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next(dv["udid"] for rt in d for dv in d[rt]))')
FAIL=0
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

# Roamr test drive on I-280 at ~80 mph: truck avatar, chase cam, speed limit HUD, colored route.
APP=build/Build/Products/Debug-iphonesimulator/Roamr.app
if [ -d "$APP" ]; then
  xcrun simctl install "$UDID" "$APP"
  for svc in location location-always motion; do xcrun simctl privacy "$UDID" grant $svc com.troydunn.roamr || true; done
  xcrun simctl location "$UDID" set 37.3229,-122.0322 || true
  xcrun simctl launch "$UDID" com.troydunn.roamr -demo -autodrive > /dev/null
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
  if xcrun simctl spawn "$UDID" launchctl list | grep -q com.troydunn.roamr; then echo "OK    roamr-drive"; else echo "CRASH roamr-drive"; FAIL=1; fi
  xcrun simctl location "$UDID" clear || true
fi

# Clicker in demo mode (pretend-paired TV): apps grid and remote.
APP=build/Build/Products/Debug-iphonesimulator/Clicker.app
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
  xcrun simctl launch "$UDID" com.troydunn.clicker > /dev/null; sleep 4
  xcrun simctl io "$UDID" screenshot shots/clicker-0-setup.png > /dev/null 2>&1
fi
exit $FAIL
