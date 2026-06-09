"""
Shared APNs push. Gated on config — no-ops cleanly (logs the intended message)
until an APNs key is set, so feature code can call it freely before enrollment.
"""

import os
import time
from typing import List


def apns_send(tokens: List[str], title: str, body: str) -> None:
    tokens = [t for t in tokens if t]
    if not tokens:
        return
    key = os.getenv("APNS_KEY_P8"); key_id = os.getenv("APNS_KEY_ID")
    team = os.getenv("APNS_TEAM_ID"); topic = os.getenv("APNS_TOPIC")
    if not (key and key_id and team and topic):
        print(f"[push] skipped (APNs not configured) → {len(tokens)} device(s): {title} — {body}")
        return
    try:
        import jwt as pyjwt
        import httpx
        provider = pyjwt.encode({"iss": team, "iat": int(time.time())}, key, algorithm="ES256", headers={"kid": key_id})
        host = "https://api.sandbox.push.apple.com" if os.getenv("APNS_SANDBOX") else "https://api.push.apple.com"
        with httpx.Client(http2=True, timeout=10) as c:
            for t in tokens:
                c.post(f"{host}/3/device/{t}",
                       headers={"authorization": f"bearer {provider}", "apns-topic": topic, "apns-push-type": "alert"},
                       json={"aps": {"alert": {"title": title, "body": body}, "sound": "default"}})
    except Exception as e:
        print(f"[push] send failed: {e}")


def push_users(sb, user_ids: List[str], title: str, body: str) -> None:
    """Send to every device registered to any of the given users."""
    uids = [u for u in user_ids if u]
    if not uids:
        return
    rows = sb.table("device_tokens").select("token").in_("user_id", uids).execute().data
    apns_send([r["token"] for r in rows], title, body)
