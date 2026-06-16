"""
Headshots for draft-eligible prospects (the NHL has none for un-drafted players,
so the league draft board otherwise shows only initials).

Two sources, both public and license-clean, applied in order during sync:

1. CHL roster photos (OHL/WHL/QMJHL) via the HockeyTech/LeagueStat `modulekit`
   feed — the same feed their own sites/apps use (no scraping). Covers ~96% of
   CHL prospects, roughly half the full board.
2. Wikidata-validated Wikimedia photos for the *notable* prospects CHL doesn't
   cover (USHL/NCAA/European juniors). Each match is confirmed to be a human
   ice-hockey player whose birth year matches the prospect's, so we never attach
   the wrong person's photo. Coverage is low (most draft-eligible teens have no
   Wikipedia photo yet) but grows over time.

Still uncovered: USHL via its own roster feed (open photo CDN, but the feed is
key-gated and ushl.com — a SidearmSports site — doesn't expose a live key).
"""

import re
import time
import unicodedata
import urllib.parse
from datetime import date, timedelta
from typing import Dict, List, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor

import requests

# NHL draft-ranking league code -> HockeyTech client_code.
CHL_CLIENTS = {"OHL": "ohl", "WHL": "whl", "QMJHL": "lhjmq"}

_FEED = "https://lscluster.hockeytech.com/feed/index.php"
_KEY = "f1aa699db3d81487"  # public LeagueStat key used by the CHL sites/apps
_SESSION = requests.Session()
# Descriptive UA per Wikimedia's policy (bare UAs from cloud IPs get throttled).
_SESSION.headers["User-Agent"] = "HockeyQuant/1.0 (https://hockeyquant.onrender.com; matthew4000@icloud.com)"


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


# --- Source 2: Wikidata-validated Wikimedia photos (the rest of the board) -----

_WD_API = "https://www.wikidata.org/w/api.php"
_Q_HUMAN = "Q5"
_Q_HOCKEY_PLAYER = "Q11774891"
_Q_ICE_HOCKEY = "Q41466"


def _wd_get(params: dict) -> dict:
    """Polite Wikidata GET with retries; tolerates throttle/non-JSON responses."""
    for i in range(3):
        try:
            r = _SESSION.get(_WD_API, params={**params, "format": "json"}, timeout=20)
            if r.text.lstrip().startswith("{"):
                data = r.json()
                if "error" not in data:        # e.g. maxlag/ratelimited — back off
                    return data
        except Exception:
            pass
        time.sleep(0.6 * (i + 1))
    return {}


def _claim_ids(claims: dict, prop: str) -> list:
    out = []
    for c in claims.get(prop, []):
        try:
            out.append(c["mainsnak"]["datavalue"]["value"]["id"])
        except (KeyError, TypeError):
            pass
    return out


def _claim_birth_year(claims: dict) -> Optional[str]:
    for c in claims.get("P569", []):
        try:
            return c["mainsnak"]["datavalue"]["value"]["time"][1:5]
        except (KeyError, TypeError):
            pass
    return None


def _claim_image(claims: dict) -> Optional[str]:
    for c in claims.get("P18", []):
        try:
            return c["mainsnak"]["datavalue"]["value"]
        except (KeyError, TypeError):
            pass
    return None


def _wikidata_headshot(name: str, birth_iso: Optional[str]) -> Tuple[Optional[str], bool]:
    """
    A Wikimedia Commons headshot for `name`, but only when Wikidata confirms the
    matched entity is a human ice-hockey player whose birth year matches the
    prospect's — so we never attach the wrong person's photo.

    Returns (url_or_None, searched_ok). `searched_ok` is False when an API call
    failed (transient) so the caller can avoid caching a non-result and retry
    later; True means we genuinely completed the search (hit or real miss).
    """
    year = (birth_iso or "")[:4]
    search = _wd_get({"action": "wbsearchentities", "search": name,
                      "language": "en", "type": "item", "limit": 6})
    if "search" not in search:
        return None, False   # search call failed — don't cache, retry next sync
    for hit in search["search"]:
        qid = hit.get("id")
        if not qid:
            continue
        ent = _wd_get({"action": "wbgetentities", "ids": qid, "props": "claims"})
        if "entities" not in ent:
            return None, False   # entity lookup failed — this hit may be the match
        claims = ent["entities"].get(qid, {}).get("claims", {})
        if _Q_HUMAN not in _claim_ids(claims, "P31"):
            continue
        if not (_Q_HOCKEY_PLAYER in _claim_ids(claims, "P106")
                or _Q_ICE_HOCKEY in _claim_ids(claims, "P641")):
            continue
        wd_year = _claim_birth_year(claims)
        if year and wd_year and year != wd_year:
            continue   # same name, different (usually older) player — skip
        image = _claim_image(claims)
        if image:
            f = urllib.parse.quote(image.replace(" ", "_"))
            return f"https://commons.wikimedia.org/wiki/Special:FilePath/{f}?width=320", True
    return None, True   # searched, no valid match


_WIKI_RECHECK_DAYS = 7


def attach_wikipedia_headshots(rows: List[dict]) -> int:
    """
    Fill `info["headshot"]` for *notable* draft prospects that CHL didn't cover
    (USHL/NCAA/European juniors) from Wikidata-validated Wikimedia photos.

    Bounded to the notable board, and each prospect is checked at most once per
    week (`info["wiki_ts"]`, carried across syncs) so we don't re-query Wikidata
    every run for the many teens who simply have no photo yet. Best-effort.
    """
    cutoff = (date.today() - timedelta(days=_WIKI_RECHECK_DAYS)).isoformat()
    targets = [r for r in rows
               if r.get("notable")
               and r.get("league") not in CHL_CLIENTS
               and not (r.get("info") or {}).get("headshot")
               and (r.get("info") or {}).get("wiki_ts", "") < cutoff]
    if not targets:
        return 0

    today = date.today().isoformat()

    def fill(r: dict) -> int:
        info = r.setdefault("info", {})
        url, searched_ok = _wikidata_headshot(r.get("name", ""), info.get("birth"))
        if searched_ok:
            info["wiki_ts"] = today   # cache only genuine results, never transient failures
        if url:
            info["headshot"] = url
            return 1
        return 0

    with ThreadPoolExecutor(max_workers=3) as ex:
        return sum(ex.map(fill, targets))
