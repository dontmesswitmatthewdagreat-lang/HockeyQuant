"""
Season & playoff odds via Monte-Carlo. Uses cheap team strength ratings (MoneyPuck,
no per-game analysis) → per-game win prob, simulates the remaining schedule N times
→ projected points, playoff %, and Cup % (NHL seeding + a re-seeded bracket).

Mode-aware: `season` (a real in-progress season, or a `mock` one for testing) vs
`playoffs` (the current postseason fallback — Cup % for the teams still alive).
"""

import math
import random
import time
from typing import Dict, List, Optional, Tuple

import numpy as np
import requests

from services.analyzer import NHLAnalyzer
from services.goal_predictor import GoalPredictor, calc_moneyline_prob
from services.constants import NHL_DIVISIONS, NHL_CONFERENCES

BASE = "https://api-web.nhle.com/v1"
NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}

ALL_TEAMS = sorted({t for ts in NHL_DIVISIONS.values() for t in ts})
TEAM_DIV = {t: d for d, ts in NHL_DIVISIONS.items() for t in ts}
_DIV_CONF = {d: c for c, divs in NHL_CONFERENCES.items() for d in divs}
TEAM_CONF = {t: _DIV_CONF[TEAM_DIV[t]] for t in ALL_TEAMS}

_analyzer_singleton: Optional[NHLAnalyzer] = None
_cache: Dict[str, Tuple[float, dict]] = {}
_TTL = 1800
N_SIMS = 1500


def _analyzer() -> NHLAnalyzer:
    global _analyzer_singleton
    if _analyzer_singleton is None:
        _analyzer_singleton = NHLAnalyzer()
    return _analyzer_singleton


def _ratings() -> Tuple[Dict[str, Tuple[float, float]], float]:
    an = _analyzer()
    gp = GoalPredictor(data_loader=an.data_loader, analyzer=an)
    la = gp._get_league_avg_goals_per_game()
    return {t: gp._get_team_strength(t, la) for t in ALL_TEAMS}, la


def _game_probs(ratings, la, a, b, a_home):
    """(p_a_reg, p_b_reg, p_ot_a) for team a vs b. a_home: a is the home team."""
    offa, defa = ratings.get(a, (1.0, 1.0))
    offb, defb = ratings.get(b, (1.0, 1.0))
    xa = offa * defb * la
    xb = offb * defa * la
    if a_home:
        xa *= 1.03
    else:
        xb *= 1.03
    # calc_moneyline_prob(pred_away, pred_home) -> home_win, away_win, push
    if a_home:
        m = calc_moneyline_prob(xb, xa); p_a, p_b = m["home_win"], m["away_win"]
    else:
        m = calc_moneyline_prob(xa, xb); p_a, p_b = m["away_win"], m["home_win"]
    ot_share_a = xa / max(xa + xb, 1e-6)
    return p_a, p_b, m["push"], ot_share_a


def winprob(ratings, la, a, b, a_home=True) -> float:
    """Full win prob (incl. OT) for a over b."""
    p_a, p_b, push, ot_a = _game_probs(ratings, la, a, b, a_home)
    return p_a + push * ot_a


def series_prob(p: float) -> float:
    """P(win a best-of-7, first to 4) given per-game win prob p."""
    p = min(max(p, 0.01), 0.99)
    return sum(math.comb(3 + l, l) * (p ** 4) * ((1 - p) ** l) for l in range(4))


# ---------------------------------------------------------------------------
# Season simulation
# ---------------------------------------------------------------------------

def _seed_and_playoffs(points: Dict[str, int]) -> Tuple[List[str], List[str]]:
    """Return (east 8 seeds, west 8 seeds) by NHL format: 3/division + 2 wildcards."""
    out = {}
    for conf in ("Eastern", "Western"):
        divs = NHL_CONFERENCES[conf]
        top3, rest = [], []
        for d in divs:
            ranked = sorted(NHL_DIVISIONS[d], key=lambda t: points[t], reverse=True)
            top3 += ranked[:3]
            rest += ranked[3:]
        wc = sorted(rest, key=lambda t: points[t], reverse=True)[:2]
        seeds = sorted(top3 + wc, key=lambda t: points[t], reverse=True)
        out[conf] = seeds
    return out["Eastern"], out["Western"]


