"""Set up an app's auto-renewable subscriptions in App Store Connect.

usage: asc_subs.py <bundle id> <config.json>

config.json:
  {"group": "<reference name>", "groupDisplay": "<shown to users>", "customAppName": "<optional>",
   "subs": [{"productId", "name", "period" (ONE_WEEK|ONE_MONTH|TWO_MONTHS|THREE_MONTHS|SIX_MONTHS|ONE_YEAR),
             "level" (1 = highest), "price" (USD, e.g. "2.99"), "displayName", "description", "trial" (optional, e.g. ONE_WEEK)}],
   "reviewNote": "...", "reviewScreenshot": "path/to.png (optional)"}

Idempotent: finds the group, subscriptions, localizations, availability, prices and intro offers that already
exist and only creates what's missing. One step failing doesn't stop the rest; exits non-zero at the end if
anything essential failed. Needs the Paid Apps agreement active (App Store Connect > Business).
"""
import json, os, sys, time, urllib.request, urllib.error, urllib.parse, hashlib
import jwt

bundle, cfg_path = sys.argv[1:3]
cfg = json.load(open(cfg_path))
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
API = "https://api.appstoreconnect.apple.com"
failed = []  # essential failures


def call(path, method="GET", body=None, raw=None, ctype="application/json"):
    url = path if path.startswith("http") else API + path
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    for attempt in range(4):
        req = urllib.request.Request(url, method=method, data=data,
                                     headers={"Authorization": f"Bearer {token}", "Content-Type": ctype})
        try:
            with urllib.request.urlopen(req) as r:
                out = r.read(); return (json.loads(out) if out else {}), None
        except urllib.error.HTTPError as e:
            msg = e.read()[:700].decode(errors="replace")
            if e.code == 429 and attempt < 3:
                time.sleep(5); continue
            if e.code == 409 and method == "POST" and "exist" in msg.lower():
                return {"data": None, "alreadyExists": True}, None
            return None, f"{e.code}: {msg}"
        except Exception as e:  # network hiccup
            if attempt < 3:
                time.sleep(5); continue
            return None, str(e)


def get_all(path):
    """GET every page (follows links.next). Returns (data, included, err)."""
    data, inc, url = [], [], path
    while url:
        res, err = call(url)
        if err: return data, inc, err
        data += res.get("data") or []
        inc += res.get("included") or []
        url = res.get("links", {}).get("next")
    return data, inc, None


def rel(type_, id_):
    return {"data": {"type": type_, "id": id_}}


def short(text, n=55):
    text = (text or "").strip()
    if len(text) <= n: return text
    cut = text[:n - 1].rsplit(" ", 1)[0].rstrip(" ,;:-–")
    return (cut or text[:n - 1]) + "…"


def price_eq(a, b):
    try: return abs(float(a) - float(b)) < 0.001
    except (TypeError, ValueError): return False


# 1. App
res, err = call(f"/v1/apps?filter[bundleId]={urllib.parse.quote(bundle)}")
if err or not res.get("data"): sys.exit(f"App {bundle} not found {err or ''}")
app_id = res["data"][0]["id"]
print("App:", bundle, app_id)

# 2. Subscription group + en-US localization
groups, _, err = get_all(f"/v1/apps/{app_id}/subscriptionGroups?limit=200")
if err: sys.exit("Couldn't list subscription groups " + err)
group = next((g for g in groups if g["attributes"].get("referenceName") == cfg["group"]), None)
if group:
    print("Group: found", cfg["group"])
else:
    res, err = call("/v1/subscriptionGroups", "POST", {"data": {"type": "subscriptionGroups",
                    "attributes": {"referenceName": cfg["group"]}, "relationships": {"app": rel("apps", app_id)}}})
    if err or not res.get("data"): sys.exit("Couldn't create group " + (err or "(exists but not listed)"))
    group = res["data"]; print("Group: created", cfg["group"])
gid = group["id"]

