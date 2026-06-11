"""
What-if simulator. Runs the team analysis once per matchup (cached), then applies
the user's overrides (swap starting goalie ↔ backup, nudge fatigue / injuries /
special teams) and re-runs the Poisson goal model — cheap, no network.
"""

import copy
import time
from typing import Dict, Optional, Tuple

from services.analyzer import NHLAnalyzer
from services.goal_predictor import GoalPredictor

_analyzer_singleton: Optional[NHLAnalyzer] = None
_cache: Dict[str, Tuple[float, Tuple[dict, dict]]] = {}
_TTL = 1800  # 30 min


def _analyzer() -> NHLAnalyzer:
    global _analyzer_singleton
    if _analyzer_singleton is None:
        _analyzer_singleton = NHLAnalyzer()
    return _analyzer_singleton


def base_analyses(away: str, home: str) -> Tuple[dict, dict]:
    """The two analyze_team result dicts for a matchup (cached ~30 min)."""
    key = f"{away}-{home}"
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < _TTL:
        return hit[1]
    an = _analyzer()
    away_a = an.analyze_team(away, home, is_away=True)
    home_a = an.analyze_team(home, away, is_away=False)
    _cache[key] = (time.time(), (away_a, home_a))
    return away_a, home_a


def _apply(team: dict, ov: Optional[dict]) -> dict:
    d = copy.deepcopy(team)
    if not ov:
        return d
    if ov.get("goalie") == "backup" and d.get("backup_goalie_gsax") is not None:
        d["goalie_gsax"] = d["backup_goalie_gsax"]
        if d.get("backup_goalie"):
            d["goalie"] = d["backup_goalie"]   # so per-game GSAX uses the backup's games played
    for k in ("fatigue_mult", "injury_mult", "st_mult"):
        if ov.get(k) is not None:
            d[k] = float(ov[k])
    return d


def _factors(d: dict) -> dict:
    bg = d.get("backup_goalie_gsax")
    return {
        "goalie": d.get("goalie"),
        "backup_goalie": d.get("backup_goalie"),
        "goalie_gsax": round(d.get("goalie_gsax", 0.0), 1),
        "backup_goalie_gsax": round(bg, 1) if bg is not None else None,
        "fatigue_mult": round(d.get("fatigue_mult", 1.0), 3),
        "injury_mult": round(d.get("injury_mult", 1.0), 3),
        "st_mult": round(d.get("st_mult", 1.0), 3),
    }


def sim_inputs(a: str, b: str) -> dict:
    """Expected goals for a matchup in BOTH home orientations (for series sims
    with home-ice alternation). Reuses the cached analyses + predict_goals."""
    a_an, b_an = base_analyses(a, b)  # a as away, b as home
    an = _analyzer()
    gp = GoalPredictor(data_loader=an.data_loader, analyzer=an)
    pa = gp.predict_goals(b, a, b_an, a_an)   # A home (away=b, home=a)
    pb = gp.predict_goals(a, b, a_an, b_an)   # B home (away=a, home=b)
    return {
        "a": a, "b": b,
        "a_home": {"a_xg": pa["home_expected_goals"], "b_xg": pa["away_expected_goals"]},
        "b_home": {"a_xg": pb["away_expected_goals"], "b_xg": pb["home_expected_goals"]},
    }


def simulate(away: str, home: str, away_ov: Optional[dict], home_ov: Optional[dict]) -> dict:
    base_away, base_home = base_analyses(away, home)
    away_a = _apply(base_away, away_ov)
    home_a = _apply(base_home, home_ov)

    an = _analyzer()
    gp = GoalPredictor(data_loader=an.data_loader, analyzer=an)
    goal_pred = gp.predict_goals(away, home, away_a, home_a)
    b = an._build_betting_lines(goal_pred, None, home, away)

    return {
        "away_team": away,
        "home_team": home,
        "away_xg": b["away_expected_goals"],
        "home_xg": b["home_expected_goals"],
        "total": b["predicted_total"],
        "margin": b["predicted_margin"],
        "ml_away_prob": b["ml_away_prob"],
        "ml_home_prob": b["ml_home_prob"],
        "puck_line": b["puck_line"],
        "puck_line_home_cover_prob": b["puck_line_home_cover_prob"],
        "over_under": b["over_under"],
        "over_prob": b["over_prob"],
        "under_prob": b["under_prob"],
        "applied": {"away": _factors(away_a), "home": _factors(home_a)},
    }