def _sim_bracket(seeds: List[str], sp: Dict[Tuple[str, str], float]) -> str:
    """Re-seeded 1–8 conference bracket → champion (sp = precomputed series probs)."""
    alive = seeds[:]
    while len(alive) > 1:
        n = len(alive)
        nxt = []
        for i in range(n // 2):
            high, low = alive[i], alive[n - 1 - i]
            nxt.append(high if random.random() < sp[(high, low)] else low)
        nxt.sort(key=lambda t: seeds.index(t))
        alive = nxt
    return alive[0]


def _simulate(base_points: Dict[str, int], schedule: List[Tuple[str, str]], ratings, la, n: int) -> dict:
    teams = ALL_TEAMS
    idx = {t: i for i, t in enumerate(teams)}
    sp = {(x, y): series_prob(winprob(ratings, la, x, y, True))
          for x in teams for y in teams if x != y}

    # Vectorized regular-season points: (n_sims × 32).
    pts = np.tile(np.array([base_points[t] for t in teams], dtype=np.int32), (n, 1))
    for (h, a) in schedule:
        ph, pa, _, ot_h = _game_probs(ratings, la, h, a, True)
        hi, ai = idx[h], idx[a]
        r = np.random.random(n)
        home_win = r < ph
        away_win = (r >= ph) & (r < ph + pa)
        ot = ~(home_win | away_win)
        ot_home = ot & (np.random.random(n) < ot_h)
        ot_away = ot & ~ot_home
        pts[home_win | ot_home, hi] += 2
        pts[away_win | ot_away, ai] += 2
        pts[ot_away, hi] += 1
        pts[ot_home, ai] += 1

    made = {t: 0 for t in teams}
    cups = {t: 0 for t in teams}
    pts_sum = pts.sum(axis=0)
    for s in range(n):
        p = {t: int(pts[s, idx[t]]) for t in teams}
        east, west = _seed_and_playoffs(p)
        for t in east + west:
            made[t] += 1
        ec = _sim_bracket(east, sp)
        wc = _sim_bracket(west, sp)
        cups[ec if random.random() < sp[(ec, wc)] else wc] += 1

    return {
        "mode": "season",
        "teams": sorted([{
            "team": t, "division": TEAM_DIV[t], "conference": TEAM_CONF[t],
            "current_points": base_points[t], "proj_points": round(float(pts_sum[idx[t]]) / n, 1),
            "playoff_pct": round(made[t] / n * 100, 1), "cup_pct": round(cups[t] / n * 100, 1),
        } for t in teams], key=lambda x: (-x["playoff_pct"], -x["proj_points"])),
    }


def _mock_season(ratings, la) -> dict:
    """Synthetic mid-season: ~51 GP, points scaled to each team's pace, a balanced
    remaining round-robin (every pair once more)."""
    an = _analyzer()
    base = {}
    for t in ALL_TEAMS:
        st = an.get_team_stats(t) or {}
        final_pts = st.get("points", 92)
        base[t] = int(round(final_pts * 51 / 82))
    schedule = [(ALL_TEAMS[i], ALL_TEAMS[j]) if (i + j) % 2 == 0 else (ALL_TEAMS[j], ALL_TEAMS[i])
                for i in range(len(ALL_TEAMS)) for j in range(i + 1, len(ALL_TEAMS))]
    return _simulate(base, schedule, ratings, la, N_SIMS)


# ---------------------------------------------------------------------------
# Playoff fallback (current postseason)
# ---------------------------------------------------------------------------

def _playoff_mode(ratings, la) -> Optional[dict]:
    """Active playoff series (teams with upcoming games) → Cup % from a best-of-7."""
    try:
        data = requests.get(f"{BASE}/schedule/now", headers=NHL_HEADERS, timeout=12).json()
    except Exception:
        return None
    matchups = {}
    for week in data.get("gameWeek", []):
        for g in week.get("games", []):
            if g.get("gameState") in ("FUT", "PRE", "LIVE", "CRIT"):
                a = g.get("awayTeam", {}).get("abbrev")
                h = g.get("homeTeam", {}).get("abbrev")
                if a and h:
                    matchups[tuple(sorted((a, h)))] = (a, h)
    if not matchups:
        return None
    series, cup = [], {}
    for (a, h) in matchups.values():
        p_h = winprob(ratings, la, h, a, a_home=True)
        sp_h = series_prob(p_h)
        series.append({"away": a, "home": h,
                       "away_pct": round((1 - sp_h) * 100, 1), "home_pct": round(sp_h * 100, 1),
                       "status": "Active series"})
        cup[h] = round(sp_h * 100, 1)
        cup[a] = round((1 - sp_h) * 100, 1)
    return {"mode": "playoffs", "series": series,
            "teams": sorted([{"team": t, "cup_pct": p} for t, p in cup.items()], key=lambda x: -x["cup_pct"])}


def season_sim(mock: bool = False) -> dict:
    key = f"season:{'mock' if mock else 'real'}"
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < _TTL:
        return hit[1]
    ratings, la = _ratings()
    if mock:
        out = _mock_season(ratings, la)
    else:
        out = _playoff_mode(ratings, la) or _mock_season(ratings, la)
    _cache[key] = (time.time(), out)
    return out