locs, _, err = get_all(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations?limit=200")
if err: print("Group localization: couldn't list", err)
elif any(l["attributes"].get("locale") == "en-US" for l in locs): print("Group localization: exists")
else:
    attrs = {"locale": "en-US", "name": cfg.get("groupDisplay") or cfg["group"]}
    if cfg.get("customAppName"): attrs["customAppName"] = cfg["customAppName"]
    _, err = call("/v1/subscriptionGroupLocalizations", "POST", {"data": {"type": "subscriptionGroupLocalizations",
                  "attributes": attrs, "relationships": {"subscriptionGroup": rel("subscriptionGroups", gid)}}})
    print("Group localization:", err or "created")
    if err: failed.append("group localization")

# All territories (for availability + intro offers)
territories, _, err = get_all("/v1/territories?limit=200")
territories = [t["id"] for t in territories]
print("Territories:", len(territories), err or "")
if err or not territories: failed.append("territories")

existing_subs, _, err = get_all(f"/v1/subscriptionGroups/{gid}/subscriptions?limit=200")
if err: print("Couldn't list subscriptions", err); failed.append("list subscriptions")
sub_ids = {}

for s in cfg["subs"]:
    pid = s["productId"]
    tag = s.get("name", pid)
    # 3. Subscription
    sub = next((x for x in existing_subs if x["attributes"].get("productId") == pid), None)
    if sub:
        print(f"[{tag}] found ({sub['attributes'].get('state')})")
    else:
        attrs = {"name": s["name"], "productId": pid, "subscriptionPeriod": s["period"],
                 "groupLevel": int(s.get("level", 1)), "familySharable": False}
        if cfg.get("reviewNote"): attrs["reviewNote"] = cfg["reviewNote"]
        res, err = call("/v1/subscriptions", "POST", {"data": {"type": "subscriptions", "attributes": attrs,
                        "relationships": {"group": rel("subscriptionGroups", gid)}}})
        if err or not res.get("data"):
            print(f"[{tag}] create failed:", err or "(exists but not listed in this group)")
            failed.append(f"{pid} create"); continue
        sub = res["data"]; print(f"[{tag}] created")
    sid = sub["id"]; sub_ids[pid] = sid

    # 3b. en-US localization
    locs, _, err = get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations?limit=200")
    if err: print(f"[{tag}] localization: couldn't list", err)
    elif any(l["attributes"].get("locale") == "en-US" for l in locs): print(f"[{tag}] localization: exists")
    else:
        _, err = call("/v1/subscriptionLocalizations", "POST", {"data": {"type": "subscriptionLocalizations",
                      "attributes": {"locale": "en-US", "name": short(s.get("displayName") or s["name"], 30),
                                     "description": short(s.get("description", ""), 55)},
                      "relationships": {"subscription": rel("subscriptions", sid)}}})
        print(f"[{tag}] localization:", err or "created")
        if err: failed.append(f"{pid} localization")

    # 4. Availability
    res, err = call(f"/v1/subscriptions/{sid}/subscriptionAvailability")
    if not err and res.get("data"):
        print(f"[{tag}] availability: exists")
    elif territories:
        _, err = call("/v1/subscriptionAvailabilities", "POST", {"data": {"type": "subscriptionAvailabilities",
                      "attributes": {"availableInNewTerritories": True},
                      "relationships": {"subscription": rel("subscriptions", sid),
                                        "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}})
        print(f"[{tag}] availability:", err or f"set ({len(territories)} territories)")
        if err: failed.append(f"{pid} availability")

    # 5. Prices (USA point + Apple's equalized points everywhere else)
    prices, inc, err = get_all(f"/v1/subscriptions/{sid}/prices?include=territory&limit=200")
    priced = {(p.get("relationships", {}).get("territory", {}).get("data") or {}).get("id") for p in prices} - {None}
    if err: print(f"[{tag}] prices: couldn't list", err)
    if not err and len(prices) >= 100:
        print(f"[{tag}] prices: {len(prices)} already set")
    else:
        point, url = None, f"/v1/subscriptions/{sid}/pricePoints?filter[territory]=USA&limit=200"
        while url and not point:
            res, err = call(url)
            if err: break
            point = next((p for p in res["data"] if price_eq(p["attributes"].get("customerPrice"), s["price"])), None)
            url = res.get("links", {}).get("next")
        if not point:
            print(f"[{tag}] prices: no USA price point for ${s['price']}", err or "")
            failed.append(f"{pid} price"); point = None
        else:
            eq, _, err = get_all(f"/v1/subscriptionPricePoints/{point['id']}/equalizations?include=territory&limit=200")
            if err: print(f"[{tag}] prices: couldn't read equalizations", err)
            todo = [(point["id"], "USA")] + [(e["id"], (e.get("relationships", {}).get("territory", {}).get("data") or {}).get("id")) for e in eq]
            ok = skip = bad = 0
            for ppid, terr in todo:
                if terr and terr in priced: skip += 1; continue
                _, e2 = call("/v1/subscriptionPrices", "POST", {"data": {"type": "subscriptionPrices",
                             "attributes": {"startDate": None, "preserveCurrentPrice": False},
                             "relationships": {"subscription": rel("subscriptions", sid),
                                               "subscriptionPricePoint": rel("subscriptionPricePoints", ppid)}}})
                if e2:
                    bad += 1
                    if terr == "USA" or bad <= 3: print(f"[{tag}] price {terr}:", e2[:300])
                    if terr == "USA": failed.append(f"{pid} USA price")
                else: ok += 1
            print(f"[{tag}] prices ${s['price']}: {ok} set, {skip} already there, {bad} failed")

    # 6. Free-trial introductory offer, one per territory
    if s.get("trial"):
        offers, _, err = get_all(f"/v1/subscriptions/{sid}/introductoryOffers?include=territory&limit=200")
        if err: print(f"[{tag}] trial: couldn't list", err)
        else:
            have = {(o.get("relationships", {}).get("territory", {}).get("data") or {}).get("id") for o in offers} - {None}
            if offers and not have: have = set(territories)  # can't tell which; assume done
            ok = bad = 0
            for t in territories:
                if t in have: continue
                _, e2 = call("/v1/subscriptionIntroductoryOffers", "POST", {"data": {"type": "subscriptionIntroductoryOffers",
                             "attributes": {"duration": s["trial"], "offerMode": "FREE_TRIAL", "numberOfPeriods": 1,
                                            "startDate": None, "endDate": None},
                             "relationships": {"subscription": rel("subscriptions", sid), "territory": rel("territories", t)}}})
                if e2:
                    bad += 1
                    if bad <= 3: print(f"[{tag}] trial {t}:", e2[:300])
                else: ok += 1
            print(f"[{tag}] trial {s['trial']}: {ok} created, {len(have)} already there, {bad} failed")

    # 7. Review screenshot
    shot = cfg.get("reviewScreenshot")
    if shot and os.path.exists(shot):
        res, err = call(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
        if not err and res.get("data"):
            print(f"[{tag}] screenshot: exists")
        else:
            try:
                data = open(shot, "rb").read()
                res, err = call("/v1/subscriptionAppStoreReviewScreenshots", "POST", {"data": {
                                "type": "subscriptionAppStoreReviewScreenshots",
                                "attributes": {"fileName": os.path.basename(shot), "fileSize": len(data)},
                                "relationships": {"subscription": rel("subscriptions", sid)}}})
                if err or not res.get("data"): print(f"[{tag}] screenshot reserve:", err)
                else:
                    shot_id = res["data"]["id"]
                    for op in res["data"]["attributes"]["uploadOperations"]:
                        chunk = data[op["offset"]:op["offset"] + op["length"]]
                        req = urllib.request.Request(op["url"], method=op["method"], data=chunk,
                                                     headers={h["name"]: h["value"] for h in op["requestHeaders"]})
                        urllib.request.urlopen(req).read()
                    _, err = call(f"/v1/subscriptionAppStoreReviewScreenshots/{shot_id}", "PATCH",
                                  {"data": {"type": "subscriptionAppStoreReviewScreenshots", "id": shot_id,
                                            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
                    print(f"[{tag}] screenshot:", err or "uploaded")
            except Exception as e:
                print(f"[{tag}] screenshot failed:", e)
    elif shot:
        print(f"[{tag}] screenshot: {shot} not found, skipped")

# 8. Final state
for pid, sid in sub_ids.items():
    res, err = call(f"/v1/subscriptions/{sid}")
    print("State:", pid, err or res["data"]["attributes"].get("state"))

if failed:
    print("FAILED:", ", ".join(failed)); sys.exit(1)
print("Subscriptions ready")
