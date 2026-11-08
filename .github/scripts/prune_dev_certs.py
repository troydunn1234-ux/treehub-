"""Revoke old iOS development certificates on the Apple account.

Each fresh CI runner makes a new development certificate when it signs an
archive, and Apple allows only a few. They're useless once the runner is gone,
so clear them out before archiving. Distribution certificates are left alone.
"""
import json, os, time, urllib.request
import jwt  # PyJWT

kid, iss = os.environ["KID"], os.environ["ISS"]
key = open(os.environ["KEY_PATH"]).read()
token = jwt.encode({"iss": iss, "iat": int(time.time()), "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
                   key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})
base = "https://api.appstoreconnect.apple.com/v1/certificates"

def call(url, method="GET"):
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as r:
        body = r.read()
        return json.loads(body) if body else {}

certs = call(base + "?limit=200&fields[certificates]=certificateType,name,expirationDate")["data"]
dev = [c for c in certs if c["attributes"]["certificateType"] in ("DEVELOPMENT", "IOS_DEVELOPMENT")]
print(f"{len(certs)} certificates, {len(dev)} development")
for c in dev:
    call(f"{base}/{c['id']}", "DELETE")
    print("revoked", c["attributes"].get("name"), c["id"])
