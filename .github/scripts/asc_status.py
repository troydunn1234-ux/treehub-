import json, os, time, urllib.request, jwt
t = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time())+600, "aud": "appstoreconnect-v1"}, open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
def g(p): return json.load(urllib.request.urlopen(urllib.request.Request("https://api.appstoreconnect.apple.com"+p, headers={"Authorization":"Bearer "+t})))
for b in ["com.troydunn.clicker","com.troydunn.natalorbit"]:
    a = g(f"/v1/apps?filter[bundleId]={b}")["data"][0]
    for v in g(f"/v1/apps/{a['id']}/appStoreVersions?filter[platform]=IOS")["data"]:
        print(a["attributes"]["name"], v["attributes"]["versionString"], v["attributes"]["appStoreState"])
