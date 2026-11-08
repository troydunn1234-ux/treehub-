"""Answer the age-rating questionnaire (all 'none' -> 4+) and stop selling in EU
countries (avoids the EU trader address requirement). usage: asc_setup.py <bundle id>"""
import json, os, sys, time, urllib.request, urllib.error
import jwt

bundle = sys.argv[1]
token = jwt.encode({"iss": os.environ["ISS"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   open(os.environ["KEY_PATH"]).read(), algorithm="ES256", headers={"kid": os.environ["KID"], "typ": "JWT"})
ROOT = "https://api.appstoreconnect.apple.com"

def call(path, method="GET", body=None):
    req = urllib.request.Request(path if path.startswith("http") else ROOT + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return (json.loads(raw) if raw else {}), None
    except urllib.error.HTTPError as e:
        return None, f"{e.code}: {e.read()[:300].decode(errors='replace')}"

app_id = call(f"/v1/apps?filter[bundleId]={bundle}")[0]["data"][0]["id"]

# ---- Age rating
infos = call(f"/v1/apps/{app_id}/appInfos")[0]["data"]
answers = {k: "NONE" for k in ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
           "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
           "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic",
           "gunsOrOtherWeapons"]}
answers.update({k: False for k in ["gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "parentalControls",
                "ageAssurance", "userGeneratedContent", "advertising", "healthOrWellnessTopics"]})
for info in infos:
    decl, err = call(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
    if err: print("age rating read failed", err); continue
    did = decl["data"]["id"]; ok = 0
    print("current:", json.dumps(decl["data"]["attributes"]))
    _, err = call(f"/v1/ageRatingDeclarations/{did}", "PATCH", {"data": {"type": "ageRatingDeclarations", "id": did, "attributes": answers}})
    print("all-at-once:", err or "OK")
    if not err: continue
    for k, v in answers.items():
        _, err = call(f"/v1/ageRatingDeclarations/{did}", "PATCH",
                      {"data": {"type": "ageRatingDeclarations", "id": did, "attributes": {k: v}}})
        if err: print(f"  skip {k}: {err[:300]}")
        else: ok += 1
    print(f"Age rating: answered {ok} questions (all none/no) on appInfo {info['id']}")

# ---- Territories: everywhere except the EU
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
                if e2: print(f"  {terr}: {e2[:120]}")
                else: changed += 1
        url = res.get("links", {}).get("next")
    print(f"Availability updated ({changed} changes): all countries except the EU")
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
    print("Availability created: all countries except the EU" if not err else f"Availability failed: {err}")
