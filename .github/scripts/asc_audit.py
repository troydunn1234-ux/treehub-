"""Read-only audit of every app's App Store page: what's filled in and what's still missing.

usage: asc_audit.py [bundle ...]   (default: all seven apps)
Prints only lengths / states / yes-no flags (workflow logs on a public repo are public: no contact details).
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt

APPS = ["com.troydunn.clicker", "com.troydunn.natalorbit", "com.troydunn.stillpoint", "com.troydunn.pulselab",
        "com.troydunn.rootbound", "com.troydunn.roamr", "com.troydunn.ridequest"]
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})


def g(path):
    url = path if path.startswith("http") else "https://api.appstoreconnect.apple.com" + path
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"Authorization": "Bearer " + token})) as r:
            raw = r.read(); return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"error": f"{e.code} {e.read()[:200].decode(errors='replace')}"}


def data(path):
    res = g(path)
    return res.get("data") if "error" not in res else None


def L(s): return len(s or "")


for bundle in (sys.argv[1:] or APPS):
    apps = data(f"/v1/apps?filter[bundleId]={bundle}") or []
    if not apps:
        print(f"\n### {bundle}: not found"); continue
    app = apps[0]; aid = app["id"]; a = app["attributes"]
    print(f"\n### {bundle}  id={aid}  name='{a.get('name')}'  contentRights={a.get('contentRightsDeclaration')}")

    for info in data(f"/v1/apps/{aid}/appInfos?include=primaryCategory,secondaryCategory") or []:
        ia = info["attributes"]; rel = info.get("relationships", {})
        cat = lambda k: ((rel.get(k) or {}).get("data") or {}).get("id")
        print(f"  appInfo {ia.get('appStoreState')} state={ia.get('state')} age={ia.get('appStoreAgeRating')} "
              f"cat={cat('primaryCategory')}/{cat('secondaryCategory')}")
        for l in data(f"/v1/appInfos/{info['id']}/appInfoLocalizations") or []:
            la = l["attributes"]
            print(f"    loc {la['locale']}: name='{la.get('name')}' subtitle='{la.get('subtitle')}' privacyUrl={'yes' if la.get('privacyPolicyUrl') else 'NO'}")
        decl = data(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
        if decl:
            unanswered = [k for k, v in decl["attributes"].items() if v is None]
            print(f"    ageRating: {len(decl['attributes']) - len(unanswered)} answered, unanswered={unanswered}")

    # price + availability
    mp = g(f"/v1/appPriceSchedules/{aid}/manualPrices?include=appPricePoint&limit=5")
    pts = [i["attributes"].get("customerPrice") for i in mp.get("included", []) if i["type"] == "appPricePoints"] if "error" not in mp else mp["error"][:60]
    print(f"  price points: {pts}")
    av = data(f"/v1/apps/{aid}/appAvailabilityV2")
    if av:
        n, url = 0, f"/v2/appAvailabilities/{av['id']}/territoryAvailabilities?limit=200"
        while url:
            res = g(url)
            if "error" in res: break
            n += sum(1 for t in res["data"] if t["attributes"].get("available"))
            url = res.get("links", {}).get("next")
        print(f"  available in {n} territories")
    else:
        print("  availability: NOT SET")

    for v in data(f"/v1/apps/{aid}/appStoreVersions?limit=5") or []:
        va = v["attributes"]
        b = data(f"/v1/appStoreVersions/{v['id']}/build")
        print(f"  version {va.get('platform')} {va['versionString']} {va['appStoreState']} copyright={'yes' if va.get('copyright') else 'NO'} "
              f"build={(b or {}).get('attributes', {}).get('version') if b else 'NONE'} release={va.get('releaseType')}")
        rd = data(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail")
        if rd:
            ra = rd["attributes"]
            print(f"    review: contactFirst={'yes' if ra.get('contactFirstName') else 'NO'} contactLast={'yes' if ra.get('contactLastName') else 'NO'} "
                  f"phone={'yes' if ra.get('contactPhone') else 'NO'} email={'yes' if ra.get('contactEmail') else 'NO'} "
                  f"demoRequired={ra.get('demoAccountRequired')} notes={L(ra.get('notes'))}ch")
        else:
            print("    review details: NONE")
        for l in data(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations") or []:
            la = l["attributes"]
            print(f"    loc {la['locale']}: desc={L(la.get('description'))} kw={L(la.get('keywords'))} promo={L(la.get('promotionalText'))} "
                  f"support={'yes' if la.get('supportUrl') else 'NO'} marketing={'yes' if la.get('marketingUrl') else 'no'} whatsNew={L(la.get('whatsNew'))}")
            for s in data(f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets") or []:
                shots = data(f"/v1/appScreenshotSets/{s['id']}/appScreenshots") or []
                states = sorted({x["attributes"]["assetDeliveryState"]["state"] for x in shots})
                print(f"      shots {s['attributes']['screenshotDisplayType']}: {len(shots)} {states}")

    for p in data(f"/v1/apps/{aid}/inAppPurchasesV2?limit=50") or []:
        pa = p["attributes"]
        locs = [l["attributes"]["locale"] for l in (data(f"/v2/inAppPurchases/{p['id']}/inAppPurchaseLocalizations") or [])]
        shot = data(f"/v2/inAppPurchases/{p['id']}/appStoreReviewScreenshot")
        sched = data(f"/v2/inAppPurchases/{p['id']}/iapPriceSchedule")
        avail = data(f"/v2/inAppPurchases/{p['id']}/inAppPurchaseAvailability")
        print(f"  IAP {pa.get('productId')} {pa.get('state')} type={pa.get('inAppPurchaseType')} locs={locs} "
              f"reviewShot={'yes' if shot else 'NO'} price={'yes' if sched else 'NO'} avail={'yes' if avail else 'NO'} note={L(pa.get('reviewNote'))}ch")
    for grp in data(f"/v1/apps/{aid}/subscriptionGroups?limit=20") or []:
        glocs = [l["attributes"]["locale"] for l in (data(f"/v1/subscriptionGroups/{grp['id']}/subscriptionGroupLocalizations") or [])]
        print(f"  SUBGROUP {grp['attributes'].get('referenceName')} locs={glocs}")
        for s in data(f"/v1/subscriptionGroups/{grp['id']}/subscriptions?limit=20") or []:
            sa = s["attributes"]
            locs = [l["attributes"]["locale"] for l in (data(f"/v1/subscriptions/{s['id']}/subscriptionLocalizations") or [])]
            shot = data(f"/v1/subscriptions/{s['id']}/appStoreReviewScreenshot")
            prices = data(f"/v1/subscriptions/{s['id']}/prices?limit=1")
            avail = data(f"/v1/subscriptions/{s['id']}/subscriptionAvailability")
            print(f"    SUB {sa.get('productId')} {sa.get('state')} locs={locs} reviewShot={'yes' if shot else 'NO'} "
                  f"prices={'yes' if prices else 'NO'} avail={'yes' if avail else 'NO'} note={L(sa.get('reviewNote'))}ch")
print("\nAudit done (read-only).")
