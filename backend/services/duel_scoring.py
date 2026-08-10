"""Weekly scoring for Global League duels.

Two numbers per roster, kept separate all the way into the table:

  score  — what the skaters produced: goals and assists.
  bonus  — the defensive and goaltending layer, so a shutdown defenceman or a
           goalie stealing games is worth drafting instead of dead weight.

A note on what's measurable. The NHL per-game log carries goals, assists,
plus/minus, shorthanded production, shots and ice time — but *not* hits,
blocked shots or takeaways, which only appear in per-game boxscores. Pulling a
boxscore for every player-game would be a large multiplier of requests for a
weekly job, so the defensive signal here is plus/minus and shorthanded play
(both genuinely defensive, both per-game) plus a premium on defencemen's
points, since a defenceman scores far less than a forward and would otherwise
never be worth a pick.
"""

import datetime
import time
from typing import Optional

import requests

# --- skater base -------------------------------------------------------------
GOAL = 3.0
ASSIST = 2.0

# --- defensive layer ---------------------------------------------------------
PLUS_MINUS = 1.0          # on-ice goal differential
SHORTHANDED_POINT = 2.0   # penalty-kill production, on top of the base
# No defenceman premium: the roster is positionally locked (C, LW, RW, D, D, G),
# so nobody ever chooses between a forward and a blueliner. Both sides ice two
# defencemen either way, and a premium would only amplify whoever happened to
# roll the better D tier.

# --- goaltending -------------------------------------------------------------
WIN = 3.0
SAVE = 0.15
GOAL_AGAINST = -1.0   # kept mild on purpose: every roster must start a
                      # goalie, so a bad night should be a weak week, not a
                      # negative one that beats leaving the slot empty.
SHUTOUT = 3.0

_LOG_URL = "https://api-web.nhle.com/v1/player/{pid}/game-log/{season}/2"
_TTL = 3600
_cache: dict = {}


def current_season(today: Optional[datetime.date] = None) -> str:
    """NHL season id like 20252026. The league year flips in September."""
    d = today or datetime.date.today()
    start = d.year if d.month >= 9 else d.year - 1
    return f"{start}{start + 1}"


def game_log(nhl_id: int, season: str) -> list:
    """Cached per-player game log. Many duels share stars in the same week."""
    key = (nhl_id, season)
    hit = _cache.get(key)
    if hit and time.time() - hit["ts"] < _TTL:
        return hit["data"]
    try:
        r = requests.get(_LOG_URL.format(pid=nhl_id, season=season), timeout=20)
        r.raise_for_status()
        games = r.json().get("gameLog", []) or []
    except Exception:
        # Never let one unreachable player zero out a whole roster — serve the
        # last good log if we have one, otherwise treat as no games played.
        return hit["data"] if hit else []
    _cache[key] = {"ts": time.time(), "data": games}
    return games


def _in_week(game: dict, start: datetime.date, end: datetime.date) -> bool:
    try:
        d = datetime.date.fromisoformat(str(game.get("gameDate"))[:10])
    except ValueError:
        return False
    return start <= d <= end


def score_player(nhl_id: int, position: str, start: datetime.date,
                 end: datetime.date, season: Optional[str] = None) -> dict:
    """Score one player's week. Returns base, bonus and the raw line."""
    season = season or current_season(end)
    games = [g for g in game_log(nhl_id, season) if _in_week(g, start, end)]
    is_goalie = (position or "").upper() == "G"

    if is_goalie:
        saves = wins = ga = so = 0
        for g in games:
            shots, against = g.get("shotsAgainst") or 0, g.get("goalsAgainst") or 0
            saves += max(0, shots - against)
            ga += against
            so += g.get("shutouts") or 0
            if (g.get("decision") or "").upper() == "W":
                wins += 1
        bonus = wins * WIN + saves * SAVE + ga * GOAL_AGAINST + so * SHUTOUT
        return {"nhl_id": nhl_id, "games": len(games), "base": 0.0,
                "bonus": round(bonus, 2),
                "line": {"wins": wins, "saves": saves, "ga": ga, "shutouts": so}}

    goals = sum(g.get("goals") or 0 for g in games)
    assists = sum(g.get("assists") or 0 for g in games)
    plus_minus = sum(g.get("plusMinus") or 0 for g in games)
    sh_points = sum(g.get("shorthandedPoints") or 0 for g in games)
    base = goals * GOAL + assists * ASSIST
    bonus = plus_minus * PLUS_MINUS + sh_points * SHORTHANDED_POINT
    return {"nhl_id": nhl_id, "games": len(games), "base": round(base, 2),
            "bonus": round(bonus, 2),
            "line": {"g": goals, "a": assists, "+/-": plus_minus, "sh": sh_points}}


def score_roster(players: list, start: datetime.date, end: datetime.date) -> dict:
    """players: [{nhl_id, position}] — the drafted roster for one side."""
    rows = [score_player(p["nhl_id"], p.get("position", ""), start, end)
            for p in players]
    return {"base": round(sum(r["base"] for r in rows), 2),
            "bonus": round(sum(r["bonus"] for r in rows), 2),
            "players": rows}


def grade_week(sb, week_start: Optional[datetime.date] = None) -> dict:
    """Score and settle every live duel for a finished week."""
    from services.duels import apply_result, week_bounds

    if week_start is None:
        week_start = week_bounds()[0] - datetime.timedelta(days=7)
    week_end = week_start + datetime.timedelta(days=6)

    duels = (sb.table("duels").select("*")
             .eq("week_start", str(week_start)).eq("state", "live")
             .limit(500).execute().data)
    if not duels:
        return {"graded": 0, "week_start": str(week_start)}

    graded = []
    for duel in duels:
        picks = (sb.table("duel_picks").select("user_id,chosen_nhl_id,slot")
                 .eq("duel_id", duel["id"]).limit(64).execute().data)
        ids = [p["chosen_nhl_id"] for p in picks if p["chosen_nhl_id"]]
        if not ids:
            continue
        meta = (sb.table("fantasy_players").select("nhl_id,position")
                .in_("nhl_id", ids).limit(64).execute().data)
        pos = {m["nhl_id"]: m["position"] for m in meta}

        sides = {duel["user_a"]: [], duel["user_b"]: []}
        for p in picks:
            if p["chosen_nhl_id"] and p["user_id"] in sides:
                sides[p["user_id"]].append({
                    "nhl_id": p["chosen_nhl_id"],
                    "position": pos.get(p["chosen_nhl_id"], ""),
                })

        a = score_roster(sides[duel["user_a"]], week_start, week_end)
        b = score_roster(sides[duel["user_b"]], week_start, week_end)
        result = apply_result(sb, duel["id"], a["base"], b["base"],
                              a["bonus"], b["bonus"])
        graded.append({"duel_id": duel["id"], **result})

    return {"graded": len(graded), "week_start": str(week_start), "results": graded}
