#!/usr/bin/env -S uv run --quiet --script
# /// script
# dependencies = ["pyjwt[crypto]", "requests"]
# ///
"""Tiny App Store Connect API helper: asc.py GET /v1/apps?filter[bundleId]=... | asc.py POST /v1/x '{json}'"""
import json, os, sys, time, jwt, requests

KEY_ID = os.environ.get("ASC_KEY_ID", "4VK7XSDKY9")
ISSUER = os.environ.get("ASC_ISSUER_ID", "d4f4d460-5a2d-4cfc-9bdc-14ba239ad277")
key = open(os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")).read()
token = jwt.encode({"iss": ISSUER, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
                   key, algorithm="ES256", headers={"kid": KEY_ID})
method, path = sys.argv[1], sys.argv[2]
body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
r = requests.request(method, "https://api.appstoreconnect.apple.com" + path,
                     headers={"Authorization": f"Bearer {token}"}, json=body)
print(r.status_code)
print(json.dumps(r.json(), indent=1) if r.text else "")
