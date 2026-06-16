"""
Prospect tracking from the NHL API: this year's draft-eligible rankings
(league-wide) + each team's prospect pool. Free, no scraping.
"""

import hashlib
from datetime import datetime, timezone
from typing import List, Dict

import requests

from services.constants import NHL_DIVISIONS
from services.prospect_headshots import attach_chl_headshots

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


def sync_all(sb) -> int:
    """Fetch draft rankings + all team pools and upsert (on nhl_id)."""
    rows = fetch_draft_rankings()
    for t in ALL_TEAMS:
        rows += fetch_team_prospects(t)
    attach_chl_headshots(rows)   # CHL roster photos for draft-eligible prospects
    now = datetime.now(timezone.utc).isoformat()
    for r in rows:
        r["updated_at"] = now
    for i in range(0, len(rows), 300):
        sb.table("prospects").upsert(rows[i:i + 300], on_conflict="nhl_id").execute()
    return len(rows)
