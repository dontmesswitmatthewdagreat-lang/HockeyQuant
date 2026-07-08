"""Actual NHL draft results (post-draft): picks by year/team, cached in memory."""

import time
from typing import Dict, List, Optional

import requests

NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}
_cache: Dict[int, dict] = {}
_TTL = 12 * 3600


def fetch_draft_picks(year: int) -> List[dict]:
    """All picks for a draft year (empty until the draft happens)."""
    entry = _cache.get(year)
    if entry and time.time() - entry["ts"] < _TTL:
        return entry["picks"]
    picks = []
    try:
        data = requests.get(f"https://api-web.nhle.com/v1/draft/picks/{year}/all",
                            headers=NHL_HEADERS, timeout=15).json()
        for p in data.get("picks", []):
            first = (p.get("firstName") or {}).get("default", "")
            last = (p.get("lastName") or {}).get("default", "")
            name = f"{first} {last}".strip()
            if not name or not p.get("overallPick"):
                continue
            picks.append({
                "round": p.get("round"),
                "overall": p.get("overallPick"),
                "team": p.get("teamAbbrev"),
                "player": name,
                "position": p.get("positionCode"),
                "country": p.get("countryCode"),
                "league": p.get("amateurLeague"),
                "club": p.get("amateurClubName"),
            })
    except Exception:
        return entry["picks"] if entry else []
    _cache[year] = {"ts": time.time(), "picks": picks}
    return picks


def drafted_lookup(year: int) -> Dict[str, dict]:
    """Lowercased player name → pick."""
    return {p["player"].lower(): p for p in fetch_draft_picks(year)}


def team_picks(year: int, abbrev: str) -> List[dict]:
    return [p for p in fetch_draft_picks(year) if p["team"] == abbrev.upper()]
