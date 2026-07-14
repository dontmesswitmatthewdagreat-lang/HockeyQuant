"""
League pulses: dial-style reads on league-wide stories for the News tab —
luck (PDO spread), deadline cap liquidity, playoff-race tightness, and
playoff upsets. Each pulse has a seasonal window; outside it the payload is
returned dormant with a note about when it lights up, so the deck never
shuffles cards in and out unannounced.

Shared shape (rendered by one generic iOS card):
    {id, kicker, active, score, label, season, note, explainer,
     sublines: [{label, value, tint}], rows: [{team, title, detail, value, positive}]}
"""

import datetime
import time
from typing import List, Optional

import requests

NHL_HEADERS = {"User-Agent": "HockeyQuant/1.0"}
_cache: dict = {}
_TTL = 3600


def _season_label(today: datetime.date) -> str:
    start = today.year if today.month >= 9 else today.year - 1
    return f"{start}-{(start + 1) % 100:02d}"


def _dormant(pid: str, kicker: str, note: str) -> dict:
    return {"id": pid, "kicker": kicker, "active": False, "score": None,
            "label": None, "season": None, "note": note, "explainer": None,
            "sublines": [], "rows": []}


def _band(score: int, labels: List[str]) -> str:
    """Map a 0-100 score onto five labels (same bands as the market dial)."""
    if score < 20: return labels[0]
    if score < 42: return labels[1]
    if score <= 58: return labels[2]
    if score <= 80: return labels[3]
    return labels[4]


# MARK: - Luck meter (PDO spread, sample-adjusted)

def _alive_playoff_teams(today: datetime.date) -> Optional[set]:
    """Teams still standing in the current playoffs (None if unavailable).
    A team is out once it has lost a completed series."""
    start = today.year - 1
    try:
        data = requests.get(
            f"https://api-web.nhle.com/v1/playoff-series/carousel/{start}{start + 1}/",
            headers=NHL_HEADERS, timeout=15).json()
    except Exception:
        return None
    participants, eliminated = set(), set()
    for rnd in data.get("rounds", []):
        for s in rnd.get("series", []):
            top, bot = s.get("topSeed") or {}, s.get("bottomSeed") or {}
            ta, ba = top.get("abbrev"), bot.get("abbrev")
            if not ta or not ba:
                continue
            participants |= {ta, ba}
            need = int(s.get("neededToWin") or 4)
            tw, bw = int(top.get("wins") or 0), int(bot.get("wins") or 0)
            if tw >= need:
                eliminated.add(ba)
            elif bw >= need:
                eliminated.add(ta)
    return (participants - eliminated) or None


def luck_meter(today: datetime.date) -> dict:
    from services.data_loader import get_data_loader
    loader = get_data_loader()
    loader.load_all_data()
    df = loader.team_data
    rows = []
    for _, t in df[df["situation"] == "all"].iterrows():
        try:
            sog_for = float(t["shotsOnGoalFor"]); sog_ag = float(t["shotsOnGoalAgainst"])
            if sog_for < 100 or sog_ag < 100:
                continue
            sh = float(t["goalsFor"]) / sog_for
            sv = 1.0 - float(t["goalsAgainst"]) / sog_ag
            rows.append({"team": str(t["team"]), "pdo": (sh + sv) * 100,
                         "nf": sog_for, "na": sog_ag,
                         "gf": float(t["goalsFor"]),
                         "over_x": float(t["goalsFor"]) - float(t["xGoalsFor"])})
        except (TypeError, ValueError, ZeroDivisionError, KeyError):
            continue

    # Playoffs: the regular-season luck read, but only for teams still alive —
    # the regression watch that matters for the series being played.
    in_playoffs = today.month in (5, 6) or (today.month == 4 and today.day >= 15)
    playoff_note = None
    if in_playoffs:
        alive = _alive_playoff_teams(today)
        pool = [r for r in rows if r["team"] in alive] if alive else []
        if len(pool) >= 4:
            rows = pool
            playoff_note = f"Playoff survivors only — {len(rows)} teams still alive."
    if len(rows) < (4 if playoff_note else 16):
        return _dormant("luck", "LUCK METER",
                        "Warming up — needs a few weeks of shots to read the bounces.")

    # Sample adjustment: each team's PDO carries binomial noise that dominates
    # early in the season. Subtract the expected sampling variance from the
    # observed spread (dial) and shrink each team toward 100 by how little
    # we've seen of them (rows), so October reads on the same scale as March.
    p = sum(r["gf"] for r in rows) / sum(r["nf"] for r in rows)
    pq = p * (1 - p)
    for r in rows:
        r["noise_var"] = 10000 * pq * (1 / r["nf"] + 1 / r["na"])
    pdos = [r["pdo"] for r in rows]
    mean = sum(pdos) / len(pdos)
    obs_var = sum((v - mean) ** 2 for v in pdos) / len(pdos)
    true_var = max(0.0, obs_var - sum(r["noise_var"] for r in rows) / len(rows))
    corrected_std = true_var ** 0.5
    score = max(2, min(98, int(round(corrected_std * 45))))
    # Floor keeps week-one shrinkage from collapsing every team to exactly 100.
    shrink_var = max(true_var, 0.36)
    for r in rows:
        k = shrink_var / (shrink_var + r["noise_var"])
        r["adj"] = 100 + (r["pdo"] - 100) * k
    rows.sort(key=lambda r: -r["adj"])
    top, bottom = rows[0], rows[-1]
    shown = rows if len(rows) <= 10 else rows[:5] + rows[-5:]

    offseason = today.month in (7, 8, 9)
    season = _season_label(today if not offseason else today.replace(month=1))
    note = playoff_note or (f"Final {season} numbers — resets on opening night." if offseason else None)
    return {
        "id": "luck", "kicker": "LUCK METER", "active": True, "score": score,
        "label": _band(score, ["ALL EARNED", "STEADY", "NORMAL BOUNCES", "BOUNCY", "LUCK-DRIVEN"]),
        "season": season,
        "note": note,
        "explainer": "PDO is shooting% plus save% — over time it gravitates to 100. "
                     "Teams far above are riding hot bounces, teams far below are due "
                     "to cash in. The score is how spread out the league is right now, "
                     "adjusted for sample size so early-season noise doesn't peg the dial.",
        "sublines": [
            {"label": "LUCKIEST", "value": f"{top['team']} · {top['adj']:.1f} PDO", "tint": "hot"},
            {"label": "SNAKEBIT", "value": f"{bottom['team']} · {bottom['adj']:.1f} PDO", "tint": "cold"},
            {"label": "TRUE SPREAD", "value": f"±{corrected_std:.1f}", "tint": None},
        ],
        "rows": [{
            "team": r["team"], "title": r["team"],
            "detail": f"{r['over_x']:+.1f} goals vs expected",
            "value": f"{r['adj']:.1f}", "positive": r["adj"] >= 100,
        } for r in shown],
    }


