"""
Junior-league headshots for draft-eligible prospects (prototype #1: CHL).

The NHL publishes no headshot for un-drafted players, so the league-wide draft
board has only initials. The CHL leagues (OHL/WHL/QMJHL) publish official roster
photos through HockeyTech/LeagueStat — the same public `modulekit` feed their own
websites and apps use (no scraping). This module builds a name -> photo index
from those rosters and fills `info["headshot"]` on each matching draft prospect.

Coverage on the current board is ~97% of CHL prospects (~half the full board).
Not yet wired up: USHL (open photo CDN but the roster feed needs an authorized
key) and NCAA/European-junior (no single roster API).
"""

import re
import unicodedata
from datetime import date
from typing import Dict, List, Tuple
from concurrent.futures import ThreadPoolExecutor

import requests

# NHL draft-ranking league code -> HockeyTech client_code.
CHL_CLIENTS = {"OHL": "ohl", "WHL": "whl", "QMJHL": "lhjmq"}

_FEED = "https://lscluster.hockeytech.com/feed/index.php"
_KEY = "f1aa699db3d81487"  # public LeagueStat key used by the CHL sites/apps
_SESSION = requests.Session()
_SESSION.headers["User-Agent"] = "HockeyQuant/1.0"


def _feed(client: str, view: str, **params) -> dict:
    q = {"feed": "modulekit", "view": view, "key": _KEY,
         "client_code": client, "fmt": "json", "lang": "en"}
    q.update(params)
    try:
        return _SESSION.get(_FEED, params=q, timeout=25).json().get("SiteKit", {})
    except Exception:
        return {}


def _norm(s: str) -> str:
    """Lowercased, accent- and punctuation-stripped (e.g. 'José Dubé' -> 'josedube')."""
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z]", "", s.lower())


def _season_tokens() -> Tuple[str, str]:
    """(YYYY, YY) of the just-completed junior season for the upcoming draft."""
    t = date.today()
    start = t.year if t.month >= 8 else t.year - 1   # season starts in September
    return str(start), f"{(start + 1) % 100:02d}"


def _current_regular_season(client: str):
    y1, y2 = _season_tokens()
    seasons = _feed(client, "seasons").get("Seasons", [])
    for s in seasons:
        n = s.get("season_name", "")
        if "regular" in n.lower() and y1 in n and y2 in n:
            return s.get("season_id")
    # Fallback: first regular season the feed lists (newest).
    reg = [s for s in seasons if "regular" in (s.get("season_name") or "").lower()]
    return reg[0].get("season_id") if reg else None


def _league_photos(client: str) -> Tuple[Dict[str, str], Dict[str, list]]:
    """Build {firstlast: image} and {last: [(first_initial, image)]} for one league."""
    sid = _current_regular_season(client)
    if not sid:
        return {}, {}
    teams = _feed(client, "teamsbyseason", season_id=sid).get("Teamsbyseason", [])

    def roster(team):
        tid = team.get("id") or team.get("team_id")
        rows = _feed(client, "roster", team_id=tid, season_id=sid).get("Roster", [])
        return [p for p in rows if isinstance(p, dict) and p.get("player_image")]

    exact: Dict[str, str] = {}
    by_last: Dict[str, list] = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        for players in ex.map(roster, teams):
            for p in players:
                first, last = p.get("first_name", ""), p.get("last_name", "")
                img = p["player_image"]
                exact[_norm(first) + _norm(last)] = img
                by_last.setdefault(_norm(last), []).append((_norm(first)[:1], img))
    return exact, by_last


def attach_chl_headshots(rows: List[dict]) -> int:
    """
    Fill `info["headshot"]` for every CHL draft prospect that lacks one, using the
    league's official roster photo. Returns the count filled. Best-effort: a feed
    failure just leaves those prospects on the initials fallback.

    Matching is by normalized name: exact full-name first, then a last-name +
    first-initial fallback (only when unambiguous) to catch transliterations.
    """
    targets = [r for r in rows
               if r.get("league") in CHL_CLIENTS
               and not (r.get("info") or {}).get("headshot")]
    if not targets:
        return 0

    indexes = {code: _league_photos(client)
               for code, client in CHL_CLIENTS.items()
               if any(r.get("league") == code for r in targets)}

    filled = 0
    for r in targets:
        exact, by_last = indexes.get(r["league"], ({}, {}))
        name = (r.get("name") or "").split()
        if not name:
            continue
        first, last = name[0], name[-1]
        img = exact.get(_norm("".join(name)))
        if not img:
            cands = [u for ini, u in by_last.get(_norm(last), []) if ini == _norm(first)[:1]]
            img = cands[0] if len(cands) == 1 else None   # skip ambiguous last names
        if img:
            info = r.setdefault("info", {})
            info["headshot"] = img
            filled += 1
    return filled
