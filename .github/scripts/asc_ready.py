"""Get an app's App Store version ready to submit (never submits it).

usage: asc_ready.py <bundle id> <metadata.json>

From metadata.json: "ageRating" (overrides; every other question is answered none/no), "copyright",
"reviewNotes", "contentRights" (default DOES_NOT_USE_THIRD_PARTY_CONTENT).
Also: availability everywhere except the EU (no EU trader declaration needed), the newest processed build
attached, export compliance on that build, and App Review contact details copied from another of your apps
when this one has none (read and written straight through the API, never printed or stored).
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt
import socket
socket.setdefaulttimeout(120)  # never hang the job on one stuck request

bundle, meta_path = sys.argv[1], sys.argv[2]
meta = json.load(open(meta_path))
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
ROOT = "https://api.appstoreconnect.apple.com"
DONORS = ["com.troydunn.clicker", "com.troydunn.natalorbit", "com.troydunn.stillpoint", "com.troydunn.pulselab",
          "com.troydunn.rootbound", "com.troydunn.roamr", "com.troydunn.ridequest"]
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")


def call(path, method="GET", body=None):
    req = urllib.request.Request(path if path.startswith("http") else ROOT + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return (json.loads(raw) if raw else {}), None
    except urllib.error.HTTPError as e:
        return None, f"{e.code}: {e.read()[:400].decode(errors='replace')}"


app_id = call(f"/v1/apps?filter[bundleId]={bundle}")[0]["data"][0]["id"]

# ---- Content rights
_, err = call(f"/v1/apps/{app_id}", "PATCH", {"data": {"type": "apps", "id": app_id, "attributes": {
    "contentRightsDeclaration": meta.get("contentRights", "DOES_NOT_USE_THIRD_PARTY_CONTENT")}}})
print("Content rights:", err or "set")

# ---- Age rating (only on an editable appInfo)
answers = {k: "NONE" for k in ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
           "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
           "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic",
           "gunsOrOtherWeapons"]}
answers.update({k: False for k in ["gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "parentalControls",
                "ageAssurance", "socialMedia", "userGeneratedContent", "advertising", "healthOrWellnessTopics"]})
answers.update(meta.get("ageRating", {}))
infos = call(f"/v1/apps/{app_id}/appInfos")[0]["data"]
for info in infos:
    state = info["attributes"].get("appStoreState") or info["attributes"].get("state")
    if state not in EDITABLE:
        print(f"Age rating: appInfo is {state}, left as is"); continue
    decl, err = call(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
    if err: print("Age rating read failed", err); continue
    did = decl["data"]["id"]
    _, err = call(f"/v1/ageRatingDeclarations/{did}", "PATCH", {"data": {"type": "ageRatingDeclarations", "id": did, "attributes": answers}})
    if not err:
        print("Age rating: all questions answered", {k: v for k, v in meta.get("ageRating", {}).items()})
    else:
        ok, skipped = 0, []
        for k, v in answers.items():
            _, e2 = call(f"/v1/ageRatingDeclarations/{did}", "PATCH", {"data": {"type": "ageRatingDeclarations", "id": did, "attributes": {k: v}}})
            if e2: skipped.append(k)
            else: ok += 1
        print(f"Age rating: answered {ok} one by one; not accepted by the API: {skipped}")
    info2, _ = call(f"/v1/appInfos/{info['id']}")
    if info2: print("  rating now:", info2["data"]["attributes"].get("appStoreAgeRating"))

# ---- Availability: every country except the EU
EU = set("AUT BEL BGR HRV CYP CZE DNK EST FIN FRA DEU GRC HUN IRL ITA LVA LTU LUX MLT NLD POL PRT ROU SVK SVN ESP SWE".split())
avail, err = call(f"/v1/apps/{app_id}/appAvailabilityV2")
if avail and avail.get("data"):
    aid = avail["data"]["id"]; url = f"/v2/appAvailabilities/{aid}/territoryAvailabilities?include=territory&limit=200"
    changed = 0
    while url:
        res, err = call(url)
        if err: print("territories read failed", err); break
        for t in res["data"]:
            terr = t["relationships"]["territory"]["data"]["id"]
            want = terr not in EU
            if t["attributes"].get("available") != want:
                _, e2 = call(f"/v1/territoryAvailabilities/{t['id']}", "PATCH",
                             {"data": {"type": "territoryAvailabilities", "id": t["id"], "attributes": {"available": want}}})
                if not e2: changed += 1
        url = res.get("links", {}).get("next")
    print(f"Availability: all countries except the EU ({changed} changed)")
else:
    terrs, url = [], "/v1/territories?limit=200"
    while url:
        res, _ = call(url); terrs += [t["id"] for t in res["data"]]; url = res.get("links", {}).get("next")
    inc = [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": t not in EU},
            "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for t in terrs]
    body = {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": False},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                       "territoryAvailabilities": {"data": [{"type": i["type"], "id": i["id"]} for i in inc]}}},
            "included": inc}
    _, err = call("/v2/appAvailabilities", "POST", body)
    print("Availability: created, all countries except the EU" if not err else f"Availability failed: {err}")

# ---- The version being prepared
vers = call(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS")[0]["data"]
ver = next((v for v in vers if v["attributes"]["appStoreState"] in EDITABLE), None)
if not ver:
    print("No editable version (", [v["attributes"]["appStoreState"] for v in vers], "); version details left as they are")
    sys.exit(0)
vid = ver["id"]
_, err = call(f"/v1/appStoreVersions/{vid}", "PATCH", {"data": {"type": "appStoreVersions", "id": vid,
              "attributes": {"copyright": meta.get("copyright", "2026 Troy Dunn")}}})
print("Copyright:", err or "set")

# Review details: notes + no sign-in; contact copied from another app if missing.
rd, _ = call(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
cur = (rd or {}).get("data") or None
attrs = {"demoAccountRequired": False, "notes": meta.get("reviewNotes", "")[:3999]}
CONTACT = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")
if not cur or not all(cur["attributes"].get(k) for k in CONTACT):
    for donor in DONORS:
        if donor == bundle: continue
        d = (call(f"/v1/apps?filter[bundleId]={donor}")[0] or {}).get("data") or []
        if not d: continue
        for v in (call(f"/v1/apps/{d[0]['id']}/appStoreVersions?limit=5")[0] or {}).get("data", []):
            dd = (call(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail")[0] or {}).get("data")
            if dd and all(dd["attributes"].get(k) for k in CONTACT):
                attrs.update({k: dd["attributes"][k] for k in CONTACT}); break
        if "contactEmail" in attrs: break
    print("Review contact:", "copied from another of your apps" if "contactEmail" in attrs else "NOT FOUND (add it in App Store Connect)")
if cur:
    _, err = call(f"/v1/appStoreReviewDetails/{cur['id']}", "PATCH", {"data": {"type": "appStoreReviewDetails", "id": cur["id"], "attributes": attrs}})
else:
    _, err = call("/v1/appStoreReviewDetails", "POST", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
                  "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
print("Review details (notes, no sign-in):", "set" if not err else err[:200])

# Newest processed build, attached (if it's newer than what's attached) + export compliance.
builds = (call(f"/v1/builds?filter[app]={app_id}&filter[processingState]=VALID&sort=-uploadedDate&limit=5")[0] or {}).get("data", [])
builds = [b for b in builds if not b["attributes"].get("expired")]
if not builds:
    print("Build: none processed yet (ship one with the TestFlight workflow, then rerun)")
else:
    b = builds[0]
    have = (call(f"/v1/appStoreVersions/{vid}/build")[0] or {}).get("data")
    if have and have["id"] == b["id"]:
        print("Build", b["attributes"]["version"], "already attached")
    else:
        if b["attributes"].get("usesNonExemptEncryption") is None:
            call(f"/v1/builds/{b['id']}", "PATCH", {"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})
        _, err = call(f"/v1/appStoreVersions/{vid}/relationships/build", "PATCH", {"data": {"type": "builds", "id": b["id"]}})
        print(f"Build {b['attributes']['version']} attached" if not err else "Build attach failed " + err[:300])
print("Ready step done. Nothing was submitted for review.")
