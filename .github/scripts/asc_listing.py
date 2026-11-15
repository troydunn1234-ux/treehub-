"""Fill in an app's App Store listing from store/<app>/metadata.json and upload
marketing screenshots. Never submits anything for review.

usage: asc_listing.py <bundle id> <metadata.json> <screenshots dir> [apple watch screenshots dir] [13-inch iPad screenshots dir]
"""
import hashlib, json, os, sys, time, urllib.request, urllib.error
import jwt
import socket
socket.setdefaulttimeout(120)  # never hang the job on one stuck request

bundle, meta_path, shots_dir = sys.argv[1], sys.argv[2], sys.argv[3]
watch_dir = sys.argv[4] if len(sys.argv) > 4 else None
ipad_dir = sys.argv[5] if len(sys.argv) > 5 else None
meta = json.load(open(meta_path))
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
API = "https://api.appstoreconnect.apple.com/v1"

def call(path, method="GET", body=None, quiet=False):
    url = path if path.startswith("http") else API + path
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    tries = 1 if method == "POST" else 4  # a dropped connection is retried (not a POST, which could make a duplicate)
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(req) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            if not quiet: print(f"  ! {method} {path.split('?')[0]} -> {e.code}: {e.read()[:400].decode(errors='replace')}")
            return None
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            print(f"  ! {method} {path.split('?')[0]} -> {e!r}; " + ("retrying" if attempt < tries - 1 else "giving up"))
            time.sleep(10 * (attempt + 1))
    return None

app = call(f"/apps?filter[bundleId]={bundle}")["data"][0]
app_id = app["id"]
print("App:", app["attributes"]["name"])

# --- App-level info: subtitle, privacy policy URL, categories (on the editable appInfo)
infos = call(f"/apps/{app_id}/appInfos")["data"]
info = next((i for i in infos if i["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW", None)), infos[0])
rel = {}
if meta.get("primaryCategory"): rel["primaryCategory"] = {"data": {"type": "appCategories", "id": meta["primaryCategory"]}}
if meta.get("secondaryCategory"): rel["secondaryCategory"] = {"data": {"type": "appCategories", "id": meta["secondaryCategory"]}}
if rel and call(f"/appInfos/{info['id']}", "PATCH", {"data": {"type": "appInfos", "id": info["id"], "relationships": rel}}) is not None:
    print("Categories set")
locs = call(f"/appInfos/{info['id']}/appInfoLocalizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), locs[0])
attrs = {k: meta[k] for k in ("subtitle", "privacyPolicyUrl") if meta.get(k)}
if call(f"/appInfoLocalizations/{loc['id']}", "PATCH", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}}) is not None:
    print("Subtitle and privacy policy set")
