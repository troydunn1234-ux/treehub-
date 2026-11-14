import json, os, time, urllib.request, jwt
t = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time())+600, "aud": "appstoreconnect-v1"}, open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
def g(p): return json.load(urllib.request.urlopen(urllib.request.Request("https://api.appstoreconnect.apple.com"+p, headers={"Authorization":"Bearer "+t})))
for b in ["com.troydunn.clicker","com.troydunn.natalorbit","com.troydunn.stillpoint","com.troydunn.pulselab","com.troydunn.rootbound","com.troydunn.roamr","com.troydunn.ridequest"]:
    a = g(f"/v1/apps?filter[bundleId]={b}")["data"][0]
    for v in g(f"/v1/apps/{a['id']}/appStoreVersions?filter[platform]=IOS")["data"]:
        print(a["attributes"]["name"], v["attributes"]["versionString"], v["attributes"]["appStoreState"])
# Latest TestFlight builds and whether Apple finished processing them.
for b in ["com.troydunn.stillpoint", "com.troydunn.pulselab"]:
    try:
        a = g(f"/v1/apps?filter[bundleId]={b}")["data"][0]
        for x in g(f"/v1/builds?filter[app]={a['id']}&sort=-uploadedDate&limit=2")["data"]:
            at = x["attributes"]
            print(a["attributes"]["name"], "build", at["version"], at["processingState"], "expired" if at.get("expired") else "", at.get("uploadedDate", "")[:16])
    except Exception as e:
        print(b, "lookup failed:", e)
# App Store IDs (the number in apps.apple.com/app/id<N>), in-app purchases and subscriptions per app.
for b in ["com.troydunn.clicker","com.troydunn.natalorbit","com.troydunn.stillpoint","com.troydunn.pulselab","com.troydunn.rootbound","com.troydunn.roamr","com.troydunn.ridequest"]:
    try:
        a = g(f"/v1/apps?filter[bundleId]={b}")["data"][0]
        print("APPID", b, a["id"], a["attributes"]["name"])
        for p in g(f"/v1/apps/{a['id']}/inAppPurchasesV2?limit=50")["data"]:
            print("  IAP", p["attributes"].get("productId"), p["attributes"].get("state"))
        for grp in g(f"/v1/apps/{a['id']}/subscriptionGroups?limit=20")["data"]:
            for s in g(f"/v1/subscriptionGroups/{grp['id']}/subscriptions?limit=20")["data"]:
                print("  SUB", grp["attributes"].get("referenceName"), s["attributes"].get("productId"), s["attributes"].get("state"))
    except Exception as e:
        print(b, "lookup failed:", e)
