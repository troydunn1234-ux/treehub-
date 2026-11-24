#!/bin/bash
# Runs each active bundled web app that was built this run in an iPhone simulator with demo data, screenshots it,
# and fails on a real crash: the app dying, the page's web process crashing, or an uncaught JavaScript error or
# unhandled promise rejection while the page loads (see webcheck.py). Only Ride Quest is checked: Food Book was
# dropped and Natal Orbit is paused, so neither is built. Apps not built this run are skipped, and the whole step
# is skipped with a warning when no simulator is usable. The native apps have their own steps (screenshots.sh,
# appshots.sh).
set -u
mkdir -p shots
WEB_APPS="RideQuest:com.troydunn.ridequest"
PRODUCTS=build/Build/Products/Debug-iphonesimulator

TODO=""
for pair in $WEB_APPS; do
  if [ -d "$PRODUCTS/${pair%%:*}.app" ]; then TODO="$TODO $pair"; else echo "SKIP  ${pair%%:*} (not built this run)"; fi
done
[ -n "$TODO" ] || { echo "No web app was built this run; nothing to check."; exit 0; }

UDID=$(python3 .github/scripts/sim_pick.py --boot)
if [ -z "$UDID" ]; then
  echo "::warning title=Web app check skipped::No usable iPhone simulator on this runner, so the web apps were not run."
  exit 0
fi

FAIL=0
for pair in $TODO; do
  python3 .github/scripts/webcheck.py "$UDID" "$PRODUCTS/${pair%%:*}.app" "${pair##*:}" shots || FAIL=1
done
exit $FAIL
