"""Attach the newest processed build to the editable App Store version (no submit)."""
import json, os, sys, time, urllib.request, urllib.error
import jwt
bundle = sys.argv[1]
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
def call(path, method="GET", body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return (json.loads(raw) if raw else {}), None
    except urllib.error.HTTPError as e:
        return None, f"{e.code}: {e.read()[:500].decode(errors='replace')}"
app_id = call(f"/v1/apps?filter[bundleId]={bundle}")[0]["data"][0]["id"]
vers = call(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS")[0]["data"]
for v in vers: print("version", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
ver = next((v for v in vers if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), None)
if not ver: sys.exit("No editable version")
for attempt in range(40):
    builds = call(f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5")[0]["data"]
    for b in builds: print(" build", b["attributes"]["version"], b["attributes"]["processingState"])
    ok = next((b for b in builds if b["attributes"]["processingState"] == "VALID"), None)
    if ok and ok == builds[0]: break
    print("waiting for newest build to finish processing..."); time.sleep(30)
_, err = call(f"/v1/appStoreVersions/{ver['id']}/relationships/build", "PATCH", {"data": {"type": "builds", "id": ok["id"]}})
print(f"Attached build {ok['attributes']['version']} to {ver['attributes']['versionString']}" if not err else "attach failed " + err)
# export compliance: app only uses standard HTTPS/TLS
call(f"/v1/builds/{ok['id']}", "PATCH", {"data": {"type": "builds", "id": ok["id"], "attributes": {"usesNonExemptEncryption": False}}})
