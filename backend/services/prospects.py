"""
Prospect tracking from the NHL API: this year's draft-eligible rankings
(league-wide) + each team's prospect pool. Free, no scraping.
"""

import hashlib
from datetime import datetime, timezone
from typing import List, Dict

import requests

from services.constants import NHL_DIVISIONS
from services.prospect_headshots import attach_chl_headshots, attach_wikipedia_headshots

ALL_TEAMS = sorted({t for teams in NHL_DIVISIONS.values() for t in teams})
NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}


def _synthetic_id(name: str, year) -> int:
    """Stable negative id for draft-eligible prospects (no NHL id yet)."""
    h = int(hashlib.md5(f"{name}|{year}".encode()).hexdigest()[:12], 16)
    return -(h % 1_000_000_000)


def fetch_draft_rankings() -> List[Dict]:
    """Top draft-eligible prospects across all categories (NA/Intl skaters + goalies)."""
    out: List[Dict] = []
    try:
        base = requests.get("https://api-web.nhle.com/v1/draft/rankings/now", headers=NHL_HEADERS, timeout=15).json()
    except Exception:
        return out
    year = base.get("draftYear")
    cats = [c.get("id") for c in base.get("categories", []) if c.get("id")] or [1, 2, 3, 4]
    for cat in cats:
        try:
            data = requests.get(f"https://api-web.nhle.com/v1/draft/rankings/{year}/{cat}", headers=NHL_HEADERS, timeout=15).json()
        except Exception:
            continue
        for p in data.get("rankings", []):
            name = f"{p.get('firstName', '')} {p.get('lastName', '')}".strip()
            if not name:
                continue
            rank = p.get("finalRank") or p.get("midtermRank")
            out.append({
                "nhl_id": _synthetic_id(name, year),
                "name": name,
                "team": None,
                "position": p.get("positionCode"),
                "draft_year": year,
                "draft_overall": None,
                "league": p.get("lastAmateurLeague"),
                "ranking": rank,
                "notable": bool(rank and rank <= 32),
                "info": {
                    "club": p.get("lastAmateurClub"), "shoots": p.get("shootsCatches"),
                    "birth": p.get("birthDate"), "country": p.get("birthCountry"),
                    "category": data.get("categoryKey"), "category_id": cat,
                },
            })
    return out


def fetch_team_prospects(abbrev: str) -> List[Dict]:
    """A team's prospect pool (drafted, in the system, not yet established NHLers)."""
    out: List[Dict] = []
    try:
        data = requests.get(f"https://api-web.nhle.com/v1/prospects/{abbrev}", headers=NHL_HEADERS, timeout=15).json()
    except Exception:
        return out
    for grp in ("forwards", "defensemen", "goalies"):
        for p in data.get(grp, []):
            first = (p.get("firstName") or {}).get("default", "")
            last = (p.get("lastName") or {}).get("default", "")
            name = f"{first} {last}".strip()
            if not name or not p.get("id"):
                continue
            out.append({
                "nhl_id": p.get("id"),
                "name": name,
                "team": abbrev,
                "position": p.get("positionCode"),
                "draft_year": None,
                "draft_overall": None,
                "league": None,
                "ranking": None,
                "notable": False,
                "info": {"shoots": p.get("shootsCatches"), "birth": p.get("birthDate"),
                         "headshot": p.get("headshot"), "country": p.get("birthCountry")},
            })
    return out


def _reuse_existing_headshots(sb, rows: List[Dict]) -> None:
    """Carry over resolved headshots (and the Wikidata recheck timestamp) from the
    prior sync so we don't re-query external sources for prospects already handled."""
    try:
        existing = {r["nhl_id"]: (r.get("info") or {})
                    for r in sb.table("prospects").select("nhl_id,info").execute().data}
    except Exception:
        return
    for r in rows:
        prev = existing.get(r.get("nhl_id")) or {}
        info = r.get("info") or {}
        if not info.get("headshot") and prev.get("headshot"):
            r.setdefault("info", {})["headshot"] = prev["headshot"]
        if "wiki_ts" not in info and prev.get("wiki_ts"):
            r.setdefault("info", {})["wiki_ts"] = prev["wiki_ts"]


def sync_all(sb) -> int:
    """Fetch draft rankings + all team pools and upsert (on nhl_id)."""
    rows = fetch_draft_rankings()
    for t in ALL_TEAMS:
        rows += fetch_team_prospects(t)
    _reuse_existing_headshots(sb, rows)  # keep photos we already resolved
    attach_chl_headshots(rows)        # CHL roster photos for draft-eligible prospects
    attach_wikipedia_headshots(rows)  # Wikidata-validated photos for the rest of the board
    now = datetime.now(timezone.utc).isoformat()
    for r in rows:
        r["updated_at"] = now
    for i in range(0, len(rows), 300):
        sb.table("prospects").upsert(rows[i:i + 300], on_conflict="nhl_id").execute()
    _snapshot_rankings(sb, rows)
    return len(rows)


def _snapshot_rankings(sb, rows) -> None:
    """Append today's Central Scouting ranks so the app can show trends.
    Best-effort: skipped silently until the prospect_rankings table exists."""
    today = datetime.now(timezone.utc).date().isoformat()
    snaps = [{
        "nhl_id": r["nhl_id"],
        "list_date": today,
        "category_id": (r.get("info") or {}).get("category_id"),
        "rank": r["ranking"],
    } for r in rows if r.get("ranking") and r.get("nhl_id")]
    try:
        for i in range(0, len(snaps), 300):
            sb.table("prospect_rankings").upsert(
                snaps[i:i + 300], on_conflict="nhl_id,list_date").execute()
    except Exception as e:
        print(f"[prospects] ranking snapshot skipped: {e}")
