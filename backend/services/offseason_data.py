"""
Offseason GM data: real free agents, team cap space, and team rosters,
scraped from Spotrac with long-lived in-memory caches (the data moves on an
hours timescale, and we want to be a polite scraper).
"""

import re
import time
from typing import Any, Dict, List, Optional

import requests

_UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"}
_FA_URL = "https://www.spotrac.com/nhl/free-agents/"
_CAP_URL = "https://www.spotrac.com/nhl/cap/_/year/2026"
_TEAM_URL = "https://www.spotrac.com/nhl/{slug}/cap/_/year/2026"
_TTL = 12 * 3600

_cache: Dict[str, Any] = {}

# Spotrac team-page slugs + abbrev normalization (Spotrac uses a few short forms).
TEAM_SLUGS = {
    "ANA": "anaheim-ducks", "BOS": "boston-bruins", "BUF": "buffalo-sabres",
    "CAR": "carolina-hurricanes", "CBJ": "columbus-blue-jackets", "CGY": "calgary-flames",
    "CHI": "chicago-blackhawks", "COL": "colorado-avalanche", "DAL": "dallas-stars",
    "DET": "detroit-red-wings", "EDM": "edmonton-oilers", "FLA": "florida-panthers",
    "LAK": "los-angeles-kings", "MIN": "minnesota-wild", "MTL": "montreal-canadiens",
    "NJD": "new-jersey-devils", "NSH": "nashville-predators", "NYI": "new-york-islanders",
    "NYR": "new-york-rangers", "OTT": "ottawa-senators", "PHI": "philadelphia-flyers",
    "PIT": "pittsburgh-penguins", "SEA": "seattle-kraken", "SJS": "san-jose-sharks",
    "STL": "st-louis-blues", "TBL": "tampa-bay-lightning", "TOR": "toronto-maple-leafs",
    "UTA": "utah-mammoth", "VAN": "vancouver-canucks", "VGK": "vegas-golden-knights",
    "WPG": "winnipeg-jets", "WSH": "washington-capitals",
}
_ABBREV_FIX = {"SJ": "SJS", "TB": "TBL", "LA": "LAK", "NJ": "NJD", "WAS": "WSH",
               "VGS": "VGK", "MON": "MTL", "UTAH": "UTA"}


def _norm_abbrev(a: str) -> str:
    a = (a or "").strip().upper()
    return _ABBREV_FIX.get(a, a)


def _get(url: str) -> str:
    r = requests.get(url, headers=_UA, timeout=25)
    r.raise_for_status()
    return r.text


def _cached(key: str, fetch):
    entry = _cache.get(key)
    if entry and time.time() - entry["ts"] < _TTL:
        return entry["data"]
    data = fetch()
    _cache[key] = {"ts": time.time(), "data": data}
    return data


def _cells(row_html: str) -> List[str]:
    """Plain-text contents of each <td> in a row."""
    tds = re.findall(r"<td[^>]*>(.*?)</td>", row_html, re.S)
    out = []
    for td in tds:
        txt = re.sub(r"<[^>]+>", " ", td)
        out.append(re.sub(r"\s+", " ", txt).strip())
    return out


def _dollars(s: str) -> Optional[float]:
    m = re.search(r"(-?)\$(-?)([\d,]+)", s or "")
    if not m:
        return None
    v = float(m.group(3).replace(",", ""))
    return -v if (m.group(1) or m.group(2)) else v


# MARK: free agents ----------------------------------------------------------

def fetch_free_agents() -> List[Dict[str, Any]]:
    """The *available* free-agent pool (Spotrac's second table: Player, Pos,
    Shoots, Age, YOE, Prev Team, Prev AAV, Type)."""
    def _fetch():
        html = _get(_FA_URL)
        # The available-players table is the one whose header block mentions
        # "Prev Team"; parse rows after that header.
        anchor = html.find("Prev Team")
        if anchor == -1:
            return []
        section = html[anchor:]
        rows = re.findall(r"<tr[^>]*>(.*?)</tr>", section, re.S)
        agents = []
        for row in rows:
            name_m = re.search(r"/nhl/player/[^\"]*\"[^>]*>([^<]{3,50})</a>", row)
            if not name_m:
                continue
            cells = _cells(row)
            # Expected: [player, pos, shoots, age, yoe, prev team, prev aav, type]
            if len(cells) < 8:
                continue
            # Prev team is plain text after the crest <img> in the 6th cell.
            prev_team = _norm_abbrev(cells[5]) if re.fullmatch(r"[A-Za-z]{2,4}", cells[5]) else None
            fa_type = cells[-1].upper()
            if "UFA" not in fa_type and "RFA" not in fa_type:
                continue
            try:
                age = int(re.search(r"\d+", cells[3]).group(0)) if re.search(r"\d+", cells[3]) else None
            except Exception:
                age = None
            agents.append({
                "name": name_m.group(1).strip(),
                "position": cells[1][:3].upper(),
                "age": age,
                "prev_team": prev_team,
                "prev_aav": _dollars(cells[-2]),
                "type": "RFA" if "RFA" in fa_type else "UFA",
            })
        return agents
    return _cached("fa", _fetch)


# MARK: team cap -------------------------------------------------------------

def fetch_team_caps() -> List[Dict[str, Any]]:
    """Per-team cap space + total allocations from the league cap table."""
    def _fetch():
        html = _get(_CAP_URL)
        tb = html.find("<tbody")
        rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html[tb:], re.S)
        teams = []
        for row in rows:
            ab_m = re.search(r'<span class="d-none">([A-Z]{2,4})</span>', row)
            if not ab_m:
                continue
            # Spotrac serves this table with varying column counts; the first
            # dollar cell is always Cap Space, the second (when present) Total
            # Cap Allocations.
            dollars = [d for d in (_dollars(c) for c in _cells(row)) if d is not None]
            if not dollars:
                continue
            teams.append({
                "abbrev": _norm_abbrev(ab_m.group(1)),
                "cap_space": dollars[0],
                "cap_total": dollars[1] if len(dollars) > 1 else None,
            })
        return teams
    return _cached("caps", _fetch)


# MARK: team roster ----------------------------------------------------------

_POSITIONS = {"C", "LW", "RW", "W", "D", "G", "F"}


def fetch_roster(abbrev: str) -> List[Dict[str, Any]]:
    """Contracted players (name, pos, age, AAV) for a team's current cap page."""
    slug = TEAM_SLUGS.get(_norm_abbrev(abbrev))
    if not slug:
        return []

    def _fetch():
        html = _get(_TEAM_URL.format(slug=slug))
        rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.S)
        players, seen = [], set()
        for row in rows:
            name_m = re.search(r"/nhl/player/[^\"]*\"[^>]*>([^<]{3,50})</a>", row)
            if not name_m:
                continue
            name = name_m.group(1).strip()
            if name in seen:
                continue
            cells = _cells(row)
            # Row shape: [name, pos, cap hit, base, cap %, bonuses, total, ...]
            if len(cells) < 3:
                continue
            pos = cells[1].upper() if cells[1].upper() in _POSITIONS else "?"
            aav = _dollars(cells[2])
            if not aav or aav < 500_000:
                continue
            seen.add(name)
            players.append({"name": name, "position": pos, "aav": aav})
        players.sort(key=lambda p: -p["aav"])
        return players
    return _cached(f"roster:{slug}", _fetch)
