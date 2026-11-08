"""Register the app's bundle ID with Apple if it isn't there yet (apps without
capabilities otherwise only get the wildcard ID, which App Store Connect can't use)."""
import json, os, sys, time, urllib.request, urllib.error
import jwt

bundle, name = sys.argv[1], sys.argv[2]
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
def call(path, method="GET", body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com/v1" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        print(f"{method} {path} -> {e.code}: {e.read()[:300]}"); return None
found = call(f"/bundleIds?filter[identifier]={bundle}")
if found and any(b["attributes"]["identifier"] == bundle for b in found["data"]):
    print("Bundle ID already registered")
else:
    r = call("/bundleIds", "POST", {"data": {"type": "bundleIds", "attributes": {"identifier": bundle, "name": name, "platform": "IOS"}}})
    print("Registered bundle ID" if r else "Could not register bundle ID")
