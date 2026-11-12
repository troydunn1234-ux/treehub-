"""Create (or update) an app's one-time "Pro" in-app purchase in App Store Connect.

usage: asc_iap.py <bundle id> <product id> <price e.g. 2.99, or 0.0 for a free trial> <name> <description> [review screenshot .png]

Idempotent: re-running finds the existing product by product id and only fills in what's missing.
Needs the Paid Apps agreement active (App Store Connect > Business).
"""
import json, os, sys, time, urllib.request, urllib.error, hashlib
import jwt

bundle, product_id, price, name, desc = sys.argv[1:6]
shot = sys.argv[6] if len(sys.argv) > 6 else None
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
API = "https://api.appstoreconnect.apple.com"

def call(path, method="GET", body=None, raw=None, ctype="application/json"):
    url = path if path.startswith("http") else API + path
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, method=method, data=data,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req) as r:
            out = r.read(); return (json.loads(out) if out else {}), None
    except urllib.error.HTTPError as e:
        return None, f"{e.code}: {e.read()[:700].decode(errors='replace')}"

res, err = call(f"/v1/apps?filter[bundleId]={bundle}")
if err or not res["data"]: sys.exit(f"App {bundle} not found {err or ''}")
app_id = res["data"][0]["id"]

# 1. The product
res, err = call(f"/v1/apps/{app_id}/inAppPurchasesV2?filter[productId]={product_id}")
if err: sys.exit("Couldn't list IAPs " + err)
iap = res["data"][0] if res["data"] else None
if not iap:
    body = {"data": {"type": "inAppPurchases", "attributes": {
                "name": name, "productId": product_id, "inAppPurchaseType": "NON_CONSUMABLE",
                "reviewNote": os.environ.get("REVIEW_NOTE") or (
                              "One-time unlock of all features. Tap the lock on any Pro feature, or the Unlock button, to see the paywall. "
                              "Restore purchase is on the same screen.")},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}
    res, err = call("/v2/inAppPurchases", "POST", body)
    if err: sys.exit("Couldn't create IAP " + err)
    iap = res["data"]
    print("Created", product_id)
else:
    print("Found", product_id, iap["attributes"].get("state"))
iap_id = iap["id"]

# 2. English localization
res, err = call(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")
if not err and not any(l["attributes"]["locale"] == "en-US" for l in res["data"]):
    body = {"data": {"type": "inAppPurchaseLocalizations",
                     "attributes": {"locale": "en-US", "name": name, "description": desc},
                     "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}
    _, err = call("/v1/inAppPurchaseLocalizations", "POST", body)
    print("Localization:", err or "ok")

# 3. Price (USA base; Apple matches the rest)
res, err = call(f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule")
if err or not res.get("data"):
    point, url = None, f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=USA&limit=200"
    while url and not point:
        res, err = call(url)
        if err: sys.exit("Couldn't read price points " + err)
        point = next((p for p in res["data"] if p["attributes"]["customerPrice"] in (price, price + "0")), None)
        url = res.get("links", {}).get("next")
    if not point: sys.exit(f"No USA price point for ${price}")
    body = {"data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p1}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${p1}", "attributes": {"startDate": None},
                          "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point["id"]}}}}]}
    _, err = call("/v1/inAppPurchasePriceSchedules", "POST", body)
    print(f"Price ${price}:", err or "ok")
else:
    print("Price already scheduled")

# 4. Availability: everywhere the app is
res, err = call(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
if err or not res.get("data"):
    terr, url = [], "/v1/territories?limit=200"
    while url:
        res, err = call(url)
        if err: break
        terr += [t["id"] for t in res["data"]]
        url = res.get("links", {}).get("next")
    body = {"data": {"type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
                     "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                                       "availableTerritories": {"data": [{"type": "territories", "id": t} for t in terr]}}}}
    _, err = call("/v1/inAppPurchaseAvailabilities", "POST", body)
    print("Availability:", err or f"ok ({len(terr)} territories)")

# 5. Review screenshot (required before the IAP can be submitted the first time)
if shot and os.path.exists(shot):
    res, err = call(f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
    if err or not res.get("data"):
        data = open(shot, "rb").read()
        body = {"data": {"type": "inAppPurchaseAppStoreReviewScreenshots",
                         "attributes": {"fileName": os.path.basename(shot), "fileSize": len(data)},
                         "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}
        res, err = call("/v1/inAppPurchaseAppStoreReviewScreenshots", "POST", body)
        if err: print("Screenshot reserve:", err)
        else:
            sid = res["data"]["id"]
            for op in res["data"]["attributes"]["uploadOperations"]:
                chunk = data[op["offset"]:op["offset"] + op["length"]]
                req = urllib.request.Request(op["url"], method=op["method"], data=chunk,
                                             headers={h["name"]: h["value"] for h in op["requestHeaders"]})
                urllib.request.urlopen(req).read()
            _, err = call(f"/v1/inAppPurchaseAppStoreReviewScreenshots/{sid}", "PATCH",
                          {"data": {"type": "inAppPurchaseAppStoreReviewScreenshots", "id": sid,
                                    "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
            print("Screenshot:", err or "uploaded")
    else:
        print("Screenshot already attached")
print("IAP ready:", iap_id)
