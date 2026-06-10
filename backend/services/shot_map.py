"""
Shot map data from the NHL play-by-play. Resolves the game from date+teams,
pulls every shot (on-goal / goal / missed), and normalizes each team's shots
onto its attacking half-rink so location is comparable despite period end-swaps.

Blocked shots are excluded: the NHL credits them to the blocking team, so both
the owner and the coordinate are the defender's, not the shooter's.
"""

import time
from typing import Dict, Optional, Tuple

import requests

NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}
BASE = "https://api-web.nhle.com/v1"
SHOT_TYPES = {"shot-on-goal": "shot", "goal": "goal", "missed-shot": "miss"}

_cache: Dict[str, Tuple[float, dict]] = {}
_TTL = 900  # 15 min


def resolve_game_id(date_str: str, away: str, home: str) -> Tuple[Optional[int], Optional[str]]:
    """Find the NHL game id + state for a matchup on a date (via /score/{date})."""
    try:
        data = requests.get(f"{BASE}/score/{date_str}", headers=NHL_HEADERS, timeout=12).json()
    except Exception:
        return None, None
    for g in data.get("games", []):
        a = g.get("awayTeam", {}).get("abbrev")
        h = g.get("homeTeam", {}).get("abbrev")
        if a == away.upper() and h == home.upper():
            return g.get("id"), g.get("gameState")
    return None, None


def _player_name(spot: dict) -> str:
    first = (spot.get("firstName") or {}).get("default", "")
    last = (spot.get("lastName") or {}).get("default", "")
    return f"{first[:1]}. {last}".strip(". ") if last else (first or "")


def fetch_shot_map(date_str: str, away: str, home: str) -> dict:
    away, home = away.upper(), home.upper()
    gid, state = resolve_game_id(date_str, away, home)
    if not gid:
        return {"available": False, "shots": []}

    ck = str(gid)
    hit = _cache.get(ck)
    if hit and time.time() - hit[0] < _TTL:
        return hit[1]

    try:
        pbp = requests.get(f"{BASE}/gamecenter/{gid}/play-by-play", headers=NHL_HEADERS, timeout=15).json()
    except Exception:
        return {"available": False, "shots": []}

    home_id = pbp.get("homeTeam", {}).get("id")
    away_id = pbp.get("awayTeam", {}).get("id")
    team_abbrev = {home_id: home, away_id: away}
    names = {s.get("playerId"): _player_name(s) for s in pbp.get("rosterSpots", [])}

    raw = []
    for p in pbp.get("plays", []):
        result = SHOT_TYPES.get(p.get("typeDescKey"))
        if not result:
            continue
        det = p.get("details", {})
        x, y = det.get("xCoord"), det.get("yCoord")
        if x is None or y is None:
            continue
        owner = det.get("eventOwnerTeamId")
        team = team_abbrev.get(owner)
        if team is None:
            continue
        shooter_id = det.get("scoringPlayerId") or det.get("shootingPlayerId")
        raw.append({
            "x": float(x), "y": float(y), "team": team, "result": result,
            "period": (p.get("periodDescriptor", {}) or {}).get("number", 1),
            "shotType": det.get("shotType"),
            "shooter": names.get(shooter_id),
            "_sort": p.get("sortOrder", 0),
        })

    # Normalize each team onto one attacking half: the side where most of its
    # shots already are. Then orient home→+x (right net), away→−x (left net).
    def _attacking_sign(team: str) -> int:
        xs = [s["x"] for s in raw if s["team"] == team]
        return 1 if sum(1 for v in xs if v >= 0) >= sum(1 for v in xs if v < 0) else -1

    sign = {home: _attacking_sign(home), away: _attacking_sign(away)}
    target = {home: 1, away: -1}
    for s in raw:
        # collapse onto the team's own attacking side, then flip to the target side
        if (s["x"] >= 0) != (sign[s["team"]] >= 0):
            s["x"], s["y"] = -s["x"], -s["y"]
        if sign[s["team"]] != target[s["team"]]:
            s["x"], s["y"] = -s["x"], -s["y"]

    raw.sort(key=lambda s: (s["period"], s["_sort"]))
    shots = [{k: s[k] for k in ("x", "y", "team", "result", "period", "shotType", "shooter")} for s in raw]

    def _summary(team: str) -> dict:
        ts = [s for s in shots if s["team"] == team]
        return {"sog": sum(1 for s in ts if s["result"] in ("shot", "goal")),
                "goals": sum(1 for s in ts if s["result"] == "goal")}

    out = {
        "available": True,
        "game_state": state,
        "home": home, "away": away,
        "shots": shots,
        "summary": {"home": _summary(home), "away": _summary(away)},
    }
    _cache[ck] = (time.time(), out)
    return out
