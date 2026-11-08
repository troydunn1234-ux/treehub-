"""Make sure an app has an internal TestFlight group with every team member in it.

Run after an upload. Uses the App Store Connect API key from the workflow's secrets.
Emails are read from the account at run time; none are stored in this repo.
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt  # PyJWT

bundle = sys.argv[1]
kid, iss = os.environ["KID"], os.environ["ISS"]
key = open(os.environ["KEY_PATH"]).read()
token = jwt.encode({"iss": iss, "iat": int(time.time()), "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
                   key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})
API = "https://api.appstoreconnect.apple.com/v1"

def call(path, method="GET", body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"{method} {path} -> {e.code}: {e.read()[:300]}")
        return None

apps = call(f"/apps?filter[bundleId]={bundle}")
if not apps or not apps["data"]:
    print(f"No App Store Connect app for {bundle} yet; create it at appstoreconnect.apple.com."); sys.exit(0)
app_id = apps["data"][0]["id"]

groups = call(f"/apps/{app_id}/betaGroups") or {"data": []}
internal = [g for g in groups["data"] if g["attributes"].get("isInternalGroup")]
if internal:
    group_id = internal[0]["id"]
    print("Internal group exists:", internal[0]["attributes"]["name"])
else:
    g = call("/betaGroups", "POST", {"data": {"type": "betaGroups",
            "attributes": {"name": "Me", "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    if not g: sys.exit(0)
    group_id = g["data"]["id"]
    print("Created internal group")

# Add every account user (you) as a tester of this group.
users = call("/users?limit=50") or {"data": []}
existing = call(f"/betaGroups/{group_id}/betaTesters?limit=200") or {"data": []}
have = {t["attributes"].get("email", "").lower() for t in existing["data"]}
for u in users["data"]:
    a = u["attributes"]
    email = (a.get("username") or "").lower()
    if not email or email in have: continue
    r = call("/betaTesters", "POST", {"data": {"type": "betaTesters",
            "attributes": {"email": email, "firstName": a.get("firstName", ""), "lastName": a.get("lastName", "")},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group_id}]}}}})
    print("Added a tester" if r else "Could not add a tester")
