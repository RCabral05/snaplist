"""Fills in what App Store Connect needs before review: attaches the build,
sets the copyright, answers the age rating (nothing in Snaplist applies), and
with --submit adds the version to the draft review submission and submits it.

Run by .github/workflows/asc.yml with the key from repository secrets."""
import os, sys, time
import jwt, requests

BUNDLE = "com.rcabral.snaplist"
BASE = "https://api.appstoreconnect.apple.com"
VERSION, BUILD, COPYRIGHT = os.environ["VERSION"], os.environ["BUILD"], os.environ["COPYRIGHT"]
SUBMIT = os.environ.get("SUBMIT") == "true"


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      os.environ["KEY_P8"], algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"})


H = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}


def call(method, path, body=None, **params):
    r = requests.request(method, BASE + path, headers=H, json=body, params=params)
    if r.status_code >= 400:
        raise RuntimeError(f"{method} {path}: {r.status_code} {r.text[:1500]}")
    return r.json() if r.text else {}


app_id = call("GET", "/v1/apps", **{"filter[bundleId]": BUNDLE})["data"][0]["id"]
version = next(v for v in call("GET", f"/v1/apps/{app_id}/appStoreVersions")["data"]
               if v["attributes"]["versionString"] == VERSION)
vid = version["id"]

# The build: the one with this build number under this version.
builds = call("GET", "/v1/builds", **{"filter[app]": app_id, "filter[version]": BUILD,
                                      "filter[preReleaseVersion.version]": VERSION})["data"]
if not builds:
    sys.exit(f"No build {BUILD} for {VERSION}")
call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": builds[0]["id"]}})
print(f"Build {VERSION} ({BUILD}) attached")

call("PATCH", f"/v1/appStoreVersions/{vid}",
     {"data": {"type": "appStoreVersions", "id": vid, "attributes": {"copyright": COPYRIGHT}}})
print(f"Copyright: {COPYRIGHT}")

# Age rating: no violence, no mature themes, no gambling, no web browser, no
# chat, no user content, no ads. Each question takes NONE or false.
info = next(i for i in call("GET", f"/v1/apps/{app_id}/appInfos")["data"]
            if i["attributes"].get("state") != "READY_FOR_DISTRIBUTION")
ar = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
# Yes/no questions take false; how-often questions take NONE. Sent together,
# since Apple checks the answers as a set.
yes_no = {"advertising", "ageAssurance", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
          "parentalControls", "socialMedia", "socialMediaAgeRestricted", "unrestrictedWebAccess", "userGeneratedContent"}
how_often = {"alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
             "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
             "sexualContentOrNudity", "horrorOrFearThemes", "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
             "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"}
answers = {k: (False if k in yes_no else "NONE") for k in ar["attributes"] if k in yes_no | how_often}
try:
    call("PATCH", f"/v1/ageRatingDeclarations/{ar['id']}",
         {"data": {"type": "ageRatingDeclarations", "id": ar["id"], "attributes": answers}})
    print(f"Age rating: {len(answers)} answered")
except RuntimeError as error:
    print("Age rating not saved:", str(error)[:1500])
unknown = [k for k, v in ar["attributes"].items() if v is None and k not in answers]
if unknown:
    print("Age rating questions left as they are:", ", ".join(unknown))

# Content rights: Snaplist shows only what the person adds themselves.
call("PATCH", f"/v1/apps/{app_id}", {"data": {"type": "apps", "id": app_id,
     "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
print("Content rights: no third-party content")

# The app itself is free; Pro is the subscriptions.
points = call("GET", f"/v1/apps/{app_id}/appPricePoints", **{"filter[territory]": "USA", "limit": 200})["data"]
free = next((p for p in points if float(p["attributes"]["customerPrice"]) == 0), None)
if free is None:
    print("No free price point found")
else:
    try:
        call("POST", "/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
        print("Price: Free")
    except RuntimeError as error:
        print("Price not set:", str(error)[:1500])

if SUBMIT:
    drafts = [s for s in call("GET", "/v1/reviewSubmissions", **{"filter[app]": app_id, "filter[platform]": "IOS"})["data"]
              if s["attributes"]["state"] == "READY_FOR_REVIEW"]
    if drafts:
        sid = drafts[0]["id"]
    else:
        sid = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                   "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]["id"]
    try:
        call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        print("Version added to the review submission")
    except RuntimeError as error:
        print("Version not added:", str(error)[:3000])
    call("PATCH", f"/v1/reviewSubmissions/{sid}",
         {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
    print("Submitted for review")
