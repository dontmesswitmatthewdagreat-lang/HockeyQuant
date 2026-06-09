"""
HockeyQuant News Router — AI-compiled daily NHL news digest.

Generated 3x/day (cron): a morning league-wide digest, plus per-team pre-game
and post-game digests for teams playing that date (within their windows).
Stores AI summaries + source links only (no full article text).
"""

from datetime import datetime, timezone, timedelta
from typing import Optional, List

import requests
from fastapi import APIRouter, HTTPException

from services.supabase_client import get_supabase
from services.news_sources import fetch_league_items, fetch_team_items
from services.news_digester import build_digest, MODEL
from services.push import apns_send, push_users
from services.constants import TEAM_FULL_NAMES

router = APIRouter()
NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}


def _sb():
    sb = get_supabase()
    if sb is None:
        raise HTTPException(status_code=503, detail="Database not configured")
    return sb


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _games_for_date(date_str: str) -> List[dict]:
    """Each team playing `date_str` with its game start (UTC)."""
    try:
        r = requests.get(f"https://api-web.nhle.com/v1/schedule/{date_str}", headers=NHL_HEADERS, timeout=15)
        data = r.json()
    except Exception:
        return []
    out = []
    for day in data.get("gameWeek", []):
        if day.get("date") != date_str:
            continue
        for g in day.get("games", []):
            st = g.get("startTimeUTC")
            if not st:
                continue
            gutc = datetime.fromisoformat(st.replace("Z", "+00:00"))
            a = (g.get("awayTeam") or {}).get("abbrev")
            h = (g.get("homeTeam") or {}).get("abbrev")
            for team in (a, h):
                if team:
                    out.append({"team": team, "game_utc": gutc})
    return out


def _exists(sb, date_str: str, kind: str, scope: str) -> bool:
    rows = sb.table("news_digests").select("id").eq("digest_date", date_str).eq("kind", kind).eq("scope", scope).execute().data
    return bool(rows)


def _store(sb, date_str: str, kind: str, scope: str, digest: dict) -> None:
    sb.table("news_digests").upsert([{
        "digest_date": date_str, "kind": kind, "scope": scope,
        "title": digest["title"], "intro": digest["intro"], "items": digest["items"],
        "model": MODEL, "created_at": _now(),
    }], on_conflict="digest_date,kind,scope").execute()


@router.post("/news/generate/{date_str}/{kind}")
def generate(date_str: str, kind: str):
    """Cron/admin: build + store digests for a date. Idempotent per (date, kind, scope)."""
    if kind not in ("morning", "pregame", "postgame"):
        raise HTTPException(status_code=400, detail="kind must be morning|pregame|postgame")
    sb = _sb()

    if kind == "morning":
        if _exists(sb, date_str, "morning", "league"):
            return {"skipped": "already generated"}
        digest = build_digest(fetch_league_items(), "league", "morning", max_items=8)
        if not digest:
            raise HTTPException(status_code=502, detail="Could not build digest")
        _store(sb, date_str, "morning", "league", digest)
        tokens = [t["token"] for t in sb.table("device_tokens").select("token").execute().data]
        apns_send(tokens, "Morning hockey digest 🏒",
                  (digest.get("intro") or "Today's NHL roundup is ready.")[:140])
        return {"generated": ["league"], "items": len(digest["items"])}

    now = datetime.now(timezone.utc)
    generated = []
    for g in _games_for_date(date_str):
        team, gutc = g["team"], g["game_utc"]
        if kind == "pregame":
            in_window = gutc - timedelta(hours=4) <= now <= gutc - timedelta(hours=1)
        else:  # postgame — a few hours after the (~3h) game ends
            in_window = now >= gutc + timedelta(hours=5)
        if not in_window or _exists(sb, date_str, kind, team):
            continue
        digest = build_digest(fetch_team_items(team), team, kind, max_items=6)
        if not digest:
            continue
        _store(sb, date_str, kind, team, digest)
        generated.append(team)
        followers = sb.table("profiles").select("id").eq("favorite_team", team).execute().data
        label = "Pre-Game" if kind == "pregame" else "Post-Game"
        push_users(sb, [u["id"] for u in followers],
                   f"{TEAM_FULL_NAMES.get(team, team)} — {label} digest",
                   (digest.get("intro") or "")[:140])
    return {"generated": generated}


@router.get("/news/latest")
def latest(team: Optional[str] = None):
    """App feed: the latest league morning digest + the favorite team's recent digests."""
    sb = _sb()
    digests = sb.table("news_digests").select("*").eq("scope", "league").eq("kind", "morning") \
        .order("digest_date", desc=True).limit(1).execute().data
    if team:
        digests += sb.table("news_digests").select("*").eq("scope", team) \
            .order("created_at", desc=True).limit(4).execute().data
    return {"digests": digests}
