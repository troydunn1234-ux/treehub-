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
  xcrun simctl launch "$UDID" "$B" > /dev/null
  sleep 0.6; xcrun simctl io "$UDID" screenshot "shots/web-$T-0-splash.png" > /dev/null 2>&1
  sleep 9;   xcrun simctl io "$UDID" screenshot "shots/web-$T-1-loaded.png" > /dev/null 2>&1
  if xcrun simctl spawn "$UDID" launchctl list | grep -q "$B"; then echo "OK    $T"; else echo "CRASH $T"; FAIL=1; fi
  xcrun simctl terminate "$UDID" "$B" 2>/dev/null || true
done
exit $FAIL
