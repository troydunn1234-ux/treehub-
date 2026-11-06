#!/bin/bash
# Boots an iPhone simulator, runs TreeHub with demo data and captures each screen.
set -u
APP=build/Build/Products/Debug-iphonesimulator/TreeHub.app
BUNDLE=com.troydunn.treehub
mkdir -p shots

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys,re
d=json.load(sys.stdin)["devices"]
best=None
for rt,devs in d.items():
    if "iOS" not in rt: continue
    ver=tuple(int(x) for x in re.findall(r"\d+",rt.split("iOS")[-1]))
    for dv in devs:
        n=dv["name"]
        if not n.startswith("iPhone"): continue
        score=(ver, "Pro Max" in n, "Pro" in n)
        if best is None or score>best[0]: best=(score,dv["udid"],n,rt)
print(best[1]); sys.stderr.write("Simulator: %s %s\n"%(best[2],best[3]))
')
echo "UDID=$UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
for svc in location location-always motion photos; do xcrun simctl privacy "$UDID" grant $svc $BUNDLE || true; done
xcrun simctl location "$UDID" set 37.2872,-121.9500 || true

FAIL=0
shot () {
  local name=$1; shift
  local wait=$1; shift
  xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
  xcrun simctl launch "$UDID" $BUNDLE -demo "$@" > /dev/null
  sleep "$wait"
  if xcrun simctl spawn "$UDID" launchctl list | grep -q "$BUNDLE"; then
    echo "OK    $name"
  else
    echo "CRASH $name"; FAIL=1
  fi
  xcrun simctl io "$UDID" screenshot "shots/$name.png" > /dev/null 2>&1
}

shot 1-home 8
shot 2-hug-log 8 -hugLog
shot 3-celebration 9 -celebrate
shot 4-grove 8 -tab trees
shot 5-collection 8 -tab collection
shot 6-track 8 -tab track

# Live tracking: drive a fake run through Campbell while recording
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
xcrun simctl launch "$UDID" $BUNDLE -demo -autostart > /dev/null
sleep 3
xcrun simctl location "$UDID" start --speed=4 --interval=1 \
  37.2872,-121.9500 37.2880,-121.9478 37.2895,-121.9465 37.2910,-121.9470 37.2918,-121.9490 37.2905,-121.9512 37.2888,-121.9520 37.2872,-121.9500 || true
sleep 40
if xcrun simctl spawn "$UDID" launchctl list | grep -q "$BUNDLE"; then echo "OK    7-live-run"; else echo "CRASH 7-live-run"; FAIL=1; fi
xcrun simctl io "$UDID" screenshot "shots/7-live-run.png" > /dev/null 2>&1
xcrun simctl location "$UDID" clear || true

# Crash reports, if any
find ~/Library/Logs/DiagnosticReports -name "TreeHub*" -mmin -30 -exec cp {} shots/ \; 2>/dev/null || true
ls shots
exit $FAIL
