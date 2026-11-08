"""Fill in an app's App Store listing from store/<app>/metadata.json and upload
marketing screenshots. Never submits anything for review.

usage: asc_listing.py <bundle id> <metadata.json> <screenshots dir>
"""
import hashlib, json, os, sys, time, urllib.request, urllib.error
import jwt

bundle, meta_path, shots_dir = sys.argv[1], sys.argv[2], sys.argv[3]
meta = json.load(open(meta_path))
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
API = "https://api.appstoreconnect.apple.com/v1"

def call(path, method="GET", body=None, quiet=False):
    url = path if path.startswith("http") else API + path
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        if not quiet: print(f"  ! {method} {path.split('?')[0]} -> {e.code}: {e.read()[:400].decode(errors='replace')}")
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

# --- Screenshots (6.9" iPhone set), replacing what's there
files = sorted(f for f in os.listdir(shots_dir) if f.endswith(".png"))
if not files:
    print("No screenshots to upload"); sys.exit(0)
sets = call(f"/appStoreVersionLocalizations/{vloc['id']}/appScreenshotSets")["data"]
display = "APP_IPHONE_67"
sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display), None)
if not sset:
    sset = call("/appScreenshotSets", "POST", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": vloc["id"]}}}}})["data"]
for old in call(f"/appScreenshotSets/{sset['id']}/appScreenshots")["data"]:
    call(f"/appScreenshots/{old['id']}", "DELETE")

for f in files:
    data = open(os.path.join(shots_dir, f), "rb").read()
    shot = call("/appScreenshots", "POST", {"data": {"type": "appScreenshots", "attributes": {"fileName": f, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})
    if not shot: continue
    sid = shot["data"]["id"]
    for op in shot["data"]["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"], data=part,
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req).read()
    done = call(f"/appScreenshots/{sid}", "PATCH", {"data": {"type": "appScreenshots", "id": sid,
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print("Uploaded screenshot", f if done else f + " (commit failed)")
print("Listing updated. Nothing was submitted for review.")
