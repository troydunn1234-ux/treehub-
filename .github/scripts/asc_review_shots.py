"""Attach the paywall screenshot as the App Review screenshot of every in-app purchase and subscription of an app
that doesn't have a good one yet (a missing review screenshot is what keeps them in MISSING_METADATA).

usage: asc_review_shots.py <bundle id> <paywall .png>      FORCE=1 replaces existing screenshots too.
"""
import hashlib, json, os, sys, time, urllib.request, urllib.error
import jwt
import socket
socket.setdefaulttimeout(120)  # never hang the job on one stuck request

bundle, shot = sys.argv[1], sys.argv[2]
data = open(shot, "rb").read()
checksum = hashlib.md5(data).hexdigest()
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
API = "https://api.appstoreconnect.apple.com"
force = os.environ.get("FORCE") == "1"


def call(path, method="GET", body=None):
    req = urllib.request.Request(path if path.startswith("http") else API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return (json.loads(raw) if raw else {}), None
    except urllib.error.HTTPError as e:
        return None, f"{e.code}: {e.read()[:400].decode(errors='replace')}"


def attach(label, get_path, kind, rel_name, rel_type, owner_id):
    """kind: inAppPurchaseAppStoreReviewScreenshots | subscriptionAppStoreReviewScreenshots"""
    res, err = call(get_path)
    cur = (res or {}).get("data")
    if cur:
        state = ((cur["attributes"].get("assetDeliveryState") or {}).get("state"))
        if state == "COMPLETE" and not force:
            print(f"{label}: review screenshot already there"); return
        call(f"/v1/{kind}/{cur['id']}", "DELETE")
    res, err = call(f"/v1/{kind}", "POST", {"data": {"type": kind, "attributes": {"fileName": os.path.basename(shot), "fileSize": len(data)},
                    "relationships": {rel_name: {"data": {"type": rel_type, "id": owner_id}}}}})
    if err:
        print(f"{label}: reserve failed {err}"); return
    sid = res["data"]["id"]
    for op in res["data"]["attributes"]["uploadOperations"]:
        req = urllib.request.Request(op["url"], method=op["method"], data=data[op["offset"]:op["offset"] + op["length"]],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req).read()
    _, err = call(f"/v1/{kind}/{sid}", "PATCH", {"data": {"type": kind, "id": sid, "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}})
    print(f"{label}: review screenshot", err or "uploaded")


app_id = call(f"/v1/apps?filter[bundleId]={bundle}")[0]["data"][0]["id"]
iaps = (call(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50")[0] or {}).get("data", [])
for p in iaps:
    attach(p["attributes"]["productId"], f"/v2/inAppPurchases/{p['id']}/appStoreReviewScreenshot",
           "inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseV2", "inAppPurchases", p["id"])
subs = []
for g in (call(f"/v1/apps/{app_id}/subscriptionGroups?limit=20")[0] or {}).get("data", []):
    for s in (call(f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50")[0] or {}).get("data", []):
        subs.append(s)
        attach(s["attributes"]["productId"], f"/v1/subscriptions/{s['id']}/appStoreReviewScreenshot",
               "subscriptionAppStoreReviewScreenshots", "subscription", "subscriptions", s["id"])

# Apple processes the image, then the product moves from MISSING_METADATA to READY_TO_SUBMIT.
time.sleep(30)
for p in iaps:
    r = (call(f"/v2/inAppPurchases/{p['id']}")[0] or {}).get("data", {})
    print("State:", p["attributes"]["productId"], r.get("attributes", {}).get("state"))
for s in subs:
    r = (call(f"/v1/subscriptions/{s['id']}")[0] or {}).get("data", {})
    print("State:", s["attributes"]["productId"], r.get("attributes", {}).get("state"))
print("Nothing was submitted for review.")