# MARK: - Deadline pulse (cap liquidity, Jan 1 → mid-March)

def deadline_pulse(today: datetime.date) -> dict:
    if not (today.month in (1, 2) or (today.month == 3 and today.day <= 12)):
        return _dormant("deadline", "DEADLINE PULSE",
                        "Lights up Jan 1 — cap space, buyers and sellers on the road to the deadline.")
    from services.offseason_data import fetch_team_caps
    caps = [c for c in fetch_team_caps() if c.get("cap_space") is not None]
    if len(caps) < 20:
        return _dormant("deadline", "DEADLINE PULSE", "Cap sheets are refreshing — back shortly.")
    caps.sort(key=lambda c: -c["cap_space"])
    total = sum(c["cap_space"] for c in caps)
    buyers = sum(1 for c in caps if c["cap_space"] > 4_000_000)
    pressed = sum(1 for c in caps if c["cap_space"] < 1_000_000)
    score = max(2, min(98, int(round(total / 400_000_000 * 90))))
    return {
        "id": "deadline", "kicker": "DEADLINE PULSE", "active": True, "score": score,
        "label": _band(score, ["FROZEN", "TIGHT", "WORKABLE", "LIQUID", "FLUSH"]),
        "season": _season_label(today), "note": None,
        "explainer": "How much room the league has to make moves: total deadline cap "
                     "space, who can actually add salary, and who is pinned to the ceiling.",
        "sublines": [
            {"label": "LEAGUE SPACE", "value": f"${total / 1e6:,.0f}M", "tint": None},
            {"label": "REAL BUYERS", "value": f"{buyers} teams over $4M", "tint": "cold"},
            {"label": "CAP-STRAPPED", "value": f"{pressed} teams under $1M", "tint": "hot"},
        ],
        "rows": [{
            "team": c["abbrev"], "title": c["abbrev"], "detail": "deadline space",
            "value": f"${c['cap_space'] / 1e6:.1f}M", "positive": True,
        } for c in caps[:6]],
    }


# MARK: - Race tightness (wildcard compression, Nov → regular-season end)

