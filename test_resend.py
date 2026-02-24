#!/usr/bin/env python3
"""Quick Resend email test via REST API (no extra library needed)."""

import urllib.request
import urllib.error
import json

# ── Config ────────────────────────────────────────────────────────────────────
API_KEY    = "_"
FROM_EMAIL = "noreply@m.auspexmedix.com"
TO_EMAIL   = "longh1686@gmail.com"
# ─────────────────────────────────────────────────────────────────────────────

payload = {
    "from":    FROM_EMAIL,
    "to":      [TO_EMAIL],
    "subject": "✅ Resend Test from HotCRP",
    "text":    "If you see this, Resend is working correctly!",
    "html":    "<h3>✅ Resend is working!</h3><p>Email sent from HotCRP Docker setup.</p>",
}

req = urllib.request.Request(
    "https://api.resend.com/emails",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Content-Type":  "application/json",
        "Authorization": f"Bearer {API_KEY}",
        # Cloudflare blocks Python's default UA — use a browser-like one
        "User-Agent": "Mozilla/5.0 (compatible; resend-python-test/1.0)",
    },
    method="POST",
)

print(f"Sending test email from {FROM_EMAIL} to {TO_EMAIL} ...")
try:
    with urllib.request.urlopen(req) as resp:
        body = json.loads(resp.read())
        print(f"✅ Success! ID: {body.get('id')}")
        print("   → Check your inbox at", TO_EMAIL)
except urllib.error.HTTPError as e:
    raw = e.read()
    print(f"❌ HTTP {e.code}: {e.reason}")
    try:
        err = json.loads(raw)
        print(json.dumps(err, indent=2))
    except Exception:
        print("Raw response:", raw.decode(errors="replace") or "(empty body)")
except Exception as e:
    print(f"❌ Error: {e}")