# App name: only while that appInfo is editable (a new version is being prepared), and in its own
# request so a taken name doesn't block the subtitle.
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")
if meta.get("name") and loc["attributes"].get("name") != meta["name"]:
    if info["attributes"].get("appStoreState") in EDITABLE:
        if call(f"/appInfoLocalizations/{loc['id']}", "PATCH", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": {"name": meta["name"]}}}) is not None:
            print("App name set to", meta["name"])
        else:
            print("App name not changed (the name may be taken)")
    else:
        print("App name change waits for the next editable version")

# --- Version-level: description, keywords, promo text, support URL
versions = call(f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=5")["data"]
ver = next((v for v in versions if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), None)
if not ver:
    print("No editable App Store version; skipping description and screenshots"); sys.exit(0)
vlocs = call(f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]
vloc = next((l for l in vlocs if l["attributes"]["locale"] == "en-US"), vlocs[0])
vattrs = {k: meta[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl") if meta.get(k)}
if call(f"/appStoreVersionLocalizations/{vloc['id']}", "PATCH", {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"], "attributes": vattrs}}) is not None:
    print("Description, keywords, promo text and support URL set")

# --- Screenshots, replacing what's there: the 6.9" iPhone set, plus the Apple Watch set when there is one
import time as _t

# Apple Watch display type by pixel size (simulator screenshots).
WATCH_TYPES = {(410, 502): "APP_WATCH_ULTRA", (422, 514): "APP_WATCH_ULTRA", (416, 496): "APP_WATCH_SERIES_10",
               (374, 446): "APP_WATCH_SERIES_10", (396, 484): "APP_WATCH_SERIES_7", (352, 430): "APP_WATCH_SERIES_7",
               (368, 448): "APP_WATCH_SERIES_4", (324, 394): "APP_WATCH_SERIES_4", (312, 390): "APP_WATCH_SERIES_3",
               (272, 340): "APP_WATCH_SERIES_3"}


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def upload_set(display, folder, files):
    sets = call(f"/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")["data"]
    sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display), None)
    if not sset:
        res = call("/appScreenshotSets", "POST", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                   "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"]}}}}})
        if not res: print("Couldn't make the", display, "set"); return
        sset = res["data"]
    for old in call(f"/appScreenshotSets/{sset['id']}/appScreenshots")["data"]:
        call(f"/appScreenshots/{old['id']}", "DELETE")
    for f in files[:10]:
        data = open(os.path.join(folder, f), "rb").read()
        shot = call("/appScreenshots", "POST", {"data": {"type": "appScreenshots", "attributes": {"fileName": f, "fileSize": len(data)},
                    "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})
        if not shot: continue
        sid = shot["data"]["id"]
        for op in shot["data"]["attributes"]["uploadOperations"]:
            part = data[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], method=op["method"], data=part,
                                         headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
            for attempt in range(4):
                try:
                    urllib.request.urlopen(req).read(); break
                except urllib.error.HTTPError:
                    raise
                except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
                    print("  ! upload part:", repr(e), "retrying" if attempt < 3 else "giving up")
                    _t.sleep(10 * (attempt + 1))
        done = call(f"/appScreenshots/{sid}", "PATCH", {"data": {"type": "appScreenshots", "id": sid,
                    "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(display, "uploaded", f if done else f + " (commit failed)")
    # Wait until Apple has processed every screenshot; one stuck in UPLOAD_COMPLETE/FAILED blocks "Add for Review".
    for attempt in range(12):
        items = call(f"/appScreenshotSets/{sset['id']}/appScreenshots")["data"]
        states = [(x["attributes"]["fileName"], x["attributes"]["assetDeliveryState"]["state"]) for x in items]
        print(display, "states:", states)
        if all(st == "COMPLETE" for _, st in states): break
        if any(st == "FAILED" for _, st in states):
            for x in items:
                if x["attributes"]["assetDeliveryState"]["state"] == "FAILED":
                    print("  FAILED:", x["attributes"]["fileName"], x["attributes"]["assetDeliveryState"].get("errors"))
                    call(f"/appScreenshots/{x['id']}", "DELETE")
            break
        _t.sleep(20)


files = sorted(f for f in os.listdir(shots_dir) if f.endswith(".png")) if os.path.isdir(shots_dir) else []
if files:
    upload_set("APP_IPHONE_67", shots_dir, files)
else:
    print("No iPhone screenshots to upload")
# 13-inch iPad (2064x2752 or 2048x2732): App Store Connect requires this set for apps that run on iPad.
ipad = sorted(f for f in os.listdir(ipad_dir) if f.endswith(".png")) if ipad_dir and os.path.isdir(ipad_dir) else []
ipad = [f for f in ipad if png_size(os.path.join(ipad_dir, f)) in ((2064, 2752), (2048, 2732))]
if ipad:
    upload_set("APP_IPAD_PRO_3GEN_129", ipad_dir, ipad)
if watch_dir and os.path.isdir(watch_dir):
    by_type = {}
    for f in sorted(x for x in os.listdir(watch_dir) if x.endswith(".png")):
        t = WATCH_TYPES.get(png_size(os.path.join(watch_dir, f)))
        if t: by_type.setdefault(t, []).append(f)
        else: print("Watch screenshot", f, png_size(os.path.join(watch_dir, f)), "is not an App Store size; skipped")
    for t, fs in by_type.items():
        upload_set(t, watch_dir, fs)
print("Listing updated. Nothing was submitted for review.")
