#!/bin/bash
# Records a video of the UI tour test on an iPhone simulator.
set -u
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
        if best is None or score>best[0]: best=(score,dv["udid"])
print(best[1])')
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl location "$UDID" set 37.2872,-121.9500 || true

# Build first so the recording starts close to the app launching
xcodebuild build-for-testing -project TreeHub.xcodeproj -scheme TreeHub \
  -destination "id=$UDID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet || exit 1
xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/TreeHub.app
for svc in location location-always motion photos; do xcrun simctl privacy "$UDID" grant $svc com.troydunn.treehub || true; done

xcrun simctl io "$UDID" recordVideo --codec=h264 --force shots/tour-raw.mov &
REC=$!
sleep 2
# A looping jog around downtown Campbell for the tracking part
( sleep 75; xcrun simctl location "$UDID" start --speed=4 --interval=1 \
  37.2872,-121.9500 37.2880,-121.9478 37.2895,-121.9465 37.2910,-121.9470 37.2918,-121.9490 37.2905,-121.9512 37.2888,-121.9520 37.2872,-121.9500 ) &

xcodebuild test-without-building -project TreeHub.xcodeproj -scheme TreeHub \
  -destination "id=$UDID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -25
RESULT=${PIPESTATUS[0]}
sleep 1
kill -INT $REC; wait $REC 2>/dev/null
ls -la shots
brew install ffmpeg >/dev/null 2>&1 || true
if command -v ffmpeg >/dev/null; then
  ffmpeg -y -loglevel error -i shots/tour-raw.mov -vf "scale=590:-2,fps=30" -c:v libx264 -crf 26 -preset veryfast -movflags +faststart -an shots/tour.mp4 && rm shots/tour-raw.mov
fi
ls -la shots
exit 0
