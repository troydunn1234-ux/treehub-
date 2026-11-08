"""Set an app's one-time price (base territory USA; Apple auto-converts the rest).

usage: asc_price.py <bundle id> <price, e.g. 2.99>
Needs the Paid Apps agreement to be active in App Store Connect > Business.
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt

bundle, price = sys.argv[1], sys.argv[2]
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
API = "https://api.appstoreconnect.apple.com/v1"

def call(path, method="GET", body=None):
    url = path if path.startswith("http") else API + path
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return json.loads(raw) if raw else {}, None
    except urllib.error.HTTPError as e:
        return None, f"{e.code}: {e.read()[:600].decode(errors='replace')}"

res, err = call(f"/apps?filter[bundleId]={bundle}")
app_id = res["data"][0]["id"]

point, url = None, f"/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=200"
while url and not point:
    res, err = call(url)
    if err: sys.exit("Couldn't read price points " + err)
    point = next((p for p in res["data"] if p["attributes"]["customerPrice"] in (price, price + "0")), None)
    url = res.get("links", {}).get("next")
if not point: sys.exit(f"No USA price point for ${price}")

body = {"data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${p1}"}]}}},
        "included": [{"type": "appPrices", "id": "${p1}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": point["id"]}}}}]}
res, err = call("/appPriceSchedules", "POST", body)
if err:
    print(f"::warning::Price not set yet ({err}). Sign the Paid Apps agreement and add bank + tax info "
          "in App Store Connect > Business, then rerun.")
    sys.exit(0)
print(f"Price set to ${price} (USA base; other countries auto-matched)")
