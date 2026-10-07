"""Prints where the App Store submission stands, from the App Store Connect API.

Run by .github/workflows/asc.yml with the key from repository secrets."""
import json, os, sys, time
import jwt, requests

BUNDLE = "com.rcabral.snaplist"
BASE = "https://api.appstoreconnect.apple.com"


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      os.environ["KEY_P8"], algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"})


H = {"Authorization": f"Bearer {token()}"}


def get(path, **params):
    r = requests.get(BASE + path, headers=H, params=params)
    if r.status_code >= 400:
        return {"error": r.status_code, "detail": r.text[:300]}
    return r.json()


def line(label, value):
    print(f"{label:28} {value}")


app = get("/v1/apps", **{"filter[bundleId]": BUNDLE})["data"][0]
app_id = app["id"]
line("App", f'{app["attributes"]["name"]} ({app_id})')

versions = get(f"/v1/apps/{app_id}/appStoreVersions", include="build")
if "error" in versions: print(versions)
for v in versions.get("data", []):
    a = v["attributes"]
    line("Version", f'{a["versionString"]} {a["platform"]} state={a.get("appStoreState") or a.get("appVersionState")} copyright={a.get("copyright")!r}')
    rel = v["relationships"]
    line("  build attached", (rel.get("build", {}).get("data") or {}).get("id"))
    rd = get(f'/v1/appStoreVersions/{v["id"]}/appStoreReviewDetail')
    d = (rd.get("data") or {}).get("attributes", {}) if isinstance(rd.get("data"), dict) else {}
    line("  review contact", f'{d.get("contactFirstName")} {d.get("contactLastName")} phone={"set" if d.get("contactPhone") else None} notes={"set" if d.get("notes") else None} signIn={d.get("demoAccountRequired")}')
    shots = get(f'/v1/appStoreVersions/{v["id"]}/appStoreVersionLocalizations')
    for loc in shots.get("data", []):
        sets = get(f'/v1/appStoreVersionLocalizations/{loc["id"]}/appScreenshotSets')
        for s in sets.get("data", []):
            n = len(get(f'/v1/appScreenshotSets/{s["id"]}/appScreenshots').get("data", []))
            line("  screenshots", f'{loc["attributes"]["locale"]} {s["attributes"]["screenshotDisplayType"]}: {n}')

builds = get("/v1/builds", **{"filter[app]": app_id, "sort": "-uploadedDate", "limit": 5, "include": "preReleaseVersion"})
pre = {i["id"]: i["attributes"]["version"] for i in builds.get("included", []) if i["type"] == "preReleaseVersions"}
for b in builds.get("data", []):
    a = b["attributes"]
    pv = pre.get((b["relationships"]["preReleaseVersion"]["data"] or {}).get("id"))
    line("Build", f'{pv} ({a["version"]}) {a["processingState"]} uploaded {a["uploadedDate"][:16]} id={b["id"]}')

infos = get(f"/v1/apps/{app_id}/appInfos", include="ageRatingDeclaration,primaryCategory")
for info in infos.get("data", []):
    line("App info", f'state={info["attributes"].get("state") or info["attributes"].get("appStoreState")} ageRating={info["attributes"].get("appStoreAgeRating")}')
    ar = get(f'/v1/appInfos/{info["id"]}/ageRatingDeclaration')
    attrs = (ar.get("data") or {}).get("attributes", {})
    unset = [k for k, v in attrs.items() if v is None]
    line("  age rating unanswered", len(unset))

price = get(f"/v1/apps/{app_id}/appPriceSchedule")
line("Price schedule", "set" if price.get("data") else f"not set {price.get('error', '')}")

groups = get(f"/v1/apps/{app_id}/subscriptionGroups", include="subscriptions")
for g in groups.get("data", []):
    line("Subscription group", g["attributes"]["referenceName"])
for s in [i for i in groups.get("included", []) if i["type"] == "subscriptions"]:
    a = s["attributes"]
    line("  subscription", f'{a["productId"]} {a.get("subscriptionPeriod")} state={a["state"]}')

subs = get("/v1/reviewSubmissions", **{"filter[app]": app_id, "include": "items"})
for r in subs.get("data", []):
    line("Review submission", f'{r["attributes"]["state"]} platform={r["attributes"]["platform"]} items={len(r["relationships"].get("items", {}).get("data") or [])}')
