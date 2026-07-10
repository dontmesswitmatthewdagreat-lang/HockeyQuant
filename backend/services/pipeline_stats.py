"""
Live prospect performance:

- CHL (OHL/WHL/QMJHL) season stats via the same HockeyTech feed the headshot
  pipeline uses — name-matched onto team prospect pools so "My Team" rows show
  real junior production.
- Calder Watch: prospects-table players who are putting up NHL numbers in the
  current MoneyPuck season — the rookie race, dormant during the offseason.
"""

import time
from typing import Dict, List, Optional

from services.prospect_headshots import _feed, _current_regular_season, _norm, CHL_CLIENTS

_cache: Dict[str, dict] = {}
_TTL = 6 * 3600


def chl_skater_stats() -> Dict[str, dict]:
    """norm(name) -> {league, gp, goals, assists, points} across the three CHL leagues."""
    entry = _cache.get("chl")
    if entry and time.time() - entry["ts"] < _TTL:
        return entry["data"]
    out: Dict[str, dict] = {}
    for league, client in CHL_CLIENTS.items():
        try:
            sid = _current_regular_season(client)
            if not sid:
                continue
            rows = _feed(client, "statviewtype", type="topscorers",
                         season_id=sid, limit=1200).get("Statviewtype", [])
        except Exception:
            continue
        for r in rows:
            name = f"{r.get('first_name', '')} {r.get('last_name', '')}".strip()
            if not name:
                continue
            try:
                out.setdefault(_norm(name.replace(" ", "")) or name.lower(), {
                    "name": name,
                    "league": league,
                    "gp": int(r.get("games_played") or 0),
                    "goals": int(r.get("goals") or 0),
                    "assists": int(r.get("assists") or 0),
                    "points": int(r.get("points") or 0),
                })
            except (TypeError, ValueError):
                continue
    _cache["chl"] = {"ts": time.time(), "data": out}
    return out


def stats_for_names(names: List[str]) -> Dict[str, dict]:
    """Original name -> junior stat line, for the names we can match."""
    table = chl_skater_stats()
    out = {}
    for n in names:
        hit = table.get(_norm(n.replace(" ", "")) or n.lower())
        if hit:
            out[n] = hit
    return out


# MARK: - Calder Watch

def calder_watch(sb) -> dict:
    """Prospects (from our pools) who are producing in the NHL this season.
    Inactive during the offseason so it lights up on opening night."""
    import datetime
    today = datetime.date.today()
    active = today.month not in (7, 8, 9)   # deck is dark July–September

    entry = _cache.get("calder")
    if entry and time.time() - entry["ts"] < _TTL and entry["active"] == active:
        return entry["data"]

    season_start = today.year if today.month >= 10 else today.year - 1
    season_label = f"{season_start}-{(season_start + 1) % 100:02d}"
    result = {"active": active, "season": season_label, "players": []}
    if not active:
        _cache["calder"] = {"ts": time.time(), "active": active, "data": result}
        return result

    try:
        rows = sb.table("prospects").select("name,team,info").not_.is_("team", "null") \
            .limit(1500).execute().data
    except Exception:
        rows = sb.table("prospects").select("name,team,info").limit(1500).execute().data
        rows = [r for r in rows if r.get("team")]

    pool = {}
    for r in rows:
        pool[_norm(r["name"].replace(" ", "")) or r["name"].lower()] = r

    from services.data_loader import get_data_loader
    loader = get_data_loader()
    loader.load_all_data()
    df = loader.skater_data
    players = []
    if df is not None:
        for _, s in df.iterrows():
            key = _norm(str(s["name"]).replace(" ", "")) or str(s["name"]).lower()
            hit = pool.get(key)
            if not hit:
                continue
            gp = int(s.get("games_played", 0) or 0)
            if gp < 1:
                continue
            goals = int(float(s.get("I_F_goals", 0) or 0))
            assists = int(float(s.get("I_F_primaryAssists", 0) or 0)
                          + float(s.get("I_F_secondaryAssists", 0) or 0))
            players.append({
                "name": str(s["name"]),
                "team": str(s.get("team", "")),
                "position": str(s.get("position", "?")).upper(),
                "gamesPlayed": gp,
                "goals": goals,
                "assists": assists,
                "points": goals + assists,
                "headshot": (hit.get("info") or {}).get("headshot"),
            })
    players.sort(key=lambda p: (-p["points"], -p["goals"]))
    result["players"] = players[:25]
    _cache["calder"] = {"ts": time.time(), "active": active, "data": result}
    return result