def race_tightness(today: datetime.date) -> dict:
    in_window = today.month in (11, 12, 1, 2, 3) or (today.month == 4 and today.day <= 16)
    if not in_window:
        return _dormant("race", "RACE TIGHTNESS",
                        "Lights up in November — a live read on how tight the wildcard races are.")
    try:
        data = requests.get("https://api-web.nhle.com/v1/standings/now",
                            headers=NHL_HEADERS, timeout=15).json()
        standings = data.get("standings", [])
    except Exception:
        standings = []
    if len(standings) < 30:
        return _dormant("race", "RACE TIGHTNESS", "Standings are refreshing — back shortly.")

    conf: dict = {}
    for s in standings:
        try:
            conf.setdefault(s["conferenceAbbrev"], []).append(
                {"team": s["teamAbbrev"]["default"], "pts": int(s["points"])})
        except (KeyError, TypeError):
            continue

    gaps, sublines, rows = [], [], []
    for abbrev, name in (("E", "EAST"), ("W", "WEST")):
        teams = sorted(conf.get(abbrev, []), key=lambda t: -t["pts"])
        if len(teams) < 11:
            continue
        cut = teams[7]          # second wildcard holds the line
        chasers = teams[8:11]
        gaps += [cut["pts"] - c["pts"] for c in chasers]
        close = sum(1 for c in chasers if cut["pts"] - c["pts"] <= 3)
        sublines.append({"label": name, "value": f"{close} within 3 pts of the line",
                         "tint": "hot" if close >= 2 else None})
        rows.append({"team": cut["team"], "title": cut["team"],
                     "detail": f"{name.title()} — holds the last spot",
                     "value": f"{cut['pts']} PTS", "positive": True})
        rows += [{"team": c["team"], "title": c["team"],
                  "detail": f"chasing, {cut['pts'] - c['pts']} back",
                  "value": f"{c['pts']} PTS", "positive": False} for c in chasers]
    if not gaps:
        return _dormant("race", "RACE TIGHTNESS", "Standings are refreshing — back shortly.")

    avg_gap = sum(gaps) / len(gaps)
    score = max(2, min(98, int(round(95 - avg_gap * 13))))
    return {
        "id": "race", "kicker": "RACE TIGHTNESS", "active": True, "score": score,
        "label": _band(score, ["DECIDED", "DRIFTING", "IN REACH", "TIGHT", "KNIFE-EDGE"]),
        "season": _season_label(today), "note": None,
        "explainer": "How compressed the wildcard races are: the gap between the last "
                     "playoff spot and the teams chasing it, in both conferences.",
        "sublines": sublines + [{"label": "AVG GAP TO THE LINE",
                                 "value": f"{avg_gap:.1f} pts", "tint": None}],
        "rows": rows,
    }


# MARK: - Playoff pulse (series upsets, mid-April → June)

def playoff_pulse(today: datetime.date) -> dict:
    if not (today.month in (5, 6) or (today.month == 4 and today.day >= 15)):
        return _dormant("playoffs", "PLAYOFF PULSE",
                        "Lights up in April — series upsets, comebacks, and sweep watch.")
    start = today.year - 1
    try:
        data = requests.get(
            f"https://api-web.nhle.com/v1/playoff-series/carousel/{start}{start + 1}/",
            headers=NHL_HEADERS, timeout=15).json()
        rounds = data.get("rounds", [])
    except Exception:
        rounds = []
    series = []
    for rnd in rounds:
        for s in rnd.get("series", []):
            top, bot = s.get("topSeed") or {}, s.get("bottomSeed") or {}
            if not top.get("abbrev") or not bot.get("abbrev"):
                continue
            series.append({"round": rnd.get("roundNumber", 0),
                           "top": top["abbrev"], "tw": int(top.get("wins") or 0),
                           "bot": bot["abbrev"], "bw": int(bot.get("wins") or 0)})
    live = [s for s in series if s["tw"] + s["bw"] > 0]
    if not live:
        return _dormant("playoffs", "PLAYOFF PULSE", "The bracket is setting — back at puck drop.")

    upsets = sum(1 for s in live if s["bw"] > s["tw"])
    done_upsets = sum(1 for s in live if s["bw"] >= 4)
    score = max(2, min(98, int(round(upsets / len(live) * 100))))
    latest_round = max(s["round"] for s in live)
    current = [s for s in live if s["round"] == latest_round]
    return {
        "id": "playoffs", "kicker": "PLAYOFF PULSE", "active": True, "score": score,
        "label": _band(score, ["CHALK", "MOSTLY CHALK", "SOME DRAMA", "UPSET-MINDED", "BRACKET CHAOS"]),
        "season": _season_label(today), "note": None,
        "explainer": "How upset-minded the bracket is: the share of series where the "
                     "lower seed is ahead or has already won.",
        "sublines": [
            {"label": "LOWER SEED AHEAD", "value": f"{upsets} of {len(live)} series", "tint": "hot" if upsets else None},
            {"label": "UPSETS COMPLETE", "value": f"{done_upsets}", "tint": None},
            {"label": "ROUND", "value": f"{latest_round}", "tint": None},
        ],
        "rows": [{
            "team": s["top"] if s["tw"] >= s["bw"] else s["bot"],
            "title": f"{s['top']} vs {s['bot']}",
            "detail": "lower seed leads" if s["bw"] > s["tw"]
                      else ("top seed leads" if s["tw"] > s["bw"] else "even"),
            "value": f"{s['tw']}–{s['bw']}", "positive": s["tw"] >= s["bw"],
        } for s in current],
    }


def league_pulses() -> List[dict]:
    entry = _cache.get("pulses")
    if entry and time.time() - entry["ts"] < _TTL:
        return entry["data"]
    today = datetime.date.today()
    pulses = []
    for fn in (luck_meter, race_tightness, deadline_pulse, playoff_pulse):
        try:
            pulses.append(fn(today))
        except Exception:
            continue
    # Live reads lead the deck; dormant cards trail in seasonal order.
    pulses.sort(key=lambda p: not p["active"])
    _cache["pulses"] = {"ts": time.time(), "data": pulses}
    return pulses
