"""Puts fastlane/review_notes.txt into the App Review notes of a version.
Run by .github/workflows/asc.yml (notes input) with the key from repository secrets."""
import os, time
import jwt, requests

BASE = "https://api.appstoreconnect.apple.com"
now = int(time.time())
token = jwt.encode({"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                   os.environ["KEY_P8"], algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"})
H = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def call(method, path, body=None, **params):
    r = requests.request(method, BASE + path, headers=H, json=body, params=params)
    if r.status_code >= 400:
        raise RuntimeError(f"{method} {path}: {r.status_code} {r.text[:1500]}")
    return r.json() if r.text else {}


app_id = call("GET", "/v1/apps", **{"filter[bundleId]": "com.rcabral.snaplist"})["data"][0]["id"]
version = next(v for v in call("GET", f"/v1/apps/{app_id}/appStoreVersions")["data"]
               if v["attributes"]["versionString"] == os.environ["VERSION"])
detail = call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")["data"]
notes = open("fastlane/review_notes.txt").read().strip()
call("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}",
     {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": {"notes": notes}}})
print(f"Review notes updated ({len(notes)} characters)")
