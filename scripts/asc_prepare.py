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
        raise RuntimeError(f"{method} {path}: {r.status_code} {r.text[:600]}")
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
skip = {"kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "developerAgeRatingInfoUrl"}
answered, failed = 0, []
for key, value in ar["attributes"].items():
    if key in skip or value is not None:
        continue
    for answer in ("NONE", False):
        try:
            call("PATCH", f"/v1/ageRatingDeclarations/{ar['id']}",
                 {"data": {"type": "ageRatingDeclarations", "id": ar["id"], "attributes": {key: answer}}})
            answered += 1
            break
        except RuntimeError as error:
            last = str(error)
    else:
        failed.append(f"{key}: {last[:200]}")
print(f"Age rating: {answered} answered")
for f in failed:
    print("  not answered:", f)

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
        print("Version not added (may already be in it):", str(error)[:300])
    call("PATCH", f"/v1/reviewSubmissions/{sid}",
         {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
    print("Submitted for review")
